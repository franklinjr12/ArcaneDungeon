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
	_coverage(t, root, save)

	save.set_base_dir("user://")
	var d := DirAccess.open(DIR)
	if d != null:
		for f in d.get_files():
			d.remove(f)
		DirAccess.remove_absolute(DIR)
	_restore_globals(root)
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

# ---------------------------------------------------------------- step 4: full mouse + keyboard coverage

func _restore_globals(root: Node) -> void:
	IA.reset_to_defaults()
	preload("res://game/core/settings.gd").new().apply_audio()
	Engine.max_fps = 0
	root.content_scale_factor = 1.0
	AudioServer.set_bus_mute(0, false)
	OsShell.opener = Callable()

## A brand-new SaveService reading the test dir: what a restart would load.
func _fresh_settings():
	var f = preload("res://game/core/save_service.gd").new()
	f.set_base_dir(DIR)
	var s = f.settings
	f.free()
	return s

func _defaults(save) -> void:
	save.settings.reset()
	save.settings.apply_audio()
	save.settings.apply_bindings()
	save.settings.apply_display(null)
	save.save_settings()

func _coverage(t, root: Node, save) -> void:
	_defaults(save)
	_title_coverage(t, root, save)
	_defaults(save)
	_run_coverage(t, root, save)
	_defaults(save)
	_pause_menu_standalone(t)
	_defaults(save)
	_restore_globals(root)

func _title_coverage(t, root: Node, save) -> void:
	var vp := _viewport()
	var menu: Node = load("res://scenes/main.tscn").instantiate()
	menu.show_debug_entries = false
	vp.add_child(menu)
	var panel: Control = menu.panel
	var new_run: Button = panel.get_node("NewRunButton")
	var quit: Button = panel.get_node("QuitButton")
	t.check(_focus(vp) == new_run, "AD-205 title: New Run has initial focus")
	var routes := new_run.pressed.get_connections().filter(func(c): return c["callable"].get_method() == "_switch_scene")
	t.equal(routes.size(), 1, "AD-205 title: New Run is wired to _switch_scene")
	t.check(quit.pressed.get_connections().size() >= 1, "AD-205 title: Quit has a handler")
	quit.grab_focus()
	t.check(_focus(vp) == quit, "AD-205 title: Quit takes focus")
	for entry in [["SettingsButton", "settings_screen"], ["CompendiumButton", "compendium_screen"], ["CreditsButton", "credits_screen"]]:
		var b: Button = panel.get_node(entry[0])
		for how in ["click", "accept"]:
			var tag := "AD-205 title: %s %s " % [entry[0], how]
			if how == "click":
				_click(vp, b)
			else:
				b.grab_focus()
				_action(vp, "ui_accept")
			var screen = menu.get(entry[1])
			t.check(screen != null and screen.visible and not panel.visible, tag + "opens the screen")
			_key(vp, KEY_ESCAPE)
			t.check(not screen.visible and panel.visible and _focus(vp) == b, tag + "Esc closes it and restores focus")
	var sb: Button = panel.get_node("SettingsButton")
	_click(vp, sb)
	_settings_pages(t, vp, menu.settings_screen, save, "title", null)
	# Back: click, ui_cancel, both return to the Settings button.
	_click(vp, menu.settings_screen.back_button)
	t.check(not menu.settings_screen.visible and _focus(vp) == sb, "AD-205 title: Back click closes Settings, focus on Settings button")
	_click(vp, sb)
	_action(vp, "ui_cancel")
	t.check(not menu.settings_screen.visible and _focus(vp) == sb, "AD-205 title: ui_cancel closes Settings, focus on Settings button")
	vp.queue_free()

