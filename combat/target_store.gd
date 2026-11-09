extends RefCounted
const Target = preload("res://combat/magic_target.gd")
var _targets: Dictionary = {}
# Id-sorted snapshot, rebuilt lazily. Never mutated in place: a rebuild assigns a new array.
var _sorted: Array = []
var _dirty: bool = false

func add(target) -> bool:
	if _targets.has(target.id):
		return false
	_targets[target.id] = target
	_dirty = true
	return true

func get_target(target_id: int):
	return _targets.get(target_id,null)

func remove(target_id: int) -> void:
	if _targets.has(target_id):
		_targets[target_id].removed = true
		_targets.erase(target_id)
		_dirty = true

## Read-only: callers must not mutate the returned array.
func all() -> Array:
	if _dirty:
		var ids := _targets.keys()
		ids.sort()
		var out: Array = []
		for id in ids:
			out.append(_targets[id])
		_sorted = out
		_dirty = false
	return _sorted

func query(center: Vector2, query_radius: float, attacker_team: int, exclude_ids: Array = [], required_status: String = "", tick: int = -1) -> Array:
	var hits: Array = []
	for target in _targets.values():
		if not target.eligible(attacker_team) or target.id in exclude_ids:
			continue
		if not required_status.is_empty() and not target.status.has(required_status,tick):
			continue
		var distance := center.distance_to(target.position)
		if distance <= query_radius + target.radius:
			hits.append(target)
	if hits.size() < 2:
		return hits
	hits.sort_custom(func(a,b):
		var da: float = center.distance_squared_to(a.position)
		var db: float = center.distance_squared_to(b.position)
		if absf(da-db) < 0.000001:
			return a.id < b.id
		return da < db)
	return hits

## Same result as query(center,query_radius,attacker_team)[0] (null when that is empty), without building or sorting the list.
func nearest(center: Vector2, query_radius: float, attacker_team: int):
	var best = null
	var best_d := 0.0
	for target in _targets.values():
		if not target.eligible(attacker_team):
			continue
		var distance := center.distance_to(target.position)
		if distance > query_radius + target.radius:
			continue
		var d := center.distance_squared_to(target.position)
		var better := true
		if best != null:
			better = target.id < best.id if absf(d-best_d) < 0.000001 else d < best_d
		if better:
			best = target
			best_d = d
	return best

func advance_movers(dt: float, bounds: Rect2) -> void:
	for target in all():
		if not target.alive() or target.motion.is_zero_approx():
			continue
		target.position += target.motion * dt
		if target.position.x < bounds.position.x + target.radius or target.position.x > bounds.end.x - target.radius:
			target.motion.x = -target.motion.x
			target.position.x = clampf(target.position.x,bounds.position.x+target.radius,bounds.end.x-target.radius)
		if target.position.y < bounds.position.y + target.radius or target.position.y > bounds.end.y - target.radius:
			target.motion.y = -target.motion.y
			target.position.y = clampf(target.position.y,bounds.position.y+target.radius,bounds.end.y-target.radius)
