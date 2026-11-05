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
	_apply_modifier_scaling(root_plan)
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
	if cooldown_override < 0 and root["modifier_ids"].has("mod.expand") and root_plan["manifestation"]["id"] == "form.burst":
		cooldown = ceili(float(cooldown) / float(root_plan["params"]["expand_speed_scale"]))
	if cooldown_override < 0 and root["modifier_ids"].has("mod.rapid"):
		cooldown = maxi(1,roundi(float(cooldown) * float(root_plan["params"]["rapid_cooldown_scale"])))
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

## Compile-time Expand then Rapid, in fixed order whatever the modifier_ids order (AD-133).
func _apply_modifier_scaling(root_plan: Dictionary) -> void:
	var ids: Array = []
	for modifier in root_plan["modifiers"]:
		ids.append(modifier["id"])
	var params: Dictionary = root_plan["params"]
	if "mod.expand" in ids:
		var a := float(params["expand_area_scale"])
		var sp := float(params["expand_speed_scale"])
		match root_plan["manifestation"]["id"]:
			"form.projectile":
				_scale_param(root_plan,"radius",a)
				_scale_param(root_plan,"speed",sp)
			"form.burst":
				_scale_param(root_plan,"burst_radius",a)
			"form.orb":
				_scale_param(root_plan,"orb_radius",a)
				_scale_param(root_plan,"angular_speed",sp)
			"form.beam":
				_scale_param(root_plan,"beam_length",a)
				_scale_param(root_plan,"tick_interval_ticks",1.0 / sp,true)
			"form.field":
				_scale_param(root_plan,"field_radius",a)
				_scale_param(root_plan,"tick_interval_ticks",1.0 / sp,true)
	if "mod.rapid" in ids:
		_scale_param(root_plan,"base_damage",float(params["rapid_damage_scale"]))

## Multiplies one resolved param, clamped to its spec range; int params stay int (ceil when requested).
func _scale_param(root_plan: Dictionary, key: String, factor: float, round_up := false) -> void:
	var params: Dictionary = root_plan["params"]
	if not params.has(key):
		return
	var spec: Dictionary = {}
	for rune in [root_plan["manifestation"],root_plan["essence"]]:
		if rune["params"].has(key):
			spec = rune["params"][key]
	var scaled := float(params[key]) * factor
	if spec.get("type","") == "int":
		scaled = ceilf(scaled - 0.0001) if round_up else roundf(scaled)
	if spec.has("min"):
		scaled = maxf(scaled,float(spec["min"]))
	if spec.has("max"):
		scaled = minf(scaled,float(spec["max"]))
	params[key] = int(scaled) if spec.get("type","") == "int" else scaled
