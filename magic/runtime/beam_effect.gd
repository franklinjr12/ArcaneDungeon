extends RefCounted
## AD-132: channelled line from the caster. Pulses at a fixed tick interval; the first wall or bounds edge clips it.
const Projectile = preload("res://magic/runtime/projectile_effect.gd")
var id: int
var cast_id: int
var formula_id: String
var caster_id: int
var team: int
var root: Dictionary
var position := Vector2.ZERO
var end_point := Vector2.ZERO
var aim := Vector2.RIGHT
var age := 0
var expired := false
var end_reason := ""
var on_hit: Dictionary = {}

func _init(spec: Dictionary) -> void:
	id = int(spec["effect_id"])
	cast_id = int(spec["cast_id"])
	formula_id = str(spec["formula_id"])
	caster_id = int(spec["caster_id"])
	team = int(spec["team"])
	root = spec["root"].duplicate(true)
	aim = spec["direction"].normalized()
	position = spec["position"]+aim*float(root["params"]["beam_length"])
	end_point = position

func set_aim(direction: Vector2) -> void:
	if not direction.is_zero_approx():
		aim = direction.normalized()

func expire(reason: String) -> void:
	if not expired:
		expired = true
		end_reason = reason

## Returns {"pulse":bool,"hits":Array,"truncated":bool}; hits are ordered by distance along the beam, then target id.
func advance(_tick: int, caster, target_store, bounds: Rect2, walls: Array, max_targets: int) -> Dictionary:
	var result := {"pulse":false,"hits":[],"truncated":false}
	if expired:
		return result
	age += 1
	var p: Dictionary = root["params"]
	if age > int(p["lifetime_ticks"]):
		expire("lifetime")
		return result
	if caster == null or not caster.alive():
		expire("caster_lost")
		return result
	var start: Vector2 = caster.position
	var finish := start+aim*float(p["beam_length"])
	var reach := Projectile._bounds_exit_time(start,finish,bounds)
	for wall in walls:
		reach = minf(reach,Projectile.segment_wall_time(start,finish,wall,0.0))
	end_point = start.lerp(finish,reach)
	position = end_point
	if (age-1) % int(p["tick_interval_ticks"]) != 0:
		return result
	result["pulse"] = true
	var length := start.distance_to(end_point)
	var half_width := float(p["beam_width"])*0.5
	var contacts: Array = []
	for target in target_store.all():
		if not target.eligible(team):
			continue
		var along: float = (target.position-start).dot(aim)
		if along > length:
			continue
		along = maxf(along,0.0)
		var closest := start+aim*along
		if closest.distance_to(target.position) <= target.radius+half_width:
			contacts.append({"target_id":target.id,"position":target.position,"effect_id":id,"along":along})
	contacts.sort_custom(func(a,b):
		if absf(float(a["along"])-float(b["along"])) < 0.000001:
			return int(a["target_id"]) < int(b["target_id"])
		return float(a["along"]) < float(b["along"]))
	if contacts.size() > max_targets:
		result["truncated"] = true
		contacts.resize(max_targets)
	result["hits"] = contacts
	return result
