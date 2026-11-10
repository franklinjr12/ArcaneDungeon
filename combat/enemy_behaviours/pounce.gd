extends "res://combat/enemy_behaviours/behaviour.gd"
## Attack (AD-197): fast approach (chase), then a committed pounce. Direction (swipe) or landing point (leap) is
## locked when the windup starts, so a dodge or a sidestep during the long telegraph always pays off.
## style swipe: short lunge, one wide arc hit on the last lunge tick. style leap: flies to the telegraphed point, slam circle on landing.
const ROLE := "attack"
const Lurk = preload("res://combat/enemy_behaviours/water_lurk.gd")

var _origin := Vector2.ZERO
var _direction := Vector2.RIGHT
var _landing := Vector2.ZERO

func wants_attack(_enemy, _session, _ctx: Dictionary) -> bool:
	return true

func _leaps() -> bool:
	return str(params.get("style","swipe")) == "leap"

func active_ticks(_enemy) -> int:
	return int(params.get("leap_ticks",0)) if _leaps() else int(params.get("lunge_ticks",0))

func build_attack(enemy, ctx: Dictionary) -> Dictionary:
	var intent: Dictionary = standard_intent(enemy,ctx)
	_origin = enemy.target.position
	_direction = ctx["toward"].normalized()
	if _leaps():
		_landing = ctx["player"].position
		intent["telegraph_shape"] = "slam"
		intent["landing"] = _landing
		intent["range"] = float(params["slam_radius"])
	else:
		intent["telegraph_shape"] = "arc"
		intent["arc_center"] = _origin+_direction*float(params["lunge_distance"])
		intent["arc_radius"] = float(params["swipe_radius"])
		intent["arc_degrees"] = float(params["swipe_arc_degrees"])
	return intent

func active_tick(enemy, session, _ctx: Dictionary) -> void:
	var player = session.sim.actor
	var pos: Vector2 = enemy.target.position
	if _leaps():
		var step: Vector2 = (_landing-_origin)/float(params["leap_ticks"])
		enemy.target.position = Lurk.step_free(session,pos,step,enemy.target.radius)
		if enemy.state_tick >= int(params["leap_ticks"]) and player.alive() and _landing.distance_to(player.position) <= float(params["slam_radius"])+player.radius:
			_damage(enemy,session)
		return
	enemy.target.position = enemy.step_body(session,pos,_direction*float(params["lunge_distance"])/float(params["lunge_ticks"]))
	if enemy.state_tick < int(params["lunge_ticks"]) or not player.alive():
		return
	var offset: Vector2 = player.position-enemy.target.position
	if offset.length() <= float(params["swipe_radius"])+player.radius and absf(_direction.angle_to(offset)) <= deg_to_rad(float(params["swipe_arc_degrees"])*0.5):
		_damage(enemy,session)

func _damage(enemy, session) -> void:
	session.damage_player(enemy.target.id,float(param(enemy,"damage")),str(params.get("channel","physical")))

static func validate(params: Dictionary) -> Array:
	var issues := check("pounce",params,["style"],["swipe_arc_degrees","swipe_radius","lunge_distance","lunge_ticks","slam_radius","leap_ticks"])
	if not issues.is_empty():
		return issues
	var style := str(params["style"])
	if style == "swipe":
		for key in ["swipe_arc_degrees","swipe_radius","lunge_distance","lunge_ticks"]:
			if not params.has(key):
				issues.append("pounce: swipe requires param '%s'" % key)
		if float(params.get("lunge_ticks",1)) < 1.0:
			issues.append("pounce: lunge_ticks must be >= 1")
	elif style == "leap":
		for key in ["slam_radius","leap_ticks"]:
			if not params.has(key):
				issues.append("pounce: leap requires param '%s'" % key)
		if float(params.get("leap_ticks",1)) < 1.0:
			issues.append("pounce: leap_ticks must be >= 1")
	else:
		issues.append("pounce: style must be 'swipe' or 'leap'")
	return issues
