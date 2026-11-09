extends RefCounted
## AD-185: binding-aware room 1 strip, telegraph tip, Sigil Desk pointer, Tips toggle.
const Prompts = preload("res://ui/onboarding_prompts.gd")
const InputActions = preload("res://ui/input_actions.gd")
const Flow = preload("res://world/run_flow.gd")
const NEW_IDS := ["telegraph", "spells_are_runes"]

func run(t) -> void:
	var p = Prompts.new()
	for id in NEW_IDS:
		var s := str(p.tips.get(id, ""))
		t.check(not s.is_empty() and s.length() <= Prompts.MAX_CHARS and not s.contains("{"), "AD-185 tip loads, fits, expanded: " + id)
	var room1 := str(p.tips["room1"])
	t.check(not room1.contains("{") and room1.length() <= Prompts.MAX_CHARS, "AD-185 room1 expanded and fits")
	t.check(room1.contains(InputActions.action_text("dash")) and room1.contains(InputActions.action_text("cast_slot_1")), "AD-185 room1 shows current bindings")
	var old_events := InputMap.action_get_events("dash")
	InputMap.action_erase_events("dash")
	var ev := InputEventKey.new()
	ev.physical_keycode = KEY_J
	InputMap.action_add_event("dash", ev)
	p.refresh_bindings()
	t.check(str(p.tips["room1"]).contains(InputActions.event_text(ev)), "AD-185 rebinding updates room1")
	t.check(str(p.tips["telegraph"]).contains(InputActions.event_text(ev)), "AD-185 rebinding updates telegraph")
	InputMap.action_erase_events("dash")
	for e in old_events:
		InputMap.action_add_event("dash", e)

	var q = Prompts.new()
	q.tick(1000)
	t.check(q.trigger("room1") != "", "AD-185 room1 shows")
	t.check(q.trigger("telegraph") != "", "AD-185 telegraph shows")
	t.equal(q.current, "telegraph", "AD-185 telegraph interrupts room1")
	t.check(q.is_timed_active(), "AD-185 telegraph is timed")
	q.tick(1000 + 5900)
	t.equal(q.current, "telegraph", "AD-185 telegraph stays until deadline")
	q.tick(1000 + 6000)
	t.equal(q.current, "room1", "AD-185 room1 returns after telegraph")
	t.check(not q.is_timed_active(), "AD-185 timer cleared")
	var d = Prompts.new()
	d.tick(0)
	d.trigger("room1")
	d.trigger("telegraph")
	d.dismiss()
	d.tick(60000)
	t.equal(d.current, "", "AD-185 dismiss during timed tip does not restore room1")
	t.equal(d.text(), "", "AD-185 dismissed strip stays gone")

	# Once per profile, through SaveService.
	var w = Prompts.new()
	for id in NEW_IDS:
		t.check(w.trigger(id) != "", "AD-185 first trigger: " + id)
		t.equal(w.trigger(id), "", "AD-185 once only: " + id)
	var dir := "user://ad185_test/"
	DirAccess.make_dir_recursive_absolute(dir)
	var svc = preload("res://game/core/save_service.gd").new()
	svc.set_base_dir(dir)
	svc.profile["stats"]["onboarding_seen"] = w.seen
	t.equal(svc.save_profile(), OK, "AD-185 profile saved")
	var svc2 = preload("res://game/core/save_service.gd").new()
	svc2.set_base_dir(dir)
	svc2.load_profile()
	var n = Prompts.new()
	n.load_seen(svc2.profile["stats"].get("onboarding_seen", []))
	for id in NEW_IDS:
		t.equal(n.trigger(id), "", "AD-185 persisted tip suppressed: " + id)
	svc.free()
	svc2.free()
	for f in DirAccess.get_files_at(dir):
		DirAccess.remove_absolute(dir + f)
	DirAccess.remove_absolute(dir)

	# Tips toggle.
	var o = Prompts.new()
	o.enabled = false
	t.equal(o.trigger("room1"), "", "AD-185 disabled: no trigger")
	t.check(not o.seen.has("room1"), "AD-185 disabled: not marked seen")
	o.note_telegraph()
	o.note_workshop(2)
	t.equal(o.next_hint(), "", "AD-185 disabled: no hint")
	o.enabled = true
	t.check(o.trigger("room1") != "", "AD-185 enabled again: tip can trigger")
	o.enabled = false
	t.equal(o.text(), "", "AD-185 disabled: no text")

	_ui_section(t)

func _ui_section(t) -> void:
	var root: Node = (Engine.get_main_loop() as SceneTree).root
	var save = root.get_node_or_null("SaveService")
	if save == null:
		save = preload("res://game/core/save_service.gd").new()
		save.name = "SaveService"
		root.add_child(save)
	var old_dir: String = save.base_dir
	var old_profile = save.profile
	var dir := "user://ad185_ui/"
	DirAccess.make_dir_recursive_absolute(dir)
	for name in DirAccess.get_files_at(dir):
		DirAccess.remove_absolute(dir + name)
	save.set_base_dir(dir)
	save.profile = save.default_profile()
	var scene: Node = load("res://scenes/run.tscn").instantiate()
	scene.show_dev_tools = false
	root.add_child(scene)
	var a: Node = scene
	a._update_labels()
	t.check(a.flow.prelude and a.guide.current == "spells_are_runes", "AD-185 UI desk shows the runes pointer")
	a.flow.finish_prelude(true)
	a._after_desk(true)
	a._update_labels()
	t.equal(a.guide.current, "room1", "AD-185 UI room 1 strip after the desk")
	t.check(a.flow.session != null and not a.flow.session.enemies.is_empty(), "AD-185 UI room 1 has enemies")
	if a.flow.session != null and not a.flow.session.enemies.is_empty():
		a.flow.session.enemies[0].state = "windup"
		a._update_labels()
		t.equal(a.guide.current, "telegraph", "AD-185 UI telegraph at first windup")
	a.queue_free()
	save.set_base_dir(old_dir)
	save.profile = old_profile
