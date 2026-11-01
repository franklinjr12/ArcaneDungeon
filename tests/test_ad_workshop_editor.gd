extends RefCounted
## AD-023: editable preset slots incl. empty UI slot 4, cap-aware preview, rejection reasons.
const Flow = preload("res://world/run_flow.gd")
const Limits = preload("res://magic/runtime/spell_limits.gd")

func _workshop():
	var flow = Flow.new(20261029)
	flow.run.sequence_index = flow.config["rooms"].size()-2
	flow._enter_current()
	return flow

func _codes(issues: Array) -> Array:
	var codes: Array = []
	for issue in issues:
		codes.append(issue["code"])
	return codes

func run(t) -> void:
	var flow = _workshop()
	t.equal(flow.mode,"workshop","AD-023 reached workshop")
	t.equal(flow.run.formulas.size(),2,"AD-023 run starts with 2 presets")
	var opened: Dictionary = flow.open_editor(2)
	t.check(opened["ok"],"AD-023 empty slot 4 opens with valid starter draft")
	t.check(flow.editor.is_new,"AD-023 slot 4 draft is new")
	t.equal(flow.editor.draft["formula_id"],"custom.slot_3","AD-023 starter formula id")
	var limits = Limits.new()
	limits.load_defaults()
	var cap: int = limits.get_limit("max_complexity")
	var preview: Dictionary = flow.editor.validate()
	t.check(preview.has("mana") and preview.has("cooldown") and preview.has("complexity"),"AD-023 preview has cost, cooldown, complexity")
	t.equal(preview["complexity_cap"],cap,"AD-023 preview cap from spell_limits")
	flow.editor.cancel()
	flow.session.player.modal = false
	var probe = load("res://magic/editor/spell_editor.gd").new(flow.run,flow.session.sim.registry)
	t.equal(probe.open(3)["reason"],"SLOT_INVALID","AD-023 slot index 3 invalid")
	t.equal(probe.open(-1)["reason"],"SLOT_INVALID","AD-023 negative slot invalid")
	# (d) cancel leaves presets untouched
	t.equal(flow.run.formulas.size(),2,"AD-023 cancel does not append")
	# (b) locked rune
	t.check(flow.open_editor(2)["ok"],"AD-023 reopen slot 4")
	var bad: Dictionary = flow.editor.set_root("essence.fire","form.orb")
	t.check(not bad["ok"] and "RUNE_LOCKED" in _codes(bad["issues"]),"AD-023 locked orb rejected with reason")
	t.equal(flow.close_editor(true)["reason"],"FORMULA_INVALID","AD-023 invalid formula cannot be applied")
	t.equal(flow.run.formulas.size(),2,"AD-023 invalid apply does not append")
	# (c) valid apply + cast
	var good: Dictionary = flow.editor.set_root("essence.lightning","form.projectile")
	t.check(good["ok"],"AD-023 valid formula passes")
	t.check(flow.close_editor(true)["ok"],"AD-023 valid formula applies")
	t.equal(flow.run.formulas.size(),3,"AD-023 slot 4 persisted in run")
	t.equal(flow.session.sim.loadout.preview(3)["formula_id"],"custom.slot_3","AD-023 slot 4 equipped in session")
	t.check(flow.range_sim.loadout.slots[3]["formula_id"] == "custom.slot_3","AD-023 range loadout slot 4 compiled")
	t.check(flow.test_cast(3,Vector2.RIGHT)["accepted"],"AD-023 slot 4 casts in range")
	# (f) no neutral essence in palette
	for entry in flow.editor.available("essence"):
		t.check(entry["id"] != "essence.neutral","AD-023 palette excludes neutral")
