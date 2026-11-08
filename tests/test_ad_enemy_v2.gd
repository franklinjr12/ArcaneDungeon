extends RefCounted
const Generator = preload("res://tests/ad_enemy_golden_generator.gd")
const Session = preload("res://combat/combat_session.gd")
const Registry = preload("res://combat/enemy_behaviours/registry.gd")

func run(t) -> void:
	t.with_frozen_balance(func(): _golden(t))
	_chase(t)
	_keep_distance(t)
	_melee_attack(t)
	_ranged_attack(t)
	_charge(t)
	_turret(t)
	_phase_walls(t)
	_summon(t)
	_shield_front(t)
	t.with_frozen_balance(func(): _explode_on_death(t)) # AD-175: fixed explode/kill values assume the frozen enemy balance
	t.with_frozen_balance(func(): _support_buff(t))
	_composed_determinism(t)
	_registry(t)
	_registry_v2(t)

func _golden(t) -> void:
	var fixture: Dictionary = t.fixture("ad_enemy_traces_v1.json")
	var cases: Dictionary = fixture["cases"]
	t.equal(cases.keys().size(),Generator.CASES.size(),"AD-136 golden case count")
	for case_name in cases:
		var expected: Array = cases[case_name]
		var actual: Array = Generator.run_case(case_name)
		var message := ""
		if actual.size() != expected.size():
			message = "length %d != %d" % [actual.size(),expected.size()]
		for i in mini(actual.size(),expected.size()):
			if actual[i] != expected[i]:
				message = "line %d: got '%s' expected '%s'" % [i,actual[i],expected[i]]
				break
		t.check(message == "","AD-136 golden %s %s" % [case_name,message])

## Session with one enemy of `kind`, config overridden by `overrides`, spawned at actor + offset.
func _spawn(kind: String, offset: Vector2, overrides: Dictionary = {}) -> Array:
	var s = Session.new(136,"empty",0)
	var config: Dictionary = s.data["enemies"][kind].duplicate(true)
	config.merge(overrides,true)
	s.data["enemies"]["probe"] = config
	var enemy = s.spawn_enemy("probe",s.sim.actor.position+offset)
	return [s,enemy]

func _steps(s, n: int) -> void:
	for i in n:
		s.step()

func _chase(t) -> void:
	var pair := _spawn("bone_thrall",Vector2(300,0),{"behaviours":[{"id":"chase"}]})
	var s = pair[0]
	var enemy = pair[1]
	var before: float = enemy.target.position.distance_to(s.sim.actor.position)
	_steps(s,20)
	var after: float = enemy.target.position.distance_to(s.sim.actor.position)
	t.check(after < before-20.0,"AD-136 chase approaches the player (%.1f -> %.1f)" % [before,after])
	t.check(enemy.intent == null and s.damage_events.is_empty(),"AD-136 chase alone never attacks")

func _keep_distance(t) -> void:
	var retreat := _spawn("fallen_adept",Vector2(150,0),{"behaviours":[{"id":"keep_distance","approach_margin":45,"retreat_margin":60}]})
	var before: float = retreat[1].target.position.distance_to(retreat[0].sim.actor.position)
	_steps(retreat[0],20)
	t.check(retreat[1].target.position.distance_to(retreat[0].sim.actor.position) > before+10.0,"AD-136 keep_distance retreats inside the band")
	var approach := _spawn("fallen_adept",Vector2(300,0),{"preferred_range":60,"behaviours":[{"id":"keep_distance","approach_margin":45,"retreat_margin":60}]})
	before = approach[1].target.position.distance_to(approach[0].sim.actor.position)
	_steps(approach[0],20)
	t.check(approach[1].target.position.distance_to(approach[0].sim.actor.position) < before-10.0,"AD-136 keep_distance approaches beyond the band")
	var hold := _spawn("grave_hound",Vector2(260,0),{"behaviours":[{"id":"keep_distance","approach_margin":35,"retreat_margin":50}]})
	var enemy = hold[1]
	var ctx := {"toward":hold[0].sim.actor.position-enemy.target.position,"distance":260.0,"sight":true,"player":hold[0].sim.actor}
	var lateral: Vector2 = enemy.behaviours[0].movement(enemy,hold[0],ctx)
	var expected_y := -1.0 if enemy.target.id % 2 == 0 else 1.0
	t.check(is_zero_approx(lateral.x) and is_equal_approx(lateral.y,expected_y*float(enemy.tuning["strafe_factor"])),
		"AD-136 keep_distance strafes sideways by id parity (%s)" % str(lateral))
	var start: Vector2 = enemy.target.position
	_steps(hold[0],10)
	var moved: Vector2 = enemy.target.position-start
	t.check(absf(moved.y) > absf(moved.x) and signf(moved.y) == expected_y,"AD-136 keep_distance strafe moves laterally in the band")

