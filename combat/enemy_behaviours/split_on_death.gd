extends "res://combat/enemy_behaviours/behaviour.gd"
## on_death component: queues `count` enemies of split_kind on a ring (split_radius px, angles TAU*i/count) around the corpse.
## Spawns go through session.pending_spawns (flushed before the room-clear check). The split kind should not itself split.
const ROLE := "tick"

func on_death(enemy, session) -> void:
	var count: int = int(params["count"])
	for i in count:
		var angle: float = TAU*float(i)/float(count)
		session.pending_spawns.append({"kind":str(params["split_kind"]),"summoner_id":enemy.target.id,
			"position":enemy.target.position+Vector2.RIGHT.rotated(angle)*float(params["split_radius"])})

static func validate(params: Dictionary) -> Array:
	var issues := check("split_on_death",params,["split_kind","count","split_radius"],["count","split_radius"])
	if typeof(params.get("split_kind")) != TYPE_STRING or str(params.get("split_kind","")).is_empty():
		issues.append("split_on_death: param 'split_kind' must be a non-empty string")
	if typeof(params.get("count")) in [TYPE_INT,TYPE_FLOAT] and (float(params["count"]) < 1.0 or float(params["count"]) != floorf(float(params["count"]))):
		issues.append("split_on_death: param 'count' must be an integer >= 1")
	if typeof(params.get("split_radius")) in [TYPE_INT,TYPE_FLOAT] and float(params["split_radius"]) <= 0.0:
		issues.append("split_on_death: param 'split_radius' must be > 0")
	return issues
