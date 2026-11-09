extends SceneTree
# AD-186: run against the exported release build (not registered in run_tests.gd).
# Pass `-- --main-scene=res://...` when hosted as the main scene. Pass `-- --skip-pack` to skip the pack-contents check when run from the project directory.
const Art = preload("res://ui/pixel_art_renderer.gd")
const InputActions = preload("res://ui/input_actions.gd")
var failures: Array = []

func _initialize() -> void:
	call_deferred("_run")

func _fail(reason: String) -> void:
	failures.append(reason)
	print("RELEASE_PROBE FAIL: ", reason)

func _check(ok: bool, reason: String) -> void:
	if not ok:
		_fail(reason)

func _key(code: int) -> InputEventKey:
	var ev := InputEventKey.new()
	ev.keycode = code
	ev.physical_keycode = code
	ev.pressed = true
	return ev

func _action(name: String) -> InputEventAction:
	var ev := InputEventAction.new()
	ev.action = name
	ev.pressed = true
	return ev

func _run() -> void:
	await process_frame
	_check(not OS.is_debug_build(), "OS.is_debug_build() is true")
	_check(OS.has_feature("template_release"), "template_release feature missing")
	_check(not InputActions.debug_keys_enabled(), "InputActions.debug_keys_enabled() is true")
	if not OS.get_cmdline_user_args().has("--skip-pack"):
		for d in ["tests", "docs", "art/source", "art/aseprite", "art/previews", "tools", "scripts"]:
			_check(not DirAccess.dir_exists_absolute("res://" + d), "pack contains res://" + d)
	_check(FileAccess.file_exists("res://art/export/manifest.json"), "art/export/manifest.json missing from pack")
	await _title()
	await _arena()
	await _run_scene()
	if failures.is_empty():
		print("RELEASE_PROBE OK")
	quit(0 if failures.is_empty() else 1)

func _title() -> void:
	var main_scene := str(ProjectSettings.get_setting("application/run/main_scene"))
	for arg in OS.get_cmdline_user_args(): # the export check hosts the probe as main scene and passes the real one
		if arg.begins_with("--main-scene="):
			main_scene = arg.substr(13)
	var title = (load(main_scene) as PackedScene).instantiate()
	root.add_child(title)
	for i in 4:
		await process_frame
	_check(title.find_child("SandboxButton", true, false) == null, "title has SandboxButton")
	_check(title.find_child("ArenaButton", true, false) == null, "title has ArenaButton")
	var version := str(JSON.parse_string(FileAccess.get_file_as_string("res://game/data/demo_v1.json")).get("version", ""))
	var stamp = title.find_child("BuildStamp", true, false)
	_check(stamp != null and not version.is_empty() and stamp.text.contains(version), "BuildStamp lacks version " + version)
	title.free()
	await process_frame

func _arena() -> void:
	var arena = (load("res://scenes/arena.tscn") as PackedScene).instantiate()
	root.add_child(arena)
	await process_frame
	var art: bool = Art.use_art_export
	var scenario = arena.scenario
	for code in [KEY_F3, KEY_F4, KEY_F6, KEY_1, KEY_2, KEY_3]:
		arena._input(_key(code))
	await process_frame
	_check(not arena.session.debug_overlay, "arena F3 toggled debug_overlay")
	_check(not arena.canvas.show_debug, "arena canvas show_debug on")
	_check(Art.use_art_export == art, "arena F6 toggled use_art_export")
	_check(arena.scenario == scenario, "arena 1/2/3 changed scenario")
	arena.free()
	await process_frame

func _run_scene() -> void:
	var run = (load("res://scenes/run.tscn") as PackedScene).instantiate()
	root.add_child(run)
	await process_frame
	_check(not run.dev_tools_enabled(), "run dev_tools_enabled() is true")
	_check(run.dev_panel == null, "run dev_panel exists")
	var art: bool = Art.use_art_export
	for a in ["dev_policy", "dev_overlay", "dev_art_export"]:
		run._input(_action(a))
	run._input(_key(KEY_F3))
	await process_frame
	_check(not run.arena_canvas.show_debug, "run arena_canvas show_debug on")
	_check(Art.use_art_export == art, "run dev_art_export toggled use_art_export")
	run.free()
