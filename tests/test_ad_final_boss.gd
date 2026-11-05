extends RefCounted
## AD-142 step 1: Drowned Archivist (stage 2 final boss): 3 phases, water bolts + Wet zones, flood toggle, wisps, storm pulses.
const Session = preload("res://combat/combat_session.gd")
const AT := Vector2(1030,450)
const FLOOR_TICKS := 36
const Driver = preload("res://tests/m3_run_driver.gd")
const Flow = preload("res://world/run_flow.gd")
const BUILDS := [0,2]
const MAX_TICKS := 12000
const MIN_KILL_TICKS := 5400
const MAX_KILL_TICKS := 10800

func run(t) -> void:
	var cfg := _cfg()
	_phase_one(t,cfg)
	_phase_two(t,cfg)
	_phase_three(t,cfg)
	_phase_never_drops(t)
	_telegraph_floor(t,cfg)
	_beatable_any_element(t,cfg)
	_deterministic(t)
	_arena_room(t)
	_scripted_wins(t)
	_run_summary(t)

func _cfg() -> Dictionary:
	var doc: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://world/data/run_v2.json"))
	return doc["bosses"]["cistern_boss"]

func _rects(cfg: Dictionary, index: int) -> Array:
	return cfg["flood_sets"][index].map(func(entry): return entry["rect"])

func _fresh():
	var s = Session.new(1421,"empty",0)
	s.defer_clear = true
	var boss = s.spawn_boss(_cfg(),AT)
	return [s,boss]

## Advances until the next attack fires (windup -> recover), returning the ticks spent in that windup.
func _next_fire(boss, s) -> int:
	var seen := false
	for i in 2000:
		boss.advance(s)
		if boss.state == "windup":
			seen = true
		elif seen and boss.state == "recover":
			return i
	return -1

func _to_windup(boss, s) -> void:
	for i in 2000:
		if boss.state == "windup":
			return
		boss.advance(s)

func _phase_one(t, cfg: Dictionary) -> void:
	var pair = _fresh()
	var s = pair[0]
	var boss = pair[1]
	t.check(boss != null and boss.kind == "drowned_archivist","AD-142 archivist spawns from bosses.cistern_boss")
	t.check(boss.target.tags.has("boss"),"AD-142 archivist is tagged boss")
	s.sim.actor.position = AT+Vector2(-300,0)
	var hp0: float = s.sim.actor.health.current
	var windup := int(boss.tuning["phases"][0]["windup_ticks"])
	boss.advance(s)
	t.equal(boss.intent.snapshot()["kind"],"water_bolt","AD-142 phase 1 opens with water_bolt")
	t.equal(boss.phase,1,"AD-142 starts in phase 1")
	for i in windup-1:
		boss.advance(s)
	t.check(s.enemy_shots.is_empty() and s.hazards.is_empty() and s.sim.actor.health.current == hp0,"AD-142 nothing fires during the water_bolt windup")
	boss.advance(s)
	t.equal(s.enemy_shots.size(),int(cfg["water_bolt_shots"]),"AD-142 water_bolt fires water_bolt_shots shots")
	t.equal(boss.cycle,1,"AD-142 cycle advances after the first attack")
	s.enemy_shots.clear()
	_to_windup(boss,s)
	var locked: Vector2 = s.sim.actor.position
	t.equal(boss.intent.snapshot()["kind"],"wet_zone","AD-142 phase 1 second pattern is wet_zone")
	t.equal(boss.intent.snapshot()["target"],locked,"AD-142 wet_zone locks the player position at windup start")
	s.sim.actor.position += Vector2(0,200)
	for i in windup-1:
		boss.advance(s)
	t.check(s.hazards.is_empty(),"AD-142 no puddle during the wet_zone windup")
	boss.advance(s)
	t.equal(s.hazards.size(),1,"AD-142 wet_zone adds exactly one hazard")
	t.check(s.hazards[0]["position"] == locked and s.hazards[0]["status"] == "wet" and float(s.hazards[0]["radius"]) == float(cfg["wet_zone_radius"]),"AD-142 puddle sits at the locked position with data radius")
	_to_windup(boss,s)
	t.equal(boss.intent.snapshot()["kind"],"water_bolt","AD-142 phase 1 cycles back to water_bolt")

