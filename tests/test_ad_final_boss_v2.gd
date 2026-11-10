extends RefCounted
## AD-201 Drowned Archivist v2 step 1: pool dive (ripple-telegraphed pool-to-pool emerge, splash ring, Wet on emerge, freeze-stun). All settings are synthetic.
const Session = preload("res://combat/combat_session.gd")
const BossCombat = preload("res://combat/boss_combat.gd")
const Difficulty = preload("res://game/core/difficulty.gd")
const A := Vector2(400,200)
const B := Vector2(1000,200)
const C := Vector2(700,750)
const POOLS := [[400,200],[1000,200],[700,750]]
const SHOCK := {"speed":300,"width":40,"max_radius":260,"damage":12}
const NEAR_B := Vector2(950,250)
const MOVE_DAMAGE := 10.0

func run(t) -> void:
	_emerge_other_pool(t)
	_emerge_nearest_pick(t)
	_ripple_telegraph(t)
	_untargetable_while_submerged(t)
	_splash_ring_hits_once(t)
	_splash_ring_misses_far(t)
	_splash_damage_scaling(t)
	_wet_on_emerge(t)
	_frozen_pool_stuns(t)
	_cold_projectile_stuns(t)
	_unfrozen_pool_no_stun(t)
	_legacy_submerge_unchanged(t)
	_validate(t)

func _move(extra: Dictionary = {}) -> Dictionary:
	return {"mode":"submerge","exit":"pool","telegraph_ticks":40,"submerged_ticks":60,"emerge_telegraph_ticks":40,"radius":110,"damage":MOVE_DAMAGE}.merged(extra,true)

func _cfg(move: Dictionary, extra: Dictionary = {}) -> Dictionary:
	var cfg := {"kind":"test_archivist","hp":2400,"radius":30,"recovery_ticks":10,"min_telegraph_ticks":36,"shot_speed":300,"shot_spread":0,
		"shot_damage":0,"radial_shots":4,"radial_damage":0,"telegraph_radius":190,"pools":POOLS,
		"stagger":{"ticks":90,"damage_taken_multiplier":1.5},"water_freeze":{"radius":40,"ice_ticks":600},
		"phases":[{"threshold":1.0,"windup_ticks":40,"pool":[{"move":move}]}]}
	return cfg.merged(extra,true)

## Session with shallow water around every pool; the boss starts in pool A.
func _fresh(cfg: Dictionary, player_at: Vector2, water: bool = true) -> Array:
	var s = Session.new(1981,"empty",0)
	s.defer_clear = true
	var boss = s.spawn_boss(cfg,A)
	s.sim.actor.position = player_at
	if water:
		s.set_water(POOLS.map(func(p): return {"kind":"shallow","rect":[p[0]-64,p[1]-64,128,128]}))
	return [s,boss]

func _hp(s) -> float:
	return s.sim.actor.health.current

func _emerging(boss) -> bool:
	return boss.state == "windup" and str(boss.intent.snapshot()["kind"]) == "emerge"

## Drives the boss (boss.advance only) through one dive until it has emerged; reports what it saw on the way.
func _dive(s, boss) -> Dictionary:
	var out := {"from":boss.target.position,"hidden":true,"ripple":null,"telegraph":-1,"landing":Vector2.ZERO,"ticks":0}
	for i in 800:
		boss.advance(s)
		if boss.state == "submerged" or _emerging(boss):
			out["hidden"] = out["hidden"] and boss.submerged and boss.target.untargetable and not boss.target.eligible(s.sim.actor.team)
		if _emerging(boss):
			var snap: Dictionary = boss.intent.snapshot()
			out["ripple"] = snap.get("pool_ripple")
			out["telegraph"] = int(snap["telegraph_ticks"])
			out["landing"] = snap["landing"]
			out["ticks"] = int(out["ticks"])+1
		elif int(out["ticks"]) > 0:
			break
	out["to"] = boss.target.position
	return out

