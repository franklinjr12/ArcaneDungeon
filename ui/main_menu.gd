extends Control
const VisualTheme = preload("res://ui/pixel_theme.gd")
const MenuImage = preload("res://assets/pixel/menu_background.png")
## TASK-001: launcher only; actual gameplay belongs to M1/M2.
var volume_slider: HSlider
var flash_toggle: CheckBox
var shake_toggle: CheckBox
var telemetry_toggle: CheckBox

func _ready() -> void:
	VisualTheme.apply(self)
	var backdrop := TextureRect.new()
	backdrop.texture = MenuImage
	backdrop.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	backdrop.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	backdrop.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(backdrop)
	var panel := VBoxContainer.new()
	panel.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	panel.custom_minimum_size = Vector2(370, 300)
	panel.position = Vector2(-185, -150)
	panel.add_theme_constant_override("separation", 18)
	add_child(panel)
	var heading := Label.new()
	heading.text = "ARCANE DUNGEON"
	heading.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	heading.add_theme_font_size_override("font_size", 34)
	heading.add_theme_color_override("font_color",Color("#ffd18c"))
	heading.add_theme_color_override("font_shadow_color",Color("#07101e"))
	heading.add_theme_constant_override("shadow_offset_x",3)
	panel.add_child(heading)
	var subheading := Label.new()
	subheading.text = "SPELLFORGE  •  THE FIRST DESCENT"
	subheading.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	panel.add_child(subheading)
	for pair in [["Magic Sandbox", "res://scenes/sandbox.tscn"], ["Combat Arena", "res://scenes/arena.tscn"], ["Start Run (M3)", "res://scenes/run.tscn"]]:
		var button := Button.new()
		button.text = pair[0]
		button.custom_minimum_size.y = 48
		panel.add_child(button)
		button.pressed.connect(_switch_scene.bind(pair[1]))
		var director = get_node_or_null("/root/AudioDirector")
		if director != null:
			director.bind_button(button)
	_build_settings_row.call_deferred()

func _switch_scene(path: String) -> void:
	var error := get_tree().change_scene_to_file(path)
	if error != OK:
		preload("res://game/core/error_log.gd").record("MAIN_SCENE_CHANGE_FAILED", "%s (%s)" % [path, error])


## Settings live in a sibling control under the viewport root (not a menu descendant), so the
## launcher keeps exactly its three navigation buttons; freed together with the menu.
func _build_settings_row() -> void:
	var save = get_node_or_null("/root/SaveService")
	if save == null:
		return
	var settings = save.settings
	var row := VBoxContainer.new()
	row.add_theme_constant_override("separation", 4)
	row.custom_minimum_size = Vector2(370, 0)
	row.set_anchors_and_offsets_preset(Control.PRESET_CENTER_BOTTOM, Control.PRESET_MODE_MINSIZE, 24)
	VisualTheme.apply(row)
	get_tree().root.add_child(row)
	tree_exiting.connect(row.queue_free)
	var volume_row := HBoxContainer.new()
	row.add_child(volume_row)
	var volume_label := Label.new()
	volume_label.text = "Master volume"
	volume_row.add_child(volume_label)
	volume_slider = HSlider.new()
	volume_slider.min_value = 0.0
	volume_slider.max_value = 1.0
	volume_slider.step = 0.05
	volume_slider.value = float(settings.volumes.get("Master", 1.0))
	volume_slider.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	volume_row.add_child(volume_slider)
	volume_slider.value_changed.connect(func(v: float):
		settings.volumes["Master"] = v
		settings.apply_audio()
		save.save_settings())
	flash_toggle = _toggle(row, "Reduce flashes", settings.reduce_flashes, func(on: bool):
		settings.reduce_flashes = on
		save.save_settings())
	shake_toggle = _toggle(row, "Screen shake", settings.screen_shake, func(on: bool):
		settings.screen_shake = on
		save.save_settings())
	telemetry_toggle = _toggle(row, "Local telemetry (opt-in)", settings.telemetry_opt_in, func(on: bool):
		settings.telemetry_opt_in = on
		save.save_settings())

func _toggle(parent: Control, text: String, value: bool, on_change: Callable) -> CheckBox:
	var box := CheckBox.new()
	box.text = text
	box.button_pressed = value
	parent.add_child(box)
	box.toggled.connect(on_change)
	return box
