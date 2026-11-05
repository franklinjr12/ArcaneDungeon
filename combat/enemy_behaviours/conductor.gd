extends "res://combat/enemy_behaviours/behaviour.gd"
## Modifier: tags the enemy "conductor"; Lightning that hits it arcs to the nearest other target (InteractionResolver).
const ROLE := "modifier"

func modify(enemy) -> void:
	if not enemy.target.tags.has("conductor"):
		enemy.target.tags.append("conductor")

static func validate(params: Dictionary) -> Array:
	return check("conductor",params,[],[])
