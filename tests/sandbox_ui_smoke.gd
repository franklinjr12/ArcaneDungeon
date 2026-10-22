extends SceneTree
## End-to-end M1 scene check that exercises actual sandbox controller pathways.
var failures := 0

func _initialize() -> void:
	call_deferred("_run")

func verify(test: bool, description: String) -> void:
	if test:
		print("M1 UI PASS: ",description)
	else:
		failures += 1
		printerr("M1 UI FAIL: ",description)

func _run() -> void:
	var file = load("res://scenes/sandbox.tscn")
	verify(file is PackedScene,"sandbox scene is a PackedScene")
	if not file is PackedScene:
		quit(1)
		return
	var scene = file.instantiate()
	root.add_child(scene)
	current_scene = scene
	await process_frame
	verify(scene.sim != null and scene.sim.initialized,"sandbox simulation initialized on ready")
	if scene.sim == null:
		quit(1)
		return
	verify(scene.samples.size() >= 6,"at least six ready-to-equip formulas")
	verify(scene.surface != null,"interactive canvas exists")
	verify(scene.stats.text.contains("M1 budgets:"),"per-cast and active-effect budgets visible in debug HUD")
	verify(scene.sim.inspect()["targets"].size() >= 7,"stationary and moving dummies spawned")
	# End-to-end Water Burst -> Wet -> Lightning in the same scene/controller.
	scene._select_slot(0)
	scene._equip_sample(6)
	verify(scene.sim.loadout.preview(0)["formula_id"] == "sample.water_burst","sample equip via UI")
	scene._cast_or_inspect(Vector2(365,255),MOUSE_BUTTON_LEFT)
	scene.sim.advance_one_tick()
	for i in 15:
		scene.sim.advance_one_tick()
	scene._cast_or_inspect(Vector2(505,255),MOUSE_BUTTON_LEFT)
	scene.sim.advance_one_tick()
	for i in 15:
		scene.sim.advance_one_tick()
	var one = scene.sim.targets.get_target(2)
	var two = scene.sim.targets.get_target(3)
	verify(one.status.has("wet",scene.sim.clock.tick) and two.status.has("wet",scene.sim.clock.tick),
		"Water Burst casts create Wet on two clustered targets")
	scene._equip_sample(2)
	scene._cast_or_inspect(Vector2(365,255),MOUSE_BUTTON_LEFT)
	for i in 45:
		scene.sim.advance_one_tick()
	verify(scene.sim.trace.filter_records(-1,"sample.lightning_shot","reaction").size() == 1,
		"Lightning hit on Wet target creates bounded arc to second Wet target")
	scene._cast_or_inspect(Vector2(365,255),MOUSE_BUTTON_MIDDLE)
	verify(scene.inspected_id == 2,"middle-click selects and inspects target")
	scene._command("pause")
	verify(scene.sim.clock.paused,"pause button toggles simulation")
	var before_tick: int = scene.sim.clock.tick
	scene._command("step")
	verify(scene.sim.clock.tick == before_tick+1,"single-step button advances paused game")
	scene._command("stress")
	verify(scene.sim.trace.filter_records(-1,"sandbox.stress","budget_exceeded").size() == 1,
		"stress button exposes finite budget")
	scene._command("export")
	verify(FileAccess.file_exists("user://magic_sandbox_trace.json"),"export button saves normalized trace")
	scene._command("reset")
	verify(scene.sim.clock.tick == 0 and scene.sim.trace.snapshot().is_empty(),"reset button restores reproducible baseline")
	quit(1 if failures > 0 else 0)
