extends RefCounted
## AD-150 step 1: environment props sim core (burn, puddle/ice, brazier, breakables), one test per interaction.
const Session = preload("res://combat/combat_session.gd")
const EnvProps = preload("res://world/env_props.gd")
const Room = preload("res://world/room_template.gd")
const Flow = preload("res://world/run_flow.gd")
const POOLS := ["res://world/data/rooms_ruins_v1.json","res://world/data/rooms_cistern_v1.json"]

# Same free strip as test_ad_cistern: arena walls end at y=735, so y 770-870 is open. The player stands at (100,820) and shoots right.
const SPOT := Vector2(100,820)

func run(t) -> void:
	_crate(t)
	_cobweb(t)
	_puddle_wet_conduct(t)
	_ice(t)
	_brazier(t)
	_urn(t)
	_cracked_wall(t)
	_validate(t)
	_determinism(t)
	_templates(t)
	_template_negatives(t)
	_run_flow_urn(t)

func _shot(essence: String) -> Dictionary:
	return {"schema_version":1,"formula_id":"test."+essence,"display_name":essence,
		"root":{"essence_id":essence,"manifestation_id":"form.projectile","modifier_ids":[],"params":{}}}

func _rig(entries: Array):
	var s = Session.new(150,"empty",0)
	s.defer_clear = true
	s.set_env_props(entries)
	s.sim.actor.position = SPOT
	return s

func _shoot(s, essence: String) -> void:
	# Sessions lock editing and slot 0 is the builtin bolt; test shots go through slot 1.
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

func _tough(enemy) -> void:
	enemy.target.health.maximum = 5000.0
	enemy.target.health.reset()

func _crate(t) -> void:
	var rect := Rect2(400,790,40,60)
	var s = _rig([{"id":"c1","kind":"crate","rect":[400,790,40,60]}])
	var kind: Dictionary = s.env_props.kinds["crate"]
	t.check(s.world.walls.has(rect) and s.sim.collision_walls.has(rect),"AD-150 crate: solid for walking and spells")
	t.check(not s.world.valid_position(Vector2(420,820),14.0),"AD-150 crate: blocks walking")
	_shoot(s,"essence.fire")
	_run(s,50)
	t.check(_state(s,"c1") == "burning","AD-150 crate: Fire projectile ignites it")
	_run(s,int(kind["burn_ticks"])+2)
	t.check(_state(s,"c1") == "destroyed","AD-150 crate: burns out after burn_ticks")
	t.check(not s.world.walls.has(rect) and not s.sim.collision_walls.has(rect),"AD-150 crate: walking and projectile geometry freed")
	t.check(s.world.valid_position(Vector2(420,820),14.0),"AD-150 crate: walkable after burning")
	var water = _rig([{"id":"c1","kind":"crate","rect":[400,790,40,60]}])
	_shoot(water,"essence.water")
	_run(water,60)
	t.check(_state(water,"c1") == "intact","AD-150 crate: non-Fire does not ignite it")

func _cobweb(t) -> void:
	var s = _rig([{"id":"w1","kind":"cobweb","rect":[400,790,48,60]}])
	var kind: Dictionary = s.env_props.kinds["cobweb"]
	_shoot(s,"essence.water")
	_run(s,60)
	t.check(s.sim.active.is_empty() and _state(s,"w1") == "intact","AD-150 cobweb: catches a non-Fire projectile")
	t.check(s.world.valid_position(Vector2(424,820),14.0),"AD-150 cobweb: does not block walking")
	_shoot(s,"essence.fire")
	_run(s,50)
	t.check(_state(s,"w1") == "burning","AD-150 cobweb: Fire ignites it")
	_run(s,int(kind["burn_ticks"])+2)
	t.check(_state(s,"w1") == "destroyed" and not s.sim.collision_walls.has(Rect2(400,790,48,60)),"AD-150 cobweb: burns away and stops catching spells")
	_shoot(s,"essence.water")
	_run(s,5)
	t.check(not s.sim.active.is_empty() and s.sim.active[0]["effect"].position.x > 120.0,"AD-150 cobweb: projectiles fly freely once burned")

