extends RefCounted
## AD-202 step 1: Ruins cover kinds, layout.pits (walking blockers) and layout.arena_walls (shared-wall opt-out).
## AD-202 step 2: Room.rule_report (docs/rooms/ROOM_RULES.md) on synthetic rooms.
const Session = preload("res://combat/combat_session.gd")
const EnvProps = preload("res://world/env_props.gd")
const Geometry = preload("res://world/arena_geometry.gd")
const Room = preload("res://world/room_template.gd")
const Flow = preload("res://world/run_flow.gd")
const Art = preload("res://ui/pixel_art_renderer.gd")
const POOLS := ["res://world/data/rooms_ruins_v1.json","res://world/data/rooms_cistern_v1.json"]
const COVER_KINDS := ["pillar","cracked_pillar","rubble","sarcophagus","broken_wall","column"]

# Arena walls end at y=735, so the strip y 770-870 is free for shots. The player stands at SPOT and shoots right.
const SPOT := Vector2(100,820)

func run(t) -> void:
	_kinds(t)
	_solid_cover(t)
	_projectiles_and_force(t)
	_pits(t)
	_arena_walls(t)
	_run_flow(t)
	_templates_still_valid(t)
	_placeholder_frames(t)
	_rule_report(t)

func _tuning() -> Dictionary:
	return JSON.parse_string(FileAccess.get_file_as_string("res://combat/combat_tuning_v1.json"))

func _room(layout: Dictionary) -> Dictionary:
	return {"id":"synthetic_ad202","stage":0,"room":0,"type":"combat","scene":"res://scenes/run.tscn",
		"entrance":[185,450],"exit":[1220,450],"reward":[1150,450],"layout":layout,
		"waves":[{"trigger":"start","delay_ticks":0,"enemies":[["bone_thrall",420,200]]}]}

func _verdict(room: Dictionary) -> Dictionary:
	var tuning := _tuning()
	return Room.new().initialize(room,tuning["arena"],tuning["enemies"].keys())

func _codes(verdict: Dictionary) -> Array:
	var codes: Array = []
	for issue in verdict["issues"]:
		codes.append(str(issue["code"]))
	return codes

func _shot(essence: String) -> Dictionary:
	return {"schema_version":1,"formula_id":"test."+essence,"display_name":essence,
		"root":{"essence_id":essence,"manifestation_id":"form.projectile","modifier_ids":[],"params":{}}}

func _rig(entries: Array):
	var s = Session.new(202,"empty",0)
	s.defer_clear = true
	s.set_env_props(entries)
	s.sim.actor.position = SPOT
	return s

func _shoot(s, essence: String) -> void:
	s.sim.loadout.allow_edit = true
	s.sim.equip(1,_shot(essence))
	s.sim.loadout.slots[1]["cooldown"] = 0
	s.sim.mana = 120.0
	s.sim.try_cast(1,s.sim.actor.position,Vector2.RIGHT)

func _run(s, ticks: int) -> void:
	for i in ticks:
		s.step()

func _state(s, id: String) -> String:
	for prop in s.env_props.props:
		if prop["id"] == id:
			return str(prop["state"])
	return ""

func _kinds(t) -> void:
	var kinds: Dictionary = EnvProps.load_data()["kinds"]
	for kind in COVER_KINDS:
		t.check(EnvProps.KIND_IDS.has(kind) and kinds.has(kind),"AD-202 kinds: %s registered" % kind)
		t.check(bool(kinds[kind]["solid_walk"]) and bool(kinds[kind]["blocks_spells"]),"AD-202 kinds: %s blocks walking and spells" % kind)
		var breakable := (kinds[kind].get("break_by",[]) as Array).has("essence.force")
		t.equal(breakable,kind in ["cracked_pillar","broken_wall"],"AD-202 kinds: %s Force-breakable only when intended" % kind)
	t.equal(kinds["column"]["shape"],"circle","AD-202 kinds: column is a circle")
	t.equal(int(kinds["cracked_pillar"]["coins"]),2,"AD-202 kinds: cracked pillar coins")
	t.equal(int(kinds["broken_wall"]["coins"]),4,"AD-202 kinds: broken wall coins")

