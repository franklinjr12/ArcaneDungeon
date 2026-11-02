extends SceneTree
## AD-089 projectile telegraph screenshots + 10 s sequence (not a test: needs a display). Run:
##   xvfb-run -a godot --path . --resolution 1280x720 --script res://tests/capture_ad_projectile_telegraph.gd -- docs/ui/telegraphs/ad089/after
const Flow = preload("res://world/run_flow.gd")
const Driver = preload("res://tests/m3_run_driver.gd")
const Canvas = preload("res://ui/combat_canvas.gd")
const SEED := 20261022
const SEQUENCE_TICKS := 600
const SEQUENCE_STEP := 30
var out_dir := "user://ad089"

func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	if args.size() > 0:
		out_dir = args[0]
	DirAccess.make_dir_recursive_absolute(out_dir)
	root.size = Vector2i(1280, 720)
	call_deferred("_run")

func _has_adept(flow) -> bool:
	for e in flow.session.enemies:
		if e.kind == "fallen_adept" and e.target.alive():
			return true
	return false

func _adept_shot_in_flight(flow) -> bool:
	for s in flow.session.enemy_shots:
		for e in flow.session.enemies:
			if e.kind == "fallen_adept" and e.target.id == int(s["source_id"]):
				return true
	return false

func _adept_windup(flow) -> bool:
	for e in flow.session.enemies:
		if e.kind == "fallen_adept" and e.state == "windup" and e.target.alive():
			return true
	return false

func _shot(canvas, flow, name: String) -> void:
	canvas.session = flow.session
	canvas.queue_redraw()
	await process_frame
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png("%s/%s.png" % [out_dir, name])
	print("CAPTURE ", name)

func _run() -> void:
	var flow = Flow.new(SEED)
	for room_index in 4:
		if room_index == 3:
			flow.run.sequence_index = 3
			flow._enter_current()
		for i in 4600:
			if flow.state != "fighting" or _has_adept(flow):
				break
			Driver.fight(flow, 1)
		if _has_adept(flow):
			break
		if room_index < 3:
			flow.choose_reward(0)
			Driver.reach_exit(flow)
	if not _has_adept(flow):
		push_error("no fallen_adept found")
		quit(1)
		return
	var canvas := Canvas.new()
	canvas.size = Vector2(1280, 720)
	canvas.session = flow.session
	canvas.environment_id = 0
	canvas.show_debug = false
	root.add_child(canvas)
	await process_frame
	var got_windup := false
	var got_bolt := false
	var seq := 0
	var tick := 0
	while tick < SEQUENCE_TICKS or not (got_windup and got_bolt):
		if tick > SEQUENCE_TICKS + 3000 or flow.state != "fighting":
			break
		if flow.state == "fighting":
			# Idle mage: the scripted driver kills adepts before their bolt flies.
			flow.step({"move": Vector2.ZERO, "aim": Vector2.RIGHT, "cursor": flow.session.sim.actor.position + Vector2.RIGHT * 130, "cast": -1, "dash": false})
		canvas.session = flow.session
		var foe_at := Vector2.ZERO
		for e in flow.session.enemies:
			if e.kind == "fallen_adept":
				foe_at = e.target.position
		canvas.hover = foe_at - canvas.camera_offset()
		if not got_windup and _adept_windup(flow):
			await _shot(canvas, flow, "adept_windup")
			got_windup = true
		if not got_bolt and _adept_shot_in_flight(flow):
			await _shot(canvas, flow, "bolt_in_flight")
			got_bolt = true
		if tick < SEQUENCE_TICKS and tick % SEQUENCE_STEP == 0:
			await _shot(canvas, flow, "seq_%02d" % seq)
			seq += 1
		else:
			canvas.queue_redraw()
			await process_frame
		tick += 1
	print("DONE windup=%s bolt=%s seq=%d" % [got_windup, got_bolt, seq])
	quit(0 if got_windup and got_bolt and seq == 20 else 1)
