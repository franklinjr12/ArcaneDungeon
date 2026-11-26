extends RefCounted
## Input-map helpers shared by the arena and run controllers.
## AD-255: true while the last meaningful input came from a gamepad (menus then set focus on open).
static var pad_last_used := false

## Returns true when this event flipped the last-used device to the pad.
static func note_device(event: InputEvent) -> bool:
	var pad: bool = (event is InputEventJoypadButton and event.pressed) or (event is InputEventJoypadMotion and absf(event.axis_value) >= 0.5)
	var other: bool = (event is InputEventKey and event.pressed) or (event is InputEventMouseButton and event.pressed)
	if pad and not pad_last_used:
		pad_last_used = true
		return true
	if other:
		pad_last_used = false
	return false

const CAST_ACTIONS := ["cast_slot_1","cast_slot_2","cast_slot_3","cast_slot_4"]

static func cast_slot_for_event(event: InputEvent) -> int:
	for i in CAST_ACTIONS.size():
		if event.is_action_pressed(CAST_ACTIONS[i],false):
			return i
	return -1

static func slot_for_mouse_button(button: int) -> int:
	return 0 if button == MOUSE_BUTTON_LEFT else 1

## AD-225: right mouse button press (overlays use it as a close gesture).
static func is_secondary_press(event: InputEvent) -> bool:
	return event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_RIGHT

static func debug_keys_enabled() -> bool:
	return OS.is_debug_build()

## Cast slot bound to a mouse button, or -1 (so rebound cast actions are followed).
static func cast_slot_for_mouse_button(button: int) -> int:
	var ev := InputEventMouseButton.new()
	ev.button_index = button
	ev.pressed = true
	return cast_slot_for_event(ev)

const REBINDABLE := ["move_up","move_down","move_left","move_right","cast_slot_1","cast_slot_2",
	"cast_slot_3","cast_slot_4","dash","interact","pause","report","toggle_fullscreen"]

const GAMEPAD_FILE := "res://game/data/gamepad_v1.json"
static var _gamepad_cache: Dictionary = {}
static var _gamepad_loaded := false

## AD-254: default pad data (bindings, aim deadzone); empty when the file is missing or invalid.
static func gamepad_data() -> Dictionary:
	if _gamepad_loaded:
		return _gamepad_cache
	_gamepad_loaded = true
	var file := FileAccess.open(GAMEPAD_FILE, FileAccess.READ)
	var parsed = JSON.parse_string(file.get_as_text()) if file != null else null
	if typeof(parsed) == TYPE_DICTIONARY:
		_gamepad_cache = parsed
	return _gamepad_cache

## Keyboard/mouse defaults from the project settings plus the data-driven pad defaults.
static func default_events(action: String) -> Array:
	var out: Array = []
	var setting = ProjectSettings.get_setting("input/" + action, null)
	if typeof(setting) == TYPE_DICTIONARY:
		for ev in setting.get("events", []):
			out.append(ev.duplicate())
	var pad = gamepad_data().get("bindings", {})
	var list = pad.get(action, []) if typeof(pad) == TYPE_DICTIONARY else []
	if typeof(list) == TYPE_ARRAY:
		for d in list:
			var ev := dict_to_event(d)
			if ev == null or not (ev is InputEventJoypadButton or ev is InputEventJoypadMotion):
				continue
			var dup := false
			for have in out:
				dup = dup or events_equal(have, ev)
			if not dup:
				out.append(ev)
	return out

static func _with_alt(d: Dictionary, ev: InputEventKey) -> Dictionary:
	if ev.alt_pressed:
		d["alt_pressed"] = true
	return d

static func event_to_dict(ev) -> Dictionary:
	if ev is InputEventKey:
		if ev.physical_keycode != 0:
			return _with_alt({"type":"key","physical_keycode":int(ev.physical_keycode)}, ev)
		return _with_alt({"type":"key","keycode":int(ev.keycode)}, ev)
	if ev is InputEventMouseButton:
		return {"type":"mouse","button_index":int(ev.button_index)}
	if ev is InputEventJoypadButton:
		return {"type":"joy_button","button_index":int(ev.button_index)}
	if ev is InputEventJoypadMotion:
		return {"type":"joy_axis","axis":int(ev.axis),"value":-1.0 if ev.axis_value < 0.0 else 1.0}
	return {}

static func _num(d: Dictionary, key: String) -> bool:
	return d.has(key) and (typeof(d[key]) == TYPE_INT or typeof(d[key]) == TYPE_FLOAT)

