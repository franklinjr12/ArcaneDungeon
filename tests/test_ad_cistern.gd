extends RefCounted
## AD-138 step 1: water tile rules (Wet on standing, deep water blocks walking, Lightning conducts through water).
const Session = preload("res://combat/combat_session.gd")
const WaterTiles = preload("res://world/water_tiles.gd")
const Room = preload("res://world/room_template.gd")
const Flow = preload("res://world/run_flow.gd")
const POOL_PATH := "res://world/data/rooms_cistern_v1.json"

# Rooms of combat_tuning_v1 arena have walls up to y=735 and a wall at x 890-976 (y 360-535); the strip y 770-870 is free.
const SHALLOW := {"kind":"shallow","rect":[200,770,700,100]}
const DEEP := {"kind":"deep","rect":[900,770,100,100]}
const WET_SPOT := {"kind":"shallow","rect":[300,300,500,120]}

func run(t) -> void:
	_wet(t)
	_deep(t)
	_conduct(t)
	_validate(t)
	_determinism(t)
	_pool(t)
	_pool_negative(t)
	_sequence(t)
	_full_runs(t)

func _session(water: Array) -> Object:
	var s = Session.new(138,"empty",0)
	if not water.is_empty():
		s.set_water(water)
	return s

func _lightning(s, target) -> Dictionary:
	var payload := {"team":s.sim.actor.team,"essence_id":"essence.lightning","damage":10.0,"cast_id":1,"root_cast_id":1}
	return s.sim.resolver.resolve(payload,target,s.sim.targets,s.sim.clock.tick)

func _wet(t) -> void:
	var s = _session([WET_SPOT])
	var interval: int = int(s.data["water"]["wet_interval_ticks"])
	s.sim.actor.position = Vector2(400,360)
	var inside = s.spawn_enemy("bone_thrall",Vector2(700,360))
	var outside = s.spawn_enemy("bone_thrall",Vector2(700,700))
	t.check(inside != null and outside != null,"AD-138 water: enemies spawn")
	for i in interval:
		s.step()
	var tick: int = s.sim.clock.tick
	t.check(s.sim.actor.status.has("wet",tick),"AD-138 water: player in shallow water becomes Wet within the interval")
	t.check(inside.target.status.has("wet",tick),"AD-138 water: enemy in water becomes Wet")
	t.check(not outside.target.status.has("wet",tick),"AD-138 water: enemy outside water stays dry")
	var dry = _session([WET_SPOT])
	dry.sim.actor.position = Vector2(400,700)
	for i in interval*2:
		dry.step()
	t.check(not dry.sim.actor.status.has("wet",dry.sim.clock.tick),"AD-138 water: player outside water stays dry")
	var none = _session([])
	none.sim.actor.position = Vector2(400,360)
	for i in interval*2:
		none.step()
	t.check(none.water == null and not none.sim.actor.status.has("wet",none.sim.clock.tick),"AD-138 water: no water, no Wet")
	none.restart()
	t.check(none.water == null,"AD-138 water: restart clears water")
	s.restart()
	t.check(s.water == null and s.world.ground_blockers.is_empty() and s.sim.resolver.water == null,"AD-138 water: restart resets blockers and resolver")

func _deep(t) -> void:
	var s = _session([SHALLOW,DEEP])
	var radius := 14.0
	t.check(s.world.ground_blockers.size() == 1,"AD-138 deep: only deep rects block walking")
	t.check(not s.world.valid_position(Vector2(950,820),radius),"AD-138 deep: valid_position inside deep water is false")
	t.check(s.world.valid_position(Vector2(500,820),radius),"AD-138 deep: shallow water is walkable")
	var moved: Vector2 = s.world.move_body(Vector2(800,820),Vector2(300,0),radius)
	t.check(moved.x <= 900.0-radius+0.001 and moved.x > 900.0-radius-7.0,"AD-138 deep: move_body stops at the deep edge (%s)" % str(moved))
	t.check(s.world.clear_sight(Vector2(800,820),Vector2(1100,820),radius),"AD-138 deep: sight crosses deep water")
	t.check(not s.sim.collision_walls.has(Rect2(900,770,100,100)),"AD-138 deep: spell collision walls exclude deep water")
	var dir: Vector2 = s.world.navigate_direction(Vector2(800,820),Vector2(1100,820),radius)
	t.check(absf(dir.y) > 0.1,"AD-138 deep: navigation routes around deep water (%s)" % str(dir))

