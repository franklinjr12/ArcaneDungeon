extends Control
## AD-068: modal pause overlay (GDD §8). The owner (run controller) shows/hides it and reacts to the
## signals; this menu never frees itself. AD-152: skin A layout (ad_ui_screen_pause_layout.json).
const VisualTheme = preload("res://ui/pixel_theme.gd")
const SkinA = preload("res://ui/skin_a.gd")
const SettingsScreen = preload("res://ui/settings_screen.gd")
const FeedbackSnapshot = preload("res://ui/feedback_snapshot.gd")
const TEXT := {
	"title": "pause.title",
	"resume": "pause.resume",
	"loadout": "pause.loadout",
	"controls": "pause.controls",
	"settings": "pause.settings",
	"retry": "pause.retry",
	"abandon": "pause.abandon",
	"save_quit": "pause.save_quit",
	"save_quit_prompt": "pause.save_quit_prompt",
	"tips_hide": "pause.tips_hide",
	"tips_show": "pause.tips_show",
	"confirm": "pause.confirm",
	"cancel": "pause.cancel",
	"retry_prompt": "pause.retry_prompt",
	"quit_prompt": "pause.quit_prompt",
	"hint": "pause.hint",
	"open_reports": "pause.open_reports",
}
const BUTTON_IDS := {"btn_resume": "ResumeButton", "btn_loadout": "LoadoutButton", "btn_controls": "ControlsButton", "btn_settings": "SettingsButton", "btn_save_quit": "SaveQuitButton", "btn_open_reports": "OpenReportsButton", "btn_abandon": "QuitButton"}
signal resume_requested
signal loadout_requested
signal retry_confirmed
signal quit_confirmed
signal save_quit_confirmed
signal tips_toggled

var panel: Control
var confirm_box: Control
var confirm_label: Label
var backdrop: TextureRect
var title_label: Label
var run_info_label: Label
var hint_label: Label
var resume_button: Button
var loadout_button: Button
var controls_button: Button
var settings_button: Button
var quit_button: Button
var save_quit_button: Button
var open_reports_button: Button
var confirm_button: Button
var cancel_button: Button
var settings_screen = null
var _pending := ""
var _opened_from_controls := false
var _tips_on := true
var _buttons: Dictionary = {}  # layout id -> Button
var _widgets: Dictionary = {}  # layout id -> widget rect
var _chrome: Array = []  # [Control, layout id]
var _confirm_panel: PanelContainer
var _confirm_frame: Panel

