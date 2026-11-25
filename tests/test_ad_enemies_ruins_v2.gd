extends RefCounted
## AD-237: new Ruins enemies. Step 1: Rune Sentry (rotating telegraphed beam). Step 2: Grave Mites (swarm). Step 3: Ash Censer (fire ward).
const Session = preload("res://combat/combat_session.gd")
const Registry = preload("res://combat/enemy_behaviours/registry.gd")

func run(t) -> void:
	_sentry_config(t)
	_sentry_validate(t)
	_sentry_telegraph(t)
	_sentry_rotates(t)
	_sentry_off_beam(t)
	_sentry_static(t)
	_sentry_scenario(t)
	_sentry_deterministic(t)
	_mite_config(t)
	_mite_validate(t)
	_mite_scenario(t)
	_mite_stats(t)
	_mite_bite_windup(t)
	_mite_burst_vs_bolt(t)
	_mite_deterministic(t)
	_censer_config(t)
	_censer_validate(t)
	_censer_scenario(t)
	_censer_ward(t)
	_censer_range(t)
	_censer_wet(t)
	_censer_death(t)
	_censer_deterministic(t)

func _sentry_session() -> Array:
	var s = Session.new(237,"empty",0)
	var player = s.sim.actor
	var sentry = s.spawn_enemy("rune_sentry",player.position+Vector2(250,0))
	return [s,sentry]

## Steps until the sentry enters `wanted` (guarded); returns true when reached.
func _until(s, sentry, wanted: String) -> bool:
	var guard := 0
	while sentry.state != wanted and guard < 400:
		s.step()
		guard += 1
	return sentry.state == wanted

func _sentry_config(t) -> void:
	var s = Session.new(237,"empty",0)
	var cfg: Dictionary = s.data["enemies"].get("rune_sentry",{})
	t.check(not cfg.is_empty() and Registry.validate_enemy(cfg).is_empty(),"AD-237 rune_sentry config validates")
	t.check(int(cfg["telegraph_ticks"]) >= 50,"AD-237 rune_sentry telegraph >= 50 ticks (%d)" % int(cfg["telegraph_ticks"]))
	t.check(float(cfg["move_speed"]) == 0.0,"AD-237 rune_sentry has move_speed 0")
	var negatives: Array = []
	for channel in cfg["channel_resistances"]:
		if float(cfg["channel_resistances"][channel]) < 0.0:
			negatives.append(channel)
	t.check(negatives == ["lightning"],"AD-237 rune_sentry has exactly one weakness: lightning (%s)" % str(negatives))
	var beam: Dictionary = {}
	for entry in cfg["behaviours"]:
		if entry["id"] == "rune_sentry":
			beam = entry
	var tangential: float = float(beam["beam_length"])*deg_to_rad(float(beam["beam_sweep_degrees_per_tick"]))*60.0
	t.check(tangential < float(s.data["player"]["move_speed"])*0.75,"AD-237 beam tip speed %.0f u/s is well below player speed" % tangential)

func _sentry_validate(t) -> void:
	var script = Registry.SCRIPTS["rune_sentry"]
	var good := {"id":"rune_sentry","beam_length":300,"beam_half_width":14,"beam_sweep_degrees_per_tick":0.5,"beam_active_ticks":180,"hit_interval_ticks":30}
	t.check(script.validate(good).is_empty(),"AD-237 valid rune_sentry accepted")
	for key in ["beam_length","beam_half_width","beam_sweep_degrees_per_tick","beam_active_ticks","hit_interval_ticks"]:
		var missing: Dictionary = good.duplicate()
		missing.erase(key)
		t.check(not script.validate(missing).is_empty(),"AD-237 rune_sentry missing %s rejected" % key)
		var zero: Dictionary = good.duplicate()
		zero[key] = 0
		t.check(not script.validate(zero).is_empty(),"AD-237 rune_sentry %s = 0 rejected" % key)
		var text: Dictionary = good.duplicate()
		text[key] = "x"
		t.check(not script.validate(text).is_empty(),"AD-237 rune_sentry non-numeric %s rejected" % key)

