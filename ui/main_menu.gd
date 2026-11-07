extends Control
const VisualTheme = preload("res://ui/pixel_theme.gd")
const SkinA = preload("res://ui/skin_a.gd")
const ReduceMotion = preload("res://ui/reduce_motion.gd")
const SettingsScreen = preload("res://ui/settings_screen.gd")
const BuildInfo = preload("res://game/core/build_info.gd")
const CompendiumScreen = preload("res://ui/compendium_screen.gd")
## AD-067: GDD §8 Title screen. Sandbox/Arena are shown only in debug builds.
const TEXT := {
	"title": "menu.title",
	"subtitle": "menu.subtitle",
	"continue": "menu.continue",
	"new_run": "menu.new_run",
	"compendium": "menu.compendium",
	"settings": "menu.settings",
	"quit": "menu.quit",
	"debug": "menu.debug",
	"sandbox": "menu.sandbox",
	"arena": "menu.arena",
}
## null = resolve from OS.is_debug_build(); tests set false before add_child for a release-like run.
var show_debug_entries = null
var settings_screen: Control = null
var compendium_screen: Control = null
var panel: Panel

const TITLE_DIR := "res://assets/ui/title/"
const LOGO_DIR := "res://assets/ui/logo/"
const PARALLAX := [["par_far", 2.0], ["par_mid", 5.0], ["par_near", 10.0]]
const OVERSCAN := 16.0
const BUTTON_IDS := {"btn_continue": "ContinueButton", "btn_new_run": "NewRunButton", "btn_compendium": "CompendiumButton", "btn_settings": "SettingsButton", "btn_quit": "QuitButton"}
var _layers: Array = []  # {rect, depth}
var _logo: TextureRect
var _logo_glow: TextureRect
var _buttons: Dictionary = {}  # layout id -> Button
var _debug_box: VBoxContainer
var _drift := true

func _ready() -> void:
	VisualTheme.apply(self)
	tooltip_text = tr(TEXT["title"])
	_drift = OS.get_environment("AD_UI_SHOT_STATE") == ""
	var save_service = get_node_or_null("/root/SaveService")
	if save_service != null:
		save_service.settings.apply_display(get_window())
	if show_debug_entries == null:
		show_debug_entries = OS.is_debug_build()
	_build_backdrop()
	_logo = TextureRect.new()
	_logo.name = "Logo"
	_logo.texture = load(LOGO_DIR + "ad_key_logo.png")
	_logo.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_logo.stretch_mode = TextureRect.STRETCH_SCALE
	_logo.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	add_child(_logo)
	_logo_glow = TextureRect.new()
	_logo_glow.name = "LogoGlow"
	var glow_mat := CanvasItemMaterial.new()
	glow_mat.blend_mode = CanvasItemMaterial.BLEND_MODE_ADD
	_logo_glow.material = glow_mat
	_logo_glow.texture = load(LOGO_DIR + "ad_key_logo_glow.png")
	_logo_glow.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_logo_glow.stretch_mode = TextureRect.STRETCH_SCALE
	_logo_glow.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	_logo_glow.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_logo_glow)
	panel = Panel.new()
	panel.name = "MenuPanel"
	panel.add_theme_stylebox_override("panel", SkinA.stylebox("ad_ui_panel_large"))
	add_child(panel)
	var continue_button: Button = null
	if save_service != null and save_service.has_run():
		continue_button = _button(panel, "ContinueButton", tr(TEXT["continue"]))
		continue_button.pressed.connect(func():
			save_service.resume_requested = true
			_switch_scene("res://scenes/run.tscn"))
		_buttons["btn_continue"] = continue_button
	var new_run := _button(panel, "NewRunButton", tr(TEXT["new_run"]))
	new_run.pressed.connect(_switch_scene.bind("res://scenes/run.tscn"))
	_buttons["btn_new_run"] = new_run
	_buttons["btn_compendium"] = _button(panel, "CompendiumButton", tr(TEXT["compendium"]))
	_buttons["btn_compendium"].pressed.connect(open_compendium)
	_buttons["btn_settings"] = _button(panel, "SettingsButton", tr(TEXT["settings"]))
	_buttons["btn_settings"].pressed.connect(open_settings)
	_buttons["btn_quit"] = _button(panel, "QuitButton", tr(TEXT["quit"]))
	_buttons["btn_quit"].pressed.connect(func(): get_tree().quit())
	if show_debug_entries:
		_debug_box = VBoxContainer.new()
		_debug_box.name = "DebugBox"
		add_child(_debug_box)
		var debug_label := Label.new()
		debug_label.text = tr(TEXT["debug"])
		debug_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		_debug_box.add_child(debug_label)
		_button(_debug_box, "SandboxButton", tr(TEXT["sandbox"])).pressed.connect(_switch_scene.bind("res://scenes/sandbox.tscn"))
		_button(_debug_box, "ArenaButton", tr(TEXT["arena"])).pressed.connect(_switch_scene.bind("res://scenes/arena.tscn"))
	var stamp := Label.new()
	stamp.name = "BuildStamp"
	stamp.text = tr("menu.build_stamp") % BuildInfo.label()
	stamp.mouse_filter = Control.MOUSE_FILTER_IGNORE
	stamp.add_theme_font_size_override("font_size", 10)
	stamp.modulate = Color(1, 1, 1, 0.7)
	add_child(stamp)
	stamp.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_RIGHT, Control.PRESET_MODE_MINSIZE, 6)
	_link_focus()
	get_viewport().size_changed.connect(_relayout)
	_relayout()
	(continue_button if continue_button != null else new_run).grab_focus()
	_debug_shot_entry()

