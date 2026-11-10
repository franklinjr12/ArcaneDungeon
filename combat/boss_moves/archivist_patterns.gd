extends RefCounted
## AD-201: Drowned Archivist kit driven by boss settings. Static helpers over the BossCombat. No RNG.
## Top level: `pools` [[x,y],...] (pool centres), `emerge_status` (status id applied to the boss when it emerges),
## `freeze_stun` {ticks,radius} (emerging into a frozen pool stuns the boss; needs `water_freeze` and `stagger`).
## AD-201 step 2: `book_pages` {hp,radius,speed,turn_deg_per_tick,lifetime_ticks,damage,cap,count,spread_degrees} for the `page_throw` pattern
## (phase key `page_speed_scale`), `wisp_shield` {damage_taken_multiplier} (BossCombat: shielded while a wisp of the boss lives) and
## `storm_conduct` {duration_ticks,damage,interval_ticks} (the storm pulse also electrifies the water).
## A `submerge` move with `"exit":"pool"` surfaces at another pool (a ripple telegraph shows where) and may carry a `shockwave` splash ring.
const Warden = preload("res://combat/boss_moves/warden_patterns.gd")
const Elite = preload("res://combat/boss_moves/elite_patterns.gd")
const PAGE := "book_page"
const PAGE_KEYS := ["hp","radius","speed","turn_deg_per_tick","lifetime_ticks","damage","cap","count","spread_degrees"]
const CONDUCT_KEYS := ["duration_ticks","damage","interval_ticks"]
## Pools within this many px of the boss count as the one it dove from.
const SAME_POOL := 8.0
const FREEZE_STUN_KEYS := ["ticks","radius"]

static func _num(value) -> bool:
	return typeof(value) == TYPE_INT or typeof(value) == TYPE_FLOAT

static func uses_pools(move: Dictionary) -> bool:
	return str(move.get("exit","")) == "pool"

## Emerge point: a pool other than the one the boss is in, chosen with the move's anchor_pick relative to the player.
static func exit_point(boss, session, move: Dictionary) -> Vector2:
	var here: Vector2 = boss.target.position
	var others: Array = boss.tuning.get("pools",[]).filter(func(pool): return Vector2(float(pool[0]),float(pool[1])).distance_to(here) > SAME_POOL)
	return session.world.pick_anchor(others,session.sim.actor.position,boss.target.radius,str(move.get("anchor_pick","farthest")) == "farthest",here)

## The boss has just reappeared at its emerge point. Returns true when it surfaced into ice and was stunned instead
## (no splash, no slam, no Wet); the caller must then skip its usual end-of-move handling.
static func finish_emerge(boss, session, move: Dictionary) -> bool:
	var stun = boss.tuning.get("freeze_stun")
	if stun != null and session.water != null and session.water.frozen_near(boss.target.position,float(stun["radius"])):
		if boss._pending_roar:
			boss._after_move_or_attack(session) # the deferred roar wins over the stun
			return true
		if boss._reset_cycle_after_fire:
			boss._reset_cycle_after_fire = false
			boss.cycle = 0
		boss.stun(session,int(stun["ticks"]))
		return true
	var status := str(boss.tuning.get("emerge_status",""))
	var statuses: Dictionary = session.sim.settings["statuses"]
	if not status.is_empty() and statuses.has(status):
		boss.target.status.apply(status,session.sim.clock.tick,statuses[status],{"source_id":boss.target.id})
	if move.has("shockwave"):
		Warden.start_aftermath(boss,session,move)
	return false

static func handles(tuning: Dictionary, attack: String) -> bool:
	return attack == "page_throw" and tuning.has("book_pages")

## Same slam-shaped telegraph as a skull throw, at the boss, with the phase windup.
static func windup_fields(boss, _session, _attack: String) -> Dictionary:
	var origin: Vector2 = boss.target.position
	return {"kind":"page_throw","origin":origin,"telegraph_ticks":int(boss.tuning["phases"][boss.phase-1]["windup_ticks"]),
		"range":float(boss.tuning["telegraph_radius"]),"telegraph_shape":"slam","landing":origin}

## Queues up to `count` pages fanned over spread_degrees around the aim at the player, never beyond `cap` live + queued.
## The phase's `page_speed_scale` multiplies their speed.
static func fire(boss, session) -> void:
	var spec: Dictionary = boss.tuning["book_pages"]
	var origin: Vector2 = boss.target.position
	var aim: Vector2 = session.sim.actor.position-origin
	aim = aim.normalized() if not aim.is_zero_approx() else Vector2.RIGHT
	var settings: Dictionary = spec.duplicate()
	settings["speed"] = float(spec["speed"])*float(boss.tuning["phases"][boss.phase-1].get("page_speed_scale",1.0))
	var count := int(spec["count"])
	for index in count:
		if Elite.live_owned(boss,session,PAGE) >= int(spec["cap"]):
			break
		var offset := 0.0 if count <= 1 else deg_to_rad(float(spec["spread_degrees"]))*(float(index)/float(count-1)-0.5)
		var heading := aim.rotated(offset)
		var at: Vector2 = origin+heading*(float(boss.tuning["radius"])+float(spec["radius"]))
		if not session.world.valid_position(at,float(spec["radius"])):
			at = origin
		session.pending_spawns.append({"minion":PAGE,"position":at,"summoner_id":boss.target.id,"heading":heading,"settings":settings})

