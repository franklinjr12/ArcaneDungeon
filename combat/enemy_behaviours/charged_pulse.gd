extends "res://combat/enemy_behaviours/behaviour.gd"
## Attack: telegraphed radial pulse around the enemy. On execute the player inside pulse_radius takes `damage` on
## pulse_channel and, if the hit was accepted, gains pulse_status (default charged).
const ROLE := "attack"

func wants_attack(_enemy, _session, _ctx: Dictionary) -> bool:
	return true

func build_attack(enemy, ctx: Dictionary) -> Dictionary:
	var intent := standard_intent(enemy,ctx)
	intent["range"] = float(params["pulse_radius"])
	return intent

func execute_attack(enemy, session) -> void:
	var actor = session.sim.actor
	if not actor.alive():
		return
	if enemy.target.position.distance_to(actor.position) > float(params["pulse_radius"])+actor.radius:
		return
	var result: Dictionary = session.damage_player(enemy.target.id,float(param(enemy,"damage")),str(params.get("pulse_channel","lightning")))
	if result.get("accepted",true) == false:
		return
	var status := str(params.get("pulse_status","charged"))
	var statuses: Dictionary = session.sim.settings["statuses"]
	if statuses.has(status):
		actor.status.apply(status,session.sim.clock.tick,statuses[status],{"source_id":enemy.target.id})

static func validate(params: Dictionary) -> Array:
	var issues := check("charged_pulse",params,["pulse_radius"],["pulse_radius"])
	if typeof(params.get("pulse_radius")) in [TYPE_INT,TYPE_FLOAT] and float(params["pulse_radius"]) <= 0.0:
		issues.append("charged_pulse: param 'pulse_radius' must be > 0")
	for key in ["pulse_channel","pulse_status"]:
		if params.has(key) and typeof(params[key]) != TYPE_STRING:
			issues.append("charged_pulse: param '%s' must be a string" % key)
	return issues
