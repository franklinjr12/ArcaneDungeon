extends RefCounted
const Generator = preload("res://tests/ad_enemy_golden_generator.gd")
const Session = preload("res://combat/combat_session.gd")
const Registry = preload("res://combat/enemy_behaviours/registry.gd")

func run(t) -> void:
	_golden(t)
	_chase(t)
	_keep_distance(t)
	_melee_attack(t)
	_ranged_attack(t)
	_registry(t)

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
