extends RefCounted
## AD-199: Undead Warden attacks driven by boss settings: `melee` sweeps/slam, `spear_line`, `grave_rise`. Static helpers over the BossCombat.
## Each attack locks its aim when the windup starts; damage goes through session.damage_player so dash i-frames apply. No RNG.
const Difficulty = preload("res://game/core/difficulty.gd")
const MELEE_KEYS := {"arc":["windup_ticks","reach","arc_degrees","damage"],"slam":["windup_ticks","reach","damage"]}
const SPEAR_KEYS := ["windup_ticks","count","start","spacing","radius","damage"]
const GRAVE_KEYS := ["windup_ticks","cap","radius"]
const SHOCK_KEYS := ["speed","width","max_radius","damage"]

static func handles(tuning: Dictionary, attack: String) -> bool:
	var melee = tuning.get("melee")
	if typeof(melee) == TYPE_DICTIONARY and melee.has(attack):
		return true
	return (attack == "spear_line" or attack == "grave_rise") and tuning.has(attack)

## Leap landing with a `shockwave`: an expanding ring hazard (damage once, blocked by walls) and an optional delayed radial burst.
static func start_aftermath(boss, session, move: Dictionary) -> void:
	var shock: Dictionary = move["shockwave"]
	var per_tick := float(shock["speed"])/float(session.sim.clock.tick_rate)
	var lifetime := ceili(float(shock["max_radius"])/per_tick)
	var at: Vector2 = boss.target.position
	boss._aftermath.append({"at":at,"age":0,"per_tick":per_tick,"width":float(shock["width"]),"max_radius":float(shock["max_radius"]),
		"damage":float(shock["damage"]),"ring_open":true,"burst_at":int(move.get("burst_delay_ticks",-1))})
	session.add_hazard({"kind":"boss_ring","status":"","position":at,"radius":0.0,"duration_ticks":lifetime,"interval_ticks":1,
		"source_id":boss.target.id,"ring_per_tick":per_tick,"ring_width":float(shock["width"])})

## Once per tick in every state: ages the aftermath entries (ring contact, burst) and counts the optional per-phase timed summon.
static func advance(boss, session) -> void:
	if not boss._aftermath.is_empty():
		var player = session.sim.actor
		var kept: Array = []
		for ring in boss._aftermath:
			ring["age"] = int(ring["age"])+1
			var age: int = ring["age"]
			if bool(ring["ring_open"]):
				var radius: float = float(ring["per_tick"])*age
				if radius > float(ring["max_radius"]):
					ring["ring_open"] = false
				elif player.alive() and absf(player.position.distance_to(ring["at"])-radius) <= float(ring["width"])*0.5+player.radius \
						and session.world.clear_sight(ring["at"],player.position):
					session.damage_player(boss.target.id,float(ring["damage"]),"physical")
					ring["ring_open"] = false
			if int(ring["burst_at"]) >= 0 and age >= int(ring["burst_at"]):
				_burst(boss,session)
				ring["burst_at"] = -1
			if bool(ring["ring_open"]) or int(ring["burst_at"]) >= 0:
				kept.append(ring)
		boss._aftermath = kept
	if boss.tuning.has("phases") and boss.tuning["phases"][boss.phase-1].has("timed_summon") and boss.state != "roar":
		var timed: Dictionary = boss.tuning["phases"][boss.phase-1]["timed_summon"]
		var age: int = boss._summon_age
		var first := int(timed["first_ticks"])
		if age >= first and (age-first)%int(timed["every_ticks"]) == 0:
			var spec: Dictionary = boss.tuning["grave_rise"]
			boss.fire_summon(session,str(spec.get("kind","bone_thrall")),spec.get("offsets",[]),int(spec["cap"]))
			session._notify("! BOSS GRAVE_RISE",boss.target.position)
		boss._summon_age = age+1

static func _burst(boss, session) -> void:
	var number := int(boss.tuning["radial_shots"])
	for index in number:
		var heading := Vector2.RIGHT.rotated(TAU*float(index)/float(number))
		session.spawn_enemy_projectile(boss.target.id,boss.target.position,heading,float(boss.tuning["radial_damage"]),float(boss.tuning["shot_speed"]))

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
	for p in (settings["phases"].size() if typeof(settings.get("phases")) == TYPE_ARRAY else 0):
		var phase = settings["phases"][p]
		if typeof(phase) != TYPE_DICTIONARY:
			continue
		var pool = phase.get("pool",[])
		for e in (pool.size() if typeof(pool) == TYPE_ARRAY else 0):
			var move = pool[e].get("move") if typeof(pool[e]) == TYPE_DICTIONARY else null
			if typeof(move) == TYPE_DICTIONARY:
				_validate_aftermath(settings,move,"phases[%d].pool[%d].move" % [p,e],issues)
		if phase.has("timed_summon"):
			var path := "phases[%d].timed_summon" % p
			if _missing(phase["timed_summon"],["first_ticks","every_ticks"],path,issues):
				var timed: Dictionary = phase["timed_summon"]
				if _num(timed.get("first_ticks")) and float(timed["first_ticks"]) < 0.0:
					issues.append({"code":"BOSS_WARDEN_PARAM","path":path+".first_ticks","message":"first_ticks must be >= 0"})
				if _num(timed.get("every_ticks")) and float(timed["every_ticks"]) < 1.0:
					issues.append({"code":"BOSS_WARDEN_PARAM","path":path+".every_ticks","message":"every_ticks must be >= 1"})
			if not settings.has("grave_rise"):
				issues.append({"code":"BOSS_WARDEN_PARAM","path":path,"message":"timed_summon needs a grave_rise block"})
	return issues

## `shockwave` {speed,width,max_radius,damage} (all > 0) and `burst_delay_ticks` (>= 1; needs radial_shots, radial_damage, shot_speed).
static func _validate_aftermath(settings: Dictionary, move: Dictionary, path: String, issues: Array) -> void:
	if move.has("shockwave") and _missing(move["shockwave"],SHOCK_KEYS,path+".shockwave",issues):
		for key in SHOCK_KEYS:
			if _num(move["shockwave"].get(key)) and float(move["shockwave"][key]) <= 0.0:
				issues.append({"code":"BOSS_WARDEN_PARAM","path":"%s.shockwave.%s" % [path,key],"message":"'%s' must be > 0" % key})
	if move.has("burst_delay_ticks"):
		if not _num(move["burst_delay_ticks"]) or float(move["burst_delay_ticks"]) < 1.0:
			issues.append({"code":"BOSS_WARDEN_PARAM","path":path+".burst_delay_ticks","message":"burst_delay_ticks must be a number >= 1"})
		elif not move.has("shockwave"):
			issues.append({"code":"BOSS_WARDEN_PARAM","path":path+".burst_delay_ticks","message":"burst_delay_ticks needs a shockwave"})
		elif not ["radial_shots","radial_damage","shot_speed"].all(func(key): return _num(settings.get(key))):
			issues.append({"code":"BOSS_WARDEN_PARAM","path":path+".burst_delay_ticks","message":"the burst needs radial_shots, radial_damage and shot_speed"})
