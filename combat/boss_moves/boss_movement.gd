extends RefCounted
## AD-198: boss movement helpers. Continuous modes (walk_to_player, strafe) run only while the boss is not winding up;
## discrete modes (reposition, leap, submerge, blink) are pool entries driven by boss_combat.gd. All settings are data.
const CONTINUOUS := {"walk_to_player":["speed","stop_range"],"strafe":["speed","preferred_range","margin"]}
const DISCRETE := {"reposition":["speed","max_ticks"],"leap":["telegraph_ticks","flight_ticks","radius","damage"],
	"submerge":["telegraph_ticks","submerged_ticks","emerge_telegraph_ticks","radius","damage"],"blink":["blink_ticks","radius"]}

## One tick of continuous movement; `boss` is the BossCombat, `spec` the phase's `movement` dictionary.
static func continuous_step(boss, session, spec: Dictionary) -> void:
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

static func _missing(spec: Dictionary, keys: Array, path: String, issues: Array) -> void:
	for key in keys:
		if not spec.has(key):
			issues.append({"code":"BOSS_MOVE_PARAM","path":"%s.%s" % [path,key],"message":"movement needs '%s'" % key})

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
