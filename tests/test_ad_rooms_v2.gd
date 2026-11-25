extends RefCounted
## AD-241: room affix data and template validation (dark / unstable / haunted).
const Room = preload("res://world/room_template.gd")
const Session = preload("res://combat/combat_session.gd")
const Director = preload("res://world/encounter_director.gd")

func _verdict(room: Dictionary, tuning: Dictionary) -> Dictionary:
	var copy: Dictionary = room.duplicate(true)
	copy["min_spawn_distance"] = 45
	copy["player_radius"] = 22
	copy["grid_step"] = 20
	return Room.new().initialize(copy,tuning["arena"],tuning["enemies"].keys())

func _codes(verdict: Dictionary) -> Array:
	var codes: Array = []
	for issue in verdict["issues"]:
		codes.append(issue["code"])
	return codes

func _room(tuning: Dictionary, type: String = "combat") -> Dictionary:
	var w := float(tuning["arena"]["width"])
	var cy := float(tuning["arena"]["height"])*0.5
	return {"id":"synthetic","stage":1,"room":1,"type":type,"scene":"res://scenes/run.tscn",
		"entrance":[185,cy],"exit":[w-160,cy],"reward":[w-260,cy],
		"waves":[{"trigger":"start","delay_ticks":0,"enemies":[["lantern_wisp",w*0.6,cy-120],["bone_thrall",w*0.7,cy+120]]}],
		"layout":{}}

func run(t) -> void:
	test_ad_241_room_affix_data(t)
	test_ad_241_room_affix_validation(t)
	test_ad_241_dark_light_radius(t)
	test_ad_241_unstable_tiles(t)
	test_ad_241_haunted_respawn(t)
	test_ad_241_none_room_unchanged(t)
	test_ad_241_ruins_pool(t)
	test_ad_241_cistern_pool(t)

func test_ad_241_room_affix_data(t) -> void:
	var run: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://world/data/run_v2.json"))
	var aff: Dictionary = run["room_affixes"]
	t.check(aff["ids"] == ["dark","unstable","haunted"],"AD-241 room affix ids")
	t.check(int(aff["dark"]["light_radius"]) == 220,"AD-241 dark light radius is 220 u")
	t.check(int(aff["unstable"]["collapse_delay_ticks"]) == 2*60,"AD-241 unstable collapse is 2 s at 60 ticks/s")
	t.check(str(aff["haunted"]["respawn_kind"]) == "lantern_wisp" and int(aff["haunted"]["respawns"]) == 1,"AD-241 haunted respawns wisps once")

func test_ad_241_room_affix_validation(t) -> void:
	var tuning: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://combat/combat_tuning_v1.json"))
	var base := _room(tuning)
	t.check(_verdict(base,tuning)["ok"],"AD-241 synthetic base room valid %s" % str(_verdict(base,tuning)["issues"]))
	for id in ["none","dark","haunted"]:
		var r := base.duplicate(true)
		r["room_affix"] = id
		t.check(_verdict(r,tuning)["ok"],"AD-241 %s room valid" % id)
	var cy: float = base["entrance"][1]
	var ex: float = base["entrance"][0]
	var unstable := base.duplicate(true)
	unstable["room_affix"] = "unstable"
	unstable["layout"]["cracked_tiles"] = [[ex+300,cy-200,80,80],[ex+300,cy+120,80,80]]
	t.check(_verdict(unstable,tuning)["ok"],"AD-241 unstable room valid %s" % str(_verdict(unstable,tuning)["issues"]))
	var unknown := base.duplicate(true)
	unknown["room_affix"] = "frozen"
	t.check("ROOM_AFFIX_UNKNOWN" in _codes(_verdict(unknown,tuning)),"AD-241 unknown affix rejected")
	for type in ["boss","treasure","challenge"]:
		var r := _room(tuning,type)
		r["room_affix"] = "dark"
		t.check("ROOM_AFFIX_NOT_ALLOWED" in _codes(_verdict(r,tuning)),"AD-241 affix not allowed on %s" % type)
	var no_tiles := base.duplicate(true)
	no_tiles["room_affix"] = "unstable"
	t.check("ROOM_AFFIX_INVALID" in _codes(_verdict(no_tiles,tuning)),"AD-241 unstable without cracked_tiles rejected")
	var thin := unstable.duplicate(true)
	thin["layout"]["cracked_tiles"] = [[ex+300,cy-200,40,80]]
	t.check("ROOM_AFFIX_INVALID" in _codes(_verdict(thin,tuning)),"AD-241 cracked tile under 56 u rejected")
	var cut := unstable.duplicate(true)
	cut["layout"]["cracked_tiles"] = [[ex+300,-200,80,1400]]
	t.check("ROOM_AFFIX_INVALID" in _codes(_verdict(cut,tuning)),"AD-241 unstable collapse cutting the exit rejected")
	var no_wisp := base.duplicate(true)
	no_wisp["room_affix"] = "haunted"
	no_wisp["waves"][0]["enemies"].remove_at(0)
	t.check("ROOM_AFFIX_INVALID" in _codes(_verdict(no_wisp,tuning)),"AD-241 haunted without wisp rejected")

