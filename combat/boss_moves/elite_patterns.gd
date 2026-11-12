extends RefCounted
## AD-200: elite mini-boss attacks driven by boss settings: top-level `homing_skull` and `decoy` blocks. Static helpers over the BossCombat. No RNG.
## `homing_skull` {hp,radius,speed,turn_deg_per_tick,lifetime_ticks,damage,cap}; `decoy` {hp,radius,damage_multiplier,copies:[pattern names]}.
## A phase with `spawn_decoy:true` queues one decoy at the anchor farthest from the boss when its roar begins.
## Storm crystal: `beam_sweep` {windup_ticks,sweep_degrees,deg_per_tick,length,width,damage,hit_interval_ticks} (phase `beam_speed_scale`),
## `electrify` {duration_ticks,damage,interval_ticks}, `water_freeze` {radius,ice_ticks} (Cold freezes water cells) and
## `small_crystals` {kind,offsets,cap,hp,radius} (queued at the roar of a phase with `small_crystals:true`).
const Minion = preload("res://combat/boss_moves/elite_minion.gd")
const Projectile = preload("res://magic/runtime/projectile_effect.gd")
const Warden = preload("res://combat/boss_moves/warden_patterns.gd")
const SKULL_KEYS := ["hp","radius","speed","turn_deg_per_tick","lifetime_ticks","damage","cap"]
const DECOY_KEYS := ["hp","radius","damage_multiplier"]
const BEAM_KEYS := ["windup_ticks","sweep_degrees","deg_per_tick","length","width","damage","hit_interval_ticks"]
const ELECTRIFY_KEYS := ["duration_ticks","damage","interval_ticks"]
const FREEZE_KEYS := ["radius","ice_ticks"]
const CRYSTAL_KEYS := ["cap","hp","radius"]
const COLD := "essence.cold"

static func handles(tuning: Dictionary, attack: String) -> bool:
	return ["homing_skull","beam_sweep","electrify"].has(attack) and tuning.has(attack)

static func windup_fields(boss, session, attack: String) -> Dictionary:
	var origin: Vector2 = boss.target.position
	if attack == "beam_sweep":
		return _beam_windup(boss,session,origin)
	var ticks := int(boss.tuning["phases"][boss.phase-1]["windup_ticks"]) if boss.tuning.has("phases") else int(boss.tuning["windup_ticks"])
	if attack == "electrify":
		for entry in (session.water.view() if session.water != null else []):
			var rect: Rect2 = entry["rect"]
			session.add_hazard({"kind":"boss_water_warning","status":"","position":rect.get_center(),"radius":rect.size.length()*0.5,
				"duration_ticks":ticks+1,"interval_ticks":1,"source_id":boss.target.id,"rect":rect})
		return {"kind":attack,"origin":origin,"telegraph_ticks":ticks,"range":float(boss.tuning["telegraph_radius"]),"telegraph_shape":"none"}
	return {"kind":attack,"origin":origin,"telegraph_ticks":ticks,"range":float(boss.tuning["telegraph_radius"]),"telegraph_shape":"slam","landing":origin}

## Beam telegraph: the angle is locked toward the player now, half a sweep behind the sweep direction (which alternates each cast).
static func _beam_windup(boss, session, origin: Vector2) -> Dictionary:
	var spec: Dictionary = boss.tuning["beam_sweep"]
	var ticks: int = Warden._ticks(boss,int(spec["windup_ticks"]),1.0)
	var aim: Vector2 = session.sim.actor.position-origin
	var angle: float = (aim if not aim.is_zero_approx() else Vector2.RIGHT).angle()-float(boss._beam_dir)*deg_to_rad(float(spec["sweep_degrees"]))*0.5
	var scale := _beam_scale(boss)
	var lifetime := ticks+ceili(float(spec["sweep_degrees"])/(float(spec["deg_per_tick"])*scale))+2
	var id: int = session.add_hazard({"kind":"boss_beam","status":"","position":origin,"radius":float(spec["length"]),"duration_ticks":lifetime,
		"interval_ticks":1,"source_id":boss.target.id,"beam_angle":angle,"beam_width":float(spec["width"]),"telegraph":true})
	boss._beam = {"angle":angle,"dir":boss._beam_dir,"swept":0.0,"hazard":id,"next_hit":0}
	return {"kind":"beam_sweep","origin":origin,"telegraph_ticks":ticks,"range":float(spec["length"]),"telegraph_shape":"none","beam_angle":angle}

