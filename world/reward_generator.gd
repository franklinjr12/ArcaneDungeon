extends RefCounted
## Stable independent RNG per room: cannot be altered by combat tick counts.
const Difficulty = preload("res://game/core/difficulty.gd")
const Artifacts = preload("res://world/artifacts.gd")
const BALANCE := "res://magic/data/magic_balance_v1.json"
static var _balance: Dictionary = {}
var config: Dictionary = {}
var excluded: Array = []
var excluded_artifacts: Array = []
func _init(tuning: Dictionary, excluded_ids: Array = [], excluded_artifact_ids: Array = []) -> void:
	config = tuning.duplicate(true)
	excluded = excluded_ids.duplicate()
	excluded_artifacts = excluded_artifact_ids.duplicate()

func choices(run, room_id: String, force_artifact: bool = false) -> Array:
	var possible: Array = []
	for id in config.get("reward_pool", []):
		if id not in run.unlocked and id not in excluded and id not in possible:
			possible.append(id)
	var key := str(run.seed)+":"+room_id
	var hash_value := 2166136261
	for c in key.to_utf8_buffer():
		hash_value = ((hash_value ^ int(c))*16777619) & 0x7fffffff
	var random := RandomNumberGenerator.new()
	random.seed = hash_value
	var wanted := Difficulty.scale_i(int(config["reward_choices"]),"reward_rate")
	var options: Array = []
	var completers := reaction_completers(possible,loadout_essences(run))
	for id in pick_biased(possible,wanted,random,config,completers,float(config.get("reaction_bias_weight",0.0))):
		var card: Dictionary = config.get("reward_cards", {}).get(id, {})
		options.append({"kind":"rune","id":id,"name_key":str(card.get("name_key","rune."+id+".name")),
			"behaviour_key":str(card.get("behaviour_key","rune."+id+".desc")),"rarity":rarity_of(id,config)})
	if options.size() < wanted:
		options.append({"kind":"currency","amount":Difficulty.scale_i(int(config["room_reward_currency"]),"coin_rate",0)})
	# AD-143: artifact card appended last, own RNG so the rune picks above never shift.
	var artifact_card := artifact_choice(run,hash_value,force_artifact,excluded_artifacts)
	if not artifact_card.is_empty():
		options.append(artifact_card)
	return options

static func artifact_choice(run, hash_value: int, force_artifact: bool, excluded_ids: Array = []) -> Dictionary:
	var settings: Dictionary = Artifacts.config()
	var held: Array = run.artifacts
	if held.size() >= Artifacts.max_held():
		return {}
	var candidates: Array = Artifacts.definitions().keys().filter(func(id): return id not in held and id not in excluded_ids)
	candidates.sort()
	if candidates.is_empty():
		return {}
	var random := RandomNumberGenerator.new()
	random.seed = (hash_value ^ int(settings.get("seed_salt",0))) & 0x7fffffff
	var roll := random.randf()
	if not force_artifact and roll >= float(settings.get("reward_artifact_chance",0.0)):
		return {}
	var id: String = candidates[random.randi() % candidates.size()]
	var def: Dictionary = Artifacts.definitions()[id]
	return {"kind":"artifact","id":id,"name_key":str(def["name_key"]),"behaviour_key":str(def["desc_key"]),"rarity":str(def.get("rarity","common"))}

static func rarity_of(id: String, tuning: Dictionary) -> String:
	return str(tuning.get("rune_rarity",{}).get(id,"common"))

static func weight_of(id: String, tuning: Dictionary) -> float:
	var weights: Dictionary = tuning.get("rarity_weights",{})
	var rarity := rarity_of(id,tuning)
	return float(weights.get(rarity,weights.get("common",1)))

