extends RefCounted
## AD-141 step 1: data-driven mini-boss patterns (elite variants with +1 pattern).
const Session = preload("res://combat/combat_session.gd")
const AT := Vector2(1030,450)
const IDS := ["ruins_adept_elite","cistern_crystal_elite"]
const EXTRA := {"ruins_adept_elite":"fan","cistern_crystal_elite":"pulse"}
const ELITE := {"hp_multiplier":1.5,"damage_multiplier":1.0}

func run(t) -> void:
	for id in IDS:
		_boss(t,id)
	_pulse_range(t)
	_unknown_and_deterministic(t)

func _fresh(id: String, elite: Dictionary = ELITE):
	var s = Session.new(1411,"empty",0)
	s.defer_clear = true
	return [s,s.spawn_mini_boss(id,AT,elite)]

func _run_ticks(boss, s, n: int) -> void:
	for i in n:
		boss.advance(s)

func _boss(t, id: String) -> void:
	var pair = _fresh(id)
	var s = pair[0]
	var boss = pair[1]
	var cfg: Dictionary = s.data["mini_bosses"][id]
	t.check(boss != null,"AD-141 %s spawns" % id)
	t.equal(boss.kind,str(cfg["base_enemy"]),"AD-141 %s kind matches base enemy" % id)
	t.check(boss.target.tags.has("boss") and boss.target.tags.has("mini_boss"),"AD-141 %s tagged boss + mini_boss" % id)
	t.equal(boss.target.health.maximum,float(cfg["hp"])*float(ELITE["hp_multiplier"]),"AD-141 %s hp = hp x elite multiplier" % id)
	var patterns: Array = boss.tuning["patterns"]
	t.equal(patterns.size(),2,"AD-141 %s has base pattern +1" % id)
	t.check(patterns.has(EXTRA[id]) and EXTRA[id] not in ["radial","targeted"],"AD-141 %s has a pattern the warden lacks" % id)
	var floor_ticks := int(cfg["min_telegraph_ticks"])
	t.check(int(boss.tuning["windup_ticks"]) >= floor_ticks and int(boss.tuning["second_phase_windup_ticks"]) >= floor_ticks,"AD-141 %s telegraphs >= min ticks" % id)
	t.check(floor_ticks >= 36,"AD-141 %s min telegraph is 0.6 s" % id)
	s.sim.actor.position = AT+Vector2(-100,0)
	var hp0: float = s.sim.actor.health.current
	var windup := int(boss.tuning["windup_ticks"])
	boss.advance(s)
	t.equal(boss.state,"windup","AD-141 %s starts windup" % id)
	t.equal(boss.intent.snapshot()["kind"],str(patterns[0]),"AD-141 %s first pattern" % id)
	_run_ticks(boss,s,windup-1)
	t.check(s.enemy_shots.is_empty() and s.sim.actor.health.current == hp0,"AD-141 %s nothing fires during windup" % id)
	boss.advance(s)
	t.equal(boss.state,"recover","AD-141 %s fires exactly at end of windup" % id)
	if id == "cistern_crystal_elite":
		t.check(s.sim.actor.health.current < hp0,"AD-141 %s pulse hits inside radius" % id)
	else:
		t.equal(s.enemy_shots.size(),1,"AD-141 %s targeted shot" % id)
	s.enemy_shots.clear()
	_run_ticks(boss,s,int(cfg["recovery_ticks"]))
	t.equal(boss.intent.snapshot()["kind"],str(patterns[1]),"AD-141 %s second pattern next cycle" % id)
	hp0 = s.sim.actor.health.current
	_run_ticks(boss,s,windup-1)
	boss.advance(s)
	if id == "ruins_adept_elite":
		t.equal(s.enemy_shots.size(),int(cfg["fan_shots"]),"AD-141 %s fan count" % id)
	else:
		t.equal(s.enemy_shots.size(),int(cfg["radial_shots"]),"AD-141 %s radial count" % id)
	boss.target.health.current = boss.target.health.maximum*(float(cfg["phase_threshold"])-0.05)
	boss.advance(s)
	t.equal(boss.phase,2,"AD-141 %s phase 2 below threshold" % id)

func _pulse_range(t) -> void:
	var pair = _fresh("cistern_crystal_elite")
	var s = pair[0]
	var boss = pair[1]
	var radius := float(boss.tuning["pulse_radius"])
	s.sim.actor.position = AT+Vector2(-(radius+60.0),0)
	var hp0: float = s.sim.actor.health.current
	_run_ticks(boss,s,int(boss.tuning["windup_ticks"])+1)
	t.equal(boss.state,"recover","AD-141 pulse fired")
	t.equal(s.sim.actor.health.current,hp0,"AD-141 pulse does not hurt outside pulse_radius")

func _unknown_and_deterministic(t) -> void:
	var s = Session.new(1411,"empty",0)
	t.check(s.spawn_mini_boss("nope",AT) == null,"AD-141 unknown mini-boss id returns null")
	var snaps: Array = []
	for run_index in 2:
		var pair = _fresh("ruins_adept_elite")
		for i in 400:
			pair[0].sim.actor.position = Vector2(700,450)
			pair[1].advance(pair[0])
		snaps.append(JSON.stringify(pair[0].snapshot()))
	t.equal(snaps[0],snaps[1],"AD-141 mini-boss run is deterministic")