func _tuning() -> Dictionary:
	return JSON.parse_string(FileAccess.get_file_as_string("res://combat/combat_tuning_v1.json"))

## Session + director for a synthetic room, the way run_flow builds a combat room. The player is made unkillable.
func _encounter(room: Dictionary, tuning: Dictionary) -> Array:
	var copy: Dictionary = room.duplicate(true)
	copy["min_spawn_distance"] = 45
	copy["player_radius"] = 22
	copy["grid_step"] = 20
	var template = Room.new()
	template.initialize(copy,tuning["arena"],tuning["enemies"].keys())
	var s = Session.new(241,"empty",0)
	s.sim.actor.health.maximum = 1.0e9
	s.sim.actor.health.current = 1.0e9
	s.sim.actor.position = template.marker("entrance")
	var d = Director.new()
	d.initialize(template,s,8)
	return [s,d]

func _tick(s, d, count: int = 1) -> void:
	for i in count:
		s.step()
		d.advance()

func _events(d, name: String) -> int:
	var n := 0
	for entry in d.log:
		if str(entry["event"]) == name:
			n += 1
	return n

func test_ad_241_dark_light_radius(t) -> void:
	var tuning := _tuning()
	var dark := _room(tuning)
	dark["room_affix"] = "dark"
	var pair := _encounter(dark,tuning)
	t.equal(pair[1].light_radius(),220.0,"AD-241 dark room light radius 220 u (director)")
	t.equal(pair[0].light_radius(),220.0,"AD-241 dark room light radius 220 u (session)")
	var plain := _encounter(_room(tuning),tuning)
	t.equal(plain[1].light_radius(),0.0,"AD-241 room without affix has unlimited light")
	var fresh = Session.new(241,"empty",0)
	t.equal(fresh.light_radius(),0.0,"AD-241 session outside a run has unlimited light")

func test_ad_241_unstable_tiles(t) -> void:
	var tuning := _tuning()
	var room := _room(tuning)
	var cy: float = room["entrance"][1]
	var ex: float = room["entrance"][0]
	room["room_affix"] = "unstable"
	room["layout"]["cracked_tiles"] = [[ex+300,cy-200,80,80],[ex+300,cy+120,80,80]]
	var pair := _encounter(room,tuning)
	var s = pair[0]
	var d = pair[1]
	var affix = s.room_affix
	var center := Vector2(ex+340,cy-160)
	t.check(affix.tiles.size() == 2 and affix.tiles[0]["state"] == "idle","AD-241 cracked tiles start idle")
	_tick(s,d,30)
	t.check(affix.tiles[0]["state"] == "idle","AD-241 cracked tile stays idle until stepped on")
	t.check(s.world.valid_position(center,22.0),"AD-241 idle cracked tile is walkable")
	s.sim.actor.position = center
	_tick(s,d)
	var stepped: int = s.sim.clock.tick
	t.check(affix.tiles[0]["state"] == "telegraph","AD-241 tile telegraphs right after the first step")
	s.sim.actor.position = Vector2(ex,cy)
	while s.sim.clock.tick-stepped < 119:
		_tick(s,d)
	t.check(affix.tiles[0]["state"] == "telegraph" and s.world.valid_position(center,22.0),"AD-241 tile still walkable 1 tick before collapse")
	_tick(s,d)
	t.check(affix.tiles[0]["state"] == "collapse","AD-241 tile collapses exactly 120 ticks after the step")
	t.check(not s.world.valid_position(center,22.0),"AD-241 collapsed tile blocks walking")
	var outside := Vector2(ex+260,cy-160)
	t.check(s.world.move_body(outside,Vector2(80,0),22.0).x <= ex+300-22.0+0.01,"AD-241 player cannot walk onto a collapsed tile")
	_tick(s,d,20)
	t.check(affix.tiles[0]["state"] == "pit","AD-241 collapsed tile settles into a pit")
	_tick(s,d,300)
	t.check(affix.tiles[1]["state"] == "idle" and s.world.valid_position(Vector2(ex+340,cy+160),22.0),"AD-241 tile never stepped on never collapses")
	t.check(RoomAffixesStates() == ["idle","telegraph","collapse","pit"],"AD-241 tile state names fixed for art")
	# Standing on the tile when it collapses: pushed to the nearest open spot, no fall damage (no AD-202 fall rule).
	var stay := _encounter(room,tuning)
	stay[0].sim.actor.position = center
	var hp: float = stay[0].sim.actor.health.current
	var hits: int = stay[0].attacks_received
	_tick(stay[0],stay[1],121)
	t.check(stay[0].room_affix.tiles[0]["state"] == "collapse","AD-241 occupied tile still collapses")
	t.check(stay[0].world.valid_position(stay[0].sim.actor.position,stay[0].sim.actor.radius) and not stay[0].room_affix._overlaps(stay[0].room_affix.tiles[0]["rect"],stay[0].sim.actor.position,stay[0].sim.actor.radius),"AD-241 player on a collapsing tile is pushed to a valid spot")
	t.check(stay[0].sim.actor.health.current == hp or stay[0].attacks_received > hits,"AD-241 collapse itself deals no damage")
	var again := _encounter(room,tuning)
	again[0].sim.actor.position = center
	_tick(again[0],again[1],121)
	t.check(again[0].sim.actor.position == stay[0].sim.actor.position and again[0].room_affix.events == stay[0].room_affix.events,"AD-241 unstable collapse is deterministic")

