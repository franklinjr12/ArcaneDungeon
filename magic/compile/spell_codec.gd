extends RefCounted
## Strict whitelist codec; never deserialize executable Godot resources.
const MAX_JSON_LENGTH := 8192
const ROOT_KEYS := ["schema_version", "formula_id", "display_name", "root", "on_hit"]
const EFFECT_KEYS := ["essence_id", "manifestation_id", "modifier_ids", "params"]
const TRIGGER_KEYS := ["trigger_id", "payload"]

static func decode(text: String) -> Dictionary:
	if text.length() > MAX_JSON_LENGTH:
		return _fail("FORMULA_TOO_LARGE","$","Maximum encoded formula size exceeded")
	var json := JSON.new()
	var error := json.parse(text)
	if error != OK:
		return _fail("MALFORMED_JSON","$","JSON parse failed at line %d: %s" % [json.get_error_line(),json.get_error_message()])
	var issues := check_shape(json.data)
	if not issues.is_empty():
		return {"ok":false,"formula":{},"issues":issues}
	return {"ok":true,"formula":_canonical(json.data),"issues":[]}

static func encode(formula: Variant) -> Dictionary:
	var issues := check_shape(formula)
	if not issues.is_empty():
		return {"ok":false,"json":"","issues":issues}
	var json := JSON.stringify(_canonical(formula))
	if json.length() > MAX_JSON_LENGTH:
		return {"ok":false,"json":"","issues":[_issue("FORMULA_TOO_LARGE","$","Maximum encoded formula size exceeded")]}
	return {"ok":true,"json":json,"issues":[]}

static func check_shape(formula: Variant) -> Array:
	var issues: Array = []
	if typeof(formula) != TYPE_DICTIONARY:
		return [_issue("FORMULA_NOT_OBJECT", "$", "Formula must be an object")]
	for key in formula:
		if key not in ROOT_KEYS:
			issues.append(_issue("FORMULA_UNKNOWN_FIELD","$."+str(key),"Unknown formula field"))
	if not formula.has("schema_version") or typeof(formula.get("schema_version")) not in [TYPE_INT,TYPE_FLOAT] or formula.get("schema_version") != 1:
		issues.append(_issue("SCHEMA_UNSUPPORTED","$.schema_version","Only schema_version=1 is supported"))
	for key in ["formula_id","display_name"]:
		if not formula.has(key) or typeof(formula.get(key)) != TYPE_STRING or len(formula[key]) < 1 or len(formula[key]) > 80:
			issues.append(_issue("FORMULA_TEXT_INVALID","$."+key,"Expected nonempty string no longer than 80"))
	if formula.has("formula_id") and typeof(formula["formula_id"]) == TYPE_STRING and not _safe_id(formula["formula_id"]):
		issues.append(_issue("FORMULA_ID_INVALID","$.formula_id","Expected stable lowercase formula ID"))
	if not formula.has("root"):
		issues.append(_issue("ROOT_REQUIRED","$.root","Formula root required"))
	else:
		_check_effect(formula["root"],"$.root",issues)
	if formula.has("on_hit"):
		var trigger = formula["on_hit"]
		if typeof(trigger) != TYPE_DICTIONARY:
			issues.append(_issue("TRIGGER_NOT_OBJECT","$.on_hit","Trigger must be object"))
		else:
			for key in trigger:
				if key not in TRIGGER_KEYS:
					issues.append(_issue("TRIGGER_UNKNOWN_FIELD","$.on_hit."+str(key),"Unknown trigger field"))
			if not trigger.has("trigger_id") or typeof(trigger.get("trigger_id")) != TYPE_STRING:
				issues.append(_issue("TRIGGER_ID_REQUIRED","$.on_hit.trigger_id","Trigger ID required"))
			elif not _safe_id(trigger["trigger_id"]):
				issues.append(_issue("TRIGGER_ID_INVALID","$.on_hit.trigger_id","Invalid trigger ID"))
			if not trigger.has("payload"):
				issues.append(_issue("TRIGGER_PAYLOAD_REQUIRED","$.on_hit.payload","Trigger payload required"))
			else:
				_check_effect(trigger["payload"],"$.on_hit.payload",issues)
	return issues

