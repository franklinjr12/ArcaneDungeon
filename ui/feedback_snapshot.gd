extends Control
## AD-184: F8 feedback snapshot. Writes screenshot + run log + one-line note to user://reports/<stamp>/ only when the
## player asks. Local files only, no network; works in release exports (never gated on debug builds).
const VisualTheme = preload("res://ui/pixel_theme.gd")
const FILE := "res://game/data/demo_v1.json"
const REPORTS_DIR := "user://reports/"
const DEFAULT_MAX_CHARS := 140
## Test-only overrides (dir must stay under user://).
static var dir_override := ""
static var image_override: Image = null
signal closed(saved_path: String)

var _image: Image = null
var _run_log: Dictionary = {}
var _edit: LineEdit

static func max_chars() -> int:
	var file := FileAccess.open(FILE,FileAccess.READ)
	var parsed = JSON.parse_string(file.get_as_text()) if file != null else null
	if parsed is Dictionary:
		var v = parsed.get("report_note_max_chars",DEFAULT_MAX_CHARS)
		if (v is int or v is float) and int(v) > 0:
			return int(v)
	return DEFAULT_MAX_CHARS

static func _dir() -> String:
	var dir := dir_override if not dir_override.is_empty() else REPORTS_DIR
	if not dir.ends_with("/"):
		dir += "/"
	return dir

static func capture(viewport: Viewport) -> Image:
	if image_override != null:
		return image_override
	if DisplayServer.get_name() == "headless" or viewport == null:
		return null
	var tex := viewport.get_texture()
	return tex.get_image() if tex != null else null

static func write_report(image: Image, run_log: Dictionary, note: String) -> String:
	var dir := _dir()
	if not dir.begins_with("user://"):
		return ""
	if DirAccess.make_dir_recursive_absolute(dir) != OK:
		return ""
	var stamp := ""
	for c in Time.get_datetime_string_from_system(true):
		if c >= "0" and c <= "9":
			stamp += c
	var path := dir + stamp
	var n := 0
	while DirAccess.dir_exists_absolute(path):
		n += 1
		path = dir + stamp + "_%d" % n
	if DirAccess.make_dir_recursive_absolute(path) != OK:
		return ""
	if image != null and not image.is_empty():
		image.save_png(path + "/screenshot.png")
	var log_file := FileAccess.open(path + "/run_log.json",FileAccess.WRITE)
	if log_file == null:
		return ""
	log_file.store_string(JSON.stringify(run_log,"\t"))
	log_file.close()
	var line := note.replace("\r"," ").replace("\n"," ").strip_edges().substr(0,max_chars())
	var note_file := FileAccess.open(path + "/note.txt",FileAccess.WRITE)
	if note_file == null:
		return ""
	note_file.store_string(line)
	note_file.close()
	return path

static func reports_dir_path() -> String:
	return ProjectSettings.globalize_path(_dir())

func _ready() -> void:
	VisualTheme.apply(self)
	mouse_filter = Control.MOUSE_FILTER_STOP
	visible = false
	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(center)
	var panel := PanelContainer.new()
	center.add_child(panel)
	var box := VBoxContainer.new()
	panel.add_child(box)
	var title := Label.new()
	title.text = tr("report.title")
	box.add_child(title)
	var prompt := Label.new()
	prompt.text = tr("report.prompt")
	box.add_child(prompt)
	_edit = LineEdit.new()
	_edit.custom_minimum_size = Vector2(360,0)
	_edit.text_submitted.connect(confirm)
	box.add_child(_edit)
	var row := HBoxContainer.new()
	box.add_child(row)
	var save := Button.new()
	save.text = tr("report.save")
	save.pressed.connect(func(): confirm(_edit.text))
	row.add_child(save)
	var cancel_btn := Button.new()
	cancel_btn.text = tr("report.cancel")
	cancel_btn.pressed.connect(cancel)
	row.add_child(cancel_btn)

func open(image: Image, run_log: Dictionary) -> void:
	_image = image
	_run_log = run_log
	_edit.max_length = max_chars()
	_edit.clear()
	visible = true
	_edit.grab_focus()

func is_open() -> bool:
	return visible

func confirm(note: String) -> void:
	if not visible:
		return
	var path := write_report(_image,_run_log,note)
	_close()
	closed.emit(path)

func cancel() -> void:
	if not visible:
		return
	_close()
	closed.emit("")

func _close() -> void:
	visible = false
	_image = null
	_run_log = {}
