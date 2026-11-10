extends RefCounted
## AD-198 step 1: boss framework. Weighted per-phase pattern pools, combos, no immediate repeat, back-compat. All settings are synthetic.
const Session = preload("res://combat/combat_session.gd")
const Pool = preload("res://combat/boss_moves/boss_pattern_pool.gd")
const BossCombat = preload("res://combat/boss_combat.gd")
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
