extends RefCounted
## AD-134: On Kill, On Expire and Timer triggers (data, validation and compile). Values are proposed.
const Runner = preload("res://magic/runtime/spell_runner.gd")

const FORMS := ["form.projectile","form.burst","form.orb","form.beam","form.field"]
const LASTING := ["form.projectile","form.orb","form.beam","form.field"]
const NEW_TRIGGERS := ["trigger.on_kill","trigger.on_expire","trigger.timer"]

func _formula(form: String, trigger: String = "", payload_form: String = "form.burst", payload_mods: Array = []) -> Dictionary:
	var formula := {"schema_version":2,"formula_id":"test.%s.%s" % [form,trigger],"display_name":form,
		"root":{"essence_id":"essence.fire","manifestation_id":form,"modifier_ids":[],"params":{}}}
	if trigger != "":
		formula["on_hit"] = {"trigger_id":trigger,"payload":{"essence_id":"essence.water","manifestation_id":payload_form,"modifier_ids":payload_mods,"params":{}}}
	return formula

func run(t) -> void:
	_compile(t)
	_rejections(t)
	_payload_rules(t)
	_plan_snapshot(t)

func _compile(t) -> void:
	var r = Runner.new(134)
	for form in FORMS:
		t.check(r.equip(0,_formula(form,"trigger.on_kill"))["ok"],"AD-134 On Kill compiles on %s" % form)
	for trigger in ["trigger.on_expire","trigger.timer"]:
		for form in LASTING:
			t.check(r.equip(0,_formula(form,trigger))["ok"],"AD-134 %s compiles on %s" % [trigger,form])
	t.check(r.equip(0,_formula("form.projectile","trigger.on_hit"))["ok"],"AD-134 On Hit still compiles on projectile")

func _rejections(t) -> void:
	var r = Runner.new(134)
	for trigger in ["trigger.on_expire","trigger.timer"]:
		t.contains_issue(r.equip(0,_formula("form.burst",trigger))["issues"],"TRIGGER_INCOMPATIBLE","AD-134 %s rejected on burst" % trigger)
	t.contains_issue(r.equip(0,_formula("form.orb","trigger.on_hit"))["issues"],"TRIGGER_INCOMPATIBLE","AD-134 On Hit on orb still rejected")
	var bogus: Dictionary = r.equip(0,_formula("form.projectile","trigger.bogus"))
	var codes: Array = []
	for issue in bogus["issues"]:
		codes.append(issue["code"])
	t.check(not bogus["ok"] and ("RUNE_UNKNOWN" in codes or "TRIGGER_UNKNOWN" in codes),"AD-134 unknown trigger rejected")

func _payload_rules(t) -> void:
	var r = Runner.new(134)
	for trigger in NEW_TRIGGERS:
		t.contains_issue(r.equip(0,_formula("form.projectile",trigger,"form.orb"))["issues"],"PAYLOAD_FORM_INVALID","AD-134 %s non-burst payload rejected" % trigger)
		t.contains_issue(r.equip(0,_formula("form.projectile",trigger,"form.burst",["mod.chain"]))["issues"],"PAYLOAD_MODIFIER_FORBIDDEN","AD-134 %s payload modifier rejected" % trigger)

func _plan_snapshot(t) -> void:
	var r = Runner.new(134)
	r.equip(0,_formula("form.projectile","trigger.timer"))
	var plan: Dictionary = r.loadout.get_plan(0).snapshot()
	t.equal(int(plan["on_hit"]["trigger_params"]["interval_ticks"]),30,"AD-134 timer plan interval_ticks default")
	r.equip(1,_formula("form.projectile","trigger.on_kill"))
	t.equal(r.loadout.get_plan(1).snapshot()["on_hit"]["trigger_params"],{},"AD-134 on kill has no trigger params")
	r.equip(2,_formula("form.projectile","trigger.on_hit"))
	var on_hit_mana := int(r.loadout.get_plan(2).snapshot()["mana_cost"])
	var costs := {"trigger.on_kill":6,"trigger.on_expire":5,"trigger.timer":7}
	for trigger in NEW_TRIGGERS:
		r.equip(3,_formula("form.projectile",trigger))
		var with_trigger := int(r.loadout.get_plan(3).snapshot()["mana_cost"])
		t.equal(with_trigger - on_hit_mana,int(costs[trigger]) - 5,"AD-134 %s mana includes trigger rune cost" % trigger)