func _puddle_wet_conduct(t) -> void:
	var s = _rig([{"id":"p1","kind":"puddle","rect":[300,770,300,100]}])
	t.check(s.water != null and s.sim.resolver.water == s.water and s.water.in_water(Vector2(450,820)),"AD-150 puddle: installs shallow water")
	var a = s.spawn_enemy("bone_thrall",Vector2(380,820))
	var b = s.spawn_enemy("bone_thrall",Vector2(520,820))
	_tough(a)
	_tough(b)
	_run(s,int(s.data["water"]["wet_interval_ticks"]))
	t.check(a.target.status.has("wet",s.sim.clock.tick),"AD-150 puddle: enemy standing in it gets Wet")
	t.check(not s.sim.actor.status.has("wet",s.sim.clock.tick),"AD-150 puddle: player outside stays dry")
	var payload := {"team":s.sim.actor.team,"essence_id":"essence.lightning","damage":10.0,"cast_id":1,"root_cast_id":1}
	var out: Dictionary = s.sim.resolver.resolve(payload,a.target,s.sim.targets,s.sim.clock.tick)
	t.check(not out["reaction"].is_empty() and int(out["reaction"]["target_id"]) == b.target.id,"AD-150 puddle: Lightning arcs between two targets in it")

func _ice(t) -> void:
	var entries := [{"id":"p1","kind":"puddle","rect":[300,770,300,100]}]
	var s = _rig(entries)
	var kind: Dictionary = s.env_props.kinds["puddle"]
	var control = _rig(entries)
	_shoot(s,"essence.cold")
	while not s.sim.active.is_empty() and s.sim.clock.tick < 200:
		s.step()
	t.check(_state(s,"p1") == "frozen" and s.env_props.on_ice(Vector2(450,820)),"AD-150 ice: Cold turns the puddle to ice")
	t.check(not s.water.in_water(Vector2(450,820)),"AD-150 ice: frozen puddle stops being water")
	var frozen_at: int = s.sim.clock.tick
	while control.sim.clock.tick < frozen_at:
		control.step()
	var ice = s.spawn_enemy("bone_thrall",Vector2(450,820))
	var dry = control.spawn_enemy("bone_thrall",Vector2(450,820))
	_tough(ice)
	_tough(dry)
	_run(s,10)
	_run(control,10)
	s.sim.actor.position = Vector2(900,820)
	control.sim.actor.position = Vector2(900,820)
	_run(s,2)
	_run(control,2)
	t.check(ice.last_displacement.x < 0.0 and dry.last_displacement.x > 0.0,"AD-150 ice: sliding enemy keeps its old heading, normal enemy turns")
	_run(s,10)
	_run(control,10)
	t.check(absf(ice.target.position.x-dry.target.position.x) > 1.0,"AD-150 ice: displacement differs from the non-ice case")
	_run(s,int(kind["ice_ticks"]))
	t.check(_state(s,"p1") == "intact" and not s.env_props.on_ice(Vector2(450,820)) and s.water.in_water(Vector2(450,820)),"AD-150 ice: reverts to a puddle after ice_ticks")

func _brazier(t) -> void:
	for essence in ["essence.water","essence.lightning"]:
		var s = _rig([{"id":"b1","kind":"brazier","position":[300,820]}])
		var foe = s.spawn_enemy("bone_thrall",Vector2(520,820))
		_tough(foe)
		_shoot(s,essence)
		_run(s,60)
		t.check(foe.target.status.has("burning",s.sim.clock.tick),"AD-150 brazier: %s projectile ignites its target" % essence)
		t.check(s.sim.trace_json().contains("burning:applied"),"AD-150 brazier: %s ignition is traced" % essence)
		var plain = _rig([])
		var other = plain.spawn_enemy("bone_thrall",Vector2(520,820))
		_tough(other)
		_shoot(plain,essence)
		_run(plain,60)
		t.check(not other.target.status.has("burning",plain.sim.clock.tick),"AD-150 brazier: %s without a brazier does not burn" % essence)

