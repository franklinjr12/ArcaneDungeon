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
	return {"discovered": discovered, "ink": 0, "upgrades": {}}

## AD-233: Arcane Ink earn amounts per event (room_cleared, mini_boss, boss, new_stage, run_won).
static func ink_rules() -> Dictionary:
	var rules = load_config().get("ink", {})
	return rules if rules is Dictionary else {}

## Adds a non-negative amount of ink; returns the new total.
static func add_ink(meta: Dictionary, amount: int) -> int:
	meta["ink"] = int(meta.get("ink", 0)) + maxi(amount, 0)
	return meta["ink"]

static func valid_meta(m) -> bool:
	if typeof(m) != TYPE_DICTIONARY or typeof(m.get("discovered")) != TYPE_DICTIONARY:
		return false
	var ink = m.get("ink", 0)
	if typeof(ink) != TYPE_INT and typeof(ink) != TYPE_FLOAT:
		return false
	if float(ink) < 0.0 or float(ink) != floorf(float(ink)):
		return false
	m["ink"] = int(ink)
	if not _valid_upgrades(m):
		return false
	var d: Dictionary = m["discovered"]
	for cat in categories():
		if typeof(d.get(cat)) != TYPE_ARRAY:
			return false
		for id in d[cat]:
			if typeof(id) != TYPE_STRING:
				return false
	return true

static func _valid_upgrades(m: Dictionary) -> bool:
	var ups = m.get("upgrades", {})
	if typeof(ups) != TYPE_DICTIONARY:
		return false
	var out := {}
	for id in ups:
		if typeof(id) != TYPE_STRING or id not in upgrade_ids():
			return false
		var v = ups[id]
		if typeof(v) != TYPE_INT and typeof(v) != TYPE_FLOAT:
			return false
		if float(v) != floorf(float(v)) or int(v) < 0 or int(v) > max_tier(id):
			return false
		out[id] = int(v)
	m["upgrades"] = out
	return true

## AD-234: Scriptorium upgrades. Tier per id lives in meta["upgrades"]; numbers come from meta_v1.json.
static func upgrade_ids() -> Array:
	return ["max_hp", "max_mana", "mana_regen"]

static func upgrade_def(id: String) -> Dictionary:
	var d = load_config().get("upgrades", {}).get(id, {})
	return d if d is Dictionary else {}

static func max_tier(id: String) -> int:
	return (upgrade_def(id).get("costs", []) as Array).size()

static func tier(meta: Dictionary, id: String) -> int:
	var ups = meta.get("upgrades", {})
	return int(ups.get(id, 0)) if ups is Dictionary else 0

## Ink cost of the next tier, or -1 when maxed (or unknown id).
static func next_cost(meta: Dictionary, id: String) -> int:
	var t := tier(meta, id)
	if t >= max_tier(id):
		return -1
	return int(upgrade_def(id)["costs"][t])

static func can_buy(meta: Dictionary, id: String) -> bool:
	var cost := next_cost(meta, id)
	return cost >= 0 and int(meta.get("ink", 0)) >= cost

static func buy(meta: Dictionary, id: String) -> bool:
	if not can_buy(meta, id):
		return false
	meta["ink"] = int(meta.get("ink", 0)) - next_cost(meta, id)
	if typeof(meta.get("upgrades")) != TYPE_DICTIONARY:
		meta["upgrades"] = {}
	meta["upgrades"][id] = tier(meta, id) + 1
	return true

## Total Ink invested in owned tiers.
static func spent_ink(meta: Dictionary) -> int:
	var total := 0
	for id in upgrade_ids():
		var costs: Array = upgrade_def(id).get("costs", [])
		for i in mini(tier(meta, id), costs.size()):
			total += int(costs[i])
	return total

## Free respec: refunds every owned tier into ink and clears upgrades; returns the refunded amount.
static func respec(meta: Dictionary) -> int:
	var refund := spent_ink(meta)
	meta["ink"] = int(meta.get("ink", 0)) + refund
	meta["upgrades"] = {}
	return refund

static func bonuses(meta: Dictionary) -> Dictionary:
	return {
		"max_hp": float(upgrade_def("max_hp").get("per_tier", 0)) * tier(meta, "max_hp"),
		"max_mana": float(upgrade_def("max_mana").get("per_tier", 0)) * tier(meta, "max_mana"),
		"mana_regen_mult": 1.0 + float(upgrade_def("mana_regen").get("per_tier", 0)) * tier(meta, "mana_regen"),
	}

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
