extends RefCounted
## Shared collision and occlusion for actors, enemy attacks, and spell projectiles.
const Projectile = preload("res://magic/runtime/projectile_effect.gd")
var bounds := Rect2()
var walls: Array = []
## AD-138: rects that block walking only (deep water); spells and sight cross them.
var ground_blockers: Array = []
func _init(arena: Dictionary) -> void:
	bounds = Rect2(0,0,float(arena["width"]),float(arena["height"]))
	for dims in arena["walls"]:
		walls.append(Rect2(float(dims[0]),float(dims[1]),float(dims[2]),float(dims[3])))

func valid_position(point: Vector2, radius: float) -> bool:
	if point.x < bounds.position.x+radius or point.y < bounds.position.y+radius or point.x > bounds.end.x-radius or point.y > bounds.end.y-radius:
		return false
	for wall in walls:
		var nearest := Vector2(clampf(point.x,wall.position.x,wall.end.x),clampf(point.y,wall.position.y,wall.end.y))
		if nearest.distance_squared_to(point) < radius*radius:
			return false
	for blocker in ground_blockers:
		var nearest := Vector2(clampf(point.x,blocker.position.x,blocker.end.x),clampf(point.y,blocker.position.y,blocker.end.y))
		if nearest.distance_squared_to(point) < radius*radius:
			return false
	return true

## AD-198: anchors are [x,y] arrays or Vector2. Only anchors that fit `radius` count; ties go to the lowest index.
func pick_anchor(anchors: Array, reference: Vector2, radius: float, farthest: bool, fallback: Vector2) -> Vector2:
	var best := fallback
	var best_distance := -INF if farthest else INF
	var found := false
	for anchor in anchors:
		var point := _anchor_point(anchor)
		if not valid_position(point,radius):
			continue
		var distance := point.distance_squared_to(reference)
		if not found or (distance > best_distance if farthest else distance < best_distance):
			best = point
			best_distance = distance
			found = true
	return best

## `point` if a body of `radius` fits there, else the nearest fitting anchor, else `fallback` (the caller's current position).
func nearest_open_point(point: Vector2, anchors: Array, radius: float, fallback: Vector2) -> Vector2:
	if valid_position(point,radius):
		return point
	return pick_anchor(anchors,point,radius,false,fallback)

static func _anchor_point(anchor) -> Vector2:
	return anchor if anchor is Vector2 else Vector2(float(anchor[0]),float(anchor[1]))

func add_ground_blockers(rects: Array) -> void:
	for rect in rects:
		ground_blockers.append(rect)

func move_body(point: Vector2, movement: Vector2, radius: float) -> Vector2:
	# Substepping prevents fast dash/mob traversal from skipping walls.
	var segments := maxi(1,int(ceil(movement.length()/6.0)))
	var stride := movement/float(segments)
	var result := point
	for i in segments:
		if valid_position(result+Vector2(stride.x,0.0),radius):
			result.x += stride.x
		if valid_position(result+Vector2(0.0,stride.y),radius):
			result.y += stride.y
	return result

func clear_sight(origin: Vector2, destination: Vector2, padding: float = 0.0) -> bool:
	for wall in walls:
		if Projectile.segment_wall_time(origin,destination,wall,padding) < 0.99999:
			return false
	return true

## Sight plus ground blockers: what an actor can walk straight along (spells and sight ignore blockers).
func walk_clear(origin: Vector2, destination: Vector2, padding: float = 0.0) -> bool:
	if not clear_sight(origin,destination,padding):
		return false
	for blocker in ground_blockers:
		if Projectile.segment_wall_time(origin,destination,blocker,padding) < 0.99999:
			return false
	return true

## Stable visibility graph path around axis-aligned obstacles, not a terrain/navmesh system.
func navigate_direction(start: Vector2, destination: Vector2, radius: float) -> Vector2:
	if walk_clear(start,destination,radius):
		return (destination-start).normalized()
	var points: Array = [start,destination]
	for wall in walls+ground_blockers:
		var space: float = radius+7.0
		for x in [wall.position.x-space,wall.end.x+space]:
			for y in [wall.position.y-space,wall.end.y+space]:
				var candidate := Vector2(x,y)
				if valid_position(candidate,radius):
					points.append(candidate)
	var distances: Array = []
	var parents: Array = []
	var visited: Array = []
	for i in points.size():
		distances.append(INF)
		parents.append(-1)
		visited.append(false)
	distances[0] = 0.0
	for k in points.size():
		var index := -1
		var best := INF
		for i in points.size():
			if not visited[i] and float(distances[i]) < best:
				best = float(distances[i])
				index = i
		if index == -1:
			break
		if index == 1:
			break
		visited[index] = true
		for candidate_index in points.size():
			if visited[candidate_index] or candidate_index == index:
				continue
			if not walk_clear(points[index],points[candidate_index],radius):
				continue
			var candidate_distance: float = best+points[index].distance_to(points[candidate_index])
			if candidate_distance+0.0001 < float(distances[candidate_index]):
				distances[candidate_index] = candidate_distance
				parents[candidate_index] = index
	if parents[1] == -1:
		return (destination-start).normalized()
	var waypoint := 1
	while int(parents[waypoint]) > 0:
		waypoint = int(parents[waypoint])
	return (points[waypoint]-start).normalized()
