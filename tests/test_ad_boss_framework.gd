extends RefCounted
## AD-198 step 1: boss framework. Weighted per-phase pattern pools, combos, no immediate repeat, back-compat. All settings are synthetic.
const Session = preload("res://combat/combat_session.gd")
const Pool = preload("res://combat/boss_moves/boss_pattern_pool.gd")
const BossCombat = preload("res://combat/boss_combat.gd")
const Art = preload("res://ui/pixel_art_renderer.gd")
const WATER_TAG := "boss_rising_water"
const ANCHORS := [[300,450],[1100,200],[1100,700]]
const AT := Vector2(1030,450)

func run(t) -> void:
	_no_immediate_repeat(t)
	_weights(t)
	_combo(t)
	_determinism(t)
	_validate(t)
	_legacy(t)
	_walk(t)
	_strafe(t)
	_reposition(t)
	_leap(t)
	_leap_fallback(t)
	_submerge(t)
	_telegraph_floor(t)
	_pick_anchor(t)
	_stationary(t)
	_validate_moves(t)
	_zone(t)
	_zone_dash(t)
	_debris(t)
	_debris_determinism(t)
	_rising_water(t)
	_hazard_stop(t)
	_hazard_floor(t)
	_hazard_fx(t)
	_hazard_legacy(t)
	_validate_hazards(t)
	_roar(t)
	_roar_cancels_windup(t)
	_roar_arena(t)
	_roar_hazard_timers(t)
	_roar_defer(t)
	_roar_multi(t)
	_stagger(t)
	_beats_death(t)
	_beats_legacy(t)
	_beats_fx(t)
	_validate_beats(t)

func _base(extra: Dictionary = {}) -> Dictionary:
	var cfg := {"kind":"test_boss","hp":2000,"radius":49,"recovery_ticks":30,"min_telegraph_ticks":36,"shot_speed":280,"shot_spread":0,
		"shot_damage":5,"radial_shots":4,"radial_damage":5,"fan_shots":3,"fan_arc_degrees":40,"telegraph_radius":190,"pulse_radius":150,"pulse_damage":5,
		"phases":[{"threshold":1.0,"windup_ticks":40,"pool":[
			{"pattern":"radial","weight":1},{"pattern":"fan","weight":1},{"pattern":"targeted","weight":1}]}]}
	return cfg.merged(extra,true)

func _pool_cfg(pool: Array) -> Dictionary:
	return _base({"phases":[{"threshold":1.0,"windup_ticks":40,"pool":pool}]})

func _fresh(cfg: Dictionary, seed: int = 1981) -> Array:
	var s = Session.new(seed,"empty",0)
	s.defer_clear = true
	var boss = s.spawn_boss(cfg,AT)
	s.sim.actor.position = AT+Vector2(-300,0)
	return [s,boss]

## Advances the boss, recording the attack kind at every windup start and the ticks spent in each recover.
func _trace(cfg: Dictionary, seed: int, attacks: int) -> Dictionary:
	var pair := _fresh(cfg,seed)
	var s = pair[0]
	var boss = pair[1]
	var kinds: Array = []
	var gaps: Array = []
	var windups: Array = []
	var prev := ""
	var in_state := 0
	for i in attacks*400:
		boss.advance(s)
		if boss.state != prev:
			if prev == "recover":
				gaps.append(in_state)
			elif prev == "windup":
				windups.append(in_state)
			if boss.state == "windup":
				kinds.append(boss.intent.snapshot()["kind"])
			prev = boss.state
			in_state = 0
		in_state += 1
		if kinds.size() >= attacks and boss.state == "recover":
			break
	return {"kinds":kinds,"gaps":gaps,"windups":windups,"session":s}

func _no_immediate_repeat(t) -> void:
	var kinds: Array = _trace(_base(),7,300)["kinds"]
	t.equal(kinds.size(),300,"AD-198 pool boss makes 300 picks")
	var repeats := 0
	for i in range(1,kinds.size()):
		if kinds[i] == kinds[i-1]:
			repeats += 1
	t.equal(repeats,0,"AD-198 pool never repeats the previous pattern")
	for name in ["radial","fan","targeted"]:
		t.check(kinds.has(name),"AD-198 pool eventually picks %s" % name)

func _weights(t) -> void:
	var cfg := _pool_cfg([{"pattern":"radial","weight":10},{"pattern":"fan","weight":1},{"pattern":"targeted","weight":1},{"pattern":"pulse","weight":1}])
	var kinds: Array = _trace(cfg,11,400)["kinds"]
	var radial := kinds.count("radial")
	var fan := kinds.count("fan")
	t.check(radial > fan*2,"AD-198 a 10:1 weight picks radial clearly more often (%d vs %d)" % [radial,fan])
	var pool: Array = [{"pattern":"a","weight":2},{"pattern":"b","weight":3}]
	var rng := RandomNumberGenerator.new()
	rng.seed = 5
	t.equal(Pool.pick(pool,"a",[],rng)["pattern"],"b","AD-198 pick skips the last key")
	t.equal(Pool.pick(pool,"",["b"],rng)["pattern"],"a","AD-198 pick skips blocked keys")
	t.equal(Pool.entry_key({"combo":["fan","radial"]}),"fan","AD-198 combo entry key is its first pattern")
	t.equal(Pool.last_key({"combo":["fan","radial"]}),"radial","AD-198 combo last key is its final pattern")
	t.equal(Pool.entry_key({"move":{"mode":"strafe"}}),"move:strafe","AD-198 move entry key")

func _combo(t) -> void:
	var cfg := _pool_cfg([{"combo":["fan","radial"],"gap_ticks":12,"weight":1},{"pattern":"targeted","weight":1},{"pattern":"pulse","weight":1}])
	var trace := _trace(cfg,3,60)
	var kinds: Array = trace["kinds"]
	var checked := 0
	for i in range(0,kinds.size()-1):
		if kinds[i] == "fan" and kinds[i+1] == "radial":
			checked += 1
			t.equal(trace["gaps"][i],12,"AD-198 combo members are separated by exactly gap_ticks")
			t.equal(trace["windups"][i+1],40,"AD-198 the second combo member gets a full windup")
		elif kinds[i] == "fan":
			t.check(false,"AD-198 fan always continues into radial")
		if kinds[i] == "targeted" or kinds[i] == "pulse":
			t.equal(trace["gaps"][i],30,"AD-198 non-combo attacks use recovery_ticks")
	t.check(checked > 0,"AD-198 combo was picked at least once")
	var after_combo := false
	for i in range(1,kinds.size()):
		if kinds[i-1] == "radial" and kinds[i] == "radial":
			after_combo = true
	t.check(not after_combo,"AD-198 no repeat across a combo's last pattern")

