extends RefCounted
## AD-201: Drowned Archivist kit driven by boss settings. Static helpers over the BossCombat. No RNG.
## Top level: `pools` [[x,y],...] (pool centres), `emerge_status` (status id applied to the boss when it emerges),
## `freeze_stun` {ticks,radius} (emerging into a frozen pool stuns the boss; needs `water_freeze` and `stagger`).
## A `submerge` move with `"exit":"pool"` surfaces at another pool (a ripple telegraph shows where) and may carry a `shockwave` splash ring.
const Warden = preload("res://combat/boss_moves/warden_patterns.gd")
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

## BOSS_ARCHIVIST_PARAM for bad `pools`, `emerge_status`, `freeze_stun`, and a pool-exit submerge without 2+ pools.
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
	var phases = settings.get("phases",[])
	for p in (phases.size() if typeof(phases) == TYPE_ARRAY else 0):
		var pool = phases[p].get("pool",[]) if typeof(phases[p]) == TYPE_DICTIONARY else []
		for e in (pool.size() if typeof(pool) == TYPE_ARRAY else 0):
			var move = pool[e].get("move") if typeof(pool[e]) == TYPE_DICTIONARY else null
			if typeof(move) == TYPE_DICTIONARY and uses_pools(move) and (typeof(pools) != TYPE_ARRAY or pools.size() < 2):
				issues.append({"code":"BOSS_ARCHIVIST_PARAM","path":"phases[%d].pool[%d].move.exit" % [p,e],"message":"exit 'pool' needs a top-level 'pools' array with at least 2 entries"})
	return issues
