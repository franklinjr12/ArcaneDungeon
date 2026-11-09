extends Control
## AD-189: Credits screen (main menu). Skin A chrome reused from the compendium layout; text comes from game/data/credits_v1.json.
## The owner listens to back_requested; this screen never frees itself.
const VisualTheme = preload("res://ui/pixel_theme.gd")
const SkinA = preload("res://ui/skin_a.gd")
const SettingsScreen = preload("res://ui/settings_screen.gd")
const DATA_PATH := "res://game/data/credits_v1.json"
const CHROME_LAYOUT := "compendium_runes"
const TEXT := {
	"title": "credits.title",
	"back": "credits.back",
	"unavailable": "credits.unavailable",
}
signal back_requested

var back_button: Button
var scroll: ScrollContainer
## One Label per section title, in file order.
var section_labels: Array = []
var _layout := {}
var _items: Array = []  # {c, w}
var _backdrop: SettingsScreen.SkinBox
var _list: VBoxContainer
var _texts: Array = []  # labels sized by font only

## Sections [{title_key, entries: [{name, detail}]}]; [] on a missing or invalid file (silent, no engine error).
static func load_sections(path := DATA_PATH) -> Array:
	if not FileAccess.file_exists(path):
		return []
	var parsed = JSON.parse_string(FileAccess.get_file_as_string(path))
	if not parsed is Dictionary or int(parsed.get("schema_version", 0)) != 1 or not parsed.get("sections") is Array:
		return []
	var out := []
	for s in parsed["sections"]:
		if not s is Dictionary or not s.get("title_key") is String or not s.get("entries") is Array:
			return []
		var entries := []
		for e in s["entries"]:
			if not e is Dictionary or not e.get("name") is String:
				return []
			entries.append({"name": e["name"], "detail": str(e.get("detail", ""))})
		out.append({"title_key": s["title_key"], "entries": entries})
	return out

func _ready() -> void:
	VisualTheme.apply(self)
	_layout = SkinA.widgets_by_id(CHROME_LAYOUT)
	_backdrop = SettingsScreen.SkinBox.new("ad_ui_modal_backdrop_75", true)
	add_child(_backdrop)
	_build_chrome()
	_build_list()
	get_viewport().size_changed.connect(_relayout)
	visibility_changed.connect(_focus_first)
	_relayout()
	_focus_first()

func _w(id: String) -> Dictionary:
	return _layout.get(id, {"x": 0, "y": 0, "w": 0, "h": 0})

func _reg(c: Control, parent: Node, rect: Dictionary) -> Control:
	parent.add_child(c)
	_items.append({"c": c, "w": rect})
	return c

func _build_chrome() -> void:
	_reg(SettingsScreen.SkinBox.new("ad_ui_panel_large", false), self, _w("panel"))
	_reg(SettingsScreen.SkinBox.new("ad_ui_header", false), self, _w("title_header"))
	var title := Label.new()
	title.text = tr(TEXT["title"])
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	title.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_reg(title, self, _w("title_header"))
	_reg(SettingsScreen.SkinBox.new("ad_ui_panel_inset", false), self, _w("content"))
	scroll = ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_reg(scroll, self, _w("content"))
	back_button = SettingsScreen.SkinButton.new()
	back_button.text = tr(TEXT["back"])
	back_button.focus_mode = Control.FOCUS_ALL
	_reg(back_button, self, _w("btn_back"))
	var director = get_node_or_null("/root/AudioDirector")
	if director != null:
		director.bind_button(back_button)
	back_button.pressed.connect(func(): back_requested.emit())

func _build_list() -> void:
	_list = VBoxContainer.new()
	_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(_list)
	var sections := load_sections()
	if sections.is_empty():
		_list.add_child(_line(tr(TEXT["unavailable"])))
		return
	for s in sections:
		var head := _line(tr(s["title_key"]))
		head.add_theme_color_override("font_color", SkinA.label_color("focus"))
		_list.add_child(head)
		section_labels.append(head)
		for e in s["entries"]:
			_list.add_child(_line("%s - %s" % [e["name"], e["detail"]] if e["detail"] != "" else e["name"]))

func _line(text: String) -> Label:
	var l := Label.new()
	l.text = text
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_texts.append(l)
	return l

func _relayout() -> void:
	if _items.is_empty() or not is_inside_tree():
		return
	var vp := get_viewport_rect().size
	var sc := SkinA.canvas_scale(vp)
	var origin := SkinA.canvas_origin(vp, sc)
	var fs := maxi(14, int(7.0 * sc))
	_backdrop.position = Vector2.ZERO
	_backdrop.size = vp
	_backdrop.set_skin_scale(sc)
	for it in _items:
		var c: Control = it["c"]
		SkinA.place(c, it["w"], sc, origin)
		if c.has_method("set_skin_scale"):
			c.set_skin_scale(sc)
		if c is Label or c is Button:
			c.add_theme_font_size_override("font_size", fs)
	var pad := 4.0 * sc
	scroll.position += Vector2(pad, pad)
	scroll.size -= Vector2(pad, pad) * 2.0
	_list.custom_minimum_size.x = scroll.size.x - 8.0
	for l in _texts:
		l.add_theme_font_size_override("font_size", fs)

func _focus_first() -> void:
	if is_visible_in_tree() and back_button != null:
		back_button.grab_focus()

func _unhandled_input(event: InputEvent) -> void:
	if not visible:
		return
	if event.is_action_pressed("ui_cancel"):
		back_requested.emit()
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("ui_down") or event.is_action_pressed("ui_up"):
		var step := int(scroll.size.y * 0.25)
		scroll.scroll_vertical += step if event.is_action_pressed("ui_down") else -step
		get_viewport().set_input_as_handled()
