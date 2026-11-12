extends RefCounted
## AD-225: window-mode application goes through an injectable display backend (mocked here), F11 / Alt+Enter toggle
## is a rebindable action, and the choice persists through the config round-trip.
const Settings = preload("res://game/core/settings.gd")
const InputActions = preload("res://ui/input_actions.gd")

class MockDisplay:
	var mode := DisplayServer.WINDOW_MODE_WINDOWED
	var borderless := false
	var calls: Array = []
	func get_mode() -> int: return mode
	func is_borderless() -> bool: return borderless
	func set_mode(m: int) -> void:
		mode = m
		calls.append(["mode", m])
	func set_borderless(b: bool) -> void:
		borderless = b
		calls.append(["borderless", b])
	func set_size(v: Vector2i) -> void: calls.append(["size", v])
	func set_position(v: Vector2i) -> void: calls.append(["pos", v])
	func screen_position() -> Vector2i: return Vector2i.ZERO
	func screen_size() -> Vector2i: return Vector2i(1920, 1080)
	func has_call(kind: String, value = null) -> bool:
		for c in calls:
			if c[0] == kind and (value == null or c[1] == value):
				return true
		return false

func run(t) -> void:
	var s := Settings.new()
	var d := MockDisplay.new()
	s.display = d
	s.window_mode = "fullscreen"
	s.apply_display(null)
	t.check(d.has_call("mode", DisplayServer.WINDOW_MODE_FULLSCREEN), "fullscreen issues WINDOW_MODE_FULLSCREEN")
	d.calls.clear()
	s.window_mode = "windowed"
	s.apply_display(null)
	t.check(d.has_call("mode", DisplayServer.WINDOW_MODE_WINDOWED), "windowed issues WINDOW_MODE_WINDOWED")
	t.check(d.has_call("size", Vector2i(1280, 720)), "leaving fullscreen restores project size")
	d.calls.clear()
	s.window_mode = "borderless"
	s.apply_display(null)
	t.check(d.has_call("borderless", true), "borderless sets the flag")
	d.calls.clear()
	s.window_mode = "fullscreen"
	s.apply_display(null)
	t.check(d.has_call("borderless", false) and d.mode == DisplayServer.WINDOW_MODE_FULLSCREEN, "fullscreen clears borderless first")
	d.calls.clear()
	s.window_mode = "windowed"
	s.apply_display(null)
	d.calls.clear()
	s.apply_display(null)
	t.check(not d.has_call("size"), "windowed->windowed never resizes")

	s.window_mode = "windowed"
	s.toggle_fullscreen()
	t.equal(s.window_mode, "fullscreen", "toggle windowed -> fullscreen")
	var cfg := ConfigFile.new()
	s.to_config(cfg)
	var s2 := Settings.new()
	s2.from_config(cfg)
	t.equal(s2.window_mode, "fullscreen", "fullscreen persists through config")
	s.toggle_fullscreen()
	t.equal(s.window_mode, "windowed", "toggle fullscreen -> windowed")
	s.window_mode = "borderless"
	s.toggle_fullscreen()
	t.equal(s.window_mode, "fullscreen", "borderless toggles to fullscreen")

	t.check(InputActions.REBINDABLE.has("toggle_fullscreen"), "toggle_fullscreen is rebindable")
	var f11 := false
	var alt_enter := false
	for ev in InputActions.default_events("toggle_fullscreen"):
		if ev is InputEventKey and ev.physical_keycode == KEY_F11 and not ev.alt_pressed:
			f11 = true
		if ev is InputEventKey and ev.physical_keycode == KEY_ENTER and ev.alt_pressed:
			alt_enter = true
	t.check(f11, "default F11")
	t.check(alt_enter, "default Alt+Enter")
	var saved := InputActions.current_bindings()
	var ev := InputEventKey.new()
	ev.physical_keycode = KEY_ENTER
	ev.alt_pressed = true
	var back := InputActions.dict_to_event(InputActions.event_to_dict(ev))
	t.check(back != null and back.alt_pressed and back.physical_keycode == KEY_ENTER, "alt modifier survives dict round-trip")
	var s3 := Settings.new()
	s3.bindings = {"toggle_fullscreen": [InputActions.event_to_dict(ev)]}
	var cfg3 := ConfigFile.new()
	s3.to_config(cfg3)
	var s4 := Settings.new()
	s4.from_config(cfg3)
	t.check(InputActions.events_equal(InputActions.dict_to_event(s4.bindings["toggle_fullscreen"][0]), ev), "rebinding persists via Settings")
	InputActions.apply_bindings(saved)
