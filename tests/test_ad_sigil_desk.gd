extends RefCounted
## AD-130: Sigil Desk prelude flow (opt-in, flow-level).
const Flow = preload("res://world/run_flow.gd")
const Prompts = preload("res://ui/onboarding_prompts.gd")
const SEED := 20261022

func _desk_flow() -> Object:
	var f = Flow.new(SEED,Flow.CONFIG_V2)
	f.enter_prelude()
	return f

func _build_slot4(f, t) -> void:
	var opened: Dictionary = f.open_editor(2)
	t.check(opened["ok"] or opened.get("issues") != null,"AD-130 slot 4 editor opens")
	f.editor.set_root("essence.lightning","form.projectile")
	if not "mod.split" in f.editor.draft["root"]["modifier_ids"]:
		f.editor.toggle_modifier("mod.split")

func _snap(f) -> String:
	return JSON.stringify(f.snapshot())

func _play(seed_value: int) -> String:
	var f = Flow.new(seed_value,Flow.CONFIG_V2)
	f.enter_prelude()
	f.open_editor(2)
	f.editor.set_root("essence.lightning","form.projectile")
	f.editor.toggle_modifier("mod.split")
	f.close_editor(true,10.0)
	f.test_cast(3,Vector2.RIGHT)
	f.try_exit(Vector2.ZERO)
	return _snap(f)

func run(t) -> void:
	var plain = Flow.new(SEED,Flow.CONFIG_V2)
	t.equal(plain.state,"fighting","AD-130 default flow still starts in combat")
	t.check(not plain.prelude,"AD-130 prelude off by default")
	t.check(plain.prelude_available(),"AD-130 v2 config offers the prelude")
	t.check(not Flow.new(SEED).prelude_available(),"AD-130 v1 config has no prelude")
	var v1 = Flow.new(SEED)
	t.equal(v1.enter_prelude().get("reason"),"PRELUDE_UNAVAILABLE","AD-130 v1 enter_prelude refused")

	var f = Flow.new(SEED,Flow.CONFIG_V2)
	var entered: Dictionary = f.enter_prelude()
	t.check(entered["ok"],"AD-130 enter_prelude ok")
	t.equal(f.state,"workshop","AD-130 desk is a workshop state")
	t.check(f.prelude and f.merchant == null,"AD-130 prelude flag set, no shop")
	t.equal(f.run.sequence_index,0,"AD-130 sequence index unchanged")
	for id in ["essence.lightning","form.projectile","mod.split"]:
		t.check(f.run.unlocked.has(id),"AD-130 rune granted: " + id)
	t.equal(f.finish_prelude(false).get("reason"),"PRELUDE_INCOMPLETE","AD-130 cannot finish before building")

	var opened: Dictionary = f.open_editor(2)
	t.check(opened.has("ok"),"AD-130 editor opens on slot 4")
	t.equal(f.editor.guided_next(),"essence.lightning","AD-130 guided starts with essence")
	f.editor.set_root("essence.lightning","form.projectile")
	t.equal(f.editor.guided_next(),"mod.split","AD-130 guided then asks for the modifier")
	t.check(not f.editor.guided_done(),"AD-130 guided not done yet")
	f.editor.toggle_modifier("mod.split")
	t.equal(f.editor.guided_next(),"","AD-130 guided complete")
	t.check(f.editor.guided_done(),"AD-130 guided done with a valid spell")
	t.equal(f.finish_prelude(false).get("reason"),"EDITOR_OPEN","AD-130 cannot leave with the editor open")
	t.check(f.close_editor(true,12.0)["ok"],"AD-130 slot 4 applies")
	t.equal(f.run.formulas.size(),3,"AD-130 three formulas after build")
	t.check(f.prelude_built and not f.prelude_ready(),"AD-130 built but test cast still required")
	t.check(not f.test_cast(1,Vector2.RIGHT).is_empty() and not f.prelude_tested,"AD-130 other slot does not count")
	f.enter_test_range()
	var cast: Dictionary = f.test_cast(3,Vector2.RIGHT)
	t.check(bool(cast["accepted"]) and f.prelude_tested,"AD-130 slot 4 test cast counted")
	t.check(f.prelude_ready(),"AD-130 prelude ready")
	var left: Dictionary = f.try_exit(Vector2.ZERO)
	t.check(left["ok"],"AD-130 door leads on")
	t.equal(f.state,"fighting","AD-130 room 1 is combat")
	t.equal(f.run.sequence_index,0,"AD-130 room 1 keeps sequence index 0")
	t.equal(str(f.room.values["id"]),str(f.rooms[0]["id"]),"AD-130 room 1 id")
	t.check(not f.prelude,"AD-130 prelude over")
	t.check(f.session.sim.loadout.slots[3]["compiled"] != null,"AD-130 slot 4 equipped in room 1")
	t.equal(f.open_editor(2).get("reason"),"COMBAT_LOCKED","AD-130 no editing in room 1")

	var g = Flow.new(SEED,Flow.CONFIG_V2)
	t.check(g.finish_prelude(true)["ok"] and g.state == "fighting","AD-130 skip path reaches room 1")
	# Combat room cleared (not workshop) still refuses editing.
	g.state = "cleared"
	t.equal(g.open_editor(2).get("reason"),"POLICY_WORKSHOP_ONLY","AD-130 editing stays workshop-only")

	t.equal(_play(SEED),_play(SEED),"AD-130 same actions give identical room-1 snapshot")

	var p = Prompts.new()
	p.prelude_active = true
	p.note_workshop(2)
	p.note_valid_edit()
	t.equal(p.next_hint(),"","AD-130 hints suppressed during prelude")
	t.equal(p.trigger("first_workshop"),"","AD-130 first_workshop suppressed during prelude")
	t.equal(p.note_prelude_done(),["workshop_empty_slot","test_on_dummy"],"AD-130 desk marks hints seen")
	t.equal(p.note_prelude_done(),[],"AD-130 second call adds nothing")
	p.prelude_active = false
	p.note_workshop(2)
	t.equal(p.next_hint(),"","AD-130 taught hints stay quiet afterwards")
	t.check(p.trigger("first_workshop") != "","AD-130 first_workshop kept for the real workshop")