func _run_coverage(t, root: Node, save) -> void:
	var vp := _viewport()
	var scene := _scene(vp)
	var pm = scene.pause_menu
	t.check(scene.arena_canvas.settings == save.settings, "AD-205 run: arena_canvas.settings is SaveService.settings")
	_pause(scene)
	_click(vp, pm.settings_button)
	var screen = pm.settings_screen
	_settings_pages(t, vp, screen, save, "pause", scene)
	# Back from Settings and from Controls return focus to their opener.
	screen.select_tab("audio")
	_click(vp, screen.back_button)
	t.check(not pm.is_settings_open() and pm.panel.visible and _focus(vp) == pm.settings_button, "AD-205 pause: Back click focuses Settings button")
	_click(vp, pm.settings_button)
	_action(vp, "ui_cancel")
	t.check(not pm.is_settings_open() and _focus(vp) == pm.settings_button, "AD-205 pause: ui_cancel focuses Settings button")
	_click(vp, pm.controls_button)
	t.check(pm.is_controls_open(), "AD-205 pause: Controls opens the controls tab")
	_click(vp, screen.back_button)
	t.check(not pm.is_settings_open() and _focus(vp) == pm.controls_button, "AD-205 pause: Back from Controls focuses Controls button")
	pm.controls_button.grab_focus()
	_action(vp, "ui_accept")
	t.check(pm.is_controls_open(), "AD-205 pause: ui_accept on Controls opens controls tab")
	_action(vp, "ui_cancel")
	t.check(not pm.is_settings_open() and _focus(vp) == pm.controls_button, "AD-205 pause: ui_cancel from Controls focuses Controls button")
	pm.settings_button.grab_focus()
	_action(vp, "ui_accept")
	t.check(pm.is_settings_open() and not pm.is_controls_open(), "AD-205 pause: ui_accept on Settings opens Settings")
	# In-run effects.
	screen.select_tab("access")
	_click(vp, screen.tips_toggle)
	t.check(not save.settings.tips_enabled, "AD-205 pause: tips toggle off")
	scene._update_labels()
	t.check(not scene.guide.enabled, "AD-205 pause: tips off reaches scene.guide on _update_labels")
	_click(vp, screen.tips_toggle)
	scene._update_labels()
	t.check(scene.guide.enabled, "AD-205 pause: tips back on reaches scene.guide")
	var tele_before: bool = scene.flow.experiment.enabled
	_click(vp, screen.telemetry_toggle)
	t.check(save.settings.telemetry_opt_in == not tele_before, "AD-205 pause: telemetry toggle flips the setting")
	var ev := InputEventKey.new()
	ev.physical_keycode = KEY_J
	screen.select_tab("controls")
	_click(vp, screen.binding_buttons["move_up"])
	_push_key(vp, KEY_J)
	t.check(InputMap.action_has_event("move_up", ev), "AD-205 pause: rebind is live in InputMap")
	_key(vp, KEY_ESCAPE)
	_key(vp, KEY_ESCAPE)
	t.check(not scene.is_paused(), "AD-205 pause: Esc Esc resumes")
	t.check(scene.flow.experiment.enabled == save.settings.telemetry_opt_in, "AD-205 pause: telemetry change takes effect after close_pause")
	t.check(InputMap.action_has_event("move_up", ev), "AD-205 pause: rebind survives resume")
	if scene.flow.experiment.enabled:
		_pause(scene)
		scene.pause_menu.open_settings()
		scene.pause_menu.settings_screen.select_tab("access")
		_click(vp, scene.pause_menu.settings_screen.telemetry_toggle)
		scene.close_pause()
		t.check(not scene.flow.experiment.enabled, "AD-205 pause: telemetry off takes effect after close_pause")
	scene.queue_free()
	vp.queue_free()

func _push_key(vp: SubViewport, keycode: Key) -> void:
	_key(vp, keycode)

func _push_button(vp: SubViewport, button: MouseButton) -> void:
	var ev := InputEventMouseButton.new()
	ev.button_index = button
	ev.position = Vector2(5, 5)
	ev.pressed = true
	vp.push_input(ev, true)

## Click the slider at `ratio` of its width.
func _click_slider(vp: SubViewport, s: HSlider, ratio: float) -> void:
	_click_at(vp, s.get_global_rect().position + Vector2(s.size.x * ratio, s.size.y * 0.5))

## Toggle by click, then flip it back with ui_accept. `read` maps a Settings object to the stored value.
func _toggle_both(t, vp: SubViewport, b: Button, live, read: Callable, tag: String) -> void:
	var start = read.call(live)
	var was := b.button_pressed
	_click(vp, b)
	t.check(read.call(live) == not start and b.button_pressed != was, tag + "click flips the setting and the toggle")
	t.check(read.call(_fresh_settings()) == not start, tag + "click persists")
	b.grab_focus()
	_action(vp, "ui_accept")
	t.check(read.call(live) == start, tag + "ui_accept flips it back")
	t.check(read.call(_fresh_settings()) == start, tag + "ui_accept persists")

