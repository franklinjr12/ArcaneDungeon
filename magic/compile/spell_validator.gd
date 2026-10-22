extends RefCounted
const Codec = preload("res://magic/compile/spell_codec.gd")
var registry
var max_complexity := 12

func _init(rune_registry, complexity_cap: int = 12) -> void:
	registry = rune_registry
	max_complexity = complexity_cap

func validate(formula: Variant, unlocked_rune_ids: Array) -> Dictionary:
	var issues := Codec.check_shape(formula)
	if not issues.is_empty():
		return {"ok":false,"issues":issues}
	var root: Dictionary = formula["root"]
	var root_form: String = root["manifestation_id"]
	_check_effect(root,"$.root",unlocked_rune_ids,issues)
	if root_form not in ["form.projectile","form.burst","form.orb"]:
		issues.append(_issue("ROOT_FORM_INVALID","$.root.manifestation_id","Unsupported root manifestation"))
	var seen: Dictionary = {}
	for i in root["modifier_ids"].size():
		var rune_id = root["modifier_ids"][i]
		if seen.has(rune_id):
			issues.append(_issue("MODIFIER_DUPLICATE","$.root.modifier_ids[%d]"%i,"Duplicate modifier"))
		seen[rune_id] = true
		if root_form != "form.projectile":
			issues.append(_issue("MODIFIER_INCOMPATIBLE","$.root.modifier_ids[%d]"%i,"Prototype modifiers attach only to Projectile"))
	if formula.has("on_hit"):
		var on_hit: Dictionary = formula["on_hit"]
		var trigger_id: String = on_hit.get("trigger_id","")
		_check_rune(trigger_id,"trigger","$.on_hit.trigger_id",unlocked_rune_ids,issues)
		if trigger_id != "trigger.on_hit":
			issues.append(_issue("TRIGGER_UNKNOWN","$.on_hit.trigger_id","Only On Hit is supported in v1"))
		if root_form != "form.projectile":
			issues.append(_issue("TRIGGER_INCOMPATIBLE","$.on_hit","On Hit attaches to Projectile only"))
		if on_hit.has("payload"):
			var payload: Dictionary = on_hit["payload"]
			_check_effect(payload,"$.on_hit.payload",unlocked_rune_ids,issues)
			if payload["manifestation_id"] != "form.burst":
				issues.append(_issue("PAYLOAD_FORM_INVALID","$.on_hit.payload.manifestation_id","On Hit payload must be Burst"))
			if not payload["modifier_ids"].is_empty():
				issues.append(_issue("PAYLOAD_MODIFIER_FORBIDDEN","$.on_hit.payload.modifier_ids","Payload modifiers are not supported"))
	var complexity := _complexity(formula)
	if complexity > max_complexity:
		issues.append(_issue("COMPLEXITY_EXCEEDED","$","Spell complexity %d exceeds cap %d" % [complexity,max_complexity]))
	return {"ok":issues.is_empty(),"issues":issues}

func _check_effect(effect: Dictionary, path: String, unlocked: Array, issues: Array) -> void:
	_check_rune(effect["essence_id"],"essence",path+".essence_id",unlocked,issues)
	_check_rune(effect["manifestation_id"],"form",path+".manifestation_id",unlocked,issues)
	for i in effect["modifier_ids"].size():
		_check_rune(effect["modifier_ids"][i],"modifier","%s.modifier_ids[%d]"%[path,i],unlocked,issues)
	var parameter_specs: Dictionary = {}
	for id in [effect["essence_id"],effect["manifestation_id"]] + effect["modifier_ids"]:
		var rune = registry.get_rune(id)
		if rune != null:
			parameter_specs.merge(rune.snapshot().get("params",{}),true)
	for param in effect["params"]:
		if not parameter_specs.has(param):
			issues.append(_issue("UNKNOWN_PARAMETER",path+".params."+str(param),"Parameter not defined by selected runes"))
			continue
		var spec = parameter_specs[param]
		var value = effect["params"][param]
		var expected = spec["type"]
		var type_ok = (expected == "bool" and typeof(value) == TYPE_BOOL) or (expected == "int" and typeof(value) == TYPE_INT) or (expected == "float" and typeof(value) in [TYPE_INT,TYPE_FLOAT]) or (expected == "string" and typeof(value) == TYPE_STRING)
		if not type_ok:
			issues.append(_issue("PARAMETER_TYPE_INVALID",path+".params."+str(param),"Parameter requires "+str(expected)))
		elif typeof(value) in [TYPE_INT,TYPE_FLOAT]:
			if (spec.has("min") and value < spec["min"]) or (spec.has("max") and value > spec["max"]):
				issues.append(_issue("PARAMETER_OUT_OF_RANGE",path+".params."+str(param),"Parameter outside allowed range"))

func _check_rune(id: String, category: String, path: String, unlocked: Array, issues: Array) -> void:
	var rune = registry.get_rune(id)
	if rune == null:
		issues.append(_issue("RUNE_UNKNOWN",path,"Unknown rune "+id))
		return
	if rune.category() != category:
		issues.append(_issue("RUNE_WRONG_CATEGORY",path,"Expected "+category+" rune"))
	if id not in unlocked:
		issues.append(_issue("RUNE_LOCKED",path,"Rune not unlocked: "+id))

func _complexity(formula: Dictionary) -> int:
	var total := _effect_complexity(formula["root"])
	if formula.has("on_hit"):
		total += _weight(formula["on_hit"]["trigger_id"])
		total += _effect_complexity(formula["on_hit"]["payload"])
	return total

func _effect_complexity(effect: Dictionary) -> int:
	var total := _weight(effect["essence_id"]) + _weight(effect["manifestation_id"])
	for id in effect["modifier_ids"]:
		total += _weight(id)
	return total

func _weight(id: String) -> int:
	var rune = registry.get_rune(id)
	return int(rune.snapshot()["complexity_weight"]) if rune != null else 0

func _issue(code: String, path: String, message: String) -> Dictionary:
	return {"code":code,"path":path,"message":message}