func _sentry_telegraph(t) -> void:
	var r := _sentry_session()
	var s = r[0]
	var sentry = r[1]
	var player = s.sim.actor
	var telegraph := int(sentry.tuning["telegraph_ticks"])
	t.check(_until(s,sentry,"windup"),"AD-237 sentry starts a windup when the player is in reach")
	var hp0: float = player.health.current
	var windup_ticks := 0
	var damaged_in_windup := false
	var guard := 0
	while sentry.state == "windup" and guard < 400:
		windup_ticks += 1
		if player.health.current < hp0:
			damaged_in_windup = true
		s.step()
		guard += 1
	t.check(not damaged_in_windup,"AD-237 no damage during the telegraph")
	t.check(windup_ticks == telegraph,"AD-237 windup lasts telegraph_ticks (%d vs %d)" % [windup_ticks,telegraph])
	t.check(sentry.state == "attack","AD-237 windup is followed by the attack state (%s)" % sentry.state)
	t.check(player.health.current == hp0,"AD-237 still undamaged at the first attack tick")
	guard = 0
	while sentry.state == "attack" and player.health.current == hp0 and guard < 400:
		s.step()
		guard += 1
	t.check(player.health.current < hp0 and sentry.state == "attack","AD-237 damage arrives only after the state changed to attack")

func _sentry_rotates(t) -> void:
	var r := _sentry_session()
	var s = r[0]
	var sentry = r[1]
	t.check(_until(s,sentry,"windup"),"AD-237 sentry windup reached for rotation test")
	var locked: Vector2 = sentry.intent.snapshot()["direction"]
	t.check(str(sentry.intent.snapshot()["geometry"]) == "line" and is_equal_approx(float(sentry.intent.snapshot()["range"]),300.0),"AD-237 intent is a line of beam_length")
	for i in int(sentry.tuning["telegraph_ticks"])-2:
		s.step()
	t.check(sentry.state == "windup" and sentry.intent.snapshot()["direction"].is_equal_approx(locked),"AD-237 beam direction stays locked during the telegraph")
	t.check(_until(s,sentry,"attack"),"AD-237 sentry reaches attack")
	var first: Vector2 = sentry.intent.snapshot()["direction"]
	s.step()
	var second: Vector2 = sentry.intent.snapshot()["direction"]
	var step_degrees := rad_to_deg(absf(first.angle_to(second)))
	t.check(not first.is_equal_approx(second),"AD-237 beam direction changes between active ticks")
	t.check(is_equal_approx(step_degrees,0.5),"AD-237 beam turns beam_sweep_degrees_per_tick (%f)" % step_degrees)
	t.check(first.angle_to(second) > 0.0,"AD-237 beam always sweeps the same (clockwise) way")

func _sentry_off_beam(t) -> void:
	var r := _sentry_session()
	var s = r[0]
	var sentry = r[1]
	var player = s.sim.actor
	t.check(_until(s,sentry,"windup"),"AD-237 windup reached for off-beam test")
	# The beam starts toward the player's old spot and sweeps away from the point directly below the sentry.
	player.position = sentry.target.position+Vector2(0,150)
	var hp0: float = player.health.current
	var guard := 0
	while sentry.state != "recover" and guard < 600:
		s.step()
		guard += 1
	t.check(sentry.state == "recover","AD-237 sentry finishes its sweep")
	t.check(player.health.current == hp0,"AD-237 a player off the beam line takes no damage")

func _sentry_static(t) -> void:
	var r := _sentry_session()
	var s = r[0]
	var sentry = r[1]
	var at: Vector2 = sentry.target.position
	var moved := false
	for i in 500:
		s.step()
		if sentry.target.position != at:
			moved = true
	t.check(not moved,"AD-237 rune_sentry never moves through a full attack cycle")

func _sentry_scenario(t) -> void:
	var s = Session.new(237,"rune_sentry",0)
	var kinds: Array = s.enemies.map(func(e): return e.kind)
	t.check(s.scenario == "rune_sentry" and kinds == ["rune_sentry"],"AD-237 scenario rune_sentry has exactly one rune_sentry (%s)" % str(kinds))
	t.check(str(s.data["scenarios"]["rune_sentry"]["name"]) == "Rune Sentry","AD-237 scenario is named Rune Sentry")

func _sentry_run() -> Array:
	var r := _sentry_session()
	var s = r[0]
	var sentry = r[1]
	for i in 170:
		s.step()
	return [s.sim.actor.health.current,sentry.intent.snapshot()["direction"] if sentry.intent != null else Vector2.ZERO,sentry.state]

func _sentry_deterministic(t) -> void:
	var a := _sentry_run()
	var b := _sentry_run()
	t.check(a == b and a[2] == "attack","AD-237 sentry run deterministic (hp, beam direction, state)")

