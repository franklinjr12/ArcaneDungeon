extends RefCounted
## AD-143: run artifacts as data + hooks. This holder owns the held ids and per-room counters;
## effects are applied by the simulation through has()/param().
const PATH := "res://world/data/artifacts_v1.json"
const HOOKS := ["on_cast","on_hit","on_kill","on_dash","on_room_clear","on_hp_threshold"]
static var _cache: Dictionary = {}
var held: Array = []
## Per-room runtime counters used by the effects; cleared by reset_room().
var state: Dictionary = {}

static func load_config() -> Dictionary:
	var file := FileAccess.open(PATH, FileAccess.READ)
	if file == null:
		return {}
	var parsed = JSON.parse_string(file.get_as_text())
	return parsed if parsed is Dictionary else {}

static func config() -> Dictionary:
	if _cache.is_empty():
		_cache = load_config()
	return _cache

static func definitions() -> Dictionary:
	return config().get("artifacts", {})

static func max_held() -> int:
	return int(config().get("max_held", 6))

static func is_known(id: String) -> bool:
	return definitions().has(id)

static func rarity_of(id: String) -> String:
	return str(definitions().get(id, {}).get("rarity", "common"))

func _init(initial_ids: Array = []) -> void:
	for id in initial_ids:
		if can_add(str(id)):
			held.append(str(id))

func has(id: String) -> bool:
	return id in held

func param(id: String, key: String, default: Variant = null) -> Variant:
	return definitions().get(id, {}).get("params", {}).get(key, default)

func hooked(hook: String) -> Array:
	return held.filter(func(id): return hook in definitions().get(id, {}).get("hooks", []))

func can_add(id: String) -> bool:
	return is_known(id) and id not in held and held.size() < max_held()

func add(id: String) -> Dictionary:
	if not is_known(id):
		return {"ok":false,"reason":"ARTIFACT_UNKNOWN"}
	if id in held:
		return {"ok":false,"reason":"ARTIFACT_DUPLICATE"}
	if held.size() >= max_held():
		return {"ok":false,"reason":"ARTIFACT_LIMIT"}
	held.append(id)
	return {"ok":true,"reason":"ARTIFACT_ADDED"}

func ids() -> Array:
	return held.duplicate()

func is_empty() -> bool:
	return held.is_empty()

func reset_room() -> void:
	state.clear()