## Live lantern wisps (kind `wisp_kind`) owned by the boss; queued ones do not count.
static func live_wisps(boss, session) -> int:
	var wisp := str(boss.tuning.get("wisp_kind","lantern_wisp"))
	var count := 0
	for enemy in session.enemies:
		if enemy.kind == wisp and enemy.summoner_id == boss.target.id and enemy.target.alive():
			count += 1
	return count

static func _positive(spec, keys: Array, path: String, issues: Array) -> void:
	if typeof(spec) != TYPE_DICTIONARY:
		issues.append({"code":"BOSS_ARCHIVIST_PARAM","path":path,"message":"must be a dictionary"})
		return
	for key in keys:
		if not _num(spec.get(key)) or float(spec[key]) <= 0.0:
			issues.append({"code":"BOSS_ARCHIVIST_PARAM","path":"%s.%s" % [path,key],"message":"'%s' must be a number > 0" % key})

## BOSS_ARCHIVIST_PARAM for bad `pools`, `emerge_status`, `freeze_stun`, a pool-exit submerge without 2+ pools,
## missing or non-positive `book_pages` / `storm_conduct` keys, a `wisp_shield` multiplier outside 0..1, `page_throw` without `book_pages` and a bad `page_speed_scale`.
static func validate(settings: Dictionary) -> Array:
	var issues: Array = []
	var pools = settings.get("pools")
	if settings.has("pools") and (typeof(pools) != TYPE_ARRAY or not pools.all(func(p): return typeof(p) == TYPE_ARRAY and p.size() == 2 and _num(p[0]) and _num(p[1]))):
		issues.append({"code":"BOSS_ARCHIVIST_PARAM","path":"pools","message":"pools must be an array of [x,y] numbers"})
		pools = null
	if settings.has("emerge_status") and typeof(settings["emerge_status"]) != TYPE_STRING:
		issues.append({"code":"BOSS_ARCHIVIST_PARAM","path":"emerge_status","message":"emerge_status must be a string"})
	if settings.has("freeze_stun"):
		var stun = settings["freeze_stun"]
		if typeof(stun) != TYPE_DICTIONARY:
			issues.append({"code":"BOSS_ARCHIVIST_PARAM","path":"freeze_stun","message":"must be a dictionary"})
		else:
			for key in FREEZE_STUN_KEYS:
				if not _num(stun.get(key)) or float(stun[key]) < 1.0:
					issues.append({"code":"BOSS_ARCHIVIST_PARAM","path":"freeze_stun."+key,"message":"'%s' must be a number >= 1" % key})
		for need in ["water_freeze","stagger"]:
			if not settings.has(need):
				issues.append({"code":"BOSS_ARCHIVIST_PARAM","path":"freeze_stun","message":"freeze_stun needs a %s block" % need})
	if settings.has("book_pages"):
		_positive(settings["book_pages"],PAGE_KEYS,"book_pages",issues)
	if settings.has("storm_conduct"):
		_positive(settings["storm_conduct"],CONDUCT_KEYS,"storm_conduct",issues)
	if settings.has("wisp_shield"):
		var shield = settings["wisp_shield"]
		var multiplier = shield.get("damage_taken_multiplier") if typeof(shield) == TYPE_DICTIONARY else null
		if not _num(multiplier) or float(multiplier) < 0.0 or float(multiplier) >= 1.0:
			issues.append({"code":"BOSS_ARCHIVIST_PARAM","path":"wisp_shield.damage_taken_multiplier","message":"damage_taken_multiplier must be a number >= 0 and < 1"})
	var phases = settings.get("phases",[])
	for p in (phases.size() if typeof(phases) == TYPE_ARRAY else 0):
		if typeof(phases[p]) == TYPE_DICTIONARY:
			if phases[p].has("page_speed_scale") and not (_num(phases[p]["page_speed_scale"]) and float(phases[p]["page_speed_scale"]) > 0.0):
				issues.append({"code":"BOSS_ARCHIVIST_PARAM","path":"phases[%d].page_speed_scale" % p,"message":"page_speed_scale must be a number > 0"})
			if not settings.has("book_pages") and Elite._lists(phases[p],"page_throw"):
				issues.append({"code":"BOSS_ARCHIVIST_PARAM","path":"phases[%d]" % p,"message":"the page_throw pattern needs a book_pages block"})
		var pool = phases[p].get("pool",[]) if typeof(phases[p]) == TYPE_DICTIONARY else []
		for e in (pool.size() if typeof(pool) == TYPE_ARRAY else 0):
			var move = pool[e].get("move") if typeof(pool[e]) == TYPE_DICTIONARY else null
			if typeof(move) == TYPE_DICTIONARY and uses_pools(move) and (typeof(pools) != TYPE_ARRAY or pools.size() < 2):
				issues.append({"code":"BOSS_ARCHIVIST_PARAM","path":"phases[%d].pool[%d].move.exit" % [p,e],"message":"exit 'pool' needs a top-level 'pools' array with at least 2 entries"})
	return issues
