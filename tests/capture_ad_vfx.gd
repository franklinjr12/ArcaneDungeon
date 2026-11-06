extends SceneTree
## AD-149 VFX captures (developer capture, not a test: needs a display). Run:
##   xvfb-run -a godot --path . --script res://tests/capture_ad_vfx.gd -- docs/playtests/ad_vfx
## Writes trail_<element>.png (projectile mid-flight) and impact_<element>.png (just after the hit) for fire, water,
## lightning, cold and force in a Ruins combat room, status_<burning|wet|charged|chilled>.png, and
## hit_flash_on.png / hit_flash_reduced.png (player hit with reduce_flashes off / on).
const Settings = preload("res://game/core/settings.gd")
const ELEMENTS := ["fire", "water", "lightning", "cold", "force"]
const STATUSES := ["burning", "wet", "charged", "chilled"]
var out_dir := "res://docs/playtests/ad_vfx"
var control
var flow
var canvas
var settings

func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	if args.size() > 0:
		out_dir = args[0]
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(out_dir))
	root.size = Vector2i(1280, 720)
	call_deferred("_run")

func _path(name: String) -> String:
	return "%s/%s.png" % [ProjectSettings.globalize_path(out_dir), name]

## Fresh run.tscn in the first Ruins combat room, durable enemies, full-effects settings.
func _stage() -> bool:
	if control != null:
		control.queue_free()
		await process_frame
	control = load("res://scenes/run.tscn").instantiate()
	root.add_child(control)
	current_scene = control
	control.set_physics_process(false)
	control._stats_recorded = true
	await process_frame
	flow = control.flow
	canvas = control.arena_canvas
	var found := -1
	for i in flow.rooms.size():
		if int(flow.rooms[i].get("stage", 0)) == 0 and str(flow.rooms[i].get("type", "")) == "combat":
			found = i
			break
	if found < 0:
		return false
	flow.run.sequence_index = found
	flow._enter_current()
	control._redraw_panel()
	settings = Settings.new()
	canvas.settings = settings
	var sim = flow.session.sim
	sim.loadout.unlocked = sim.registry.get_ids()
	sim.loadout.allow_edit = true
	for e in flow.session.enemies:
		e.target.health.maximum = 1e6
		e.target.health.current = 1e6
	return true

func _tick(command: Dictionary = {}) -> void:
	var actor = flow.session.sim.actor
	actor.health.current = actor.health.maximum
	flow.step(command)
	canvas.queue_redraw()
	await process_frame

func _shot(name: String) -> void:
	for i in 2:
		canvas.queue_redraw()
		await process_frame
	await RenderingServer.frame_post_draw
	var err := root.get_texture().get_image().save_png(_path(name))
	print("CAPTURE ", name, " ", "ok" if err == OK else "ERR %d" % err)

func _damaged() -> bool:
	for e in flow.session.enemies:
		if e.target.health.current < 1e6:
			return true
	return false

func _foe():
	for e in flow.session.enemies:
		if e.target.alive():
			return e
	return null

func _element(element: String) -> void:
	if not await _stage():
		print("MISSING ROOM")
		return
	var sim = flow.session.sim
	sim.equip(1, {"schema_version": 1, "formula_id": "ad149.%s" % element, "display_name": "AD-149 %s" % element,
		"root": {"essence_id": "essence.%s" % element, "manifestation_id": "form.projectile", "modifier_ids": [], "params": {}}})
	var trail_done := false
	for i in 600:
		sim.mana = float(sim.settings["combat"]["player_max_mana"])
		var foe = _foe()
		var cmd := {"move": Vector2.ZERO, "aim": Vector2.RIGHT, "cursor": sim.actor.position + Vector2.RIGHT * 200.0, "cast": 1, "dash": false}
		if foe != null:
			cmd["aim"] = (foe.target.position - sim.actor.position).normalized()
			cmd["cursor"] = foe.target.position
		await _tick(cmd)
		if foe == null:
			break
		if not trail_done and canvas.get_node("Vfx").active_count() > 12 and canvas.get_node("Vfx").glow_count() > 0 \
				and foe.target.position.distance_to(sim.actor.position) > 120.0 and not _damaged():
			trail_done = true
			await _shot("trail_%s" % element)
		if trail_done and _damaged():
			await _tick({})
			await _shot("impact_%s" % element)
			return
	print("INCOMPLETE ", element, " trail=", trail_done)

func _statuses() -> void:
	if not await _stage():
		return
	var sim = flow.session.sim
	var defs: Dictionary = sim.settings["statuses"]
	var foes: Array = []
	for e in flow.session.enemies:
		foes.append(e)
	for i in STATUSES.size():
		if i >= foes.size():
			break
		foes[i].target.status.apply(STATUSES[i], sim.clock.tick, defs[STATUSES[i]], {"source_id": sim.actor.id})
	for i in 24:
		await _tick({})
	await _shot("status_all")
	for s in STATUSES:
		await _stage()
		sim = flow.session.sim
		defs = sim.settings["statuses"]
		for e in flow.session.enemies:
			e.target.status.apply(s, sim.clock.tick, defs[s], {"source_id": sim.actor.id})
		for i in 24:
			await _tick({})
		await _shot("status_%s" % s)

func _flash(reduced: bool) -> void:
	if not await _stage():
		return
	settings.reduce_flashes = reduced
	for i in 10:
		await _tick({})
	var p = flow.session.player
	p.hit_flash = int(p.tuning["hit_flash_ticks"])
	canvas.queue_redraw()
	await process_frame
	await _shot("hit_flash_reduced" if reduced else "hit_flash_on")

func _run() -> void:
	var only := OS.get_cmdline_user_args()
	var which: Array = ELEMENTS if only.size() < 2 else [only[1]]
	for el in which:
		await _element(el)
	if only.size() < 2:
		await _statuses()
		await _flash(false)
		await _flash(true)
	quit(0)
