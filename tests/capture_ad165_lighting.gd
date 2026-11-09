extends SceneTree
## AD-165 lighting capture (developer capture, not a test: needs a display). Run:
##   xvfb-run -a -s '-screen 0 1280x720x24' godot --path . --script res://tests/capture_ad165_lighting.gd -- docs/ui/lighting/before
## Writes <name>_high.png and <name>_off.png for 3 combat rooms per stage (ruins_c1..3, cistern_c1..3), both boss
## rooms, the workshop and telegraph_spells (enemy windup while spells fly).
const Settings = preload("res://game/core/settings.gd")
const SEED := 20261022
var out_dir := "res://docs/playtests/ad_lighting"
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

## Fresh run.tscn jumped to the `nth` (1-based) room of `stage` with type `room_type`. Returns false when missing.
func _stage(stage: int, room_type: String, nth: int = 1) -> bool:
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
	var seen := 0
	for i in flow.rooms.size():
		var r = flow.rooms[i]
		if (stage < 0 or int(r.get("stage", 0)) == stage) and str(r.get("type", "")) == room_type:
			seen += 1
			if seen == nth:
				found = i
				break
	if found < 0:
		return false
	flow.run.sequence_index = found
	flow._enter_current()
	control._redraw_panel()
	settings = Settings.new()
	canvas.settings = settings
	return true

func _tick(command: Dictionary = {}) -> void:
	var actor = flow.session.sim.actor
	actor.health.current = actor.health.maximum
	flow.step(command)
	canvas.queue_redraw()
	await process_frame

func _shot(name: String, mode: String) -> void:
	settings.lighting = mode
	for i in 3:
		canvas.queue_redraw()
		await process_frame
	await RenderingServer.frame_post_draw
	var err := root.get_texture().get_image().save_png(_path("%s_%s" % [name, mode]))
	print("CAPTURE ", name, " ", mode, " ", "ok" if err == OK else "ERR %d" % err)

func _static_room(name: String, stage: int, room_type: String, nth: int = 1) -> void:
	if not await _stage(stage, room_type, nth):
		print("MISSING ROOM ", name)
		return
	for i in 30:
		await _tick({})
	await _shot(name, "high")
	await _shot(name, "off")

## Worst-case spell volley plus an enemy mid-windup, so the telegraph can be judged against the lights.
func _telegraph_room() -> void:
	if not await _stage(1, "combat"):
		return
	var sim = flow.session.sim
	sim.loadout.unlocked = sim.registry.get_ids()
	sim.loadout.allow_edit = true
	sim.equip(1, {"schema_version": 1, "formula_id": "ad148.cap", "display_name": "AD-148 volley",
		"root": {"essence_id": "essence.fire", "manifestation_id": "form.projectile",
			"modifier_ids": ["mod.split", "mod.pierce", "mod.homing"], "params": {}},
		"on_hit": {"trigger_id": "trigger.on_hit", "payload": {"essence_id": "essence.lightning",
			"manifestation_id": "form.burst", "modifier_ids": [], "params": {}}}})
	for e in flow.session.enemies:
		e.target.health.maximum = 1e6
		e.target.health.current = 1e6
	for i in 400:
		sim.mana = float(sim.settings["combat"]["player_max_mana"])
		var foe = null
		for e in flow.session.enemies:
			if e.target.alive():
				foe = e
				if e.state == "windup":
					break
		var cmd := {"move": Vector2.ZERO, "aim": Vector2.RIGHT, "cursor": sim.actor.position + Vector2.RIGHT * 200.0, "cast": 1, "dash": false}
		if foe != null:
			cmd["aim"] = (foe.target.position - sim.actor.position).normalized()
			cmd["cursor"] = foe.target.position
		await _tick(cmd)
		if foe != null and foe.state == "windup" and foe.state_tick >= int(foe.tuning["telegraph_ticks"]) / 2 \
				and canvas.get_node("Lighting").active_spell_lights() > 0:
			break
	await _shot("telegraph_spells", "high")
	await _shot("telegraph_spells", "off")

## The workshop is drawn by test_canvas (ui/sandbox_canvas.gd), not arena_canvas.
func _workshop() -> void:
	if not await _stage(-1, "workshop"):
		print("MISSING ROOM workshop")
		return
	for i in 10:
		await process_frame
	for mode in ["high", "off"]:
		settings.lighting = mode
		for i in 3:
			await process_frame
		await RenderingServer.frame_post_draw
		var err := root.get_texture().get_image().save_png(_path("workshop_%s" % mode))
		print("CAPTURE workshop ", mode, " ", "ok" if err == OK else "ERR %d" % err)

func _run() -> void:
	for n in 3:
		await _static_room("ruins_c%d" % (n + 1), 0, "combat", n + 1)
	for n in 3:
		await _static_room("cistern_c%d" % (n + 1), 1, "combat", n + 1)
	await _static_room("ruins_boss", 0, "boss")
	await _static_room("cistern_boss", 1, "boss")
	await _workshop()
	await _telegraph_room()
	quit(0)
