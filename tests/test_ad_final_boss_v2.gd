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
const Minion = preload("res://combat/boss_moves/elite_minion.gd")
const PAGES := {"hp":6,"radius":14,"speed":150,"turn_deg_per_tick":2,"lifetime_ticks":300,"damage":7,"cap":5,"count":3,"spread_degrees":40}
const CONDUCT := {"duration_ticks":200,"damage":6,"interval_ticks":10}

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
	_page_throw_queues(t)
	_page_cap(t)
	_page_flight_and_hit(t)
	_page_destroyed_and_burned(t)
	_page_speed_scale(t)
	_difficulty_scaling(t)
	_wisp_shield(t)
	_shield_vs_stagger(t)
	_shield_vs_roar(t)
	_thralls_die_with_boss(t)
	_storm_conduct(t)
	_validate_step2(t)

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

# --- step 2: book pages, wisp shield, conducting storm pulse ---

func _patterns(names: Array, extra: Dictionary = {}) -> Dictionary:
	return {"threshold":1.0,"windup_ticks":40,"patterns":names}.merged(extra,true)

## Pattern-cycle archivist (no pool phases): `phases` are phase dictionaries.
func _pcfg(phases: Array, extra: Dictionary = {}) -> Dictionary:
	return _cfg({},{"recovery_ticks":10,"phases":phases}.merged(extra,true))

func _pages(s) -> Array:
	return s.enemies.filter(func(e): return e is Minion and e.kind == "book_page")

func _live_pages(s) -> Array:
	return _pages(s).filter(func(e): return e.target.alive())

func _queue_page(s, boss, at: Vector2, heading: Vector2) -> Object:
	s.pending_spawns.append({"minion":"book_page","position":at,"summoner_id":boss.target.id,"heading":heading,"settings":boss.tuning["book_pages"]})
	s._flush_pending_spawns()
	return _pages(s).back()

## Advances only the boss until it has fired once (pending spawns appear or the cycle counter moves).
func _until_fired(s, boss, limit: int = 300) -> bool:
	var cycle: int = boss.cycle
	for i in limit:
		boss.advance(s)
		if boss.cycle != cycle:
			return true
	return false

func _cast(s, essence: String, dir: Vector2, ticks: int) -> void:
	s.sim.loadout.allow_edit = true
	s.sim.equip(1,{"schema_version":1,"formula_id":"test.hit","display_name":"hit",
		"root":{"essence_id":essence,"manifestation_id":"form.projectile","modifier_ids":[],"params":{}}})
	s.sim.loadout.slots[1]["cooldown"] = 0
	s.sim.mana = 120.0
	s.sim.try_cast(1,s.sim.actor.position,dir)
	for i in ticks:
		s.sim.step()

func _page_throw_queues(t) -> void:
	var pair := _fresh(_pcfg([_patterns(["page_throw"])],{"book_pages":PAGES}),Vector2(400,600))
	var s = pair[0]
	var boss = pair[1]
	for i in 400:
		boss.advance(s)
		if boss.state == "windup":
			break
	var snap: Dictionary = boss.intent.snapshot()
	t.check(snap["kind"] == "page_throw" and snap["telegraph_shape"] == "slam" and snap["landing"] == A and int(snap["telegraph_ticks"]) == 40,"AD-201 page_throw opens a slam windup at the boss with the phase windup ticks")
	t.equal(s.pending_spawns.size(),0,"AD-201 nothing is queued during the windup")
	t.check(_until_fired(s,boss),"AD-201 setup: the boss threw pages")
	var queued: Array = s.pending_spawns
	t.equal(queued.size(),3,"AD-201 page_throw queues count pages")
	t.check(queued.all(func(q): return q["minion"] == "book_page" and int(q["summoner_id"]) == boss.target.id),"AD-201 the pages are book_page minions owned by the boss")
	var angles: Array = queued.map(func(q): return rad_to_deg(Vector2.DOWN.angle_to(q["heading"])))
	t.check(is_zero_approx(angles[1]) and is_equal_approx(angles[0],-20.0) and is_equal_approx(angles[2],20.0) or is_equal_approx(angles[0],20.0) and is_equal_approx(angles[2],-20.0),"AD-201 the pages fan over spread_degrees around the aim at the player (%s)" % str(angles))
	s._flush_pending_spawns()
	var pages := _live_pages(s)
	t.check(pages.size() == 3 and pages.all(func(p): return p.state == "fly" and p.target.tags == ["enemy","book_page"] and is_equal_approx(p.target.health.current,6.0)),"AD-201 the pages fly as tagged targets with settings hp")
	t.check(pages.all(func(p): return p.target.position.distance_to(A) > 40.0),"AD-201 the pages start outside the boss")

