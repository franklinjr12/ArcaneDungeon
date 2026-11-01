extends Control
const VisualTheme = preload("res://ui/pixel_theme.gd")
const MenuImage = preload("res://assets/pixel/menu_background.png")
const SettingsScreen = preload("res://ui/settings_screen.gd")
## AD-067: GDD §8 Title screen. Sandbox/Arena are shown only in debug builds.
const TEXT := {
	"title": "ARCANE DUNGEON",
	"subtitle": "SPELLFORGE  •  THE FIRST DESCENT",
	"new_run": "New Run",
	"settings": "Settings",
	"quit": "Quit",
	"debug": "Debug",
	"sandbox": "Magic Sandbox",
	"arena": "Combat Arena",
}
## null = resolve from OS.is_debug_build(); tests set false before add_child for a release-like run.
var show_debug_entries = null
var settings_screen: Control = null
var panel: VBoxContainer

func _ready() -> void:
	VisualTheme.apply(self)
	if show_debug_entries == null:
		show_debug_entries = OS.is_debug_build()
	var backdrop := TextureRect.new()
	backdrop.texture = MenuImage
	backdrop.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	backdrop.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	backdrop.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(backdrop)
	panel = VBoxContainer.new()
	panel.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	panel.custom_minimum_size = Vector2(370, 300)
	panel.position = Vector2(-185, -150)
	panel.add_theme_constant_override("separation", 18)
	add_child(panel)
	var heading := Label.new()
	heading.text = TEXT["title"]
	heading.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	heading.add_theme_font_size_override("font_size", 34)
	heading.add_theme_color_override("font_color",Color("#ffd18c"))
	heading.add_theme_color_override("font_shadow_color",Color("#07101e"))
	heading.add_theme_constant_override("shadow_offset_x",3)
	panel.add_child(heading)
	var subheading := Label.new()
	subheading.text = TEXT["subtitle"]
	subheading.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	panel.add_child(subheading)
	var new_run := _button(panel, "NewRunButton", TEXT["new_run"])
	new_run.pressed.connect(_switch_scene.bind("res://scenes/run.tscn"))
	_button(panel, "SettingsButton", TEXT["settings"]).pressed.connect(open_settings)
	_button(panel, "QuitButton", TEXT["quit"]).pressed.connect(func(): get_tree().quit())
	if show_debug_entries:
		var debug_label := Label.new()
		debug_label.text = TEXT["debug"]
		debug_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		panel.add_child(debug_label)
		_button(panel, "SandboxButton", TEXT["sandbox"]).pressed.connect(_switch_scene.bind("res://scenes/sandbox.tscn"))
		_button(panel, "ArenaButton", TEXT["arena"]).pressed.connect(_switch_scene.bind("res://scenes/arena.tscn"))
	new_run.grab_focus()

func _button(parent: Control, node_name: String, text: String) -> Button:
	var button := Button.new()
	button.name = node_name
	button.text = text
	button.custom_minimum_size.y = 48
	parent.add_child(button)
	var director = get_node_or_null("/root/AudioDirector")
	if director != null:
		director.bind_button(button)
	return button

func _switch_scene(path: String) -> void:
	var error := get_tree().change_scene_to_file(path)
	if error != OK:
		preload("res://game/core/error_log.gd").record("MAIN_SCENE_CHANGE_FAILED", "%s (%s)" % [path, error])

func open_settings() -> void:
	if settings_screen == null:
		settings_screen = SettingsScreen.new()
		settings_screen.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		add_child(settings_screen)
		settings_screen.back_requested.connect(_close_settings)
	settings_screen.show()
	panel.hide()

func _close_settings() -> void:
	settings_screen.hide()
	panel.show()
	panel.get_node("SettingsButton").grab_focus()