func _determinism(t) -> void:
	var a: Array = _trace(_base(),21,40)["kinds"]
	var b: Array = _trace(_base(),21,40)["kinds"]
	var c: Array = _trace(_base(),22,40)["kinds"]
	t.equal(a,b,"AD-198 same seed gives the identical attack sequence")
	t.check(a != c,"AD-198 a different seed gives a different sequence")

func _validate(t) -> void:
	var small := _pool_cfg([{"pattern":"radial"},{"pattern":"fan"},{"move":{"mode":"strafe"}}])
	var codes: Array = Pool.validate(small).map(func(i): return i["code"])
	t.check(codes.has("BOSS_POOL_TOO_SMALL"),"AD-198 validate rejects 2 distinct patterns (moves do not count)")
	t.equal(Pool.validate(_base()),[],"AD-198 validate accepts a valid pool")
	var weights: Array = Pool.validate(_pool_cfg([{"pattern":"radial","weight":0},{"pattern":"fan","weight":1.5},{"pattern":"targeted"}])).map(func(i): return i["code"])
	t.equal(weights,["BOSS_POOL_WEIGHT","BOSS_POOL_WEIGHT"],"AD-198 validate flags bad weights")
	var combos: Array = Pool.validate(_pool_cfg([{"combo":["fan"]},{"combo":["radial","fan"],"gap_ticks":-1},{"pattern":"targeted"}])).map(func(i): return i["code"])
	t.equal(combos,["BOSS_POOL_COMBO","BOSS_POOL_COMBO"],"AD-198 validate flags short combos and negative gaps")
	t.equal(Pool.validate({"phases":[{"threshold":1.0,"windup_ticks":40,"patterns":["radial"]}]}),[],"AD-198 phases without pool are not inspected")

func _legacy(t) -> void:
	var flat := {"kind":"test_boss","hp":2000,"radius":49,"recovery_ticks":30,"windup_ticks":40,"phase_threshold":0.0,"second_phase_windup_ticks":40,
		"shot_speed":280,"shot_spread":0,"shot_damage":5,"radial_shots":4,"radial_damage":5,"telegraph_radius":190,"patterns":["radial","fan","targeted"],"fan_shots":3,"fan_arc_degrees":40}
	var phased := _base({"phases":[{"threshold":1.0,"windup_ticks":40,"patterns":["radial","fan","targeted"]}]})
	for cfg in [flat,phased]:
		var kinds: Array = _trace(cfg,31,7)["kinds"]
		t.equal(kinds,["radial","fan","targeted","radial","fan","targeted","radial"],"AD-198 legacy boss still cycles patterns in order")
		var s = _trace(cfg,31,7)["session"]
		var fresh = Session.new(31,"empty",0)
		t.equal(s.sim.clock.random_int(1,1000000),fresh.sim.clock.random_int(1,1000000),"AD-198 legacy boss leaves the sim RNG untouched")
	var pool_trace := _trace(_base(),31,10)
	var fresh2 = Session.new(31,"empty",0)
	t.equal(pool_trace["session"].sim.clock.random_int(1,1000000),fresh2.sim.clock.random_int(1,1000000),"AD-198 pool boss leaves the sim RNG untouched")

## Pool of three patterns plus a heavily weighted move, so the first pick is the move; shots deal no damage unless `shots` is set.
func _move_cfg(move: Dictionary, shots: float = 0.0) -> Dictionary:
	var pool: Array = [{"move":move,"weight":1000},{"pattern":"radial"},{"pattern":"fan"},{"pattern":"targeted"}]
	return _base({"anchors":ANCHORS,"shot_damage":shots,"radial_damage":shots,"phases":[{"threshold":1.0,"windup_ticks":40,"pool":pool}]})

func _movement_cfg(movement: Dictionary) -> Dictionary:
	return _base({"shot_damage":0.0,"radial_damage":0.0,"phases":[{"threshold":1.0,"windup_ticks":40,"movement":movement,"pool":[{"pattern":"radial"},{"pattern":"fan"},{"pattern":"targeted"}]}]})

func _walk(t) -> void:
	var pair := _fresh(_movement_cfg({"mode":"walk_to_player","speed":90,"stop_range":200}))
	var s = pair[0]
	var boss = pair[1]
	s.sim.actor.position = Vector2(1030,150)
	var moved_in_windup := false
	var previous: Vector2 = boss.target.position
	var prev_state := ""
	for i in 900:
		boss.advance(s)
		if boss.state == "windup" and prev_state == "windup" and boss.target.position != previous:
			moved_in_windup = true
		previous = boss.target.position
		prev_state = boss.state
	var distance: float = boss.target.position.distance_to(s.sim.actor.position)
	t.check(distance < 299.0 and distance >= 199.9 and distance <= 202.0,"AD-198 walk_to_player closes from 300 and stops at stop_range (%.1f)" % distance)
	t.check(not moved_in_windup,"AD-198 continuous movement never moves the boss during a windup")

func _strafe(t) -> void:
	var pair := _fresh(_movement_cfg({"mode":"strafe","speed":80,"preferred_range":200,"margin":50}))
	var s = pair[0]
	var boss = pair[1]
	s.sim.actor.position = Vector2(1030,350)
	var start: Vector2 = boss.target.position
	var low := INF
	var high := 0.0
	for i in 600:
		boss.advance(s)
		if i > 120:
			var distance: float = boss.target.position.distance_to(s.sim.actor.position)
			low = minf(low,distance)
			high = maxf(high,distance)
	t.check(low >= 150.0 and high <= 250.0,"AD-198 strafe keeps distance in preferred_range +- margin (%.1f..%.1f)" % [low,high])
	t.check(boss.target.position.distance_to(start) > 40.0,"AD-198 strafe actually moves the boss")

func _reposition(t) -> void:
	var pair := _fresh(_move_cfg({"mode":"reposition","anchor_pick":"farthest","speed":200,"max_ticks":300}))
	var s = pair[0]
	var boss = pair[1]
	var entered := false
	for i in 400:
		var before: String = boss.state
		boss.advance(s)
		entered = entered or boss.state == "moving"
		if before == "moving" and boss.state == "recover":
			break
	t.check(entered,"AD-198 reposition enters the moving state")
	t.check(boss.target.position.distance_to(Vector2(1100,200)) <= 6.0,"AD-198 reposition arrives at the farthest anchor (tie goes to the lowest index): %s" % str(boss.target.position))
	t.equal(boss._last_key,"move:reposition","AD-198 a move counts as one no-repeat step")