func _page_cap(t) -> void:
	var tight := _fresh(_pcfg([_patterns(["page_throw"])],{"book_pages":PAGES.merged({"cap":2},true)}),Vector2(400,600))
	_until_fired(tight[0],tight[1])
	t.equal(tight[0].pending_spawns.size(),2,"AD-201 a cast never queues beyond cap")
	var pair := _fresh(_pcfg([_patterns(["page_throw"])],{"book_pages":PAGES.merged({"cap":4,"speed":20},true)}),Vector2(150,800))
	var s = pair[0]
	var peak := 0
	var casts := 0
	for i in 200:
		var before: int = pair[1].cycle
		s.step()
		casts += 1 if pair[1].cycle > before else 0
		peak = maxi(peak,_live_pages(s).size()+s.pending_spawns.size())
	t.check(casts >= 3 and peak == 4,"AD-201 repeated casts never exceed cap live+queued pages (casts %d, peak %d)" % [casts,peak])

func _page_flight_and_hit(t) -> void:
	var pair := _fresh(_pcfg([_patterns(["fan"])],{"book_pages":PAGES,"recovery_ticks":4000}),Vector2(400,700))
	var s = pair[0]
	var page = _queue_page(s,pair[1],Vector2(400,500),Vector2.RIGHT)
	s.sim.actor.position = Vector2(500,700)
	var start_error := absf(page.heading.angle_to(s.sim.actor.position-page.target.position))
	var largest := 0.0
	var speed := 0.0
	for i in 20:
		var before: Vector2 = page.heading
		var from: Vector2 = page.target.position
		page.advance(s)
		speed = maxf(speed,from.distance_to(page.target.position))
		largest = maxf(largest,absf(before.angle_to(page.heading)))
	t.check(largest <= deg_to_rad(2.0)+0.0001 and largest > 0.0,"AD-201 a page turns by at most turn_deg_per_tick per tick")
	t.check(absf(page.heading.angle_to(s.sim.actor.position-page.target.position)) < start_error,"AD-201 a page homes toward the player")
	t.check(is_equal_approx(speed,150.0/float(s.sim.clock.tick_rate)),"AD-201 a page moves speed/tick_rate per tick")
	var hp := _hp(s)
	var dead := 0
	for i in 400:
		s.step()
		if not page.target.alive():
			dead = i
			break
	t.check(dead > 0 and is_equal_approx(hp-_hp(s),Difficulty.scale_f(7.0,"enemy_damage")),"AD-201 a page hits the player once for book_pages.damage and is gone")
	var after := _hp(s)
	for i in 30:
		s.step()
	t.equal(_hp(s),after,"AD-201 a spent page deals no more damage")
	var walled := _fresh(_pcfg([_patterns(["fan"])],{"book_pages":PAGES,"recovery_ticks":4000}),A)
	walled[0].sim.actor.position = Vector2(1100,270)
	var blocked = _queue_page(walled[0],walled[1],Vector2(520,270),Vector2.RIGHT)
	for i in 40:
		blocked.advance(walled[0])
	t.check(not blocked.target.alive(),"AD-201 a page dies on a wall")
	var timed := _fresh(_pcfg([_patterns(["fan"])],{"book_pages":PAGES.merged({"speed":10,"lifetime_ticks":50},true),"recovery_ticks":4000}),A)
	timed[0].sim.actor.position = Vector2(1100,800)
	var late = _queue_page(timed[0],timed[1],Vector2(400,700),Vector2.RIGHT)
	for i in 49:
		late.advance(timed[0])
	t.check(late.target.alive(),"AD-201 a page is alive just before lifetime_ticks")
	late.advance(timed[0])
	t.check(not late.target.alive(),"AD-201 a page expires at lifetime_ticks")

