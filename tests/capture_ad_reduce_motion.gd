extends SceneTree
## AD-083 OFF/ON reduce-motion screenshots (not a test: needs a display). Run:
##   xvfb-run -a godot --path . --script res://tests/capture_ad_reduce_motion.gd -- docs/playtests/ad_a11y
const Art = preload("res://ui/pixel_art_renderer.gd")
const Flow = preload("res://world/run_flow.gd")
const Driver = preload("res://tests/m3_run_driver.gd")
const Canvas = preload("res://ui/combat_canvas.gd")
const Settings = preload("res://game/core/settings.gd")
const SEED := 20261022
var out_dir := "user://ad083_shots"
var canvas

func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	if args.size() > 0:
		out_dir = args[0]
	DirAccess.make_dir_recursive_absolute(out_dir)
	root.size = Vector2i(1280, 720)
	call_deferred("_run")

func _shot(name: String) -> void:
	canvas.queue_redraw()
	await process_frame
	await RenderingServer.frame_post_draw
	var err := root.get_texture().get_image().save_png("%s/%s.png" % [out_dir, name])
	print("CAPTURE ", name, " ", "ok" if err == OK else "ERR %d" % err)

func _run() -> void:
	var flow = Flow.new(SEED)
	canvas = Canvas.new()
	canvas.size = Vector2(1280, 720)
	canvas.view_rect = Rect2(0, 0, 1280, 720)
	root.add_child(canvas)
	canvas.session = flow.session
	# Fight through the route until an enemy telegraph is live.
	var found := false
	for room_index in 4:
		if room_index == 3:
			flow.run.sequence_index = 3
			flow._enter_current()
		var memo: Dictionary = {}
		for i in 4600:
			if flow.state != "fighting" or found:
				break
			Driver.fight(flow, 1)
			canvas.session = flow.session
			for item in Art.collect_fx(flow.session, flow.session.sim.clock.tick, memo):
				if String(item["event"]).begins_with("telegraph."):
					found = true
		if found:
			break
		if room_index < 3:
			flow.choose_reward(0)
			Driver.reach_exit(flow)
	canvas.session = flow.session
	print("TELEGRAPH ", found)
	flow.session.player.hit_flash = 12
	var off := Settings.new()
	off.reduce_flashes = false
	off.screen_shake = true
	var on := Settings.new()
	on.reduce_flashes = true
	on.screen_shake = false
	canvas.settings = off
	await _shot("reduce_off")
	flow.session.player.hit_flash = 12
	canvas.settings = on
	await _shot("reduce_on")
	quit(0)