func _build_backdrop() -> void:
	for layer in PARALLAX:
		var base := TextureRect.new()
		base.name = String(layer[0])
		var rects := [base]
		add_child(base)
		for suffix in ["", "_glow", "_light"]:
			var r: TextureRect = base if suffix == "" else TextureRect.new()
			if suffix != "":
				r.name = String(layer[0]) + suffix
				var mat := CanvasItemMaterial.new()
				mat.blend_mode = CanvasItemMaterial.BLEND_MODE_ADD
				r.material = mat
				add_child(r)
				rects.append(r)
			r.texture = load("%sad_ui_title_illustration_%s%s.png" % [TITLE_DIR, layer[0], suffix])
			r.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
			r.stretch_mode = TextureRect.STRETCH_SCALE
			r.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
			r.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_layers.append({"rects": rects, "depth": layer[1]})

func _link_focus() -> void:
	var order: Array = SkinA.layout("menu").get("focus_order", [])
	var chain: Array = []
	for id in order:
		if _buttons.has(id):
			chain.append(_buttons[id])
	for i in chain.size():
		var b: Button = chain[i]
		var prev: Button = chain[(i - 1 + chain.size()) % chain.size()]
		var next: Button = chain[(i + 1) % chain.size()]
		b.focus_neighbor_top = b.get_path_to(prev)
		b.focus_neighbor_bottom = b.get_path_to(next)

func _relayout() -> void:
	var vp := get_viewport_rect().size
	var sc := SkinA.canvas_scale(vp)
	var origin := SkinA.canvas_origin(vp, sc)
	_place_backdrop(vp, sc, Vector2.ZERO)
	var widgets := {}
	for w in SkinA.layout("menu").get("widgets", []):
		widgets[w.get("id", "")] = w
	if widgets.has("logo"):
		SkinA.place(_logo, widgets["logo"], sc, origin)
		SkinA.place(_logo_glow, widgets["logo"], sc, origin)
	if widgets.has("menu_panel"):
		SkinA.place(panel, widgets["menu_panel"], sc, origin)
	for id in _buttons:
		if widgets.has(id):
			SkinA.place(_buttons[id], widgets[id], sc, origin - panel.position)
			_buttons[id].add_theme_font_size_override("font_size", int(7 * sc))
	if _debug_box != null:
		var area: Dictionary = SkinA.layout("menu").get("safe_area", {})
		var bottom_right := origin + Vector2(area.get("x", 16) + area.get("w", 608), area.get("y", 9) + area.get("h", 342)) * sc
		_debug_box.size = Vector2(130, 0) * sc
		_debug_box.position = bottom_right - Vector2(_debug_box.size.x, 0) - Vector2(0, 100 * sc)
		for b in _debug_box.find_children("*", "Button", false, false):
			b.custom_minimum_size.y = 20 * sc
			b.add_theme_font_size_override("font_size", int(7 * sc))