func _is_pool(p: Vector2) -> bool:
	return POOLS.any(func(pool): return Vector2(pool[0],pool[1]) == p)

func _emerge_other_pool(t) -> void:
	var players := [Vector2(150,450),Vector2(1000,650),Vector2(700,100),Vector2(400,260),Vector2(1000,200),Vector2(700,700)]
	for pick in ["farthest","nearest"]:
		var pair := _fresh(_cfg(_move({"anchor_pick":pick})),players[0])
		var ok := true
		var moved := 0
		for dive in players.size():
			pair[0].sim.actor.position = players[dive]
			var out := _dive(pair[0],pair[1])
			ok = ok and _is_pool(out["to"]) and out["to"] != out["from"] and out["to"].distance_to(out["from"]) > 8.0 and out["to"] == out["landing"]
			moved += 1 if out["to"] != out["from"] else 0
		t.check(ok and moved == players.size(),"AD-201 every %s dive emerges at a different pool than it dove from (%d dives)" % [pick,moved])
	var visited := {}
	var pair := _fresh(_cfg(_move()),Vector2(150,450))
	for dive in 8:
		visited[_dive(pair[0],pair[1])["to"]] = true
	t.check(visited.size() >= 2,"AD-201 repeated dives travel between pools")

func _emerge_nearest_pick(t) -> void:
	var pair := _fresh(_cfg(_move({"anchor_pick":"nearest"})),NEAR_B)
	t.equal(_dive(pair[0],pair[1])["to"],B,"AD-201 anchor_pick nearest surfaces at the other pool nearest the player")
	var far := _fresh(_cfg(_move({"anchor_pick":"farthest"})),Vector2(150,450))
	t.equal(_dive(far[0],far[1])["to"],B,"AD-201 default pick surfaces at the other pool farthest from the player")
	var lone := _fresh(_cfg(_move(),{"pools":[[400,200]]}),Vector2(150,450))
	t.equal(_dive(lone[0],lone[1])["to"],A,"AD-201 a lone pool never moves the boss to another point")

func _ripple_telegraph(t) -> void:
	var pair := _fresh(_cfg(_move()),Vector2(150,450))
	var out := _dive(pair[0],pair[1])
	t.check(out["ripple"] == true,"AD-201 the emerge windup carries pool_ripple")
	t.equal(out["telegraph"],40,"AD-201 the emerge telegraph is the configured emerge_telegraph_ticks")
	t.equal(out["ticks"],40,"AD-201 the emerge windup really lasts that many ticks")
	t.equal(out["landing"],B,"AD-201 the ripple is at the exit pool")
	var plain := _fresh(_cfg(_move({"exit":""}),{"anchors":POOLS}),Vector2(150,450))
	t.check(_dive(plain[0],plain[1])["ripple"] == null,"AD-201 without exit=pool the emerge windup has no pool_ripple")
	Difficulty.set_override({"telegraph_length":0.5})
	var floor_pair := _fresh(_cfg(_move()),Vector2(150,450))
	Difficulty.set_override({})
	t.equal(_dive(floor_pair[0],floor_pair[1])["telegraph"],36,"AD-201 the emerge ripple still gets the min_telegraph floor")

func _untargetable_while_submerged(t) -> void:
	var pair := _fresh(_cfg(_move()),Vector2(150,450))
	var out := _dive(pair[0],pair[1])
	var boss = pair[1]
	t.check(out["hidden"],"AD-201 the boss is submerged and untargetable from the dive until it emerges")
	t.check(not boss.submerged and not boss.target.untargetable and boss.target.eligible(pair[0].sim.actor.team),"AD-201 the emerged boss is targetable again")

## Ticks from the emerge until a ring of SHOCK speed touches a player `distance` px away (mirrors the contact rule).
func _contact_tick(s, distance: float, shock: Dictionary) -> int:
	var per_tick := float(shock["speed"])/float(s.sim.clock.tick_rate)
	for age in range(1,300):
		if per_tick*age > float(shock["max_radius"]):
			return -1
		if absf(distance-per_tick*age) <= float(shock["width"])*0.5+s.sim.actor.radius:
			return age
	return -1

