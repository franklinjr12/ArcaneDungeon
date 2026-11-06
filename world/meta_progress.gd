extends RefCounted
## AD-145: light meta progression. Pure helpers over the profile's "meta" block: discovered ids per
## category and discovery milestones that unlock runes/artifacts into the pools (no permanent stat power).
## Deterministic: no RNG, no wall-clock time.
const PATH := "res://world/data/meta_v1.json"
static var _cache: Dictionary = {}

static func load_config() -> Dictionary:
	if _cache.is_empty():
		var file := FileAccess.open(PATH, FileAccess.READ)
		if file == null:
			return {}
		var parsed = JSON.parse_string(file.get_as_text())
		_cache = parsed if parsed is Dictionary else {}
	return _cache

static func categories() -> Array:
	return load_config().get("categories", ["runes", "reactions", "enemies", "artifacts"])

static func milestones() -> Array:
	return load_config().get("milestones", [])

static func empty_meta() -> Dictionary:
	var discovered := {}
	for cat in categories():
		discovered[cat] = []
	return {"discovered": discovered}

static func valid_meta(m) -> bool:
	if typeof(m) != TYPE_DICTIONARY or typeof(m.get("discovered")) != TYPE_DICTIONARY:
		return false
	var d: Dictionary = m["discovered"]
	for cat in categories():
		if typeof(d.get(cat)) != TYPE_ARRAY:
			return false
		for id in d[cat]:
			if typeof(id) != TYPE_STRING:
				return false
	return true

## Adds unique ids per category (sorted); returns the ids that were new, per category.
static func merge(meta: Dictionary, discoveries: Dictionary) -> Dictionary:
	var added := {}
	var d: Dictionary = meta["discovered"]
	for cat in categories():
		added[cat] = []
		var list: Array = d[cat]
		var incoming = discoveries.get(cat, [])
		if typeof(incoming) != TYPE_ARRAY:
			continue
		for id in incoming:
			if typeof(id) == TYPE_STRING and id not in list and id not in added[cat]:
				added[cat].append(id)
		added[cat].sort()
		if not added[cat].is_empty():
			list.append_array(added[cat])
			list.sort()
	return added

static func counts(meta: Dictionary) -> Dictionary:
	var out := {}
	for cat in categories():
		out[cat] = (meta["discovered"][cat] as Array).size()
	return out

static func milestones_met(meta: Dictionary) -> Array:
	var c := counts(meta)
	var out: Array = []
	for ms in milestones():
		if int(c.get(ms.get("category", ""), 0)) >= int(ms.get("count", 0)):
			out.append(str(ms["id"]))
	return out

static func _locked(meta: Dictionary, key: String) -> Array:
	var met := milestones_met(meta)
	var unlocked := {}
	var all := {}
	for ms in milestones():
		for id in ms.get("unlocks", {}).get(key, []):
			all[id] = true
			if str(ms["id"]) in met:
				unlocked[id] = true
	var out: Array = []
	for id in all:
		if not unlocked.has(id):
			out.append(id)
	out.sort()
	return out

static func locked_runes(meta: Dictionary) -> Array:
	return _locked(meta, "runes")

static func locked_artifacts(meta: Dictionary) -> Array:
	return _locked(meta, "artifacts")

static func newly_met(before_meta: Dictionary, after_meta: Dictionary) -> Array:
	var before := milestones_met(before_meta)
	return milestones_met(after_meta).filter(func(id): return id not in before)
