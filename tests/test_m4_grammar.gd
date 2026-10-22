extends RefCounted
## TASK-049: explicit v1 golden costs and full legal matrix, independent of sample files.
const Registry = preload("res://magic/data/rune_registry.gd")
const Compiler = preload("res://magic/compile/spell_compiler.gd")
const Runner = preload("res://magic/runtime/spell_runner.gd")
const Codec = preload("res://magic/compile/spell_codec.gd")
const ELEMENTS = ["essence.fire","essence.water","essence.lightning"]
const FORMS = ["form.projectile","form.burst","form.orb"]

static func formula(e: String, form: String, mods: Array = [], trigger := false) -> Dictionary:
	var data := {"schema_version":1,"formula_id":"matrix."+e+"."+form,
		"display_name":"Matrix","root":{"essence_id":e,"manifestation_id":form,
			"modifier_ids":mods.duplicate(),"params":{}}}
	if trigger:
		data["on_hit"] = {"trigger_id":"trigger.on_hit","payload":{
			"essence_id":"essence.lightning","manifestation_id":"form.burst","modifier_ids":[],"params":{}}}
	return data

func _has(issues: Array, code: String) -> bool:
	return issues.any(func(v):return v["code"]==code)

func run(t) -> void:
	var registry = Registry.new()
	t.check(registry.load_seed()["ok"],"TASK-049 registry seed valid")
	var compiler = Compiler.new(registry,12)
	var ids: Array = registry.get_ids()
	var expected_costs := {
		"essence.fire":[7,13,14],"essence.water":[6,12,13],"essence.lightning":[8,14,15]}
	var cooldowns := [2,8,9]
	for element in ELEMENTS:
		for k in FORMS.size():
			var f: Dictionary = formula(element,FORMS[k])
			var outcome: Dictionary = compiler.compile(f,ids)
			t.check(outcome["ok"],"TASK-049 grammar matrix "+element+" "+FORMS[k])
			if outcome["ok"]:
				var plan: Dictionary = outcome["compiled_spell"].snapshot()
				t.equal(plan["mana_cost"],expected_costs[element][k],"TASK-049 golden mana "+element+" "+FORMS[k])
				t.equal(plan["complexity"],1+(1 if k==0 else 2),"TASK-049 golden complexity "+element+" "+FORMS[k])
				t.equal(plan["cooldown_ticks"],cooldowns[k],"TASK-049 golden cooldown "+element+" "+FORMS[k])
				t.equal(plan["root"]["essence"]["id"],element,"TASK-049 golden compiled essence")
				t.equal(plan["root"]["manifestation"]["id"],FORMS[k],"TASK-049 golden compiled form")
				t.check(plan["on_hit"].is_empty(),"TASK-049 simple root has no surprise trigger")
				var again: Dictionary = compiler.compile(f,ids)
				t.equal(again["compiled_spell"].snapshot(),plan,"TASK-049 cache does not mutate plans")
	# Exact supported combinations, including element-agnostic triggers.
	for mod in ["mod.homing","mod.split","mod.pierce"]:
		for element in ELEMENTS:
			var checked: Dictionary = compiler.compile(formula(element,"form.projectile",[mod]),ids)
			t.check(checked["ok"],"TASK-049 legal "+mod+" on "+element)
			if checked["ok"]:
				t.equal(checked["compiled_spell"].snapshot()["root"]["modifiers"][0]["id"],mod,"TASK-049 modifier preserved")
	for element in ELEMENTS:
		var cascaded := formula(element,"form.projectile",[],true)
		var outcome: Dictionary = compiler.compile(cascaded,ids)
		t.check(outcome["ok"],"TASK-049 On Hit Burst accepted for "+element)
		if outcome["ok"]:
			t.equal(outcome["compiled_spell"].snapshot()["on_hit"]["effect"]["manifestation"]["id"],"form.burst",
				"TASK-049 child effect manifest is Burst")
	var golden := compiler.compile(formula("essence.fire","form.projectile",["mod.split"],true),ids)
	t.check(golden["ok"],"TASK-049 complete trigger combination compiles")
	if golden["ok"]:
		var snap: Dictionary = golden["compiled_spell"].snapshot()
		t.equal(snap["mana_cost"],30,"TASK-049 golden Fire Split On Hit Lightning Burst mana")
		t.equal(snap["complexity"],8,"TASK-049 golden Fire Split On Hit Lightning Burst complexity")
		t.equal(snap["cooldown_ticks"],8,"TASK-049 golden trigger cooldown")
		t.equal(snap["execution_phases"],["spawn","split","homing","collision","pierce","resolve","enqueue_trigger","drain_queue","cleanup"],
			"TASK-049 fixed runtime execution phases")
		t.check(not snap["modifier_order_affects_runtime"],"TASK-049 runtime modifier order fixed")
	# Error codes must remain stable as v1 contract.
	var bad := formula("essence.fire","form.burst",["mod.split"])
	t.check(_has(compiler.compile(bad,ids)["issues"],"MODIFIER_INCOMPATIBLE"),"TASK-049 modifier on Burst forbidden")
	bad = formula("essence.fire","form.projectile",["mod.split","mod.split"])
	t.check(_has(compiler.compile(bad,ids)["issues"],"MODIFIER_DUPLICATE"),"TASK-049 duplicate modifier forbidden")
	bad = formula("essence.fire","form.orb",[],true)
	t.check(_has(compiler.compile(bad,ids)["issues"],"TRIGGER_INCOMPATIBLE"),"TASK-049 trigger on Orb forbidden")
	bad = formula("essence.fire","form.projectile",[],true)
	bad["on_hit"].erase("payload")
	t.check(not compiler.compile(bad,ids)["ok"],"TASK-049 missing On Hit payload forbidden")
	bad = formula("essence.fire","form.projectile",[],true)
	bad["on_hit"]["payload"]["modifier_ids"] = ["mod.pierce"]
	t.check(_has(compiler.compile(bad,ids)["issues"],"PAYLOAD_MODIFIER_FORBIDDEN"),
		"TASK-049 child modifiers forbidden")
	bad = formula("essence.fire","form.projectile",[],true)
	bad["on_hit"]["payload"]["manifestation_id"] = "form.projectile"
	t.check(_has(compiler.compile(bad,ids)["issues"],"PAYLOAD_FORM_INVALID"),"TASK-049 On Hit payload must be Burst")
	bad = formula("essence.fire","form.projectile")
	bad["schema_version"] = 99
	t.check(not compiler.compile(bad,ids)["ok"],"TASK-049 unknown schema version fails")
	bad = formula("essence.fire","form.projectile")
	bad["root"]["essence_id"] = "essence.missing"
	t.check(_has(compiler.compile(bad,ids)["issues"],"RUNE_UNKNOWN"),"TASK-049 unknown rune diagnostic")
	bad = formula("essence.fire","form.projectile")
	bad["root"]["params"]["speed"] = "very fast"
	t.check(_has(compiler.compile(bad,ids)["issues"],"PARAMETER_TYPE_INVALID"),"TASK-049 invalid parameter type")
	bad = formula("essence.fire","form.projectile")
	t.check(_has(compiler.compile(bad,["essence.fire"])["issues"],"RUNE_LOCKED"),"TASK-049 locked rune diagnostic")
	var tiny = Compiler.new(registry,3)
	t.check(_has(tiny.compile(formula("essence.fire","form.projectile",["mod.split"]),ids)["issues"],"COMPLEXITY_EXCEEDED"),
		"TASK-049 complexity budget enforced")
	# Existing root plans must remain the same after registry-independent new compile calls.
	var unchanged: Dictionary = compiler.compile(formula("essence.fire","form.projectile"),ids)["compiled_spell"].snapshot()
	for element in ELEMENTS:
		compiler.compile(formula(element,"form.burst"),ids)
	t.equal(unchanged,compiler.compile(formula("essence.fire","form.projectile"),ids)["compiled_spell"].snapshot(),
		"TASK-049 unrelated formula compilation cannot mutate existing golden plan")
	# Simulate adding a completely unrelated rune to a new registry revision.
	# Snapshot revision itself will change; cost/formula hash/plan contents must not.
	var seed_data: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://magic/data/runes_v1.json"))
	var extended: Array = seed_data["runes"].duplicate(true)
	var new_rune: Dictionary = extended[0].duplicate(true)
	new_rune["id"] = "essence.future_candidate"
	extended.append(new_rune)
	var previous_revision: int = registry.revision
	t.check(registry.replace_all(extended)["ok"],"TASK-049 adding a valid unrelated rune succeeds")
	t.check(registry.revision > previous_revision,"TASK-049 new registry revision recorded")
	var after: Dictionary = compiler.compile(formula("essence.fire","form.projectile"),registry.get_ids())["compiled_spell"].snapshot()
	for key in ["formula_hash","mana_cost","complexity","cooldown_ticks","root","on_hit","execution_phases"]:
		t.equal(after[key],unchanged[key],"TASK-049 additive rune roster cannot alter golden spell "+key)

