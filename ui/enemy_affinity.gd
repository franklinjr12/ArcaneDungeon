extends RefCounted
## AD-194: weak/resist channels per enemy kind, read from live data (Compendium enemy page, later the HUD).
const SkinA = preload("res://ui/skin_a.gd")
const TUNING_PATH := "res://combat/combat_tuning_v1.json"
const RUN_PATH := "res://world/data/run_v2.json"
const BOSS_KINDS := ["drowned_archivist", "undead_warden"]

static var _cache: Dictionary = {}

static func _load(path: String) -> Dictionary:
	if not _cache.has(path):
		var parsed = JSON.parse_string(FileAccess.get_file_as_string(path))
		_cache[path] = parsed if parsed is Dictionary else {}
	return _cache[path]

static func _resistances(kind: String) -> Dictionary:
	if kind in BOSS_KINDS:
		var bosses = _load(RUN_PATH).get("bosses", {})
		if bosses is Dictionary:
			for key in bosses:
				if bosses[key] is Dictionary and bosses[key].get("kind", "") == kind:
					return bosses[key].get("channel_resistances", {})
		return {}
	var enemy = _load(TUNING_PATH).get("enemies", {}).get(kind, {})
	return enemy.get("channel_resistances", {}) if enemy is Dictionary else {}

## {"weak": [...], "resist": [...]}, both sorted; value < 0 is weak, > 0 resist (1.0 = immune).
static func of(kind: String) -> Dictionary:
	var weak: Array = []
	var resist: Array = []
	var res := _resistances(kind)
	for channel in res:
		var v := float(res[channel])
		if v < 0.0:
			weak.append(channel)
		elif v > 0.0:
			resist.append(channel)
	weak.sort()
	resist.sort()
	return {"weak": weak, "resist": resist}

static func icon(channel: String) -> AtlasTexture:
	return SkinA.rune_icon("essence." + channel)