func _page_destroyed_and_burned(t) -> void:
	var shot := _fresh(_pcfg([_patterns(["fan"])],{"book_pages":PAGES,"recovery_ticks":4000}),Vector2(400,700))
	var page = _queue_page(shot[0],shot[1],Vector2(400,550),Vector2.RIGHT)
	_cast(shot[0],"essence.force",Vector2.UP,40)
	t.check(not page.target.alive(),"AD-201 a bolt shoots a page down")
	var pair := _fresh(_pcfg([_patterns(["fan"])],{"book_pages":PAGES.merged({"hp":600},true),"recovery_ticks":4000}),Vector2(400,700))
	var s = pair[0]
	var tough = _queue_page(s,pair[1],Vector2(900,300),Vector2.RIGHT)
	tough.advance(s)
	t.check(tough.target.alive() and tough.state == "fly","AD-201 a page that is not Burning keeps flying")
	tough.target.status.apply("burning",s.sim.clock.tick,s.sim.settings["statuses"]["burning"],{"source_id":0})
	tough.advance(s)
	t.check(not tough.target.alive(),"AD-201 a Burning page dies at once")
	tough.advance(s)
	t.check(tough.state == "dead" and s._death_ids.has(tough.target.id),"AD-201 a burned page reports its death")
	var wet := _fresh(_pcfg([_patterns(["fan"])],{"book_pages":PAGES.merged({"hp":600},true),"recovery_ticks":4000}),Vector2(400,700))
	var soaked = _queue_page(wet[0],wet[1],Vector2(900,300),Vector2.RIGHT)
	soaked.target.status.apply("wet",wet[0].sim.clock.tick,wet[0].sim.settings["statuses"]["wet"],{"source_id":0})
	soaked.advance(wet[0])
	t.check(soaked.target.alive(),"AD-201 only Burning burns a page")
	var fire := _fresh(_pcfg([_patterns(["fan"])],{"book_pages":PAGES.merged({"hp":600},true),"recovery_ticks":4000}),Vector2(400,700))
	var scorched = _queue_page(fire[0],fire[1],Vector2(400,550),Vector2.RIGHT)
	_cast(fire[0],"essence.fire",Vector2.UP,40)
	scorched.advance(fire[0])
	t.check(not scorched.target.alive(),"AD-201 a Fire bolt burns a tough page")

func _page_speed_scale(t) -> void:
	var speeds: Array = []
	for scale in [1.0,1.5]:
		var phase := _patterns(["page_throw"],{"page_speed_scale":scale})
		var pair := _fresh(_pcfg([phase],{"book_pages":PAGES}),Vector2(400,600))
		_until_fired(pair[0],pair[1])
		var spec: Dictionary = pair[0].pending_spawns[0]
		pair[0]._flush_pending_spawns()
		var page = _live_pages(pair[0])[0]
		var from: Vector2 = page.target.position
		page.advance(pair[0])
		speeds.append([float(spec["settings"]["speed"]),from.distance_to(page.target.position)])
	t.check(is_equal_approx(speeds[0][0],150.0) and is_equal_approx(speeds[1][0],225.0),"AD-201 page_speed_scale multiplies the queued page speed")
	t.check(speeds[1][1] > speeds[0][1]*1.4,"AD-201 the faster page really moves faster")
	var plain := _fresh(_pcfg([_patterns(["page_throw"])],{"book_pages":PAGES}),Vector2(400,600))
	_until_fired(plain[0],plain[1])
	t.equal(float(plain[0].pending_spawns[0]["settings"]["speed"]),150.0,"AD-201 without page_speed_scale pages keep the base speed")
	t.equal(float(plain[1].tuning["book_pages"]["speed"]),150.0,"AD-201 the boss's own book_pages stay unscaled")

