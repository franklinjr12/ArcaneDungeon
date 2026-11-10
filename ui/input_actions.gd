extends RefCounted
## Input-map helpers shared by the arena and run controllers.
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

static func default_events(action: String) -> Array:
	var out: Array = []
	var setting = ProjectSettings.get_setting("input/" + action, null)
	if typeof(setting) == TYPE_DICTIONARY:
		for ev in setting.get("events", []):
			out.append(ev.duplicate())
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

static func apply_bindings(overrides: Dictionary) -> void:
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

static func default_aim_source():
	return MouseAimSource.new()

static func event_text(ev) -> String:
	if ev == null:
		return TranslationServer.translate("settings.controls.unbound")
	if ev is InputEventKey and ev.physical_keycode != 0:
		var code: int = ev.physical_keycode if DisplayServer.get_name() == "headless" else DisplayServer.keyboard_get_keycode_from_physical(ev.physical_keycode)
		return OS.get_keycode_string(code if code != KEY_NONE else ev.physical_keycode)
	return ev.as_text()

## First bound event of an action as display text (follows rebinding).
static func action_text(action: String) -> String:
	var events := InputMap.action_get_events(action) if InputMap.has_action(action) else []
	return event_text(events[0] if not events.is_empty() else null)