static func dict_to_event(d) -> InputEvent:
	if typeof(d) != TYPE_DICTIONARY:
		return null
	match d.get("type", ""):
		"key":
			var ev := InputEventKey.new()
			if _num(d, "physical_keycode") and int(d["physical_keycode"]) != 0:
				ev.physical_keycode = int(d["physical_keycode"])
			elif _num(d, "keycode") and int(d["keycode"]) != 0:
				ev.keycode = int(d["keycode"])
			else:
				return null
			ev.alt_pressed = d.get("alt_pressed", false) == true
			return ev
		"mouse":
			if not _num(d, "button_index") or int(d["button_index"]) <= 0:
				return null
			var ev := InputEventMouseButton.new()
			ev.button_index = int(d["button_index"])
			return ev
		"joy_button":
			if not _num(d, "button_index") or int(d["button_index"]) < 0:
				return null
			var ev := InputEventJoypadButton.new()
			ev.button_index = int(d["button_index"])
			return ev
		"joy_axis":
			if not _num(d, "axis") or int(d["axis"]) < 0 or not _num(d, "value"):
				return null
			var ev := InputEventJoypadMotion.new()
			ev.axis = int(d["axis"])
			ev.axis_value = -1.0 if float(d["value"]) < 0.0 else 1.0
			return ev
	return null

static func events_equal(a, b) -> bool:
	var da := event_to_dict(a)
	return not da.is_empty() and da == event_to_dict(b)

## AD-255: menu confirm/back on the pad. Adds the data-driven pad events to the built-in ui_* actions (idempotent).
static func apply_ui_pad_bindings() -> void:
	var ui = gamepad_data().get("ui_bindings", {})
	if typeof(ui) != TYPE_DICTIONARY:
		return
	for action in ui:
		if not InputMap.has_action(action) or typeof(ui[action]) != TYPE_ARRAY:
			continue
		for d in ui[action]:
			var ev := dict_to_event(d)
			if ev == null:
				continue
			var have := false
			for existing in InputMap.action_get_events(action):
				have = have or events_equal(existing, ev)
			if not have:
				InputMap.action_add_event(action, ev)

static func apply_bindings(overrides: Dictionary) -> void:
	apply_ui_pad_bindings()
	for action in REBINDABLE:
		if not InputMap.has_action(action):
			continue
		var events: Array = []
		if overrides.has(action) and typeof(overrides[action]) == TYPE_ARRAY:
			for d in overrides[action]:
				var ev := dict_to_event(d)
				if ev != null:
					events.append(ev)
		if events.is_empty():
			events = default_events(action)
		InputMap.action_erase_events(action)
		for ev in events:
			InputMap.action_add_event(action, ev)

static func reset_to_defaults() -> void:
	apply_bindings({})

static func current_bindings() -> Dictionary:
	var out := {}
	for action in REBINDABLE:
		var list: Array = []
		for ev in InputMap.action_get_events(action):
			var d := event_to_dict(ev)
			if not d.is_empty():
				list.append(d)
		out[action] = list
	return out

## action -> other REBINDABLE actions sharing an identical event (only conflicting actions appear).
static func find_conflicts(bindings: Dictionary) -> Dictionary:
	var out := {}
	for a in REBINDABLE:
		for b in REBINDABLE:
			if a == b:
				continue
			var shared := false
			for da in bindings.get(a, []):
				if da in bindings.get(b, []):
					shared = true
					break
			if shared:
				if not out.has(a):
					out[a] = []
				out[a].append(b)
	return out

static func rebind_primary(bindings: Dictionary, action: String, ev: InputEvent) -> Dictionary:
	var out := bindings.duplicate(true)
	var list: Array = out.get(action, []).duplicate()
	var d := event_to_dict(ev)
	if list.is_empty():
		list.append(d)
	else:
		list[0] = d
	out[action] = list
	return out

## Abstract aim source. Contract: world_point(canvas, origin) returns the world-space point the
## player aims at. Gameplay only calls this; a future StickAimSource returns origin + stick_dir*reach.
class MouseAimSource extends RefCounted:
	func world_point(canvas: CanvasItem, _origin: Vector2) -> Vector2:
		var local := canvas.get_local_mouse_position()
		return canvas.world_from_local(local) if canvas.has_method("world_from_local") else local

