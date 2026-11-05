extends "res://combat/enemy_behaviours/behaviour.gd"
## Tick component: damage from the front arc is scaled by front_damage_scale. The player (the source of all
## player spells) is "in front" when the angle between enemy.heading and the direction to the player is
## <= front_arc_degrees (a half-angle). Sets enemy.shield_scale each tick (1.0 otherwise); EnemyCombat
## composes it with support buffs into target.damage_scale (see EnemyCombat.apply_scales). A frozen enemy
## does not tick, so it keeps its last scale.
const ROLE := "tick"

func tick(enemy, _session, ctx: Dictionary) -> void:
	var toward: Vector2 = ctx["toward"]
	var in_front: bool = not toward.is_zero_approx() and absf(enemy.heading.angle_to(toward)) <= deg_to_rad(float(params["front_arc_degrees"]))
	enemy.shield_scale = float(params["front_damage_scale"]) if in_front else 1.0
	enemy.apply_scales()

static func validate(params: Dictionary) -> Array:
	var issues := check("shield_front",params,["front_damage_scale","front_arc_degrees"],["front_damage_scale","front_arc_degrees"])
	if typeof(params.get("front_damage_scale")) in [TYPE_INT,TYPE_FLOAT] and float(params["front_damage_scale"]) < 0.0:
		issues.append("shield_front: param 'front_damage_scale' must be >= 0")
	if typeof(params.get("front_arc_degrees")) in [TYPE_INT,TYPE_FLOAT] and (float(params["front_arc_degrees"]) < 0.0 or float(params["front_arc_degrees"]) > 180.0):
		issues.append("shield_front: param 'front_arc_degrees' must be within 0..180")
	return issues