func _melee_attack(t) -> void:
	var pair := _spawn("bone_thrall",Vector2(60,0),{"behaviours":[{"id":"chase"},{"id":"melee_attack"}]})
	var s = pair[0]
	_steps(s,2+int(pair[1].tuning["telegraph_ticks"])+2)
	t.check(s.damage_events.size() == 1 and int(s.damage_events[0].get("source_id",-1)) == pair[1].target.id,
		"AD-136 melee_attack damages the player once after the telegraph (%s)" % str(s.damage_events))
	t.check(s.enemy_shots.is_empty(),"AD-136 melee_attack spawns no projectile")

func _ranged_attack(t) -> void:
	var pair := _spawn("fallen_adept",Vector2(300,0))
	var s = pair[0]
	_steps(s,2+int(pair[1].tuning["telegraph_ticks"])+2)
	t.check(s.enemy_shots.size() == 1 and int(s.enemy_shots[0]["source_id"]) == pair[1].target.id,"AD-136 ranged_attack spawns a projectile")
	var blind := _spawn("fallen_adept",Vector2(300,0))
	var windup := false
	for i in 60:
		blind[1].target.status.apply("blinded",blind[0].sim.clock.tick,blind[0].sim.settings["statuses"]["blinded"])
		blind[0].step()
		windup = windup or blind[1].state == "windup"
	t.check(not windup and blind[0].enemy_shots.is_empty(),"AD-136 ranged_attack: blinded blocks windup")

## Steps until the enemy enters `state` (max 20 ticks); returns whether it did.
func _until(s, enemy, state: String) -> bool:
	for i in 20:
		if enemy.state == state:
			return true
		s.step()
	return enemy.state == state

func _charge(t) -> void:
	var charge := {"id":"charge","charge_speed":360,"charge_ticks":30,"contact_padding":0}
	# Open-floor charge: direction locked at windup start, travel = charge_speed*ticks/tick_rate, no contact.
	var pair := _spawn("bone_thrall",Vector2(315,0),{"attack_range":400,"behaviours":[{"id":"turret"},charge]})
	var s = pair[0]
	var enemy = pair[1]
	t.check(_until(s,enemy,"windup"),"AD-136 charge enters windup")
	var intent: Dictionary = enemy.intent.snapshot()
	var start: Vector2 = enemy.target.position
	var travel := 360.0*30.0/float(s.sim.clock.tick_rate)
	t.check(intent["geometry"] == "line" and is_equal_approx(float(intent["range"]),travel) and intent["direction"].is_equal_approx(Vector2.LEFT),
		"AD-136 charge intent is a locked line (%s)" % str(intent))
	s.sim.actor.position = Vector2(start.x,start.y+300.0)
	var saw_attack := false
	for i in 200:
		s.step()
		saw_attack = saw_attack or enemy.state == "attack"
		if enemy.state == "recover":
			break
	t.check(saw_attack and enemy.state == "recover","AD-136 charge passes through the attack state")
	t.check(is_equal_approx(enemy.target.position.y,start.y) and absf((start.x-enemy.target.position.x)-travel) < 0.01,
		"AD-136 charge locks direction and travels ~%.1f (%s -> %s)" % [travel,str(start),str(enemy.target.position)])
	t.check(s.damage_events.is_empty(),"AD-136 charge that misses deals no damage")
	# Wall stop + single hit: east-bound charge through the player into the wall at x=890 (y 360..535).
	var wall: Rect2 = s.world.walls[2]
	var hit := _spawn("bone_thrall",Vector2(0,0),{"attack_range":300,"behaviours":[{"id":"turret"},{"id":"charge","charge_speed":600,"charge_ticks":30}]})
	var hs = hit[0]
	var foe = hit[1]
	foe.target.position = Vector2(700,450)
	hs.sim.actor.position = Vector2(800,450)
	_steps(hs,2+int(foe.tuning["telegraph_ticks"])+40)
	t.check(foe.target.position.x <= wall.position.x-foe.target.radius and foe.target.position.x > wall.position.x-foe.target.radius-6.0,"AD-136 charge stops at a wall (x=%.2f)" % foe.target.position.x)
	t.check(hs.damage_events.size() == 1 and int(hs.damage_events[0].get("source_id",-1)) == foe.target.id,"AD-136 charge hits the player once (%d events)" % hs.damage_events.size())