## AD-254: right-stick deadzone from data, clamped to 0.2..0.3 (fallback 0.25).
static func aim_deadzone() -> float:
	var v = gamepad_data().get("aim_deadzone", 0.25)
	return clampf(float(v), 0.2, 0.3) if typeof(v) == TYPE_INT or typeof(v) == TYPE_FLOAT else 0.25

## AD-254: world distance from the actor at which a stick aim point is placed (data, fallback 200).
static func aim_reach() -> float:
	var v = gamepad_data().get("aim_reach", 200.0)
	return clampf(float(v), 50.0, 1000.0) if typeof(v) == TYPE_INT or typeof(v) == TYPE_FLOAT else 200.0

## Stick vector -> aim direction; inside the deadzone the last direction is kept.
static func stick_aim(stick: Vector2, deadzone: float, last_dir: Vector2) -> Vector2:
	return stick.normalized() if stick.length() > deadzone else last_dir

## Right-stick aim that falls back to the mouse: an active stick wins, a moving mouse takes over,
## and with no pad (or an untouched stick) the result is exactly the mouse source's.
class StickAimSource extends RefCounted:
	var last_dir := Vector2.RIGHT
	var _ia = load("res://ui/input_actions.gd") # inner classes cannot call the outer statics directly
	var _mouse := MouseAimSource.new()
	var _use_stick := false
	var _last_mouse := Vector2.INF

	func read_stick() -> Vector2:
		var best := Vector2.ZERO
		var pads: Array = Input.get_connected_joypads()
		for pad in pads:
			var v := Vector2(Input.get_joy_axis(pad, JOY_AXIS_RIGHT_X), Input.get_joy_axis(pad, JOY_AXIS_RIGHT_Y))
			if v.length() > best.length():
				best = v
		return best

	func world_point(canvas: CanvasItem, origin: Vector2) -> Vector2:
		var stick := read_stick()
		var mouse_pos := canvas.get_global_mouse_position()
		var moved: bool = _last_mouse != Vector2.INF and mouse_pos != _last_mouse
		_last_mouse = mouse_pos
		if stick.length() > _ia.aim_deadzone():
			_use_stick = true
		elif moved:
			_use_stick = false
		if _use_stick:
			last_dir = _ia.stick_aim(stick, _ia.aim_deadzone(), last_dir)
			return origin + last_dir * _ia.aim_reach()
		return _mouse.world_point(canvas, origin)

## Edge-detects pressed trigger (joypad axis) casts: they bind as InputEventJoypadMotion, which
## repeats while held, so controllers poll this once per physics tick instead of using _input.
class PadAxisCastPoll extends RefCounted:
	var _ia = load("res://ui/input_actions.gd")
	var _held := {}

	## Cast slot whose axis binding crossed 0.5 since the last poll, or -1.
	func poll() -> int:
		var found := -1
		for i in _ia.CAST_ACTIONS.size():
			var down := false
			if InputMap.has_action(_ia.CAST_ACTIONS[i]):
				for ev in InputMap.action_get_events(_ia.CAST_ACTIONS[i]):
					if ev is InputEventJoypadMotion:
						for pad in Input.get_connected_joypads():
							down = down or Input.get_joy_axis(pad, ev.axis) * (-1.0 if ev.axis_value < 0.0 else 1.0) >= 0.5
			if down and not _held.get(i, false) and found < 0:
				found = i
			_held[i] = down
		return found

static func stick_aim_source():
	return StickAimSource.new()

static func default_aim_source():
	return stick_aim_source()

static func event_text(ev) -> String:
	if ev == null:
		return TranslationServer.translate("settings.controls.unbound")
	if ev is InputEventKey and ev.physical_keycode != 0:
		var code: int = ev.physical_keycode if DisplayServer.get_name() == "headless" else DisplayServer.keyboard_get_keycode_from_physical(ev.physical_keycode)
		return OS.get_keycode_string(code if code != KEY_NONE else ev.physical_keycode)
	if ev is InputEventJoypadButton:
		return TranslationServer.translate("settings.controls.pad_button") % ev.button_index
	if ev is InputEventJoypadMotion:
		return TranslationServer.translate("settings.controls.pad_axis") % [ev.axis, "-" if ev.axis_value < 0.0 else "+"]
	return ev.as_text()

## First bound event of an action as display text (follows rebinding).
static func action_text(action: String) -> String:
	var events := InputMap.action_get_events(action) if InputMap.has_action(action) else []
	return event_text(events[0] if not events.is_empty() else null)
