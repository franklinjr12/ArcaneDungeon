extends RefCounted
## Follows caster, rotates at fixed ticks, and re-hits with a per-target cooldown.
var id: int
var cast_id: int
var formula_id: String
var caster_id: int
var team: int
var root: Dictionary
var position := Vector2.ZERO
var age := 0
var expired := false
var hit_at: Dictionary = {}
var angle := 0.0

func _init(spec: Dictionary) -> void:
	id = int(spec["effect_id"])
	cast_id = int(spec["cast_id"])
	formula_id = str(spec["formula_id"])
	caster_id = int(spec["caster_id"])
	team = int(spec["team"])
	root = spec["root"].duplicate(true)

func advance(dt: float, tick: int, caster, target_store, min_rehit_ticks: int) -> Array:
	if expired:
		return []
	age += 1
	var p: Dictionary = root["params"]
	if age > int(p["lifetime_ticks"]) or caster == null or not caster.alive():
		expired = true
		return []
	angle += float(p["angular_speed"])*dt
	position = caster.position+Vector2.RIGHT.rotated(angle)*float(p["orbit_radius"])
	var result: Array = []
	for target in target_store.query(position,float(p["orb_radius"]),team):
		if tick-int(hit_at.get(target.id,-100000)) < min_rehit_ticks:
			continue
		hit_at[target.id] = tick
		result.append({"target_id":target.id,"position":position,"effect_id":id})
	return result