static func _beam_scale(boss) -> float:
	return float(boss.tuning["phases"][boss.phase-1].get("beam_speed_scale",1.0)) if boss.tuning.has("phases") else 1.0

static func _beam_hazard(session, id: int) -> Variant:
	for hazard in session.hazards:
		if int(hazard["id"]) == id:
			return hazard
	return null

## The windup is over: the beam starts sweeping on the next tick (state "casting"). The next cast sweeps the other way.
static func begin_cast(boss, session) -> void:
	boss._beam_dir = -boss._beam_dir
	boss._state("casting",session.sim.clock.tick)

## One casting tick: float on, rotate, hit the player once per hit_interval_ticks, and finish after sweep_degrees.
static func casting_tick(boss, session) -> void:
	var spec: Dictionary = boss.tuning["beam_sweep"]
	var beam: Dictionary = boss._beam
	boss._walk(session)
	var left := float(spec["sweep_degrees"])-float(beam["swept"])
	var step := minf(float(spec["deg_per_tick"])*_beam_scale(boss),left)
	beam["swept"] = float(beam["swept"])+step
	beam["angle"] = float(beam["angle"])+float(beam["dir"])*deg_to_rad(step)
	var origin: Vector2 = boss.target.position
	var hazard = _beam_hazard(session,int(beam["hazard"]))
	if hazard != null:
		hazard["position"] = origin
		hazard["beam_angle"] = beam["angle"]
		hazard["telegraph"] = false
	var tick: int = session.sim.clock.tick
	var player = session.sim.actor
	if player.alive() and tick >= int(beam["next_hit"]) and _beam_touches(session,origin,float(beam["angle"]),spec,player):
		beam["next_hit"] = tick+int(spec["hit_interval_ticks"])
		session.damage_player(boss.target.id,float(spec["damage"]),"lightning")
	if float(beam["swept"]) >= float(spec["sweep_degrees"])-0.0001:
		cancel(boss,session)
		boss.finish_cast("beam_sweep",session)

## Player centre within width/2 + radius of the beam segment, which a wall cuts short (a wall between the boss and the closest point shadows it).
static func _beam_touches(session, origin: Vector2, angle: float, spec: Dictionary, player) -> bool:
	var end: Vector2 = origin+Vector2.RIGHT.rotated(angle)*float(spec["length"])
	var closest: Vector2 = Geometry2D.get_closest_point_to_segment(player.position,origin,end)
	return closest.distance_to(player.position) <= float(spec["width"])*0.5+player.radius and session.world.clear_sight(origin,closest)

## Drops the boss's beam and water warnings (roar, death, stun, end of cast).
static func cancel(boss, session) -> void:
	boss._beam = {}
	session.remove_hazards_from(boss.target.id,["boss_beam","boss_water_warning"] if boss.tuning.has("electrify") else ["boss_beam"])

## Queues one skull from `origin` (the boss, or a decoy copy with `mult` damage) unless the boss already owns `cap` skulls (live or queued).
static func fire(boss, session, attack: String, origin: Vector2, mult: float = 1.0) -> void:
	if attack == "electrify":
		_electrify(boss,session)
		return
	var spec: Dictionary = boss.tuning["homing_skull"]
	if live_owned(boss,session,"homing_skull") >= int(spec["cap"]):
		return
	var aim: Vector2 = session.sim.actor.position-origin
	aim = aim.normalized() if not aim.is_zero_approx() else Vector2.RIGHT
	var settings: Dictionary = spec.duplicate()
	settings["damage"] = float(spec["damage"])*mult
	var at: Vector2 = origin+aim*(float(boss.tuning["radius"])+float(spec["radius"]))
	if not session.world.valid_position(at,float(spec["radius"])):
		at = origin
	session.pending_spawns.append({"minion":"homing_skull","position":at,"summoner_id":boss.target.id,"heading":aim,"settings":settings})

static func _electrify(boss, session) -> void:
	session.remove_hazards_from(boss.target.id,["boss_water_warning"])
	electrify_water(boss,session,boss.tuning["electrify"])

