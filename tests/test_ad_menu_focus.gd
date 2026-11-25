extends SceneTree
## AD-255 step 1: gamepad menu focus acceptance test. Every menu screen is opened and walked with simulated
## pad events (d-pad, left stick, A, B): focus is set on open, every enabled control is reachable, B goes back.
const TestContext = preload("res://tests/test_context.gd")

const DIR := "user://ad255_test/"
const MAX_STEPS := 80

func _initialize() -> void:
	call_deferred("_run_standalone")

func _run_standalone() -> void:
	var t := TestContext.new()
	run(t)
	print("TEST SUMMARY: %d passed / %d failed" % [t.passed, t.failed])
	for failure in t.failures:
		printerr("FAILED: ", failure)
	if t.failed == 0:
		print("PASS")
	quit(1 if t.failed > 0 else 0)

func _viewport() -> SubViewport:
	var vp := SubViewport.new()
	vp.size = Vector2i(1280, 720)
	vp.disable_3d = true
	vp.gui_embed_subwindows = true
	(Engine.get_main_loop() as SceneTree).root.add_child(vp)
	return vp

func _pad_button(vp: SubViewport, button: JoyButton) -> void:
	for pressed in [true, false]:
		var ev := InputEventJoypadButton.new()
		ev.button_index = button
		ev.pressed = pressed
		vp.push_input(ev, true)

func _stick(vp: SubViewport, axis: JoyAxis, value: float) -> void:
	for v in [value, 0.0]:
		var ev := InputEventJoypadMotion.new()
		ev.axis = axis
		ev.axis_value = v
		vp.push_input(ev, true)

func _focus(vp: SubViewport) -> Control:
	return vp.gui_get_focus_owner()

## Enabled focusable controls under `root` that a pad user must be able to reach.
func _reachable_set(root: Node) -> Array:
	var out := []
	for c in root.find_children("*", "Control", true, false):
		if not (c is Button or c is HSlider or c is OptionButton) or c.focus_mode == Control.FOCUS_NONE or not c.is_visible_in_tree():
			continue
		if (c is HSlider and not c.editable) or (not c is HSlider and c.disabled):
			continue
		out.append(c)
	return out

## Explore focus by pressing every direction from every reached control (grid and tab layouts are 2D).
## Returns the reached controls; a null/off-screen result or a control with no way out is reported.
func _walk(t, vp: SubViewport, tag: String, use_stick: bool = false) -> Array:
	var start := _focus(vp)
	var seen := [start]
	var queue := [start]
	var dirs := [[JOY_BUTTON_DPAD_DOWN, JOY_AXIS_LEFT_Y, 1.0], [JOY_BUTTON_DPAD_UP, JOY_AXIS_LEFT_Y, -1.0],
			[JOY_BUTTON_DPAD_RIGHT, JOY_AXIS_LEFT_X, 1.0], [JOY_BUTTON_DPAD_LEFT, JOY_AXIS_LEFT_X, -1.0]]
	while not queue.is_empty() and seen.size() < 400:
		var c: Control = queue.pop_front()
		var exits := 0
		for d in dirs:
			c.grab_focus()
			if use_stick:
				_stick(vp, d[1], d[2])
			else:
				_pad_button(vp, d[0])
			var f := _focus(vp)
			if f == null:
				t.check(false, tag + "focus lost after leaving %s" % c.name)
				return seen
			if f != c:
				exits += 1
				if not f in seen:
					seen.append(f)
					queue.append(f)
		if exits == 0 and seen.size() > 1:
			t.check(false, tag + "focus trapped on %s" % c.name)
	return seen

func _check_screen(t, vp: SubViewport, screen: Node, tag: String) -> void:
	var f := _focus(vp)
	t.check(f != null and f.is_visible_in_tree() and screen.is_ancestor_of(f), tag + "initial focus inside the screen")
	if f == null:
		return
	var seen := _walk(t, vp, tag)
	var missing := _reachable_set(screen).filter(func(c): return not c in seen)
	t.equal(missing.size(), 0, tag + "every enabled control reachable by d-pad (missing %s)" % [missing.map(func(c): return str(c.name))])

## Pushed joypad-motion events do not drive Control focus navigation in a SubViewport (buttons do), so the
## left stick is verified at the action layer: each stick direction must match its ui_* action.
func _check_stick_actions(t) -> void:
	for entry in [["ui_down", JOY_AXIS_LEFT_Y, 1.0], ["ui_up", JOY_AXIS_LEFT_Y, -1.0],
			["ui_right", JOY_AXIS_LEFT_X, 1.0], ["ui_left", JOY_AXIS_LEFT_X, -1.0]]:
		var ev := InputEventJoypadMotion.new()
		ev.axis = entry[1]
		ev.axis_value = entry[2]
		t.check(ev.is_action_pressed(entry[0]), "AD-255 left stick drives %s" % entry[0])
	for entry in [["ui_accept", JOY_BUTTON_A], ["ui_cancel", JOY_BUTTON_B], ["ui_down", JOY_BUTTON_DPAD_DOWN]]:
		var ev := InputEventJoypadButton.new()
		ev.button_index = entry[1]
		ev.pressed = true
		t.check(ev.is_action_pressed(entry[0]), "AD-255 pad button %d drives %s" % [entry[1], entry[0]])

func run(t) -> void:
	preload("res://ui/input_actions.gd").pad_last_used = false
	var root := (Engine.get_main_loop() as SceneTree).root
	var save = root.get_node("SaveService")
	save.set_base_dir(DIR)
	_check_stick_actions(t)
	_title(t)
	_run_screens(t)
	save.set_base_dir("user://")
	var d := DirAccess.open(DIR)
	if d != null:
		for f in d.get_files():
			d.remove(f)
		DirAccess.remove_absolute(DIR)

