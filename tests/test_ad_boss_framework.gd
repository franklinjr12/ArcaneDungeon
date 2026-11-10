extends RefCounted
## AD-198 step 1: boss framework. Weighted per-phase pattern pools, combos, no immediate repeat, back-compat. All settings are synthetic.
const Session = preload("res://combat/combat_session.gd")
const Pool = preload("res://combat/boss_moves/boss_pattern_pool.gd")
const AT := Vector2(1030,450)

func run(t) -> void:
	_no_immediate_repeat(t)
	_weights(t)
	_combo(t)
	_determinism(t)
	_validate(t)
	_legacy(t)

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
