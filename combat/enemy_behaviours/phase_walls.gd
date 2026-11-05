extends "res://combat/enemy_behaviours/behaviour.gd"
## Modifier: the enemy ignores walls when moving (only the arena bounds, shrunk by its radius, clamp it),
## and with ignore_sight true its attacks ignore line of sight. Sets flags on EnemyCombat; no movement of its own.
const ROLE := "modifier"

func modify(enemy) -> void:
	enemy.phase_walls = true
	enemy.ignore_sight = bool(params.get("ignore_sight",false))

static func validate(params: Dictionary) -> Array:
	return check("phase_walls",params,[],[],["ignore_sight"])