func _urn(t) -> void:
	var s = _rig([{"id":"u1","kind":"urn","position":[400,820]}])
	_shoot(s,"essence.fire")
	_run(s,60)
	t.check(_state(s,"u1") == "intact" and s.env_props.pending_coins == 0,"AD-150 urn: non-Force does not break it")
	_shoot(s,"essence.force")
	_run(s,60)
	t.check(_state(s,"u1") == "destroyed","AD-150 urn: Force breaks it")
	t.check(s.env_props.pending_coins == int(s.env_props.kinds["urn"]["coins"]),"AD-150 urn: drops its coins")
	t.check(s.env_props.events.size() == 1 and s.env_props.events[0]["action"] == "break","AD-150 urn: break event logged")

func _cracked_wall(t) -> void:
	var rect := Rect2(400,780,48,80)
	var s = _rig([{"id":"k1","kind":"cracked_wall","rect":[400,780,48,80]}])
	t.check(s.world.walls.has(rect) and s.sim.collision_walls.has(rect),"AD-150 cracked wall: solid before breaking")
	_shoot(s,"essence.fire")
	_run(s,60)
	t.check(_state(s,"k1") == "intact","AD-150 cracked wall: Fire does not break it")
	_shoot(s,"essence.force")
	_run(s,60)
	t.check(_state(s,"k1") == "destroyed","AD-150 cracked wall: Force breaks it")
	t.check(not s.world.walls.has(rect) and not s.sim.collision_walls.has(rect),"AD-150 cracked wall: rect removed")
	t.check(s.env_props.pending_coins == int(s.env_props.kinds["cracked_wall"]["coins"]),"AD-150 cracked wall: secret cache coins")

func _validate(t) -> void:
	var kinds: Dictionary = EnvProps.load_data()["kinds"]
	t.check(EnvProps.validate([{"id":"a","kind":"crate","rect":[0,0,40,40]},{"id":"b","kind":"urn","position":[5,5]}],kinds).is_empty(),"AD-150 validate: good layout passes")
	var bad: Array = [
		[{"id":"a","kind":"lava","rect":[0,0,10,10]}],
		[{"id":"a","kind":"crate","rect":[0,0,0,10]}],
		[{"id":"a","kind":"urn"}],
		[{"id":"a","kind":"crate","rect":[0,0,10,10]},{"id":"a","kind":"crate","rect":[50,0,10,10]}],
		[{"kind":"crate","rect":[0,0,10,10]}],
		["crate"]]
	for entries in bad:
		var issues := EnvProps.validate(entries,kinds)
		t.check(not issues.is_empty() and str(issues[0]["code"]) == "ENV_PROP_INVALID","AD-150 validate: rejects %s" % str(entries))

func _scenario(entries: Array):
	var s = Session.new(150,"empty",0)
	s.defer_clear = true
	if not entries.is_empty():
		s.set_env_props(entries)
	s.sim.actor.position = SPOT
	var foe = s.spawn_enemy("bone_thrall",Vector2(520,820))
	_tough(foe)
	_shoot(s,"essence.fire")
	_run(s,30)
	_shoot(s,"essence.water")
	_run(s,60)
	return s

## Session snapshot without the wall-clock frame timer.
func _stable(s) -> Dictionary:
	var snap: Dictionary = s.snapshot()
	snap.erase("frame_ms")
	return snap

func _determinism(t) -> void:
	var layout := [{"id":"c1","kind":"crate","rect":[300,790,40,60]},{"id":"b1","kind":"brazier","position":[200,820]},
		{"id":"p1","kind":"puddle","rect":[420,770,100,100]}]
	var a = _scenario(layout)
	var b = _scenario(layout)
	t.equal(a.env_props.snapshot(),b.env_props.snapshot(),"AD-150 determinism: identical env snapshots")
	t.equal(a.sim.trace_json(),b.sim.trace_json(),"AD-150 determinism: identical traces")
	t.equal(_stable(a),_stable(b),"AD-150 determinism: identical session snapshots")
	# No env props: the session must behave exactly as before the feature.
	var plain = _scenario([])
	var empty = Session.new(150,"empty",0)
	empty.set_env_props([])
	t.check(plain.env_props == null and empty.env_props == null,"AD-150 determinism: no props means no env system")
	var far = _scenario([{"id":"u1","kind":"urn","position":[1200,100]}])
	t.equal(far.sim.trace_json(),plain.sim.trace_json(),"AD-150 determinism: untouched props leave the trace unchanged")
	t.equal(far.snapshot()["foes"],plain.snapshot()["foes"],"AD-150 determinism: untouched props leave enemy state unchanged")
	plain.restart()
	t.check(plain.env_props == null,"AD-150 determinism: restart clears env props")

