extends Control
const VisualTheme = preload("res://ui/pixel_theme.gd")
const MenuImage = preload("res://assets/pixel/menu_background.png")
## TASK-001: launcher only; actual gameplay belongs to M1/M2.

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

func _switch_scene(path: String) -> void:
	var error := get_tree().change_scene_to_file(path)
	if error != OK:
		preload("res://game/core/error_log.gd").record("MAIN_SCENE_CHANGE_FAILED", "%s (%s)" % [path, error])
