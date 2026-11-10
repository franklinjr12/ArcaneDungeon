extends RefCounted
const Session = preload("res://combat/combat_session.gd")

func run(t) -> void:
	_live_reach(t)
	_walking_is_not_enough(t)
	_wall_stop(t)
	_no_lunge_instant(t)
	run_bursts(t)

func _spawn(kind: String, offset: Vector2, overrides: Dictionary = {}) -> Array:
	var s = Session.new(136,"empty",0)
	var config: Dictionary = s.data["enemies"][kind].duplicate(true)
	config.merge(overrides,true)
	s.data["enemies"]["probe"] = config
	return [s,s.spawn_enemy("probe",s.sim.actor.position+offset)]

func _live_reach(t) -> void:
	var s = Session.new(136,"empty",0)
	var found := 0
	for kind in s.data["enemies"]:
		var cfg: Dictionary = s.data["enemies"][kind]
		for b in cfg.get("behaviours",[]):
			if b["id"] != "melee_attack":
				continue
			found += 1
			var reach := float(cfg["attack_range"])+float(b.get("lunge_distance",0.0))
			t.check(reach >= 120.0 and reach <= 150.0,"AD-196 %s melee reach %s in 120..150" % [kind,reach])
			t.check(int(cfg["telegraph_ticks"]) >= 30,"AD-196 %s melee telegraph >= 30 ticks" % kind)
			t.check(int(b.get("lunge_ticks",0)) >= 1,"AD-196 %s has lunge_ticks" % kind)
	t.check(found >= 6,"AD-196 found the melee enemies (%d)" % found)
	var pair := _spawn("bone_thrall",Vector2(70,0))
	for i in 3:
		pair[0].step()
	var lunge: Dictionary = {}
	for b in pair[1].tuning["behaviours"]:
		if b["id"] == "melee_attack":
			lunge = b
	t.check(pair[1].state == "windup" and is_equal_approx(float(pair[1].intent.snapshot()["range"]),float(pair[1].tuning["attack_range"])+float(lunge["lunge_distance"])),
		"AD-196 melee intent range equals the true reach (%s)" % str(pair[1].intent.snapshot()["range"]))

## Windup is 31 ticks and the player outwalks the 8-tick lunge (4.25 vs 8 px/tick), so walking only fails to avoid it when started late in the windup.
func _walking_is_not_enough(t) -> void:
	var pair := _spawn("bone_thrall",Vector2(70,0))
	var s = pair[0]
	var hits := 0
	var windup_tick := -1
	for i in 120:
		if windup_tick < 0 and pair[1].state == "windup":
			windup_tick = i
		if windup_tick >= 0 and i >= windup_tick+22:
			s.issue({"move":Vector2.LEFT,"aim":Vector2.LEFT})
		s.step()
	hits = s.damage_events.size()
	t.check(windup_tick >= 0,"AD-196 thrall winds up at distance 70")
	t.check(hits == 1,"AD-196 walking away does not avoid the lunge and it hits exactly once (%d)" % hits)

func _wall_stop(t) -> void:
	var pair := _spawn("bone_thrall",Vector2.ZERO)
	var s = pair[0]
	var enemy = pair[1]
	var wall: Rect2 = s.world.walls[0]
	var radius := float(enemy.target.radius)
	enemy.target.position = Vector2(wall.end.x+radius+1.0,270.0)
	s.sim.actor.position = Vector2(wall.position.x-60.0,270.0)
	var attacker = enemy._attacker
	enemy.state_tick = 0
	for i in 8:
		enemy.state_tick += 1
		attacker.active_tick(enemy,s,{})
	t.check(enemy.target.position.x >= wall.end.x+radius-0.01,"AD-196 lunge stops at a wall (%s)" % str(enemy.target.position))

func _no_lunge_instant(t) -> void:
	var pair := _spawn("bone_thrall",Vector2(60,0),{"behaviours":[{"id":"chase"},{"id":"melee_attack"}]})
	var s = pair[0]
	var attacked := false
	for i in 2+int(pair[1].tuning["telegraph_ticks"])+4:
		s.step()
		attacked = attacked or pair[1].state == "attack"
	t.check(not attacked and s.damage_events.size() == 1,"AD-196 melee_attack without lunge params stays instant")

const BEFORE_SPEEDS := {"fallen_adept":310.0,"grave_hound":340.0,"wailing_spirit":260.0}

