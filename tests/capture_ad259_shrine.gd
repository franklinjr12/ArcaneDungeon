extends SceneTree
## AD-259 shrine capture (developer capture, not a test: needs a display). Run:
##   xvfb-run -a -s '-screen 0 1280x720x24' /usr/local/bin/godot --path . --script res://tests/capture_ad259_shrine.gd -- /tmp/ad259_shrine
## Writes shrine_<stop>.png into the given directory (default user://ad259_shrine, resolved to the OS path; keep it outside the repo).
## Stops: altar, statue, idol (mage stood next to each object, in-world interact prompt visible), and room (whole workshop).
## The script only drives the real run.tscn flow through the seeded route to the first between-floor workshop. Upload to Drive is manual.
const SEED := 20261022
const SETTLE_FRAMES := 4
var out_dir := "user://ad259_shrine"
var control
var flow
var failed := false

func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	if args.size() > 0:
		out_dir = args[0]
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(out_dir) if out_dir.begins_with("user://") else out_dir)
	root.size = Vector2i(1280, 720)
	call_deferred("_run")

func _path(name: String) -> String:
	var base := out_dir
	if base.begins_with("user://"):
		base = ProjectSettings.globalize_path(base)
	return "%s/%s.png" % [base, name]

func _shoot(name: String) -> void:
	control._sync_shrine_canvas()
	control.test_canvas.queue_redraw()
	for i in SETTLE_FRAMES:
		await process_frame
	await RenderingServer.frame_post_draw
	var err := root.get_texture().get_image().save_png(_path(name))
	print("CAPTURE ", name, " ", "ok" if err == OK else "ERR %d" % err)
	if err != OK:
		failed = true

## Fights every encounter with the flow's own step() until the workshop is reached (same route as the AD-259 tests).
func _to_workshop() -> bool:
	for guard in 80:
		if flow.state == "fighting":
			for i in 3000:
				if flow.state != "fighting":
					break
				for enemy in flow.session.enemies:
					if enemy.target.alive():
						enemy.target.receive_damage(100000, "fire", 1, 100)
				flow.step()
		if flow.state == "workshop" and not flow.prelude:
			return true
		if flow.state == "won" or flow.state == "dead":
			return false
		if flow.state == "cleared" and not flow.reward_collected and flow.room.values["type"] != "boss":
			flow.choose_reward(0)
		var pos: Vector2 = flow.room.marker("exit")
		flow.session.sim.actor.position = pos
		flow.try_exit(pos, true)
	return false

func _run() -> void:
	control = load("res://scenes/run.tscn").instantiate()
	root.add_child(control)
	current_scene = control
	control.set_physics_process(false)
	control._stats_recorded = true
	await process_frame
	flow = control.flow
	if not _to_workshop():
		print("CAPTURE FAILED: could not reach the first workshop on seed ", SEED)
		quit(1)
		return
	var objects: Dictionary = {}
	for obj in flow.shrine_objects():
		objects[str(obj["id"])] = obj
	for stop in ["altar", "statue", "idol"]:
		if not objects.has(stop):
			print("CAPTURE FAILED: shrine object missing: ", stop)
			failed = true
			continue
		# Stand just inside the interact radius so the in-world prompt is drawn for this object.
		flow.range_sim.actor.position = objects[stop]["position"] + Vector2(0, 40)
		await _shoot("shrine_%s" % stop)
	# Whole room: the mage stands between altar and statue.
	flow.range_sim.actor.position = (objects["altar"]["position"] + objects["statue"]["position"]) * 0.5 + Vector2(0, 80)
	await _shoot("shrine_room")
	quit(1 if failed else 0)
