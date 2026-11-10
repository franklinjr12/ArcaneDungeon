extends RefCounted
## AD-198: opt-in weighted attack pool for a boss phase. Pure data + one RNG roll per pick; no scene or session access.
## Entries: {"pattern":p}, {"combo":[a,b,...],"gap_ticks":n} or (later steps) {"move":{"mode":m,...}}; each may carry "weight" (int >= 1) and "big"; AD-199 adds "min_range"/"max_range" (entry blocked when the player is farther/closer).
const MIN_DISTINCT := 3

## First pattern of a pattern/combo entry, or "move:<mode>" for a move entry.
static func entry_key(entry: Dictionary) -> String:
	if entry.has("move"):
		return "move:%s" % str(entry["move"].get("mode",""))
	if entry.has("combo"):
		var combo: Array = entry["combo"]
		return str(combo[0]) if not combo.is_empty() else ""
	return str(entry.get("pattern",""))

## Last pattern of a combo (what actually fires last), otherwise the same as entry_key.
static func last_key(entry: Dictionary) -> String:
	if entry.has("combo"):
		var combo: Array = entry["combo"]
		return str(combo[combo.size()-1]) if not combo.is_empty() else ""
	return entry_key(entry)

## Weighted pick in data order, skipping entries whose key is `last` or in `blocked`. Always rolls the RNG exactly once.
static func pick(pool: Array, last: String, blocked: Array, rng: RandomNumberGenerator) -> Dictionary:
	var candidates: Array = []
	for entry in pool:
		var key := entry_key(entry)
		if key != last and not blocked.has(key):
			candidates.append(entry)
	if candidates.is_empty():
		for entry in pool:
			if not blocked.has(entry_key(entry)):
				candidates.append(entry)
	if candidates.is_empty():
		candidates = pool
	var total := 0
	for entry in candidates:
		total += maxi(1,int(entry.get("weight",1)))
	var roll := rng.randi_range(1,total)
	for entry in candidates:
		roll -= maxi(1,int(entry.get("weight",1)))
		if roll <= 0:
			return entry
	return candidates[candidates.size()-1]

static func _is_whole(value) -> bool:
	return typeof(value) == TYPE_INT or (typeof(value) == TYPE_FLOAT and value == floorf(value))

## Issues for every phase that carries `pool`; phases without it are not inspected.
static func validate(settings: Dictionary) -> Array:
	var issues: Array = []
	var phases = settings.get("phases",[])
	if typeof(phases) != TYPE_ARRAY:
		return issues
	for p in phases.size():
		if typeof(phases[p]) != TYPE_DICTIONARY or not phases[p].has("pool"):
			continue
		var base := "phases[%d].pool" % p
		var pool = phases[p]["pool"]
		var keys := {}
		if typeof(pool) == TYPE_ARRAY:
			for e in pool.size():
				if typeof(pool[e]) != TYPE_DICTIONARY:
					continue
				var entry: Dictionary = pool[e]
				var path := "%s[%d]" % [base,e]
				if entry.has("weight") and not (_is_whole(entry["weight"]) and int(entry["weight"]) >= 1):
					issues.append({"code":"BOSS_POOL_WEIGHT","path":path+".weight","message":"weight must be an integer >= 1"})
				for key in ["min_range","max_range"]:
					if entry.has(key) and not ((typeof(entry[key]) == TYPE_INT or typeof(entry[key]) == TYPE_FLOAT) and float(entry[key]) >= 0.0):
						issues.append({"code":"BOSS_POOL_RANGE","path":"%s.%s" % [path,key],"message":"%s must be a number >= 0" % key})
				if entry.has("combo"):
					var combo = entry["combo"]
					if typeof(combo) != TYPE_ARRAY or combo.size() < 2:
						issues.append({"code":"BOSS_POOL_COMBO","path":path+".combo","message":"combo needs at least 2 patterns"})
					if entry.has("gap_ticks") and not (_is_whole(entry["gap_ticks"]) and int(entry["gap_ticks"]) >= 0):
						issues.append({"code":"BOSS_POOL_COMBO","path":path+".gap_ticks","message":"gap_ticks must be an integer >= 0"})
					if typeof(combo) == TYPE_ARRAY and not combo.is_empty():
						keys[entry_key(entry)] = true
				elif entry.has("pattern"):
					keys[entry_key(entry)] = true
		if keys.size() < MIN_DISTINCT:
			issues.append({"code":"BOSS_POOL_TOO_SMALL","path":base,"message":"pool needs at least %d distinct attack patterns" % MIN_DISTINCT})
	return issues
