extends RefCounted
## AD-138 step 1: water tile rules (Wet on standing, deep water blocks walking, Lightning conducts through water).
const Session = preload("res://combat/combat_session.gd")
const WaterTiles = preload("res://world/water_tiles.gd")

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
