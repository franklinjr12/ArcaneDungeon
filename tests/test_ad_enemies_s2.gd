extends RefCounted
## AD-139 step 1: Cistern slime (split_on_death) and Drowned acolyte (zone_cast).
const Session = preload("res://combat/combat_session.gd")
const Registry = preload("res://combat/enemy_behaviours/registry.gd")
const SPLIT := {"id":"split_on_death","split_kind":"cistern_slimelet","count":2,"split_radius":30}
const POOL := {"kind":"deep","rect":[200,770,600,100]}
const ZONE := {"id":"zone_cast","zone_radius":80,"zone_duration_ticks":240,"zone_interval_ticks":15}

func run(t) -> void:
	_configs(t)
	_split(t)
	_split_deterministic(t)
	_validate(t)
	_zone(t)
	_eel_config(t)
	_eel_lurk(t)
	_eel_lunge(t)
	_eel_no_water(t)
	_eel_validate(t)
	_eel_deterministic(t)

func _kill(s, enemy) -> void:
	enemy.target.receive_damage(100000.0,"physical",s.sim.actor.team,0.0)

func _slimelets(s) -> Array:
	return s.enemies.filter(func(e): return e.kind == "cistern_slimelet" and e.target.alive())

func _configs(t) -> void:
	var s = Session.new(139,"empty",0)
	for kind in ["cistern_slime","cistern_slimelet","drowned_acolyte"]:
		t.check(s.data["enemies"].has(kind) and Registry.validate_enemy(s.data["enemies"][kind]).is_empty(),"AD-139 %s config validates" % kind)
	var ids: Array = []
	for entry in s.data["enemies"]["cistern_slimelet"]["behaviours"]:
		ids.append(entry["id"])
	t.check(not ids.has("split_on_death"),"AD-139 slimelet does not split (no recursion)")
	t.check(int(s.data["enemies"]["drowned_acolyte"]["telegraph_ticks"]) >= 40,"AD-139 acolyte telegraph >= 40 ticks")

func _split_run() -> Array:
	var s = Session.new(139,"empty",0)
	var slime = s.spawn_enemy("cistern_slime",s.sim.actor.position+Vector2(400,0))
	var at: Vector2 = slime.target.position
	_kill(s,slime)
	s.step()
	return [s,at]

func _split(t) -> void:
	var run := _split_run()
	var s = run[0]
	var at: Vector2 = run[1]
	var kids := _slimelets(s)
	t.check(kids.size() == 2,"AD-139 slime splits into exactly 2 slimelets (%d)" % kids.size())
	t.check(s.state != "cleared","AD-139 room does not clear between slime death and its spawns")
	if kids.size() == 2:
		for i in 2:
			var expected: Vector2 = at+Vector2.RIGHT.rotated(TAU*float(i)/2.0)*30.0
			t.check(kids[i].target.position.distance_to(expected) < 2.0,"AD-139 slimelet %d on the split ring (%s vs %s)" % [i,str(kids[i].target.position),str(expected)])
		for kid in kids:
			_kill(s,kid)
		for i in 3:
			s.step()
		t.check(_slimelets(s).is_empty() and s.alive_enemies() == 0,"AD-139 killing slimelets spawns nothing more")
		t.check(s.state == "cleared","AD-139 room clears after slimelets die")

func _split_deterministic(t) -> void:
	var a := _split_run()
	var b := _split_run()
	var pa: Array = _slimelets(a[0]).map(func(e): return e.target.position)
	var pb: Array = _slimelets(b[0]).map(func(e): return e.target.position)
	t.check(pa == pb and pa.size() == 2,"AD-139 split deterministic across runs")

func _validate(t) -> void:
	var split = Registry.SCRIPTS["split_on_death"]
	var zone = Registry.SCRIPTS["zone_cast"]
	t.check(split.validate(SPLIT).is_empty(),"AD-139 valid split_on_death accepted")
	t.check(zone.validate(ZONE).is_empty(),"AD-139 valid zone_cast accepted")
	var bad_split: Array = [{"count":2,"split_radius":30},{"split_kind":"","count":2,"split_radius":30},
		{"split_kind":"x","count":0,"split_radius":30},{"split_kind":"x","count":1.5,"split_radius":30},
		{"split_kind":"x","count":2,"split_radius":0},{"split_kind":"x","count":2}]
	for entry in bad_split:
		t.check(not split.validate(entry).is_empty(),"AD-139 bad split_on_death rejected %s" % str(entry))
	var bad_zone: Array = [{"zone_duration_ticks":240,"zone_interval_ticks":15},{"zone_radius":0,"zone_duration_ticks":240,"zone_interval_ticks":15},
		{"zone_radius":80,"zone_duration_ticks":0,"zone_interval_ticks":15},{"zone_radius":80,"zone_duration_ticks":240,"zone_interval_ticks":-1},
		{"zone_radius":80,"zone_duration_ticks":240.5,"zone_interval_ticks":15},{"zone_radius":80,"zone_duration_ticks":240,"zone_interval_ticks":15,"zone_status":3}]
	for entry in bad_zone:
		t.check(not zone.validate(entry).is_empty(),"AD-139 bad zone_cast rejected %s" % str(entry))

