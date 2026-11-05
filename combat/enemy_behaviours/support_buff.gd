extends "res://combat/enemy_behaviours/behaviour.gd"
## Tick component: every tick, each other living non-boss enemy within buff_radius of the supporter gets
## buff_damage_scale (damage taken) and buff_speed_scale (move speed) multiplied in. Buffs are reset to 1.0
## for all enemies before the AI loop (EnemyCombat.begin_tick) and rewritten here in session enemy order, so a
## dead/frozen supporter, or an ally that left range, loses the buff the same tick.
## Precedence with shield_front: target.damage_scale = shield_scale * buff_damage_scale (multiplicative,
## recomputed from 1.0 every tick); several supporters multiply too.
const ROLE := "tick"

func tick(enemy, session, _ctx: Dictionary) -> void:
	var radius: float = float(params["buff_radius"])
	var damage_scale: float = float(params.get("buff_damage_scale",1.0))
	var speed_scale: float = float(params.get("buff_speed_scale",1.0))
	for other in session.enemies:
		if other == enemy or not other.target.alive() or "boss" in other.target.tags:
			continue
		if enemy.target.position.distance_to(other.target.position) <= radius:
			other.buff_damage_scale *= damage_scale
			other.speed_scale *= speed_scale

static func validate(params: Dictionary) -> Array:
	var issues := check("support_buff",params,["buff_radius"],["buff_radius","buff_damage_scale","buff_speed_scale"])
	if typeof(params.get("buff_radius")) in [TYPE_INT,TYPE_FLOAT] and float(params["buff_radius"]) <= 0.0:
		issues.append("support_buff: param 'buff_radius' must be > 0")
	for key in ["buff_damage_scale","buff_speed_scale"]:
		if typeof(params.get(key)) in [TYPE_INT,TYPE_FLOAT] and float(params[key]) < 0.0:
			issues.append("support_buff: param '%s' must be >= 0" % key)
	return issues