func _tuning() -> Dictionary:
	return JSON.parse_string(FileAccess.get_file_as_string("res://combat/combat_tuning_v1.json"))

func _initialize(template: Dictionary, rules: Dictionary, tuning: Dictionary) -> Dictionary:
	var copy: Dictionary = template.duplicate(true)
	for key in ["min_spawn_distance","player_radius","grid_step"]:
		if rules.has(key):
			copy[key] = rules[key]
	return Room.new().initialize(copy,tuning["arena"],tuning["enemies"].keys())

func _templates(t) -> void:
	var tuning := _tuning()
	for path in POOLS:
		var doc: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(path))
		var with_props := 0
		var seen: Dictionary = {}
		for id in doc["room_templates"]:
			var template: Dictionary = doc["room_templates"][id]
			t.check(bool(_initialize(template,doc["rules"],tuning)["ok"]),"AD-150 templates: %s initializes" % id)
			var props = template.get("layout",{}).get("env_props",[])
			if not props.is_empty():
				with_props += 1
				for entry in props:
					seen[str(entry["kind"])] = true
		t.check(with_props >= 3,"AD-150 templates: %s has at least 3 templates with env props" % path.get_file())
		t.equal(seen.keys().size(),EnvProps.KIND_IDS.size(),"AD-150 templates: %s covers every prop kind" % path.get_file())

func _template_negatives(t) -> void:
	var tuning := _tuning()
	var doc: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(POOLS[0]))
	var base: Dictionary = doc["room_templates"]["ruins_p01"]
	var cases := {
		"on exit":[[{"id":"c1","kind":"crate","rect":[1200,430,40,40]}],"ROOM_ENV_PROP_BLOCKS"],
		"urn on entrance":[[{"id":"u1","kind":"urn","position":[185,450]}],"ROOM_ENV_PROP_BLOCKS"],
		"unknown kind":[[{"id":"x1","kind":"boulder","rect":[600,100,40,40]}],"ENV_PROP_INVALID"],
		"on spawn":[[{"id":"c1","kind":"crate","rect":[400,180,40,40]}],"ROOM_SPAWN_BLOCKED"],
	}
	for label in cases:
		var template: Dictionary = base.duplicate(true)
		template["layout"]["env_props"] = cases[label][0]
		var verdict := _initialize(template,doc["rules"],tuning)
		var codes: Array = []
		for issue in verdict["issues"]:
			codes.append(str(issue["code"]))
		t.check(not bool(verdict["ok"]) and codes.has(cases[label][1]),"AD-150 templates: crate/prop %s gives %s" % [label,cases[label][1]])
	var bad := base.duplicate(true)
	bad["layout"]["env_props"] = [{"id":"x1","kind":"boulder","rect":[600,100,40,40]}]
	var issue = _initialize(bad,doc["rules"],tuning)["issues"][0]
	t.equal(str(issue["path"]),"layout.env_props[0].kind","AD-150 templates: issue path prefixed with layout.")

func _run_flow_urn(t) -> void:
	var flow = Flow.new(150,Flow.CONFIG_V2)
	var entry: Dictionary = Flow.merged_templates(flow.config)["cistern_p05"].duplicate(true)
	t.check(bool(flow._build_room(entry)["ok"]),"AD-150 run flow: props template builds")
	t.check(flow.session.env_props != null,"AD-150 run flow: props template installs env props")
	flow.state = "fighting"
	var coins: int = int(flow.session.env_props.kinds["urn"]["coins"])
	flow.session.sim.actor.position = Vector2(420,300)
	flow.session.sim.loadout.unlocked.append("essence.force") # a fresh run has not unlocked Force yet
	_shoot(flow.session,"essence.force")
	var before: int = flow.run.currency
	for i in 40:
		flow.step()
	t.equal(_state(flow.session,"urn1"),"destroyed","AD-150 run flow: Force hit breaks the urn")
	t.equal(flow.run.currency-before,coins,"AD-150 run flow: urn coins join the run purse")
	t.equal(flow.session.env_props.pending_coins,0,"AD-150 run flow: pending coins are drained")
