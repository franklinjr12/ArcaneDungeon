extends RefCounted
## AD-198: boss movement helpers. Continuous modes (walk_to_player, strafe) run only while the boss is not winding up;
## discrete modes (reposition, leap, submerge, blink) are pool entries driven by boss_combat.gd. All settings are data.
const Lurk = preload("res://combat/enemy_behaviours/water_lurk.gd")
const CONTINUOUS := {"walk_to_player":["speed","stop_range"],"strafe":["speed","preferred_range","margin"],"float_path":["speed","waypoints","prefer"]}
const DISCRETE := {"reposition":["speed","max_ticks"],"leap":["telegraph_ticks","flight_ticks","radius","damage"],
	"submerge":["telegraph_ticks","submerged_ticks","emerge_telegraph_ticks","radius","damage"],"blink":["blink_ticks","radius"]}

## One tick of continuous movement; `boss` is the BossCombat, `spec` the phase's `movement` dictionary.
static func continuous_step(boss, session, spec: Dictionary) -> void:
	if str(spec["mode"]) == "float_path":
		_float_step(boss,session,spec)
		return
	var player = session.sim.actor
	var target = boss.target
	if not player.alive():
		return
	var step := float(spec["speed"])/float(session.sim.clock.tick_rate)
	var offset: Vector2 = player.position-target.position
	var distance := offset.length()
	if distance < 0.0001:
		return
	var move := Vector2.ZERO
	if str(spec["mode"]) == "walk_to_player":
		var stop := float(spec["stop_range"])
		if distance <= stop:
			return
		move = session.world.navigate_direction(target.position,player.position,target.radius)*minf(step,distance-stop)
	else:
		var radial := offset/distance
		var preferred := float(spec["preferred_range"])
		var margin := float(spec["margin"])
		if distance > preferred+margin:
			move = radial*step
		elif distance < preferred-margin:
			move = -radial*step
		else:
			var side := 1.0 if (target.id%2 == 0) != boss.strafe_flipped else -1.0
			move = radial.rotated(PI*0.5)*side*step
	var moved: Vector2 = session.world.move_body(target.position,move,target.radius)
	if moved.is_equal_approx(target.position) and str(spec["mode"]) == "strafe":
		boss.strafe_flipped = not boss.strafe_flipped
	target.position = moved

## AD-200 float_path: drifts along `waypoints` with Lurk.step_free (deep water does not block, walls and bounds do) and never stops.
## Arriving, or making no progress, picks the adjacent waypoint farther from (prefer "away") or nearer to ("toward") the player; ties go to the lower index.
static func _float_step(boss, session, spec: Dictionary) -> void:
	var points: Array = spec["waypoints"].map(func(point): return Vector2(float(point[0]),float(point[1])))
	var target = boss.target
	if boss._waypoint < 0 or boss._waypoint >= points.size():
		boss._waypoint = _nearest(points,target.position)
	var step := float(spec["speed"])/float(session.sim.clock.tick_rate)
	var gap: Vector2 = points[boss._waypoint]-target.position
	var moved: Vector2 = Lurk.step_free(session,target.position,gap.limit_length(step),target.radius)
	var stuck := moved.is_equal_approx(target.position)
	target.position = moved
	if stuck or moved.distance_to(points[boss._waypoint]) < 0.001:
		boss._waypoint = _adjacent(points,boss._waypoint,session.sim.actor.position,str(spec["prefer"]) == "away")

static func _nearest(points: Array, from: Vector2) -> int:
	var best := 0
	for index in points.size():
		if from.distance_squared_to(points[index]) < from.distance_squared_to(points[best]):
			best = index
	return best

static func _adjacent(points: Array, index: int, player: Vector2, away: bool) -> int:
	var best := index
	for candidate in [index-1,index+1]:
		if candidate < 0 or candidate >= points.size():
			continue
		if best == index:
			best = candidate
			continue
		var better: bool = player.distance_squared_to(points[candidate]) > player.distance_squared_to(points[best]) if away \
			else player.distance_squared_to(points[candidate]) < player.distance_squared_to(points[best])
		if better:
			best = candidate
	return best

