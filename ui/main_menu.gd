extends Control
## TASK-001: launcher only; actual gameplay belongs to M1/M2.

func _ready() -> void:
	var backdrop := ColorRect.new()
	backdrop.color = Color("#0b1320")
	backdrop.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(backdrop)
	var panel := VBoxContainer.new()
	panel.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	panel.custom_minimum_size = Vector2(360, 220)
	panel.position = Vector2(-180, -110)
	panel.add_theme_constant_override("separation", 18)
	add_child(panel)
	var heading := Label.new()
	heading.text = "ARCANE DUNGEON"
	heading.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	heading.add_theme_font_size_override("font_size", 30)
	panel.add_child(heading)
	var subheading := Label.new()
	subheading.text = "M0 systems prototype • final art intentionally deferred"
	subheading.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	panel.add_child(subheading)
	for pair in [["Magic Sandbox", "res://scenes/sandbox.tscn"], ["Combat Arena", "res://scenes/arena.tscn"]]:
		var button := Button.new()
		button.text = pair[0]
		button.custom_minimum_size.y = 48
		panel.add_child(button)
		button.pressed.connect(_switch_scene.bind(pair[1]))

func _switch_scene(path: String) -> void:
	var error := get_tree().change_scene_to_file(path)
	if error != OK:
		preload("res://game/core/error_log.gd").record("MAIN_SCENE_CHANGE_FAILED", "%s (%s)" % [path, error])