static func _check_effect(effect: Variant, path: String, issues: Array) -> void:
	if typeof(effect) != TYPE_DICTIONARY:
		issues.append(_issue("EFFECT_NOT_OBJECT",path,"Effect must be object"))
		return
	for key in effect:
		if key not in EFFECT_KEYS:
			issues.append(_issue("EFFECT_UNKNOWN_FIELD",path+"."+str(key),"Unknown effect field"))
	for key in ["essence_id","manifestation_id"]:
		if not effect.has(key) or typeof(effect.get(key)) != TYPE_STRING or not _safe_id(str(effect.get(key,""))):
			issues.append(_issue("EFFECT_ID_REQUIRED",path+"."+key,"Required stable rune ID"))
	if not effect.has("modifier_ids") or typeof(effect["modifier_ids"]) != TYPE_ARRAY:
		issues.append(_issue("MODIFIERS_REQUIRED",path+".modifier_ids","Modifier IDs must be an array"))
	else:
		if effect["modifier_ids"].size() > 16:
			issues.append(_issue("TOO_MANY_MODIFIERS",path+".modifier_ids","At most 16 modifiers allowed"))
		for i in effect["modifier_ids"].size():
			var value = effect["modifier_ids"][i]
			if typeof(value) != TYPE_STRING or not _safe_id(str(value)):
				issues.append(_issue("MODIFIER_ID_INVALID","%s.modifier_ids[%d]"%[path,i],"Modifier must use stable ID"))
	if not effect.has("params") or typeof(effect["params"]) != TYPE_DICTIONARY:
		issues.append(_issue("PARAMS_REQUIRED",path+".params","Typed parameters must be object"))
	else:
		if effect["params"].size() > 32:
			issues.append(_issue("TOO_MANY_PARAMS",path+".params","At most 32 parameters allowed"))
		for param in effect["params"]:
			var value = effect["params"][param]
			if typeof(param) != TYPE_STRING or not _safe_id(str(param)):
				issues.append(_issue("PARAM_NAME_INVALID",path+".params","Invalid parameter ID"))
			if typeof(value) not in [TYPE_BOOL, TYPE_INT, TYPE_FLOAT, TYPE_STRING] or (typeof(value) == TYPE_STRING and (len(value) > 128 or "://" in value)):
				issues.append(_issue("PARAM_VALUE_INVALID",path+".params."+str(param),"Only bounded primitive parameters; no resource/script paths"))

static func _canonical(formula: Dictionary) -> Dictionary:
	var result := {"schema_version":1,"formula_id":formula["formula_id"],"display_name":formula["display_name"],"root":_canon_effect(formula["root"])}
	if formula.has("on_hit"):
		result["on_hit"] = {"trigger_id":formula["on_hit"]["trigger_id"],"payload":_canon_effect(formula["on_hit"]["payload"])}
	return result

static func _canon_effect(effect: Dictionary) -> Dictionary:
	var params: Dictionary = {}
	var keys = effect["params"].keys()
	keys.sort()
	for key in keys:
		params[key] = effect["params"][key]
	return {"essence_id":effect["essence_id"],"manifestation_id":effect["manifestation_id"],"modifier_ids":effect["modifier_ids"].duplicate(),"params":params}

static func _safe_id(value: String) -> bool:
	if len(value) < 1 or len(value) > 64 or value[0] not in "abcdefghijklmnopqrstuvwxyz":
		return false
	for char in value:
		if char not in "abcdefghijklmnopqrstuvwxyz0123456789_.-":
			return false
	return true

static func _issue(code: String, path: String, message: String) -> Dictionary:
	return {"code":code,"path":path,"message":message}

static func _fail(code: String, path: String, message: String) -> Dictionary:
	return {"ok":false,"formula":{},"issues":[_issue(code,path,message)]}