func _leap(t) -> void:
	var move := {"mode":"leap","target":"player","telegraph_ticks":50,"flight_ticks":24,"radius":110,"damage":12,"channel":"physical"}
	for dodge in [false,true]:
		var pair := _fresh(_move_cfg(move))
		var s = pair[0]
		var boss = pair[1]
		s.sim.actor.position = Vector2(1030,150)
		var health: float = s.sim.actor.health.current
		var windup := 0
		var landing := Vector2.ZERO
		var moved := false
		var hurt_early := false
		var start: Vector2 = boss.target.position
		for i in 300:
			boss.advance(s)
			if boss.state == "windup":
				windup += 1
				landing = boss.intent.snapshot()["landing"]
				if dodge and windup == 20:
					s.sim.actor.position = Vector2(400,650)
				moved = moved or boss.target.position != start
				hurt_early = hurt_early or s.sim.actor.health.current < health
			elif windup > 0 and boss.state == "recover":
				break
		t.check(windup >= 36,"AD-198 leap telegraph is at least min_telegraph_ticks (%d)" % windup)
		t.check(not moved and not hurt_early,"AD-198 leap does nothing before its telegraph ends")
		t.equal(landing,Vector2(1030,150),"AD-198 leap landing is locked to the player position when the windup starts")
		t.check(boss.target.position.distance_to(landing) < 0.01,"AD-198 leap lands at the locked point even if the player moved")
		if dodge:
			t.equal(s.sim.actor.health.current,health,"AD-198 a player outside the leap radius takes no damage")
		else:
			t.check(s.sim.actor.health.current < health,"AD-198 a player inside the leap radius is damaged")

func _leap_fallback(t) -> void:
	var pair := _fresh(_move_cfg({"mode":"leap","target":"player","telegraph_ticks":50,"flight_ticks":24,"radius":110,"damage":12}))
	var s = pair[0]
	var boss = pair[1]
	s.sim.actor.position = Vector2(600,270)
	var landing := Vector2.ZERO
	for i in 5:
		boss.advance(s)
		if boss.state == "windup":
			landing = boss.intent.snapshot()["landing"]
			break
	t.equal(landing,Vector2(300,450),"AD-198 a leap landing inside a wall falls back to the nearest valid anchor")
	t.check(s.world.valid_position(landing,boss.target.radius),"AD-198 the fallback landing is a valid position")

func _submerge(t) -> void:
	var pair := _fresh(_move_cfg({"mode":"submerge","telegraph_ticks":40,"submerged_ticks":60,"emerge_telegraph_ticks":50,"anchor_pick":"farthest","radius":110,"damage":10}))
	var s = pair[0]
	var boss = pair[1]
	var team: int = s.sim.actor.team
	var emerge_ticks := 0
	var hidden_ok := true
	var start: Vector2 = boss.target.position
	var saw_submerged := false
	for i in 400:
		boss.advance(s)
		if boss.state == "submerged" or (boss.state == "windup" and str(boss.intent.snapshot()["kind"]) == "emerge"):
			saw_submerged = true
			hidden_ok = hidden_ok and boss.submerged and not boss.target.eligible(team) and boss.target.alive() and s.alive_enemies() == 1 \
				and boss.target.receive_damage(50.0,"physical",team,1.0) == 0.0 and boss.target.position == start
		if boss.state == "windup" and str(boss.intent.snapshot()["kind"]) == "emerge":
			emerge_ticks += 1
			t.equal(boss.intent.snapshot()["landing"],Vector2(1100,200),"AD-198 emerge telegraph shows the chosen anchor")
		elif emerge_ticks > 0:
			break
	t.check(saw_submerged and hidden_ok,"AD-198 submerged boss is untargetable and hidden, yet alive and counted")
	t.check(emerge_ticks >= 36,"AD-198 emerge is telegraphed for at least min_telegraph_ticks (%d)" % emerge_ticks)
	t.equal(boss.target.position,Vector2(1100,200),"AD-198 boss reappears at the anchor only after the emerge telegraph")
	t.check(not boss.submerged and boss.target.eligible(team),"AD-198 emerged boss is targetable again")
	boss.target.health.current = 0.0
	boss.advance(s)
	t.check(boss.state == "dead" and not boss.submerged and not boss.target.untargetable,"AD-198 death clears the submerged flags")

func _telegraph_floor(t) -> void:
	var pool: Array = [{"move":{"mode":"leap","telegraph_ticks":3,"flight_ticks":24,"radius":110,"damage":12}},
		{"move":{"mode":"submerge","telegraph_ticks":2,"submerged_ticks":60,"emerge_telegraph_ticks":1,"radius":110,"damage":10}},
		{"pattern":"radial"},{"pattern":"fan"},{"pattern":"targeted"}]
	var boss = _fresh(_base({"anchors":ANCHORS,"phases":[{"threshold":1.0,"windup_ticks":40,"pool":pool}]}))[1]
	var leap: Dictionary = boss.tuning["phases"][0]["pool"][0]["move"]
	var sub: Dictionary = boss.tuning["phases"][0]["pool"][1]["move"]
	for value in [leap["telegraph_ticks"],sub["telegraph_ticks"],sub["emerge_telegraph_ticks"]]:
		t.check(int(value) >= 36,"AD-198 move telegraph %d is clamped to min_telegraph_ticks" % int(value))

func _pick_anchor(t) -> void:
	var world = _fresh(_base())[0].world
	var anchors: Array = [[1100,200],[1100,700],[300,450],[600,270]]
	var from := Vector2(1100,450)
	var tied: Array = [[1100,200],[1100,700],[600,270]]
	t.equal(world.pick_anchor(tied,from,49.0,true,Vector2.ZERO),Vector2(1100,200),"AD-198 pick_anchor farthest tie goes to the lowest index")
	t.equal(world.pick_anchor(tied,from,49.0,false,Vector2.ZERO),Vector2(1100,200),"AD-198 pick_anchor nearest tie goes to the lowest index")
	t.equal(world.pick_anchor([[600,270]],from,49.0,true,Vector2(5,5)),Vector2(5,5),"AD-198 pick_anchor skips anchors inside walls and returns the fallback")
	t.equal(world.nearest_open_point(Vector2(700,450),anchors,49.0,Vector2.ZERO),Vector2(700,450),"AD-198 nearest_open_point keeps a valid point")
	t.equal(world.nearest_open_point(Vector2(600,270),anchors,49.0,Vector2.ZERO),Vector2(300,450),"AD-198 nearest_open_point snaps an invalid point to the nearest valid anchor")
	t.equal(world.nearest_open_point(Vector2(600,270),[],49.0,Vector2(9,9)),Vector2(9,9),"AD-198 nearest_open_point falls back to the caller position")