func RoomAffixesStates() -> Array:
	return preload("res://world/room_affixes.gd").TILE_STATES

func _kill_all(s) -> void:
	for enemy in s.enemies:
		enemy.target.health.current = 0.0

func test_ad_241_haunted_respawn(t) -> void:
	var tuning := _tuning()
	var room := _room(tuning)
	room["room_affix"] = "haunted"
	var pair := _encounter(room,tuning)
	var s = pair[0]
	var d = pair[1]
	var wisp_at := Vector2(float(room["waves"][0]["enemies"][0][1]),float(room["waves"][0]["enemies"][0][2]))
	_kill_all(s)
	_tick(s,d,3)
	t.equal(s.alive_enemies(),0,"AD-241 haunted: every enemy down")
	t.equal(_events(d,"room_clear"),0,"AD-241 haunted: room does not clear while the wisp owes a respawn")
	_tick(s,d,90)
	t.equal(_events(d,"haunted_respawn"),1,"AD-241 haunted: wisp respawns once after the delay")
	var back = s.enemies[s.enemies.size()-1]
	t.check(back.kind == "lantern_wisp" and back.target.alive() and back.target.position == wisp_at,"AD-241 haunted: respawn at the original spawn")
	t.equal(_events(d,"room_clear"),0,"AD-241 haunted: room waits for the respawned wisp")
	_kill_all(s)
	_tick(s,d,200)
	t.equal(_events(d,"haunted_respawn"),1,"AD-241 haunted: respawned wisp never comes back a second time")
	t.equal(d.clear_emissions,1,"AD-241 haunted: room clears exactly once after the second wisp dies")
	t.equal(s.state,"cleared","AD-241 haunted: session cleared")

func test_ad_241_none_room_unchanged(t) -> void:
	var tuning := _tuning()
	var logs: Array = []
	for affix in ["", "none"]:
		var room := _room(tuning)
		if affix != "":
			room["room_affix"] = affix
		var pair := _encounter(room,tuning)
		_kill_all(pair[0])
		_tick(pair[0],pair[1],5)
		var events: Array = []
		for entry in pair[1].log:
			events.append(str(entry["event"]))
		t.check(events == ["wave_spawn","room_clear"],"AD-241 affix '%s' room log is wave_spawn then room_clear %s" % [affix,str(events)])
		t.check(pair[1].light_radius() == 0.0 and pair[0].room_affix.tiles.is_empty(),"AD-241 affix '%s' room has no darkness or cracked tiles" % affix)
		logs.append(pair[1].log)
	t.check(logs[0] == logs[1],"AD-241 room_affix none logs the same as a room without the field")

func _run_doc() -> Dictionary:
	return JSON.parse_string(FileAccess.get_file_as_string("res://world/data/run_v2.json"))

