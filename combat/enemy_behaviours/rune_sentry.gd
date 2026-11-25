extends "res://combat/enemy_behaviours/behaviour.gd"
## Attack (AD-237): a stationary pylon locks a direction toward the player at windup start (telegraph_ticks, no
## damage), then sweeps a beam clockwise by beam_sweep_degrees_per_tick for beam_active_ticks (EnemyCombat state
## "attack"). The player is hit (at most once per hit_interval_ticks) while within beam_length of the sentry and
## within beam_half_width + player radius of the beam line. enemy.intent follows the beam so the UI line rotates.
const ROLE := "attack"
const AttackIntent = preload("res://combat/attack_intent.gd")
var _direction := Vector2.RIGHT
var _hit_wait := 0

func wants_attack(_enemy, _session, _ctx: Dictionary) -> bool:
	return true

func active_ticks(enemy) -> int:
	return int(param(enemy,"beam_active_ticks"))

func build_attack(enemy, ctx: Dictionary) -> Dictionary:
	_direction = ctx["toward"].normalized()
	_hit_wait = 0
	var intent := standard_intent(enemy,ctx)
	intent["geometry"] = "line"
	intent["direction"] = _direction
	intent["range"] = float(param(enemy,"beam_length"))
	return intent

func active_tick(enemy, session, _ctx: Dictionary) -> void:
	_direction = _direction.rotated(deg_to_rad(float(param(enemy,"beam_sweep_degrees_per_tick")))).normalized()
	if enemy.intent != null:
		var fields: Dictionary = enemy.intent.snapshot()
		fields["direction"] = _direction
		enemy.intent = AttackIntent.new(fields)
	_hit_wait = maxi(0,_hit_wait-1)
	var player = session.sim.actor
	if _hit_wait > 0 or not player.alive():
		return
	var offset: Vector2 = player.position-enemy.target.position
	var along := offset.dot(_direction)
	if along < 0.0 or along > float(param(enemy,"beam_length")):
		return
	if absf(offset.cross(_direction)) > float(param(enemy,"beam_half_width"))+player.radius:
		return
	_hit_wait = int(param(enemy,"hit_interval_ticks"))
	session.damage_player(enemy.target.id,float(param(enemy,"damage")),str(params.get("channel","physical")))

static func validate(params: Dictionary) -> Array:
	var keys := ["beam_length","beam_half_width","beam_sweep_degrees_per_tick","beam_active_ticks","hit_interval_ticks"]
	var issues := check("rune_sentry",params,keys,keys)
	for key in keys:
		if typeof(params.get(key)) in [TYPE_INT,TYPE_FLOAT] and float(params[key]) <= 0.0:
			issues.append("rune_sentry: param '%s' must be > 0" % key)
	return issues