func _stationary(t) -> void:
	var flat := _base()
	flat.erase("anchors")
	var pair := _fresh(flat)
	for i in 600:
		pair[1].advance(pair[0])
	t.equal(pair[1].target.position,AT,"AD-198 a phase without movement or move entries never moves the boss")
	t.check(not pair[1].submerged and not pair[1].target.untargetable,"AD-198 legacy boss is never submerged")

func _validate_moves(t) -> void:
	var good := _move_cfg({"mode":"reposition","speed":200,"max_ticks":120})
	t.equal(BossCombat.validate(good),[],"AD-198 a valid movement config has no issues")
	var bad_mode: Array = BossCombat.validate(_move_cfg({"mode":"teleport"})).map(func(i): return i["code"])
	t.equal(bad_mode,["BOSS_MOVE_MODE"],"AD-198 validate flags an unknown move mode")
	var bad_phase: Array = BossCombat.validate(_movement_cfg({"mode":"fly"})).map(func(i): return i["code"])
	t.equal(bad_phase,["BOSS_MOVE_MODE"],"AD-198 validate flags an unknown phase movement mode")
	var missing: Array = BossCombat.validate(_movement_cfg({"mode":"strafe","speed":80})).map(func(i): return i["code"])
	t.equal(missing,["BOSS_MOVE_PARAM","BOSS_MOVE_PARAM"],"AD-198 validate flags missing strafe keys")
	var no_anchors := good.duplicate(true)
	no_anchors.erase("anchors")
	var codes: Array = BossCombat.validate(no_anchors).map(func(i): return i["code"])
	t.equal(codes,["BOSS_MOVE_ANCHORS"],"AD-198 validate flags a reposition without anchors")
	var leap_no_anchors := _move_cfg({"mode":"leap","telegraph_ticks":40,"flight_ticks":20,"radius":100,"damage":5})
	leap_no_anchors.erase("anchors")
	t.equal(BossCombat.validate(leap_no_anchors),[],"AD-198 a leap at the player needs no anchors")

## AD-198 step 3: arena hazards. Boss shots deal no damage so only hazards hurt; the session is stepped so hazards age like in play.
func _hazard_cfg(hazards: Array, extra: Dictionary = {}) -> Dictionary:
	return _base({"shot_damage":0,"radial_damage":0,"pulse_damage":0,"recovery_ticks":600,
		"phases":[{"threshold":1.0,"windup_ticks":40,"hazards":hazards,"pool":[{"pattern":"radial"},{"pattern":"fan"},{"pattern":"targeted"}]}]}).merged(extra,true)

func _kinds(s, wanted: Array) -> Array:
	return s.hazards.filter(func(h): return wanted.has(h["kind"]))

## Steps `calls` ticks; returns {"warn":ticks with a boss_warning visible,"hits":1-based call numbers where the player lost hp}.
func _run_hazards(s, calls: int) -> Dictionary:
	var warn := 0
	var hits: Array = []
	var hp: float = s.sim.actor.health.current
	for i in calls:
		s.step()
		if not _kinds(s,["boss_warning"]).is_empty():
			warn += 1
		if s.sim.actor.health.current < hp:
			hits.append(i+1)
		hp = s.sim.actor.health.current
	return {"warn":warn,"hits":hits}

func _zone_spec(at: Vector2) -> Dictionary:
	return {"type":"zone","at":"points","points":[[at.x,at.y]],"radius":80,"active_ticks":90,"damage":6,"damage_interval_ticks":30,
		"channel":"fire","first_ticks":10,"every_ticks":1000,"warn_ticks":40}

func _zone(t) -> void:
	var inside = _fresh(_hazard_cfg([_zone_spec(AT+Vector2(-300,0))]))[0]
	var r := _run_hazards(inside,160)
	t.equal(r["warn"],40,"AD-198 a zone warns for exactly warn_ticks")
	t.equal(r["hits"],[51,81,111],"AD-198 zone damages on its first active tick and then every damage_interval_ticks, never during the warning")
	t.check(_kinds(inside,["boss_zone"]).is_empty(),"AD-198 the zone disappears after active_ticks")
	var outside = _fresh(_hazard_cfg([_zone_spec(Vector2(200,150))]))[0]
	t.equal(_run_hazards(outside,160)["hits"],[],"AD-198 a player outside the zone takes no damage")
	var live = _fresh(_hazard_cfg([_zone_spec(AT+Vector2(-300,0))]))[0]
	_run_hazards(live,60)
	var zone: Array = _kinds(live,["boss_zone"])
	t.check(zone.size() == 1 and zone[0]["source_id"] == live.enemies[0].target.id and zone[0]["status"] == "" and zone[0]["interval_ticks"] == 1,
		"AD-198 the active zone is published as a render-only boss_zone owned by the boss")
	var player_zone := _fresh(_hazard_cfg([{"type":"zone","at":"player","radius":80,"active_ticks":30,"damage":6,"damage_interval_ticks":30,
		"first_ticks":0,"every_ticks":1000,"warn_ticks":40}]))
	player_zone[0].step()
	t.equal(_kinds(player_zone[0],["boss_warning"])[0]["position"],player_zone[0].sim.actor.position,"AD-198 an at-player zone locks on the player when the warning starts")

func _zone_dash(t) -> void:
	var s = _fresh(_hazard_cfg([_zone_spec(AT+Vector2(-300,0))]))[0]
	s.player.invulnerable_left = 1000
	t.equal(_run_hazards(s,160)["hits"],[],"AD-198 an invulnerable (dashing) player takes no hazard damage")

func _debris_cfg(seed_extra: int = 0) -> Dictionary:
	return _hazard_cfg([{"type":"debris","count":3,"scatter":140,"radius":60,"damage":10,"channel":"physical","first_ticks":5,"every_ticks":1000,"warn_ticks":40}])