func _turret(t) -> void:
	var pair := _spawn("fallen_adept",Vector2(300,0),{"behaviours":[{"id":"turret"},{"id":"ranged_attack","shots":3,"spread_step_degrees":10}]})
	var s = pair[0]
	var enemy = pair[1]
	var start: Vector2 = enemy.target.position
	_steps(s,2+int(enemy.tuning["telegraph_ticks"])+2)
	t.check(enemy.target.position == start,"AD-136 turret never moves")
	t.equal(s.enemy_shots.size(),3,"AD-136 turret volley fires `shots` projectiles")
	var offsets: Array = []
	for shot in s.enemy_shots:
		offsets.append(snappedf(rad_to_deg(shot["direction"].angle_to(Vector2.LEFT)),0.001))
	offsets.sort()
	t.check(offsets == [-10.0,0.0,10.0],"AD-136 turret volley is symmetric around the aim (%s)" % str(offsets))
	var even := _spawn("fallen_adept",Vector2(300,0),{"behaviours":[{"id":"turret"},{"id":"ranged_attack","shots":2,"spread_step_degrees":8}]})
	_steps(even[0],2+int(even[1].tuning["telegraph_ticks"])+2)
	offsets = []
	for shot in even[0].enemy_shots:
		offsets.append(snappedf(rad_to_deg(shot["direction"].angle_to(Vector2.LEFT)),0.001))
	offsets.sort()
	t.check(offsets == [-4.0,4.0],"AD-136 turret even volley straddles the aim (%s)" % str(offsets))

