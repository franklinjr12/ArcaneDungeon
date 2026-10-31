extends Control
## AD-067: Settings screen (GDD §8/§12). Reused by the title screen and the future pause menu;
## the owner listens to back_requested and decides what to do (this screen never frees itself).
const VisualTheme = preload("res://ui/pixel_theme.gd")
const Settings = preload("res://game/core/settings.gd")
const TEXT := {
	"title": "Settings",
	"buses": {"Master": "Master volume", "SFX": "SFX volume", "Ambience": "Ambience volume", "UI": "UI volume"},
	"flashes": "Reduce flashes",
	"shake": "Reduce screen shake",
	"telemetry": "Local telemetry (opt-in)",
	"back": "Back",
}
signal back_requested

var save_service = null
var volume_sliders := {}
var flash_toggle: CheckBox
var shake_toggle: CheckBox
var telemetry_toggle: CheckBox
var back_button: Button

func _ready() -> void:
	VisualTheme.apply(self)
	if save_service == null:
		save_service = get_node_or_null("/root/SaveService")
	var settings = save_service.settings if save_service != null else Settings.new()
	var disabled: bool = save_service == null
	var panel := VBoxContainer.new()
	panel.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	panel.custom_minimum_size = Vector2(370, 0)
	panel.position = Vector2(-185, -170)
	panel.add_theme_constant_override("separation", 12)
	add_child(panel)
	var heading := Label.new()
	heading.text = TEXT["title"]
	heading.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	panel.add_child(heading)
	var director = get_node_or_null("/root/AudioDirector")
	for bus in Settings.BUSES:
		var row := HBoxContainer.new()
		panel.add_child(row)
		var label := Label.new()
		label.text = TEXT["buses"][bus]
		label.custom_minimum_size.x = 150
		row.add_child(label)
		var slider := HSlider.new()
		slider.min_value = 0.0
		slider.max_value = 1.0
		slider.step = 0.05
		slider.value = float(settings.volumes.get(bus, 1.0))
		slider.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		slider.focus_mode = Control.FOCUS_ALL
		slider.editable = not disabled
		row.add_child(slider)
		slider.value_changed.connect(func(v: float):
			settings.volumes[bus] = v
			settings.apply_audio()
			_save())
		volume_sliders[bus] = slider
	flash_toggle = _toggle(panel, TEXT["flashes"], settings.reduce_flashes, disabled, director, func(on: bool):
		settings.reduce_flashes = on
		_save())
	shake_toggle = _toggle(panel, TEXT["shake"], not settings.screen_shake, disabled, director, func(on: bool):
		settings.screen_shake = not on
		_save())
	telemetry_toggle = _toggle(panel, TEXT["telemetry"], settings.telemetry_opt_in, disabled, director, func(on: bool):
		settings.telemetry_opt_in = on
		_save())
	back_button = Button.new()
	back_button.text = TEXT["back"]
	back_button.custom_minimum_size.y = 48
	back_button.focus_mode = Control.FOCUS_ALL
	panel.add_child(back_button)
	back_button.pressed.connect(func(): back_requested.emit())
	if director != null:
		director.bind_button(back_button)
	visibility_changed.connect(_focus_first)
	_focus_first()

func _save() -> void:
	if save_service != null:
		save_service.save_settings()

func _focus_first() -> void:
	if is_visible_in_tree() and volume_sliders.has(Settings.BUSES[0]):
		volume_sliders[Settings.BUSES[0]].grab_focus()

func _unhandled_input(event: InputEvent) -> void:
	if visible and event.is_action_pressed("ui_cancel"):
		back_requested.emit()
		get_viewport().set_input_as_handled()

func _toggle(parent: Control, text: String, value: bool, disabled: bool, director, on_change: Callable) -> CheckBox:
	var box := CheckBox.new()
	box.text = text
	box.button_pressed = value
	box.disabled = disabled
	box.focus_mode = Control.FOCUS_ALL
	parent.add_child(box)
	box.toggled.connect(on_change)
	if director != null:
		director.bind_button(box)
	return box