func _place_backdrop(vp: Vector2, sc: float, shift: Vector2) -> void:
	# 672x392 art = 640x360 canvas + 16 px overscan per side.
	var origin := SkinA.canvas_origin(vp, sc)
	for layer in _layers:
		for r in layer["rects"]:
			r.position = origin - Vector2(OVERSCAN, OVERSCAN) * sc + shift * float(layer["depth"])
			r.size = Vector2(672, 392) * sc

func _process(_delta: float) -> void:
	var save_service = get_node_or_null("/root/SaveService")
	if not _drift or _layers.is_empty() or not ReduceMotion.shake_enabled(save_service.settings if save_service != null else null):
		return
	var vp := get_viewport_rect().size
	var m := get_viewport().get_mouse_position()
	var shift := ((m / vp) - Vector2(0.5, 0.5)).clampf(-0.5, 0.5) * -2.0
	_place_backdrop(vp, SkinA.canvas_scale(vp), shift)

func _button(parent: Control, node_name: String, text: String) -> Button:
	var button := Button.new()
	button.name = node_name
	button.text = text
	button.custom_minimum_size.y = 24
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
	_logo.hide()
	_logo_glow.hide()

func _close_settings() -> void:
	settings_screen.hide()
	panel.show()
	_logo.show()
	_logo_glow.show()
	panel.get_node("SettingsButton").grab_focus()

func open_compendium() -> void:
	if compendium_screen == null:
		compendium_screen = CompendiumScreen.new()
		compendium_screen.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		add_child(compendium_screen)
		compendium_screen.back_requested.connect(_close_compendium)
	compendium_screen.show()
	panel.hide()
	_logo.hide()
	_logo_glow.hide()

func _close_compendium() -> void:
	compendium_screen.hide()
	panel.show()
	_logo.show()
	_logo_glow.show()
	panel.get_node("CompendiumButton").grab_focus()

## AD-090: debug-only UI shot-state hook (env AD_UI_SHOT_STATE / AD_UI_SHOT_OUT); inert in release builds.
const SHOT_RUN_STATES := ["combat","reward","loadout","workshop_editor","merchant","pause","summary","summary_win"]

func apply_debug_shot_state(state: String) -> bool:
	if not OS.is_debug_build() or not state in ["title","settings","compendium","compendium_runes","compendium_reactions","compendium_enemies","compendium_artifacts","settings_audio","settings_video","settings_controls","settings_access"]:
		return false
	if state.begins_with("settings"):
		open_settings()
		if state != "settings" and settings_screen.has_method("select_tab"):
			settings_screen.select_tab(state.trim_prefix("settings_"))
	elif state == "compendium":
		open_compendium()
	elif state.begins_with("compendium_"):
		open_compendium()
		compendium_screen.select_tab(state.trim_prefix("compendium_"))
	return true

func _debug_shot_entry() -> void:
	if not OS.is_debug_build():
		return
	var state := OS.get_environment("AD_UI_SHOT_STATE")
	if state == "":
		return
	if state in SHOT_RUN_STATES:
		get_tree().change_scene_to_file.call_deferred("res://scenes/run.tscn")
	elif apply_debug_shot_state(state):
		await _debug_shot_capture()
	else:
		push_warning("AD_UI_SHOT_STATE unknown: " + state)

func _debug_shot_capture() -> void:
	var path := OS.get_environment("AD_UI_SHOT_OUT")
	if path == "":
		return
	if OS.get_environment("AD_UI_SHOT_FULLSCREEN") == "1":
		DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_FULLSCREEN)
	var delay := OS.get_environment("AD_UI_SHOT_DELAY_MS")
	await get_tree().create_timer((int(delay) if delay != "" else 800) / 1000.0).timeout
	await RenderingServer.frame_post_draw
	var image := get_viewport().get_texture().get_image()
	var error := image.save_png(path)
	print("AD_UI_SHOT saved %s %dx%d" % [path, image.get_width(), image.get_height()])
	get_tree().quit(0 if error == OK else 1)