func _debris(t) -> void:
	var s = _fresh(_debris_cfg())[0]
	for i in 6:
		s.step()
	var points: Array = _kinds(s,["boss_warning"]).map(func(h): return h["position"])
	t.equal(points.size(),3,"AD-198 debris warns one circle per impact")
	var player_at: Vector2 = s.sim.actor.position
	for point in points:
		t.check(point.distance_to(player_at) <= 140.0+0.01,"AD-198 debris impacts land within scatter of the player")
	s.sim.actor.position = points[0]
	for i in 20:
		s.step()
	t.equal(_kinds(s,["boss_warning"]).map(func(h): return h["position"]),points,"AD-198 debris points stay locked while the player moves")
	var before: float = s.sim.actor.health.current
	for i in 40:
		s.step()
	t.check(s.sim.actor.health.current < before,"AD-198 debris hits where the locked point was, once at the end of the warning")
	t.check(_kinds(s,["boss_warning","boss_zone"]).is_empty(),"AD-198 debris leaves nothing behind after the impact")
	var dodged = _fresh(_debris_cfg())[0]
	for i in 6:
		dodged.step()
	dodged.sim.actor.position = Vector2(100,100)
	t.equal(_run_hazards(dodged,60)["hits"],[],"AD-198 stepping away from the locked debris points avoids the damage")

func _debris_points(seed: int) -> Array:
	var s = _fresh(_debris_cfg(),seed)[0]
	for i in 6:
		s.step()
	return _kinds(s,["boss_warning"]).map(func(h): return h["position"])

func _debris_determinism(t) -> void:
	t.equal(_debris_points(5),_debris_points(5),"AD-198 same seed gives the same debris positions")
	t.check(_debris_points(5) != _debris_points(6),"AD-198 a different seed gives different debris positions")

func _water_cfg() -> Dictionary:
	return _hazard_cfg([{"type":"rising_water","duration_ticks":100,"first_ticks":5,"every_ticks":1000,"warn_ticks":40,
		"sets":[[{"kind":"shallow","rect":[400,300,200,100]}]]}])

func _rising_water(t) -> void:
	var s = _fresh(_water_cfg())[0]
	s.set_water([{"kind":"shallow","rect":[0,0,60,60]}])
	var inside := Vector2(500,350)
	for i in 6:
		s.step()
	var warning: Array = _kinds(s,["boss_water_warning"])
	t.check(warning.size() == 1 and warning[0]["rect"] == Rect2(400,300,200,100) and warning[0]["position"] == Vector2(500,350)
		and is_equal_approx(warning[0]["radius"],Vector2(200,100).length()*0.5),"AD-198 water warning outlines the rect")
	t.check(not s.water.in_water(inside),"AD-198 no water yet during the warning")
	for i in 40:
		s.step()
	t.check(s.water.in_water(inside),"AD-198 the rising water appears when the warning ends")
	t.check(s.water.view().any(func(e): return e.get("tag","") == WATER_TAG),"AD-198 rising water entries carry their own tag")
	t.check(_kinds(s,["boss_water_warning"]).is_empty(),"AD-198 the water warning is gone once the water is up")
	for i in 100:
		s.step()
	t.check(not s.water.in_water(inside),"AD-198 rising water recedes after duration_ticks")
	t.check(s.water.in_water(Vector2(30,30)),"AD-198 other water survives the rising water")
	var empty = _fresh(_water_cfg())[0]
	t.check(empty.water == null,"AD-198 session starts without water")
	for i in 50:
		empty.step()
	t.check(empty.water != null and empty.water.in_water(inside),"AD-198 rising water creates the water set when the room has none")

func _hazard_stop(t) -> void:
	var specs: Array = [_zone_spec(AT+Vector2(-300,0)),{"type":"rising_water","duration_ticks":500,"first_ticks":5,"every_ticks":1000,"warn_ticks":40,
		"sets":[[{"kind":"shallow","rect":[400,300,200,100]}]]}]
	var pair := _fresh(_hazard_cfg(specs))
	var s = pair[0]
	s.set_water([{"kind":"shallow","rect":[0,0,60,60]}])
	_run_hazards(s,70)
	t.check(not _kinds(s,["boss_zone"]).is_empty() and s.water.in_water(Vector2(500,350)),"AD-198 hazards are running before the boss dies")
	pair[1].target.health.current = 0.0
	s.step()
	t.check(_kinds(s,["boss_warning","boss_water_warning","boss_zone"]).is_empty(),"AD-198 hazards stop at boss death")
	t.check(not s.water.in_water(Vector2(500,350)) and s.water.in_water(Vector2(30,30)),"AD-198 boss death removes only the rising water")
	var hits: Array = _run_hazards(s,200)["hits"]
	t.equal(hits,[],"AD-198 a dead boss spawns no further hazards")
	# phase change
	var phased := _hazard_cfg(specs,{"phases":[{"threshold":1.0,"windup_ticks":40,"hazards":specs,"pool":[{"pattern":"radial"},{"pattern":"fan"},{"pattern":"targeted"}]},
		{"threshold":0.5,"windup_ticks":40,"pool":[{"pattern":"radial"},{"pattern":"fan"},{"pattern":"targeted"}]}]})
	var two := _fresh(phased)
	var s2 = two[0]
	s2.set_water([])
	_run_hazards(s2,70)
	t.check(not _kinds(s2,["boss_zone"]).is_empty() and s2.water.in_water(Vector2(500,350)),"AD-198 phase 1 hazards are running")
	two[1].target.health.current = two[1].target.health.maximum*0.4
	s2.step()
	t.equal(two[1].phase,2,"AD-198 the boss enters phase 2")
	t.check(s2.hazards.is_empty() and not s2.water.in_water(Vector2(500,350)),"AD-198 a phase change leaves no hazards or rising water behind")
	t.equal(_run_hazards(s2,200)["hits"],[],"AD-198 a phase without hazards spawns none")
	# the next phase's own schedule starts fresh
	var swap := _hazard_cfg(specs,{"phases":[{"threshold":1.0,"windup_ticks":40,"hazards":specs,"pool":[{"pattern":"radial"},{"pattern":"fan"},{"pattern":"targeted"}]},
		{"threshold":0.5,"windup_ticks":40,"hazards":[_zone_spec(AT+Vector2(-300,0))],"pool":[{"pattern":"radial"},{"pattern":"fan"},{"pattern":"targeted"}]}]})
	var three := _fresh(swap)
	_run_hazards(three[0],30)
	three[1].target.health.current = three[1].target.health.maximum*0.4
	t.equal(_run_hazards(three[0],160)["hits"],[51,81,111],"AD-198 phase 2 hazards restart their own timers at the phase change")

func _hazard_floor(t) -> void:
	var short := _zone_spec(AT+Vector2(-300,0))
	short["warn_ticks"] = 5
	var pair := _fresh(_hazard_cfg([short]))
	t.equal(int(pair[1].tuning["phases"][0]["hazards"][0]["warn_ticks"]),36,"AD-198 hazard warn_ticks are clamped to min_telegraph_ticks")
	t.equal(_run_hazards(pair[0],80)["warn"],36,"AD-198 a clamped hazard warns for the floor")

