extends "res://combat/enemy_behaviours/behaviour.gd"
## Attack: telegraphed aimed projectile (or a volley of `shots` spaced spread_step_degrees apart,
## symmetric around the aim direction; default 1 shot); blinded enemies cannot begin a windup.
const ROLE := "attack"
const CONFIG_KEYS := ["projectile_speed"]

func wants_attack(enemy, session, _ctx: Dictionary) -> bool:
	return not enemy.target.status.has("blinded",session.sim.clock.tick)

func build_attack(enemy, ctx: Dictionary) -> Dictionary:
	return standard_intent(enemy,ctx)

func execute_attack(enemy, session) -> void:
	var player = session.sim.actor
	var direction: Vector2 = (player.position-enemy.target.position).normalized()
	var shots := int(param(enemy,"shots",1))
	var step := float(param(enemy,"spread_step_degrees",0.0))
	for i in shots:
		session.spawn_enemy_projectile(enemy.target.id,enemy.target.position,direction,float(param(enemy,"damage")),
			float(param(enemy,"projectile_speed")),float(param(enemy,"spread_degrees",0))+(float(i)-float(shots-1)*0.5)*step)

func active_ticks(enemy) -> int:
	var shots := int(param(enemy,"burst_shots",1))
	return (shots-1)*int(param(enemy,"burst_interval_ticks",0))+1 if shots > 1 else 0

## Sequential burst: each shot re-aims at the player's current position.
func active_tick(enemy, session, _ctx: Dictionary) -> void:
	var interval := int(param(enemy,"burst_interval_ticks",0))
	if interval < 1 or (enemy.state_tick-1) % interval != 0 or enemy.state_tick > active_ticks(enemy):
		return
	if not enemy._can_attack(session) or enemy.target.status.has("blinded",session.sim.clock.tick):
		return
	execute_attack(enemy,session)

static func validate(params: Dictionary) -> Array:
	var issues := check("ranged_attack",params,[],["damage","projectile_speed","spread_degrees","shots","spread_step_degrees","burst_shots","burst_interval_ticks"])
	if typeof(params.get("shots")) in [TYPE_INT,TYPE_FLOAT] and (float(params["shots"]) < 1.0 or float(params["shots"]) != floorf(float(params["shots"]))):
		issues.append("ranged_attack: param 'shots' must be an integer >= 1")
	if params.has("burst_shots") and typeof(params["burst_shots"]) in [TYPE_INT,TYPE_FLOAT]:
		var burst := float(params["burst_shots"])
		if burst < 1.0 or burst != floorf(burst):
			issues.append("ranged_attack: param 'burst_shots' must be an integer >= 1")
		elif burst > 1.0 and float(params.get("burst_interval_ticks",0)) < 1.0:
			issues.append("ranged_attack: 'burst_shots' > 1 needs 'burst_interval_ticks' >= 1")
	return issues
