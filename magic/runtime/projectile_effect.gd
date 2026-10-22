extends RefCounted
## Manifestation shared by all essences; high-speed swept circle collision.
var id: int
var cast_id: int
var formula_id: String
var caster_id: int
var team: int
var position: Vector2
var direction: Vector2
var speed: float
var radius: float
var life_ticks: int
var max_targets: int
var hit_ids: Dictionary = {}
var on_hit: Dictionary = {}
var root: Dictionary = {}
var expired := false
var age := 0

func _init(spec: Dictionary) -> void:
	id = int(spec["effect_id"])
	cast_id = int(spec["cast_id"])
	formula_id = str(spec["formula_id"])
	caster_id = int(spec["caster_id"])
	team = int(spec["team"])
	position = spec["position"]
	direction = spec["direction"].normalized()
	var params: Dictionary = spec["root"]["params"]
	root = spec["root"].duplicate(true)
	on_hit = spec.get("on_hit",{}).duplicate(true)
	speed = float(params["speed"])
	radius = float(params["radius"])
	life_ticks = int(params["lifetime_ticks"])
	max_targets = int(spec.get("max_targets",1))

func steer(dt: float, target_store, params: Dictionary) -> void:
	var acquire := float(params.get("acquire_radius",0))
	if acquire <= 0:
		return
	var targets: Array = target_store.query(position,acquire,team)
	if targets.is_empty():
		return
	var wanted: Vector2 = (targets[0].position-position).normalized()
	if wanted.is_zero_approx():
		return
	var from_angle := direction.angle()
	var delta := wrapf(wanted.angle()-from_angle,-PI,PI)
	var max_delta := float(params.get("turn_rate",0.0)) * dt
	direction = Vector2.RIGHT.rotated(from_angle+clampf(delta,-max_delta,max_delta)).normalized()

func advance(dt: float, target_store, bounds: Rect2, walls: Array = []) -> Array:
	if expired:
		return []
	age += 1
	if age > life_ticks:
		expired = true
		return []
	var start := position
	var end := start + direction * speed * dt
	var candidates: Array = []
	for target in target_store.all():
		if not target.eligible(team) or hit_ids.has(target.id):
			continue
		var t := _segment_circle_time(start,end,target.position,target.radius+radius)
		if t >= 0.0:
			candidates.append({"target":target,"t":t})
	candidates.sort_custom(func(a,b):
		if absf(float(a["t"])-float(b["t"])) < 0.000001:
			return a["target"].id < b["target"].id
		return a["t"] < b["t"])
	var exit_time := _bounds_exit_time(start,end,bounds)
	for wall in walls:
		exit_time = minf(exit_time,segment_wall_time(start,end,wall,radius))
	var hits: Array = []
	for contact in candidates:
		if contact["t"] > exit_time + 0.000001:
			break
		var target = contact["target"]
		hit_ids[target.id] = true
		hits.append({"target_id":target.id,"position":start.lerp(end,contact["t"]),"effect_id":id})
		if hit_ids.size() >= max_targets:
			expired = true
			position = start.lerp(end,contact["t"])
			return hits
	position = start.lerp(end,exit_time)
	if exit_time < 1.0:
		expired = true
	return hits

static func _segment_circle_time(start: Vector2, finish: Vector2, center: Vector2, combined_radius: float) -> float:
	var displacement := finish-start
	var offset := start-center
	var a := displacement.length_squared()
	if a <= 0.00000001:
		return 0.0 if offset.length_squared() <= combined_radius*combined_radius else -1.0
	var c := offset.length_squared()-combined_radius*combined_radius
	if c <= 0.0:
		return 0.0
	var b := 2.0*offset.dot(displacement)
	var delta := b*b-4.0*a*c
	if delta < 0.0:
		return -1.0
	var t := (-b-sqrt(delta))/(2.0*a)
	return t if t >= 0.0 and t <= 1.0 else -1.0

static func _bounds_exit_time(start: Vector2, finish: Vector2, bounds: Rect2) -> float:
	if not bounds.has_point(start):
		return 0.0
	if bounds.has_point(finish):
		return 1.0
	var delta := finish-start
	var t := 1.0
	if delta.x > 0:
		t = minf(t,(bounds.end.x-start.x)/delta.x)
	elif delta.x < 0:
		t = minf(t,(bounds.position.x-start.x)/delta.x)
	if delta.y > 0:
		t = minf(t,(bounds.end.y-start.y)/delta.y)
	elif delta.y < 0:
		t = minf(t,(bounds.position.y-start.y)/delta.y)
	return clampf(t,0.0,1.0)

## A swept point against an inflated solid AABB, returns first contact t in [0,1].
static func segment_wall_time(start: Vector2, finish: Vector2, wall: Rect2, padding: float = 0.0) -> float:
	var rect := Rect2(wall.position-Vector2.ONE*padding,wall.size+Vector2.ONE*padding*2.0)
	if rect.has_point(start):
		return 0.0
	var vector := finish-start
	var low := 0.0
	var high := 1.0
	for axis in 2:
		var origin: float = start.x if axis == 0 else start.y
		var component: float = vector.x if axis == 0 else vector.y
		var minimum: float = rect.position.x if axis == 0 else rect.position.y
		var maximum: float = rect.end.x if axis == 0 else rect.end.y
		if absf(component) < 0.00000001:
			if origin < minimum or origin > maximum:
				return 1.0
			continue
		var a := (minimum-origin)/component
		var b := (maximum-origin)/component
		low = maxf(low,minf(a,b))
		high = minf(high,maxf(a,b))
		if low > high:
			return 1.0
	return low if low >= 0.0 and low <= 1.0 and high >= 0.0 else 1.0
