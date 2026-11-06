extends SceneTree
## AD-148 lit/unlit run-screen captures (developer capture, not a test: needs a display). Run:
##   xvfb-run -a godot --path . --script res://tests/capture_ad_lighting.gd -- docs/playtests/ad_lighting
## Writes <biome>_<room>_lit.png (lighting high) and _unlit.png (lighting off) for a Ruins combat room, a Cistern
## combat room and both boss rooms, plus telegraph_spells_<lit|unlit>.png (enemy windup while spells fly).
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

## Fresh run.tscn jumped to the first room of `stage` with type `room_type`. Returns false when the route has none.
func _stage(stage: int, room_type: String) -> bool:
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
		if int(flow.rooms[i].get("stage", 0)) == stage and str(flow.rooms[i].get("type", "")) == room_type:
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
	var err := root.get_texture().get_image().save_png(_path("%s_%s" % [name, "lit" if mode == "high" else "unlit"]))
	print("CAPTURE ", name, " ", mode, " ", "ok" if err == OK else "ERR %d" % err)

func _static_room(name: String, stage: int, room_type: String) -> void:
	if not await _stage(stage, room_type):
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

func _run() -> void:
	await _static_room("ruins_combat", 0, "combat")
	await _static_room("cistern_combat", 1, "combat")
	await _static_room("ruins_boss", 0, "boss")
	await _static_room("cistern_boss", 1, "boss")
	await _telegraph_room()
	quit(0)
