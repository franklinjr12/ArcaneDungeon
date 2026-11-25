extends SceneTree
## AD-249 map 1 screenshots (developer capture, not a test: needs a display). Run:
##   xvfb-run -a godot --path . --script res://scripts/capture_ad249_map1.gd -- $TMPDIR/ad249
## Captures the first 3 Ruins combat rooms of the run, the room before the boss-1 room (approach) and the boss-1 room. Output defaults to $TMPDIR/ad249.
var out_dir := ""
var control
var flow
var canvas

func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	out_dir = args[0] if args.size() > 0 else OS.get_environment("TMPDIR") + "/ad249"
	DirAccess.make_dir_recursive_absolute(out_dir)
	root.size = Vector2i(1280, 720)
	call_deferred("_run")

func _enter(room_id: String) -> bool:
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
		if str(flow.rooms[i]["id"]) == room_id:
			flow.run.sequence_index = i
			flow._enter_current()
			control._redraw_panel()
			return true
	return false

func _shot(name: String) -> int:
	canvas.queue_redraw()
	await process_frame
	await RenderingServer.frame_post_draw
	var err := root.get_texture().get_image().save_png("%s/%s.png" % [out_dir, name])
	print("CAPTURE ", name, " ", "ok" if err == OK else "ERR %d" % err)
	return err

func _run() -> void:
	var failed := 0
	var targets: Array = []
	await _enter("ruins_boss")
	var boss_i := int(flow.run.sequence_index)
	for r in flow.rooms:
		if targets.size() < 3 and int(r.get("stage", 0)) == 0 and str(r.get("type", "")) == "combat":
			targets.append(str(r["id"]))
	var approach := str(flow.rooms[boss_i - 1]["id"])
	targets.append(approach)
	targets.append("ruins_boss")
	for rid in targets:
		if not await _enter(str(rid)):
			print("CAPTURE missing room ", rid)
			failed += 1
			continue
		failed += 1 if await _shot(("boss1_approach_" if rid == approach else "") + str(rid)) != OK else 0
	quit(1 if failed > 0 else 0)