func _ready() -> void:
	VisualTheme.apply(self)
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	for w in SkinA.layout("pause").get("widgets", []):
		_widgets[w.get("id", "")] = w
	backdrop = TextureRect.new()
	backdrop.name = "Backdrop"
	backdrop.texture = SkinA.region(_widgets.get("modal_backdrop", {}).get("sprite", "ad_ui_modal_backdrop_50"))
	backdrop.stretch_mode = TextureRect.STRETCH_TILE
	backdrop.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	backdrop.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(backdrop)
	panel = Control.new()
	panel.name = "PausePanel"
	panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(panel)
	var director = get_node_or_null("/root/AudioDirector")
	var frame := Panel.new()
	frame.add_theme_stylebox_override("panel", SkinA.stylebox("ad_ui_panel_large"))
	_add_chrome(frame, "panel")
	_sprite(SkinA.region("ad_ui_header"), "title_header")
	_sprite(SkinA.region("ad_ui_divider_h"), "div_1")
	title_label = _text("title", tr(TEXT["title"]), "selected")
	run_info_label = _text("run_info", "", "normal")
	hint_label = _text("hint", tr(TEXT["hint"]), "disabled")
	resume_button = _button(panel, "ResumeButton", tr(TEXT["resume"]), director, func(): resume_requested.emit())
	loadout_button = _button(panel, "LoadoutButton", tr(TEXT["loadout"]), director, func(): loadout_requested.emit())
	controls_button = _button(panel, "ControlsButton", tr(TEXT["controls"]), director, func(): open_controls())
	settings_button = _button(panel, "SettingsButton", tr(TEXT["settings"]), director, func(): open_settings())
	save_quit_button = _button(panel, "SaveQuitButton", tr(TEXT["save_quit"]), director, func(): request_save_quit())
	save_quit_button.visible = false
	open_reports_button = _button(panel, "OpenReportsButton", tr(TEXT["open_reports"]), director, func(): open_reports_folder())
	quit_button = _button(panel, "QuitButton", tr(TEXT["abandon"]), director, func(): request_quit())
	_buttons = {"btn_resume": resume_button, "btn_loadout": loadout_button, "btn_controls": controls_button, "btn_settings": settings_button, "btn_save_quit": save_quit_button, "btn_open_reports": open_reports_button, "btn_abandon": quit_button}
	confirm_box = Control.new()
	confirm_box.name = "ConfirmBox"
	confirm_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	confirm_box.visible = false
	add_child(confirm_box)
	_confirm_frame = Panel.new()
	_confirm_frame.name = "ConfirmFrame"
	_confirm_frame.add_theme_stylebox_override("panel", SkinA.stylebox("ad_ui_panel_large"))
	_confirm_frame.mouse_filter = Control.MOUSE_FILTER_IGNORE
	confirm_box.add_child(_confirm_frame)
	_confirm_panel = PanelContainer.new()
	_confirm_panel.add_theme_stylebox_override("panel", SkinA.stylebox("ad_ui_panel_small", 10))
	confirm_box.add_child(_confirm_panel)
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 8)
	_confirm_panel.add_child(col)
	confirm_label = Label.new()
	confirm_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	confirm_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	confirm_label.custom_minimum_size.x = 150
	col.add_child(confirm_label)
	confirm_button = _button(col, "ConfirmButton", tr(TEXT["confirm"]), director, func(): confirm_pending())
	cancel_button = _button(col, "CancelButton", tr(TEXT["cancel"]), director, func(): cancel_confirm())
	visibility_changed.connect(_on_visibility_changed)
	get_viewport().size_changed.connect(_relayout)
	_relayout()
	_focus_resume()

func _sprite(tex: Texture2D, id: String) -> void:
	var r := TextureRect.new()
	r.texture = tex
	r.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	r.stretch_mode = TextureRect.STRETCH_SCALE
	r.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	_add_chrome(r, id)

func _add_chrome(r: Control, id: String) -> void:
	r.name = id
	r.mouse_filter = Control.MOUSE_FILTER_IGNORE
	panel.add_child(r)
	_chrome.append([r, id])

func _text(id: String, text: String, color_state: String) -> Label:
	var l := Label.new()
	l.name = id
	l.text = text
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	l.add_theme_color_override("font_color", SkinA.label_color(color_state))
	_add_chrome(l, id)
	return l

## Run summary line (stage / room / time) under the title; set by the owner, tr()-formatted.
func set_run_info(text: String) -> void:
	if run_info_label != null:
		run_info_label.text = text

func _relayout() -> void:
	if backdrop == null:
		return
	var vp := get_viewport_rect().size
	var sc := SkinA.canvas_scale(vp)
	var origin := SkinA.canvas_origin(vp, sc)
	backdrop.position = Vector2.ZERO
	backdrop.size = vp
	panel.position = Vector2.ZERO
	panel.size = vp
	var fs := int(7 * sc)
	for c in _chrome:
		var w: Dictionary = _widgets.get(c[1], {})
		if not w.is_empty():
			SkinA.place(c[0], w, sc, origin)
		if c[0] is Label:
			c[0].add_theme_font_size_override("font_size", fs)
	for id in _buttons:
		var b: Button = _buttons[id]
		if _widgets.has(id):
			SkinA.place(b, _widgets[id], sc, origin)
		b.add_theme_font_size_override("font_size", fs)
	var pw: Dictionary = _widgets.get("panel", {"x": 216, "y": 52, "w": 208, "h": 256})
	var centre := origin + Vector2(pw["x"] + pw["w"] * 0.5, pw["y"] + pw["h"] * 0.5) * sc
	SkinA.place(_confirm_frame, pw, sc, origin)
	_confirm_panel.custom_minimum_size = Vector2(176, 0) * sc
	_confirm_panel.size = Vector2(176, 0) * sc
	_confirm_panel.position = centre - Vector2(88, 60) * sc
	confirm_label.custom_minimum_size.x = 150 * sc
	confirm_label.add_theme_font_size_override("font_size", fs)
	for b in [confirm_button, cancel_button]:
		b.custom_minimum_size.y = 24 * sc
		b.add_theme_font_size_override("font_size", fs)
	_link_focus()

