extends RefCounted
## AD-205: drive the REAL paused run scene with pushed input events (mouse/keys/actions) through
## the GUI pipeline, so swallowed input (e.g. _input handling everything while paused) is caught.
## Fully synchronous: tests/run_tests.gd does not await suites.

const DIR := "user://ad205_test/"
const OsShell = preload("res://ui/os_shell.gd")
const FS = preload("res://ui/feedback_snapshot.gd")
const IA = preload("res://ui/input_actions.gd")

func _viewport() -> SubViewport:
	var vp := SubViewport.new()
	vp.size = Vector2i(1280, 720)
	vp.disable_3d = true
	vp.gui_embed_subwindows = true
	(Engine.get_main_loop() as SceneTree).root.add_child(vp)
	return vp

func _click_at(vp: SubViewport, pos: Vector2) -> void:
	var mm := InputEventMouseMotion.new()
	mm.position = pos
	mm.global_position = pos
	vp.push_input(mm, true)
	for pressed in [true, false]:
		var ev := InputEventMouseButton.new()
		ev.button_index = MOUSE_BUTTON_LEFT
		ev.position = pos
		ev.global_position = pos
		ev.pressed = pressed
		ev.button_mask = MOUSE_BUTTON_MASK_LEFT if pressed else 0
		vp.push_input(ev, true)

func _click(vp: SubViewport, c: Control) -> void:
	_click_at(vp, c.get_global_rect().get_center())

func _action(vp: SubViewport, action_name: String) -> void:
	for pressed in [true, false]:
		var ev := InputEventAction.new()
		ev.action = action_name
		ev.pressed = pressed
		vp.push_input(ev, true)

func _key(vp: SubViewport, keycode: Key) -> void:
	for pressed in [true, false]:
		var ev := InputEventKey.new()
		ev.keycode = keycode
		ev.physical_keycode = keycode
		ev.pressed = pressed
		vp.push_input(ev, true)

func _focus(vp: SubViewport) -> Control:
	return vp.gui_get_focus_owner()

func _scene(vp: SubViewport) -> Node:
	var scene: Node = load("res://scenes/run.tscn").instantiate()
	scene.show_dev_tools = false
	scene.config_path = "res://world/data/vertical_slice_v1.json"
	vp.add_child(scene)
	return scene

func _pause(scene: Node) -> void:
	scene.open_pause()
	if not scene.is_paused():
		scene.apply_debug_shot_state("pause")

