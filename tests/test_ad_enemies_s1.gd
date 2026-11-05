extends RefCounted
## AD-137 step 1: generic hooks for the Stage 1 enemies (turn rate, shield break, channel weakness, intangible_cycle).
const Session = preload("res://combat/combat_session.gd")
const Registry = preload("res://combat/enemy_behaviours/registry.gd")

func run(t) -> void:
	_turn_rate(t)
	_flank(t)
	_force_break(t)
	_weakness(t)
	_intangible(t)
	_puddle(t)
	_registry(t)
	_s1_configs(t)
	_s1_shieldbearer(t)
	_s1_spirit(t)
	_s1_bloat(t)

func _spawn(offset: Vector2, overrides: Dictionary) -> Array:
	var s = Session.new(137,"empty",0)
	var config: Dictionary = s.data["enemies"]["bone_thrall"].duplicate(true)
	config.merge(overrides,true)
	s.data["enemies"]["probe"] = config
	var enemy = s.spawn_enemy("probe",s.sim.actor.position+offset)
	return [s,enemy]

func _steps(s, n: int) -> void:
	for i in n:
		s.step()

func _armor(s) -> float:
	return float(s.sim.settings["combat"]["armor_scale"])

func _turret_with(extra: Array, turn: float = 0.0) -> Dictionary:
	return {"turn_rate_degrees_per_tick":turn,"behaviours":[{"id":"turret"}]+extra}

func _turn_rate(t) -> void:
	var pair := _spawn(Vector2(250,0),_turret_with([],5.0))
	var s = pair[0]
	var enemy = pair[1]
	s.step()
	t.check(enemy.heading.is_equal_approx(Vector2.LEFT),"AD-137 turn rate: facing the player initially")
	s.sim.actor.position = enemy.target.position+Vector2(250,0)
	s.step()
	t.check(absf(rad_to_deg(enemy.heading.angle_to(Vector2.RIGHT))) > 170.0,"AD-137 turn rate: heading does not snap (%s)" % str(enemy.heading))
	_steps(s,60)
	t.check(enemy.heading.is_equal_approx(Vector2.RIGHT),"AD-137 turn rate: heading converges (%s)" % str(enemy.heading))

func _flank(t) -> void:
	var shield := {"id":"shield_front","front_damage_scale":0.5,"front_arc_degrees":60}
	var pair := _spawn(Vector2(250,0),_turret_with([shield],5.0))
	var s = pair[0]
	var enemy = pair[1]
	s.step()
	var plain: float = _spawn(Vector2(250,0),_turret_with([]))[1].target.receive_damage(20.0,"physical",s.sim.actor.team,_armor(s))
	var front: float = enemy.target.receive_damage(20.0,"physical",s.sim.actor.team,_armor(s))
	t.check(plain > 0.0 and is_equal_approx(front,plain*0.5),"AD-137 flank: frontal hit is reduced (%f vs %f)" % [front,plain])
	s.sim.actor.position = enemy.target.position+Vector2(250,0)
	s.step()
	var back: float = enemy.target.receive_damage(20.0,"physical",s.sim.actor.team,_armor(s))
	t.check(is_equal_approx(back,plain),"AD-137 flank: hit from behind inside the turn window is full (%f vs %f)" % [back,plain])

func _force_break(t) -> void:
	var shield := {"id":"shield_front","front_damage_scale":0.5,"front_arc_degrees":60,"break_impulse_speed":100}
	var pair := _spawn(Vector2(250,0),_turret_with([shield]))
	var s = pair[0]
	var enemy = pair[1]
	s.step()
	t.check(not enemy.shield_broken and is_equal_approx(enemy.target.damage_scale,0.5),"AD-137 shield intact without knockback")
	enemy.target.impulse = Vector2(300,0)
	s.step()
	t.check(enemy.shield_broken and enemy.target.damage_scale == 1.0,"AD-137 Force knockback breaks the shield (%s, %f)" % [str(enemy.shield_broken),enemy.target.damage_scale])
	var none := _spawn(Vector2(250,0),_turret_with([{"id":"shield_front","front_damage_scale":0.5,"front_arc_degrees":60}]))
	none[1].target.impulse = Vector2(900,0)
	none[0].step()
	t.check(not none[1].shield_broken and is_equal_approx(none[1].target.damage_scale,0.5),"AD-137 shield without break_impulse_speed never breaks")

