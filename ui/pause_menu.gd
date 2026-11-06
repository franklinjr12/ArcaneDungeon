extends Control
## AD-068: modal pause overlay (GDD §8). The owner (run controller) shows/hides it and reacts to the
## signals; this menu never frees itself.
const VisualTheme = preload("res://ui/pixel_theme.gd")
const SettingsScreen = preload("res://ui/settings_screen.gd")
const TEXT := {
	"title": "pause.title",
	"resume": "pause.resume",
	"settings": "pause.settings",
	"retry": "pause.retry",
	"quit": "pause.quit",
	"save_quit": "pause.save_quit",
	"save_quit_prompt": "pause.save_quit_prompt",
	"controls": "pause.controls",
	"back": "pause.back",
	"tips_hide": "pause.tips_hide",
	"tips_show": "pause.tips_show",
	"controls_text": "pause.controls_text",
	"confirm": "pause.confirm",
	"cancel": "pause.cancel",
	"retry_prompt": "pause.retry_prompt",
	"quit_prompt": "pause.quit_prompt",
}
signal resume_requested
signal retry_confirmed
signal quit_confirmed
signal save_quit_confirmed
signal tips_toggled

var panel: VBoxContainer
var confirm_box: VBoxContainer
var confirm_label: Label
var resume_button: Button
var settings_button: Button
var retry_button: Button
var quit_button: Button
var save_quit_button: Button
var controls_button: Button
var tips_button: Button
var controls_box: VBoxContainer
var controls_back_button: Button
var confirm_button: Button
var cancel_button: Button
var settings_screen = null
var _pending := ""

func _ready() -> void:
	VisualTheme.apply(self)
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	var dim := ColorRect.new()
	dim.color = Color(0, 0, 0, 0.6)
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	dim.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(dim)
	var director = get_node_or_null("/root/AudioDirector")
	panel = _column()
	_heading(panel, tr(TEXT["title"]))
	resume_button = _button(panel, "ResumeButton", tr(TEXT["resume"]), director, func(): resume_requested.emit())
	settings_button = _button(panel, "SettingsButton", tr(TEXT["settings"]), director, func(): open_settings())
	controls_button = _button(panel, "ControlsButton", tr(TEXT["controls"]), director, func(): open_controls())
	tips_button = _button(panel, "TipsButton", tr(TEXT["tips_hide"]), director, func(): tips_toggled.emit())
	retry_button = _button(panel, "RetryButton", tr(TEXT["retry"]), director, func(): request_retry())
	save_quit_button = _button(panel, "SaveQuitButton", tr(TEXT["save_quit"]), director, func(): request_save_quit())
	save_quit_button.visible = false
	quit_button = _button(panel, "QuitButton", tr(TEXT["quit"]), director, func(): request_quit())
	confirm_box = _column()
	confirm_box.custom_minimum_size.x = 400
	confirm_box.visible = false
	confirm_label = Label.new()
	confirm_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	confirm_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	confirm_box.add_child(confirm_label)
	confirm_button = _button(confirm_box, "ConfirmButton", tr(TEXT["confirm"]), director, func(): confirm_pending())
	cancel_button = _button(confirm_box, "CancelButton", tr(TEXT["cancel"]), director, func(): cancel_confirm())
	controls_box = _column()
	controls_box.custom_minimum_size.x = 520
	controls_box.visible = false
	var controls_label := Label.new()
	controls_label.name = "ControlsText"
	controls_label.text = tr(TEXT["controls_text"])
	controls_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	controls_box.add_child(controls_label)
	controls_back_button = _button(controls_box, "ControlsBackButton", tr(TEXT["back"]), director, func(): close_controls())
	visibility_changed.connect(_on_visibility_changed)
	_focus_resume()

func _column() -> VBoxContainer:
	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(center)
	var box := VBoxContainer.new()
	box.custom_minimum_size = Vector2(300, 0)
	box.add_theme_constant_override("separation", 12)
	center.add_child(box)
	return box

func _heading(parent: Control, text: String) -> void:
	var heading := Label.new()
	heading.text = text
	heading.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	parent.add_child(heading)

func _button(parent: Control, node_name: String, text: String, director, action: Callable) -> Button:
	var b := Button.new()
	b.name = node_name
	b.text = text
	b.custom_minimum_size.y = 48
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
	if is_visible_in_tree() and resume_button != null and panel.visible:
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
		retry_button.grab_focus()
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
	settings_screen.visible = true
	panel.visible = false

func close_settings() -> void:
	if settings_screen != null:
		settings_screen.visible = false
	panel.visible = true
	settings_button.grab_focus()

func open_controls() -> void:
	panel.visible = false
	controls_box.visible = true
	controls_back_button.grab_focus()

func close_controls() -> void:
	controls_box.visible = false
	panel.visible = true
	controls_button.grab_focus()

func set_tips_visible(on: bool) -> void:
	tips_button.text = tr(TEXT["tips_hide"]) if on else tr(TEXT["tips_show"])

func is_controls_open() -> bool:
	return controls_box != null and controls_box.visible

func handle_cancel() -> void:
	if is_controls_open():
		close_controls()
	elif is_settings_open():
		close_settings()
	elif is_confirm_open():
		cancel_confirm()
	else:
		resume_requested.emit()

func is_settings_open() -> bool:
	return settings_screen != null and settings_screen.visible

func is_confirm_open() -> bool:
	return confirm_box != null and confirm_box.visible
