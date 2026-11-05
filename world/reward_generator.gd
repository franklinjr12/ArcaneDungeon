extends RefCounted
## Stable independent RNG per room: cannot be altered by combat tick counts.
const Difficulty = preload("res://game/core/difficulty.gd")
var config: Dictionary = {}
var excluded: Array = []
func _init(tuning: Dictionary, excluded_ids: Array = []) -> void:
	config = tuning.duplicate(true)
	excluded = excluded_ids.duplicate()

func choices(run, room_id: String) -> Array:
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
	for id in pick_weighted(possible,wanted,random,config):
		var card: Dictionary = config.get("reward_cards", {}).get(id, {})
		options.append({"kind":"rune","id":id,"name_key":str(card.get("name_key","rune."+id+".name")),
			"behaviour_key":str(card.get("behaviour_key","rune."+id+".desc")),"rarity":rarity_of(id,config)})
	if options.size() < wanted:
		options.append({"kind":"currency","amount":Difficulty.scale_i(int(config["room_reward_currency"]),"coin_rate",0)})
	return options

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