func _hazard_fx(t) -> void:
	var s = _fresh(_hazard_cfg([_zone_spec(AT+Vector2(-300,0))]))[0]
	for i in 15:
		s.step()
	var found: Array = Art.collect_fx(s,s.sim.clock.tick,{}).filter(func(e): return e["event"] == "telegraph.circle" and e.get("uniform",0.0) == 160.0)
	t.equal(found.size(),1,"AD-198 collect_fx emits one telegraph.circle for a boss_warning")
	if found.size() == 1:
		t.check(found[0]["at"] == AT+Vector2(-300,0) and found[0]["window"] == 41 and found[0]["age"] == 5,"AD-198 the hazard telegraph carries position, age and window")

func _hazard_legacy(t) -> void:
	var s = _fresh(_base())[0]
	var boss = s.enemies[0]
	for i in 600:
		s.step()
	t.check(s.hazards.is_empty() and boss._hazards == null,"AD-198 a boss without hazards spawns none over 600 ticks")

func _validate_hazards(t) -> void:
	var good := _hazard_cfg([_zone_spec(AT),_water_cfg()["phases"][0]["hazards"][0],_debris_cfg()["phases"][0]["hazards"][0]])
	t.equal(BossCombat.validate(good),[],"AD-198 valid hazards have no issues")
	var codes := func(cfg): return BossCombat.validate(cfg).map(func(i): return i["code"])
	t.equal(codes.call(_hazard_cfg([{"type":"meteor","first_ticks":0,"every_ticks":10,"warn_ticks":40}])),["BOSS_HAZARD_TYPE"],"AD-198 validate flags an unknown hazard type")
	var broken := _zone_spec(AT)
	broken.erase("damage")
	broken["warn_ticks"] = 0
	t.equal(codes.call(_hazard_cfg([broken])),["BOSS_HAZARD_PARAM","BOSS_HAZARD_PARAM"],"AD-198 validate flags missing or invalid hazard params")
	var deep := {"type":"rising_water","duration_ticks":100,"first_ticks":5,"every_ticks":1000,"warn_ticks":40,"sets":[[{"kind":"deep","rect":[0,0,10,10]}]]}
	t.equal(codes.call(_hazard_cfg([deep])),["BOSS_HAZARD_DEEP_WATER"],"AD-198 validate rejects deep rising water")

## AD-198 step 4: phase-transition roar and stagger window. Shots deal no damage so only the test's own hits change boss or player hp.
const ROAR_WATER := [{"kind":"shallow","rect":[700,100,100,100]}]

func _plain_pool(extra: Array = []) -> Array:
	return extra+[{"pattern":"radial"},{"pattern":"fan"},{"pattern":"targeted"}]

func _roar_cfg(second: Dictionary = {}, pool: Array = [], extra: Dictionary = {}) -> Dictionary:
	var phase2 := {"threshold":0.5,"windup_ticks":40,"pool":_plain_pool(pool),"transition":{"roar_ticks":90,"arena_change":{"clear_hazards":true,"water":ROAR_WATER}}}
	return _base({"shot_damage":0,"radial_damage":0,"pulse_damage":0,"anchors":ANCHORS,
		"phases":[{"threshold":1.0,"windup_ticks":40,"pool":_plain_pool(pool)},phase2.merged(second,true)]}).merged(extra,true)

func _hit(boss, s, amount: float = 100.0) -> float:
	var before: float = boss.target.health.current
	boss.target.receive_damage(amount,"fire",s.sim.actor.team,float(s.sim.settings["combat"]["armor_scale"]))
	return before-boss.target.health.current

func _to_phase2(boss) -> void:
	boss.target.health.current = boss.target.health.maximum*0.4

func _step_until(s, boss, state: String, limit: int = 600) -> bool:
	for i in limit:
		if boss.state == state:
			return true
		s.step()
	return boss.state == state

func _roar(t) -> void:
	var pair := _fresh(_roar_cfg())
	var s = pair[0]
	var boss = pair[1]
	for i in 10:
		s.step()
	_to_phase2(boss)
	var hp: float = boss.target.health.current
	var roar_ticks := 0
	var damage_taken := 0.0
	var scale_ok := true
	for i in 200:
		s.step()
		if boss.state != "roar":
			break
		roar_ticks += 1
		damage_taken += _hit(boss,s)
		scale_ok = scale_ok and boss.target.damage_scale == 0.0 and boss.target.alive() and boss.target.eligible(s.sim.actor.team)
	t.equal(roar_ticks,90,"AD-198 the roar lasts exactly roar_ticks")
	t.check(scale_ok and damage_taken == 0.0 and boss.target.health.current == hp,"AD-198 the boss takes no damage during the roar but stays targetable")
	t.check(boss.target.damage_scale == 1.0 and boss.state == "acquire","AD-198 the roar ends with normal damage and an acquire")
	t.check(boss.transitions.any(func(e): return e["from"] == "phase2" and e["to"] == "roar"),"AD-198 the roar is recorded in transitions")
	t.check(_hit(boss,s) > 0.0,"AD-198 the boss is vulnerable again after the roar")

func _roar_cancels_windup(t) -> void:
	var pair := _fresh(_roar_cfg())
	var s = pair[0]
	var boss = pair[1]
	t.check(_step_until(s,boss,"windup"),"AD-198 test boss reaches a windup")
	for i in 20:
		s.step()
	_to_phase2(boss)
	s.step()
	t.check(boss.state == "roar" and boss.intent == null and boss._windup_attack == "" and boss._combo_queue.is_empty(),"AD-198 a windup in progress is cancelled by the roar")
	var shots := 0
	for i in 95:
		s.step()
		shots = maxi(shots,s.enemy_shots.size())
	t.equal(shots,0,"AD-198 a cancelled windup never fires")
	var combo := _fresh(_roar_cfg({},[{"combo":["radial","fan"],"gap_ticks":12,"weight":1000}]))
	for i in 3:
		combo[0].step()
	_to_phase2(combo[1])
	for i in 100:
		combo[0].step()
	t.check(combo[1].state != "roar" and combo[1]._combo_queue.size() <= 1,"AD-198 the roar clears the combo queue")

