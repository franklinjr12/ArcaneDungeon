extends RefCounted
## Deterministic HP + armor/channel-resistance model. Values in data/tuning.
var maximum := 100.0
var current := 100.0
var armor := 0.0
var resistances: Dictionary = {}

func _init(max_hp: float = 100.0, defense: float = 0.0, channel_resistance: Dictionary = {}) -> void:
	maximum = maxf(1.0,max_hp)
	current = maximum
	armor = maxf(0.0, defense)
	resistances = channel_resistance.duplicate(true)

func alive() -> bool:
	return current > 0.0

func damage(amount: float, channel: String, armor_scale: float) -> float:
	if not alive():
		return 0.0
	var fraction := clampf(float(resistances.get(channel, 0.0)), 0.0, 1.0)
	var received := maxf(0.0,amount) * (1.0 - fraction)
	received *= maxf(0.0,armor_scale) / (maxf(0.0,armor_scale) + armor)
	var dealt := minf(current,received)
	current -= dealt
	return dealt

func reset() -> void:
	current = maximum