## The water lights up for spec.duration_ticks: standing in it hurts every interval (session.water_shock); no water, no effect.
## Shared by `electrify` and the Archivist's `storm_conduct`.
static func electrify_water(boss, session, spec: Dictionary) -> void:
	if session.water == null:
		return
	session.water.electrify_all(session.sim.clock.tick+int(spec["duration_ticks"]))
	session.water_shock = {"source_id":boss.target.id,"damage":float(spec["damage"]),"interval_ticks":int(spec["interval_ticks"]),"channel":"lightning"}

## Cold answer, once per tick: Cold projectiles (their step this tick) and Cold burst/field/beam areas freeze the water cells they touch.
static func freeze_water(boss, session) -> void:
	var spec: Dictionary = boss.tuning["water_freeze"]
	var sim = session.sim
	var until: int = sim.clock.tick+int(spec["ice_ticks"])
	var radius := float(spec["radius"])
	var dt := 1.0/float(sim.clock.tick_rate)
	for entry in sim.active:
		if entry["kind"] != "projectile" or entry["effect"].expired or str(entry["effect"].root["essence"]["id"]) != COLD:
			continue
		var effect = entry["effect"]
		session.water.freeze_segment(effect.position-effect.direction*effect.speed*dt,effect.position,radius,until)
	for visual in sim.visuals:
		if str(visual.get("essence","")) != COLD or visual.has("freeze_seen"):
			continue
		match str(visual["kind"]):
			"burst":
				visual["freeze_seen"] = true
				session.water.freeze_circle(visual["position"],float(visual["radius"]),until)
			"field":
				session.water.freeze_circle(visual["position"],float(visual["radius"]),until)
			"beam":
				session.water.freeze_segment(visual["from"],visual["to"],radius,until)

## Queues the phase's small crystals around the boss (overrides hp/radius on the spawn), never beyond the cap.
static func queue_crystals(boss, session) -> void:
	if not boss.tuning.has("small_crystals") or not bool(boss.tuning["phases"][boss.phase-1].get("small_crystals",false)):
		return
	var spec: Dictionary = boss.tuning["small_crystals"]
	boss.fire_summon(session,str(spec["kind"]),spec["offsets"],int(spec["cap"]),{"hp":float(spec["hp"]),"radius":float(spec["radius"])})

## Live plus queued minions of `minion_kind` owned by the boss.
static func live_owned(boss, session, minion_kind: String) -> int:
	var count := 0
	for enemy in session.enemies:
		if enemy is Minion and enemy.kind == minion_kind and enemy.summoner_id == boss.target.id and enemy.target.alive():
			count += 1
	for spec in session.pending_spawns:
		if str(spec.get("minion","")) == minion_kind and int(spec["summoner_id"]) == boss.target.id:
			count += 1
	return count

static func live_decoy(boss, session):
	for enemy in session.enemies:
		if enemy is Minion and enemy.kind == "decoy" and enemy.summoner_id == boss.target.id and enemy.target.alive():
			return enemy
	return null

## Roar of a `spawn_decoy` phase: one decoy (never a second while one lives or is queued) at the anchor farthest from the boss.
static func queue_decoy(boss, session) -> void:
	if not boss.tuning.has("decoy") or not bool(boss.tuning["phases"][boss.phase-1].get("spawn_decoy",false)) or live_owned(boss,session,"decoy") > 0:
		return
	var spec: Dictionary = boss.tuning["decoy"]
	var anchors: Array = boss.tuning.get("anchors",[])
	var at: Vector2 = session.world.pick_anchor(anchors,boss.target.position,float(spec["radius"]),true,boss.target.position)
	if anchors.is_empty() or at == boss.target.position:
		return
	session.pending_spawns.append({"minion":"decoy","position":at,"summoner_id":boss.target.id,"settings":spec})

static func copies(boss, session, attack: String):
	var decoy = live_decoy(boss,session) if boss.tuning.has("decoy") else null
	return decoy if decoy != null and boss.tuning["decoy"].get("copies",[]).has(attack) else null

## The decoy shows the boss's telegraph from its own position.
static func mirror_windup(boss, session, attack: String, fields: Dictionary) -> void:
	var decoy = copies(boss,session,attack)
	if decoy == null:
		return
	var at: Vector2 = decoy.target.position
	var moved := fields.duplicate(true)
	for key in ["origin","landing","arc_center"]:
		if moved.has(key):
			moved[key] = at
	decoy.show_windup(moved)

static func _num(value) -> bool:
	return typeof(value) == TYPE_INT or typeof(value) == TYPE_FLOAT

