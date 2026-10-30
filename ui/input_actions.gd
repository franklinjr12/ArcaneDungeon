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

static func debug_keys_enabled() -> bool:
	return OS.is_debug_build()
