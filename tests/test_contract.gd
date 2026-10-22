extends RefCounted
const Registry = preload("res://magic/data/rune_registry.gd")
const Codec = preload("res://magic/compile/spell_codec.gd")
const Validator = preload("res://magic/compile/spell_validator.gd")
const Compiler = preload("res://magic/compile/spell_compiler.gd")

func run(t) -> void:
	var registry = Registry.new()
	var load_result: Dictionary = registry.load_seed()
	t.check(load_result["ok"], "TASK-004 seed registry loads: " + str(load_result["issues"]))
	t.equal(registry.get_ids().size(),10,"TASK-004 all ten prototype runes")
	t.equal(registry.list_by_category("essence").size(),3,"TASK-004 enumerate essence without hardcoded UI IDs")
	t.equal(registry.list_by_category("form").size(),3,"TASK-004 enumerate manifestations")
	t.equal(registry.list_by_category("modifier").size(),3,"TASK-004 enumerate modifiers")
	t.equal(registry.list_by_category("trigger").size(),1,"TASK-004 enumerate triggers")
	t.check(registry.get_rune("invalid") == null,"TASK-004 unknown rune returns null")
	var snapshot = registry.get_rune("essence.fire").snapshot()
	snapshot["mana_cost"] = 900
	t.equal(registry.get_rune("essence.fire").snapshot()["mana_cost"],5,"TASK-004 registry data defensive copy")
	var entries: Array = []
	for id in registry.get_ids():
		entries.append(registry.get_rune(id).snapshot())
	var duplicates := entries.duplicate(true)
	duplicates.append(entries[0].duplicate(true))
	var failed_load: Dictionary = registry.replace_all(duplicates)
	t.check(not failed_load["ok"],"TASK-004 duplicate rune rejected atomically")
	t.contains_issue(failed_load["issues"],"RUNE_DUPLICATE_ID","TASK-004 duplicate rune diagnostics")
	t.equal(registry.get_ids().size(),10,"TASK-004 rejection does not corrupt registry")
	var missing_category := entries.duplicate(true)
	missing_category[0].erase("category")
	var rejected := registry.replace_all(missing_category)
	t.check(not rejected["ok"],"TASK-004 missing category rejected")
	t.contains_issue(rejected["issues"],"RUNE_FIELD_REQUIRED","TASK-004 required category diagnostics")
	var invalid_schema := entries.duplicate(true)
	invalid_schema[0]["params"] = {"speed":{"type":"array"}}
	t.contains_issue(registry.replace_all(invalid_schema)["issues"],"RUNE_PARAM_TYPE","TASK-004 typed parameter definitions checked")

	var formulas: Array = []
	var json_texts: Array = []
	for filename in ["fire_shot.json","split_water.json","spark_burst.json"]:
		var file := FileAccess.open("res://tests/fixtures/"+filename,FileAccess.READ)
		t.check(file != null, "TASK-005 fixture text available "+filename)
		if file == null:
			continue
		var raw := file.get_as_text().strip_edges()
		var decoded: Dictionary = Codec.decode(raw)
		t.check(decoded["ok"],"TASK-005 decode "+filename)
		if not decoded["ok"]:
			continue
		var encoded: Dictionary = Codec.encode(decoded["formula"])
		t.check(encoded["ok"],"TASK-005 encode "+filename)
		t.equal(encoded["json"],raw,"TASK-005 golden canonical JSON "+filename)
		t.equal(Codec.decode(encoded["json"])["formula"],decoded["formula"],"TASK-005 round-trip "+filename)
		formulas.append(decoded["formula"])
		json_texts.append(encoded["json"])
	var malformed := FileAccess.open("res://tests/fixtures/malformed_formula.txt",FileAccess.READ)
	t.contains_issue(Codec.decode(malformed.get_as_text())["issues"],"MALFORMED_JSON","TASK-005 malformed JSON issue")
	t.contains_issue(Codec.decode('{"schema_version":99,"formula_id":"bad","display_name":"Bad","root":{}}')["issues"],"SCHEMA_UNSUPPORTED","TASK-005 unknown schema issue")
	t.contains_issue(Codec.decode('{"schema_version":1,"formula_id":"bad","display_name":"Bad"}')["issues"],"ROOT_REQUIRED","TASK-005 missing root issue")
	var bad_field: Dictionary = formulas[0].duplicate(true)
	bad_field["script"] = "res://run.gd"
	t.contains_issue(Codec.encode(bad_field)["issues"],"FORMULA_UNKNOWN_FIELD","TASK-005 reject executable fields")
	var bad_param: Dictionary = formulas[0].duplicate(true)
	bad_param["root"]["params"]["source"] = "res://scripts/evil.gd"
	t.contains_issue(Codec.encode(bad_param)["issues"],"PARAM_VALUE_INVALID","TASK-005 reject resource paths")
	var validator = Validator.new(registry)
	var compiler = Compiler.new(registry)
	var all_ids: Array = registry.get_ids()
	var hashes: Dictionary = {}
	for formula in formulas:
		var valid: Dictionary = validator.validate(formula,all_ids)
		t.check(valid["ok"],"TASK-006 valid sample "+formula["formula_id"])
		var result: Dictionary = compiler.compile(formula,all_ids)
		t.check(result["ok"],"TASK-007 compile sample "+formula["formula_id"])
		if result["ok"]:
			var plan: Dictionary = result["compiled_spell"].snapshot()
			hashes[plan["formula_hash"]] = true
			t.check(plan["mana_cost"] > 0 and plan["cooldown_ticks"] > 0,"TASK-007 resolved positive costs")
			t.equal(plan["modifier_order_affects_runtime"],false,"TASK-007 modifier ordering contract")
			t.equal(compiler.compile(formula,all_ids)["compiled_spell"],result["compiled_spell"],"TASK-007 cache stable")
	t.equal(hashes.size(),3,"TASK-007 sample plans distinct")
	var wrong_modifier = formulas[0].duplicate(true)
	wrong_modifier["root"]["manifestation_id"] = "form.burst"
	wrong_modifier["root"]["modifier_ids"] = ["mod.homing"]
	t.contains_issue(validator.validate(wrong_modifier,all_ids)["issues"],"MODIFIER_INCOMPATIBLE","TASK-006 Homing on Burst rejected")
	var duplicated_mod = formulas[1].duplicate(true)
	duplicated_mod["root"]["modifier_ids"] = ["mod.split","mod.split"]
	t.contains_issue(validator.validate(duplicated_mod,all_ids)["issues"],"MODIFIER_DUPLICATE","TASK-006 duplicate modifier rejected")
	var missing_payload = formulas[0].duplicate(true)
	missing_payload["on_hit"] = {"trigger_id":"trigger.on_hit"}
	t.contains_issue(validator.validate(missing_payload,all_ids)["issues"],"TRIGGER_PAYLOAD_REQUIRED","TASK-006 missing payload rejected")
	var bad_trigger = formulas[2].duplicate(true)
	bad_trigger["root"]["manifestation_id"] = "form.burst"
	t.contains_issue(validator.validate(bad_trigger,all_ids)["issues"],"TRIGGER_INCOMPATIBLE","TASK-006 On Hit on Burst rejected")
	var unknown_rune = formulas[0].duplicate(true)
	unknown_rune["root"]["essence_id"] = "essence.unknown"
	t.contains_issue(validator.validate(unknown_rune,all_ids)["issues"],"RUNE_UNKNOWN","TASK-006 unknown rune rejected")
	t.contains_issue(validator.validate(formulas[0],["form.projectile"])["issues"],"RUNE_LOCKED","TASK-006 locked rune rejected")
	t.contains_issue(Validator.new(registry,1).validate(formulas[2],all_ids)["issues"],"COMPLEXITY_EXCEEDED","TASK-006 complexity cap rejected")
	t.check(not compiler.compile(bad_trigger,all_ids)["ok"],"TASK-007 invalid formula cannot compile")
	t.check(compiler.compile(bad_trigger,all_ids)["compiled_spell"] == null,"TASK-007 invalid has no execution plan")
	var original: Dictionary = formulas[0].duplicate(true)
	var compiled = compiler.compile(original,all_ids)["compiled_spell"]
	original["root"]["essence_id"] = "essence.water"
	t.equal(compiled.snapshot()["root"]["essence"]["id"],"essence.fire","TASK-007 source edits cannot mutate cached plan")
	var leaked: Dictionary = compiled.snapshot()
	leaked["root"]["essence"]["id"] = "essence.corrupted"
	t.equal(compiled.snapshot()["root"]["essence"]["id"],"essence.fire","TASK-007 returned plan defensive copy")
	var changed_runes := entries.duplicate(true)
	for value in changed_runes:
		if value["id"] == "essence.fire":
			value["mana_cost"] += 2
	t.check(registry.replace_all(changed_runes)["ok"],"TASK-007 revised registry accepted")
	var updated = compiler.compile(formulas[0],all_ids)["compiled_spell"]
	t.equal(updated.mana_cost(),compiled.mana_cost()+2,"TASK-007 cache invalidates after registry revision")

	var erroneous_defaults: Array = entries.duplicate(true)
	for def in erroneous_defaults:
		if def["id"] == "form.projectile":
			def["params"]["speed"]["default"] = "faster"
	t.contains_issue(registry.replace_all(erroneous_defaults)["issues"],"RUNE_PARAM_DEFAULT_TYPE",
		"TASK-004/M1 typed rune defaults reject incompatible values")
	t.equal(registry.get_ids().size(),10,"TASK-004/M1 invalid defaults leave loaded registry unchanged")
