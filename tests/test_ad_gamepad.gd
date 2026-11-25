extends SceneTree
## AD-254 step 1: gamepad defaults and right-stick aim acceptance tests (fail until steps 2-3 land).
const TestContext = preload("res://tests/test_context.gd")
const IA = preload("res://ui/input_actions.gd")

const ACTIONS := ["move_up", "move_down", "move_left", "move_right", "cast_slot_1", "cast_slot_2",
		"cast_slot_3", "cast_slot_4", "dash", "interact", "pause"]

## Discovered by run_tests.gd (run(t)) and also runnable directly: --script res://tests/test_ad_gamepad.gd
func _initialize() -> void:
	var t := TestContext.new()
	run(t)
	print("TEST SUMMARY: %d passed / %d failed" % [t.passed, t.failed])
	for failure in t.failures:
		printerr("FAILED: ", failure)
	if t.failed == 0:
		print("PASS")
	quit(1 if t.failed > 0 else 0)

func run(t) -> void:
	test_ad_254_a_every_gameplay_action_has_default_pad_event(t)
	test_ad_254_b_right_stick_drives_aim_and_deadzone_holds_last(t)

func _has_method(name: String) -> bool:
	var script: Script = IA
	for m in script.get_script_method_list():
		if m["name"] == name:
			return true
	return false

func _pad_events(events: Array) -> Array:
	var out := []
	for ev in events:
		if ev is InputEventJoypadButton or ev is InputEventJoypadMotion:
			out.append(ev)
	return out

func _has_axis(events: Array, axis: int) -> bool:
	for ev in events:
		if ev is InputEventJoypadMotion and ev.axis == axis:
			return true
	return false

func test_ad_254_a_every_gameplay_action_has_default_pad_event(t) -> void:
	IA.reset_to_defaults()
	for action in ACTIONS:
		var defaults: Array = IA.default_events(action)
		var pad := _pad_events(defaults)
		t.check(pad.size() >= 1, "AD-254 default_events(%s) has a joypad event" % action)
		t.check(_pad_events(InputMap.action_get_events(action)).size() >= 1,
				"AD-254 InputMap %s has a joypad event after reset_to_defaults" % action)
		for ev in pad:
			var back = IA.dict_to_event(IA.event_to_dict(ev))
			t.check(back != null and IA.events_equal(back, ev),
					"AD-254 %s pad event round-trips through event_to_dict/dict_to_event" % action)
	t.check(IA.find_conflicts(IA.current_bindings()).size() == 0,
			"AD-254 default bindings (keyboard + pad) have no conflicts")
	for a in ["move_left", "move_right"]:
		t.check(_has_axis(IA.default_events(a), JOY_AXIS_LEFT_X), "AD-254 %s uses left stick X" % a)
	for a in ["move_up", "move_down"]:
		t.check(_has_axis(IA.default_events(a), JOY_AXIS_LEFT_Y), "AD-254 %s uses left stick Y" % a)
	t.check(_has_axis(IA.default_events("cast_slot_1"), JOY_AXIS_TRIGGER_RIGHT),
			"AD-254 cast_slot_1 uses the right trigger")
	t.check(_has_axis(IA.default_events("cast_slot_2"), JOY_AXIS_TRIGGER_LEFT),
			"AD-254 cast_slot_2 uses the left trigger")

func test_ad_254_b_right_stick_drives_aim_and_deadzone_holds_last(t) -> void:
	var has_aim := _has_method("stick_aim")
	var has_dz := _has_method("aim_deadzone")
	t.check(has_aim, "AD-254 IA.stick_aim exists")
	t.check(has_dz, "AD-254 IA.aim_deadzone exists")
	t.check(_has_method("stick_aim_source"), "AD-254 IA.stick_aim_source exists")
	var mouse = IA.default_aim_source()
	t.check(mouse != null and mouse.has_method("world_point"),
			"AD-254 default_aim_source still returns a mouse source with world_point")
	if not (has_aim and has_dz):
		return
	var ia: Script = IA  # dynamic calls: these statics do not exist until step 3
	var dz: float = ia.call("aim_deadzone")
	t.check(dz >= 0.2 and dz <= 0.3, "AD-254 aim_deadzone %.3f within 0.2..0.3" % dz)
	t.check(ia.call("stick_aim", Vector2(1, 0), dz, Vector2(0, 1)).is_equal_approx(Vector2(1, 0)),
			"AD-254 stick (1,0) aims (1,0)")
	t.check(ia.call("stick_aim", Vector2(0, -0.8), dz, Vector2(1, 0)).is_equal_approx(Vector2(0, -1)),
			"AD-254 stick (0,-0.8) aims (0,-1) normalized")
	t.check(ia.call("stick_aim", Vector2(0.1, 0.05), dz, Vector2(0, 1)).is_equal_approx(Vector2(0, 1)),
			"AD-254 stick inside deadzone holds last direction")
	t.check(ia.call("stick_aim", Vector2.ZERO, dz, Vector2(-1, 0)).is_equal_approx(Vector2(-1, 0)),
			"AD-254 stick at rest holds last direction")
	t.check(ia.call("stick_aim", Vector2(dz + 0.05, 0), dz, Vector2(0, 1)).is_equal_approx(Vector2(1, 0)),
			"AD-254 stick just above deadzone is followed")
