extends RefCounted
## AD-067: four-bus settings defaults + reusable settings screen persistence.
const Service = preload("res://game/core/save_service.gd")
const Screen = preload("res://ui/settings_screen.gd")
const DIR := "user://ad067_test/"

func _clean() -> void:
	DirAccess.make_dir_recursive_absolute(DIR)
	for f in DirAccess.get_files_at(DIR):
		DirAccess.remove_absolute(DIR + f)

func run(t) -> void:
	_clean()
	var svc = Service.new()
	svc.set_base_dir(DIR)
	for bus in ["Master", "SFX", "Ambience", "UI"]:
		t.equal(svc.settings.volumes[bus], 1.0, "AD-067 default volume " + bus)
	t.check(not svc.settings.telemetry_opt_in, "AD-067 telemetry default off")
	var screen = Screen.new()
	screen.save_service = svc
	(Engine.get_main_loop() as SceneTree).root.add_child(screen)
	var keys: Array = screen.volume_sliders.keys()
	keys.sort()
	t.equal(keys, ["Ambience", "Master", "SFX", "UI"], "AD-067 one slider per bus")
	t.check(screen.flash_toggle != null and screen.shake_toggle != null and screen.telemetry_toggle != null, "AD-067 toggles exist")
	t.check(not screen.flash_toggle.button_pressed and not screen.shake_toggle.button_pressed and not screen.telemetry_toggle.button_pressed, "AD-067 toggles start unpressed")
	screen.volume_sliders["SFX"].value = 0.35
	screen.flash_toggle.button_pressed = true
	screen.shake_toggle.button_pressed = true
	screen.telemetry_toggle.button_pressed = true
	var svc2 = Service.new()
	svc2.set_base_dir(DIR)
	t.equal(svc2.settings.volumes["SFX"], 0.35, "AD-067 SFX persists across restart")
	t.check(svc2.settings.reduce_flashes, "AD-067 reduce_flashes persists")
	t.check(not svc2.settings.screen_shake, "AD-067 reduce shake stored as screen_shake=false")
	t.check(svc2.settings.telemetry_opt_in, "AD-067 telemetry opt-in persists")
	var hits := []
	screen.back_requested.connect(func(): hits.append(1))
	screen.back_button.pressed.emit()
	t.equal(hits.size(), 1, "AD-067 back button emits back_requested")
	screen.free()
	svc2.free()
	svc.free()
	_clean()
	DirAccess.remove_absolute(DIR)
	_title(t)

func _title(t) -> void:
	var root = (Engine.get_main_loop() as SceneTree).root
	var menu = load("res://scenes/main.tscn").instantiate()
	menu.show_debug_entries = false
	root.add_child(menu)
	var first = menu.find_child("NewRunButton", true, false)
	t.check(menu.get_viewport().gui_get_focus_owner() == first or first.has_focus(), "AD-067 title focuses New Run")
	var texts := []
	for b in menu.find_children("*", "Button", true, false):
		texts.append(b.text)
	t.equal(texts, ["New Run", "Settings", "Quit"], "AD-067 release title buttons")
	t.check(menu.find_child("SandboxButton", true, false) == null and menu.find_child("ArenaButton", true, false) == null, "AD-067 no debug entries in release")
	menu.open_settings()
	t.check(menu.settings_screen.visible and not menu.panel.visible, "AD-067 settings replaces title panel")
	menu.settings_screen.back_requested.emit()
	t.check(menu.panel.visible and not menu.settings_screen.visible, "AD-067 back restores title panel")
	menu.open_settings()
	var vp = menu.get_viewport()
	var new_run = menu.find_child("NewRunButton", true, false)
	var settings_btn = menu.find_child("SettingsButton", true, false)
	t.check(vp.gui_get_focus_owner() == menu.settings_screen.volume_sliders["Master"] or menu.settings_screen.volume_sliders["Master"].has_focus(), "AD-067 settings focuses first slider")
	var ctrls: Array = menu.settings_screen.volume_sliders.values()
	ctrls.append_array([menu.settings_screen.flash_toggle, menu.settings_screen.shake_toggle, menu.settings_screen.telemetry_toggle, menu.settings_screen.back_button])
	var all_focus := true
	for c in ctrls:
		all_focus = all_focus and c.focus_mode == Control.FOCUS_ALL
	t.check(all_focus, "AD-067 settings controls keyboard focusable")
	var ev := InputEventAction.new()
	ev.action = "ui_cancel"
	ev.pressed = true
	menu.settings_screen._unhandled_input(ev)
	t.check(menu.panel.visible and not menu.settings_screen.visible, "AD-067 ui_cancel returns to title")
	t.check(vp.gui_get_focus_owner() == settings_btn or settings_btn.has_focus(), "AD-067 focus returns to SettingsButton")
	t.check(new_run != null and new_run.focus_mode == Control.FOCUS_ALL, "AD-067 title buttons focusable")
	menu.free()
	var dbg = load("res://scenes/main.tscn").instantiate()
	dbg.show_debug_entries = true
	root.add_child(dbg)
	t.check(dbg.find_child("SandboxButton", true, false) != null and dbg.find_child("ArenaButton", true, false) != null, "AD-067 debug entries when enabled")
	dbg.free()
