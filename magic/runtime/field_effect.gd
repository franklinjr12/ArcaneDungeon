extends RefCounted
## AD-132: ground zone at a fixed point that re-applies its essence to enemies inside at a fixed tick interval.
const Burst = preload("res://magic/runtime/burst_effect.gd")
var id: int
var cast_id: int
var formula_id: String
var caster_id: int
var team: int
var root: Dictionary
var position := Vector2.ZERO
var radius := 0.0
var age := 0
var expired := false
var on_hit: Dictionary = {}

func _init(spec: Dictionary) -> void:
	id = int(spec["effect_id"])
	cast_id = int(spec["cast_id"])
	formula_id = str(spec["formula_id"])
	caster_id = int(spec["caster_id"])
	team = int(spec["team"])
	root = spec["root"].duplicate(true)
	position = spec["position"]
	radius = float(root["params"]["field_radius"])

## Returns {"pulse":bool,"hits":Array,"truncated":bool}; contacts are already distance-then-id ordered.
func advance(_tick: int, target_store, max_targets: int) -> Dictionary:
	var result := {"pulse":false,"hits":[],"truncated":false}
	if expired:
		return result
	age += 1
	var p: Dictionary = root["params"]
	if age > int(p["field_duration_ticks"]):
		expired = true
		return result
	if (age-1) % int(p["tick_interval_ticks"]) != 0:
		return result
	result["pulse"] = true
	var contacts: Array = Burst.contacts(position,radius,team,target_store)
	if contacts.size() > max_targets:
		result["truncated"] = true
		contacts.resize(max_targets)
	for contact in contacts:
		contact["effect_id"] = id
	result["hits"] = contacts
	return result