func _phase_walls(t) -> void:
	var probe := _spawn("bone_thrall",Vector2.ZERO)
	var wall: Rect2 = probe[0].world.walls[0]
	var radius := float(probe[1].target.radius)
	var control := _spawn("bone_thrall",Vector2.ZERO,{"behaviours":[{"id":"chase"}]})
	var phase := _spawn("bone_thrall",Vector2.ZERO,{"behaviours":[{"id":"chase"},{"id":"phase_walls"}]})
	for pair in [control,phase]:
		pair[1].target.position = Vector2(700,270)
		pair[0].sim.actor.position = Vector2(450,270)
		_steps(pair[0],60)
	t.check(control[1].target.position.x >= wall.end.x+radius-0.01,"AD-136 phase_walls control chaser is blocked by the wall")
	t.check(phase[1].target.position.x < wall.end.x and is_equal_approx(phase[1].target.position.y,270.0),
		"AD-136 phase_walls passes through an arena wall (%s)" % str(phase[1].target.position))
	var bounds: Rect2 = phase[0].world.bounds
	var edge := _spawn("fallen_adept",Vector2(-85,0),{"behaviours":[{"id":"keep_distance","approach_margin":45,"retreat_margin":60},{"id":"phase_walls"}]})
	_steps(edge[0],120)
	var p: Vector2 = edge[1].target.position
	t.check(is_equal_approx(p.x,bounds.position.x+radius) and bounds.grow(-radius).has_point(p),"AD-136 phase_walls stays inside bounds (%s)" % str(p))
	# ignore_sight: attacks across a wall only with the flag.
	var shooters := []
	for modifier in [[],[{"id":"phase_walls","ignore_sight":true}],[{"id":"phase_walls"}]]:
		var behaviours: Array = [{"id":"turret"},{"id":"ranged_attack"}]
		behaviours.append_array(modifier)
		var shooter := _spawn("fallen_adept",Vector2.ZERO,{"behaviours":behaviours})
		shooter[1].target.position = Vector2(700,270)
		shooter[0].sim.actor.position = Vector2(450,270)
		_steps(shooter[0],2+int(shooter[1].tuning["telegraph_ticks"])+2)
		shooters.append(shooter[0].enemy_shots.size())
	t.equal(shooters,[0,1,0],"AD-136 phase_walls ignore_sight lets attacks cross walls only when set")

## Enemy lines for tick-by-tick comparison (id, kind, state, position, hp, summoner).
func _lines(s) -> Array:
	var lines: Array = []
	for enemy in s.enemies:
		lines.append("%d|%d|%s|%s|%.5f|%.5f|%.3f|%d" % [s.sim.clock.tick,enemy.target.id,enemy.kind,enemy.state,
			enemy.target.position.x,enemy.target.position.y,enemy.target.health.current,enemy.summoner_id])
	return lines

func _summon_cfg(extra: Dictionary = {}) -> Dictionary:
	var cfg := {"id":"summon","summon_kind":"bone_thrall","summon_cooldown_ticks":40,"count":2,"max_alive":3,"summon_radius":60}
	cfg.merge(extra,true)
	return cfg

func _summon(t) -> void:
	var run := func(extra: Dictionary) -> Array:
		var pair := _spawn("bone_thrall",Vector2(250,0),{"behaviours":[{"id":"turret"},_summon_cfg(extra)]})
		var s = pair[0]
		var sizes: Array = []
		var positions: Array = []
		for i in 200:
			s.step()
			sizes.append(s.enemies.size())
			if i == 60:
				for e in s.enemies:
					positions.append(e.target.position)
		return [s,pair[1],sizes,positions]
	var a: Array = run.call({})
	var s = a[0]
	var summoner = a[1]
	t.check(a[2][38] == 1 and a[2].has(3),"AD-136 summon spawns nothing before the cooldown, then spawns (%s)" % str(a[2].slice(36,50)))
	var first_at: int = a[2].find(3)
	var owned := 0
	for e in s.enemies:
		if e.summoner_id == summoner.target.id:
			owned += 1
	t.check(first_at >= 38 and first_at <= 45 and owned > 0 and a[2][first_at-1] == 1,"AD-136 summon spawns count=2 summons, owned by the summoner (first batch at idx %d)" % first_at)
	t.check(a[2].max() == 4 and s.summons_owned_by(summoner.target.id) == 3,"AD-136 summon respects max_alive (max enemies %d, owned %d)" % [a[2].max(),s.summons_owned_by(summoner.target.id)])
	t.check(s.pending_spawns.is_empty(),"AD-136 summon pending queue is flushed each tick")
	var b: Array = run.call({})
	t.check(a[3] == b[3] and _lines(a[0]) == _lines(b[0]),"AD-136 summon positions deterministic across identical runs")
	# Existing scenarios never queue spawns.
	var mixed := Session.new(136,"mixed",0)
	var queued := false
	for i in 120:
		mixed.step()
		queued = queued or not mixed.pending_spawns.is_empty()
	t.check(not queued,"AD-136 existing scenarios produce no pending spawns")

