extends RefCounted
## AD-015 (GDD §5): damage numbers are always neutral white; element shown by a symbol left of the number.
const COLOR := Color(1,1,1,1)
const SYMBOLS := {"fire":"flame","water":"droplet","lightning":"bolt"}
# Presentation-only constants, not gameplay tunables.
const LIFETIME_TICKS := 40
const RISE_PER_TICK := 0.5

var popups: Array = []
var _seen := {}

static func symbol_for(element: String) -> String:
	var key := element.trim_prefix("essence.")
	return SYMBOLS.get(key,"")

static func format(amount: float, element: String) -> Dictionary:
	return {"text": str(maxi(1,roundi(amount))), "symbol": symbol_for(element), "color": COLOR}

func reset() -> void:
	popups.clear()
	_seen.clear()

func update(targets: Array, tick: int) -> void:
	for target in targets:
		var fresh: int = target.hit_count - int(_seen.get(target.id,target.hit_count))
		_seen[target.id] = target.hit_count
		if fresh <= 0:
			continue
		var count := mini(fresh,target.damage_log.size())
		var first: int = target.damage_log.size()-count
		for i in count:
			var entry: Dictionary = target.damage_log[first+i]
			var popup := format(float(entry["amount"]),str(entry["channel"]))
			popup["position"] = target.position
			popup["spawn_tick"] = tick
			popup["index"] = i
			popups.append(popup)
	popups = popups.filter(func(p): return tick-int(p["spawn_tick"]) <= LIFETIME_TICKS)
