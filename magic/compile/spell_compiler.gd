extends RefCounted
const Codec = preload("res://magic/compile/spell_codec.gd")
const Validator = preload("res://magic/compile/spell_validator.gd")
const CompiledSpell = preload("res://magic/compile/compiled_spell.gd")
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
		"formula_hash":encoded["json"].sha256_text(),
		"registry_revision":registry.revision,
		"mana_cost":mana,"complexity":complexity,"cooldown_ticks":cooldown,
		"execution_phases":["spawn","split","homing","collision","pierce","resolve","enqueue_trigger","drain_queue","cleanup"],
		"modifier_order_affects_runtime":false,
		"root":root_plan,
		"on_hit":payload
	}
	var compiled = CompiledSpell.new(plan)
	_cache[key] = compiled
	return {"ok":true,"compiled_spell":compiled,"issues":[]}

func _compile_effect(effect: Dictionary) -> Dictionary:
	var modifiers: Array = []
	for id in effect["modifier_ids"]:
		modifiers.append(registry.get_rune(id).snapshot())
	return {"essence":registry.get_rune(effect["essence_id"]).snapshot(),
		"manifestation":registry.get_rune(effect["manifestation_id"]).snapshot(),
		"modifiers":modifiers,"params":effect["params"].duplicate(true)}
