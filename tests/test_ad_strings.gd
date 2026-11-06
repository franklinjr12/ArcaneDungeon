extends RefCounted
## AD-124: localization audit. Player-facing text in ui/*.gd must go through tr() keys from i18n/strings_en.csv.
const CSV := "res://i18n/strings_en.csv"
const FLAVOUR := "res://world/data/flavour_v1.json"
const EXEMPT_MARKERS := ["TranslationServer.translate", "preload(", "load(", "res://", "push_error", "push_warning", "print", "assert", "get_node", "find_child", "has_method", "call(", "connect(", "Input.", "InputMap", ".name =", "get_environment"]
## Debug-overlay text and unavoidable internal identifiers (file -> exact literals).
const ALLOW := {
	"ui/run_controller.gd": [
		"Render FPS %.0f / observed low %.0f\\nEdit policy: %s", # F2/dev panel overlay
		"\\nWaves scheduled: ", # dev panel overlay
		"\\nTrace: %d reactions, %d triggers, %d budget warnings", # dev panel overlay
	],
	"ui/combat_arena_controller.gd": [
		"State: %s\\nCast: %s\\nElement: %s\\nDamage taken: %.1f\\nDashes %d | Casts %d\\nFPS %d | Logic %.2fms\\n%s", # F3 debug status overlay
	],
	"ui/combat_canvas.gd": ["DEFEAT"], # prefix compared against sim feedback labels, never displayed
	"ui/room_placeholder.gd": ["MagicSandbox"], # scene node name comparison
	"ui/main_menu.gd": ["NewRunButton", "CompendiumButton", "ContinueButton", "SettingsButton", "QuitButton"], # node name
	"ui/pause_menu.gd": ["ResumeButton", "SettingsButton", "ControlsButton", "TipsButton", "RetryButton", "QuitButton", "SaveQuitButton", "ConfirmButton", "CancelButton", "ControlsBackButton"], # node names
	"ui/pixel_theme.gd": ["PanelContainer", "Button", "Label", "LineEdit", "OptionButton", "CheckBox", "TabBar", "TabContainer", "HSlider", "CheckButton", "VScrollBar"], # Godot theme type names
}

func run(t) -> void:
	var keys := _load_csv(t)
	_scan_ui(t, keys)
	_check_flavour(t, keys)
	t.equal(TranslationServer.translate("menu.title"), "ARCANE DUNGEON", "AD-124 translation loaded")

func _load_csv(t) -> Dictionary:
	var keys := {}
	var f := FileAccess.open(CSV, FileAccess.READ)
	t.check(f != null, "AD-124 csv opens")
	if f == null:
		return keys
	var header := f.get_csv_line()
	t.equal(header, PackedStringArray(["keys", "en"]), "AD-124 csv header")
	while not f.eof_reached():
		var row := f.get_csv_line()
		if row.size() == 1 and row[0] == "":
			continue
		var k := row[0]
		t.check(k != "", "AD-124 csv empty key")
		t.check(not keys.has(k), "AD-124 csv duplicate key: " + k)
		t.check(row.size() >= 2 and row[1] != "", "AD-124 csv empty value: " + k)
		keys[k] = row[1] if row.size() >= 2 else ""
	return keys

func _scan_ui(t, keys: Dictionary) -> void:
	var lit := RegEx.new()
	lit.compile('"((?:[^"\\\\]|\\\\.)*)"')
	var letters := RegEx.new()
	letters.compile("[A-Za-z]{2,}")
	var tr_call := RegEx.new()
	tr_call.compile("(?<![A-Za-z0-9_.])tr\\(")
	var keyuse := RegEx.new()
	keyuse.compile('(?:\\btr|TranslationServer\\.translate)\\(\\s*"([^"]*)"')
	var files := DirAccess.get_files_at("res://ui")
	files.sort()
	for fn in files:
		if not fn.ends_with(".gd"):
			continue
		var rel := "ui/" + fn
		var allowed: Array = ALLOW.get(rel, [])
		var lines := FileAccess.get_file_as_string("res://" + rel).split("\n")
		for i in lines.size():
			var line: String = lines[i]
			if line.strip_edges().begins_with("#"):
				continue
			for m in keyuse.search_all(line):
				var key := m.get_string(1)
				if key.ends_with("."):
					continue # dynamic key prefix
				t.check(keys.has(key), "AD-124 tr key missing from csv: %s:%d %s" % [rel, i + 1, key])
			var exempt := tr_call.search(line) != null
			for marker in EXEMPT_MARKERS:
				if line.contains(marker):
					exempt = true
					break
			if exempt:
				continue
			for m in lit.search_all(line):
				var s := m.get_string(1)
				if letters.search(s) == null:
					continue
				if not (s.contains(" ") or (s.unicode_at(0) >= 65 and s.unicode_at(0) <= 90)):
					continue
				if line.substr(m.get_end(), 1) == ":" or allowed.has(s):
					continue
				t.check(false, "AD-124 hard-coded player-facing literal: %s:%d %s" % [rel, i + 1, s])

func _check_flavour(t, keys: Dictionary) -> void:
	var data = JSON.parse_string(FileAccess.get_file_as_string(FLAVOUR))
	t.check(data is Dictionary, "AD-124 flavour parses")
	var leaves: Array = []
	_leaves(data, "", leaves)
	for pair in leaves:
		if pair[0] == "schema_version":
			continue
		t.check(keys.has(pair[1]), "AD-124 flavour leaf is csv key: %s = %s" % [pair[0], pair[1]])
		t.check(not str(pair[1]).contains(" "), "AD-124 flavour leaf not English: " + str(pair[1]))

func _leaves(v, path: String, out: Array) -> void:
	if v is Dictionary:
		for k in v:
			_leaves(v[k], str(k) if path == "" else path + "." + str(k), out)
	elif v is Array:
		for i in v.size():
			_leaves(v[i], path + "[%d]" % i, out)
	elif v is String:
		out.append([path, v])
