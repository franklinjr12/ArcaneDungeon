extends "res://combat/enemy_behaviours/behaviour.gd"
## Movement: never moves (the base movement hook already returns Vector2.ZERO). Pair with ranged_attack,
## optionally with its `shots` / `spread_step_degrees` params for a volley.
const ROLE := "movement"

func movement(_enemy, _session, _ctx: Dictionary) -> Vector2:
	return Vector2.ZERO

static func validate(params: Dictionary) -> Array:
	return check("turret",params,[],[])
