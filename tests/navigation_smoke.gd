extends SceneTree
## TASK-001 headless button-to-scene navigation verification.

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	var failures := 0
	var packed = load("res://scenes/main.tscn")
	if not packed is PackedScene:
		printerr("navigation: main scene cannot load")
		quit(1)
		return
	var starting_scene = packed.instantiate()
	root.add_child(starting_scene)
	current_scene = starting_scene
	await process_frame
	if current_scene == null or current_scene.name != "MainMenu":
		printerr("navigation: expected MainMenu")
		quit(1)
		return
	var buttons = current_scene.find_children("*","Button",true,false)
	if buttons.size() != 2:
		printerr("navigation: expected 2 launcher buttons, found ",buttons.size())
		quit(1)
		return
	buttons[0].pressed.emit()
	await process_frame
	if current_scene == null or current_scene.name != "MagicSandbox":
		printerr("navigation: Sandbox button failed")
		failures += 1
	else:
		print("NAVIGATION PASS: Sandbox")
	if current_scene != null and current_scene.name == "MagicSandbox":
		var home = current_scene.find_children("*","Button",true,false)
		home[0].pressed.emit()
		await process_frame
	if current_scene == null or current_scene.name != "MainMenu":
		printerr("navigation: back button failed")
		failures += 1
	else:
		print("NAVIGATION PASS: Back")
	if current_scene != null and current_scene.name == "MainMenu":
		var more_buttons = current_scene.find_children("*","Button",true,false)
		more_buttons[1].pressed.emit()
		await process_frame
	if current_scene == null or current_scene.name != "CombatArena":
		printerr("navigation: Arena button failed")
		failures += 1
	else:
		print("NAVIGATION PASS: Arena")
	quit(1 if failures > 0 else 0)
