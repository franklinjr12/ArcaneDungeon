extends RefCounted
const Session = preload("res://combat/combat_session.gd")

func run(t) -> void:
	_live_reach(t)
	_walking_is_not_enough(t)
	_wall_stop(t)
	_no_lunge_instant(t)

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