func _difficulty_scaling(t) -> void:
	var boss: RefCounted = _fresh(_pcfg([_patterns(["page_throw"])],{"book_pages":PAGES,"storm_conduct":CONDUCT,"elite_damage_multiplier":1.0}),A)[1]
	t.equal(boss.tuning["book_pages"]["damage"],Difficulty.scale_f(7.0,"enemy_damage"),"AD-201 book_pages.damage gets the enemy damage scaling")
	t.equal(boss.tuning["storm_conduct"]["damage"],Difficulty.scale_f(6.0,"enemy_damage"),"AD-201 storm_conduct.damage gets the enemy damage scaling")
	t.check(is_equal_approx(float(boss.tuning["book_pages"]["hp"]),6.0),"AD-201 page hp is never scaled")

# --- wisp shield ---

func _shield_cfg(multiplier: float = 0.0, extra: Dictionary = {}) -> Dictionary:
	return _pcfg([_patterns(["radial"])],{"wisp_shield":{"damage_taken_multiplier":multiplier},"recovery_ticks":4000,
		"wisp_offsets":[[90,0],[-90,0]],"wisp_cap":2}.merged(extra,true))

func _wisps(s, boss) -> Array:
	return s.enemies.filter(func(e): return e.kind == "lantern_wisp" and e.summoner_id == boss.target.id)

func _hit(boss, amount: float = 100.0) -> float:
	return boss.target.receive_damage(amount,"neutral",1,1.0)

func _wisp_shield(t) -> void:
	var pair := _fresh(_shield_cfg(0.25),Vector2(400,700))
	var s = pair[0]
	var boss = pair[1]
	boss.advance(s)
	t.check(not boss.shielded and boss.target.damage_scale == 1.0,"AD-201 no wisp, no shield")
	var full := _hit(boss)
	boss.fire_summon(s,"lantern_wisp",[[90,0]],2)
	boss.advance(s)
	t.check(not boss.shielded and boss.target.damage_scale == 1.0,"AD-201 a queued wisp does not shield")
	s._flush_pending_spawns()
	var wisp = _wisps(s,boss)[0]
	boss.advance(s)
	t.check(boss.shielded and is_equal_approx(boss.target.damage_scale,0.25),"AD-201 a live owned wisp shields the boss with the multiplier")
	t.check(is_equal_approx(_hit(boss),full*0.25),"AD-201 the shielded boss takes multiplier x damage")
	wisp.target.receive_damage(1000.0,"neutral",1,1.0)
	boss.advance(s)
	t.check(not boss.shielded and boss.target.damage_scale == 1.0 and is_equal_approx(_hit(boss),full),"AD-201 killing the wisp restores full damage")
	var zero := _fresh(_shield_cfg(0.0),Vector2(400,700))
	zero[1].fire_summon(zero[0],"lantern_wisp",[[90,0],[-90,0]],2)
	zero[0]._flush_pending_spawns()
	var hp: float = zero[1].target.health.current
	zero[1].advance(zero[0])
	t.check(zero[1].shielded and _hit(zero[1]) == 0.0 and zero[1].target.health.current == hp,"AD-201 multiplier 0 makes the boss immune")
	_wisps(zero[0],zero[1])[0].target.receive_damage(1000.0,"neutral",1,1.0)
	zero[1].advance(zero[0])
	t.check(zero[1].shielded and zero[1].target.damage_scale == 0.0,"AD-201 one wisp left still shields")
	_wisps(zero[0],zero[1])[1].target.receive_damage(1000.0,"neutral",1,1.0)
	zero[1].advance(zero[0])
	t.check(not zero[1].shielded and _hit(zero[1]) > 0.0,"AD-201 the last wisp's death drops the shield")
	var foreign := _fresh(_shield_cfg(0.0),Vector2(400,700))
	var stray = foreign[0].spawn_enemy("lantern_wisp",Vector2(600,400))
	foreign[1].advance(foreign[0])
	t.check(stray != null and not foreign[1].shielded,"AD-201 a wisp the boss does not own does not shield it")
	var plain := _fresh(_pcfg([_patterns(["radial"])],{"recovery_ticks":4000,"wisp_offsets":[[90,0]],"wisp_cap":2}),Vector2(400,700))
	plain[1].fire_summon(plain[0],"lantern_wisp",[[90,0]],2)
	plain[0]._flush_pending_spawns()
	plain[1].advance(plain[0])
	t.check(not plain[1].shielded and plain[1].target.damage_scale == 1.0,"AD-201 without wisp_shield wisps change nothing on the boss")