func _mite_config(t) -> void:
	var s = Session.new(237,"empty",0)
	var cfg: Dictionary = s.data["enemies"].get("grave_mite",{})
	t.check(not cfg.is_empty() and Registry.validate_enemy(cfg).is_empty(),"AD-237 grave_mite config validates")
	t.check(int(cfg["telegraph_ticks"]) >= 12,"AD-237 grave_mite bite telegraph >= 12 ticks (%d)" % int(cfg["telegraph_ticks"]))
	var negatives: Array = []
	for channel in cfg["channel_resistances"]:
		if float(cfg["channel_resistances"][channel]) < 0.0:
			negatives.append(channel)
	t.check(negatives == ["fire"],"AD-237 grave_mite has exactly one weakness: fire (%s)" % str(negatives))
	t.check(float(cfg["damage"])*6.0 <= float(s.data["enemies"]["grave_hound"]["damage"])*2.0*1.25,"AD-237 whole pack bite damage stays near one grave_hound burst")

func _mite_validate(t) -> void:
	var script = Registry.SCRIPTS["swarm_chase"]
	t.check(script.validate({"id":"swarm_chase","weave_degrees":12}).is_empty(),"AD-237 valid swarm_chase accepted")
	t.check(not script.validate({"id":"swarm_chase","weave_degrees":-1}).is_empty(),"AD-237 negative weave_degrees rejected")
	t.check(not script.validate({"id":"swarm_chase","weave_degrees":"x"}).is_empty(),"AD-237 non-numeric weave_degrees rejected")

func _mite_scenario(t) -> void:
	var s = Session.new(237,"grave_mites",0)
	var kinds: Array = s.enemies.map(func(e): return e.kind)
	var live: Array = s.enemies.filter(func(e): return e.target.alive())
	t.check(kinds.size() == 6 and kinds.all(func(k): return k == "grave_mite") and live.size() == 6,"AD-237 scenario grave_mites spawns exactly 6 live grave_mite (%s)" % str(kinds))
	t.check(kinds.size() >= 5 and kinds.size() <= 6,"AD-237 swarm count within 5..6")
	t.check(str(s.data["scenarios"]["grave_mites"]["name"]) == "Grave Mites","AD-237 scenario is named Grave Mites")

func _mite_stats(t) -> void:
	var e = Session.new(237,"empty",0).data["enemies"]
	t.check(float(e["grave_mite"]["move_speed"]) > float(e["grave_hound"]["move_speed"]),"AD-237 mites are faster than grave_hound")
	t.check(float(e["grave_mite"]["hp"]) <= float(e["bone_thrall"]["hp"])*0.15,"AD-237 mite hp %s <= 15%% of bone_thrall" % e["grave_mite"]["hp"])

func _mite_bite_windup(t) -> void:
	var s = Session.new(237,"empty",0)
	var player = s.sim.actor
	var mite = s.spawn_enemy("grave_mite",player.position+Vector2(120,0))
	var telegraph := int(mite.tuning["telegraph_ticks"])
	var hp0: float = player.health.current
	var guard := 0
	while mite.state != "windup" and guard < 400:
		s.step()
		guard += 1
	t.check(mite.state == "windup","AD-237 mite reaches a bite windup")
	var windup_ticks := 0
	var damaged := false
	while mite.state == "windup" and windup_ticks < 100:
		if player.health.current < hp0:
			damaged = true
		windup_ticks += 1
		s.step()
	t.check(not damaged and windup_ticks == telegraph,"AD-237 no bite damage before telegraph_ticks elapse (%d vs %d)" % [windup_ticks,telegraph])
	guard = 0
	while player.health.current == hp0 and guard < 100:
		s.step()
		guard += 1
	t.check(player.health.current < hp0,"AD-237 the bite lands after the windup")

func _mite_burst_vs_bolt(t) -> void:
	var s = Session.new(237,"grave_mites",0)
	var mites: Array = s.enemies.duplicate()
	var bolt := 10.0
	mites[0].target.receive_damage(bolt,"neutral",0,1.0)
	var dead: int = mites.filter(func(m): return not m.target.alive()).size()
	t.check(dead <= 1,"AD-237 one bolt-sized neutral hit kills at most one mite (%d)" % dead)
	var s2 = Session.new(237,"grave_mites",0)
	for m in s2.enemies:
		m.target.receive_damage(15.0,"fire",0,1.0)
	var alive: int = s2.enemies.filter(func(m): return m.target.alive()).size()
	t.check(alive == 0,"AD-237 one fire burst on every mite kills the whole pack (%d alive)" % alive)

func _mite_run() -> Array:
	var s = Session.new(237,"grave_mites",0)
	for i in 120:
		s.step()
	return [s.sim.actor.health.current,s.enemies.map(func(e): return [e.target.position,e.state])]

