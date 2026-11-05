extends "res://combat/enemy_behaviours/behaviour.gd"
## Tick component (AD-137): repeating cycle of period_ticks. The first warn_ticks of a cycle are the telegraph
## (enemy.intangible_warning, normal damage), the next intangible_ticks are intangible (enemy.intangible,
## damage scaled by intangible_damage_scale, default 0), the rest is vulnerable. Uses its own counter that
## only advances in tick(), so a frozen enemy pauses the cycle. Writes enemy.phase_scale.
const ROLE := "tick"
var _cycle_tick := 0

func tick(enemy, _session, _ctx: Dictionary) -> void:
	var warn := int(params["warn_ticks"])
	var phase := _cycle_tick % int(params["period_ticks"])
	_cycle_tick += 1
	enemy.intangible_warning = phase < warn
	enemy.intangible = phase >= warn and phase < warn+int(params["intangible_ticks"])
	enemy.phase_scale = float(params.get("intangible_damage_scale",0.0)) if enemy.intangible else 1.0
	enemy.apply_scales()

static func validate(params: Dictionary) -> Array:
	var issues := check("intangible_cycle",params,["period_ticks","warn_ticks","intangible_ticks"],["period_ticks","warn_ticks","intangible_ticks","intangible_damage_scale"])
	for key in ["period_ticks","warn_ticks","intangible_ticks"]:
		if typeof(params.get(key)) in [TYPE_INT,TYPE_FLOAT] and (typeof(params[key]) != TYPE_INT or int(params[key]) <= 0):
			issues.append("intangible_cycle: param '%s' must be an integer > 0" % key)
	if issues.is_empty() and int(params["warn_ticks"])+int(params["intangible_ticks"]) >= int(params["period_ticks"]):
		issues.append("intangible_cycle: warn_ticks + intangible_ticks must be < period_ticks")
	if typeof(params.get("intangible_damage_scale")) in [TYPE_INT,TYPE_FLOAT] and (float(params["intangible_damage_scale"]) < 0.0 or float(params["intangible_damage_scale"]) > 1.0):
		issues.append("intangible_cycle: param 'intangible_damage_scale' must be within 0..1")
	return issues