func run(t) -> void:
	var root := (Engine.get_main_loop() as SceneTree).root
	var save = root.get_node("SaveService")
	save.set_base_dir(DIR)
	var vp := _viewport()
	var scene := _scene(vp)
	var pm = scene.pause_menu
	_pause(scene)
	t.check(scene.is_paused(), "AD-205 run scene can be paused")

	t.check(not pm.loadout_button.visible, "AD-205 Loadout hidden while fighting")
	t.check(_focus(vp) == pm.resume_button, "AD-205 Resume focused initially")
	_action(vp, "ui_down")
	t.check(_focus(vp) != null and _focus(vp) != pm.resume_button, "AD-205 ui_down moves focus off Resume")
	_action(vp, "ui_up")
	t.check(_focus(vp) == pm.resume_button, "AD-205 ui_up returns focus to Resume")

	_action(vp, "ui_accept")
	t.check(not scene.is_paused(), "AD-205 ui_accept on Resume unpauses")
	_pause(scene)
	_click(vp, pm.resume_button)
	t.check(not scene.is_paused(), "AD-205 mouse click on Resume unpauses")

	_pause(scene)
	_click(vp, pm.settings_button)
	t.check(pm.is_settings_open() and not pm.is_controls_open(), "AD-205 click Settings opens Settings")
	var sliders: Dictionary = pm.settings_screen.volume_sliders
	pm.settings_screen.select_tab("audio")
	var s: Control = sliders["Master"]
	var before: float = s.value
	_click_at(vp, s.get_global_rect().position + Vector2(s.size.x * 0.25, s.size.y * 0.5))
	t.check(not is_equal_approx(s.value, before), "AD-205 clicking a volume slider while paused changes it")
	_key(vp, KEY_ESCAPE)
	t.check(not pm.is_settings_open() and scene.is_paused(), "AD-205 Esc closes only Settings")
	_click(vp, pm.controls_button)
	t.check(pm.is_controls_open(), "AD-205 click Controls opens Settings on controls tab")
	_key(vp, KEY_ESCAPE)
	t.check(not pm.is_settings_open() and scene.is_paused(), "AD-205 Esc closes Controls, stays paused")

	_click(vp, pm.quit_button)
	t.check(pm.is_confirm_open(), "AD-205 Abandon opens confirm")
	_click(vp, pm.cancel_button)
	t.check(not pm.is_confirm_open() and pm.panel.visible and scene.is_paused(), "AD-205 Cancel returns to pause panel")
	_click(vp, pm.quit_button)
	_key(vp, KEY_ESCAPE)
	t.check(not pm.is_confirm_open() and scene.is_paused(), "AD-205 Esc closes only the confirm box")

	var opened: Array = []
	OsShell.opener = func(p: String): opened.append(p)
	_click(vp, pm.open_reports_button)
	t.equal(opened.size(), 1, "AD-205 click Open Reports calls opener once")
	pm.open_reports_button.grab_focus()
	_action(vp, "ui_accept")
	t.equal(opened.size(), 2, "AD-205 ui_accept Open Reports calls opener once more")
	t.check(opened.all(func(p): return p == FS.reports_dir_path()), "AD-205 opener gets the reports path")
	OsShell.opener = Callable()

	_key(vp, KEY_ESCAPE)
	t.check(not scene.is_paused(), "AD-205 Esc on bare pause panel resumes")

	_pause(scene)
	_click(vp, pm.settings_button)
	_keyboard(t, vp, pm.settings_screen, "run", func():
		# An open embedded popup swallows pushed key events in this harness, so hand Esc to the run scene like its _input sees it.
		var esc := InputEventKey.new()
		esc.keycode = KEY_ESCAPE
		esc.physical_keycode = KEY_ESCAPE
		esc.pressed = true
		scene._input(esc))
	t.check(pm.is_settings_open() and scene.is_paused(), "AD-205 run: popup Esc leaves Settings open and paused")
	_key(vp, KEY_ESCAPE)
	t.check(not pm.is_settings_open() and scene.is_paused(), "AD-205 run: next Esc closes Settings only")
	_key(vp, KEY_ESCAPE)
	scene.queue_free()
	vp.queue_free()
	_title_keyboard(t)
	vp = _viewport()

	_new_settings(t, root, save)

	save.set_base_dir("user://")
	var d := DirAccess.open(DIR)
	if d != null:
		for f in d.get_files():
			d.remove(f)
		DirAccess.remove_absolute(DIR)
	IA.reset_to_defaults()
	vp.queue_free()

func _title_keyboard(t) -> void:
	var vp := _viewport()
	var menu: Node = load("res://scenes/main.tscn").instantiate()
	menu.show_debug_entries = false
	vp.add_child(menu)
	_click(vp, menu.find_child("SettingsButton", true, false))
	t.check(menu.settings_screen != null and menu.settings_screen.visible, "AD-205 title: click Settings opens it")
	_keyboard(t, vp, menu.settings_screen, "title", func(): t.check(menu.settings_screen.close_open_popup(), "AD-205 title: close_open_popup closes the open dropdown"))
	t.check(menu.settings_screen.visible, "AD-205 title: popup cancel leaves Settings open")
	vp.queue_free()

