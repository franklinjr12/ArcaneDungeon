class_name Affixes
extends RefCounted
## AD-239: elite enemy affixes as data. roll() picks at most one affix per elite from the seed;
## apply() stamps it on an enemy (never on boss/mini_boss). Effects are read via definitions().
const PATH := "res://world/data/affixes_v1.json"
const EXCLUDED_TAGS := ["boss","mini_boss"]
static var _cache: Dictionary = {}

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
	return config().get("affixes", {})

static func ids() -> Array:
	var out := definitions().keys()
	out.sort()
	return out

static func is_known(id: String) -> bool:
	return definitions().has(id)

static func param(id: String, key: String, default: Variant = null) -> Variant:
	return definitions().get(id, {}).get(key, default)

## room_index is 1-based within the stage; optional rooms use their own chance at any depth.
static func chance_for(room_index: int, optional: bool) -> float:
	var table: Dictionary = config().get("spawn_chance_by_depth", {})
	if optional:
		return float(table.get("optional", 0.0))
	if room_index < int(config().get("min_room", 2)):
		return 0.0
	return float(table.get(str(room_index), table.get("3", 0.0)))

## Deterministic: "" or one affix id.
static func roll(seed_value: int, room_index: int, optional: bool) -> String:
	var chance := chance_for(room_index, optional)
	if chance <= 0.0:
		return ""
	var rng := RandomNumberGenerator.new()
	rng.seed = hash([seed_value, room_index, optional])
	if rng.randf() >= chance:
		return ""
	var list := ids()
	return str(list[rng.randi_range(0, list.size() - 1)])

static func outline_color(id: String) -> Color:
	return Color.html(str(param(id, "outline_color", "#ffffff")))

static func eligible(enemy) -> bool:
	if enemy == null or enemy.target == null:
		return false
	for tag in EXCLUDED_TAGS:
		if tag in enemy.target.tags:
			return false
	return true

## Stamps the affix id; behaviour hooks (effects) read it from enemy.affix.
static func apply(_session, enemy, id: String) -> void:
	if not is_known(id) or not eligible(enemy):
		return
	enemy.affix = id