## Embedded popup input is not deliverable in headless, so choose by emitting the popup's index_pressed (what a real
## item click ends in) and hiding it: OptionButton selects the item and emits item_selected exactly as for a click.
func _pick(dd: OptionButton, index: int) -> void:
	var popup := dd.get_popup()
	popup.index_pressed.emit(index)
	popup.hide()

## Open by click and by ui_accept, pick a different item each way; `read` maps Settings to the stored value.
func _dropdown_both(t, vp: SubViewport, dd: OptionButton, live, picks: Array, values: Array, read: Callable, tag: String, effect: Callable = Callable()) -> void:
	_click(vp, dd)
	t.check(dd.get_popup().visible, tag + "click opens the popup")
	_pick(dd, picks[0])
	t.check(not dd.get_popup().visible and dd.selected == picks[0] and read.call(live) == values[0], tag + "mouse pick applies")
	t.check(read.call(_fresh_settings()) == values[0], tag + "mouse pick persists")
	t.check(not effect.is_valid() or effect.call() == values[0], tag + "mouse pick takes effect live")
	dd.grab_focus()
	_action(vp, "ui_accept")
	t.check(dd.get_popup().visible, tag + "ui_accept opens the popup")
	_pick(dd, picks[1])
	t.check(dd.selected == picks[1] and read.call(live) == values[1], tag + "keyboard pick applies")
	t.check(read.call(_fresh_settings()) == values[1], tag + "keyboard pick persists")
	t.check(not effect.is_valid() or effect.call() == values[1], tag + "keyboard pick takes effect live")

func _near(a: float, b: float) -> bool:
	return absf(a - b) < 0.011

## Every tab of an open Settings screen (title: scene == null; pause: the paused run scene).
func _settings_pages(t, vp: SubViewport, screen, save, label: String, scene) -> void:
	var tag := "AD-205 %s settings: " % label
	var live = save.settings
	for tab in ["video", "controls", "access", "audio"]:
		_click(vp, screen.tab_buttons[tab])
		t.check(screen.current_tab == tab and screen.tab_pages[tab].visible, tag + "tab button click selects " + tab)
	_audio_page(t, vp, screen, live, tag)
	_video_page(t, vp, screen, live, tag)
	_controls_page(t, vp, screen, live, tag, scene)
	_access_page(t, vp, screen, live, tag)
	_chrome(t, vp, screen, live, tag)

func _audio_page(t, vp: SubViewport, screen, live, tag: String) -> void:
	screen.select_tab("audio")
	for bus in preload("res://game/core/settings.gd").BUSES:
		var s: HSlider = screen.volume_sliders[bus]
		var idx := AudioServer.get_bus_index(bus)
		if idx < 0:
			t.check(not s.visible, tag + "%s slider hidden without its bus" % bus)
			continue
		_click_slider(vp, s, 0.3)
		var v: float = live.volumes[bus]
		t.check(v < 0.99 and _near(s.value, v), tag + "%s slider click changes the volume" % bus)
		t.check(_near(AudioServer.get_bus_volume_db(idx), linear_to_db(v)), tag + "%s slider click reaches the bus" % bus)
		t.check(_near(_fresh_settings().volumes[bus], v), tag + "%s slider click persists" % bus)
		s.grab_focus()
		_action(vp, "ui_right")
		var v2: float = live.volumes[bus]
		t.check(v2 > v and _near(AudioServer.get_bus_volume_db(idx), linear_to_db(v2)), tag + "%s slider ui_right raises the bus" % bus)
		t.check(_near(_fresh_settings().volumes[bus], v2), tag + "%s slider ui_right persists" % bus)
		_action(vp, "ui_left")
		t.check(live.volumes[bus] < v2, tag + "%s slider ui_left lowers it" % bus)
	_toggle_both(t, vp, screen.mute_toggle, live, func(s): return s.mute_unfocused, tag + "mute toggle ")
	var director = (Engine.get_main_loop() as SceneTree).root.get_node_or_null("AudioDirector")
	var cues := []
	var spy := func(cue: String, _pos, _ok): cues.append(cue)
	director.cue_played.connect(spy)
	_click(vp, screen.test_button)
	t.check("ui.confirm" in cues, tag + "Test button click plays ui.confirm")
	cues.clear()
	screen.test_button.grab_focus()
	_action(vp, "ui_accept")
	t.check("ui.confirm" in cues, tag + "Test button ui_accept plays ui.confirm")
	director.cue_played.disconnect(spy)