func _phase_two(t, cfg: Dictionary) -> void:
	var pair = _fresh()
	var s = pair[0]
	var boss = pair[1]
	s.sim.actor.position = Vector2(400,200)
	_next_fire(boss,s)
	boss.target.health.current = boss.target.health.maximum*0.6
	boss.advance(s)
	t.equal(boss.phase,2,"AD-142 hp 60% enters phase 2")
	t.check(boss.transitions.any(func(x): return x["from"] == "phase1" and x["to"] == "phase2"),"AD-142 phase 1->2 transition recorded")
	t.equal(boss.cycle,0,"AD-142 phase change resets the pattern cycle")
	t.check(s.water == null,"AD-142 no water before the flood")
	_to_windup(boss,s)
	var intent: Dictionary = boss.intent.snapshot()
	t.equal(intent["kind"],"flood","AD-142 phase 2 opens with flood")
	t.equal(intent["rects"],_rects(cfg,0),"AD-142 flood telegraph carries the rects")
	t.check(int(intent["telegraph_ticks"]) >= FLOOR_TICKS,"AD-142 flood telegraph >= 0.6 s")
	for i in int(intent["telegraph_ticks"])-1:
		boss.advance(s)
	t.check(s.water == null or s.water.view().is_empty(),"AD-142 water stays dry for the whole flood windup")
	boss.advance(s)
	var tagged: Array = s.water.view().filter(func(e): return e.get("tag","") == "archivist_flood")
	t.equal(tagged.size(),2,"AD-142 flood adds the tagged rects")
	t.check(tagged.all(func(e): return e["kind"] == "shallow"),"AD-142 flood only uses shallow water")
	var interval := int(s.data["water"]["wet_interval_ticks"])
	for i in interval:
		s.sim.clock.tick += 1
		s._step_water()
	t.check(s.sim.actor.status.has("wet",s.sim.clock.tick),"AD-142 player standing in the flood becomes Wet")
	for i in int(cfg["flood_duration_ticks"]):
		boss.advance(s)
	t.equal(s.water.view().filter(func(e): return e.get("tag","") == "archivist_flood").size(),0,"AD-142 flood drains after flood_duration_ticks")
	# A second flood picks the next set; while one is active it is skipped.
	boss.cycle = 0
	boss._start_windup(s)
	t.equal(boss.intent.snapshot()["rects"],_rects(cfg,1),"AD-142 next flood uses the next set")
	boss._fire(s)
	boss.cycle = 0
	boss._start_windup(s)
	t.equal(boss.intent.snapshot()["kind"],"water_bolt","AD-142 no second flood while one is active")
	boss.target.health.current = 0.0
	boss.advance(s)
	t.equal(s.water.view().filter(func(e): return e.get("tag","") == "archivist_flood").size(),0,"AD-142 flood drains when the boss dies")

func _phase_three(t, cfg: Dictionary) -> void:
	var pair = _fresh()
	var s = pair[0]
	var boss = pair[1]
	s.sim.actor.position = AT+Vector2(-150,0)
	boss.target.health.current = boss.target.health.maximum*0.3
	boss.advance(s)
	t.equal(boss.phase,3,"AD-142 hp 30% enters phase 3")
	t.check(boss.transitions.any(func(x): return x["to"] == "phase3"),"AD-142 phase 3 transition recorded")
	t.equal(boss.intent.snapshot()["kind"],"summon_wisps","AD-142 phase 3 opens with summon_wisps")
	t.check(s.pending_spawns.is_empty(),"AD-142 no wisps during the windup")
	_next_fire(boss,s)
	t.equal(s.pending_spawns.size(),int(cfg["wisp_offsets"].size()),"AD-142 summon_wisps queues one wisp per offset")
	t.check(s.pending_spawns.all(func(p): return p["kind"] == "lantern_wisp" and int(p["summoner_id"]) == boss.target.id),"AD-142 wisps are owned by the boss")
	var hp0: float = s.sim.actor.health.current
	_next_fire(boss,s)
	t.equal(boss.intent.snapshot()["kind"],"storm_pulse","AD-142 phase 3 second pattern is storm_pulse")
	t.check(s.sim.actor.health.current < hp0,"AD-142 storm_pulse damages the player inside the radius")
	t.check(s.sim.actor.status.has("charged",s.sim.clock.tick),"AD-142 storm_pulse charges the player")
	_next_fire(boss,s)
	_next_fire(boss,s)
	t.equal(boss.intent.snapshot()["kind"],"summon_wisps","AD-142 phase 3 cycles back to summon_wisps")
	t.equal(s.pending_spawns.size(),int(cfg["wisp_cap"]),"AD-142 summon_wisps respects wisp_cap")
	# Outside the radius: no damage, no charge.
	var far = _fresh()
	far[0].sim.actor.position = AT+Vector2(-(float(cfg["storm_pulse_radius"])+far[0].sim.actor.radius+80.0),0)
	far[1].target.health.current = far[1].target.health.maximum*0.3
	far[1].advance(far[0])
	_next_fire(far[1],far[0])
	var hp1: float = far[0].sim.actor.health.current
	_next_fire(far[1],far[0])
	t.equal(far[0].sim.actor.health.current,hp1,"AD-142 storm_pulse does not hurt outside the radius")
	t.check(not far[0].sim.actor.status.has("charged",far[0].sim.clock.tick),"AD-142 storm_pulse does not charge outside the radius")