func _shield_vs_stagger(t) -> void:
	var pair := _fresh(_shield_cfg(0.0),Vector2(400,700))
	var s = pair[0]
	var boss = pair[1]
	boss.fire_summon(s,"lantern_wisp",[[90,0]],2)
	s._flush_pending_spawns()
	boss.advance(s)
	boss.stun(s,60)
	t.equal(boss.target.damage_scale,1.5,"AD-201 setup: the stun set the stagger multiplier")
	boss.advance(s)
	t.check(boss.staggered and boss.shielded and boss.target.damage_scale == 0.0,"AD-201 the shield wins over the stagger while it lasts")
	_wisps(s,boss)[0].target.receive_damage(1000.0,"neutral",1,1.0)
	boss.advance(s)
	t.check(boss.staggered and not boss.shielded and boss.target.damage_scale == 1.5,"AD-201 without the shield the stagger multiplier applies again")
	for i in 80:
		boss.advance(s)
	t.check(not boss.staggered and boss.target.damage_scale == 1.0,"AD-201 the stagger then ends normally")
	var late := _fresh(_shield_cfg(0.0),Vector2(400,700))
	late[1].fire_summon(late[0],"lantern_wisp",[[90,0]],2)
	late[0]._flush_pending_spawns()
	late[1].stun(late[0],10)
	late[1].advance(late[0])
	for i in 15:
		late[1].advance(late[0])
	t.check(not late[1].staggered and late[1].shielded and late[1].target.damage_scale == 0.0,"AD-201 a stagger that ends under the shield leaves the shield, not 1.0")

func _shield_vs_roar(t) -> void:
	var phases := [_patterns(["radial"]),{"threshold":0.66,"windup_ticks":40,"patterns":["radial"],"transition":{"roar_ticks":30}}]
	var pair := _fresh(_pcfg(phases,{"wisp_shield":{"damage_taken_multiplier":0.4},"recovery_ticks":4000}),Vector2(400,700))
	var s = pair[0]
	var boss = pair[1]
	s.pending_spawns.append({"kind":"lantern_wisp","position":A+Vector2(90,0),"summoner_id":boss.target.id})
	s._flush_pending_spawns()
	boss.advance(s)
	t.equal(boss.target.damage_scale,0.4,"AD-201 setup: shielded before the roar")
	boss.target.health.current = boss.target.health.maximum*0.5
	boss.advance(s)
	t.check(boss.state == "roar" and boss.target.damage_scale == 0.0,"AD-201 the roar keeps the boss at 0 even under a shield")
	for i in 40:
		boss.advance(s)
	t.check(boss.state != "roar" and boss.shielded and boss.target.damage_scale == 0.4,"AD-201 the shield is back when the roar ends")

