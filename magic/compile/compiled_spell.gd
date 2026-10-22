extends RefCounted
## No mutable Dictionary escapes; cache shares this object safely.
var _plan: Dictionary = {}

func _init(plan: Dictionary) -> void:
	_plan = plan.duplicate(true)

func snapshot() -> Dictionary:
	return _plan.duplicate(true)

func formula_id() -> String:
	return str(_plan.get("formula_id",""))

func mana_cost() -> int:
	return int(_plan.get("mana_cost",0))

func cooldown_ticks() -> int:
	return int(_plan.get("cooldown_ticks",0))

func complexity() -> int:
	return int(_plan.get("complexity",0))
