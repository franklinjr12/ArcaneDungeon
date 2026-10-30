extends RefCounted
## Stable independent RNG per room: cannot be altered by combat tick counts.
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
	var options: Array = []
	while not possible.is_empty() and options.size() < int(config["reward_choices"]):
		var idx := random.randi_range(0,possible.size()-1)
		var id: String = possible[idx]
		var card: Dictionary = config.get("reward_cards", {}).get(id, {})
		options.append({"kind":"rune","id":id,"name":str(card.get("name",id)),
			"behaviour":str(card.get("behaviour",""))})
		possible.remove_at(idx)
	if options.size() < int(config["reward_choices"]):
		options.append({"kind":"currency","amount":int(config["room_reward_currency"])})
	return options
