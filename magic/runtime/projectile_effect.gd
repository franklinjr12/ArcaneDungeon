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
## Computed once from the root modifiers so the per-tick loop needs no lookup.
var homing := false
var expired := false
var age := 0
## AD-143 Rebound Sigil: remaining wall/bounds bounces (0 = expire on contact, as before).
var bounces_left := 0
## Engine epsilon (not a tunable): steps a bounced projectile off the surface so the next sweep starts clear of it.
const BOUNCE_NUDGE := 0.5

func _init(spec: Dictionary) -> void:
	id = int(spec["effect_id"])
	cast_id = int(spec["cast_id"])
	formula_id = str(spec["formula_id"])
	caster_id = int(spec["caster_id"])
	team = int(spec["team"])
	position = spec["position"]
	direction = spec["direction"].normalized()
	var params: Dictionary = spec["root"]["params"]
	# The plan is a fresh per-cast snapshot and nothing writes root/on_hit, so projectiles share it.
	root = spec["root"]
	for modifier in root.get("modifiers",[]):
		if modifier["id"] == "mod.homing":
			homing = true
	on_hit = spec.get("on_hit",{})
	speed = float(params["speed"])
	radius = float(params["radius"])
	life_ticks = int(params["lifetime_ticks"])
	max_targets = int(spec.get("max_targets",1))
	bounces_left = int(spec.get("bounces_left",0))

func steer(dt: float, target_store, params: Dictionary) -> void:
	var acquire := float(params.get("acquire_radius",0))
	if acquire <= 0:
		return
	var nearest = target_store.nearest(position,acquire,team)
	if nearest == null:
		return
	var wanted: Vector2 = (nearest.position-position).normalized()
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
	if candidates.size() >= 2:
		candidates.sort_custom(func(a,b):
			if absf(float(a["t"])-float(b["t"])) < 0.000001:
				return a["target"].id < b["target"].id
			return a["t"] < b["t"])
	var exit_time := sweep_walls(start,end,walls,radius,_bounds_exit_time(start,end,bounds))
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
		if bounces_left > 0:
			# Bounce choice: reverse the heading (rather than reflecting on the hit axis), which also covers
			# starts inside a wall and corners; targets may be hit again on the way back.
			bounces_left -= 1
			direction = -direction
			hit_ids.clear()
			position += direction * BOUNCE_NUDGE
		else:
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

## minf(initial, segment_wall_time over every wall). A wall whose padded rect lies more than 0.01 away from the segment's
## AABB on some axis cannot be touched (start is outside it and the slab test returns 1.0 or has low > high), so it is skipped.
static func sweep_walls(start: Vector2, finish: Vector2, walls: Array, padding: float, initial: float) -> float:
	var result := initial
	var seg_min_x := minf(start.x,finish.x)
	var seg_max_x := maxf(start.x,finish.x)
	var seg_min_y := minf(start.y,finish.y)
	var seg_max_y := maxf(start.y,finish.y)
	for wall in walls:
		var rect := Rect2(wall.position-Vector2.ONE*padding,wall.size+Vector2.ONE*padding*2.0)
		if seg_max_x < rect.position.x-0.01 or seg_min_x > rect.end.x+0.01 \
				or seg_max_y < rect.position.y-0.01 or seg_min_y > rect.end.y+0.01:
			continue
		result = minf(result,segment_wall_time(start,finish,wall,padding))
	return result

## A swept point against an inflated solid AABB, returns first contact t in [0,1].
static func segment_wall_time(start: Vector2, finish: Vector2, wall: Rect2, padding: float = 0.0) -> float:
	var rect := Rect2(wall.position-Vector2.ONE*padding,wall.size+Vector2.ONE*padding*2.0)
	if rect.has_point(start):
		return 0.0
	var vector := finish-start
	var low := 0.0
	var high := 1.0
	if absf(vector.x) < 0.00000001:
		if start.x < rect.position.x or start.x > rect.end.x:
			return 1.0
	else:
		var ax := (rect.position.x-start.x)/vector.x
		var bx := (rect.end.x-start.x)/vector.x
		low = maxf(low,minf(ax,bx))
		high = minf(high,maxf(ax,bx))
		if low > high:
			return 1.0
	if absf(vector.y) < 0.00000001:
		if start.y < rect.position.y or start.y > rect.end.y:
			return 1.0
	else:
		var ay := (rect.position.y-start.y)/vector.y
		var by := (rect.end.y-start.y)/vector.y
		low = maxf(low,minf(ay,by))
		high = minf(high,maxf(ay,by))
		if low > high:
			return 1.0
	return low if low >= 0.0 and low <= 1.0 and high >= 0.0 else 1.0