func _weakness(t) -> void:
	var weak := _spawn(Vector2(250,0),_turret_with([]))
	weak[1].target.health.resistances = {}
	var s = weak[0]
	var base: float = weak[1].target.receive_damage(20.0,"fire",s.sim.actor.team,_armor(s))
	var phys_base: float = _spawn(Vector2(250,0),_turret_with([]))[1].target.receive_damage(20.0,"physical",s.sim.actor.team,_armor(s))
	var pair := _spawn(Vector2(250,0),{"channel_resistances":{"fire":-0.5},"behaviours":[{"id":"turret"}]})
	var fire: float = pair[1].target.receive_damage(20.0,"fire",s.sim.actor.team,_armor(s))
	var phys: float = pair[1].target.receive_damage(20.0,"physical",s.sim.actor.team,_armor(s))
	t.check(base > 0.0 and is_equal_approx(fire,base*1.5),"AD-137 fire weakness deals 1.5x (%f vs %f)" % [fire,base])
	t.check(is_equal_approx(phys,phys_base),"AD-137 fire weakness leaves physical damage unchanged")

func _intangible(t) -> void:
	var cycle := {"id":"intangible_cycle","period_ticks":10,"warn_ticks":2,"intangible_ticks":3,"intangible_damage_scale":0.0}
	var pair := _spawn(Vector2(250,0),_turret_with([cycle]))
	var s = pair[0]
	var enemy = pair[1]
	var armor := _armor(s)
	for i in 20:
		s.step()
		var phase := i%10
		var warn := phase < 2
		var ghost := phase >= 2 and phase < 5
		t.check(enemy.intangible_warning == warn and enemy.intangible == ghost,"AD-137 intangible_cycle flags at tick %d" % i)
		var dealt: float = enemy.target.receive_damage(1.0,"physical",s.sim.actor.team,armor)
		t.check((dealt == 0.0) == ghost,"AD-137 intangible_cycle damage at tick %d (%f)" % [i,dealt])

func _registry(t) -> void:
	var good := {"id":"intangible_cycle","period_ticks":10,"warn_ticks":2,"intangible_ticks":3}
	t.check(Registry.SCRIPTS["intangible_cycle"].validate(good).is_empty(),"AD-137 valid intangible_cycle accepted")
	var bad: Array = [{"period_ticks":10,"warn_ticks":2},
		{"period_ticks":10,"warn_ticks":5,"intangible_ticks":5},
		{"period_ticks":10,"warn_ticks":0,"intangible_ticks":3},
		{"period_ticks":10,"warn_ticks":2,"intangible_ticks":3,"intangible_damage_scale":2.0},
		{"period_ticks":"x","warn_ticks":2,"intangible_ticks":3}]
	for entry in bad:
		t.check(not Registry.SCRIPTS["intangible_cycle"].validate(entry).is_empty(),"AD-137 bad intangible_cycle rejected %s" % str(entry))
	t.check(not Registry.SCRIPTS["shield_front"].validate({"front_damage_scale":0.5,"front_arc_degrees":60,"break_impulse_speed":-1}).is_empty(),"AD-137 negative break_impulse_speed rejected")

const PUDDLE := {"id":"death_puddle","puddle_radius":60,"puddle_duration_ticks":40,"puddle_interval_ticks":10}

func _puddle_run(t, check: bool) -> Array:
	var pair := _spawn(Vector2(300,0),{"behaviours":[{"id":"turret"},PUDDLE]})
	var s = pair[0]
	var enemy = pair[1]
	var inside = s.spawn_enemy("probe",enemy.target.position+Vector2(0,30))
	var outside = s.spawn_enemy("probe",enemy.target.position+Vector2(-150,0))
	var death_at: Vector2 = enemy.target.position
	enemy.target.receive_damage(100000.0,"physical",s.sim.actor.team,0.0)
	s.step()
	var log: Array = []
	if check:
		t.check(s.hazards.size() == 1 and s.hazards[0]["position"] == death_at,"AD-137 puddle: exactly one hazard at the death position")
		t.check(s.snapshot()["hazards"].size() == 1,"AD-137 puddle: hazards exposed in snapshot")
	for i in 45:
		s.step()
		var tick: int = s.sim.clock.tick
		log.append([s.hazards.size(),inside.target.status.has("wet",tick),outside.target.status.has("wet",tick),s.sim.actor.status.has("wet",tick)])
		if check and i == 11:
			t.check(inside.target.status.has("wet",tick),"AD-137 puddle: enemy inside becomes Wet")
			t.check(not outside.target.status.has("wet",tick),"AD-137 puddle: enemy outside stays dry")
	return [s,log,inside,enemy]