func _video_page(t, vp: SubViewport, screen, live, tag: String) -> void:
	screen.select_tab("video")
	var win: Window = screen.get_window()
	_dropdown_both(t, vp, screen.window_mode_option, live, [1, 2], ["fullscreen", "borderless"], func(s): return s.window_mode, tag + "window mode ")
	_pick(screen.window_mode_option, 0)
	# UI scale slider: click, then ui_right steps up by 10%.
	var us: HSlider = screen.ui_scale_slider
	_click_slider(vp, us, 0.3)
	t.check(not _near(live.ui_scale, 1.0) and _near(win.content_scale_factor, live.ui_scale), tag + "UI scale click changes content_scale_factor")
	t.check(_near(_fresh_settings().ui_scale, live.ui_scale), tag + "UI scale click persists")
	var before: float = live.ui_scale
	us.grab_focus()
	_action(vp, "ui_right")
	t.check(live.ui_scale > before and _near(win.content_scale_factor, live.ui_scale), tag + "UI scale ui_right steps up and applies")
	t.check(_near(_fresh_settings().ui_scale, live.ui_scale), tag + "UI scale ui_right persists")
	us.value = 100
	t.check(_near(win.content_scale_factor, 1.0), tag + "UI scale back to 100%")
	win.content_scale_factor = 1.0
	_dropdown_both(t, vp, screen.frame_limit_option, live, [2, 3], [60, 120], func(s): return s.frame_limit, tag + "frame limit ", func(): return Engine.max_fps)
	_pick(screen.frame_limit_option, 0)
	t.equal(Engine.max_fps, 0, tag + "frame limit unlimited resets Engine.max_fps")
	_toggle_both(t, vp, screen.vsync_toggle, live, func(s): return s.vsync, tag + "vsync toggle ")
	# Lighting: off disables the quality dropdown, on re-enables it.
	_click(vp, screen.lighting_toggle)
	t.check(live.lighting == "off" and screen.lighting_option.disabled, tag + "lighting toggle click turns lighting off and disables quality")
	t.check(_fresh_settings().lighting == "off", tag + "lighting off persists")
	screen.lighting_toggle.grab_focus()
	_action(vp, "ui_accept")
	t.check(live.lighting == "high" and not screen.lighting_option.disabled, tag + "lighting toggle ui_accept restores high and enables quality")
	_dropdown_both(t, vp, screen.lighting_option, live, [1, 0], ["low", "high"], func(s): return s.lighting, tag + "light quality ")
	_toggle_both(t, vp, screen.fps_toggle, live, func(s): return s.show_fps, tag + "show FPS toggle ")

func _access_page(t, vp: SubViewport, screen, live, tag: String) -> void:
	screen.select_tab("access")
	_toggle_both(t, vp, screen.flash_toggle, live, func(s): return s.reduce_flashes, tag + "reduce flashes ")
	_toggle_both(t, vp, screen.shake_toggle, live, func(s): return not s.screen_shake, tag + "reduce shake (stored inverted) ")
	_toggle_both(t, vp, screen.telemetry_toggle, live, func(s): return s.telemetry_opt_in, tag + "telemetry ")
	_toggle_both(t, vp, screen.tips_toggle, live, func(s): return s.tips_enabled, tag + "tips ")
	var ExperimentLog = preload("res://debug/experiment_log.gd")
	var opened := []
	OsShell.opener = func(p: String): opened.append(p)
	_click(vp, screen.open_logs_button)
	t.equal(opened.size(), 1, tag + "Open log folder click calls the opener")
	screen.open_logs_button.grab_focus()
	_action(vp, "ui_accept")
	t.equal(opened.size(), 2, tag + "Open log folder ui_accept calls the opener")
	t.check(opened.all(func(p): return p == ExperimentLog.log_dir_path()), tag + "opener gets the log path")
	OsShell.opener = Callable()

