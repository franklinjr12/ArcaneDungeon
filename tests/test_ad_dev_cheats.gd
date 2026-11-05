extends RefCounted
## Dev-panel cheats (debug builds only): kill all, skip room, jump to next stage.

func run(t) -> void:
	var root := (Engine.get_main_loop() as SceneTree).root
	var viewport := SubViewport.new()
	viewport.size = Vector2i(1280,720)
	viewport.disable_3d = true
	root.add_child(viewport)
	var scene: Node = load("res://scenes/run.tscn").instantiate()
	scene.show_dev_tools = true
	viewport.add_child(scene)
	t.check(scene.dev_tools_enabled(),"DEV cheats enabled in debug build")
	var flow = scene.flow
	if flow.prelude:
		scene._dev_skip_room()
	t.check(not flow.prelude,"DEV skip room leaves the Sigil Desk")
	t.equal(flow.state,"fighting","DEV first room is combat")
	scene._dev_kill_all()
	t.equal(flow.state,"cleared","DEV kill all clears the room")
	var index: int = flow.run.sequence_index
	scene._dev_skip_room()
	t.check(flow.run.sequence_index > index,"DEV skip room advances the sequence")
	scene._dev_next_stage()
	t.equal(int(flow.room.values.get("stage",0)),1,"DEV next stage reaches stage 2")
	t.check(flow.state not in ["dead","error"],"DEV next stage keeps the run alive")
	viewport.queue_free()
