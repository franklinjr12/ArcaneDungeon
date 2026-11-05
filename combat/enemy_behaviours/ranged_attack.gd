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

static func validate(params: Dictionary) -> Array:
	var issues := check("ranged_attack",params,[],["damage","projectile_speed","spread_degrees","shots","spread_step_degrees"])
	if typeof(params.get("shots")) in [TYPE_INT,TYPE_FLOAT] and (float(params["shots"]) < 1.0 or float(params["shots"]) != floorf(float(params["shots"]))):
		issues.append("ranged_attack: param 'shots' must be an integer >= 1")
	return issues
