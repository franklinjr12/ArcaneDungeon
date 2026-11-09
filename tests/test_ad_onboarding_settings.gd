extends RefCounted
## AD-185: Settings 'Tips' toggle (persisted, silences tips without using them up) and the pause Controls button.
const Service = preload("res://game/core/save_service.gd")
const Screen = preload("res://ui/settings_screen.gd")
const Pause = preload("res://ui/pause_menu.gd")
const Prompts = preload("res://ui/onboarding_prompts.gd")
const InputActions = preload("res://ui/input_actions.gd")
const SkinA = preload("res://ui/skin_a.gd")
const DIR := "user://ad185_test/"

func _clean() -> void:
	DirAccess.make_dir_recursive_absolute(DIR)
	for f in DirAccess.get_files_at(DIR):
		DirAccess.remove_absolute(DIR + f)

func run(t) -> void:
	_clean()
	var svc = Service.new()
	svc.set_base_dir(DIR)
	t.check(svc.settings.tips_enabled, "AD-185 tips_enabled defaults to true")
	var screen = Screen.new()
	screen.save_service = svc
	(Engine.get_main_loop() as SceneTree).root.add_child(screen)
	t.check(screen.tips_toggle != null and screen.tips_toggle.button_pressed, "AD-185 tips toggle starts on")
	screen.tips_toggle.button_pressed = false
	var svc2 = Service.new()
	svc2.set_base_dir(DIR)
	t.check(not svc2.settings.tips_enabled, "AD-185 tips off persists across a new SaveService")
	svc2.free()

	var prompts = Prompts.new()
	prompts.enabled = false
	t.equal(prompts.trigger("room1"), "", "AD-185 disabled prompts return no text")
	t.check(prompts.seen.is_empty() and prompts.shown_count == 0, "AD-185 disabled prompts are not marked seen")
	prompts.enabled = true
	t.check(prompts.trigger("room1") != "", "AD-185 re-enabled prompts still show the tip")

	t.check("btn_controls" in SkinA.layout("pause").get("focus_order", []), "AD-185 pause layout focus_order has btn_controls")
	var menu = Pause.new()
	(Engine.get_main_loop() as SceneTree).root.add_child(menu)
	menu.controls_button.pressed.emit()
	t.check(menu.is_controls_open(), "AD-185 ControlsButton opens Settings > Controls")
	var original: Dictionary = menu.settings_screen._settings.bindings.duplicate(true)
	var ev := InputEventKey.new()
	ev.physical_keycode = KEY_G
	menu.settings_screen._settings.bindings = InputActions.rebind_primary({}, "dash", ev)
	menu.settings_screen.refresh_bindings()
	t.equal(menu.settings_screen.binding_buttons["dash"].text, InputActions.event_text(ev), "AD-185 Controls tab shows the rebound dash key")
	menu.settings_screen._settings.bindings = original
	menu.settings_screen.refresh_bindings()
	menu.close_settings()
	t.check(menu.panel.visible and not menu.is_settings_open(), "AD-185 closing controls returns to the pause panel")
	menu.free()
	screen.free()
	svc.free()
	_clean()
	DirAccess.remove_absolute(DIR)