func _thralls_die_with_boss(t) -> void:
	var pair := _fresh(_shield_cfg(0.0,{"book_pages":PAGES}),Vector2(400,700))
	var s = pair[0]
	var boss = pair[1]
	var page = _queue_page(s,boss,Vector2(600,400),Vector2.RIGHT)
	boss.fire_summon(s,"lantern_wisp",[[90,0]],2)
	s._flush_pending_spawns()
	s.pending_spawns.append({"minion":"book_page","position":Vector2(700,400),"summoner_id":boss.target.id,"heading":Vector2.RIGHT,"settings":boss.tuning["book_pages"]})
	boss.advance(s)
	boss.target.damage_scale = 1.0
	boss.target.receive_damage(boss.target.health.maximum*2.0,"neutral",1,1.0)
	boss.advance(s)
	t.check(not boss.target.alive() and not page.target.alive() and _wisps(s,boss).all(func(w): return not w.target.alive()),"AD-201 pages and wisps die with the boss")
	t.check(s.pending_spawns.is_empty() and boss.target.damage_scale == 1.0 and not boss.shielded,"AD-201 queued pages are dropped and the shield is cleared on death")

# --- conducting storm pulse ---

func _storm_cfg(extra: Dictionary = {}) -> Dictionary:
	return _pcfg([_patterns(["storm_pulse"])],{"storm_pulse_radius":150,"storm_pulse_damage":0,"recovery_ticks":4000,"storm_conduct":CONDUCT}.merged(extra,true))

func _until_shock(s, limit: int = 200) -> bool:
	for i in limit:
		if not s.water_shock.is_empty():
			return true
		s.step()
	return false

## Hp lost by the player over the next `ticks` ticks.
func _shock_loss(s, ticks: int) -> float:
	var hp := _hp(s)
	for i in ticks:
		s.step()
	return hp-_hp(s)

func _storm_conduct(t) -> void:
	var pair := _fresh(_storm_cfg(),Vector2(1000,200))
	var s = pair[0]
	t.check(s.water_shock.is_empty(),"AD-201 no shock before the pulse")
	t.check(_until_shock(s),"AD-201 the storm pulse sets the water shock")
	var shock: Dictionary = s.water_shock
	t.check(int(shock["source_id"]) == pair[1].target.id and shock["channel"] == "lightning" and int(shock["interval_ticks"]) == 10 and is_equal_approx(float(shock["damage"]),Difficulty.scale_f(6.0,"enemy_damage")),"AD-201 the shock carries the storm_conduct numbers")
	t.check(s.water.is_electrified(Vector2(1000,200)) and s.water.is_electrified(Vector2(400,200)),"AD-201 the pulse electrifies every pool, even out of its radius")
	var start: int = s.sim.clock.tick
	var expected := 0
	for tick in range(start+1,start+31):
		expected += 1 if tick%10 == 0 else 0
	var loss := _shock_loss(s,30)
	t.check(expected >= 3 and is_equal_approx(loss,float(expected)*Difficulty.scale_f(6.0,"enemy_damage")),"AD-201 a player standing in the water takes damage every interval (%.1f lost)" % loss)
	var dry := _fresh(_storm_cfg(),Vector2(700,450))
	_until_shock(dry[0])
	t.equal(_shock_loss(dry[0],30),0.0,"AD-201 a player out of the water takes no conducted damage")
	var iced := _fresh(_storm_cfg(),Vector2(1000,200))
	iced[0].water.freeze_circle(Vector2(1000,200),40.0,100000)
	_until_shock(iced[0])
	t.equal(_shock_loss(iced[0],30),0.0,"AD-201 a frozen cell is not conducting")
	var expiring := _fresh(_storm_cfg({"storm_conduct":CONDUCT.merged({"duration_ticks":15},true)}),Vector2(1000,200))
	_until_shock(expiring[0])
	_shock_loss(expiring[0],20)
	t.equal(_shock_loss(expiring[0],30),0.0,"AD-201 the electrified water goes dark after duration_ticks")
	var close := _fresh(_storm_cfg({"storm_pulse_damage":5}),Vector2(400,260))
	_until_shock(close[0])
	t.check(close[0].sim.actor.status.has("charged",close[0].sim.clock.tick) and not close[0].water_shock.is_empty(),"AD-201 the pulse in range still charges the player as before")
	var bare := _storm_cfg()
	bare.erase("storm_conduct")
	var plain := _fresh(bare,Vector2(1000,200))
	for i in 150:
		plain[0].step()
	t.check(plain[0].water_shock.is_empty() and plain[0].water.state_view().is_empty(),"AD-201 without storm_conduct the pulse leaves the water alone")
	var dying := _fresh(_storm_cfg(),Vector2(1000,200))
	_until_shock(dying[0])
	dying[1].target.receive_damage(dying[1].target.health.maximum*2.0,"neutral",1,1.0)
	dying[1].advance(dying[0])
	t.check(dying[0].water_shock.is_empty() and dying[0].water.state_view().is_empty(),"AD-201 the boss's death clears the conducted shock")