func _phase_never_drops(t) -> void:
	var pair = _fresh()
	var boss = pair[1]
	boss.target.health.current = boss.target.health.maximum*0.3
	boss.advance(pair[0])
	boss.target.health.current = boss.target.health.maximum
	for i in 200:
		boss.advance(pair[0])
	t.equal(boss.phase,3,"AD-142 phase never decreases when hp is restored")

func _telegraph_floor(t, cfg: Dictionary) -> void:
	var boss = _fresh()[1]
	t.check(int(boss.tuning["min_telegraph_ticks"]) >= FLOOR_TICKS,"AD-142 min_telegraph_ticks is 0.6 s")
	t.equal(boss.tuning["phases"].size(),3,"AD-142 has three phases")
	for index in boss.tuning["phases"].size():
		t.check(int(boss.tuning["phases"][index]["windup_ticks"]) >= FLOOR_TICKS,"AD-142 phase %d windup >= 36 ticks after scaling" % (index+1))

func _beatable_any_element(t, cfg: Dictionary) -> void:
	var worst := 0.0
	for channel in cfg.get("channel_resistances",{}):
		worst = maxf(worst,float(cfg["channel_resistances"][channel]))
	t.check(worst < 1.0,"AD-142 no element is fully resisted")
	var boss = _fresh()[1]
	t.check(boss.target.health.resistances.values().all(func(v): return float(v) < 1.0),"AD-142 spawned archivist resists nothing fully")

func _deterministic(t) -> void:
	var snaps: Array = []
	for run_index in 2:
		var pair = _fresh()
		var s = pair[0]
		s.sim.actor.position = Vector2(700,450)
		for i in 1500:
			if i == 500:
				pair[1].target.health.current = pair[1].target.health.maximum*0.6
			elif i == 1000:
				pair[1].target.health.current = pair[1].target.health.maximum*0.3
			s.step()
		var snap: Dictionary = s.snapshot()
		snap.erase("frame_ms")
		snaps.append(JSON.stringify(snap))
	t.equal(snaps[0],snaps[1],"AD-142 1500-tick run is deterministic")

func _doc() -> Dictionary:
	return JSON.parse_string(FileAccess.get_file_as_string("res://world/data/run_v2.json"))

func _arena_water() -> Array:
	return _doc()["room_templates"]["cistern_boss"]["layout"]["water"]

func _arena_room(t) -> void:
	var room: Dictionary = _doc()["room_templates"]["cistern_boss"]
	var tuning: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://combat/combat_tuning_v1.json"))
	var template = preload("res://world/room_template.gd").new()
	var verdict: Dictionary = template.initialize(room.duplicate(true),tuning["arena"],tuning["enemies"].keys())
	t.check(verdict["ok"],"AD-142 water arena passes room template validation")
	t.check(_arena_water().size() >= 2,"AD-142 boss room declares layout.water")
	var s = Session.new(1424,"empty",0)
	s.set_water(_arena_water())
	for key in ["entrance","exit","reward"]:
		t.check(s.world.valid_position(Vector2(float(room[key][0]),float(room[key][1])),30.0),"AD-142 arena %s marker is clear" % key)
	t.check(s.world.valid_position(AT,float(_cfg()["radius"])),"AD-142 boss position is clear in the arena")
	var path: Vector2 = s.world.navigate_direction(Vector2(185,450),AT,s.sim.actor.radius)
	t.check(not path.is_zero_approx(),"AD-142 a walking route from the entrance to the boss exists")

