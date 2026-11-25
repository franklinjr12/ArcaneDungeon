extends "res://combat/enemy_behaviours/behaviour.gd"
## Movement (AD-237): swarm_chase approaches like chase but bends the heading by a fixed lateral weave derived from
## the enemy id ((id % 5) - 2) * weave_degrees, so a pack fans out instead of stacking. No randomness.
const ROLE := "movement"

func movement(enemy, session, ctx: Dictionary) -> Vector2:
	if float(ctx["distance"]) <= float(param(enemy,"preferred_range")):
		return Vector2.ZERO
	var weave := float((int(enemy.target.id) % 5)-2)*float(params.get("weave_degrees",0.0))
	return nav_direction(enemy,session,ctx).rotated(deg_to_rad(weave))

static func validate(params: Dictionary) -> Array:
	var issues := check("swarm_chase",params,[],["weave_degrees","preferred_range"])
	if typeof(params.get("weave_degrees")) in [TYPE_INT,TYPE_FLOAT] and float(params["weave_degrees"]) < 0.0:
		issues.append("swarm_chase: param 'weave_degrees' must be >= 0")
	return issues
