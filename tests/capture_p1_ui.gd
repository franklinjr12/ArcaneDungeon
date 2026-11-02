extends SceneTree
## AD-040 PR screenshots (not a test: needs a display). Run:
##   xvfb-run -a /usr/local/bin/godot --path . --script res://tests/capture_p1_ui.gd -- /tmp/ad040_shots
var out_dir := "user://ad040_shots"

func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	if args.size() > 0:
		out_dir = args[0]
	DirAccess.make_dir_recursive_absolute(out_dir)
	root.size = Vector2i(1280, 720)
	call_deferred("_run")

func _shot(name: String) -> void:
	for i in 3:
		await process_frame
	await RenderingServer.frame_post_draw
	var err := root.get_texture().get_image().save_png("%s/%s.png" % [out_dir, name])
	print("CAPTURE ", name, " ", "ok" if err == OK else "ERR %d" % err)

func _run() -> void:
	var control = load("res://scenes/run.tscn").instantiate()
	root.add_child(control)
	current_scene = control
	await process_frame
	var flow = control.flow
	# (a) cast slot 2, then drain mana below a slot cost.
	control.cast_pending = 1
	for i in 12:
		await physics_frame
	flow.session.sim.mana = 1.0
	control._redraw_panel()
	await _shot("hud_cooldown_low_mana")
	# (b) clear the room to show the reward cards.
	flow.session.enemies[0].target.receive_damage(1000, "fire", 1, 100)
	flow.step()
	control._redraw_panel()
	await _shot("reward_pick")
	quit(0)
