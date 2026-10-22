extends RefCounted
const PATH := "res://magic/data/spell_limits_v1.json"
const FIELDS := ["max_complexity","max_event_depth","max_events_per_root_cast","max_effects_per_cast","max_active_effects","max_lifetime_ticks","max_chain_targets","min_rehit_delay_ticks"]
var _values: Dictionary = {}

func load_defaults() -> Dictionary:
	var file := FileAccess.open(PATH,FileAccess.READ)
	if file == null:
		return {"ok":false,"issues":[{"code":"LIMIT_FILE_MISSING","path":PATH,"message":"No limit configuration found"}]}
	var parser := JSON.new()
	if parser.parse(file.get_as_text()) != OK or typeof(parser.data) != TYPE_DICTIONARY:
		return {"ok":false,"issues":[{"code":"LIMIT_JSON_INVALID","path":PATH,"message":"Limits JSON malformed"}]}
	return configure(parser.data)

func configure(values: Dictionary) -> Dictionary:
	var issues: Array = []
	if values.get("schema_version") != 1:
		issues.append({"code":"LIMIT_SCHEMA_INVALID","path":"schema_version","message":"Only limits v1 supported"})
	for key in FIELDS:
		var value = values.get(key)
		if typeof(value) not in [TYPE_FLOAT,TYPE_INT] or value < 0 or floor(float(value)) != float(value):
			issues.append({"code":"LIMIT_INVALID","path":key,"message":"Required nonnegative whole number"})
	for key in values:
		if key not in FIELDS and key != "schema_version":
			issues.append({"code":"LIMIT_FIELD_UNKNOWN","path":str(key),"message":"Unsupported limit"})
	if issues.is_empty():
		var normalized := {"schema_version":1}
		for key in FIELDS:
			normalized[key] = int(values[key])
		_values = normalized
	return {"ok":issues.is_empty(),"issues":issues}

func get_limit(key: String) -> int:
	return int(_values.get(key,0))

func snapshot() -> Dictionary:
	return _values.duplicate(true)
