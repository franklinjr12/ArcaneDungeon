extends "res://world/arena_geometry.gd"
## AD-174: ArenaGeometry with a per-wall broad-phase and a cached visibility-graph corner set. Every query returns exactly
## what the base class returns (checked by tests/qa/demo_perf_probe.gd --check-equivalence); only the work done differs.
## Caches are dropped whenever walls or ground_blockers differ from the last call (run_flow and env_props mutate them).
var _cached_walls: Array = []
var _cached_blockers: Array = []
## radius -> {"corners": PackedVector2Array, "clear": PackedByteArray} (clear[i*n+j]: 0 unknown, 1 clear, 2 blocked; directed)
var _graphs: Dictionary = {}

func valid_position(point: Vector2, radius: float) -> bool:
	if point.x < bounds.position.x+radius or point.y < bounds.position.y+radius or point.x > bounds.end.x-radius or point.y > bounds.end.y-radius:
		return false
	var reach := radius+0.01
	var squared := radius*radius
	for wall in walls:
		if point.x < wall.position.x-reach or point.x > wall.end.x+reach or point.y < wall.position.y-reach or point.y > wall.end.y+reach:
			continue
		var nearest := Vector2(clampf(point.x,wall.position.x,wall.end.x),clampf(point.y,wall.position.y,wall.end.y))
		if nearest.distance_squared_to(point) < squared:
			return false
	for blocker in ground_blockers:
		if point.x < blocker.position.x-reach or point.x > blocker.end.x+reach or point.y < blocker.position.y-reach or point.y > blocker.end.y+reach:
			continue
		var nearest := Vector2(clampf(point.x,blocker.position.x,blocker.end.x),clampf(point.y,blocker.position.y,blocker.end.y))
		if nearest.distance_squared_to(point) < squared:
			return false
	return true

func clear_sight(origin: Vector2, destination: Vector2, padding: float = 0.0) -> bool:
	return not _segment_blocked(origin,destination,walls,padding)

func walk_clear(origin: Vector2, destination: Vector2, padding: float = 0.0) -> bool:
	if _segment_blocked(origin,destination,walls,padding):
		return false
	return not _segment_blocked(origin,destination,ground_blockers,padding)

## True when some rect makes segment_wall_time < 0.99999. A rect whose padded bounds lie more than 0.01 from the segment's
## AABB on some axis cannot be touched (same argument as Projectile.sweep_walls), so only the other rects run the real test.
func _segment_blocked(origin: Vector2, destination: Vector2, rects: Array, padding: float) -> bool:
	var reach := padding+0.01
	var low_x := minf(origin.x,destination.x)
	var high_x := maxf(origin.x,destination.x)
	var low_y := minf(origin.y,destination.y)
	var high_y := maxf(origin.y,destination.y)
	for rect in rects:
		if high_x < rect.position.x-reach or low_x > rect.end.x+reach or high_y < rect.position.y-reach or low_y > rect.end.y+reach:
			continue
		if Projectile.segment_wall_time(origin,destination,rect,padding) < 0.99999:
			return true
	return false

func _graph_for(radius: float) -> Dictionary:
	if walls != _cached_walls or ground_blockers != _cached_blockers:
		_graphs.clear()
		_cached_walls = walls.duplicate()
		_cached_blockers = ground_blockers.duplicate()
	if _graphs.has(radius):
		return _graphs[radius]
	var corners := PackedVector2Array()
	for wall in walls+ground_blockers:
		var space: float = radius+7.0
		for x in [wall.position.x-space,wall.end.x+space]:
			for y in [wall.position.y-space,wall.end.y+space]:
				var candidate := Vector2(x,y)
				if valid_position(candidate,radius):
					corners.append(candidate)
	var clear := PackedByteArray()
	clear.resize(corners.size()*corners.size())
	var graph := {"corners":corners,"clear":clear}
	_graphs[radius] = graph
	return graph

## Same visibility-graph Dijkstra as the base; corner-to-corner walk_clear results are memoised per radius.
func navigate_direction(start: Vector2, destination: Vector2, radius: float) -> Vector2:
	if walk_clear(start,destination,radius):
		return (destination-start).normalized()
	var graph := _graph_for(radius)
	var corners: PackedVector2Array = graph["corners"]
	var clear: PackedByteArray = graph["clear"]
	var corner_count := corners.size()
	var points := PackedVector2Array([start,destination])
	points.append_array(corners)
	var count := points.size()
	var distances := PackedFloat64Array()
	distances.resize(count)
	distances.fill(INF)
	var parents := PackedInt32Array()
	parents.resize(count)
	parents.fill(-1)
	var visited := PackedByteArray()
	visited.resize(count)
	distances[0] = 0.0
	for k in count:
		var index := -1
		var best := INF
		for i in count:
			if visited[i] == 0 and distances[i] < best:
				best = distances[i]
				index = i
		if index == -1:
			break
		if index == 1:
			break
		visited[index] = 1
		var from_point: Vector2 = points[index]
		var row := (index-2)*corner_count
		for candidate_index in count:
			if visited[candidate_index] != 0 or candidate_index == index:
				continue
			if index >= 2 and candidate_index >= 2:
				var slot := row+candidate_index-2
				var known := clear[slot]
				if known == 0:
					known = 1 if walk_clear(from_point,points[candidate_index],radius) else 2
					clear[slot] = known
				if known == 2:
					continue
			elif not walk_clear(from_point,points[candidate_index],radius):
				continue
			var candidate_distance: float = best+from_point.distance_to(points[candidate_index])
			if candidate_distance+0.0001 < distances[candidate_index]:
				distances[candidate_index] = candidate_distance
				parents[candidate_index] = index
	if parents[1] == -1:
		return (destination-start).normalized()
	var waypoint := 1
	while parents[waypoint] > 0:
		waypoint = parents[waypoint]
	return (points[waypoint]-start).normalized()