func _show_in_scroll(screen, c: Control) -> void:
	screen._scroll.ensure_control_visible(c)
	screen._scroll.notification(Container.NOTIFICATION_SORT_CHILDREN)

func _bound(live, action: String, slot: int) -> Dictionary:
	var list: Array = live.bindings.get(action, [])
	return list[slot] if list.size() > slot else {}

func _controls_page(t, vp: SubViewport, screen, live, tag: String, scene) -> void:
	screen.select_tab("controls")
	var key_j := {"type": "key", "physical_keycode": KEY_J}
	var mid := {"type": "mouse", "button_index": MOUSE_BUTTON_MIDDLE}
	t.check(screen.binding_buttons["pause"].disabled and screen.alt_buttons["pause"].disabled, tag + "Pause rebind stays locked to Esc")
	for slot in 2:
		var action := "move_up" if slot == 0 else "move_down"
		var b: Button = (screen.binding_buttons if slot == 0 else screen.alt_buttons)[action]
		var which := "primary" if slot == 0 else "alt"
		var effective_before: Array = screen.effective_bindings()[action].duplicate(true)
		_show_in_scroll(screen, b)
		_click(vp, b)
		t.check(screen.listening_action == action and screen._listen_slot == slot and b.mark == "listening", tag + "%s rebind click starts listening" % which)
		_key(vp, KEY_ESCAPE)
		t.check(screen.listening_action == "" and b.mark == "" and screen.effective_bindings()[action] == effective_before, tag + "%s Esc cancels without binding" % which)
		t.check(screen.is_visible_in_tree() and (scene == null or (scene.is_paused() and scene.pause_menu.is_settings_open())), tag + "%s Esc while listening keeps Settings (and pause) open" % which)
		b.grab_focus()
		_action(vp, "ui_accept")
		t.check(screen.listening_action == action and screen._listen_slot == slot, tag + "%s rebind ui_accept starts listening" % which)
		if slot == 0:
			_push_key(vp, KEY_J)
			t.check(_bound(live, action, 0) == key_j and IA.current_bindings()[action].has(key_j), tag + "key press binds primary and updates InputMap")
			t.check(_fresh_settings().bindings.get(action, [{}])[0] == key_j, tag + "primary rebind persists")
		else:
			_push_button(vp, MOUSE_BUTTON_MIDDLE)
			t.check(_bound(live, action, 1) == mid and IA.current_bindings()[action].has(mid), tag + "mouse button binds alt and updates InputMap")
			t.check(_bound(_fresh_settings(), action, 1) == mid, tag + "alt rebind persists")
		t.check(screen.listening_action == "", tag + "%s binding ends listening" % which)
	# Conflict: dash takes interact's key.
	var interact_key: Dictionary = IA.current_bindings()["interact"][0]
	var old_dash: Dictionary = IA.current_bindings()["dash"][0]
	var ev: InputEventKey = IA.dict_to_event(interact_key)
	ev.pressed = true
	for resolve in ["swap click", "cancel click", "swap key", "cancel key"]:
		var d: Button = screen.binding_buttons["dash"]
		_show_in_scroll(screen, d)
		_click(vp, d)
		vp.push_input(ev, true)
		var ctag: String = tag + "conflict (%s): " % resolve
		t.check(screen.conflicts.has("dash") and screen.conflicts.has("interact"), ctag + "shared key is flagged")
		t.check(screen._conflict_group[0].visible and screen.swap_button.visible and not screen.swap_button.disabled and not screen.cancel_button.disabled, ctag + "conflict panel with Swap/Cancel shows")
		var btn: Button = screen.swap_button if resolve.begins_with("swap") else screen.cancel_button
		_show_in_scroll(screen, btn)
		if resolve.ends_with("click"):
			_click(vp, btn)
		else:
			btn.grab_focus()
			_action(vp, "ui_accept")
		t.check(screen.conflicts.is_empty(), ctag + "resolved")
		if resolve.begins_with("swap"):
			t.check(IA.current_bindings()["dash"][0] == interact_key and IA.current_bindings()["interact"][0] == old_dash, ctag + "keys swapped in InputMap")
			t.check(_fresh_settings().bindings.get("interact", [{}])[0] == old_dash, ctag + "swap persists")
			var tmp := interact_key
			interact_key = old_dash
			old_dash = tmp
			ev = IA.dict_to_event(interact_key)
			ev.pressed = true
		else:
			t.check(IA.current_bindings()["dash"][0] == old_dash and IA.current_bindings()["interact"][0] == interact_key, ctag + "cancel restores both")
			t.check(_fresh_settings().bindings.get("dash", [{}])[0] == old_dash, ctag + "cancel persists")
	# Reset keys by click and by keyboard.
	for how in ["click", "accept"]:
		_show_in_scroll(screen, screen.reset_keys_button)
		var rk: Button = screen.reset_keys_button
		if how == "click":
			_click(vp, rk)
		else:
			rk.grab_focus()
			_action(vp, "ui_accept")
		var defaults_ok := true
		for action in IA.REBINDABLE:
			var want := IA.default_events(action).map(func(e): return IA.event_to_dict(e))
			defaults_ok = defaults_ok and IA.current_bindings()[action] == want
		t.check(defaults_ok and live.bindings.is_empty() and _fresh_settings().bindings.is_empty(), tag + "Reset keys (%s) restores default events and persists" % how)
		if how == "click":
			var b: Button = screen.binding_buttons["move_up"]
			_click(vp, b)
			_push_key(vp, KEY_K)
			t.check(not live.bindings.is_empty(), tag + "rebinding works again after reset")