func _pair(water: Array, a_at: Vector2, b_at: Vector2) -> Array:
	var s = _session(water)
	s.sim.actor.position = Vector2(100,820)
	var a = s.spawn_enemy("bone_thrall",a_at)
	var b = s.spawn_enemy("bone_thrall",b_at)
	return [s,a,b]

func _conduct(t) -> void:
	var arc_radius := 220.0
	var near := [SHALLOW]
	var rig := _pair(near,Vector2(220,820),Vector2(520,820))
	var s = rig[0]
	var gap: float = rig[1].target.position.distance_to(rig[2].target.position)
	var conduct := float(s.sim.settings["combat"]["water_conduct_radius"])
	t.check(gap > arc_radius+rig[2].target.radius and gap < conduct,"AD-138 conduct: setup is beyond arc_radius but within water_conduct_radius (%f)" % gap)
	var out := _lightning(s,rig[1].target)
	t.check(out["accepted"] and not rig[2].target.status.has("wet",s.sim.clock.tick),"AD-138 conduct: B is not Wet")
	t.check(not out["reaction"].is_empty() and int(out["reaction"]["target_id"]) == rig[2].target.id and int(out["reaction"]["source_id"]) == rig[1].target.id,"AD-138 conduct: Lightning on A arcs to B in the same body")
	t.check(is_equal_approx(float(out["reaction"]["damage"]),10.0*float(s.sim.settings["combat"]["arc_damage_scale"])),"AD-138 conduct: arc keeps the damage scale")
	var dry := _pair([],Vector2(220,820),Vector2(520,820))
	t.check(_lightning(dry[0],dry[1].target)["reaction"].is_empty(),"AD-138 conduct: same setup without water does not arc")
	var split := _pair([{"kind":"shallow","rect":[200,770,200,100]},{"kind":"shallow","rect":[450,770,150,100]}],Vector2(220,820),Vector2(520,820))
	t.check(_lightning(split[0],split[1].target)["reaction"].is_empty(),"AD-138 conduct: B in a separate water body gets no arc")
	var three := _pair(near,Vector2(220,820),Vector2(520,820))
	var extra = three[0].spawn_enemy("bone_thrall",Vector2(400,820))
	var third := _lightning(three[0],three[1].target)
	t.check(not third["reaction"].is_empty() and int(third["reaction"]["target_id"]) == extra.target.id,"AD-138 conduct: exactly one arc, to the nearest in-body target")
	var wet_rule := _pair([],Vector2(320,360),Vector2(480,360))
	for enemy in [wet_rule[1],wet_rule[2]]:
		enemy.target.status.apply("wet",0,wet_rule[0].sim.settings["statuses"]["wet"],{})
	t.check(not _lightning(wet_rule[0],wet_rule[1].target)["reaction"].is_empty(),"AD-138 conduct: existing Wet arc rule unchanged outside water")

func _validate(t) -> void:
	t.check(WaterTiles.validate([SHALLOW,DEEP]).is_empty(),"AD-138 validate: good tiles pass")
	var bad: Array = [
		[{"kind":"lava","rect":[0,0,10,10]}],
		[{"kind":"deep","rect":[0,0,10]}],
		[{"kind":"deep","rect":[0,0,0,10]}],
		[{"kind":"deep","rect":[0,0,10,-5]}],
		[{"kind":"deep","rect":[0,0,"a",10]}],
		[{"kind":"deep"}],
		["deep"]]
	for entries in bad:
		var issues := WaterTiles.validate(entries)
		t.check(not issues.is_empty() and str(issues[0]["code"]) == "WATER_TILE_INVALID" and issues[0].has("path") and issues[0].has("message"),"AD-138 validate: rejects %s" % str(entries))
	t.equal(WaterTiles.new([SHALLOW,DEEP]).body_of(Vector2(950,820)),0,"AD-138 water: touching shallow and deep share one body")
	t.equal(WaterTiles.new([SHALLOW,{"kind":"deep","rect":[1100,770,100,100]}]).body_of(Vector2(1150,820)),1,"AD-138 water: bodies numbered by first rect index")
	var touching := WaterTiles.new([{"kind":"shallow","rect":[0,0,10,10]},{"kind":"deep","rect":[50,0,10,10]},{"kind":"shallow","rect":[10,0,40,10]}])
	t.equal(touching.body_of(Vector2(55,5)),0,"AD-138 water: touching rects join one body")
	t.equal(touching.body_of(Vector2(500,500)),-1,"AD-138 water: outside any water is -1")

