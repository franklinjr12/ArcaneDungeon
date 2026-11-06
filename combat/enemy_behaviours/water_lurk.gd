extends "res://combat/enemy_behaviours/behaviour.gd"
## Movement: the Deep eel stays in its own water body (deep water blocks the normal mover, so tick()
## steps it directly), drifting to the water point nearest the player; after a lunge it returns to water.
## Does nothing without session.water.
const ROLE := "movement"

func movement(_enemy, _session, _ctx: Dictionary) -> Vector2:
	return Vector2.ZERO

func tick(enemy, session, ctx: Dictionary) -> void:
	if enemy.state != "chase" or session.water == null:
		return
	var pos: Vector2 = enemy.target.position
	var body: int = session.water.body_of(pos)
	var goal := _goal(session.water.view(),body,pos,ctx["player"].position)
	if goal.distance_squared_to(pos) < 0.0001:
		return
	var step: Vector2 = (goal-pos).limit_length(float(param(enemy,"move_speed"))*enemy.speed_scale/float(ctx["tick_rate"]))
	if body < 0:
		enemy.target.position = step_free(session,pos,step,enemy.target.radius)
		return
	var next := pos+step
	if session.water.body_of(next) == body and session.world.bounds.has_point(next):
		enemy.target.position = next

## In water: the point of the eel's own body nearest the player (first rect wins ties). On land: the nearest water point.
static func _goal(view: Array, body: int, pos: Vector2, player: Vector2) -> Vector2:
	var from: Vector2 = player if body >= 0 else pos
	var best := pos
	var best_distance := INF
	for entry in view:
		if body >= 0 and int(entry["body"]) != body:
			continue
		var rect: Rect2 = entry["rect"]
		var point := Vector2(clampf(from.x,rect.position.x,rect.end.x),clampf(from.y,rect.position.y,rect.end.y))
		var distance := point.distance_squared_to(from)
		if distance < best_distance:
			best_distance = distance
			best = point
	return best

## Like EnemyCombat.step_body but deep-water ground blockers are ignored: only walls and arena bounds stop the body.
static func step_free(session, from: Vector2, displacement: Vector2, radius: float) -> Vector2:
	var segments := maxi(1,int(ceil(displacement.length()/6.0)))
	var stride := displacement/float(segments)
	var result := from
	for i in segments:
		if not _free(session,result+stride,radius):
			break
		result += stride
	return result

static func _free(session, point: Vector2, radius: float) -> bool:
	var bounds: Rect2 = session.world.bounds
	if point.x < bounds.position.x+radius or point.y < bounds.position.y+radius or point.x > bounds.end.x-radius or point.y > bounds.end.y-radius:
		return false
	for wall in session.world.walls:
		var nearest := Vector2(clampf(point.x,wall.position.x,wall.end.x),clampf(point.y,wall.position.y,wall.end.y))
		if nearest.distance_squared_to(point) < radius*radius:
			return false
	return true

static func validate(params: Dictionary) -> Array:
	return check("water_lurk",params,[],["move_speed"])