func _puddle(t) -> void:
	var run := _puddle_run(t,true)
	t.check(run[0].hazards.is_empty(),"AD-137 puddle: hazard gone after duration_ticks")
	var player_pair := _spawn(Vector2(300,0),{"behaviours":[{"id":"turret"},PUDDLE]})
	var s = player_pair[0]
	s.sim.actor.position = player_pair[1].target.position+Vector2(20,0)
	player_pair[1].target.receive_damage(100000.0,"physical",s.sim.actor.team,0.0)
	_steps(s,3)
	t.check(s.sim.actor.status.has("wet",s.sim.clock.tick),"AD-137 puddle: player inside becomes Wet")
	t.check(run[1] == _puddle_run(t,false)[1],"AD-137 puddle: deterministic across runs")
	var bad: Array = [{"puddle_duration_ticks":40,"puddle_interval_ticks":10},
		{"puddle_radius":0,"puddle_duration_ticks":40,"puddle_interval_ticks":10},
		{"puddle_radius":60,"puddle_duration_ticks":0,"puddle_interval_ticks":10},
		{"puddle_radius":60,"puddle_duration_ticks":40,"puddle_interval_ticks":-1},
		{"puddle_radius":60,"puddle_duration_ticks":40,"puddle_interval_ticks":10,"puddle_status":3}]
	for entry in bad:
		t.check(not Registry.SCRIPTS["death_puddle"].validate(entry).is_empty(),"AD-137 bad death_puddle rejected %s" % str(entry))
	t.check(Registry.SCRIPTS["death_puddle"].validate(PUDDLE).is_empty(),"AD-137 valid death_puddle accepted")

# --- Stage 1 archetypes from tuning (AD-137 step 3) ---
const S1_KINDS := ["ossuary_shieldbearer","wailing_spirit","corpse_bloat"]

func _real(kind: String, offset: Vector2, player_at = null) -> Array:
	var s = Session.new(137,"empty",0)
	if player_at != null:
		s.sim.actor.position = player_at
	return [s,s.spawn_enemy(kind,s.sim.actor.position+offset)]

func _hit(s, enemy, channel: String = "physical") -> float:
	return enemy.target.receive_damage(20.0,channel,s.sim.actor.team,_armor(s))

func _s1_configs(t) -> void:
	var s = Session.new(137,"empty",0)
	for kind in S1_KINDS:
		t.check(s.data["enemies"].has(kind) and Registry.validate_enemy(s.data["enemies"][kind]).is_empty(),"AD-137 %s config validates (%s)" % [kind,str(Registry.validate_enemy(s.data["enemies"].get(kind,{})))])
	var rooms = JSON.parse_string(FileAccess.get_file_as_string("res://world/data/rooms_ruins_v1.json"))
	var used := {}
	for room in rooms["room_templates"].values():
		for wave in room["waves"]:
			for entry in wave["enemies"]:
				used[entry[0]] = true
				t.check(s.data["enemies"].has(entry[0]),"AD-137 room wave kind %s exists in tuning" % entry[0])
	for kind in S1_KINDS:
		t.check(used.has(kind),"AD-137 %s appears in Ruins waves" % kind)

