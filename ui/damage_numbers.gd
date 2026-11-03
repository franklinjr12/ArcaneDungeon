extends RefCounted
## AD-015 (GDD §5): damage numbers are always neutral white; element shown by a symbol left of the number.
const COLOR := Color(1,1,1,1)
const SYMBOLS := {"fire":"flame","water":"droplet","lightning":"bolt"}
# Presentation-only constants, not gameplay tunables.
const LIFETIME_TICKS := 40
const RISE_PER_TICK := 0.5
const STACK_GAP := 2.0
const LINE_HEIGHT := 14.0

var popups: Array = []
var _seen := {}

static func symbol_for(element: String) -> String:
	var key := element.trim_prefix("essence.")
	return SYMBOLS.get(key,"")

static func format(amount: float, element: String) -> Dictionary:
	return {"text": str(maxi(1,roundi(amount))), "symbol": symbol_for(element), "color": COLOR}

## AD-093: pure deterministic layout. items: {anchor: top-left, size, group, order}. Groups are processed in
## first-appearance order, items in spawn order; an item overlapping any placed rect moves up until clear.
## Returns rects in input order.
static func stack_layout(items: Array) -> Array[Rect2]:
	var rects: Array[Rect2] = []
	rects.resize(items.size())
	var groups: Array = []
	for item in items:
		if not groups.has(item["group"]):
			groups.append(item["group"])
	var placed: Array[Rect2] = []
	for group in groups:
		var members: Array = []
		for i in items.size():
			if str(items[i]["group"]) == str(group):
				members.append(i)
		members.sort_custom(func(a, b): return int(items[a]["order"]) < int(items[b]["order"]) or (int(items[a]["order"]) == int(items[b]["order"]) and a < b))
		for i in members:
			var rect := Rect2(items[i]["anchor"],items[i]["size"])
			var moved := true
			while moved:
				moved = false
				for other in placed:
					var hit := rect.intersection(other)
					if hit.has_area():
						rect.position.y = other.position.y-rect.size.y-STACK_GAP
						moved = true
			rects[i] = rect
			placed.append(rect)
	return rects

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
			popup["target_id"] = target.id
			popup["spawn_tick"] = tick
			popup["index"] = i
			popups.append(popup)
	popups = popups.filter(func(p): return tick-int(p["spawn_tick"]) <= LIFETIME_TICKS)
