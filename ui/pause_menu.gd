extends Control
## AD-068: modal pause overlay (GDD §8). The owner (run controller) shows/hides it and reacts to the
## signals; this menu never frees itself.
const VisualTheme = preload("res://ui/pixel_theme.gd")
const SettingsScreen = preload("res://ui/settings_screen.gd")
const TEXT := {
	"title": "Paused",
	"resume": "Resume",
	"settings": "Settings",
	"retry": "Retry same seed",
	"quit": "Quit to Title",
	"confirm": "Confirm",
	"cancel": "Cancel",
	"retry_prompt": "Restart this run with the same seed? Current progress is lost.",
	"quit_prompt": "Quit to Title? This run ends, is recorded as abandoned and cannot be resumed.",
}
signal resume_requested
signal retry_confirmed
signal quit_confirmed

var panel: VBoxContainer
var confirm_box: VBoxContainer
var confirm_label: Label
var resume_button: Button
var settings_button: Button
var retry_button: Button
var quit_button: Button
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
	panel = _column(Vector2(-150, -150))
	_heading(panel, TEXT["title"])
	resume_button = _button(panel, "ResumeButton", TEXT["resume"], director, func(): resume_requested.emit())
	settings_button = _button(panel, "SettingsButton", TEXT["settings"], director, func(): open_settings())
	retry_button = _button(panel, "RetryButton", TEXT["retry"], director, func(): request_retry())
	quit_button = _button(panel, "QuitButton", TEXT["quit"], director, func(): request_quit())
	confirm_box = _column(Vector2(-200, -100))
	confirm_box.custom_minimum_size.x = 400
	confirm_box.visible = false
	confirm_label = Label.new()
	confirm_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	confirm_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	confirm_box.add_child(confirm_label)
	confirm_button = _button(confirm_box, "ConfirmButton", TEXT["confirm"], director, func(): confirm_pending())
	cancel_button = _button(confirm_box, "CancelButton", TEXT["cancel"], director, func(): cancel_confirm())
	visibility_changed.connect(_on_visibility_changed)
	_focus_resume()

func _column(offset: Vector2) -> VBoxContainer:
	var box := VBoxContainer.new()
	box.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	box.custom_minimum_size = Vector2(300, 0)
	box.position = offset
	box.add_theme_constant_override("separation", 12)
	add_child(box)
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
	_ask("retry", TEXT["retry_prompt"])

func request_quit() -> void:
	_ask("quit", TEXT["quit_prompt"])

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

func cancel_confirm() -> void:
	var action := _pending
	_pending = ""
	confirm_box.visible = false
	panel.visible = true
	(retry_button if action == "retry" else quit_button).grab_focus()

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