func _shield_front(t) -> void:
	var pair := _spawn("bone_thrall",Vector2(250,0),{"behaviours":[{"id":"turret"},{"id":"shield_front","front_damage_scale":0.5,"front_arc_degrees":60}]})
	var s = pair[0]
	var enemy = pair[1]
	var armor: float = float(s.sim.settings["combat"]["armor_scale"])
	s.step()
	t.check(enemy.heading.is_equal_approx(Vector2.LEFT) and is_equal_approx(enemy.target.damage_scale,0.5),"AD-136 shield_front: heading tracks the player and scale is set (%s, %f)" % [str(enemy.heading),enemy.target.damage_scale])
	var base := _spawn("bone_thrall",Vector2(250,0),{"behaviours":[{"id":"turret"}]})
	base[0].step()
	var plain: float = base[1].target.receive_damage(20.0,"physical",s.sim.actor.team,armor)
	var front: float = enemy.target.receive_damage(20.0,"physical",s.sim.actor.team,armor)
	t.check(plain > 0.0 and is_equal_approx(front,plain*0.5),"AD-136 shield_front halves frontal damage (%f vs %f)" % [front,plain])
	# Rear: enemy faces away from the player. Call the component directly (EnemyCombat re-aims every tick).
	enemy.heading = Vector2.RIGHT
	var ctx := {"toward":s.sim.actor.position-enemy.target.position}
	enemy.behaviours[1].tick(enemy,s,ctx)
	var rear: float = enemy.target.receive_damage(20.0,"physical",s.sim.actor.team,armor)
	t.check(enemy.target.damage_scale == 1.0 and is_equal_approx(rear,plain),"AD-136 shield_front does not reduce rear damage (%f vs %f)" % [rear,plain])
	# Frozen enemies keep their last scale.
	enemy.heading = Vector2.LEFT
	enemy.behaviours[1].tick(enemy,s,ctx)
	enemy.target.status.apply("frozen",s.sim.clock.tick,s.sim.settings["statuses"]["frozen"])
	s.sim.actor.position = enemy.target.position+Vector2(0,300)
	s.step()
	t.check(is_equal_approx(enemy.target.damage_scale,0.5),"AD-136 shield_front: frozen enemy keeps its last scale")

func _explode_on_death(t) -> void:
	var results: Array = []
	for offset in [Vector2(60,0),Vector2(400,0)]:
		var pair := _spawn("bone_thrall",offset,{"behaviours":[{"id":"turret"},{"id":"explode_on_death","explode_radius":90,"explode_damage":17,"explode_channel":"physical"}]})
		var s = pair[0]
		var hp_before: float = s.sim.actor.health.current
		s.step()
		pair[1].target.health.damage(1000.0,"physical",1.0)
		_steps(s,5)
		results.append([s.damage_events.size(),hp_before-s.sim.actor.health.current,s.feedback.filter(func(v): return v["label"] == "*").size()])
	t.check(results[0][0] == 1 and results[0][1] > 0.0,"AD-136 explode_on_death damages a nearby player once (%s)" % str(results[0]))
	t.check(results[1][0] == 0 and is_zero_approx(results[1][1]),"AD-136 explode_on_death spares a far player (%s)" % str(results[1]))
	t.check(results[0][2] == 1 and results[1][2] == 1,"AD-136 explode_on_death emits one feedback event either way")