func run_bursts(t) -> void:
	var s0 = Session.new(136,"empty",0)
	t.check(int(s0.data["player"]["dash_cooldown_ticks"]) == 40,"AD-196 dash cooldown is 40 ticks")
	for kind in BEFORE_SPEEDS:
		var ratio := float(s0.data["enemies"][kind]["projectile_speed"])/float(BEFORE_SPEEDS[kind])
		t.check(ratio >= 1.2 and ratio <= 1.35,"AD-196 %s projectile speed x%.2f in 1.20..1.35" % [kind,ratio])
	for pair in [["ruins_adept_elite",310.0],["cistern_crystal_elite",280.0]]:
		var ratio := float(s0.data["mini_bosses"][pair[0]]["shot_speed"])/float(pair[1])
		t.check(ratio >= 1.2 and ratio <= 1.35,"AD-196 %s shot speed x%.2f in 1.20..1.35" % [pair[0],ratio])
	for spec in [["fallen_adept",3,12],["grave_hound",2,10]]:
		var times := _shot_ticks(spec[0],Vector2(200,0),Vector2.ZERO,0)
		t.check(times.size() == spec[1],"AD-196 %s fires a %d-shot burst (%s)" % [spec[0],spec[1],str(times)])
		for i in range(1,times.size()):
			t.check(times[i]-times[i-1] == spec[2],"AD-196 %s burst spacing %d" % [spec[0],spec[2]])
	# re-aim: the player moves between shots, so the second shot direction differs from the first
	var dirs := _shot_dirs("fallen_adept",Vector2(200,0),Vector2.UP)
	t.check(dirs.size() >= 2 and dirs[0].distance_to(dirs[1]) > 0.01,"AD-196 second burst shot re-aims at the moved player")
	var single := _spawn("fallen_adept",Vector2(200,0),{"behaviours":[{"id":"ranged_attack","burst_shots":1,"burst_interval_ticks":0}]})
	var attacked := false
	for i in 120:
		single[0].step()
		attacked = attacked or single[1].state == "attack"
	t.check(not attacked,"AD-196 burst_shots 1 never enters the attack state")
	# dying mid-burst stops the burst
	var dying := _spawn("fallen_adept",Vector2(200,0))
	var count := 0
	var counted := {}
	var killed := false
	for i in 200:
		if not killed and dying[1].state == "attack" and dying[1].state_tick >= 2:
			dying[1].target.health.current = 0.0
			killed = true
		dying[0].step()
		for shot in dying[0].enemy_shots:
			counted[shot["id"]] = true
		count = counted.size()
	t.check(killed and count <= 1,"AD-196 a dead shooter stops its burst (%d)" % count)
	# loses sight mid-burst: a wall appears between shooter and player
	var blind := _spawn("fallen_adept",Vector2(200,0))
	var seen := {}
	var walled := false
	for i in 200:
		if not walled and blind[1].state == "attack" and blind[1].state_tick >= 2:
			blind[0].world.walls.append(Rect2(blind[0].sim.actor.position+Vector2(80,-300),Vector2(20,600)))
			blind[0].world.clear_sight(Vector2.ZERO,Vector2.ONE)
			walled = true
		blind[0].step()
		for shot in blind[0].enemy_shots:
			seen[shot["id"]] = true
	t.check(walled and seen.size() <= 1,"AD-196 a burst stops when the shooter loses sight (%d)" % seen.size())
	var issues: Array = preload("res://combat/enemy_behaviours/ranged_attack.gd").validate({"burst_shots":0,"burst_interval_ticks":0})
	t.check(not issues.is_empty(),"AD-196 validate rejects burst_shots 0")
	var bad: Array = preload("res://combat/enemy_behaviours/ranged_attack.gd").validate({"burst_shots":2,"burst_interval_ticks":0})
	t.check(not bad.is_empty(),"AD-196 validate rejects a burst without an interval")

## Ticks (step index) on which enemy shots appear while the player stands still in sight.
func _shot_ticks(kind: String, offset: Vector2, _move: Vector2, _unused: int) -> Array:
	var pair := _spawn(kind,offset,{"move_speed":0})
	var times: Array = []
	var seen := {}
	for i in 100:
		pair[0].step()
		for shot in pair[0].enemy_shots:
			if not seen.has(shot["id"]):
				seen[shot["id"]] = true
				times.append(i)
	return times

func _shot_dirs(kind: String, offset: Vector2, player_move: Vector2) -> Array:
	var pair := _spawn(kind,offset,{"move_speed":0})
	var dirs: Array = []
	var seen := {}
	for i in 200:
		if pair[1].state == "attack":
			pair[0].issue({"move":player_move,"aim":Vector2.RIGHT})
		pair[0].step()
		for shot in pair[0].enemy_shots:
			if not seen.has(shot["id"]):
				seen[shot["id"]] = true
				dirs.append(shot["direction"])
	return dirs