func _link_focus() -> void:
	var chain: Array = []
	for id in SkinA.layout("pause").get("focus_order", []):
		if _buttons.has(id) and _buttons[id].visible:
			chain.append(_buttons[id])
	for i in chain.size():
		var b: Button = chain[i]
		b.focus_neighbor_top = b.get_path_to(chain[(i - 1 + chain.size()) % chain.size()])
		b.focus_neighbor_bottom = b.get_path_to(chain[(i + 1) % chain.size()])

func open_reports_folder() -> void:
	FeedbackSnapshot.ensure_reports_dir()
	if DisplayServer.get_name() != "headless":
		OS.shell_open(FeedbackSnapshot.reports_dir_path())

func _button(parent: Control, node_name: String, text: String, director, action: Callable) -> Button:
	var b := Button.new()
	b.name = node_name
	b.text = text
	b.focus_mode = Control.FOCUS_ALL
	parent.add_child(b)
	b.pressed.connect(action)
	if director != null:
		director.bind_button(b)
	return b

func _on_visibility_changed() -> void:
	if visible:
		_focus_resume()

func _focus_resume() -> void:
	if is_visible_in_tree() and resume_button != null and panel.visible and not is_settings_open():
		resume_button.grab_focus()

func request_retry() -> void:
	_ask("retry", tr(TEXT["retry_prompt"]))

func request_quit() -> void:
	_ask("quit", tr(TEXT["quit_prompt"]))

func request_save_quit() -> void:
	_ask("save_quit", tr(TEXT["save_quit_prompt"]))

## AD-146: Save & Quit is offered only where the run may be saved (the workshop).
func set_save_available(on: bool) -> void:
	save_quit_button.visible = on
	_link_focus()

func _ask(action: String, prompt: String) -> void:
	_pending = action
	confirm_label.text = prompt
	panel.visible = false
	confirm_box.visible = true
	cancel_button.grab_focus()

func confirm_pending() -> void:
	var action := _pending
	_pending = ""
	if action == "retry":
		retry_confirmed.emit()
	elif action == "quit":
		quit_confirmed.emit()
	elif action == "save_quit":
		save_quit_confirmed.emit()

func cancel_confirm() -> void:
	var action := _pending
	_pending = ""
	confirm_box.visible = false
	panel.visible = true
	if action == "retry":
		resume_button.grab_focus()
	elif action == "save_quit":
		save_quit_button.grab_focus()
	else:
		quit_button.grab_focus()

func open_settings() -> void:
	if settings_screen == null:
		settings_screen = SettingsScreen.new()
		settings_screen.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		add_child(settings_screen)
		settings_screen.back_requested.connect(close_settings)
	_opened_from_controls = false
	settings_screen.visible = true
	panel.visible = false

func close_settings() -> void:
	if settings_screen != null:
		settings_screen.visible = false
	panel.visible = true
	(controls_button if _opened_from_controls else settings_button).grab_focus()
	_opened_from_controls = false

## AD-152: the controls help moved to Settings > Controls.
func open_controls() -> void:
	open_settings()
	_opened_from_controls = true
	settings_screen.select_tab("controls")

func close_controls() -> void:
	close_settings()

func set_tips_visible(on: bool) -> void:
	_tips_on = on

func is_controls_open() -> bool:
	return is_settings_open() and settings_screen.current_tab == "controls"

func handle_cancel() -> void:
	if is_settings_open():
		close_settings()
	elif is_confirm_open():
		cancel_confirm()
	else:
		resume_requested.emit()

func is_settings_open() -> bool:
	return settings_screen != null and settings_screen.visible

func is_confirm_open() -> bool:
	return confirm_box != null and confirm_box.visible