func _solid_cover(t) -> void:
	var room := _room({"env_props":[{"id":"p1","kind":"pillar","rect":[400,300,48,48]},
		{"id":"c1","kind":"column","position":[800,600]}]})
	t.check(bool(_verdict(room)["ok"]),"AD-202 cover: room with pillar and column validates")
	var s = _rig(room["layout"]["env_props"])
	t.check(not s.world.valid_position(Vector2(424,324),22),"AD-202 cover: no walking inside the pillar")
	t.check(not s.world.valid_position(Vector2(800,600),22),"AD-202 cover: no walking inside the column")
	t.check(s.world.valid_position(Vector2(424,420),22),"AD-202 cover: open floor near the pillar stays walkable")
	var bare := Geometry.new(_tuning()["arena"])
	t.check(bare.valid_position(Vector2(424,324),22),"AD-202 cover: that spot is open without the prop")

func _projectiles_and_force(t) -> void:
	# An urn behind the cover breaks to Force only when the shot reaches it; the control rig has no cover.
	var urn := {"id":"u1","kind":"urn","position":[600,820]}
	var control = _rig([urn])
	_shoot(control,"essence.force")
	_run(control,90)
	t.equal(_state(control,"u1"),"destroyed","AD-202 projectile: control shot reaches the urn")
	for kind in ["pillar","cracked_pillar","broken_wall"]:
		var rect := [300,800,48,40] if kind != "broken_wall" else [300,804,96,32]
		var wall := Rect2(rect[0],rect[1],rect[2],rect[3])
		var s = _rig([{"id":"w1","kind":kind,"rect":rect},urn] if kind == "pillar" else [{"id":"w1","kind":kind,"rect":rect}])
		_shoot(s,"essence.force")
		_run(s,90)
		if kind == "pillar":
			t.equal(_state(s,"w1"),"intact","AD-202 force: pillar survives Force")
			t.check(s.world.walls.has(wall) and s.sim.collision_walls.has(wall),"AD-202 force: pillar rect stays solid")
			t.equal(_state(s,"u1"),"intact","AD-202 projectile: pillar blocks the shot")
		else:
			t.equal(_state(s,"w1"),"destroyed","AD-202 force: Force destroys %s" % kind)
			t.check(not s.world.walls.has(wall) and not s.sim.collision_walls.has(wall),"AD-202 force: %s rect removed" % kind)
			t.equal(s.env_props.pending_coins,int(s.env_props.kinds[kind]["coins"]),"AD-202 force: %s coins" % kind)
	var fire = _rig([{"id":"k1","kind":"cracked_pillar","rect":[300,800,48,40]}])
	_shoot(fire,"essence.fire")
	_run(fire,90)
	t.equal(_state(fire,"k1"),"intact","AD-202 force: Fire does not break a cracked pillar")

func _pits(t) -> void:
	var wall_pit := [700,0,60,900] # full height: nothing east of it can be reached on foot
	var room := _room({"pits":[wall_pit]})
	room["waves"][0]["enemies"] = [["bone_thrall",900,200]]
	room["exit"] = [660,450]
	room["reward"] = [620,450]
	var verdict := _verdict(room)
	t.check(not bool(verdict["ok"]) and _codes(verdict).has("ROOM_SPAWN_UNREACHABLE"),"AD-202 pits: spawn behind a full-height pit is unreachable")
	room["layout"]["pits"] = [[700,0,60,400]]
	t.check(bool(_verdict(room)["ok"]),"AD-202 pits: a pit with a way round validates")
	for bad in [[[700,0,60]],[[700,0,0,400]],[["a",0,60,400]],"x"]:
		room["layout"]["pits"] = bad
		var v := _verdict(room)
		t.check(not bool(v["ok"]) and _codes(v).has("ROOM_LAYOUT_INVALID") and str(v["issues"][0]["path"]) == "layout.pits","AD-202 pits: invalid entry %s rejected" % str(bad))
	var world := Geometry.new(_tuning()["arena"])
	world.add_ground_blockers([Rect2(700,0,60,900)])
	var from := Vector2(660,800)
	var to := Vector2(800,800)
	t.check(world.clear_sight(from,to,4.0),"AD-202 pits: sight crosses the pit")
	t.check(not world.walk_clear(from,to,4.0) and not world.valid_position(Vector2(730,800),22),"AD-202 pits: walking does not")