func _support_buff(t) -> void:
	var s = Session.new(136,"empty",0)
	var thrall: Dictionary = s.data["enemies"]["bone_thrall"].duplicate(true)
	var support: Dictionary = thrall.duplicate(true)
	support["behaviours"] = [{"id":"turret"},{"id":"support_buff","buff_radius":150,"buff_damage_scale":0.5,"buff_speed_scale":1.5}]
	thrall["behaviours"] = [{"id":"turret"},{"id":"shield_front","front_damage_scale":0.5,"front_arc_degrees":60}]
	s.data["enemies"]["supporter"] = support
	s.data["enemies"]["ally"] = thrall
	var origin: Vector2 = s.sim.actor.position
	var ally = s.spawn_enemy("ally",origin+Vector2(300,0))
	var far = s.spawn_enemy("ally",origin+Vector2(300,300))
	var healer = s.spawn_enemy("supporter",origin+Vector2(400,0))
	s.step()
	t.check(is_equal_approx(ally.target.damage_scale,0.25) and is_equal_approx(ally.speed_scale,1.5),"AD-136 support_buff scales an ally in range, multiplied with shield_front (%f, %f)" % [ally.target.damage_scale,ally.speed_scale])
	t.check(is_equal_approx(far.target.damage_scale,0.5) and far.speed_scale == 1.0,"AD-136 support_buff leaves an out-of-range ally unbuffed (%f)" % far.target.damage_scale)
	t.check(healer.target.damage_scale == 1.0,"AD-136 support_buff does not buff its supporter")
	ally.target.position = origin+Vector2(300,400)
	s.step()
	t.check(is_equal_approx(ally.target.damage_scale,0.5) and ally.speed_scale == 1.0,"AD-136 support_buff clears when the ally leaves range")
	ally.target.position = origin+Vector2(300,0)
	s.step()
	healer.target.health.damage(1000.0,"physical",1.0)
	s.step()
	t.check(is_equal_approx(ally.target.damage_scale,0.5) and ally.speed_scale == 1.0,"AD-136 support_buff clears after the supporter dies (%f)" % ally.target.damage_scale)

func _composed_determinism(t) -> void:
	var runs: Array = []
	for n in 2:
		var s = Session.new(136,"empty",0)
		var base: Dictionary = s.data["enemies"]["bone_thrall"].duplicate(true)
		var boss_like: Dictionary = base.duplicate(true)
		boss_like["behaviours"] = [{"id":"chase"},{"id":"melee_attack"},_summon_cfg({"summon_cooldown_ticks":30,"max_alive":4}),
			{"id":"shield_front","front_damage_scale":0.5,"front_arc_degrees":90},{"id":"explode_on_death","explode_radius":80,"explode_damage":10}]
		var healer: Dictionary = base.duplicate(true)
		healer["behaviours"] = [{"id":"keep_distance","approach_margin":45,"retreat_margin":60},{"id":"support_buff","buff_radius":200,"buff_damage_scale":0.7,"buff_speed_scale":1.2}]
		s.data["enemies"]["mix_a"] = boss_like
		s.data["enemies"]["mix_b"] = healer
		var origin: Vector2 = s.sim.actor.position
		s.spawn_enemy("mix_a",origin+Vector2(400,0))
		s.spawn_enemy("mix_b",origin+Vector2(450,80))
		var lines: Array = []
		for i in 300:
			if i == 150:
				s.enemies[0].target.health.damage(1000.0,"physical",1.0)
			s.step()
			lines.append_array(_lines(s))
		runs.append(lines)
	t.check(runs[0] == runs[1] and runs[0].size() > 600,"AD-136 composed summon/shield/explode/support mix is deterministic over 300 ticks (%d lines)" % runs[0].size())

