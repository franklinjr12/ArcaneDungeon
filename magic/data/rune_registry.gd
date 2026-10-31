extends RefCounted
const RuneDefinition = preload("res://magic/data/rune_definition.gd")
const SEED_PATH := "res://magic/data/runes_v1.json"
var revision := 0
var _runes: Dictionary = {}

func load_seed(path: String = SEED_PATH) -> Dictionary:
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		return _fail("REGISTRY_MISSING_FILE", path, "Cannot read rune seed data")
	var parser := JSON.new()
	var parse_error := parser.parse(file.get_as_text())
	if parse_error != OK:
		return _fail("REGISTRY_INVALID_JSON", path, parser.get_error_message())
	if typeof(parser.data) != TYPE_DICTIONARY or parser.data.get("schema_version") != 1 or typeof(parser.data.get("runes")) != TYPE_ARRAY:
		return _fail("REGISTRY_INVALID_SCHEMA", path, "Expected v1 rune array")
	return replace_all(parser.data["runes"])

func replace_all(entries: Array) -> Dictionary:
	var next_runes: Dictionary = {}
	var issues: Array = []
	for i in entries.size():
		var value = entries[i]
		if typeof(value) != TYPE_DICTIONARY:
			issues.append({"code":"RUNE_NOT_OBJECT","path":"runes[%d]"%i,"message":"Rune must be an object"})
			continue
		var rune = RuneDefinition.new()
		for issue in rune.from_dict(value):
			issues.append({"code":issue["code"],"path":"runes[%d].%s"%[i,issue["path"]],"message":issue["message"]})
		if not rune.id().is_empty():
			if next_runes.has(rune.id()):
				issues.append({"code":"RUNE_DUPLICATE_ID","path":"runes[%d].id"%i,"message":"Duplicate rune identifier: "+rune.id()})
			else:
				next_runes[rune.id()] = rune
	if issues.is_empty():
		_runes = next_runes
		revision += 1
	return {"ok":issues.is_empty(),"issues":issues}

func get_rune(rune_id: String):
	if not _runes.has(rune_id):
		return null
	var copy = RuneDefinition.new()
	copy.from_dict(_runes[rune_id].snapshot())
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
