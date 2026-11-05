extends "res://combat/enemy_behaviours/behaviour.gd"
## Movement: navigate toward the player while farther than preferred_range.
const ROLE := "movement"

func movement(enemy, session, ctx: Dictionary) -> Vector2:
	if float(ctx["distance"]) > float(param(enemy,"preferred_range")):
		return session.world.navigate_direction(enemy.target.position,ctx["player"].position,enemy.target.radius)
	return Vector2.ZERO

static func validate(params: Dictionary) -> Array:
	return check("chase",params,[],["preferred_range"])
