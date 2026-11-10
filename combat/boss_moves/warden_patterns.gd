extends RefCounted
## AD-199: Undead Warden attacks driven by boss settings: `melee` sweeps/slam, `spear_line`, `grave_rise`. Static helpers over the BossCombat.
## Each attack locks its aim when the windup starts; damage goes through session.damage_player so dash i-frames apply. No RNG.
const Difficulty = preload("res://game/core/difficulty.gd")
const MELEE_KEYS := {"arc":["windup_ticks","reach","arc_degrees","damage"],"slam":["windup_ticks","reach","damage"]}
const SPEAR_KEYS := ["windup_ticks","count","start","spacing","radius","damage"]
const GRAVE_KEYS := ["windup_ticks","cap","radius"]

static func handles(tuning: Dictionary, attack: String) -> bool:
	var melee = tuning.get("melee")
	if typeof(melee) == TYPE_DICTIONARY and melee.has(attack):
		return true
	return (attack == "spear_line" or attack == "grave_rise") and tuning.has(attack)

## Scaled windup; `phase_scale` (melee only) is applied after the difficulty scale, then the telegraph floor.
static func _ticks(boss, base: int, phase_scale: float) -> int:
	var scaled := Difficulty.scale_i(base,"telegraph_length")
	return maxi(roundi(float(scaled)*phase_scale),int(boss.tuning.get("min_telegraph_ticks",0)))

static func _aim(boss, session) -> Vector2:
	var offset: Vector2 = session.sim.actor.position-boss.target.position
	return offset.normalized() if not offset.is_zero_approx() else Vector2.RIGHT

## AttackIntent fields for `attack`; the aim is locked here and read back from the intent when the attack fires.
static func windup_fields(boss, session, attack: String) -> Dictionary:
	var origin: Vector2 = boss.target.position
	if attack == "spear_line":
		var spec: Dictionary = boss.tuning["spear_line"]
		var ticks := _ticks(boss,int(spec["windup_ticks"]),1.0)
		var direction := _aim(boss,session)
		var points: Array = []
		for index in int(spec["count"]):
			var at: Vector2 = origin+direction*(float(spec["start"])+float(index)*float(spec["spacing"]))
			points.append(at.clamp(session.world.bounds.position,session.world.bounds.end))
		for point in points:
			session.add_hazard({"kind":"boss_warning","status":"","position":point,"radius":float(spec["radius"]),
				"duration_ticks":ticks+1,"interval_ticks":1,"source_id":boss.target.id})
		return {"kind":attack,"origin":origin,"telegraph_ticks":ticks,"range":float(spec["radius"]),"telegraph_shape":"none",
			"direction":direction,"points":points}
	if attack == "grave_rise":
		var spec: Dictionary = boss.tuning["grave_rise"]
		return {"kind":attack,"origin":origin,"telegraph_ticks":_ticks(boss,int(spec["windup_ticks"]),1.0),"range":float(spec["radius"]),
			"telegraph_shape":"slam","landing":origin}
	var spec: Dictionary = boss.tuning["melee"][attack]
	var phase_scale := 1.0
	if boss.tuning.has("phases"):
		phase_scale = float(boss.tuning["phases"][boss.phase-1].get("windup_scale",1.0))
	var fields := {"kind":attack,"origin":origin,"telegraph_ticks":_ticks(boss,int(spec["windup_ticks"]),phase_scale),"range":float(spec["reach"]),
		"direction":_aim(boss,session)}
	if str(spec["shape"]) == "arc":
		fields.merge({"telegraph_shape":"arc","arc_center":origin,"arc_radius":float(spec["reach"]),"arc_degrees":float(spec["arc_degrees"])})
	else:
		fields.merge({"telegraph_shape":"slam","landing":origin})
	return fields

static func fire(boss, session, attack: String) -> void:
	var intent: Dictionary = boss.intent.snapshot()
	var player = session.sim.actor
	var target = boss.target
	if attack == "grave_rise":
		var spec: Dictionary = boss.tuning["grave_rise"]
		boss.fire_summon(session,str(spec.get("kind","bone_thrall")),spec.get("offsets",[]),int(spec["cap"]))
		return
	if attack == "spear_line":
		var spec: Dictionary = boss.tuning["spear_line"]
		cancel_warnings(boss,session)
		for point in intent["points"]:
			if player.position.distance_to(point) <= float(spec["radius"])+player.radius:
				session.damage_player(target.id,float(spec["damage"]),"physical")
				return
		return
	var spec: Dictionary = boss.tuning["melee"][attack]
	var offset: Vector2 = player.position-target.position
	if offset.length() > float(spec["reach"])+player.radius:
		return
	if str(spec["shape"]) == "arc" and absf(Vector2(intent["direction"]).angle_to(offset)) > deg_to_rad(float(spec["arc_degrees"]))*0.5:
		return
	session.damage_player(target.id,float(spec["damage"]),"physical")

static func cancel_warnings(boss, session) -> void:
	session.remove_hazards_from(boss.target.id,["boss_warning"])

static func _num(value) -> bool:
	return typeof(value) == TYPE_INT or typeof(value) == TYPE_FLOAT

static func _missing(spec, keys: Array, path: String, issues: Array) -> bool:
	if typeof(spec) != TYPE_DICTIONARY:
		issues.append({"code":"BOSS_WARDEN_PARAM","path":path,"message":"must be a dictionary"})
		return false
	for key in keys:
		if not _num(spec.get(key)):
			issues.append({"code":"BOSS_WARDEN_PARAM","path":"%s.%s" % [path,key],"message":"'%s' must be a number" % key})
	return true

## BOSS_WARDEN_PARAM for missing or non-numeric keys of `melee`, `spear_line` and `grave_rise`.
static func validate(settings: Dictionary) -> Array:
	var issues: Array = []
	if settings.has("melee"):
		var melee = settings["melee"]
		if typeof(melee) != TYPE_DICTIONARY:
			issues.append({"code":"BOSS_WARDEN_PARAM","path":"melee","message":"must be a dictionary"})
		else:
			for key in melee:
				var path := "melee.%s" % key
				if typeof(melee[key]) != TYPE_DICTIONARY or not MELEE_KEYS.has(str(melee[key].get("shape",""))):
					issues.append({"code":"BOSS_WARDEN_PARAM","path":path+".shape","message":"shape must be one of %s" % str(MELEE_KEYS.keys())})
				else:
					_missing(melee[key],MELEE_KEYS[str(melee[key]["shape"])],path,issues)
	if settings.has("spear_line"):
		_missing(settings["spear_line"],SPEAR_KEYS,"spear_line",issues)
	if settings.has("grave_rise") and _missing(settings["grave_rise"],GRAVE_KEYS,"grave_rise",issues):
		var offsets = settings["grave_rise"].get("offsets")
		if typeof(offsets) != TYPE_ARRAY or not offsets.all(func(o): return typeof(o) == TYPE_ARRAY and o.size() == 2 and _num(o[0]) and _num(o[1])):
			issues.append({"code":"BOSS_WARDEN_PARAM","path":"grave_rise.offsets","message":"offsets must be an array of [x,y] numbers"})
		if typeof(settings["grave_rise"].get("kind")) != TYPE_STRING:
			issues.append({"code":"BOSS_WARDEN_PARAM","path":"grave_rise.kind","message":"kind must be a string"})
	return issues
