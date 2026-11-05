extends "res://combat/enemy_behaviours/behaviour.gd"
## on_death component (runs once, in EnemyCombat's death_announced block): leaves a ground hazard at the corpse
## that applies puddle_status (default wet) to everything inside puddle_radius every puddle_interval_ticks
## for puddle_duration_ticks. The hazard itself is advanced by CombatSession.
const ROLE := "tick"

func on_death(enemy, session) -> void:
	session.add_hazard({"kind":"puddle","status":str(params.get("puddle_status","wet")),"position":enemy.target.position,
		"radius":float(params["puddle_radius"]),"duration_ticks":int(params["puddle_duration_ticks"]),
		"interval_ticks":int(params["puddle_interval_ticks"]),"source_id":enemy.target.id})

static func validate(params: Dictionary) -> Array:
	var keys := ["puddle_radius","puddle_duration_ticks","puddle_interval_ticks"]
	var issues := check("death_puddle",params,keys,keys)
	for key in keys:
		if typeof(params.get(key)) in [TYPE_INT,TYPE_FLOAT] and float(params[key]) <= 0.0:
			issues.append("death_puddle: param '%s' must be > 0" % key)
	for key in ["puddle_duration_ticks","puddle_interval_ticks"]:
		if typeof(params.get(key)) == TYPE_FLOAT and not is_equal_approx(float(params[key]),roundf(float(params[key]))):
			issues.append("death_puddle: param '%s' must be an integer" % key)
	if params.has("puddle_status") and typeof(params["puddle_status"]) != TYPE_STRING:
		issues.append("death_puddle: param 'puddle_status' must be a string")
	return issues
