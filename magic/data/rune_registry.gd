extends RefCounted
const RuneDefinition = preload("res://magic/data/rune_definition.gd")
const SEED_PATH := "res://magic/data/runes_v2.json"
const DEFAULT_CATEGORIES := [
	{"id":"essence","display_key":"rune_category.essence","label":"Essence","order":0},
	{"id":"form","display_key":"rune_category.form","label":"Manifestation","order":1},
	{"id":"modifier","display_key":"rune_category.modifier","label":"Modifier","order":2},
	{"id":"trigger","display_key":"rune_category.trigger","label":"Trigger","order":3},
]
var revision := 0
var _runes: Dictionary = {}
var _categories: Array = DEFAULT_CATEGORIES.duplicate(true)
var _param_blocks: Dictionary = {}

## Loads schema v2 rune data; a legacy schema v1 file is migrated in memory (default categories, no blocks).
func load_seed(path: String = SEED_PATH) -> Dictionary:
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		return _fail("REGISTRY_MISSING_FILE", path, "Cannot read rune seed data")
	var parser := JSON.new()
	var parse_error := parser.parse(file.get_as_text())
	if parse_error != OK:
		return _fail("REGISTRY_INVALID_JSON", path, parser.get_error_message())
	var data = parser.data
	if typeof(data) != TYPE_DICTIONARY or typeof(data.get("runes")) != TYPE_ARRAY or typeof(data.get("schema_version")) not in [TYPE_INT,TYPE_FLOAT]:
		return _fail("REGISTRY_INVALID_SCHEMA", path, "Expected rune array with schema_version 1 or 2")
	var version := int(data["schema_version"])
	if version == 1:
		return replace_all(data["runes"])
	if version != 2:
		return _fail("REGISTRY_INVALID_SCHEMA", path, "Unsupported rune schema_version")
	return replace_all(data["runes"], data.get("categories"), data.get("param_blocks"))

## Atomic replace. categories/param_blocks default to the currently loaded ones.
func replace_all(entries: Array, categories = null, param_blocks = null) -> Dictionary:
	var next_categories: Array = _categories if categories == null else categories
	var next_blocks: Dictionary = _param_blocks if param_blocks == null else {}
	var issues: Array = []
	if categories != null:
		issues.append_array(_check_categories(categories))
	if param_blocks != null:
		if typeof(param_blocks) != TYPE_DICTIONARY:
			issues.append({"code":"REGISTRY_PARAM_BLOCKS_INVALID","path":"param_blocks","message":"param_blocks must be an object"})
		else:
			next_blocks = param_blocks
			for block_name in param_blocks:
				if typeof(param_blocks[block_name]) != TYPE_DICTIONARY:
					issues.append({"code":"REGISTRY_PARAM_BLOCKS_INVALID","path":"param_blocks."+str(block_name),"message":"Param block must be an object"})
	if not issues.is_empty():
		return {"ok":false,"issues":issues}
	var category_ids: Array = []
	for category in next_categories:
		category_ids.append(category["id"])
	var next_runes: Dictionary = {}
	for i in entries.size():
		var value = entries[i]
		if typeof(value) != TYPE_DICTIONARY:
			issues.append({"code":"RUNE_NOT_OBJECT","path":"runes[%d]"%i,"message":"Rune must be an object"})
			continue
		var resolved := _resolve_params(value, next_blocks, "runes[%d]"%i, issues)
		var rune = RuneDefinition.new()
		for issue in rune.from_dict(resolved, category_ids):
			issues.append({"code":issue["code"],"path":"runes[%d].%s"%[i,issue["path"]],"message":issue["message"]})
		if not rune.id().is_empty():
			if next_runes.has(rune.id()):
				issues.append({"code":"RUNE_DUPLICATE_ID","path":"runes[%d].id"%i,"message":"Duplicate rune identifier: "+rune.id()})
			else:
				next_runes[rune.id()] = rune
	if issues.is_empty():
		_runes = next_runes
		_categories = next_categories.duplicate(true)
		_param_blocks = next_blocks.duplicate(true)
		revision += 1
	return {"ok":issues.is_empty(),"issues":issues}