func _zone(t) -> void:
	var s = Session.new(139,"empty",0)
	var player = s.sim.actor
	var acolyte = s.spawn_enemy("drowned_acolyte",player.position+Vector2(250,0))
	var locked := Vector2.ZERO
	var moved := false
	var guard := 0
	while acolyte.state != "windup" and guard < 200:
		s.step()
		guard += 1
	t.check(acolyte.state == "windup","AD-139 acolyte starts a cast within range")
	locked = acolyte.intent.snapshot()["target"]
	t.check(locked.distance_to(player.position) < 0.01,"AD-139 intent locks the player position at windup start")
	player.position += Vector2(200,0)
	guard = 0
	while s.hazards.is_empty() and guard < 200:
		s.step()
		guard += 1
	t.check(s.hazards.size() == 1,"AD-139 acolyte cast adds one hazard")
	if s.hazards.size() == 1:
		var h: Dictionary = s.hazards[0]
		t.check(h["position"] == locked and h["status"] == "wet" and float(h["radius"]) == 80.0,"AD-139 zone centred on the locked point")
		t.check(not player.status.has("wet",s.sim.clock.tick) or player.position.distance_to(locked) <= 80.0+player.radius,"AD-139 moved player outside the zone is not Wet")
		player.position = locked
		for i in 20:
			s.step()
		t.check(player.status.has("wet",s.sim.clock.tick),"AD-139 player standing in the zone becomes Wet")

## Eel at (500,820) inside a deep pool whose land edge is y=770; the player starts on land far outside lunge range.
func _eel_session(with_water: bool = true) -> Array:
	var s = Session.new(139,"empty",0)
	var eel = s.spawn_enemy("deep_eel",Vector2(500,820))
	if with_water:
		s.set_water([POOL])
	s.sim.actor.position = Vector2(500,500)
	return [s,eel]

func _eel_config(t) -> void:
	var s = Session.new(139,"empty",0)
	var cfg: Dictionary = s.data["enemies"]["deep_eel"]
	t.check(Registry.validate_enemy(cfg).is_empty(),"AD-139 deep_eel config validates")
	var rate: float = float(s.sim.clock.tick_rate)
	t.check(float(cfg["telegraph_ticks"])/rate >= 0.5,"AD-139 eel ripple telegraph >= 0.5 s (%d ticks at %d Hz)" % [int(cfg["telegraph_ticks"]),int(rate)])

func _eel_lurk(t) -> void:
	var run := _eel_session()
	var s = run[0]
	var eel = run[1]
	var always_in := true
	for i in 240:
		s.step()
		always_in = always_in and s.water.in_water(eel.target.position)
	t.check(always_in,"AD-139 chasing eel never leaves water")
	t.check(eel.state == "chase" and absf(eel.target.position.x-500.0) < 1.0 and eel.target.position.y < 780.0,"AD-139 eel drifts to the pool edge nearest the player (%s)" % str(eel.target.position))

func _eel_lunge(t) -> void:
	var run := _eel_session()
	var s = run[0]
	var eel = run[1]
	for i in 240:
		s.step()
	var player = s.sim.actor
	player.position = Vector2(500,700)
	var guard := 0
	while eel.state != "windup" and guard < 20:
		s.step()
		guard += 1
	t.check(eel.state == "windup","AD-139 eel winds up with the player in range")
	var spot: Vector2 = eel.target.position
	var intent: Dictionary = eel.intent.snapshot()
	t.check(intent.get("telegraph") == "ripple" and intent.get("submerged_origin") == spot,"AD-139 eel intent carries ripple telegraph")
	var still := true
	var windup_ticks := 0
	while eel.state == "windup" and windup_ticks < 200:
		still = still and eel.target.position == spot
		s.step()
		windup_ticks += 1
	t.check(still and windup_ticks >= int(s.data["enemies"]["deep_eel"]["telegraph_ticks"]),"AD-139 eel stays put through the telegraph (%d ticks)" % windup_ticks)
	var hp_before: float = player.health.current
	var left_water := false
	var hits := 0
	var last_hp := hp_before
	guard = 0
	while eel.state in ["attack","recover"] and guard < 200:
		left_water = left_water or not s.water.in_water(eel.target.position)
		s.step()
		guard += 1
		if player.health.current < last_hp:
			hits += 1
			last_hp = player.health.current
	t.check(left_water,"AD-139 eel lunges out of the water")
	t.check(hits == 1 and player.health.current < hp_before,"AD-139 lunge damages the player exactly once (%d hits)" % hits)
	player.position = Vector2(500,300)
	for i in 120:
		s.step()
	t.check(s.water.in_water(eel.target.position),"AD-139 eel returns to water after the lunge")

func _eel_no_water(t) -> void:
	var run := _eel_session(false)
	var s = run[0]
	var eel = run[1]
	s.sim.actor.position = Vector2(500,760)
	var spot: Vector2 = eel.target.position
	var attacked := false
	for i in 200:
		s.step()
		attacked = attacked or eel.state in ["windup","attack"]
	t.check(not attacked and eel.target.position == spot,"AD-139 eel without water never attacks or moves")

func _eel_validate(t) -> void:
	var lunge = Registry.SCRIPTS["lunge"]
	t.check(lunge.validate({"charge_speed":520,"charge_ticks":14,"contact_padding":4}).is_empty(),"AD-139 valid lunge accepted")
	for entry in [{"charge_ticks":14},{"charge_speed":520},{"charge_speed":0,"charge_ticks":14},{"charge_speed":520,"charge_ticks":0},
			{"charge_speed":520,"charge_ticks":14,"contact_padding":"x"},{"charge_speed":520,"charge_ticks":14,"contact_padding":-1}]:
		t.check(not lunge.validate(entry).is_empty(),"AD-139 bad lunge rejected %s" % str(entry))

func _eel_trace() -> Array:
	var run := _eel_session()
	var s = run[0]
	var trace: Array = []
	for i in 400:
		if i == 150:
			s.sim.actor.position = Vector2(500,700)
		if i == 300:
			s.sim.actor.position = Vector2(500,300)
		s.step()
		trace.append(run[1].target.position)
	return trace

func _eel_deterministic(t) -> void:
	var a := _eel_trace()
	var b := _eel_trace()
	t.check(a == b and a.size() == 400,"AD-139 eel trace deterministic across runs")
