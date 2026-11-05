extends RefCounted
## AD-139 step 1: Cistern slime (split_on_death) and Drowned acolyte (zone_cast).
const Session = preload("res://combat/combat_session.gd")
const Registry = preload("res://combat/enemy_behaviours/registry.gd")
const SPLIT := {"id":"split_on_death","split_kind":"cistern_slimelet","count":2,"split_radius":30}
const ZONE := {"id":"zone_cast","zone_radius":80,"zone_duration_ticks":240,"zone_interval_ticks":15}

func run(t) -> void:
	_configs(t)
	_split(t)
	_split_deterministic(t)
	_validate(t)
	_zone(t)

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
