extends RefCounted
const Codec = preload("res://magic/compile/spell_codec.gd")
const Validator = preload("res://magic/compile/spell_validator.gd")
const CompiledSpell = preload("res://magic/compile/compiled_spell.gd")
const BASIC_BOLT_PATH := "res://magic/data/basic_bolt_v1.json"
var registry
var validator
var _cache: Dictionary = {}

func _init(rune_registry, complexity_cap: int = 12) -> void:
	registry = rune_registry
	validator = Validator.new(registry,complexity_cap)

func compile(formula: Variant, unlocked_rune_ids: Array) -> Dictionary:
	var outcome = validator.validate(formula,unlocked_rune_ids)
	if not outcome["ok"]:
		return {"ok":false,"compiled_spell":null,"issues":outcome["issues"]}
	var encoded := Codec.encode(formula)
	if not encoded["ok"]:
		return {"ok":false,"compiled_spell":null,"issues":encoded["issues"]}
	var unlocked := unlocked_rune_ids.duplicate()
	unlocked.sort()
	var key := "%d/%d/%s/%s" % [registry.revision,validator.max_complexity,encoded["json"].sha256_text(),JSON.stringify(unlocked).sha256_text()]
	if _cache.has(key):
		return {"ok":true,"compiled_spell":_cache[key],"issues":[]}
	var compiled = _build(formula,encoded["json"].sha256_text(),-1,-1)
	_cache[key] = compiled
	return {"ok":true,"compiled_spell":compiled,"issues":[]}

## Built-in formulas (AD-011) may use builtin runes; cost and cooldown come from data, not rune sums.
func compile_builtin(definition: Dictionary) -> Dictionary:
	var bad := {"ok":false,"compiled_spell":null,"issues":[{"code":"BUILTIN_DEFINITION_INVALID","path":"$","message":"Invalid built-in spell definition."}]}
	var keys: Array = definition.keys()
	keys.sort()
	if keys != ["cooldown_ticks","formula","mana_cost","schema_version"]:
		return bad
	if typeof(definition["schema_version"]) not in [TYPE_INT,TYPE_FLOAT] or int(definition["schema_version"]) != 1:
		return bad
	for field in ["mana_cost","cooldown_ticks"]:
		var value = definition[field]
		if typeof(value) not in [TYPE_INT,TYPE_FLOAT] or float(value) != floor(float(value)) or int(value) < 0:
			return bad
	var formula = definition["formula"]
	if typeof(formula) != TYPE_DICTIONARY or typeof(formula.get("root")) != TYPE_DICTIONARY:
		return bad
	if not registry.is_builtin(str(formula["root"].get("essence_id",""))):
		return bad
	var allowed: Array = registry.get_builtin_ids()
	var ids: Array = [formula["root"].get("manifestation_id","")]
	ids.append_array(formula["root"].get("modifier_ids",[]))
	for id in ids:
		if str(id) != "" and not registry.is_builtin(str(id)):
			allowed.append(str(id))
	var builtin_validator = Validator.new(registry,validator.max_complexity)
	builtin_validator.allow_builtin = true
	var outcome = builtin_validator.validate(formula,allowed)
	if not outcome["ok"]:
		return {"ok":false,"compiled_spell":null,"issues":outcome["issues"]}
	var encoded := Codec.encode(formula)
	if not encoded["ok"]:
		return {"ok":false,"compiled_spell":null,"issues":encoded["issues"]}
	return {"ok":true,"compiled_spell":_build(formula,encoded["json"].sha256_text(),int(definition["mana_cost"]),int(definition["cooldown_ticks"])),"issues":[]}

static func load_builtin_definition(path := BASIC_BOLT_PATH) -> Dictionary:
	var parsed = JSON.parse_string(FileAccess.get_file_as_string(path))
	if typeof(parsed) != TYPE_DICTIONARY:
		return {"ok":false,"definition":{},"issues":[{"code":"BUILTIN_DEFINITION_INVALID","path":path,"message":"Cannot parse built-in definition."}]}
	return {"ok":true,"definition":parsed,"issues":[]}

## Shared plan builder; negative override values mean "sum from runes / max of runes".
func _build(formula: Dictionary, formula_hash: String, mana_override: int, cooldown_override: int):
	var root: Dictionary = formula["root"]
	var runes: Array = [root["essence_id"],root["manifestation_id"]]
	runes.append_array(root["modifier_ids"])
	var root_plan := _compile_effect(root)
	var payload: Dictionary = {}
	if formula.has("on_hit"):
		var on_hit = formula["on_hit"]
		runes.append(on_hit["trigger_id"])
		runes.append(on_hit["payload"]["essence_id"])
		runes.append(on_hit["payload"]["manifestation_id"])
		payload = {"trigger":registry.get_rune(on_hit["trigger_id"]).snapshot(),"effect":_compile_effect(on_hit["payload"])}
	var mana := 0
	var complexity := 0
	var cooldown := 0
	for id in runes:
		var data = registry.get_rune(id).snapshot()
		mana += data["mana_cost"]
		complexity += data["complexity_weight"]
		cooldown = maxi(cooldown,data["cooldown_ticks"])
	var plan := {
		"schema_version":1,"formula_id":formula["formula_id"],
		"formula_hash":formula_hash,
		"registry_revision":registry.revision,
		"mana_cost":mana if mana_override < 0 else mana_override,
		"complexity":complexity,
		"cooldown_ticks":cooldown if cooldown_override < 0 else cooldown_override,
		"execution_phases":["spawn","split","homing","collision","pierce","resolve","enqueue_trigger","drain_queue","cleanup"],
		"modifier_order_affects_runtime":false,
		"root":root_plan,
		"on_hit":payload
	}
	if mana_override >= 0:
		plan["builtin"] = true
	return CompiledSpell.new(plan)

func _compile_effect(effect: Dictionary) -> Dictionary:
	var modifiers: Array = []
	for id in effect["modifier_ids"]:
		modifiers.append(registry.get_rune(id).snapshot())

	var essence: Dictionary = registry.get_rune(effect["essence_id"]).snapshot()
	var form: Dictionary = registry.get_rune(effect["manifestation_id"]).snapshot()
	var resolved: Dictionary = {}
	for rune in [essence,form] + modifiers:
		for key in rune["params"]:
			var spec: Dictionary = rune["params"][key]
			if spec.has("default"):
				resolved[key] = spec["default"]
	for key in effect["params"]:
		resolved[key] = effect["params"][key]
	return {"essence":essence,"manifestation":form,
		"modifiers":modifiers,"params":resolved}