func _scenario() -> Array:
	var rig := _pair([SHALLOW],Vector2(220,820),Vector2(520,820))
	var s = rig[0]
	s.sim.actor.position = Vector2(400,820)
	var log: Array = []
	for i in 40:
		s.step()
		if i == 20:
			var out := _lightning(s,rig[1].target)
			log.append(str(out["reaction"]))
		var tick: int = s.sim.clock.tick
		log.append([s.sim.actor.status.has("wet",tick),rig[1].target.status.has("wet",tick),rig[2].target.status.has("wet",tick)])
	return log

func _determinism(t) -> void:
	t.check(_scenario() == _scenario(),"AD-138 water: identical status/arc sequence across runs")

func _verdict(room: Dictionary, rules: Dictionary, tuning: Dictionary) -> Dictionary:
	var copy: Dictionary = room.duplicate(true)
	copy["min_spawn_distance"] = rules["min_spawn_distance"]
	copy["player_radius"] = rules["player_radius"]
	copy["grid_step"] = rules["grid_step"]
	return Room.new().initialize(copy,tuning["arena"],tuning["enemies"].keys())

func _codes(verdict: Dictionary) -> Array:
	var codes: Array = []
	for issue in verdict.get("issues",[]):
		codes.append(issue["code"])
	return codes

func _has_deep(room: Dictionary) -> bool:
	for entry in room["layout"]["water"]:
		if entry["kind"] == "deep":
			return true
	return false

func _pool(t) -> void:
	var doc: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(POOL_PATH))
	var tuning: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://combat/combat_tuning_v1.json"))
	var rules: Dictionary = doc["rules"]
	t.check(doc["pool"].size() == int(rules["pool_size"]) and doc["pool"].size() == 10,"AD-138 cistern pool has 10 templates")
	var layouts: Dictionary = {}
	var deep_rooms := 0
	for id in doc["room_templates"]:
		var room: Dictionary = doc["room_templates"][id]
		var verdict := _verdict(room,rules,tuning)
		t.check(verdict["ok"],"AD-138 template %s valid %s" % [id,str(verdict.get("issues",[]))])
		t.check(not room["layout"].get("water",[]).is_empty(),"AD-138 %s has water" % id)
		layouts[JSON.stringify(room["layout"])+JSON.stringify(room["waves"])] = true
	t.check(layouts.size() == doc["room_templates"].size(),"AD-138 every cistern template is distinct")
	for id in doc["pool"]:
		var room: Dictionary = doc["room_templates"][id]
		t.check(room["type"] == "combat","AD-138 %s is a combat room" % id)
		deep_rooms += 1 if _has_deep(room) else 0
	t.check(deep_rooms >= 4,"AD-138 at least 4 pool rooms have deep channels (%d)" % deep_rooms)
	var treasure: Dictionary = doc["room_templates"][doc["treasure_room"]]
	t.check(treasure["type"] == "treasure" and int(treasure["choice_count"]) == 1 and treasure["pedestals"].size() >= 2,"AD-138 treasure room offers a 1-of-N pedestal choice")
	var challenge: Dictionary = doc["room_templates"][doc["challenge_room"]]
	t.check(challenge["type"] == "challenge" and challenge["waves"].size() == 2 and challenge.has("elite") and challenge.has("challenge_reward") and challenge.has("mini_boss_slot") and challenge["mini_boss_slot"] is Dictionary and JSON.parse_string(FileAccess.get_file_as_string("res://combat/combat_tuning_v1.json"))["mini_bosses"].has(challenge["mini_boss_slot"]["id"]),"AD-138 challenge room has 2 waves, elite, reward and a mini-boss slot")

func _pool_negative(t) -> void:
	var doc: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(POOL_PATH))
	var tuning: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://combat/combat_tuning_v1.json"))
	var rules: Dictionary = doc["rules"]
	var base: Dictionary = doc["room_templates"]["cistern_p03"]
	var in_deep: Dictionary = base.duplicate(true)
	in_deep["waves"][0]["enemies"][0] = ["bone_thrall",720,100]
	t.check("ROOM_SPAWN_BLOCKED" in _codes(_verdict(in_deep,rules,tuning)),"AD-138 validator rejects a spawn inside a deep rect")
	var cut: Dictionary = base.duplicate(true)
	cut["layout"]["water"] = [{"kind":"deep","rect":[300,0,100,900]}]
	t.check("ROOM_EXIT_UNREACHABLE" in _codes(_verdict(cut,rules,tuning)),"AD-138 validator: full-height deep channel cuts off the exit")
	var bad_kind: Dictionary = base.duplicate(true)
	bad_kind["layout"]["water"] = [{"kind":"lava","rect":[300,0,100,100]}]
	var verdict := _verdict(bad_kind,rules,tuning)
	t.check("WATER_TILE_INVALID" in _codes(verdict) and str(verdict["issues"][0]["path"]).begins_with("layout.water"),"AD-138 validator rejects a bad water kind")
	var marker: Dictionary = base.duplicate(true)
	marker["layout"]["water"] = [{"kind":"deep","rect":[1100,400,200,100]}]
	var codes := _codes(_verdict(marker,rules,tuning))
	t.check("ROOM_MARKER_BLOCKED" in codes,"AD-138 validator rejects a reward marker in deep water")
	var ped: Dictionary = doc["room_templates"]["cistern_treasure_v1"].duplicate(true)
	ped["layout"]["water"] = [{"kind":"deep","rect":[650,250,100,100]}]
	t.check("ROOM_PEDESTAL_INVALID" in _codes(_verdict(ped,rules,tuning)),"AD-138 validator rejects a pedestal in deep water")