func _ring_hits(player_at: Vector2, shock: Dictionary) -> Array:
	var pair := _fresh(_cfg(_move({"damage":0,"shockwave":shock,"anchor_pick":"nearest"})),player_at)
	var s = pair[0]
	_dive(s,pair[1])
	var rings: int = s.hazards.filter(func(h): return h["kind"] == "boss_ring").size()
	var hits: Array = []
	for age in range(1,81):
		var before := _hp(s)
		pair[1].advance(s)
		if _hp(s) < before:
			hits.append([age,before-_hp(s)])
	return [hits,rings,_contact_tick(s,player_at.distance_to(pair[1].target.position),shock),pair[1].target.position]

func _splash_ring_hits_once(t) -> void:
	var band := Vector2(1000,400)
	var got := _ring_hits(band,SHOCK)
	t.equal(got[3],B,"AD-201 the ring is centred on the emerge point")
	t.equal(got[1],1,"AD-201 the emerge publishes one ring hazard")
	t.check(got[2] > 0,"AD-201 the test player stands on the ring band")
	t.equal(got[0],[[got[2],Difficulty.scale_f(12.0,"enemy_damage")]],"AD-201 the splash ring hits a player on the band once")

func _splash_ring_misses_far(t) -> void:
	var got := _ring_hits(Vector2(1000,650),SHOCK)
	t.equal(got[0],[],"AD-201 a player beyond the ring's reach is never hit")
	var plain := _fresh(_cfg(_move({"damage":0})),Vector2(1000,400))
	_dive(plain[0],plain[1])
	t.check(plain[1]._aftermath.is_empty() and plain[0].hazards.filter(func(h): return h["kind"] == "boss_ring").is_empty(),"AD-201 an emerge without a shockwave block starts no ring")

func _splash_damage_scaling(t) -> void:
	var boss = _fresh(_cfg(_move({"shockwave":SHOCK}),{"elite_damage_multiplier":2.0}),Vector2(150,450))[1]
	t.equal(boss.tuning["phases"][0]["pool"][0]["move"]["shockwave"]["damage"],Difficulty.scale_f(24.0,"enemy_damage"),"AD-201 splash damage is scaled like other move damage")

func _wet_on_emerge(t) -> void:
	var pair := _fresh(_cfg(_move(),{"emerge_status":"wet"}),Vector2(150,450))
	var boss = pair[1]
	var tick: int = pair[0].sim.clock.tick
	t.check(not boss.target.status.has("wet",tick),"AD-201 the boss starts dry")
	var out := _dive(pair[0],pair[1])
	t.check(out["to"] != out["from"] and boss.target.status.has("wet",tick),"AD-201 the boss is Wet after emerging when emerge_status is wet")
	var dry := _fresh(_cfg(_move()),Vector2(150,450))
	_dive(dry[0],dry[1])
	t.check(not dry[1].target.status.has("wet",dry[0].sim.clock.tick),"AD-201 no emerge_status, no Wet")

func _stun_cfg(extra: Dictionary = {}) -> Dictionary:
	return _cfg(_move({"anchor_pick":"nearest"}),{"freeze_stun":{"ticks":120,"radius":60}}.merged(extra,true))

