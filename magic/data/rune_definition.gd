extends Resource
## Public API exposes snapshots only. Registry keeps its own private copy.
const REQUIRED := ["id", "category", "schema_version", "params", "compatibility_tags", "complexity_weight", "mana_cost", "cooldown_ticks", "description", "display_key"]
const CATEGORIES := ["essence", "form", "modifier", "trigger"]
const PARAM_TYPES := ["bool", "int", "float", "string"]
var _definition: Dictionary = {}

func from_dict(value: Dictionary) -> Array:
	var issues: Array = []
	for key in REQUIRED:
		if not value.has(key):
			issues.append(_issue("RUNE_FIELD_REQUIRED", key, "Missing required rune field"))
	for key in value:
		if key not in REQUIRED:
			issues.append(_issue("RUNE_UNKNOWN_FIELD", key, "Unknown rune field"))
	if not issues.is_empty():
		return issues
	if typeof(value["id"]) != TYPE_STRING or not _id_valid(value["id"]):
		issues.append(_issue("RUNE_INVALID_ID", "id", "Expected stable lowercase dotted rune ID"))
	if typeof(value["schema_version"]) not in [TYPE_INT,TYPE_FLOAT] or value["schema_version"] != 1:
		issues.append(_issue("RUNE_SCHEMA_VERSION", "schema_version", "Only v1 rune data is supported"))
	if typeof(value["category"]) != TYPE_STRING or value["category"] not in CATEGORIES:
		issues.append(_issue("RUNE_CATEGORY_INVALID", "category", "Category must be essence, form, modifier or trigger"))
	if typeof(value["params"]) != TYPE_DICTIONARY:
		issues.append(_issue("RUNE_PARAMS_INVALID", "params", "Typed parameter definitions must be a dictionary"))
	else:
		for param in value["params"]:
			var spec = value["params"][param]
			if typeof(param) != TYPE_STRING or not _id_valid(param):
				issues.append(_issue("RUNE_PARAM_NAME", "params", "Invalid parameter identifier"))
			elif typeof(spec) != TYPE_DICTIONARY or not spec.has("type") or spec.get("type") not in PARAM_TYPES:
				issues.append(_issue("RUNE_PARAM_TYPE", "params." + str(param), "Expected typed parameter specification"))
			else:
				for field in spec:
					if field not in ["type", "min", "max", "default"]:
						issues.append(_issue("RUNE_PARAM_UNKNOWN_FIELD", "params.%s.%s" % [param,field], "Unknown parameter metadata"))
				if spec.has("min") and typeof(spec["min"]) not in [TYPE_INT, TYPE_FLOAT]:
					issues.append(_issue("RUNE_PARAM_BOUND", "params."+str(param)+".min", "Numeric minimum expected"))
				if spec.has("max") and typeof(spec["max"]) not in [TYPE_INT, TYPE_FLOAT]:
					issues.append(_issue("RUNE_PARAM_BOUND", "params."+str(param)+".max", "Numeric maximum expected"))
	if typeof(value["compatibility_tags"]) != TYPE_ARRAY:
		issues.append(_issue("RUNE_TAGS_INVALID", "compatibility_tags", "Expected tags array"))
	else:
		for tag in value["compatibility_tags"]:
			if typeof(tag) != TYPE_STRING or not _id_valid(tag):
				issues.append(_issue("RUNE_TAG_INVALID", "compatibility_tags", "Tags must use stable IDs"))
	for number_key in ["complexity_weight", "mana_cost", "cooldown_ticks"]:
		if typeof(value[number_key]) not in [TYPE_INT,TYPE_FLOAT] or value[number_key] < 0 or floor(float(value[number_key])) != float(value[number_key]):
			issues.append(_issue("RUNE_TUNING_INVALID", number_key, "Prototype tuning must be a nonnegative integer"))
	for string_key in ["description", "display_key"]:
		if typeof(value[string_key]) != TYPE_STRING or len(value[string_key]) > 256:
			issues.append(_issue("RUNE_TEXT_INVALID", string_key, "Expected short text"))
	if issues.is_empty():
		_definition = value.duplicate(true)
		_definition["schema_version"] = 1
		for number_key in ["complexity_weight","mana_cost","cooldown_ticks"]:
			_definition[number_key] = int(_definition[number_key])
	return issues

func snapshot() -> Dictionary:
	return _definition.duplicate(true)

func id() -> String:
	return str(_definition.get("id",""))

func category() -> String:
	return str(_definition.get("category",""))

static func _id_valid(id: String) -> bool:
	if len(id) < 1 or len(id) > 64 or not id[0].is_valid_identifier():
		return false
	for char in id:
		if char not in "abcdefghijklmnopqrstuvwxyz0123456789_.-":
			return false
	return true

static func _issue(code: String, path: String, message: String) -> Dictionary:
	return {"code":code, "path":path, "message":message}
