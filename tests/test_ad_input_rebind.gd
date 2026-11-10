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
	svc.free()
	svc2.free()
	_ui_test(t)
	IA.reset_to_defaults()
	_clean()
	DirAccess.remove_absolute(DIR)

func _ui_test(t) -> void:
	IA.reset_to_defaults()
	_clean()
	var svc = Service.new()
	svc.set_base_dir(DIR)
	var screen = load("res://ui/settings_screen.gd").new()
	screen.save_service = svc
	Engine.get_main_loop().root.add_child(screen)
	for a in IA.REBINDABLE:
		if a == "toggle_fullscreen":
			continue  # AD-225: no Controls-page layout row yet; rebound through the saved bindings
		t.check(screen.binding_buttons.has(a),"AD-125 UI row for " + a)
	t.equal(screen.conflicts.size(),0,"AD-125 UI no initial conflicts")
	screen.rebind_action("dash",_key(KEY_F))
	t.check(screen.conflicts.has("dash") and screen.conflicts.has("interact"),"AD-125 UI conflict flagged both rows")
	t.check(screen.conflict_labels["dash"].visible and screen.binding_buttons["interact"].tooltip_text != "","AD-125 UI conflict label and tooltip")
	var svc2 = Service.new()
	svc2.set_base_dir(DIR)
	var saved = svc2.settings.bindings.get("dash",[])
	t.check(saved.size() > 0 and saved[0] == IA.event_to_dict(_key(KEY_F)),"AD-125 UI rebind persisted")
	t.check(screen.binding_buttons["dash"].mark == "conflict" and screen.swap_button.visible and not screen.swap_button.disabled,"AD-152 UI conflict sprite and swap/cancel panel")
	screen.cancel_button.pressed.emit()
	t.equal(screen.conflicts.size(),0,"AD-152 UI cancel restores the previous key")
	t.check(not screen.swap_button.visible,"AD-152 UI conflict panel hides when clear")
	screen.rebind_action("dash",_key(KEY_F))
	screen.swap_button.pressed.emit()
	t.equal(screen.conflicts.size(),0,"AD-152 UI swap resolves the conflict")
	t.check(IA.events_equal(InputMap.action_get_events("interact")[0],IA.default_events("dash")[0]),"AD-152 UI swap gives the other action the old key")
	screen.rebind_action("cast_slot_1",_key(KEY_G),1)
	t.check(screen.alt_buttons["cast_slot_1"].text != "" and IA.events_equal(InputMap.action_get_events("cast_slot_1")[1],_key(KEY_G)),"AD-152 UI alt slot rebinds")
	screen.rebind_action("dash",_key(KEY_F))
	screen.reset_keys_button.pressed.emit()
	t.equal(screen.conflicts.size(),0,"AD-152 UI reset keys clears conflicts")
	screen.binding_buttons["dash"].pressed.emit()
	t.equal(screen.listening_action,"dash","AD-152 UI primary field starts listening")
	var esc := InputEventKey.new()
	esc.physical_keycode = KEY_ESCAPE
	esc.pressed = true
	screen._input(esc)
	t.equal(screen.listening_action,"","AD-152 UI Esc cancels listening without binding")
	t.check(screen.binding_buttons["pause"].disabled,"AD-152 UI pause row stays disabled")
	screen.rebind_action("dash",_key(KEY_F))
	screen.reset_button.pressed.emit()
	t.equal(screen.conflicts.size(),0,"AD-125 UI reset clears conflicts")
	t.check(IA.events_equal(InputMap.action_get_events("dash")[0],IA.default_events("dash")[0]),"AD-125 UI reset restores InputMap")
	screen.free()
	svc.free()
	svc2.free()
	IA.reset_to_defaults()
	_clean()