func _mite_deterministic(t) -> void:
	t.check(_mite_run() == _mite_run(),"AD-237 mite swarm run deterministic")

func _censer_session() -> Array:
	var s = Session.new(237,"empty",0)
	var player = s.sim.actor
	var censer = s.spawn_enemy("ash_censer",player.position+Vector2(300,0))
	return [s,censer]

func _ward(censer):
	for b in censer.behaviours:
		if b.has_method("warded_ids"):
			return b
	return null

func _fire_taken(ally) -> float:
	var h: float = ally.target.health.current
	ally.target.receive_damage(10.0,"fire",0,1.0)
	var taken: float = h-ally.target.health.current
	ally.target.health.current = h
	return taken

func _wet(s, ally) -> void:
	ally.target.status.apply("wet",s.sim.clock.tick,s.sim.settings["statuses"]["wet"],{"team":0})

func _censer_config(t) -> void:
	var s = Session.new(237,"empty",0)
	var cfg: Dictionary = s.data["enemies"].get("ash_censer",{})
	t.check(not cfg.is_empty() and Registry.validate_enemy(cfg).is_empty(),"AD-237 ash_censer config validates")
	var negatives: Array = []
	for channel in cfg["channel_resistances"]:
		if float(cfg["channel_resistances"][channel]) < 0.0:
			negatives.append(channel)
	t.check(negatives == ["cold"],"AD-237 ash_censer has exactly one weakness: cold (%s)" % str(negatives))
	t.check(float(cfg["damage"]) == 0.0 and float(cfg["hp"]) <= float(s.data["enemies"]["bone_thrall"]["hp"]),"AD-237 ash_censer deals no damage and is no HP sponge")

func _censer_validate(t) -> void:
	var script = Registry.SCRIPTS["fire_ward"]
	t.check(script.validate({"id":"fire_ward","ward_radius":120,"ward_fire_resistance":0.75}).is_empty(),"AD-237 valid fire_ward accepted")
	t.check(not script.validate({"id":"fire_ward","ward_radius":0,"ward_fire_resistance":0.75}).is_empty(),"AD-237 zero ward_radius rejected")
	t.check(not script.validate({"id":"fire_ward","ward_radius":120,"ward_fire_resistance":1.5}).is_empty(),"AD-237 ward resistance above 1 rejected")
	t.check(not script.validate({"id":"fire_ward","ward_radius":120,"ward_fire_resistance":-0.1}).is_empty(),"AD-237 negative ward resistance rejected")
	t.check(not script.validate({"id":"fire_ward","ward_radius":120}).is_empty(),"AD-237 missing ward resistance rejected")

func _censer_scenario(t) -> void:
	var s = Session.new(237,"ash_censer",0)
	var kinds: Array = s.enemies.map(func(e): return e.kind)
	t.check(kinds.count("ash_censer") == 1 and kinds.count("bone_thrall") == 2 and kinds.count("grave_hound") == 1,"AD-237 scenario ash_censer: one censer, two thralls, one hound (%s)" % str(kinds))
	var censer = s.enemies[kinds.find("ash_censer")]
	for e in s.enemies:
		if e != censer:
			t.check(e.target.position.distance_to(censer.target.position) <= 120.0,"AD-237 scenario %s starts inside the ward" % e.kind)
	s.step()
	t.equal(_ward(censer).warded_ids().size(),3,"AD-237 ward is active on the scenario allies after one tick")

func _censer_ward(t) -> void:
	var a := _censer_session()
	var s = a[0]
	var censer = a[1]
	var thrall = s.spawn_enemy("bone_thrall",censer.target.position+Vector2(0,90))
	var before := _fire_taken(thrall)
	s.step()
	t.equal(_ward(censer).warded_ids(),[thrall.target.id],"AD-237 ally within 120 is warded")
	var after := _fire_taken(thrall)
	t.check(is_equal_approx(after,before*0.25),"AD-237 warded ally takes fire x0.25 (%s vs %s)" % [after,before])
	var neutral_before: float = thrall.target.health.current
	thrall.target.receive_damage(10.0,"neutral",0,1.0)
	t.check(is_equal_approx(neutral_before-thrall.target.health.current,before),"AD-237 ward does not touch other channels")
	t.check(not _ward(censer).warded_ids().has(censer.target.id) and not censer.target.health.resistances.has("fire"),"AD-237 the censer does not ward itself")