func _registry_v2(t) -> void:
	var base: Dictionary = Session.new(136,"empty",0).data["enemies"]["bone_thrall"]
	var cases := {
		"missing charge_speed": [[{"id":"chase"},{"id":"charge","charge_ticks":10}],"missing param 'charge_speed'"],
		"non-numeric charge_ticks": [[{"id":"chase"},{"id":"charge","charge_speed":300,"charge_ticks":"long"}],"must be numeric"],
		"fractional charge_ticks": [[{"id":"chase"},{"id":"charge","charge_speed":300,"charge_ticks":2.5}],"'charge_ticks' must be an integer >= 1"],
		"zero charge_speed": [[{"id":"chase"},{"id":"charge","charge_speed":0,"charge_ticks":5}],"'charge_speed' must be > 0"],
		"zero shots": [[{"id":"turret"},{"id":"ranged_attack","shots":0}],"'shots' must be an integer >= 1"],
		"non-numeric step": [[{"id":"turret"},{"id":"ranged_attack","spread_step_degrees":"wide"}],"must be numeric"],
		"turret plus chase": [[{"id":"turret"},{"id":"chase"}],"exactly one movement"],
		"summon missing kind": [[{"id":"chase"},{"id":"summon","summon_cooldown_ticks":10,"count":1,"max_alive":1,"summon_radius":50}],"missing param 'summon_kind'"],
		"summon zero count": [[{"id":"chase"},_summon_cfg({"count":0})],"'count' must be an integer >= 1"],
		"shield arc": [[{"id":"chase"},{"id":"shield_front","front_damage_scale":0.5,"front_arc_degrees":200}],"within 0..180"],
		"explode radius": [[{"id":"chase"},{"id":"explode_on_death","explode_radius":0,"explode_damage":5}],"'explode_radius' must be > 0"],
		"buff radius": [[{"id":"chase"},{"id":"support_buff","buff_radius":"near"}],"must be numeric"],
		"non-bool ignore_sight": [[{"id":"chase"},{"id":"phase_walls","ignore_sight":1}],"must be bool"],
	}
	for label in cases:
		var config := base.duplicate(true)
		config["behaviours"] = cases[label][0]
		t.check("|".join(Registry.validate_enemy(config)).contains(cases[label][1]),"AD-136 registry rejects %s" % label)
	var ok := base.duplicate(true)
	ok["behaviours"] = [{"id":"turret"},{"id":"charge","charge_speed":300,"charge_ticks":10},{"id":"phase_walls","ignore_sight":true}]
	t.check(Registry.validate_enemy(ok).is_empty(),"AD-136 registry accepts turret + charge + phase_walls %s" % str(Registry.validate_enemy(ok)))

func _registry(t) -> void:
	var tuning: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://combat/combat_tuning_v1.json"))
	for kind in ["bone_thrall","fallen_adept","grave_hound"]:
		var issues: Array = Registry.validate_enemy(tuning["enemies"][kind])
		t.check(issues.is_empty(),"AD-136 registry accepts %s %s" % [kind,str(issues)])
	var base: Dictionary = tuning["enemies"]["fallen_adept"]
	var unknown := base.duplicate(true)
	unknown["behaviours"] = [{"id":"teleport"},{"id":"chase"}]
	t.check("|".join(Registry.validate_enemy(unknown)).contains("unknown id 'teleport'"),"AD-136 registry rejects unknown id")
	t.equal(Registry.build(unknown["behaviours"]).size(),1,"AD-136 registry build skips unknown id without crashing")
	var missing := base.duplicate(true)
	missing["behaviours"] = [{"id":"keep_distance","approach_margin":45},{"id":"ranged_attack"}]
	t.check("|".join(Registry.validate_enemy(missing)).contains("missing param 'retreat_margin'"),"AD-136 registry rejects missing param")
	var typed := base.duplicate(true)
	typed["behaviours"] = [{"id":"keep_distance","approach_margin":"far","retreat_margin":60}]
	t.check("|".join(Registry.validate_enemy(typed)).contains("must be numeric"),"AD-136 registry rejects non-numeric param")
	var two := base.duplicate(true)
	two["behaviours"] = [{"id":"chase"},{"id":"keep_distance","approach_margin":45,"retreat_margin":60},{"id":"ranged_attack"}]
	t.check("|".join(Registry.validate_enemy(two)).contains("exactly one movement"),"AD-136 registry rejects two movement components")
	var attacks := base.duplicate(true)
	attacks["behaviours"] = [{"id":"chase"},{"id":"melee_attack"},{"id":"ranged_attack"}]
	t.check("|".join(Registry.validate_enemy(attacks)).contains("at most one attack"),"AD-136 registry rejects two attack components")