## Weighted sampling without replacement; candidate order is preserved, weight <= 0 is never picked.
static func pick_weighted(candidates: Array, count: int, random: RandomNumberGenerator, tuning: Dictionary) -> Array:
	var pool: Array = candidates.filter(func(id): return weight_of(str(id),tuning) > 0.0)
	var picked: Array = []
	while not pool.is_empty() and picked.size() < count:
		var total := 0.0
		for id in pool:
			total += weight_of(str(id),tuning)
		var roll := random.randf()*total
		var idx := pool.size()-1
		for i in pool.size():
			roll -= weight_of(str(pool[i]),tuning)
			if roll < 0.0:
				idx = i
				break
		picked.append(pool[idx])
		pool.remove_at(idx)
	return picked

static func balance() -> Dictionary:
	if _balance.is_empty():
		var parsed = JSON.parse_string(FileAccess.get_file_as_string(BALANCE))
		_balance = parsed if parsed is Dictionary else {}
	return _balance

## Every string under an "essence_id" key, walking dictionaries and arrays (root and trigger payloads).
static func essences_of(formula: Variant) -> Array:
	var found: Array = []
	if formula is Dictionary:
		for key in formula:
			var value = formula[key]
			if str(key) == "essence_id" and value is String:
				found.append(value)
			else:
				found.append_array(essences_of(value))
	elif formula is Array:
		for item in formula:
			found.append_array(essences_of(item))
	return found

static func loadout_essences(run) -> Array:
	var formulas = run.get("formulas")
	var result: Array = []
	if not (formulas is Array):
		return result
	for id in essences_of(formulas):
		if id != "essence.neutral" and id not in result:
			result.append(id)
	return result

static func reactions_for(essences: Array) -> Array:
	var data := balance()
	var rules: Array = data.get("reactions",{}).get("rules",[]).duplicate()
	# The wet+lightning arc lives in combat/interaction_resolver.gd, not in reactions.rules.
	rules.append({"id":"wet_lightning_arc","channel":"lightning","requires_any":["wet"],"apply":[]})
	var channels: Dictionary = data.get("channels",{})
	var own: Array = []
	var statuses: Array = []
	for essence in essences:
		var def: Dictionary = channels.get(essence,{})
		own.append(str(def.get("channel","")))
		var applied := str(def.get("apply",""))
		if applied != "" and applied not in statuses:
			statuses.append(applied)
	var found: Array = []
	var changed := true
	while changed:
		changed = false
		for rule in rules:
			if rule["id"] in found or str(rule["channel"]) not in own:
				continue
			var reachable := false
			for status in rule.get("requires_any",[]):
				if status in statuses:
					reachable = true
			if not reachable:
				continue
			found.append(rule["id"])
			changed = true
			for status in rule.get("apply",[]):
				if status not in statuses:
					statuses.append(status)
	return found

static func reaction_completers(candidates: Array, loadout: Array) -> Array:
	var base := reactions_for(loadout)
	var result: Array = []
	for id in candidates:
		if not str(id).begins_with("essence.") or id in loadout:
			continue
		for reaction in reactions_for(loadout + [id]):
			if reaction not in base:
				result.append(id)
				break
	return result

## With weight <= 0 or no completers this is exactly pick_weighted (no extra RNG use).
static func pick_biased(candidates: Array, count: int, random: RandomNumberGenerator, tuning: Dictionary, completers: Array, weight: float) -> Array:
	if weight <= 0.0 or completers.is_empty():
		return pick_weighted(candidates,count,random,tuning)
	var remaining: Array = candidates.duplicate()
	var picked: Array = []
	while picked.size() < count and not remaining.is_empty():
		var favoured: Array = remaining.filter(func(id): return id in completers and weight_of(str(id),tuning) > 0.0)
		var pool: Array = remaining
		if not favoured.is_empty() and random.randf() < weight:
			pool = favoured
		var pick := pick_weighted(pool,1,random,tuning)
		if pick.is_empty():
			break
		picked.append(pick[0])
		remaining.erase(pick[0])
	return picked