## Back/Defaults/Apply (always on screen) by click and by ui_accept.
func _chrome(t, vp: SubViewport, screen, live, tag: String) -> void:
	var Settings = preload("res://game/core/settings.gd")
	var key_j := {"type": "key", "physical_keycode": KEY_J}
	for how in ["click", "accept"]:
		var htag: String = tag + "Defaults (%s): " % how
		screen.select_tab("audio")
		screen.volume_sliders["Master"].value = 0.4
		screen.mute_toggle.button_pressed = true
		screen.select_tab("video")
		screen.frame_limit_option.item_selected.emit(2)
		screen.rebind_action("move_up", IA.dict_to_event(key_j))
		t.check(live.volumes["Master"] < 1.0 and live.mute_unfocused and live.frame_limit == 60 and Engine.max_fps == 60, htag + "setup changed settings")
		_press(vp, screen.reset_button, how)
		t.check(_near(live.volumes["Master"], 1.0) and not live.mute_unfocused and live.frame_limit == 0 and live.bindings.is_empty(), htag + "settings reset")
		t.check(_near(screen.volume_sliders["Master"].value, 1.0) and not screen.mute_toggle.button_pressed and screen.frame_limit_option.selected == 0, htag + "controls refreshed")
		t.check(Engine.max_fps == 0 and _near(AudioServer.get_bus_volume_db(AudioServer.get_bus_index("Master")), 0.0), htag + "reset applied live")
		t.check(screen.binding_buttons["move_up"].text == IA.event_text(IA.default_events("move_up")[0]) and not IA.current_bindings()["move_up"].has(key_j), htag + "rebind buttons and InputMap back to default")
		var fresh = _fresh_settings()
		t.check(_near(fresh.volumes["Master"], 1.0) and not fresh.mute_unfocused and fresh.bindings.is_empty(), htag + "reset persisted")
	for how in ["click", "accept"]:
		var atag: String = tag + "Apply (%s): " % how
		var limit := 30 if how == "click" else 60
		live.frame_limit = limit
		live.mute_unfocused = true
		live.volumes["SFX"] = 0.5
		live.bindings = {"move_up": [key_j]}
		var fresh = _fresh_settings()
		t.check(fresh.frame_limit == 0 and not fresh.mute_unfocused, atag + "in-memory change is not saved yet")
		_press(vp, screen.apply_button, how)
		fresh = _fresh_settings()
		t.check(fresh.frame_limit == limit and fresh.mute_unfocused and _near(fresh.volumes["SFX"], 0.5) and fresh.bindings.has("move_up"), atag + "persisted")
		t.check(Engine.max_fps == limit and _near(AudioServer.get_bus_volume_db(AudioServer.get_bus_index("SFX")), linear_to_db(0.5)) and IA.current_bindings()["move_up"].has(key_j), atag + "applied live")
		_press(vp, screen.reset_button, "click")
	t.check(Settings.new().frame_limit == 0, tag + "chrome cleanup done")

