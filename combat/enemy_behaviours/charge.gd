extends "res://combat/enemy_behaviours/behaviour.gd"
## Attack: after the telegraph, dash along the direction locked at windup start for charge_ticks at
## charge_speed (stops at walls unless phasing); damages the player once per charge on contact
## (distance <= enemy radius + player radius + contact_padding). Uses EnemyCombat's "attack" state.
const ROLE := "attack"
var _direction := Vector2.ZERO
var _hit := false

func wants_attack(_enemy, _session, _ctx: Dictionary) -> bool:
	return true

func active_ticks(enemy) -> int:
	return int(param(enemy,"charge_ticks"))

func build_attack(enemy, ctx: Dictionary) -> Dictionary:
	_direction = ctx["toward"].normalized()
	_hit = false
	var intent := standard_intent(enemy,ctx)
	intent["geometry"] = "line"
	intent["direction"] = _direction
	intent["range"] = float(param(enemy,"charge_speed"))*float(active_ticks(enemy))/float(ctx["tick_rate"])
	return intent

func active_tick(enemy, session, _ctx: Dictionary) -> void:
	var step: Vector2 = _direction*float(param(enemy,"charge_speed"))/float(session.sim.clock.tick_rate)
	enemy.target.position = enemy.step_body(session,enemy.target.position,step)
	var player = session.sim.actor
	if _hit or not player.alive():
		return
	if enemy.target.position.distance_to(player.position) <= enemy.target.radius+player.radius+float(params.get("contact_padding",0.0)):
		_hit = true
		session.damage_player(enemy.target.id,float(param(enemy,"damage")),str(params.get("channel","physical")))

static func validate(params: Dictionary) -> Array:
	var issues := check("charge",params,["charge_speed","charge_ticks"],["charge_speed","charge_ticks","contact_padding","damage"])
	if typeof(params.get("charge_ticks")) in [TYPE_INT,TYPE_FLOAT] and (float(params["charge_ticks"]) < 1.0 or float(params["charge_ticks"]) != floorf(float(params["charge_ticks"]))):
		issues.append("charge: param 'charge_ticks' must be an integer >= 1")
	if typeof(params.get("charge_speed")) in [TYPE_INT,TYPE_FLOAT] and float(params["charge_speed"]) <= 0.0:
		issues.append("charge: param 'charge_speed' must be > 0")
	return issues
