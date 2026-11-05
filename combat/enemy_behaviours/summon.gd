extends "res://combat/enemy_behaviours/behaviour.gd"
## Tick component: while chasing with the player perceived, every summon_cooldown_ticks spawns `count`
## enemies of summon_kind on a ring (summon_radius px) around the summoner, up to max_alive live summons
## owned by it (queued ones included). Spawns go through session.pending_spawns, flushed after the AI loop.
## Ring angles are TAU*i/count rotated by 0.5 rad per earlier batch, so positions are deterministic.
const ROLE := "tick"
var _timer := 0
var _batches := 0

func tick(enemy, session, ctx: Dictionary) -> void:
	if enemy.state != "chase" or float(ctx["distance"]) >= float(enemy.tuning["perception_radius"]):
		return
	_timer += 1
	if _timer < int(params["summon_cooldown_ticks"]):
		return
	var room: int = int(params["max_alive"])-session.summons_owned_by(enemy.target.id)
	if room <= 0:
		return
	_timer = 0
	var count: int = mini(int(params["count"]),room)
	for i in count:
		var angle: float = TAU*float(i)/float(count)+0.5*float(_batches)
		session.pending_spawns.append({"kind":str(params["summon_kind"]),"summoner_id":enemy.target.id,
			"position":enemy.target.position+Vector2.RIGHT.rotated(angle)*float(params["summon_radius"])})
	_batches += 1

static func validate(params: Dictionary) -> Array:
	var issues := check("summon",params,["summon_kind","summon_cooldown_ticks","count","max_alive","summon_radius"],
		["summon_cooldown_ticks","count","max_alive","summon_radius"])
	if typeof(params.get("summon_kind")) != TYPE_STRING or str(params.get("summon_kind","")).is_empty():
		issues.append("summon: param 'summon_kind' must be a non-empty string")
	for key in ["summon_cooldown_ticks","count","max_alive"]:
		if typeof(params.get(key)) in [TYPE_INT,TYPE_FLOAT] and (float(params[key]) < 1.0 or float(params[key]) != floorf(float(params[key]))):
			issues.append("summon: param '%s' must be an integer >= 1" % key)
	if typeof(params.get("summon_radius")) in [TYPE_INT,TYPE_FLOAT] and float(params["summon_radius"]) <= 0.0:
		issues.append("summon: param 'summon_radius' must be > 0")
	return issues
