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
## AD-240 Mirror Glyph: wall reflections left for this beam (0 keeps the single straight segment).
var reflects_left := 0
## Points of the beam path (caster, reflection points..., end_point); only longer than 2 after a reflection.
var path: Array = []

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
	reflects_left = int(spec.get("reflects",0))

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
	var hit_wall := Rect2()
	var wall_hit := false
	for wall in walls:
		var wall_time := Projectile.segment_wall_time(start,finish,wall,0.0)
		if wall_time < reach:
			wall_hit = true
			hit_wall = wall
		reach = minf(reach,wall_time)
	end_point = start.lerp(finish,reach)
	var segments: Array = [[start,end_point,0.0]]
	var travelled := start.distance_to(end_point)
	path = [start,end_point]
	var left := reflects_left
	var remaining := float(p["beam_length"])-start.distance_to(end_point)
	var heading := aim
	while left > 0 and wall_hit and remaining > 0.5:
		left -= 1
		heading = _reflect(heading,end_point,hit_wall)
		var from := end_point+heading
		var to := from+heading*remaining
		var bounce_reach := Projectile._bounds_exit_time(from,to,bounds)
		wall_hit = false
		for wall in walls:
			var bounce_time := Projectile.segment_wall_time(from,to,wall,0.0)
			if bounce_time < bounce_reach:
				wall_hit = true
				hit_wall = wall
			bounce_reach = minf(bounce_reach,bounce_time)
		end_point = from.lerp(to,bounce_reach)
		segments.append([from,end_point,travelled])
		travelled += from.distance_to(end_point)
		path.append(end_point)
		remaining -= from.distance_to(end_point)
	position = end_point
	if (age-1) % int(p["tick_interval_ticks"]) != 0:
		return result
	result["pulse"] = true
	var half_width := float(p["beam_width"])*0.5
	var contacts: Array = []
	var seen := {}
	for segment in segments:
		var seg_start: Vector2 = segment[0]
		var seg_dir: Vector2 = (segment[1]-seg_start)
		var length := seg_dir.length()
		var seg_aim := aim if segment == segments[0] else seg_dir.normalized()
		for target in target_store.all():
			if not target.eligible(team) or seen.has(target.id):
				continue
			var along: float = (target.position-seg_start).dot(seg_aim)
			if along > length:
				continue
			along = maxf(along,0.0)
			var closest := seg_start+seg_aim*along
			if closest.distance_to(target.position) <= target.radius+half_width:
				seen[target.id] = true
				contacts.append({"target_id":target.id,"position":target.position,"effect_id":id,"along":along+float(segment[2])})
	contacts.sort_custom(func(a,b):
		if absf(float(a["along"])-float(b["along"])) < 0.000001:
			return int(a["target_id"]) < int(b["target_id"])
		return float(a["along"]) < float(b["along"]))
	if contacts.size() > max_targets:
		result["truncated"] = true
		contacts.resize(max_targets)
	result["hits"] = contacts
	return result

## Mirror the heading off the wall face nearest to the hit point.
static func _reflect(heading: Vector2, point: Vector2, wall: Rect2) -> Vector2:
	var near_x := minf(absf(point.x-wall.position.x),absf(point.x-wall.end.x))
	var near_y := minf(absf(point.y-wall.position.y),absf(point.y-wall.end.y))
	return Vector2(-heading.x,heading.y) if near_x < near_y else Vector2(heading.x,-heading.y)