func _title(t) -> void:
	var vp := _viewport()
	var menu: Node = load("res://scenes/main.tscn").instantiate()
	menu.show_debug_entries = false
	vp.add_child(menu)
	var panel: Control = menu.panel
	t.check(_focus(vp) != null and panel.is_ancestor_of(_focus(vp)), "AD-255 main: initial focus set")
	var seen := _walk(t, vp, "AD-255 main: ")
	t.equal(_reachable_set(panel).filter(func(c): return not c in seen).size(), 0, "AD-255 main: every button reachable")
	for entry in [["SettingsButton", "settings_screen"], ["CompendiumButton", "compendium_screen"],
			["ScriptoriumButton", "scriptorium_screen"], ["CreditsButton", "credits_screen"]]:
		var b: Button = panel.get_node(entry[0])
		var tag := "AD-255 %s: " % entry[1]
		b.grab_focus()
		_pad_button(vp, JOY_BUTTON_A)
		var screen = menu.get(entry[1])
		t.check(screen != null and screen.visible and not panel.visible, tag + "A opens the screen")
		if screen == null:
			continue
		if entry[1] == "settings_screen":
			for tab in ["audio", "video", "controls", "access"]:
				screen.select_tab(tab)
				var f := _focus(vp)
				t.check(f != null and f.is_visible_in_tree() and screen.is_ancestor_of(f), tag + "%s tab has focus" % tab)
				_check_tab(t, vp, screen, tag + tab + ": ")
		else:
			_check_screen(t, vp, screen, tag)
		_pad_button(vp, JOY_BUTTON_B)
		t.check(not screen.visible and panel.visible and _focus(vp) == b, tag + "B closes it and focus returns to its button")
	vp.queue_free()

## Settings tab: the walk must reach every enabled control of the page plus Back/Reset/Apply.
func _check_tab(t, vp: SubViewport, screen, tag: String) -> void:
	screen.tab_buttons[screen.current_tab].grab_focus()
	var seen := _walk(t, vp, tag)
	var expected := _reachable_set(screen.tab_pages[screen.current_tab])
	for b in [screen.back_button, screen.reset_button, screen.apply_button]:
		expected.append(b)
	var missing := expected.filter(func(c): return not c in seen)
	t.equal(missing.size(), 0, tag + "every enabled control reachable (missing %s)" % [missing.map(func(c): return str(c.name))])

func _run_scene(vp: SubViewport) -> Node:
	var scene: Node = load("res://scenes/run.tscn").instantiate()
	scene.show_dev_tools = false
	scene.config_path = "res://world/data/vertical_slice_v1.json"
	vp.add_child(scene)
	return scene

func _run_screens(t) -> void:
	# Reward choice: cards focused, every card reachable, no trap (a reward must be taken, so B has nothing to leave).
	var vp := _viewport()
	var scene := _run_scene(vp)
	t.check(scene.apply_debug_shot_state("reward"), "AD-255 reward: debug state reached")
	var o = scene.reward_overlay
	t.check(_focus(vp) != null and o.is_ancestor_of(_focus(vp)), "AD-255 reward: initial focus set")
	var seen := _walk(t, vp, "AD-255 reward: ")
	var missing := _reachable_set(o).filter(func(c): return not c in seen)
	t.equal(missing.size(), 0, "AD-255 reward: every card reachable (missing %s)" % [missing.map(func(c): return str(c.name))])
	vp.queue_free()

	# Workshop: focus set, shop overlay and spell editor navigable, B backs out of editor/shop.
	vp = _viewport()
	scene = _run_scene(vp)
	t.check(scene.apply_debug_shot_state("workshop"), "AD-255 workshop: debug state reached")
	_pad_button(vp, JOY_BUTTON_Y) # unbound pad press: marks the pad as the last-used device
	var f := _focus(vp)
	t.check(f != null and f.is_visible_in_tree(), "AD-255 workshop: initial focus set")
	if f != null:
		var wseen := _walk(t, vp, "AD-255 workshop: ")
		var holder: Control = scene.workshop_holder if scene.workshop_holder.visible else scene.shop_overlay
		var wmissing := _reachable_set(holder).filter(func(c): return not c in wseen)
		t.equal(wmissing.size(), 0, "AD-255 workshop: every control reachable (missing %s)" % [wmissing.map(func(c): return str(c.name))])
	t.check(scene.apply_debug_shot_state("merchant") and scene.shop_overlay.visible, "AD-255 merchant: shop overlay shown")
	f = _focus(vp)
	t.check(f != null and scene.shop_overlay.is_ancestor_of(f), "AD-255 merchant: initial focus set in the shop")
	var sseen := _walk(t, vp, "AD-255 merchant: ")
	t.equal(_reachable_set(scene.shop_overlay).filter(func(c): return not c in sseen).size(), 0, "AD-255 merchant: every offer reachable")
	_pad_button(vp, JOY_BUTTON_B)
	t.check(not scene.shop_overlay.visible, "AD-255 merchant: B closes the shop")
	t.check(_focus(vp) != null, "AD-255 workshop: focus kept after leaving the shop")
	t.check(scene.apply_debug_shot_state("workshop_editor") and scene.editor_open, "AD-255 editor: opens")
	f = _focus(vp)
	t.check(f != null and scene.editor_dock.is_ancestor_of(f), "AD-255 editor: initial focus inside the editor")
	if f != null:
		var eseen := _walk(t, vp, "AD-255 editor: ")
		t.equal(_reachable_set(scene.editor_dock).filter(func(c): return not c in eseen).size(), 0, "AD-255 editor: every control reachable")
	_pad_button(vp, JOY_BUTTON_B)
	t.check(not scene.editor_open, "AD-255 editor: B backs out")
	vp.queue_free()
