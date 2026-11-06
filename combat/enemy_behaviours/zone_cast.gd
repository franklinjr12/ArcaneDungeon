extends "res://combat/enemy_behaviours/behaviour.gd"
## Attack: telegraphed ground zone. The player's position at windup start is locked as the zone centre (stored in the
## intent as "target"); on execute a hazard (existing puddle pipeline) applies zone_status (default wet) there.
const ROLE := "attack"

func wants_attack(_enemy, _session, _ctx: Dictionary) -> bool:
	return true

func build_attack(enemy, ctx: Dictionary) -> Dictionary:
	var intent := standard_intent(enemy,ctx)
	intent["target"] = ctx["player"].position
	intent["range"] = float(params["zone_radius"])
	return intent

func execute_attack(enemy, session) -> void:
	var locked: Vector2 = enemy.intent.snapshot()["target"]
	session.add_hazard({"kind":"puddle","status":str(params.get("zone_status","wet")),"position":locked,
		"radius":float(params["zone_radius"]),"duration_ticks":int(params["zone_duration_ticks"]),
		"interval_ticks":int(params["zone_interval_ticks"]),"source_id":enemy.target.id})

static func validate(params: Dictionary) -> Array:
	var keys := ["zone_radius","zone_duration_ticks","zone_interval_ticks"]
	var issues := check("zone_cast",params,keys,keys)
	for key in keys:
		if typeof(params.get(key)) in [TYPE_INT,TYPE_FLOAT] and float(params[key]) <= 0.0:
			issues.append("zone_cast: param '%s' must be > 0" % key)
	for key in ["zone_duration_ticks","zone_interval_ticks"]:
		if typeof(params.get(key)) == TYPE_FLOAT and not is_equal_approx(float(params[key]),roundf(float(params[key]))):
			issues.append("zone_cast: param '%s' must be an integer" % key)
	if params.has("zone_status") and typeof(params["zone_status"]) != TYPE_STRING:
		issues.append("zone_cast: param 'zone_status' must be a string")
	return issues