func _validate_step2(t) -> void:
	var good := _pcfg([_patterns(["page_throw","storm_pulse"],{"page_speed_scale":1.5})],{"book_pages":PAGES,"storm_conduct":CONDUCT,"wisp_shield":{"damage_taken_multiplier":0.0}})
	t.equal(BossCombat.validate(good),[],"AD-201 a good step-2 archivist config has no issues")
	var bad := func(extra: Dictionary) -> bool:
		return BossCombat.validate(good.merged(extra,true)).any(func(i): return i["code"] == "BOSS_ARCHIVIST_PARAM")
	for key in PAGES.keys():
		var missing: Dictionary = PAGES.duplicate()
		missing.erase(key)
		t.check(bad.call({"book_pages":missing}),"AD-201 book_pages without %s is rejected" % key)
		t.check(bad.call({"book_pages":PAGES.merged({key:0},true)}),"AD-201 book_pages.%s = 0 is rejected" % key)
	for key in CONDUCT.keys():
		var missing: Dictionary = CONDUCT.duplicate()
		missing.erase(key)
		t.check(bad.call({"storm_conduct":missing}),"AD-201 storm_conduct without %s is rejected" % key)
		t.check(bad.call({"storm_conduct":CONDUCT.merged({key:-1},true)}),"AD-201 storm_conduct.%s < 0 is rejected" % key)
	t.check(bad.call({"book_pages":"x"}) and bad.call({"storm_conduct":[1]}),"AD-201 non-dictionary book_pages / storm_conduct are rejected")
	for value in [1.0,1.5,-0.1,"x",null]:
		t.check(bad.call({"wisp_shield":{"damage_taken_multiplier":value}}),"AD-201 wisp_shield multiplier %s is rejected" % str(value))
	t.check(bad.call({"wisp_shield":{}}) and bad.call({"wisp_shield":5}),"AD-201 a wisp_shield without a multiplier is rejected")
	for value in [0.0,0.4,0.99]:
		t.check(not bad.call({"wisp_shield":{"damage_taken_multiplier":value}}),"AD-201 wisp_shield multiplier %s is accepted" % str(value))
	var no_pages: Dictionary = good.duplicate(true)
	no_pages.erase("book_pages")
	t.check(BossCombat.validate(no_pages).any(func(i): return i["code"] == "BOSS_ARCHIVIST_PARAM" and str(i["path"]) == "phases[0]"),"AD-201 page_throw without book_pages is rejected")
	var pooled: Dictionary = no_pages.duplicate(true)
	pooled["phases"] = [{"threshold":1.0,"windup_ticks":40,"pool":[{"pattern":"page_throw"}]}]
	t.check(BossCombat.validate(pooled).any(func(i): return i["code"] == "BOSS_ARCHIVIST_PARAM"),"AD-201 a pooled page_throw needs book_pages too")
	for value in [0,-1,"x"]:
		var phases: Array = [_patterns(["page_throw"],{"page_speed_scale":value})]
		t.check(bad.call({"phases":phases}),"AD-201 page_speed_scale %s is rejected" % str(value))