## Containers lay out on a deferred sort and the suite never awaits a frame, so sort a control's container ancestors now.
func _settle(c: Control) -> void:
	var chain: Array = []
	var n: Node = c.get_parent()
	while n is Container:
		chain.push_front(n)
		n = n.get_parent()
	for container in chain:
		container.notification(Container.NOTIFICATION_SORT_CHILDREN)

func _press(vp: SubViewport, b: Button, how: String) -> void:
	if how == "click":
		_settle(b)
		_click(vp, b)
	else:
		b.grab_focus()
		_action(vp, "ui_accept")

func _pause_menu_standalone(t) -> void:
	var vp := _viewport()
	var pm = preload("res://ui/pause_menu.gd").new()
	vp.add_child(pm)
	var seen := []
	pm.resume_requested.connect(func(): seen.append("resume"))
	pm.loadout_requested.connect(func(): seen.append("loadout"))
	pm.save_quit_confirmed.connect(func(): seen.append("save_quit"))
	pm.quit_confirmed.connect(func(): seen.append("quit"))
	pm.set_loadout_available(false)
	t.check(not pm.loadout_button.visible and not pm.save_quit_button.visible, "AD-205 pause menu: Loadout and Save & Quit hidden by default")
	t.check(_focus(vp) == pm.resume_button, "AD-205 pause menu: Resume focused")
	for how in ["click", "accept"]:
		var tag := "AD-205 pause menu (%s): " % how
		seen.clear()
		_press(vp, pm.resume_button, how)
		t.equal(seen, ["resume"], tag + "Resume emits resume_requested")
		pm.set_loadout_available(true)
		_press(vp, pm.loadout_button, how)
		t.equal(seen, ["resume", "loadout"], tag + "Loadout emits loadout_requested")
		pm.set_loadout_available(false)
		_press(vp, pm.settings_button, how)
		t.check(pm.is_settings_open() and not pm.is_controls_open() and not pm.panel.visible, tag + "Settings opens")
		_action(vp, "ui_cancel")
		t.check(not pm.is_settings_open() and pm.panel.visible and _focus(vp) == pm.settings_button, tag + "ui_cancel closes Settings, focus restored")
		_press(vp, pm.controls_button, how)
		t.check(pm.is_controls_open(), tag + "Controls opens the controls tab")
		_action(vp, "ui_cancel")
		t.check(not pm.is_settings_open() and _focus(vp) == pm.controls_button, tag + "ui_cancel closes Controls, focus on Controls button")
		var opened := []
		OsShell.opener = func(p: String): opened.append(p)
		_press(vp, pm.open_reports_button, how)
		OsShell.opener = Callable()
		t.equal(opened, [FS.reports_dir_path()], tag + "Open Reports goes through OsShell.opener")
		# Save & Quit (workshop only): Confirm emits, Cancel returns.
		pm.set_save_available(true)
		seen.clear()
		_press(vp, pm.save_quit_button, how)
		t.check(pm.is_confirm_open() and not pm.panel.visible and _focus(vp) == pm.cancel_button, tag + "Save & Quit opens the confirm box on Cancel")
		_press(vp, pm.cancel_button, how)
		t.check(not pm.is_confirm_open() and pm.panel.visible and _focus(vp) == pm.save_quit_button and seen.is_empty(), tag + "Cancel returns to Save & Quit")
		_press(vp, pm.save_quit_button, how)
		_press(vp, pm.confirm_button, how)
		t.equal(seen, ["save_quit"], tag + "Confirm emits save_quit_confirmed")
		pm.cancel_confirm()
		pm.set_save_available(false)
		# Abandon.
		seen.clear()
		_press(vp, pm.quit_button, how)
		t.check(pm.is_confirm_open(), tag + "Abandon opens the confirm box")
		_press(vp, pm.cancel_button, how)
		t.check(not pm.is_confirm_open() and _focus(vp) == pm.quit_button and seen.is_empty(), tag + "Abandon Cancel returns")
		_press(vp, pm.quit_button, how)
		_press(vp, pm.confirm_button, how)
		t.equal(seen, ["quit"], tag + "Abandon Confirm emits quit_confirmed")
		pm.cancel_confirm()
	vp.queue_free()