func _arena_walls(t) -> void:
	# [600,270] sits inside the shared wall [570,165,64,210].
	var room := _room({})
	room["reward"] = [600,270]
	var omitted := _verdict(room)
	t.check(not bool(omitted["ok"]) and _codes(omitted).has("ROOM_MARKER_BLOCKED"),"AD-202 arena_walls: omitted flag keeps shared walls")
	room["layout"] = {"arena_walls":true}
	t.check(_codes(_verdict(room)).has("ROOM_MARKER_BLOCKED"),"AD-202 arena_walls: true keeps shared walls")
	room["layout"] = {"arena_walls":false}
	t.check(bool(_verdict(room)["ok"]),"AD-202 arena_walls: false frees the old shared-wall positions")
	room["layout"] = {"arena_walls":false,"walls":[[900,100,40,40]]}
	room["reward"] = [1150,450]
	t.check(bool(_verdict(room)["ok"]),"AD-202 arena_walls: layout walls still apply when shared walls are off")
	room["reward"] = [920,120]
	t.check(_codes(_verdict(room)).has("ROOM_MARKER_BLOCKED"),"AD-202 arena_walls: layout walls still block when shared walls are off")

func _run_flow(t) -> void:
	var tuning := _tuning()
	var shared := Rect2(570,165,64,210)
	var flow = Flow.new(202,Flow.CONFIG_V2)
	var plain := _room({})
	t.check(bool(flow._build_room(plain)["ok"]),"AD-202 run flow: plain room builds")
	t.check(flow.session.world.walls.has(shared) and flow.session.sim.collision_walls.has(shared) and flow.session.pits.is_empty(),"AD-202 run flow: shared walls kept, no pits")
	t.equal(flow.session.world.walls.size(),tuning["arena"]["walls"].size(),"AD-202 run flow: plain room wall count unchanged")
	var open := _room({"arena_walls":false,"walls":[[900,100,40,40]],"pits":[[700,0,60,400]],
		"env_props":[{"id":"p1","kind":"pillar","rect":[400,300,48,48]}]})
	open["reward"] = [600,270]
	t.check(bool(flow._build_room(open)["ok"]),"AD-202 run flow: open room builds")
	var session = flow.session
	t.check(not session.world.walls.has(shared) and not session.sim.collision_walls.has(shared),"AD-202 run flow: shared walls removed from world and sim")
	t.equal(session.world.walls.size(),2,"AD-202 run flow: only layout wall and pillar remain")
	t.equal(session.sim.collision_walls.size(),2,"AD-202 run flow: sim walls match")
	t.equal(session.pits,[Rect2(700,0,60,400)],"AD-202 run flow: pits stored for rendering")
	t.check(session.world.ground_blockers.has(Rect2(700,0,60,400)) and not session.sim.collision_walls.has(Rect2(700,0,60,400)),"AD-202 run flow: pits block walking but not spells")
	session.restart()
	t.check(session.pits.is_empty(),"AD-202 run flow: restart clears pits")
	var canvas := Node2D.new()
	canvas.draw.connect(func(): Art.pits(canvas,[Rect2(700,0,60,400)],Vector2.ZERO))
	canvas.notification(CanvasItem.NOTIFICATION_DRAW)
	canvas.free()

