extends RefCounted
## AD-184: F8 feedback snapshot writes screenshot/run log/note under user://reports/.
const FS = preload("res://ui/feedback_snapshot.gd")
const IA = preload("res://ui/input_actions.gd")
const DIR := "user://ad184_test_reports/"

func _rm(path: String) -> void:
	if not DirAccess.dir_exists_absolute(path):
		return
	for d in DirAccess.get_directories_at(path):
		_rm(path.path_join(d))
	for f in DirAccess.get_files_at(path):
		DirAccess.remove_absolute(path.path_join(f))
	DirAccess.remove_absolute(path)

func _folders() -> Array:
	return Array(DirAccess.get_directories_at(DIR)) if DirAccess.dir_exists_absolute(DIR) else []

func _report_event() -> InputEventAction:
	var ev := InputEventAction.new()
	ev.action = "report"
	ev.pressed = true
	return ev

func run(t) -> void:
	IA.reset_to_defaults()
	_rm(DIR)
	FS.dir_override = DIR
	var evs := IA.default_events("report")
	t.check("report" in IA.REBINDABLE and evs.size() == 1 and evs[0].physical_keycode == KEY_F8, "AD-184 report action defaults to F8 and is rebindable")
	var viewport := SubViewport.new()
	viewport.size = Vector2i(1280, 720)
	viewport.disable_3d = true
	(Engine.get_main_loop() as SceneTree).root.add_child(viewport)
	var scene: Node = load("res://scenes/run.tscn").instantiate()
	scene.show_dev_tools = false
	scene.config_path = "res://world/data/vertical_slice_v1.json"
	viewport.add_child(scene)
	var snap = scene.feedback_snapshot

	FS.image_override = Image.create(8, 8, false, Image.FORMAT_RGBA8)
	scene._input(_report_event())
	t.check(snap.is_open() and scene.is_paused(), "AD-184 report action opens popup and pauses")
	snap.confirm("too hard")
	var f := _folders()
	t.equal(f.size(), 1, "AD-184 one report folder written")
	if f.size() == 1:
		var p: String = DIR + f[0]
		var img := Image.load_from_file(ProjectSettings.globalize_path(p + "/screenshot.png"))
		t.check(img != null and not img.is_empty(), "AD-184 screenshot.png loads")
		var parsed = JSON.parse_string(FileAccess.get_file_as_string(p + "/run_log.json"))
		t.check(parsed is Dictionary and int(parsed.get("seed_value", parsed.get("seed", -1))) == scene.flow.run.seed and parsed.get("rooms") is Array, "AD-184 run_log.json has seed and rooms")
		t.equal(FileAccess.get_file_as_string(p + "/note.txt"), "too hard", "AD-184 note.txt content")
	t.check(not scene.is_paused() and not scene.flow.session.sim.clock.paused, "AD-184 unpaused after save")

	scene._input(_report_event())
	snap.cancel()
	t.equal(_folders().size(), 1, "AD-184 cancel writes no folder")
	t.check(not scene.is_paused(), "AD-184 unpaused after cancel")

	var long_note := "a\nb " + "x".repeat(400)
	var path := FS.write_report(null, {"rooms": []}, long_note)
	var note := FileAccess.get_file_as_string(path + "/note.txt")
	t.check(not note.contains("\n") and note.length() <= FS.max_chars() and note.length() > 100, "AD-184 note is one line and capped")
	FS.image_override = null
	t.check(FileAccess.file_exists(path + "/run_log.json") and FileAccess.file_exists(path + "/note.txt") and not FileAccess.file_exists(path + "/screenshot.png"), "AD-184 report without image still writes log and note")
	var p2 := FS.write_report(null, {}, "x")
	t.check(p2 != "" and p2 != path and DirAccess.dir_exists_absolute(p2), "AD-184 same-second reports get separate folders")

	var key := InputEventKey.new()
	key.physical_keycode = KEY_F9
	IA.apply_bindings(IA.rebind_primary(IA.current_bindings(), "report", key))
	t.check(InputMap.event_is_action(key, "report"), "AD-184 rebound key triggers report")
	IA.reset_to_defaults()

	t.check(not FileAccess.get_file_as_string("res://ui/feedback_snapshot.gd").contains("is_debug_build") and not FileAccess.get_file_as_string("res://ui/feedback_snapshot.gd").contains("dev_tools_enabled"), "AD-184 snapshot not debug-gated")
	var cfg := FileAccess.get_file_as_string("res://export_presets.cfg")
	var ok := true
	for line in cfg.split("\n"):
		if line.begins_with("exclude_filter") and (line.contains("ui/") or line.contains("game/")):
			ok = false
	t.check(ok, "AD-184 export filters keep ui/ and game/")

	viewport.queue_free()
	FS.image_override = null
	FS.dir_override = ""
	_rm(DIR)
	IA.reset_to_defaults()
