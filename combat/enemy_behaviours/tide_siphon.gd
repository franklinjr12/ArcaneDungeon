extends "res://combat/enemy_behaviours/behaviour.gd"
## Tick component (AD-238): tide_siphon. Every puddle_cooldown_ticks (while the player is within perception range) it
## drops a Wet puddle puddle_offset units from the player toward itself (deterministic, no randomness), as a session
## hazard sourced from the siphon. It never owns more than max_puddles live puddles. Hazards wet everything inside,
## enemies and the player alike, so the player can use the same puddles for their own wet-lightning reactions.
## A dead siphon's puddles are deliberately NOT removed: they persist until their duration ends so the player can
## still use them. wet_lightning_scale is read by CombatSession.damage_player: lightning from this enemy deals that
## multiple to a Wet player (the combo the puddles set up).
const ROLE := "tick"

var _ticks_since: int = 0

func tick(enemy, session, ctx: Dictionary) -> void:
	_ticks_since += 1
	if _ticks_since < int(params["puddle_cooldown_ticks"]) or float(ctx["distance"]) > float(enemy.tuning["perception_radius"]):
		return
	var own := 0
	for hazard in session.hazards:
		if int(hazard["source_id"]) == enemy.target.id and str(hazard["kind"]) == "puddle":
			own += 1
	if own >= int(params["max_puddles"]):
		return
	_ticks_since = 0
	var player = ctx["player"]
	var position: Vector2 = player.position+(enemy.target.position-player.position).normalized()*float(params["puddle_offset"])
	session.add_hazard({"kind":"puddle","status":"wet","position":position,"radius":float(params["puddle_radius"]),
		"duration_ticks":int(params["puddle_duration_ticks"]),"interval_ticks":int(params["puddle_interval_ticks"]),
		"source_id":enemy.target.id})

static func validate(params: Dictionary) -> Array:
	var keys := ["puddle_radius","puddle_duration_ticks","puddle_interval_ticks","puddle_cooldown_ticks","max_puddles","puddle_offset","wet_lightning_scale"]
	var issues := check("tide_siphon",params,keys,keys)
	for key in keys:
		if typeof(params.get(key)) in [TYPE_INT,TYPE_FLOAT]:
			var value := float(params[key])
			if key == "puddle_offset":
				if value < 0.0:
					issues.append("tide_siphon: param 'puddle_offset' must be >= 0")
			elif value <= 0.0:
				issues.append("tide_siphon: param '%s' must be > 0" % key)
	for key in ["puddle_duration_ticks","puddle_interval_ticks","puddle_cooldown_ticks","max_puddles"]:
		if typeof(params.get(key)) == TYPE_FLOAT and not is_equal_approx(float(params[key]),roundf(float(params[key]))):
			issues.append("tide_siphon: param '%s' must be an integer" % key)
	return issues