func _roar_arena(t) -> void:
	var spec := {"type":"zone","at":"player","radius":80,"active_ticks":500,"damage":6,"damage_interval_ticks":30,"channel":"fire","first_ticks":0,"every_ticks":1000,"warn_ticks":40}
	var cfg := _roar_cfg()
	cfg["phases"][0]["hazards"] = [spec]
	var pair := _fresh(cfg)
	var s = pair[0]
	var boss = pair[1]
	s.set_water([])
	for i in 60:
		s.step()
	t.check(not _kinds(s,["boss_warning","boss_zone"]).is_empty(),"AD-198 phase 1 hazard is live before the roar")
	_to_phase2(boss)
	s.step()
	t.check(boss.state == "roar" and _kinds(s,["boss_warning","boss_zone"]).is_empty(),"AD-198 clear_hazards removes the boss hazards at roar start")
	t.check(s.water.in_water(Vector2(750,150)) and s.water.view().any(func(e): return e.get("tag","") == "boss_arena"),"AD-198 arena_change adds tagged shallow water")
	for i in 120:
		s.step()
	t.check(s.water.in_water(Vector2(750,150)),"AD-198 the arena water outlasts the roar")
	boss.target.health.current = 0.0
	s.step()
	t.check(boss.state == "dead" and not s.water.in_water(Vector2(750,150)),"AD-198 boss death removes the arena water")
	var none := _fresh(_roar_cfg())
	for i in 5:
		none[0].step()
	_to_phase2(none[1])
	none[0].step()
	t.check(none[0].water != null and none[0].water.in_water(Vector2(750,150)),"AD-198 arena_change creates the water set when the room has none")

func _roar_hazard_timers(t) -> void:
	var spec := {"type":"zone","at":"points","points":[[730,330]],"radius":80,"active_ticks":60,"damage":0,"damage_interval_ticks":30,"first_ticks":10,"every_ticks":1000,"warn_ticks":40}
	var cfg := _roar_cfg({"hazards":[spec]})
	var pair := _fresh(cfg)
	var s = pair[0]
	var boss = pair[1]
	for i in 5:
		s.step()
	_to_phase2(boss)
	var roar_ticks := 0
	var warned_in_roar := false
	var first_warn := -1
	var after := 0
	for i in 200:
		s.step()
		if boss.state == "roar":
			roar_ticks += 1
			warned_in_roar = warned_in_roar or not _kinds(s,["boss_warning"]).is_empty()
		else:
			after += 1
			if first_warn < 0 and not _kinds(s,["boss_warning"]).is_empty():
				first_warn = after
	t.check(not warned_in_roar and roar_ticks == 90,"AD-198 no hazard starts during the roar")
	t.check(first_warn >= 9 and first_warn <= 12,"AD-198 phase hazard timers start when the roar ends (first warning %d ticks after)" % first_warn)

func _roar_defer(t) -> void:
	var move := {"mode":"submerge","telegraph_ticks":40,"submerged_ticks":60,"emerge_telegraph_ticks":50,"anchor_pick":"farthest","radius":110,"damage":0}
	var pair := _fresh(_roar_cfg({},[{"move":move,"weight":1000}]))
	var s = pair[0]
	var boss = pair[1]
	t.check(_step_until(s,boss,"submerged"),"AD-198 test boss submerges")
	_to_phase2(boss)
	var roar_early := false
	var emerge_seen := false
	for i in 400:
		s.step()
		emerge_seen = emerge_seen or (boss.state == "windup" and str(boss.intent.snapshot()["kind"]) == "emerge")
		if boss.state == "roar":
			break
		roar_early = roar_early or (not emerge_seen and boss.state != "submerged" and boss.state != "windup")
	t.check(boss.state == "roar" and emerge_seen and not roar_early,"AD-198 a submerge in progress defers the roar until the boss has emerged")
	t.check(not boss.submerged and not boss.target.untargetable and boss.target.position == Vector2(1100,200) and boss.target.damage_scale == 0.0,"AD-198 the deferred roar starts visible and invulnerable at the emerge point")
	t.check(not boss._pending_roar,"AD-198 the pending roar flag is consumed")
	var leap := {"mode":"leap","target":"anchor","anchor_pick":"farthest","telegraph_ticks":50,"flight_ticks":24,"radius":110,"damage":0}
	var airborne := _fresh(_roar_cfg({},[{"move":leap,"weight":1000}]))
	t.check(_step_until(airborne[0],airborne[1],"moving"),"AD-198 test boss leaps")
	_to_phase2(airborne[1])
	airborne[0].step()
	t.check(airborne[1].state == "moving" and airborne[1]._pending_roar,"AD-198 a leap in flight defers the roar")
	t.check(_step_until(airborne[0],airborne[1],"roar",100) and airborne[1].target.position.distance_to(Vector2(1100,200)) < 0.01,"AD-198 the roar starts after the leap has landed")
	var wind := _fresh(_roar_cfg({},[{"move":move,"weight":1000}]))
	t.check(_step_until(wind[0],wind[1],"windup") and str(wind[1].intent.snapshot()["kind"]) == "submerge","AD-198 test boss is in the submerge windup")
	_to_phase2(wind[1])
	wind[0].step()
	t.check(wind[1].state == "roar" and not wind[1].submerged,"AD-198 a submerge windup is cancelled by the roar")

func _roar_multi(t) -> void:
	var cfg := _roar_cfg()
	cfg["phases"].append({"threshold":0.2,"windup_ticks":40,"pool":_plain_pool(),"transition":{"roar_ticks":30}})
	var pair := _fresh(cfg)
	var s = pair[0]
	var boss = pair[1]
	for i in 5:
		s.step()
	boss.target.health.current = boss.target.health.maximum*0.1
	s.step()
	var roars: int = boss.transitions.filter(func(e): return e["to"] == "roar").size()
	var ticks := 0
	while boss.state == "roar" and ticks < 300:
		s.step()
		ticks += 1
	t.check(boss.phase == 3 and roars == 1 and ticks == 30 and boss.state == "acquire","AD-198 crossing two thresholds at once plays one roar for the highest phase (%d roars, %d ticks)" % [roars,ticks])

func _stagger_cfg(pool: Array) -> Dictionary:
	return _base({"shot_damage":0,"radial_damage":0,"pulse_damage":0,"anchors":ANCHORS,"stagger":{"ticks":90,"damage_taken_multiplier":1.5},
		"phases":[{"threshold":1.0,"windup_ticks":40,"pool":pool}]})