func _frozen_pool_stuns(t) -> void:
	var pair := _fresh(_stun_cfg(),NEAR_B)
	var s = pair[0]
	var boss = pair[1]
	s.water.freeze_circle(B,70.0,100000)
	var hp := _hp(s)
	var out := _dive(s,boss)
	t.equal(out["to"],B,"AD-201 the boss surfaces at the frozen pool")
	t.check(boss.state == "stagger" and boss.staggered,"AD-201 emerging into a frozen pool staggers the boss")
	t.check(not boss.submerged and not boss.target.untargetable,"AD-201 the stunned boss is visible and targetable")
	t.equal(boss.target.damage_scale,1.5,"AD-201 the stun uses the stagger damage_taken_multiplier")
	t.equal(_hp(s),hp,"AD-201 emerging into ice deals no slam damage")
	var ticks := 1
	while ticks < 400:
		boss.advance(s)
		if boss.state != "stagger":
			break
		ticks += 1
	t.equal(ticks,120,"AD-201 the freeze-stun lasts exactly freeze_stun.ticks")
	t.check(not boss.staggered and boss.target.damage_scale == 1.0,"AD-201 the stun window closes cleanly")
	t.equal(_hp(s),hp,"AD-201 the whole stun costs the player nothing")
	var dressed := _fresh(_stun_cfg({"emerge_status":"wet","phases":[{"threshold":1.0,"windup_ticks":40,"pool":[{"move":_move({"anchor_pick":"nearest","shockwave":SHOCK})}]}]}),NEAR_B)
	dressed[0].water.freeze_circle(B,70.0,100000)
	_dive(dressed[0],dressed[1])
	t.check(dressed[1]._aftermath.is_empty() and dressed[0].hazards.filter(func(h): return h["kind"] == "boss_ring").is_empty(),"AD-201 a stunned emerge starts no splash ring")
	t.check(not dressed[1].target.status.has("wet",dressed[0].sim.clock.tick),"AD-201 a stunned emerge does not apply the emerge status")

func _cold_projectile_stuns(t) -> void:
	var pair := _fresh(_stun_cfg(),NEAR_B)
	var s = pair[0]
	var boss = pair[1]
	s.sim.loadout.allow_edit = true
	s.sim.equip(1,{"schema_version":1,"formula_id":"test.hit","display_name":"hit",
		"root":{"essence_id":"essence.cold","manifestation_id":"form.projectile","modifier_ids":[],"params":{}}})
	s.sim.loadout.slots[1]["cooldown"] = 0
	s.sim.mana = 120.0
	s.sim.try_cast(1,s.sim.actor.position,(B-NEAR_B).normalized())
	var hp := _hp(s)
	var stagger_ticks := 0
	var frozen := false
	for i in 400:
		s.step()
		frozen = frozen or s.water.frozen_near(B,60.0)
		if boss.state == "stagger":
			stagger_ticks += 1
		elif stagger_ticks > 0:
			break
	t.check(frozen,"AD-201 a Cold projectile through the pool freezes it")
	t.equal(stagger_ticks,120,"AD-201 a boss surfacing into a Cold-frozen pool is stunned for freeze_stun.ticks")
	t.equal(_hp(s),hp,"AD-201 no damage reaches the player from the frozen emerge")

func _unfrozen_pool_no_stun(t) -> void:
	var pair := _fresh(_stun_cfg(),NEAR_B)
	var hp := _hp(pair[0])
	_dive(pair[0],pair[1])
	t.check(pair[1].state != "stagger" and not pair[1].staggered and pair[1].target.damage_scale == 1.0,"AD-201 an unfrozen pool does not stun the boss")
	t.equal(_hp(pair[0]),hp-Difficulty.scale_f(MOVE_DAMAGE,"enemy_damage"),"AD-201 an unfrozen emerge slams the player on it")
	var elsewhere := _fresh(_stun_cfg(),NEAR_B)
	elsewhere[0].water.freeze_circle(C,70.0,100000)
	_dive(elsewhere[0],elsewhere[1])
	t.check(elsewhere[1].state != "stagger","AD-201 ice at another pool does not stun")
	var expired := _fresh(_stun_cfg(),NEAR_B)
	expired[0].water.freeze_circle(B,70.0,5)
	for i in 10:
		expired[0].water.advance(i+1)
	t.check(not expired[0].water.frozen_near(B,60.0),"AD-201 frozen_near is false once the ice has melted")
	var edge: RefCounted = _fresh(_stun_cfg(),NEAR_B)[0].water
	edge.freeze_circle(A,20.0,100)
	t.check(edge.frozen_near(A,10.0) and not edge.frozen_near(A,5.0) and not edge.frozen_near(C,30.0),"AD-201 frozen_near measures from frozen cell centres (the cell centre is 8 px from the pool)")