func _templates_still_valid(t) -> void:
	var tuning := _tuning()
	for path in POOLS:
		var doc: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(path))
		for id in doc["room_templates"]:
			var copy: Dictionary = doc["room_templates"][id].duplicate(true)
			for key in ["min_spawn_distance","player_radius","grid_step"]:
				if doc["rules"].has(key):
					copy[key] = doc["rules"][key]
			var verdict := Room.new().initialize(copy,tuning["arena"],tuning["enemies"].keys())
			t.check(bool(verdict["ok"]),"AD-202 templates: %s still validates" % id)

func _placeholder_frames(t) -> void:
	var man: Dictionary = Art.export_manifest()
	for kind in COVER_KINDS:
		for stage in [0,2]:
			var fr := Art.env_prop_frame(kind,"intact",false,stage,0)
			t.check(not fr.is_empty() and man.has(fr["stem"]) and man[fr["stem"]]["tags"].has(fr["tag"]),"AD-202 art: %s stage %d maps to an existing frame" % [kind,stage])

# --- AD-202 step 2: rule_report. The good room has an open floor (arena_walls false), 3 cover pieces and a cobweb.
func _rules() -> Dictionary:
	return JSON.parse_string(FileAccess.get_file_as_string("res://world/data/run_v2.json"))["room_rules"]

func _good_room() -> Dictionary:
	var room := _room({"arena_walls":false,"walls":[[500,200,60,60]],
		"env_props":[{"id":"p1","kind":"pillar","rect":[700,500,48,48]},{"id":"p2","kind":"column","position":[900,250]},
			{"id":"w1","kind":"cobweb","rect":[400,600,48,48]}]})
	room["shape"] = "open_hall"
	room["waves"][0]["enemies"] = [["bone_thrall",800,700]]
	return room

func _report(room: Dictionary) -> Dictionary:
	return Room.rule_report(room,_tuning()["arena"],EnvProps.load_data(),_rules())

func _rule_codes(report: Dictionary) -> Array:
	return _codes(report)

