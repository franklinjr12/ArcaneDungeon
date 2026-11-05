extends RefCounted
## AD-133: Chain, Expand and Rapid modifiers (compile-time scaling and validation).
const Runner = preload("res://magic/runtime/spell_runner.gd")

const FORMS := ["form.projectile","form.burst","form.orb","form.beam","form.field"]
const NEW_MODS := ["mod.chain","mod.expand","mod.rapid"]

func _formula(form: String, modifiers: Array = [], essence: String = "essence.fire") -> Dictionary:
	return {"schema_version":2,"formula_id":"test.%s.%s" % [form,"_".join(modifiers)],"display_name":form,
		"root":{"essence_id":essence,"manifestation_id":form,"modifier_ids":modifiers,"params":{}}}

func _plan(form: String, modifiers: Array) -> Dictionary:
	var r = Runner.new(133)
	var equipped: Dictionary = r.equip(0,_formula(form,modifiers))
	if not equipped["ok"]:
		printerr("equip failed: ",equipped)
		return {}
	return r.loadout.get_plan(0).snapshot()

func run(t) -> void:
	_compile(t)
	_expand(t)
	_rapid(t)
	_order(t)

func _compile(t) -> void:
	var r = Runner.new(133)
	for form in FORMS:
		for mod in NEW_MODS:
			t.check(r.equip(0,_formula(form,[mod]))["ok"],"AD-133 %s + %s compiles" % [form,mod])
	var homing: Dictionary = r.equip(1,_formula("form.beam",["mod.homing"]))
	t.contains_issue(homing["issues"],"MODIFIER_INCOMPATIBLE","AD-133 homing on beam still incompatible")
	var payload := _formula("form.projectile")
	payload["on_hit"] = {"trigger_id":"trigger.on_hit","payload":{"essence_id":"essence.fire","manifestation_id":"form.burst","modifier_ids":["mod.chain"],"params":{}}}
	t.contains_issue(r.equip(2,payload)["issues"],"PAYLOAD_MODIFIER_FORBIDDEN","AD-133 payload modifier still forbidden")

func _approx(a, b) -> bool:
	return absf(float(a) - float(b)) < 0.001

func _expand(t) -> void:
	for form in FORMS:
		var plain := _plan(form,[])
		var plan := _plan(form,["mod.expand"])
		var p: Dictionary = plain_params(plain)
		var q: Dictionary = plan_params(plan)
		var scaled: Array = {"form.projectile":["radius","speed"],"form.burst":["burst_radius"],"form.orb":["orb_radius","angular_speed"],
			"form.beam":["beam_length","tick_interval_ticks"],"form.field":["field_radius","tick_interval_ticks"]}[form]
		var factors: Dictionary = {"radius":1.5,"speed":0.7,"burst_radius":1.5,"orb_radius":1.5,"angular_speed":0.7,"beam_length":1.5,"field_radius":1.5}
		for key in scaled:
			if key == "tick_interval_ticks":
				t.equal(int(q[key]),ceili(float(p[key]) / 0.7 - 0.0001),"AD-133 %s expand %s" % [form,key])
			else:
				t.check(_approx(q[key],minf(float(p[key]) * factors[key],_max_of(plan,key))),"AD-133 %s expand %s scaled" % [form,key])
		if form == "form.burst":
			t.equal(int(plan["cooldown_ticks"]),ceili(float(plain["cooldown_ticks"]) / 0.7 - 0.0001),"AD-133 burst expand slows cooldown")

func plain_params(plan: Dictionary) -> Dictionary:
	return plan["root"]["params"]

func plan_params(plan: Dictionary) -> Dictionary:
	return plan["root"]["params"]

func _max_of(plan: Dictionary, key: String) -> float:
	return float(plan["root"]["manifestation"]["params"][key]["max"])

func _rapid(t) -> void:
	for form in FORMS:
		var plain := _plan(form,[])
		var plan := _plan(form,["mod.rapid"])
		t.check(int(plan["cooldown_ticks"]) < int(plain["cooldown_ticks"]),"AD-133 %s rapid shortens cooldown" % form)
		t.check(_approx(plan["root"]["params"]["base_damage"],float(plain["root"]["params"]["base_damage"]) * 0.7),"AD-133 %s rapid damage x0.7" % form)

func _order(t) -> void:
	for form in FORMS:
		var a := _plan(form,["mod.chain","mod.expand","mod.rapid"])
		var b := _plan(form,["mod.rapid","mod.expand","mod.chain"])
		t.equal(a["root"]["params"],b["root"]["params"],"AD-133 %s modifier order has no effect on params" % form)
		t.equal(a["cooldown_ticks"],b["cooldown_ticks"],"AD-133 %s modifier order has no effect on cooldown" % form)