func _legacy_submerge_unchanged(t) -> void:
	var legacy := {"mode":"submerge","telegraph_ticks":40,"submerged_ticks":60,"emerge_telegraph_ticks":50,"anchor_pick":"farthest","radius":110,"damage":10}
	var pair := _fresh(_cfg(legacy,{"anchors":[[1100,200],[300,450]]}),Vector2(150,450))
	pair[0].water.freeze_circle(Vector2(1100,200),70.0,100000)
	var hp := _hp(pair[0])
	var out := _dive(pair[0],pair[1])
	t.equal(out["to"],Vector2(1100,200),"AD-201 a submerge without exit still surfaces at the anchor")
	t.check(out["ripple"] == null and pair[1].state != "stagger" and not pair[1].target.status.has("wet",0),"AD-201 a boss without the new keys gets no ripple, stun or Wet")
	t.equal(_hp(pair[0]),hp,"AD-201 the legacy emerge slam is unchanged (player out of reach)")

func _validate(t) -> void:
	var good := _cfg(_move({"shockwave":SHOCK}),{"emerge_status":"wet","freeze_stun":{"ticks":120,"radius":60},
		"phases":[{"threshold":1.0,"windup_ticks":40,"pool":[{"move":_move({"shockwave":SHOCK})},{"pattern":"radial"},{"pattern":"fan"},{"pattern":"targeted"}]}]})
	t.equal(BossCombat.validate(good),[],"AD-201 a good archivist config has no issues")
	var codes := func(cfg: Dictionary) -> Array:
		return BossCombat.validate(cfg).map(func(i): return i["code"])
	t.equal(codes.call(good.merged({"pools":"x"},true)),["BOSS_ARCHIVIST_PARAM","BOSS_ARCHIVIST_PARAM"],"AD-201 non-array pools are rejected (and the exit has no pools)")
	t.check(codes.call(good.merged({"pools":[[1,2],[3]]},true)).has("BOSS_ARCHIVIST_PARAM"),"AD-201 a malformed pool entry is rejected")
	t.check(codes.call(good.merged({"pools":[[400,200]]},true)).has("BOSS_ARCHIVIST_PARAM"),"AD-201 exit=pool with fewer than 2 pools is rejected")
	t.check(codes.call(good.merged({"emerge_status":5},true)).has("BOSS_ARCHIVIST_PARAM"),"AD-201 a non-string emerge_status is rejected")
	t.check(codes.call(good.merged({"freeze_stun":{"radius":60}},true)).has("BOSS_ARCHIVIST_PARAM"),"AD-201 freeze_stun without ticks is rejected")
	t.check(codes.call(good.merged({"freeze_stun":{"ticks":"a","radius":60}},true)).has("BOSS_ARCHIVIST_PARAM"),"AD-201 non-numeric freeze_stun is rejected")
	var no_freeze: Dictionary = good.duplicate(true)
	no_freeze.erase("water_freeze")
	t.check(codes.call(no_freeze).has("BOSS_ARCHIVIST_PARAM"),"AD-201 freeze_stun needs water_freeze")
	var no_stagger: Dictionary = good.duplicate(true)
	no_stagger.erase("stagger")
	t.check(codes.call(no_stagger).has("BOSS_ARCHIVIST_PARAM"),"AD-201 freeze_stun needs stagger")
	var no_anchors: Dictionary = good.duplicate(true)
	no_anchors.erase("anchors")
	t.check(not codes.call(no_anchors).has("BOSS_MOVE_ANCHORS"),"AD-201 a pool exit does not need anchors")