func _s1_shieldbearer(t) -> void:
	var pair := _real("ossuary_shieldbearer",Vector2(400,0))
	var s = pair[0]
	var enemy = pair[1]
	s.step()
	var plain: float = _real("bone_thrall",Vector2(400,0))[1].target.receive_damage(20.0,"physical",s.sim.actor.team,_armor(s))
	var front := _hit(s,enemy)
	t.check(front > 0.0 and is_equal_approx(front,plain*0.2),"AD-137 shieldbearer frontal damage x0.2 (%f vs %f)" % [front,plain])
	# Flank: the player jumps behind it faster than 2.5 deg/tick can follow.
	s.sim.actor.position = enemy.target.position+Vector2(300,0)
	s.step()
	t.check(is_equal_approx(_hit(s,enemy),plain),"AD-137 shieldbearer flanked: full damage")
	# Force counter: knockback at/above break_impulse_speed from the front.
	var forced := _real("ossuary_shieldbearer",Vector2(400,0))
	forced[0].step()
	forced[1].target.impulse = Vector2(420,0)  # one Force rune hit (knockback_force in magic_balance_v1.json)
	forced[0].step()
	t.check(forced[1].shield_broken and is_equal_approx(_hit(forced[0],forced[1]),plain),"AD-137 shieldbearer Force knockback: full damage")

func _s1_spirit(t) -> void:
	var s0 = Session.new(137,"empty",0)
	var wall: Rect2 = s0.world.walls[0]
	var ghost := _real("wailing_spirit",Vector2.ZERO,Vector2(300,270))
	ghost[1].target.position = Vector2(700,270)
	var cs = Session.new(137,"empty",0)
	cs.sim.actor.position = Vector2(300,270)
	var stripped: Array = cs.data["enemies"]["wailing_spirit"]["behaviours"].filter(func(b): return b["id"] != "phase_walls")
	cs.data["enemies"]["wailing_spirit"]["behaviours"] = stripped
	var control = cs.spawn_enemy("wailing_spirit",Vector2(700,270))
	_steps(ghost[0],150)
	_steps(cs,150)
	t.check(is_equal_approx(ghost[1].target.position.y,270.0) and absf(control.target.position.y-270.0) > 1.0,"AD-137 spirit control without phase_walls detours around the wall (y=%.1f)" % control.target.position.y)
	t.check(ghost[1].target.position.x < wall.end.x,"AD-137 spirit passes through the wall (x=%.1f, wall end %.1f)" % [ghost[1].target.position.x,wall.end.x])
	# Damage: fire weakness x1.5 (outside intangible), 0 while intangible.
	var pair := _real("wailing_spirit",Vector2(400,0))
	var s = pair[0]
	var enemy = pair[1]
	s.step()
	var fire := _hit(s,enemy,"fire")
	var phys := _hit(s,enemy)
	t.check(phys > 0.0 and is_equal_approx(fire,phys*1.5),"AD-137 spirit fire is 1.5x physical (%f vs %f)" % [fire,phys])
	var saw_warning := false
	for i in 200:
		s.step()
		saw_warning = saw_warning or enemy.intangible_warning
		if enemy.intangible:
			break
	t.check(saw_warning and enemy.intangible,"AD-137 spirit warns before turning intangible")
	t.check(_hit(s,enemy) == 0.0 and _hit(s,enemy,"fire") == 0.0,"AD-137 spirit takes 0 damage while intangible")

func _s1_bloat(t) -> void:
	var close := _real("corpse_bloat",Vector2(60,0))
	var radius := float(close[1].tuning["behaviours"][2]["explode_radius"])
	var before: float = close[0].sim.actor.health.current
	close[1].target.receive_damage(100000.0,"physical",close[0].sim.actor.team,0.0)
	_steps(close[0],2)
	t.check(close[0].sim.actor.health.current < before,"AD-137 bloat killed point-blank damages the player")
	var far := _real("corpse_bloat",Vector2(radius+110.0,0))
	before = far[0].sim.actor.health.current
	far[1].target.receive_damage(100000.0,"physical",far[0].sim.actor.team,0.0)
	_steps(far[0],2)
	t.check(is_equal_approx(far[0].sim.actor.health.current,before),"AD-137 bloat killed at range leaves the player unharmed")
	var lab := _real("corpse_bloat",Vector2(450,0))
	var victim = lab[0].spawn_enemy("bone_thrall",lab[1].target.position+Vector2(0,40))
	lab[1].target.receive_damage(100000.0,"physical",lab[0].sim.actor.team,0.0)
	_steps(lab[0],4)
	t.check(lab[0].hazards.size() == 1 and victim.target.status.has("wet",lab[0].sim.clock.tick),"AD-137 bloat puddle Wets an enemy standing in it")
