extends RefCounted
## AD-200: elite mini-boss attacks driven by boss settings: top-level `homing_skull` and `decoy` blocks. Static helpers over the BossCombat. No RNG.
## `homing_skull` {hp,radius,speed,turn_deg_per_tick,lifetime_ticks,damage,cap}; `decoy` {hp,radius,damage_multiplier,copies:[pattern names]}.
## A phase with `spawn_decoy:true` queues one decoy at the anchor farthest from the boss when its roar begins.
const Minion = preload("res://combat/boss_moves/elite_minion.gd")
const SKULL_KEYS := ["hp","radius","speed","turn_deg_per_tick","lifetime_ticks","damage","cap"]
const DECOY_KEYS := ["hp","radius","damage_multiplier"]

static func handles(tuning: Dictionary, attack: String) -> bool:
	return attack == "homing_skull" and tuning.has("homing_skull")

static func windup_fields(boss, _session, attack: String) -> Dictionary:
	var origin: Vector2 = boss.target.position
	var ticks := int(boss.tuning["phases"][boss.phase-1]["windup_ticks"]) if boss.tuning.has("phases") else int(boss.tuning["windup_ticks"])
	return {"kind":attack,"origin":origin,"telegraph_ticks":ticks,"range":float(boss.tuning["telegraph_radius"]),"telegraph_shape":"slam","landing":origin}

## Queues one skull from `origin` (the boss, or a decoy copy with `mult` damage) unless the boss already owns `cap` skulls (live or queued).
static func fire(boss, session, origin: Vector2, mult: float = 1.0) -> void:
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

## BOSS_ELITE_PARAM for missing or non-positive keys of `homing_skull` and `decoy`, a `spawn_decoy` phase without decoy + anchors, or a skull attack without its block.
static func validate(settings: Dictionary) -> Array:
	var issues: Array = []
	if settings.has("homing_skull"):
		_check(settings["homing_skull"],SKULL_KEYS,"homing_skull",issues)
	if settings.has("decoy") and _check(settings["decoy"],DECOY_KEYS,"decoy",issues):
		var copied = settings["decoy"].get("copies")
		if typeof(copied) != TYPE_ARRAY or not copied.all(func(entry): return typeof(entry) == TYPE_STRING):
			issues.append({"code":"BOSS_ELITE_PARAM","path":"decoy.copies","message":"copies must be an array of pattern names"})
	var phases = settings.get("phases",[])
	for p in (phases.size() if typeof(phases) == TYPE_ARRAY else 0):
		if typeof(phases[p]) != TYPE_DICTIONARY:
			continue
		var path := "phases[%d]" % p
		if bool(phases[p].get("spawn_decoy",false)):
			var anchors = settings.get("anchors",[])
			if not settings.has("decoy") or typeof(anchors) != TYPE_ARRAY or anchors.is_empty():
				issues.append({"code":"BOSS_ELITE_PARAM","path":path+".spawn_decoy","message":"spawn_decoy needs a decoy block and non-empty anchors"})
		if not settings.has("homing_skull") and _lists_skull(phases[p]):
			issues.append({"code":"BOSS_ELITE_PARAM","path":path,"message":"the homing_skull pattern needs a homing_skull block"})
	return issues

static func _lists_skull(phase: Dictionary) -> bool:
	var names: Array = []
	if typeof(phase.get("patterns")) == TYPE_ARRAY:
		names.append_array(phase["patterns"])
	if typeof(phase.get("pool")) == TYPE_ARRAY:
		for entry in phase["pool"]:
			if typeof(entry) == TYPE_DICTIONARY:
				names.append(entry.get("pattern",""))
				names.append_array(entry["combo"] if typeof(entry.get("combo")) == TYPE_ARRAY else [])
	return names.has("homing_skull")
