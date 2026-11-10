extends RefCounted
## AD-141 / AD-200: mini-boss spawn, determinism, room integration and scripted kills on the live data (the framework patterns are in test_ad_mini_bosses_v2.gd).
const Session = preload("res://combat/combat_session.gd")
const AT := Vector2(1030,450)
const IDS := ["ruins_adept_elite","cistern_crystal_elite"]
const Room = preload("res://world/room_template.gd")
const Encounter = preload("res://world/encounter_director.gd")
const Driver = preload("res://tests/m3_run_driver.gd")
const ROOMS := {"ruins_adept_elite":"res://world/data/rooms_ruins_v1.json","cistern_crystal_elite":"res://world/data/rooms_cistern_v1.json"}
const BUILDS := [0,2]
const MAX_TICKS := 6000
const ELITE := {"hp_multiplier":1.5,"damage_multiplier":1.0}

func run(t) -> void:
	_unknown_and_deterministic(t)
	_room_integration(t)
	_scripted_kills(t)

func _fresh(id: String, elite: Dictionary = ELITE):
	var s = Session.new(1411,"empty",0)
	s.defer_clear = true
	return [s,s.spawn_mini_boss(id,AT,elite)]

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

func _room(id: String) -> Dictionary:
	var doc: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(ROOMS[id]))
	return doc["room_templates"][doc["challenge_room"]]

func _room_integration(t) -> void:
	var tuning: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://combat/combat_tuning_v1.json"))
	for id in IDS:
		var values: Dictionary = _room(id)
		var slot: Dictionary = values["mini_boss_slot"]
		t.equal(str(slot["id"]),id,"AD-141 %s slot id" % id)
		t.equal(int(slot["wave"]),1,"AD-141 %s slot is wave 1" % id)
		var s = Session.new(1412,"empty",0)
		t.check(s.world.valid_position(Vector2(float(slot["position"][0]),float(slot["position"][1])),30.0),"AD-141 %s slot position is open" % id)
		var template = Room.new()
		var verdict: Dictionary = template.initialize(values.duplicate(true),tuning["arena"],tuning["enemies"].keys())
		t.check(verdict["ok"],"AD-141 %s room still valid" % id)
		var director = Encounter.new()
		director.initialize(template,s,12)
		var guard := 0
		while director.launched.size() < 2 and guard < 1000:
			for e in s.enemies:
				if e.target.alive():
					e.target.health.current = 0.0
			s.enemies = s.enemies.filter(func(e): return e.target.alive())
			s.sim.clock.tick += 1
			director.advance()
			guard += 1
		var boss = null
		for e in s.enemies:
			if e.target.tags.has("mini_boss"):
				boss = e
		t.check(boss != null and director.launched.has(1),"AD-141 %s mini-boss spawns with wave 1" % id)
		t.check(director.log.any(func(l): return l["event"] == "mini_boss_spawn" and l["id"] == id),"AD-141 %s spawn logged" % id)
		for e in s.enemies:
			if e != boss:
				e.target.health.current = 0.0
		director.advance()
		t.check(director.clear_emissions == 0 and s.state != "cleared","AD-141 %s room stays uncleared while mini-boss lives" % id)
		boss.target.health.current = 0.0
		director.advance()
		t.check(director.clear_emissions == 1,"AD-141 %s room clears after mini-boss dies" % id)

class Harness:
	var session
	var state := "fighting"
	func step(command: Dictionary) -> void:
		session.issue(command)
		session.step()
		if session.state != "playing" or session.alive_enemies() == 0:
			state = "done"

func _kill(id: String, build: int) -> Dictionary:
	var s = Session.new(1413,"empty",build)
	var boss = s.spawn_mini_boss(id,AT,_room(id)["elite"])
	var h := Harness.new()
	h.session = s
	var result: Dictionary = Driver.fight(h,MAX_TICKS)
	return {"dead":not boss.target.alive(),"alive":s.sim.actor.health.current > 0.0,"tick":s.sim.clock.tick,"hp":result["hp"]}

func _scripted_kills(t) -> void:
	for id in IDS:
		for build in BUILDS:
			var a: Dictionary = _kill(id,build)
			t.check(a["dead"] and a["alive"],"AD-141 %s build %d kills mini-boss and survives (tick %d, hp %.0f)" % [id,build,a["tick"],a["hp"]])
			t.equal(_kill(id,build)["tick"],a["tick"],"AD-141 %s build %d kill tick deterministic" % [id,build])