## Resolved entry: named blocks applied in order, then the rune's own params merged over them field by field.
static func _resolve_params(value: Dictionary, blocks: Dictionary, path: String, issues: Array) -> Dictionary:
	var resolved: Dictionary = value.duplicate(true)
	var names = resolved.get("param_blocks", [])
	resolved.erase("param_blocks")
	if typeof(names) != TYPE_ARRAY:
		issues.append({"code":"REGISTRY_PARAM_BLOCK_UNKNOWN","path":path+".param_blocks","message":"param_blocks must be an array of block names"})
		return resolved
	var params: Dictionary = {}
	for block_name in names:
		if typeof(block_name) != TYPE_STRING or not blocks.has(block_name):
			issues.append({"code":"REGISTRY_PARAM_BLOCK_UNKNOWN","path":path+".param_blocks","message":"Unknown param block: "+str(block_name)})
			continue
		_merge_params(params, blocks[block_name])
	if typeof(resolved.get("params")) == TYPE_DICTIONARY:
		_merge_params(params, resolved["params"])
		resolved["params"] = params
	elif not names.is_empty() and not resolved.has("params"):
		resolved["params"] = params
	return resolved

static func _merge_params(target: Dictionary, source: Dictionary) -> void:
	for key in source:
		if typeof(source[key]) == TYPE_DICTIONARY and typeof(target.get(key)) == TYPE_DICTIONARY:
			for field in source[key]:
				target[key][field] = source[key][field]
		else:
			target[key] = source[key].duplicate(true) if typeof(source[key]) == TYPE_DICTIONARY else source[key]

static func _check_categories(categories) -> Array:
	var issues: Array = []
	if typeof(categories) != TYPE_ARRAY or categories.is_empty():
		return [{"code":"REGISTRY_CATEGORY_INVALID","path":"categories","message":"categories must be a nonempty array"}]
	var seen: Dictionary = {}
	for i in categories.size():
		var c = categories[i]
		var path := "categories[%d]" % i
		if typeof(c) != TYPE_DICTIONARY or typeof(c.get("id")) != TYPE_STRING or typeof(c.get("display_key")) != TYPE_STRING or typeof(c.get("label")) != TYPE_STRING or typeof(c.get("order")) not in [TYPE_INT,TYPE_FLOAT] or floor(float(c["order"])) != float(c["order"]):
			issues.append({"code":"REGISTRY_CATEGORY_INVALID","path":path,"message":"Category needs string id, display_key, label and int order"})
		elif seen.has(c["id"]):
			issues.append({"code":"REGISTRY_CATEGORY_DUPLICATE","path":path+".id","message":"Duplicate category id: "+c["id"]})
		else:
			seen[c["id"]] = true
	return issues

## Sorted copies of the category dictionaries (by order, then id).
func list_categories() -> Array:
	var list: Array = _categories.duplicate(true)
	list.sort_custom(func(a, b): return [int(a["order"]), a["id"]] < [int(b["order"]), b["id"]])
	for entry in list:
		entry["order"] = int(entry["order"])
	return list

func get_rune(rune_id: String):
	if not _runes.has(rune_id):
		return null
	var category_ids: Array = []
	for category in _categories:
		category_ids.append(category["id"])
	var copy = RuneDefinition.new()
	copy.from_dict(_runes[rune_id].snapshot(), category_ids)
	return copy

func get_by_id(rune_id: String):
	return get_rune(rune_id)

## Collectible (non-builtin) rune IDs only; this is the full unlock set for callers.
func get_ids() -> Array:
	var ids: Array = []
	for rune_id in _runes:
		if not _runes[rune_id].is_builtin():
			ids.append(rune_id)
	ids.sort()
	return ids

func get_builtin_ids() -> Array:
	var ids: Array = []
	for rune_id in _runes:
		if _runes[rune_id].is_builtin():
			ids.append(rune_id)
	ids.sort()
	return ids

func get_all_ids() -> Array:
	var ids := _runes.keys()
	ids.sort()
	return ids

func is_builtin(rune_id: String) -> bool:
	return _runes.has(rune_id) and _runes[rune_id].is_builtin()

func list_by_category(category: String) -> Array:
	var list: Array = []
	for rune_id in get_ids():
		var rune = _runes[rune_id]
		if rune.category() == category:
			list.append(rune.snapshot())
	return list

func _fail(code: String, path: String, message: String) -> Dictionary:
	return {"ok":false,"issues":[{"code":code,"path":path,"message":message}]}