## Keyboard-only walk of an open Settings screen: initial focus, focus ring, vertical chains, Tab/Q/E, slider, dropdown popup.
func _keyboard(t, vp: SubViewport, screen, label: String, cancel: Callable) -> void:
	var tag := "AD-205 %s: " % label
	var f := _focus(vp)
	t.check(f != null and f.is_visible_in_tree(), tag + "Settings opens with a visible focus owner")
	t.check(f == screen.volume_sliders["Master"], tag + "focus lands on the Master slider")
	for tab in ["audio", "video", "controls", "access"]:
		screen.select_tab(tab)
		var start: Control = screen.tab_buttons[tab]
		start.grab_focus()
		var expected := []
		for c in screen.tab_pages[tab].find_children("*", "Control", true, false):
			if (c is Button or c is OptionButton or c is HSlider) and c.focus_mode != Control.FOCUS_NONE and c.is_visible_in_tree():
				if not ((c is HSlider and not c.editable) or (not c is HSlider and c.disabled)):
					expected.append(c)
		for b in [screen.back_button, screen.reset_button, screen.apply_button]:
			expected.append(b)
		var seen := []
		var steps := 0
		var ring_ok := true
		var never_null := true
		while steps < 60:
			_action(vp, "ui_down")
			steps += 1
			f = _focus(vp)
			if f == null:
				never_null = false
				break
			if f == start:
				break
			seen.append(f)
			if f.has_method("shows_focus_ring") and not f.shows_focus_ring():
				ring_ok = false
		t.check(never_null and f == start, tag + "%s ui_down wraps back to the tab button" % tab)
		t.check(ring_ok, tag + "%s focused controls show the focus ring" % tab)
		var missing := expected.filter(func(c): return not c in seen)
		t.equal(missing.size(), 0, tag + "%s ui_down visits every enabled control" % tab)
	screen.select_tab("audio")
	screen.tab_buttons["audio"].grab_focus()
	for step in [[KEY_TAB, false, "video"], [KEY_TAB, false, "controls"], [KEY_TAB, false, "access"], [KEY_TAB, false, "audio"], [KEY_TAB, true, "access"]]:
		_key_mod(vp, step[0], step[1])
		t.equal(screen.current_tab, step[2], tag + "Tab step to " + step[2])
	_key(vp, KEY_Q)
	t.equal(screen.current_tab, "controls", tag + "Q still steps back")
	_key(vp, KEY_E)
	t.equal(screen.current_tab, "access", tag + "E still steps forward")
	screen.select_tab("audio")
	var master: HSlider = screen.volume_sliders["Master"]
	master.grab_focus()
	master.value = 0.5
	_action(vp, "ui_right")
	t.check(master.value > 0.5, tag + "ui_right raises a focused slider")
	t.check(is_equal_approx(screen._settings.volumes["Master"], master.value), tag + "slider change persisted to settings")
	screen.select_tab("video")
	var dd: OptionButton = screen.window_mode_option
	dd.grab_focus()
	_action(vp, "ui_accept")
	t.check(dd.get_popup().visible, tag + "ui_accept opens the dropdown popup")
	cancel.call()
	t.check(not dd.get_popup().visible, tag + "cancel closes the popup")
	t.check(screen.visible, tag + "Settings stays open after closing the popup")

func _key_mod(vp: SubViewport, keycode: Key, shift: bool) -> void:
	for pressed in [true, false]:
		var ev := InputEventKey.new()
		ev.keycode = keycode
		ev.physical_keycode = keycode
		ev.shift_pressed = shift
		ev.pressed = pressed
		vp.push_input(ev, true)

func _new_settings(t, root: Node, save) -> void:
	var Screen = preload("res://ui/settings_screen.gd")
	var Service = preload("res://game/core/save_service.gd")
	var screen = Screen.new()
	screen.save_service = save
	root.add_child(screen)
	screen.select_tab("video")
	t.check(save.settings.frame_limit == 0 and save.settings.vsync and not save.settings.mute_unfocused, "AD-205 new settings defaults")
	screen.frame_limit_option.item_selected.emit(Settings_FRAME_LIMITS().find(60))
	screen.vsync_toggle.button_pressed = false
	screen.select_tab("audio")
	screen.mute_toggle.button_pressed = true
	t.equal(save.settings.frame_limit, 60, "AD-205 frame limit changes")
	t.equal(Engine.max_fps, 60, "AD-205 frame limit applies to Engine.max_fps")
	t.check(not save.settings.vsync and save.settings.mute_unfocused, "AD-205 vsync/mute change")
	var fresh = Service.new()
	fresh.set_base_dir(DIR)
	t.check(fresh.settings.frame_limit == 60 and not fresh.settings.vsync and fresh.settings.mute_unfocused, "AD-205 new settings persist to a fresh SaveService")
	var ad = root.get_node_or_null("AudioDirector")
	if ad != null:
		ad.notification(Node.NOTIFICATION_APPLICATION_FOCUS_OUT)
		t.check(AudioServer.is_bus_mute(0), "AD-205 focus out mutes master when mute_unfocused")
		ad.notification(Node.NOTIFICATION_APPLICATION_FOCUS_IN)
		t.check(not AudioServer.is_bus_mute(0), "AD-205 focus in unmutes master")
	else:
		t.check(false, "AD-205 AudioDirector autoload present")
	screen.reset_button.pressed.emit()
	t.check(save.settings.frame_limit == 0 and save.settings.vsync and not save.settings.mute_unfocused and Engine.max_fps == 0, "AD-205 defaults reset new settings")
	screen.queue_free()
	Engine.max_fps = 0
	AudioServer.set_bus_mute(0, false)
	root.content_scale_factor = 1.0

func Settings_FRAME_LIMITS() -> Array:
	return preload("res://game/core/settings.gd").FRAME_LIMITS
