extends SceneTree
## AD-261 cistern water captures (developer capture, not a test: needs a rendering display). Run:
##   xvfb-run -a -s '-screen 0 1920x1080x24' /usr/local/bin/godot --path . --script res://tests/capture_ad261_water.gd -- user://ad261_captures
## Writes <room>_<state>_720p.png and _1080p.png for the cistern combat room and the boss arena, with states normal,
## frozen (freeze_circle over every pool) and electrified (electrify_all). The headless driver cannot render real output.
const Art = preload("res://ui/pixel_art_renderer.gd")
const ROOMS := {"cistern_pool": ["combat", 1], "boss_arena": ["boss", 1]}
const SIZES := {"720p": Vector2i(1280, 720), "1080p": Vector2i(1920, 1080)}
var out_dir := "user://ad261_captures"
var control
var flow
var canvas
var saved: Dictionary = {}

func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	if args.size() > 0:
		out_dir = args[0]
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(out_dir))
	root.size = SIZES["720p"]
	call_deferred("_run")

func _path(name: String) -> String:
	return "%s/%s.png" % [ProjectSettings.globalize_path(out_dir), name]

func _tick() -> void:
	var actor = flow.session.sim.actor
	actor.health.current = actor.health.maximum
	flow.step({})
	canvas.queue_redraw()
	await process_frame

## Fresh run.tscn jumped to the first room of `room_type` in stage 1. Returns false when missing.
func _stage(room_type: String) -> bool:
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
	for i in flow.rooms.size():
		var r = flow.rooms[i]
		if int(r.get("stage", 0)) == 1 and str(r.get("type", "")) == room_type:
			flow.run.sequence_index = i
			flow._enter_current()
			Art.use_art_export = true
			control._redraw_panel()
			return flow.session.water != null
	return false

func _shot(name: String) -> void:
	for label in SIZES:
		root.size = SIZES[label]
		for i in 3:
			canvas.queue_redraw()
			await process_frame
		await RenderingServer.frame_post_draw
		var file := "%s_%s" % [name, label]
		var err := root.get_texture().get_image().save_png(_path(file))
		saved[file] = err == OK
		print("CAPTURE ", file, " ", "ok" if err == OK else "ERR %d" % err)
	root.size = SIZES["720p"]

func _run() -> void:
	for room in ROOMS:
		if not await _stage(ROOMS[room][0]):
			print("MISSING ROOM OR WATER ", room)
			continue
		var water = flow.session.water
		var tick: int = flow.session.sim.clock.tick
		for i in 30:
			await _tick()
		await _shot("%s_normal" % room)
		for item in water.view():
			var r: Rect2 = item["rect"] if item["rect"] is Rect2 else Rect2(item["rect"][0], item["rect"][1], item["rect"][2], item["rect"][3])
			water.freeze_circle(r.get_center(), maxf(r.size.x, r.size.y), tick + 100000)
		await _tick()
		await _shot("%s_frozen" % room)
		water.clear_states()
		water.electrify_all(flow.session.sim.clock.tick + 100000)
		for i in 10:
			await _tick()
		await _shot("%s_electrified" % room)
	print("CAPTURED: ", saved.keys())
	quit(0)