## Combat rooms of a stage pool plus their affix list; the boss room never carries one.
func test_ad_241_ruins_pool(t) -> void:
	var doc := _run_doc()
	var tuning := _tuning()
	var env_data = load("res://world/env_props.gd").load_data()
	var stage: Dictionary = doc["stages"][0]
	var pool: Array = stage["pool"]
	t.equal(pool.size(),12,"AD-241 ruins pool has 12 rooms")
	var kinds: Dictionary = {}
	var affixes: Dictionary = {}
	var affixed := 0
	for id in pool + [stage["optional_room"],stage["boss_room"]]:
		t.check(doc["room_templates"].has(id),"AD-241 ruins template %s exists" % id)
		var room: Dictionary = doc["room_templates"][id]
		var verdict := Room.new().initialize(room,tuning["arena"],tuning["enemies"].keys())
		t.check(bool(verdict["ok"]),"AD-241 %s validates (%s)" % [id,str(verdict["issues"])])
		if str(room["type"]) == "combat":
			var report := Room.rule_report(room,tuning["arena"],env_data,doc["room_rules"])
			t.check(bool(report["ok"]),"AD-241 %s passes rule_report (%s)" % [id,str(report["issues"])])
		for wave in room.get("waves",[]):
			t.check((wave["enemies"] as Array).size() <= int(doc["max_active_enemies"]),"AD-241 %s wave within the active cap" % id)
			for e in wave["enemies"]:
				kinds[e[0]] = true
		var affix := str(room.get("room_affix","none"))
		if id in pool and affix != "none":
			affixed += 1
			affixes[affix] = true
	t.check(kinds.size() >= 7,"AD-241 ruins pool spawns >= 7 enemy kinds (%s)" % str(kinds.keys()))
	for k in ["rune_sentry","grave_mite","ash_censer","lantern_wisp"]:
		t.check(kinds.has(k),"AD-241 ruins uses %s" % k)
	var share := float(affixed)/float(pool.size())
	t.check(share >= 0.25 and share <= 0.40,"AD-241 ruins affix share %.2f within 0.25-0.40" % share)
	for k in ["dark","unstable","haunted"]:
		t.check(affixes.has(k),"AD-241 ruins has a %s room" % k)
	t.check(not doc["room_templates"][stage["boss_room"]].has("room_affix"),"AD-241 ruins boss room has no affix")

const Flow = preload("res://world/run_flow.gd")

func test_ad_241_cistern_pool(t) -> void:
	var doc := _run_doc()
	var tuning := _tuning()
	var env_data = load("res://world/env_props.gd").load_data()
	var stage: Dictionary = doc["stages"][1]
	var file: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://world/data/rooms_cistern_v1.json"))
	var pool: Array = stage["pool"]
	t.equal(pool.size(),14,"AD-241 cistern pool has 14 rooms")
	t.check(pool == file["pool"] and int(file["rules"]["pool_size"]) == 14,"AD-241 stage pool matches the rooms file pool")
	var templates := Flow.merged_templates(doc)
	var kinds: Dictionary = {}
	var affixes: Dictionary = {}
	var affixed := 0
	for id in pool + [stage["optional_room"],stage["boss_room"]]:
		t.check(templates.has(id),"AD-241 cistern template %s exists" % id)
		var room: Dictionary = templates[id]
		var verdict := Room.new().initialize(room,tuning["arena"],tuning["enemies"].keys())
		t.check(bool(verdict["ok"]),"AD-241 %s validates (%s)" % [id,str(verdict["issues"])])
		if id in pool:
			var report := Room.rule_report(room,tuning["arena"],env_data,doc["room_rules"])
			t.check(bool(report["ok"]),"AD-241 %s passes rule_report (%s)" % [id,str(report["issues"])])
			for wave in room["waves"]:
				t.check((wave["enemies"] as Array).size() <= int(doc["max_active_enemies"]),"AD-241 %s wave within the active cap" % id)
				for e in wave["enemies"]:
					kinds[e[0]] = true
			var affix := str(room.get("room_affix","none"))
			if affix != "none":
				affixed += 1
				affixes[affix] = true
		else:
			t.check(str(room.get("room_affix","none")) == "none","AD-241 %s has no room affix" % id)
	t.check(templates["workshop"].get("room_affix","none") == "none","AD-241 workshop has no room affix")
	for k in ["tide_siphon","lamprey"]:
		t.check(kinds.has(k),"AD-241 cistern uses %s" % k)
	t.check(kinds.size() >= 7,"AD-241 cistern pool spawns >= 7 enemy kinds (%s)" % str(kinds.keys()))
	var share := float(affixed)/float(pool.size())
	t.check(share >= 0.25 and share <= 0.40,"AD-241 cistern affix share %.2f within 0.25-0.40" % share)
	for k in ["dark","unstable","haunted"]:
		t.check(affixes.has(k),"AD-241 cistern has a %s room" % k)
	for seed_value in [1,2,3,7,42,99,1234]:
		var seq: Array = Flow.build_sequence(doc,seed_value)
		var types: Array = []
		var seen: Dictionary = {}
		for r in seq:
			if int(r["stage"]) == 1 and str(r["id"]) != "cistern_flood_gate": # AD-242 event room
				types.append(str(r["id"]))
				t.check(not seen.has(r["id"]) or str(r["id"]) == "workshop","AD-241 seed %d: no repeated cistern room %s" % [seed_value,r["id"]])
				seen[r["id"]] = true
		var combat := types.filter(func(i): return i in pool)
		t.equal(combat.size(),3,"AD-241 seed %d: 3 cistern combat rooms" % seed_value)
		t.check(types.size() == 6 and types[3] == stage["optional_room"] and types[4] == "workshop" and types[5] == stage["boss_room"],"AD-241 seed %d: optional, workshop, boss follow (%s)" % [seed_value,str(types)])
