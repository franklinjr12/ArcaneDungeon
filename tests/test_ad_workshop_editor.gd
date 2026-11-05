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

	# AD-135: any-form modifiers, trigger switching, reason keys
	var unlocked_all: Array = flow.session.sim.registry.get_ids()
	flow.run.unlocked = unlocked_all.duplicate()
	flow.editor.cancel()
	t.check(flow.open_editor(2)["ok"],"AD-135 reopen slot 4")
	var ed = flow.editor
	ed.set_root("essence.fire","form.projectile")
	ed.toggle_modifier("mod.chain")
	ed.toggle_modifier("mod.split")
	var beam: Dictionary = ed.set_root("essence.fire","form.beam")
	t.check(beam["ok"] and ed.draft["root"]["modifier_ids"]==["mod.chain"],"AD-135 beam keeps mod.chain and drops mod.split")
	t.check(not ed.can_attach("mod.split")["ok"] and ed.can_attach("mod.split")["reason_key"]=="editor.issue.modifier_projectile_only","AD-135 can_attach split on beam")
	t.check(ed.can_attach("trigger.timer")["ok"] and not ed.can_attach("trigger.on_hit")["ok"],"AD-135 beam allows timer, not on_hit")
	ed.set_trigger(true,"essence.water","trigger.timer")
	ed.set_trigger(true,"essence.water","trigger.on_kill")
	t.equal(ed.draft["on_hit"]["trigger_id"],"trigger.on_kill","AD-135 set_trigger switches trigger id")
	t.equal(ed.draft["on_hit"]["payload"]["essence_id"],"essence.water","AD-135 switch keeps payload")
	ed.set_root("essence.fire","form.burst")
	t.check(ed.draft.has("on_hit"),"AD-135 on_kill survives burst")
	ed.set_trigger(true,"essence.water","trigger.on_expire")
	var bad_burst: Dictionary = ed.set_root("essence.fire","form.burst")
	t.check(not ed.draft.has("on_hit") and bad_burst["ok"],"AD-135 lasting_only trigger dropped on burst")
	ed.set_root("essence.fire","form.beam")
	ed.set_trigger(true,"essence.water","trigger.on_hit")
	var inc: Dictionary = ed.validate()
	t.check(not inc["ok"] and inc["issues"][0]["reason_key"]=="editor.issue.trigger_projectile_only","AD-135 on_hit on beam reason")
	ed.set_trigger(true,"essence.water","trigger.timer")
	ed.set_root("essence.fire","form.burst")
	ed.draft["on_hit"] = {"trigger_id":"trigger.timer","payload":{"essence_id":"essence.water","manifestation_id":"form.burst","modifier_ids":[],"params":{}}}
	t.equal(ed.issue_reason_key(ed.validate()["issues"][0]),"editor.issue.trigger_needs_lasting","AD-135 timer on burst reason")
	t.equal(ed.issue_reason_key({"code":"PAYLOAD_FORM_INVALID"}),"editor.issue.payload_must_be_burst","AD-135 payload form key")
	t.equal(ed.issue_reason_key({"code":"PAYLOAD_MODIFIER_FORBIDDEN"}),"editor.issue.payload_no_modifiers","AD-135 payload modifier key")
	t.equal(ed.issue_reason_key({"code":"COMPLEXITY_EXCEEDED"}),"editor.issue.complexity_exceeded","AD-135 complexity key")
	t.equal(ed.issue_reason_key({"code":"RUNE_LOCKED"}),"editor.issue.rune_locked","AD-135 locked key")
	t.equal(ed.issue_reason_key({"code":"MODIFIER_DUPLICATE"}),"editor.issue.modifier_duplicate","AD-135 duplicate key")
	t.equal(ed.issue_reason_key({"code":"NOPE"}),"editor.issue.generic","AD-135 generic fallback")
	var csv := FileAccess.get_file_as_string("res://i18n/strings_en.csv")
	var keys: Array = ["editor.issue.generic"]
	for code in ed.ISSUE_KEYS:
		keys.append("editor.issue."+code.to_lower())
	for k in ["modifier_projectile_only","trigger_projectile_only","trigger_needs_lasting","payload_must_be_burst","payload_no_modifiers","complexity_exceeded","rune_locked","modifier_duplicate"]:
		keys.append("editor.issue."+k)
	for k in keys:
		t.check(csv.contains("\n"+k+","),"AD-135 CSV has "+k)
