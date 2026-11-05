extends "res://combat/enemy_behaviours/behaviour.gd"
## Attack: telegraphed aimed projectile; blinded enemies cannot begin a windup.
const ROLE := "attack"
const CONFIG_KEYS := ["projectile_speed"]

func wants_attack(enemy, session, _ctx: Dictionary) -> bool:
	return not enemy.target.status.has("blinded",session.sim.clock.tick)

func build_attack(enemy, ctx: Dictionary) -> Dictionary:
	return standard_intent(enemy,ctx)

func execute_attack(enemy, session) -> void:
	var player = session.sim.actor
	var direction: Vector2 = (player.position-enemy.target.position).normalized()
	session.spawn_enemy_projectile(enemy.target.id,enemy.target.position,direction,float(param(enemy,"damage")),
		float(param(enemy,"projectile_speed")),float(param(enemy,"spread_degrees",0)))

static func validate(params: Dictionary) -> Array:
	return check("ranged_attack",params,[],["damage","projectile_speed","spread_degrees"])