func _censer_range(t) -> void:
	var a := _censer_session()
	var s = a[0]
	var censer = a[1]
	var far = s.spawn_enemy("bone_thrall",censer.target.position+Vector2(0,121))
	var edge = s.spawn_enemy("bone_thrall",censer.target.position+Vector2(0,-120))
	var mover = s.spawn_enemy("bone_thrall",censer.target.position+Vector2(80,0))
	s.step()
	var warded: Array = _ward(censer).warded_ids()
	t.check(not warded.has(far.target.id) and not far.target.health.resistances.has("fire"),"AD-237 ally at distance > 120 is unwarded")
	t.check(warded.has(edge.target.id) and warded.has(mover.target.id),"AD-237 ally exactly 120 away is warded")
	mover.target.position = censer.target.position+Vector2(200,0)
	s.step()
	t.check(not _ward(censer).warded_ids().has(mover.target.id) and not mover.target.health.resistances.has("fire"),"AD-237 ally leaving range loses the ward the same tick")
	var boss = s.spawn_enemy("bone_thrall",censer.target.position+Vector2(0,60))
	boss.target.tags.append("boss")
	s.step()
	t.check(not _ward(censer).warded_ids().has(boss.target.id),"AD-237 bosses are never warded")

func _censer_wet(t) -> void:
	var a := _censer_session()
	var s = a[0]
	var censer = a[1]
	var thrall = s.spawn_enemy("bone_thrall",censer.target.position+Vector2(0,90))
	s.step()
	t.check(_ward(censer).warded_ids() == [thrall.target.id],"AD-237 ward on before wetting")
	_wet(s,thrall)
	s.step()
	t.check(_ward(censer).warded_ids().is_empty() and not thrall.target.health.resistances.has("fire"),"AD-237 wetting the ally removes the ward the same tick")
	var hp: float = thrall.target.health.current
	thrall.target.receive_damage(10.0,"water",0,1.0)
	t.check(thrall.target.health.current < hp,"AD-237 a water hit lands on the unwarded ally")
	t.check(is_equal_approx(_fire_taken(thrall),10.0),"AD-237 wet ally takes full fire damage")
	s.step()
	t.check(_ward(censer).warded_ids().is_empty(),"AD-237 a wet ally stays unwarded while Wet")
	var cold_before: float = censer.target.health.current
	censer.target.receive_damage(10.0,"cold",0,1.0)
	var neutral_taken := 10.0
	t.check(cold_before-censer.target.health.current > neutral_taken,"AD-237 the censer is weak to cold")

func _censer_death(t) -> void:
	var a := _censer_session()
	var s = a[0]
	var censer = a[1]
	var plain = s.spawn_enemy("bone_thrall",censer.target.position+Vector2(0,60))
	var weak = s.spawn_enemy("grave_hound",censer.target.position+Vector2(0,-60))
	var strong = s.spawn_enemy("bone_thrall",censer.target.position+Vector2(60,0))
	weak.target.health.resistances["fire"] = -0.5
	strong.target.health.resistances["fire"] = 0.9
	var plain_had: bool = plain.target.health.resistances.has("fire")
	var before := _fire_taken(weak)
	s.step()
	t.equal(_ward(censer).warded_ids().size(),2,"AD-237 weak and plain allies warded; the 0.9 resister is left alone")
	t.check(is_equal_approx(strong.target.health.resistances["fire"],0.9),"AD-237 an ally resisting fire more than the ward keeps its value")
	t.check(is_equal_approx(_fire_taken(weak),10.0*0.25),"AD-237 a fire-weak ally is warded to x0.25")
	censer.target.health.current = 0.0
	s.step()
	t.check(is_equal_approx(weak.target.health.resistances["fire"],-0.5),"AD-237 killing the censer restores the original -0.5 exactly")
	t.check(is_equal_approx(_fire_taken(weak),before),"AD-237 weak ally takes its original fire damage again")
	t.check(plain.target.health.resistances.has("fire") == plain_had and not plain.target.health.resistances.has("fire"),"AD-237 an ally with no fire entry gets none back (not zeroed)")
	t.check(is_equal_approx(strong.target.health.resistances["fire"],0.9),"AD-237 the strong resister is untouched after the censer dies")
	t.check(_ward(censer).warded_ids().is_empty(),"AD-237 no ally stays warded after the censer dies")

func _censer_run() -> Array:
	var s = Session.new(237,"ash_censer",0)
	for i in 120:
		s.step()
	return [s.sim.actor.health.current,s.enemies.map(func(e): return [e.target.position,e.state,e.target.health.resistances.duplicate()])]

func _censer_deterministic(t) -> void:
	t.check(_censer_run() == _censer_run(),"AD-237 censer run deterministic")