static func _missing(spec: Dictionary, keys: Array, path: String, issues: Array) -> void:
	for key in keys:
		if not spec.has(key):
			issues.append({"code":"BOSS_MOVE_PARAM","path":"%s.%s" % [path,key],"message":"movement needs '%s'" % key})

static func _validate_float(spec: Dictionary, path: String, issues: Array) -> void:
	var points = spec.get("waypoints")
	if spec.has("waypoints") and (typeof(points) != TYPE_ARRAY or points.is_empty() or not points.all(func(p): return typeof(p) == TYPE_ARRAY and p.size() == 2 \
			and (typeof(p[0]) == TYPE_INT or typeof(p[0]) == TYPE_FLOAT) and (typeof(p[1]) == TYPE_INT or typeof(p[1]) == TYPE_FLOAT))):
		issues.append({"code":"BOSS_MOVE_PARAM","path":path+".waypoints","message":"waypoints must be a non-empty array of [x,y] numbers"})
	if spec.has("prefer") and not ["away","toward"].has(str(spec["prefer"])):
		issues.append({"code":"BOSS_MOVE_PARAM","path":path+".prefer","message":"prefer must be 'away' or 'toward'"})
	if spec.has("speed") and not ((typeof(spec["speed"]) == TYPE_INT or typeof(spec["speed"]) == TYPE_FLOAT) and float(spec["speed"]) > 0.0):
		issues.append({"code":"BOSS_MOVE_PARAM","path":path+".speed","message":"speed must be a number > 0"})

## Issues for phase `movement` blocks and `move` pool entries: BOSS_MOVE_MODE, BOSS_MOVE_PARAM, BOSS_MOVE_ANCHORS.
static func validate(settings: Dictionary) -> Array:
	var issues: Array = []
	var phases = settings.get("phases",[])
	if typeof(phases) != TYPE_ARRAY:
		return issues
	var anchors = settings.get("anchors",[])
	var has_anchors: bool = typeof(anchors) == TYPE_ARRAY and not anchors.is_empty()
	for p in phases.size():
		if typeof(phases[p]) != TYPE_DICTIONARY:
			continue
		if phases[p].has("movement"):
			var path := "phases[%d].movement" % p
			var spec = phases[p]["movement"]
			if typeof(spec) != TYPE_DICTIONARY or not CONTINUOUS.has(str(spec.get("mode",""))):
				issues.append({"code":"BOSS_MOVE_MODE","path":path+".mode","message":"mode must be one of %s" % str(CONTINUOUS.keys())})
			else:
				_missing(spec,CONTINUOUS[str(spec["mode"])],path,issues)
				if str(spec["mode"]) == "float_path":
					_validate_float(spec,path,issues)
		var pool = phases[p].get("pool",[])
		if typeof(pool) != TYPE_ARRAY:
			continue
		for e in pool.size():
			if typeof(pool[e]) != TYPE_DICTIONARY or not pool[e].has("move"):
				continue
			var path := "phases[%d].pool[%d].move" % [p,e]
			var spec = pool[e]["move"]
			var mode := str(spec.get("mode","")) if typeof(spec) == TYPE_DICTIONARY else ""
			if not DISCRETE.has(mode):
				issues.append({"code":"BOSS_MOVE_MODE","path":path+".mode","message":"mode must be one of %s" % str(DISCRETE.keys())})
				continue
			_missing(spec,DISCRETE[mode],path,issues)
			var needs_anchors: bool = mode != "leap" or str(spec.get("target","player")) == "anchor"
			if needs_anchors and not has_anchors:
				issues.append({"code":"BOSS_MOVE_ANCHORS","path":path,"message":"%s needs a non-empty top-level 'anchors' array" % mode})
	return issues
