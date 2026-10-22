extends RefCounted
## Stable independent RNG per room: cannot be altered by combat tick counts.
var config: Dictionary = {}
func _init(tuning: Dictionary) -> void:
	config = tuning.duplicate(true)

func choices(run, room_id: String) -> Array:
	var possible: Array = []
	for id in ["mod.split","mod.homing","mod.pierce","form.orb","trigger.on_hit"]:
		if id not in run.unlocked:
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
		options.append({"kind":"rune","id":possible[idx]})
		possible.remove_at(idx)
	options.append({"kind":"currency","amount":int(config["room_reward_currency"])})
	return options