func _cfg() -> Dictionary:
	return JSON.parse_string(FileAccess.get_file_as_string(Flow.CONFIG_V2))

func _sequence(t) -> void:
	var cfg := _cfg()
	var doc: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(POOL_PATH))
	var merged := Flow.merged_templates(cfg)
	t.check(merged.has("cistern_p01") and merged.has("cistern_challenge_v1") and merged.has("ruins_c01") and not merged.has("cistern_c01"),"AD-138 merged templates hold ruins, cistern pool and no placeholders")
	t.equal(int(merged["cistern_p01"]["grid_step"]),20,"AD-138 merged templates copy pool rules")
	var ok := true
	for run_seed in range(1,21):
		var combat_ids := 0
		for entry in Flow.build_sequence(cfg,run_seed):
			if int(entry["stage"]) == 1 and entry["type"] == "combat":
				combat_ids += 1
				ok = ok and str(entry["id"]) in doc["pool"]
		ok = ok and combat_ids >= 5 and combat_ids <= 6
	t.check(ok,"AD-138 seeds 1..20: every stage-1 combat room comes from the cistern pool")

func _kill_all(flow) -> void:
	for i in 3000:
		if flow.state != "fighting":
			return
		for enemy in flow.session.enemies:
			if enemy.target.alive():
				enemy.target.receive_damage(100000,"fire",1,100)
		flow.step()

func _scripted_run(run_seed: int, take_optional: bool, t, label: String):
	var flow = Flow.new(run_seed,Flow.CONFIG_V2)
	var water_rooms := 0
	var cistern_rooms := 0
	for guard in 80:
		var id := str(flow.room.values["id"])
		if id.begins_with("cistern_p") and flow.state == "fighting":
			cistern_rooms += 1
			var has_water: bool = flow.session.water != null
			var wet := false
			if has_water:
				water_rooms += 1
				var spot := _shallow_centre(flow.room.values["layout"]["water"])
				flow.session.sim.actor.position = spot
				var interval: int = int(flow.session.data["water"]["wet_interval_ticks"])
				for i in interval:
					flow.step()
				wet = flow.session.sim.actor.status.has("wet",flow.session.sim.clock.tick)
			t.check(has_water and wet,"AD-138 %s: %s has water and Wets a player standing in it" % [label,id])
		if flow.state == "fighting":
			_kill_all(flow)
		if flow.state == "won" or flow.state == "dead":
			break
		if flow.state == "cleared" and not flow.reward_collected and flow.room.values["type"] != "boss":
			flow.choose_reward(0)
		var pos: Vector2 = flow.room.marker("exit")
		flow.session.sim.actor.position = pos
		flow.try_exit(pos,take_optional)
	t.check(cistern_rooms >= 5 and water_rooms == cistern_rooms,"AD-138 %s: %d cistern combat rooms all with water" % [label,cistern_rooms])
	return flow

func _shallow_centre(water: Array) -> Vector2:
	for entry in water:
		if entry["kind"] == "shallow":
			var r: Array = entry["rect"]
			return Vector2(float(r[0])+float(r[2])*0.5,float(r[1])+float(r[3])*0.5)
	return Vector2.ZERO

func _full_runs(t) -> void:
	for take_optional in [false,true]:
		var label := "run optional %s" % str(take_optional)
		var flow = _scripted_run(20261022,take_optional,t,label)
		t.equal(flow.state,"won",("AD-138 %s ends won" % label))
		t.equal(str(flow.room.values["id"]),"cistern_boss","AD-138 %s reaches cistern_boss" % label)
		var entered: Array = []
		for entry in flow.logs:
			if entry["kind"] == "room_enter":
				entered.append(str(entry["id"]))
		t.equal(entered.has("cistern_challenge_v1"),take_optional,"AD-138 %s challenge room matches choice" % label)
