extends RefCounted
## AD-189: credits data, Credits screen and main menu entry.
const Screen = preload("res://ui/credits_screen.gd")
const PATH := "res://game/data/credits_v1.json"

func run(t) -> void:
	var data = JSON.parse_string(FileAccess.get_file_as_string(PATH))
	t.check(data is Dictionary and int(data.get("schema_version", 0)) == 1, "AD-189 credits schema_version 1")
	var sections: Array = data["sections"] if data is Dictionary else []
	t.check(not sections.is_empty(), "AD-189 credits sections non-empty")
	var names := []
	for s in sections:
		t.check(tr(s["title_key"]) != s["title_key"], "AD-189 credits title key translated: %s" % s["title_key"])
		for e in s["entries"]:
			names.append(e["name"])
	t.check("Franklin / Arcane Studio" in names, "AD-189 credits lists Franklin / Arcane Studio")
	t.equal(Screen.load_sections("res://game/data/__missing_credits__.json"), [], "AD-189 load_sections missing file is empty")
	t.equal(Screen.load_sections(PATH).size(), sections.size(), "AD-189 load_sections reads the data file")
	var root = (Engine.get_main_loop() as SceneTree).root
	var screen = Screen.new()
	root.add_child(screen)
	t.equal(screen.section_labels.size(), sections.size(), "AD-189 one label per section")
	var hits := []
	screen.back_requested.connect(func(): hits.append(1))
	screen.back_button.pressed.emit()
	t.equal(hits.size(), 1, "AD-189 credits back emits back_requested")
	screen.free()
	var menu = load("res://scenes/main.tscn").instantiate()
	menu.show_debug_entries = false
	root.add_child(menu)
	var btn = menu.find_child("CreditsButton", true, false)
	t.check(btn != null, "AD-189 CreditsButton exists")
	if btn != null:
		btn.pressed.emit()
		t.check(menu.credits_screen != null and menu.credits_screen.visible and not menu.panel.visible, "AD-189 button opens credits")
		menu.credits_screen.back_requested.emit()
		t.check(menu.panel.visible and not menu.credits_screen.visible, "AD-189 back restores title")
	menu.free()