static func _check(spec, keys: Array, path: String, issues: Array) -> bool:
	if typeof(spec) != TYPE_DICTIONARY:
		issues.append({"code":"BOSS_ELITE_PARAM","path":path,"message":"must be a dictionary"})
		return false
	for key in keys:
		if not _num(spec.get(key)) or float(spec[key]) <= 0.0:
			issues.append({"code":"BOSS_ELITE_PARAM","path":"%s.%s" % [path,key],"message":"'%s' must be a number > 0" % key})
	return true

## BOSS_ELITE_PARAM for missing or non-positive keys of `homing_skull`, `decoy`, `beam_sweep`, `electrify`, `water_freeze` and `small_crystals`, a `spawn_decoy` phase without decoy + anchors, or an elite attack without its block.
static func validate(settings: Dictionary) -> Array:
	var issues: Array = []
	if settings.has("homing_skull"):
		_check(settings["homing_skull"],SKULL_KEYS,"homing_skull",issues)
	if settings.has("decoy") and _check(settings["decoy"],DECOY_KEYS,"decoy",issues):
		var copied = settings["decoy"].get("copies")
		if typeof(copied) != TYPE_ARRAY or not copied.all(func(entry): return typeof(entry) == TYPE_STRING):
			issues.append({"code":"BOSS_ELITE_PARAM","path":"decoy.copies","message":"copies must be an array of pattern names"})
	for block in [["beam_sweep",BEAM_KEYS],["electrify",ELECTRIFY_KEYS],["water_freeze",FREEZE_KEYS]]:
		if settings.has(block[0]):
			_check(settings[block[0]],block[1],block[0],issues)
	if settings.has("small_crystals") and _check(settings["small_crystals"],CRYSTAL_KEYS,"small_crystals",issues):
		var crystals: Dictionary = settings["small_crystals"]
		var offsets = crystals.get("offsets")
		if typeof(crystals.get("kind")) != TYPE_STRING:
			issues.append({"code":"BOSS_ELITE_PARAM","path":"small_crystals.kind","message":"kind must be a string"})
		if typeof(offsets) != TYPE_ARRAY or not offsets.all(func(o): return typeof(o) == TYPE_ARRAY and o.size() == 2 and _num(o[0]) and _num(o[1])):
			issues.append({"code":"BOSS_ELITE_PARAM","path":"small_crystals.offsets","message":"offsets must be an array of [x,y] numbers"})
	var phases = settings.get("phases",[])
	for p in (phases.size() if typeof(phases) == TYPE_ARRAY else 0):
		if typeof(phases[p]) != TYPE_DICTIONARY:
			continue
		var path := "phases[%d]" % p
		if phases[p].has("beam_speed_scale") and not (_num(phases[p]["beam_speed_scale"]) and float(phases[p]["beam_speed_scale"]) > 0.0):
			issues.append({"code":"BOSS_ELITE_PARAM","path":path+".beam_speed_scale","message":"beam_speed_scale must be a number > 0"})
		if bool(phases[p].get("small_crystals",false)) and not settings.has("small_crystals"):
			issues.append({"code":"BOSS_ELITE_PARAM","path":path+".small_crystals","message":"small_crystals needs a small_crystals block"})
		if bool(phases[p].get("spawn_decoy",false)):
			var anchors = settings.get("anchors",[])
			if not settings.has("decoy") or typeof(anchors) != TYPE_ARRAY or anchors.is_empty():
				issues.append({"code":"BOSS_ELITE_PARAM","path":path+".spawn_decoy","message":"spawn_decoy needs a decoy block and non-empty anchors"})
		for attack in ["homing_skull","beam_sweep","electrify"]:
			if not settings.has(attack) and _lists(phases[p],attack):
				issues.append({"code":"BOSS_ELITE_PARAM","path":path,"message":"the %s pattern needs a %s block" % [attack,attack]})
	return issues

static func _lists(phase: Dictionary, attack: String) -> bool:
	var names: Array = []
	if typeof(phase.get("patterns")) == TYPE_ARRAY:
		names.append_array(phase["patterns"])
	if typeof(phase.get("pool")) == TYPE_ARRAY:
		for entry in phase["pool"]:
			if typeof(entry) == TYPE_DICTIONARY:
				names.append(entry.get("pattern",""))
				names.append_array(entry["combo"] if typeof(entry.get("combo")) == TYPE_ARRAY else [])
	return names.has(attack)