func _stagger(t) -> void:
	var pair := _fresh(_stagger_cfg([{"pattern":"radial","big":true,"weight":1000},{"pattern":"fan"},{"pattern":"targeted"}]))
	var s = pair[0]
	var boss = pair[1]
	var normal := _hit(boss,s)
	t.check(_step_until(s,boss,"stagger"),"AD-198 a finished big attack enters stagger")
	var staggered_ok: bool = boss.staggered and boss.target.damage_scale == 1.5
	var dealt := _hit(boss,s)
	t.check(staggered_ok and absf(dealt/normal-1.5) < 0.001,"AD-198 damage during stagger is 1.5x the same hit outside it (%.2f vs %.2f)" % [dealt,normal])
	var ticks := 0
	var held := true
	while boss.state == "stagger" and ticks < 300:
		held = held and boss.staggered and boss.target.position == AT
		s.step()
		ticks += 1
	t.check(ticks == 90 and held,"AD-198 stagger lasts exactly its ticks and the boss does not move")
	t.check(not boss.staggered and boss.target.damage_scale == 1.0 and absf(_hit(boss,s)-normal) < 0.001,"AD-198 stagger restores normal damage")
	t.check(boss.state == "windup","AD-198 the boss goes on to its next windup after stagger")
	var plain := _fresh(_stagger_cfg(_plain_pool()))
	var seen := false
	for i in 900:
		plain[0].step()
		seen = seen or plain[1].state == "stagger" or plain[1].staggered
	t.check(not seen,"AD-198 stagger follows only big entries")
	var combo := _fresh(_stagger_cfg([{"combo":["radial","fan"],"gap_ticks":12,"big":true,"weight":1000},{"pattern":"fan"},{"pattern":"targeted"}]))
	var early := false
	var windups := 0
	var prev := ""
	for i in 600:
		combo[0].step()
		if combo[1].state == "windup" and prev != "windup":
			windups += 1
		prev = combo[1].state
		if combo[1].state == "stagger":
			break
		early = early or combo[1].staggered
	t.check(combo[1].state == "stagger" and windups == 2 and not early,"AD-198 a big combo staggers only after its last member")
	var leap := {"mode":"leap","target":"anchor","anchor_pick":"farthest","telegraph_ticks":50,"flight_ticks":24,"radius":110,"damage":0}
	var jump := _fresh(_stagger_cfg([{"move":leap,"big":true,"weight":1000},{"pattern":"radial"},{"pattern":"fan"},{"pattern":"targeted"}]))
	t.check(_step_until(jump[0],jump[1],"stagger") and jump[1].target.position.distance_to(Vector2(1100,200)) < 0.01,"AD-198 a big leap staggers once it has landed")

func _beats_death(t) -> void:
	var pair := _fresh(_stagger_cfg([{"pattern":"radial","big":true,"weight":1000},{"pattern":"fan"},{"pattern":"targeted"}]))
	_step_until(pair[0],pair[1],"stagger")
	pair[1].target.health.current = 0.0
	pair[0].step()
	t.check(pair[1].state == "dead" and not pair[1].staggered and pair[1].target.damage_scale == 1.0,"AD-198 death during stagger leaves no flags")
	var roaring := _fresh(_roar_cfg())
	for i in 5:
		roaring[0].step()
	_to_phase2(roaring[1])
	for i in 20:
		roaring[0].step()
	roaring[1].target.health.current = 0.0
	roaring[0].step()
	t.check(roaring[1].state == "dead" and not roaring[1]._pending_roar and roaring[1].target.damage_scale == 1.0,"AD-198 death during the roar leaves no flags")
	var move := {"mode":"submerge","telegraph_ticks":40,"submerged_ticks":60,"emerge_telegraph_ticks":50,"radius":110,"damage":0}
	var pending := _fresh(_roar_cfg({},[{"move":move,"weight":1000}]))
	_step_until(pending[0],pending[1],"submerged")
	_to_phase2(pending[1])
	pending[0].step()
	pending[1].target.health.current = 0.0
	pending[0].step()
	t.check(pending[1].state == "dead" and not pending[1]._pending_roar and not pending[1].submerged and not pending[1].target.untargetable,"AD-198 death with a deferred roar leaves no flags")

func _beats_legacy(t) -> void:
	var cfg := _base({"shot_damage":0,"radial_damage":0,"pulse_damage":0,"phases":[{"threshold":1.0,"windup_ticks":40,"pool":_plain_pool()},
		{"threshold":0.5,"windup_ticks":40,"pool":_plain_pool()}]})
	var pair := _fresh(cfg)
	var s = pair[0]
	var boss = pair[1]
	var seen: Array = []
	for i in 300:
		if i == 100:
			_to_phase2(boss)
		s.step()
		if not seen.has(boss.state):
			seen.append(boss.state)
		if boss.state == "roar" or boss.state == "stagger" or boss.staggered or boss.target.damage_scale != 1.0:
			break
	t.check(boss.phase == 2 and not seen.has("roar") and not seen.has("stagger") and boss.target.damage_scale == 1.0,"AD-198 a boss without transition/stagger has no roar or stagger (%s)" % str(seen))
	t.check(not boss.transitions.any(func(e): return e["to"] == "roar"),"AD-198 a legacy phase change records no roar")

func _beats_fx(t) -> void:
	var pair := _fresh(_roar_cfg())
	var s = pair[0]
	var boss = pair[1]
	var memo := {}
	for i in 5:
		s.step()
	_to_phase2(boss)
	var phases := 0
	var live := false
	for i in 100:
		s.step()
		var now := not Art.collect_fx(s,s.sim.clock.tick,memo).filter(func(e): return e["event"] == "boss.phase").is_empty()
		phases += 1 if now and not live else 0
		live = now
	t.equal(phases,1,"AD-198 collect_fx emits one boss.phase per roar")

func _validate_beats(t) -> void:
	var codes := func(cfg): return BossCombat.validate(cfg).map(func(i): return i["code"])
	t.equal(BossCombat.validate(_roar_cfg({},[],{"stagger":{"ticks":90,"damage_taken_multiplier":1.5}})),[],"AD-198 valid transition and stagger have no issues")
	t.equal(codes.call(_roar_cfg({"transition":{"roar_ticks":0}})),["BOSS_TRANSITION_PARAM"],"AD-198 validate flags roar_ticks < 1")
	t.equal(codes.call(_roar_cfg({"transition":{"roar_ticks":90,"arena_change":{"water":[{"kind":"deep","rect":[0,0,10,10]}]}}})),["BOSS_TRANSITION_PARAM"],"AD-198 validate flags non-shallow arena water")
	t.equal(codes.call(_roar_cfg({},[],{"stagger":{"ticks":0,"damage_taken_multiplier":1.5}})),["BOSS_STAGGER_PARAM"],"AD-198 validate flags stagger ticks < 1")
	t.equal(codes.call(_roar_cfg({},[],{"stagger":{"ticks":90,"damage_taken_multiplier":1.0}})),["BOSS_STAGGER_PARAM"],"AD-198 validate flags a stagger multiplier <= 1")
