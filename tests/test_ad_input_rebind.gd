extends RefCounted
## AD-125: rebindable input model, persistence, conflicts, action-only gameplay.
const Service = preload("res://game/core/save_service.gd")
const IA = preload("res://ui/input_actions.gd")
const Settings = preload("res://game/core/settings.gd")
const DIR := "user://test_ad_input_rebind_1/"

func _key(code: int) -> InputEventKey:
	var ev := InputEventKey.new()
	ev.physical_keycode = code
	return ev

func _clean() -> void:
	DirAccess.make_dir_recursive_absolute(DIR)
	for f in DirAccess.get_files_at(DIR):
		DirAccess.remove_absolute(DIR + f)

func run(t) -> void:
	IA.reset_to_defaults()
	_clean()
	var k := _key(KEY_K)
	var svc = Service.new()
	svc.set_base_dir(DIR)
	svc.settings.bindings = IA.rebind_primary(IA.current_bindings(),"cast_slot_3",k)
	svc.settings.apply_bindings()
	t.equal(svc.save_settings(),OK,"AD-125 bindings saved")
	IA.reset_to_defaults()
	var svc2 = Service.new()
	svc2.set_base_dir(DIR)
	svc2.settings.apply_bindings()
	var evs := InputMap.action_get_events("cast_slot_3")
	t.check(evs.size() > 0 and IA.events_equal(evs[0],k),"AD-125 rebind persists across restart")
	t.check(InputMap.event_is_action(_key(KEY_K),"cast_slot_3"),"AD-125 rebound key matches action")
	var up := InputMap.action_get_events("move_up")
	t.check(up.size() >= 2,"AD-125 move_up keeps secondary binding")
	# conflicts
	IA.reset_to_defaults()
	t.equal(IA.find_conflicts(IA.current_bindings()).size(),0,"AD-125 defaults have no conflicts")
	var dash_to_interact := IA.rebind_primary(IA.current_bindings(),"dash",InputMap.action_get_events("interact")[0])
	var c := IA.find_conflicts(dash_to_interact)
	t.check(c.has("dash") and c.has("interact") and "interact" in c["dash"],"AD-125 conflict flagged both ways")
	# reset
	IA.apply_bindings(svc2.settings.bindings)
	IA.reset_to_defaults()
	var d := InputMap.action_get_events("cast_slot_3")
	t.check(IA.events_equal(d[0],IA.default_events("cast_slot_3")[0]) and not IA.events_equal(d[0],k),"AD-125 reset restores defaults")
	# invalid config
	var cfg := ConfigFile.new()
	cfg.set_value("controls","bogus_action",[{"type":"key","physical_keycode":65}])
	cfg.set_value("controls","dash","notarray")
	cfg.set_value("controls","interact",[{"type":"nope"}])
	cfg.set_value("controls","pause",[{"type":"key","physical_keycode":65}])
	var s := Settings.new()
	s.from_config(cfg)
	t.equal(s.bindings.keys(),["pause"],"AD-125 invalid config entries dropped")
	# action-only gameplay
	var f := FileAccess.open("res://ui/run_controller.gd",FileAccess.READ)
	var src := f.get_as_text()
	f.close()
	for tok in ["KEY_","keycode","MOUSE_BUTTON_","button_index","get_local_mouse_position"]:
		t.check(not src.contains(tok),"AD-125 run_controller has no raw token " + tok)
	# joypad round trip
	var jb := InputEventJoypadButton.new()
	jb.button_index = JOY_BUTTON_A
	t.check(IA.events_equal(jb,IA.dict_to_event(IA.event_to_dict(jb))),"AD-125 joy button round-trip")
	var ja := InputEventJoypadMotion.new()
	ja.axis = JOY_AXIS_LEFT_X
	ja.axis_value = -0.7
	var back = IA.dict_to_event(IA.event_to_dict(ja))
	t.check(back != null and back.axis == JOY_AXIS_LEFT_X and back.axis_value == -1.0,"AD-125 joy axis round-trip")
	IA.reset_to_defaults()
	_clean()
	DirAccess.remove_absolute(DIR)
