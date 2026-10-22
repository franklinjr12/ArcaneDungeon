extends Control
## TASK-001: the placeholder scenes are navigable but deliberately lack gameplay.

func _ready() -> void:
	var canvas := ColorRect.new()
	canvas.color = Color("#142336")
	canvas.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(canvas)

	var geometry := ColorRect.new()
	geometry.color = Color("#284861")
	geometry.custom_minimum_size = Vector2(128, 128)
	geometry.size = geometry.custom_minimum_size
	geometry.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	geometry.position -= geometry.custom_minimum_size / 2.0
	add_child(geometry)

	var column := VBoxContainer.new()
	column.position = Vector2(30, 25)
	column.add_theme_constant_override("separation", 12)
	add_child(column)
	var title := Label.new()
	title.text = "MAGIC SANDBOX" if name == "MagicSandbox" else "COMBAT ARENA"
	title.add_theme_font_size_override("font_size", 26)
	column.add_child(title)
	var caption := Label.new()
	caption.text = "M0 bootstrap: gameplay is implemented in later milestones"
	column.add_child(caption)
	var home := Button.new()
	home.text = "Back to Menu"
	home.custom_minimum_size = Vector2(160, 36)
	column.add_child(home)
	home.pressed.connect(_home)

func _home() -> void:
	var error := get_tree().change_scene_to_file("res://scenes/main.tscn")
	if error != OK:
		preload("res://game/core/error_log.gd").record("ROOM_SCENE_CHANGE_FAILED", str(error))
