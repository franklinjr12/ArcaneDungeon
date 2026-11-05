extends "res://combat/enemy_behaviours/behaviour.gd"
## on_death component (runs once, in EnemyCombat's death_announced block): if the player is within
## explode_radius (centre distance) of the corpse, deals explode_damage through session.damage_player on
## explode_channel (default physical). Always emits a feedback event at the death position.
const ROLE := "tick"

func on_death(enemy, session) -> void:
	var player = session.sim.actor
	if player.alive() and enemy.target.position.distance_to(player.position) <= float(params["explode_radius"]):
		session.damage_player(enemy.target.id,float(params["explode_damage"]),str(params.get("explode_channel","physical")),-1,true)
	session.notify_blast(enemy.target.position)

static func validate(params: Dictionary) -> Array:
	var issues := check("explode_on_death",params,["explode_radius","explode_damage"],["explode_radius","explode_damage"])
	if typeof(params.get("explode_radius")) in [TYPE_INT,TYPE_FLOAT] and float(params["explode_radius"]) <= 0.0:
		issues.append("explode_on_death: param 'explode_radius' must be > 0")
	if params.has("explode_channel") and typeof(params["explode_channel"]) != TYPE_STRING:
		issues.append("explode_on_death: param 'explode_channel' must be a string")
	return issues
