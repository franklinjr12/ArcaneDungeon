extends Control
## AD-067: Settings screen (GDD §8/§12). Reused by the title screen and the future pause menu;
## the owner listens to back_requested and decides what to do (this screen never frees itself).
const VisualTheme = preload("res://ui/pixel_theme.gd")
const Settings = preload("res://game/core/settings.gd")
const TEXT := {
	"title": "settings.title",
	"buses": {"Master": "settings.bus.master", "SFX": "settings.bus.sfx", "Ambience": "settings.bus.ambience", "UI": "settings.bus.ui"},
	"flashes": "settings.flashes",
	"shake": "settings.shake",
	"telemetry": "settings.telemetry",
	"window_mode": "settings.window_mode",
	"modes": ["settings.mode.windowed", "settings.mode.fullscreen", "settings.mode.borderless"],
	"ui_scale": "settings.ui_scale",
	"back": "settings.back",
}
signal back_requested

var save_service = null
var volume_sliders := {}
var flash_toggle: CheckBox
var shake_toggle: CheckBox
var telemetry_toggle: CheckBox
var back_button: Button
var _scroll: ScrollContainer
var window_mode_option: OptionButton
var ui_scale_slider: HSlider
var ui_scale_label: Label

func _ready() -> void:
	VisualTheme.apply(self)
	if save_service == null:
		save_service = get_node_or_null("/root/SaveService")
	var settings = save_service.settings if save_service != null else Settings.new()
	var disabled: bool = save_service == null
	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(center)
	_scroll = ScrollContainer.new()
	_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	center.add_child(_scroll)
	var panel := VBoxContainer.new()
	panel.custom_minimum_size = Vector2(370, 0)
	panel.add_theme_constant_override("separation", 12)
	_scroll.add_child(panel)
	var heading := Label.new()
	heading.text = tr(TEXT["title"])
	heading.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	panel.add_child(heading)
	var director = get_node_or_null("/root/AudioDirector")
	for bus in Settings.BUSES:
		var row := HBoxContainer.new()
		panel.add_child(row)
		var label := Label.new()
		label.text = tr(TEXT["buses"][bus])
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
	flash_toggle = _toggle(panel, tr(TEXT["flashes"]), settings.reduce_flashes, disabled, director, func(on: bool):
		settings.reduce_flashes = on
		_save())
	shake_toggle = _toggle(panel, tr(TEXT["shake"]), not settings.screen_shake, disabled, director, func(on: bool):
		settings.screen_shake = not on
		_save())
	telemetry_toggle = _toggle(panel, tr(TEXT["telemetry"]), settings.telemetry_opt_in, disabled, director, func(on: bool):
		settings.telemetry_opt_in = on
		_save())
	var director_ref = director
	var mode_row := HBoxContainer.new()
	panel.add_child(mode_row)
	var mode_label := Label.new()
	mode_label.text = tr(TEXT["window_mode"])
	mode_label.custom_minimum_size.x = 150
	mode_row.add_child(mode_label)
	window_mode_option = OptionButton.new()
	for m in TEXT["modes"]:
		window_mode_option.add_item(tr(m))
	window_mode_option.selected = maxi(Settings.WINDOW_MODES.find(settings.window_mode), 0)
	window_mode_option.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	window_mode_option.focus_mode = Control.FOCUS_ALL
	window_mode_option.disabled = disabled
	mode_row.add_child(window_mode_option)
	window_mode_option.item_selected.connect(func(i: int):
		settings.window_mode = Settings.WINDOW_MODES[i]
		settings.apply_display(get_window())
		_save())
	var scale_row := HBoxContainer.new()
	panel.add_child(scale_row)
	var scale_name := Label.new()
	scale_name.text = tr(TEXT["ui_scale"])
	scale_name.custom_minimum_size.x = 150
	scale_row.add_child(scale_name)
	ui_scale_slider = HSlider.new()
	ui_scale_slider.min_value = 90
	ui_scale_slider.max_value = 150
	ui_scale_slider.step = 10
	ui_scale_slider.value = roundf(settings.ui_scale * 100.0)
	ui_scale_slider.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	ui_scale_slider.focus_mode = Control.FOCUS_ALL
	ui_scale_slider.editable = not disabled
	scale_row.add_child(ui_scale_slider)
	ui_scale_label = Label.new()
	ui_scale_label.custom_minimum_size.x = 50
	ui_scale_label.text = "%d%%" % int(ui_scale_slider.value)
	scale_row.add_child(ui_scale_label)
	ui_scale_slider.value_changed.connect(func(v: float):
		ui_scale_label.text = "%d%%" % int(v)
		settings.ui_scale = Settings.snap_ui_scale(v / 100.0)
		settings.apply_display(get_window())
		_save())
	if director_ref != null:
		director_ref.bind_button(window_mode_option)
	back_button = Button.new()
	back_button.text = tr(TEXT["back"])
	back_button.custom_minimum_size.y = 48
	back_button.focus_mode = Control.FOCUS_ALL
	panel.add_child(back_button)
	back_button.pressed.connect(func(): back_requested.emit())
	if director != null:
		director.bind_button(back_button)
	visibility_changed.connect(_focus_first)
	_focus_first()

func _process(_delta: float) -> void:
	if _scroll != null:
		var h := get_viewport_rect().size.y - 16.0
		_scroll.custom_minimum_size = Vector2(390, minf(h, _scroll.get_child(0).get_combined_minimum_size().y))

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
