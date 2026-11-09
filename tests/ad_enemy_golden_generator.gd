extends SceneTree
## Developer-only regeneration utility. Review fixture changes before accepting them.
## godot --headless --path . --script res://tests/ad_enemy_golden_generator.gd
const Session = preload("res://combat/combat_session.gd")
const SEED = 136136
const TICKS = 600
const CASES = ["thrall_solo","adept_solo","hound_solo","mixed_scripted","cluster_scripted","statuses","deaths"]
## Scripted player walk (waypoints, 90 ticks per leg) that crosses behind the wall columns at x~570-634.
const PATH = [Vector2(185,450),Vector2(185,150),Vector2(900,150),Vector2(900,750),Vector2(185,750),Vector2(185,450),Vector2(500,450),Vector2(185,450)]
const LEG_TICKS = 90

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	preload("res://tests/test_context.gd").set_frozen_balance(true)
	var outputs: Dictionary = {}
	for case_name in CASES:
		outputs[case_name] = run_case(case_name)
	print("AD136_GOLDEN_OUTPUT:",JSON.stringify(outputs))
	quit()

static func _path_position(tick: int) -> Vector2:
	var leg: int = (tick / LEG_TICKS) % (PATH.size() - 1)
	var f: float = float(tick % LEG_TICKS) / float(LEG_TICKS)
	return PATH[leg].lerp(PATH[leg + 1],f)

static func _record(s, lines: Array) -> void:
	for enemy in s.enemies:
		lines.append("%d|%d|%s|%s|%d|%d|%.5f|%.5f|%s" % [s.sim.clock.tick,enemy.target.id,enemy.kind,enemy.state,enemy.state_tick,enemy.cooldown,
			enemy.target.position.x,enemy.target.position.y,str(enemy.intent != null)])
	for shot in s.enemy_shots:
		lines.append("shot|%d|%d|%.5f|%.5f" % [s.sim.clock.tick,shot["id"],shot["position"].x,shot["position"].y])

static func _status(s, enemy, id: String) -> void:
	enemy.target.status.apply(id,s.sim.clock.tick,s.sim.settings["statuses"][id])

static func run_case(case_name: String) -> Array:
	var scenario := "empty"
	if case_name == "mixed_scripted":
		scenario = "mixed"
	elif case_name == "cluster_scripted":
		scenario = "cluster"
	elif case_name == "deaths":
		scenario = "mixed"
	var s = Session.new(SEED,scenario,0)
	var origin: Vector2 = s.sim.actor.position
	var spawn := origin + Vector2(500,0)
	var named: Dictionary = {}
	match case_name:
		"thrall_solo":
			s.spawn_enemy("bone_thrall",spawn)
		"adept_solo":
			s.spawn_enemy("fallen_adept",spawn)
		"hound_solo":
			s.spawn_enemy("grave_hound",spawn)
		"statuses":
			named["thrall"] = s.spawn_enemy("bone_thrall",origin + Vector2(500,-250))
			named["adept"] = s.spawn_enemy("fallen_adept",origin + Vector2(380,0))
			named["hound"] = s.spawn_enemy("grave_hound",origin + Vector2(500,250))
	var lines: Array = []
	for i in TICKS:
		var moving: bool = i >= 200 if case_name in ["mixed_scripted","cluster_scripted"] else case_name != "statuses" and case_name != "deaths"
		if moving:
			var k: int = i - 200 if case_name in ["mixed_scripted","cluster_scripted"] else i
			s.sim.actor.position = _path_position(k)
		match case_name:
			"statuses":
				if i == 20:
					_status(s,named["thrall"],"chilled")
				if i == 6:
					_status(s,named["adept"],"frozen")
				if i == 150:
					_status(s,named["hound"],"blinded")
			"deaths":
				for j in s.enemies.size():
					if i == 120 + 90 * j:
						s.enemies[j].target.receive_damage(100000,"fire",1,100)
		s.step()
		_record(s,lines)
	for event in s.damage_events:
		lines.append("damage|%d|%s|%.5f" % [int(event["tick"]),str(event.get("source_id",event.get("source",""))),float(event["dealt"])])
	for transition in s.ai_transitions:
		lines.append("dead_transition|%d|%d|%s|%s" % [int(transition["tick"]),int(transition["enemy_id"]),transition["from"],transition["to"]])
	for enemy in s.enemies:
		for transition in enemy.transitions:
			lines.append("transition|%d|%d|%s|%s" % [int(transition["tick"]),int(transition["enemy_id"]),transition["from"],transition["to"]])
	return lines