func _rule_report(t) -> void:
	var rules := _rules()
	t.equal(int(rules["min_obstacles"]),2,"AD-202 rules: min_obstacles in run_v2 room_rules")
	t.equal(int(rules["max_obstacles"]),5,"AD-202 rules: max_obstacles")
	t.equal((rules["shapes"] as Array).size(),9,"AD-202 rules: nine shape ids")
	t.equal((rules["owner_shapes"] as Array).size(),5,"AD-202 rules: five owner shapes")
	for id in rules["owner_shapes"]:
		t.check((rules["shapes"] as Array).has(id),"AD-202 rules: owner shape %s is allowed" % id)
	for kind in rules["interaction_kinds"]:
		t.check(EnvProps.KIND_IDS.has(kind),"AD-202 rules: interaction kind %s exists" % kind)
	var good := _good_room()
	var report := _report(good)
	t.check(bool(report["ok"]) and report["issues"].is_empty(),"AD-202 rules: compliant room passes (%s)" % str(report["issues"]))
	t.equal(int(report["obstacles"]),3,"AD-202 rules: layout wall + pillar + column count, no shared walls")
	t.equal(int(report["interactions"]),1,"AD-202 rules: cobweb is the one interaction")
	t.equal(str(report["shape"]),"open_hall","AD-202 rules: shape reported")
	t.check(bool(_verdict(good)["ok"]),"AD-202 rules: compliant room also validates in initialize")
	t.equal(_report(good),_report(_good_room()),"AD-202 rules: report is deterministic")
	# Shared arena walls count as obstacles unless arena_walls is false: 3 shared + 1 layout wall = 4.
	var shared := _good_room()
	shared["layout"].erase("arena_walls")
	shared["layout"]["env_props"] = [{"id":"w1","kind":"cobweb","rect":[400,600,48,48]}]
	var shared_report := _report(shared)
	t.equal(int(shared_report["obstacles"]),4,"AD-202 rules: shared arena walls are obstacles")
	t.check(bool(shared_report["ok"]),"AD-202 rules: shared walls + 1 wall + cobweb passes (%s)" % str(shared_report["issues"]))
	# One bad room per code; each must fire its code (and only that code).
	var few := _good_room()
	few["layout"]["walls"] = []
	few["layout"]["env_props"].remove_at(0)
	_expect(t,few,"RULE_OBSTACLES","too few obstacles")
	var many := _good_room()
	many["layout"]["walls"] = [[300,150,40,40],[400,150,40,40],[300,350,40,40],[400,350,40,40]]
	_expect(t,many,"RULE_OBSTACLES","too many obstacles")
	var plain := _good_room()
	plain["layout"]["env_props"] = [{"id":"p1","kind":"pillar","rect":[700,500,48,48]},{"id":"p2","kind":"column","position":[900,250]}]
	_expect(t,plain,"RULE_INTERACTION","no interaction prop")
	var rubble := _good_room()
	rubble["layout"]["env_props"].append({"id":"r1","kind":"rubble","rect":[200,700,64,40]})
	rubble["layout"]["env_props"].remove_at(2)
	_expect(t,rubble,"RULE_INTERACTION","solid cover is not an interaction")
	var shapeless := _good_room()
	shapeless.erase("shape")
	_expect(t,shapeless,"RULE_SHAPE","missing shape")
	var odd := _good_room()
	odd["shape"] = "blob"
	_expect(t,odd,"RULE_SHAPE","unknown shape")
	var near := _good_room()
	near["waves"][0]["enemies"] = [["bone_thrall",800,700],["bone_thrall",300,450]]
	_expect(t,near,"RULE_SPAWN_NEAR_ENTRANCE","spawn 115 from the entrance")
	var exact := _good_room()
	exact["waves"][0]["enemies"] = [["bone_thrall",345,450]]
	t.check(not _rule_codes(_report(exact)).has("RULE_SPAWN_NEAR_ENTRANCE"),"AD-202 rules: spawn exactly 160 away is allowed")
	# Dead corner: a wall at x 80-120 leaves the top-left cell (40,40) with the arena edge on two sides and the wall on a third.
	var corner := _good_room()
	corner["layout"]["walls"] = [[80,0,40,100]]
	var corner_report := _report(corner)
	t.check(_rule_codes(corner_report).has("RULE_DEAD_CORNER"),"AD-202 rules: dead corner flagged (%s)" % str(corner_report["issues"]))
	t.check(bool(_verdict(corner)["ok"]),"AD-202 rules: the dead-corner room still validates in initialize")
	# Pocket: a pit ring closes off a free patch of floor that initialize() never visits (no spawn inside).
	var pocket := _good_room()
	pocket["layout"]["pits"] = [[1000,500,200,40],[1000,700,200,40],[1000,500,40,240],[1160,500,40,240]]
	var pocket_report := _report(pocket)
	t.check(_rule_codes(pocket_report).has("RULE_POCKET_UNREACHABLE"),"AD-202 rules: sealed pocket flagged (%s)" % str(pocket_report["issues"]))
	t.check(bool(_verdict(pocket)["ok"]),"AD-202 rules: the pocket room still validates in initialize")
	# Cells near the entrance side are not mistaken for pockets in the good room.
	t.check(not _rule_codes(report).has("RULE_POCKET_UNREACHABLE") and not _rule_codes(report).has("RULE_DEAD_CORNER"),"AD-202 rules: good room has neither pockets nor dead corners")
	# Treasure room: no waves, so the spawn rule is vacuous.
	var treasure := _good_room()
	treasure["type"] = "treasure"
	treasure["waves"] = []
	t.check(bool(_report(treasure)["ok"]),"AD-202 rules: wave-less treasure room passes")

func _expect(t, room: Dictionary, code: String, label: String) -> void:
	var report := _report(room)
	t.check(not bool(report["ok"]) and _rule_codes(report).has(code),"AD-202 rules: %s -> %s (%s)" % [label,code,str(_rule_codes(report))])
