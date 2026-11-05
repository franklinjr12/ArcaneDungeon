extends RefCounted
## AD-142 step 1: Drowned Archivist (stage 2 final boss): 3 phases, water bolts + Wet zones, flood toggle, wisps, storm pulses.
const Session = preload("res://combat/combat_session.gd")
const AT := Vector2(1030,450)
const FLOOR_TICKS := 36

func run(t) -> void:
	var cfg := _cfg()
	_phase_one(t,cfg)
	_phase_two(t,cfg)
	_phase_three(t,cfg)
	_phase_never_drops(t)
	_telegraph_floor(t,cfg)
	_beatable_any_element(t,cfg)
	_deterministic(t)

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