class Harness:
	var session
	var boss
	var state := "fighting"
	func step(command: Dictionary) -> void:
		session.issue(command)
		session.step()
		if session.state != "playing" or not boss.target.alive():
			state = "done"

## loadout: Array of two sample ids, or empty to use the starter build index.
func _kill(build: int, loadout: Array = []) -> Dictionary:
	var s = Session.new(1423,"empty",build)
	s.defer_clear = true
	s.set_water(_arena_water())
	if not loadout.is_empty():
		s.sim.loadout.allow_edit = true
		s.sim.equip_starter_loadout([s.samples[loadout[0]],s.samples[loadout[1]]])
		s.sim.loadout.allow_edit = false
	var boss = s.spawn_boss(_cfg(),AT)
	var h := Harness.new()
	h.session = s
	h.boss = boss
	Driver.fight(h,MAX_TICKS)
	var phases: Array = [1]
	for x in boss.transitions:
		if str(x["to"]).begins_with("phase"):
			phases.append(int(str(x["to"]).trim_prefix("phase")))
	return {"dead":not boss.target.alive(),"alive":s.sim.actor.health.current > 0.0,"tick":s.sim.clock.tick,"hp":s.sim.actor.health.current,"phases":phases}

func _check_win(t, label: String, a: Dictionary) -> void:
	t.check(a["dead"] and a["alive"],"AD-142 %s kills the archivist and survives (tick %d, hp %.0f)" % [label,a["tick"],a["hp"]])
	t.check(a["phases"].has(1) and a["phases"].has(2) and a["phases"].has(3),"AD-142 %s reaches all 3 phases" % label)
	t.check(a["tick"] >= MIN_KILL_TICKS and a["tick"] <= MAX_KILL_TICKS,"AD-142 %s fight lasts 90-180 s (tick %d)" % [label,a["tick"]])

func _scripted_wins(t) -> void:
	for build in BUILDS:
		var a: Dictionary = _kill(build)
		_check_win(t,"build %d" % build,a)
		t.equal(_kill(build)["tick"],a["tick"],"AD-142 build %d kill tick deterministic" % build)
	# Fire + Lightning has no Water; with build 0 (no Lightning) and build 2 (no Fire) no single element is required.
	_check_win(t,"no-water loadout",_kill(0,["sample.fire_shot","sample.lightning_shot"]))

## Reaches the cistern_boss room the way test_ad_run_v2 does, kills the archivist and checks the run summary.
func _run_summary(t) -> void:
	var flow = Flow.new(20261022,Flow.CONFIG_V2)
	for guard in 80:
		if flow.state == "fighting" and str(flow.room.values["id"]) == "cistern_boss":
			break
		if flow.state == "fighting":
			for i in 3000:
				if flow.state != "fighting":
					break
				for enemy in flow.session.enemies:
					if enemy.target.alive():
						enemy.target.receive_damage(100000,"fire",1,100)
				flow.step()
		if flow.state == "won" or flow.state == "dead":
			break
		if flow.state == "cleared" and not flow.reward_collected and flow.room.values["type"] != "boss":
			flow.choose_reward(0)
		var pos: Vector2 = flow.room.marker("exit")
		flow.session.sim.actor.position = pos
		flow.try_exit(pos,false)
	t.equal(str(flow.room.values["id"]),"cistern_boss","AD-142 run reaches the cistern boss room")
	t.check(flow.session.water != null,"AD-142 boss room installs layout water")
	var archivist = null
	for e in flow.session.enemies:
		if e.kind == "drowned_archivist":
			archivist = e
	t.check(archivist != null,"AD-142 boss room spawns the Drowned Archivist")
	t.equal(flow.state,"fighting","AD-142 boss fight is running")
	archivist.target.health.current = 0.0
	for i in 600:
		if flow.state != "fighting":
			break
		flow.step()
	t.equal(flow.state,"won","AD-142 killing the archivist wins the run")
	t.equal(flow.outcome,"won","AD-142 flow outcome is won")
	var summary: Dictionary = flow.summary()
	t.equal(summary["outcome"],"won","AD-142 run summary reports won after the kill")
	t.check(int(summary["rooms_cleared"]) > 0,"AD-142 run summary counts cleared rooms")
