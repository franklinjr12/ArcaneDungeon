extends Resource
## TASK-036. Lightweight validated Resource wrapper around versioned room dictionaries.
const Geometry = preload("res://world/arena_geometry.gd")
const WaterTiles = preload("res://world/water_tiles.gd")
const EnvProps = preload("res://world/env_props.gd")
var values: Dictionary = {}
var issues: Array = []

func initialize(room: Dictionary, arena: Dictionary, known_enemy_types: Array) -> Dictionary:
	issues.clear()
	for key in ["id","stage","room","type","scene","entrance","exit","reward","waves"]:
		if not room.has(key):
			issues.append({"code":"ROOM_MISSING_FIELD","path":key,"message":"Room requires "+key})
	if not issues.is_empty():
		return {"ok":false,"issues":issues.duplicate(true)}
	if room["type"] not in ["combat","boss","workshop","treasure","challenge"]:
		issues.append({"code":"ROOM_TYPE_INVALID","path":"type","message":"Unsupported room type"})
	if str(room["scene"]).is_empty() or not ResourceLoader.exists(str(room["scene"])):
		issues.append({"code":"ROOM_SCENE_MISSING","path":"scene","message":"Arena scene unavailable"})
	# AD-128: optional per-room layout adds obstacles on top of the shared arena.
	var merged: Dictionary = arena.duplicate(true)
	var layout = room.get("layout",{})
	if typeof(layout) == TYPE_DICTIONARY:
		# AD-202: layout.arena_walls = false drops the shared arena walls (default true).
		if layout.get("arena_walls",true) == false:
			merged["walls"] = []
		for dims in layout.get("walls",[]):
			if typeof(dims) != TYPE_ARRAY or dims.size() != 4:
				issues.append({"code":"ROOM_LAYOUT_INVALID","path":"layout.walls","message":"Wall requires x,y,w,h"})
				continue
			merged["walls"].append(dims)
	var world = Geometry.new(merged)
	# AD-138: optional layout.water; deep rects block walking for markers, spawns, pedestals and reachability.
	if typeof(layout) == TYPE_DICTIONARY and layout.has("water"):
		var water_issues: Array = WaterTiles.validate(layout["water"])
		for issue in water_issues:
			issue["path"] = "layout."+str(issue["path"])
			issues.append(issue)
		if water_issues.is_empty():
			world.add_ground_blockers(WaterTiles.new(layout["water"]).deep_rects())
	# AD-202: optional layout.pits = [x,y,w,h] rects that block walking only, like deep water.
	if typeof(layout) == TYPE_DICTIONARY and layout.has("pits"):
		var pit_rects: Array = []
		var pits_ok: bool = typeof(layout["pits"]) == TYPE_ARRAY
		if pits_ok:
			for dims in layout["pits"]:
				if typeof(dims) != TYPE_ARRAY or not EnvProps._num_array(dims,4) or float(dims[2]) <= 0.0 or float(dims[3]) <= 0.0:
					pits_ok = false
					break
				pit_rects.append(Rect2(float(dims[0]),float(dims[1]),float(dims[2]),float(dims[3])))
		if pits_ok:
			world.add_ground_blockers(pit_rects)
		else:
			issues.append({"code":"ROOM_LAYOUT_INVALID","path":"layout.pits","message":"Pits require [x,y,w,h] numbers with w,h > 0"})
	# AD-150: optional layout.env_props. Solid props join the walls before every marker/spawn/reachability check,
	# so a prop can never block entrance->exit, the reward or a spawn (props are never required to win).
	var env_rects: Array = []
	if typeof(layout) == TYPE_DICTIONARY and layout.has("env_props"):
		var env_data: Dictionary = EnvProps.load_data()
		var env_issues: Array = EnvProps.validate(layout["env_props"],env_data.get("kinds",{}))
		for issue in env_issues:
			issue["path"] = "layout."+str(issue["path"])
			issues.append(issue)
		if env_issues.is_empty():
			for prop in EnvProps.new(layout["env_props"],env_data).props:
				env_rects.append(prop["rect"])
				if bool(prop["rule"].get("solid_walk",false)):
					world.walls.append(prop["rect"])
	var min_spawn := float(room.get("min_spawn_distance",45))
	var points: Dictionary = {}
	for key in ["entrance","exit","reward"]:
		var pair = room[key]
		if typeof(pair) != TYPE_ARRAY or pair.size() != 2:
			issues.append({"code":"ROOM_MARKER_INVALID","path":key,"message":"Marker requires x,y"})
			continue
		var location := Vector2(float(pair[0]),float(pair[1]))
		points[key] = location
		if not world.valid_position(location,22):
			issues.append({"code":"ROOM_MARKER_BLOCKED","path":key,"message":"Marker overlaps solid geometry"})
		for rect in env_rects:
			if (rect as Rect2).grow(22.0).has_point(location):
				issues.append({"code":"ROOM_ENV_PROP_BLOCKS","path":"layout.env_props","message":"Env prop overlaps the "+key+" marker"})
	var count := 0
	if typeof(room["waves"]) != TYPE_ARRAY:
		issues.append({"code":"ROOM_WAVES_INVALID","path":"waves","message":"Expected wave array"})
	else:
		for wave in room["waves"]:
			if typeof(wave) != TYPE_DICTIONARY or not wave.has("enemies") or not wave.has("trigger") or not wave.has("delay_ticks"):
				issues.append({"code":"ROOM_WAVE_INVALID","path":"waves","message":"Wave requires trigger/delay/enemies"})
				continue
			if str(wave["trigger"]) not in ["start","on_clear"] or int(wave["delay_ticks"]) < 0:
				issues.append({"code":"ROOM_WAVE_TRIGGER_INVALID","path":"waves","message":"Invalid wave trigger or delay"})
			for entry in wave["enemies"]:
				if typeof(entry) != TYPE_ARRAY or entry.size() != 3 or str(entry[0]) not in known_enemy_types:
					issues.append({"code":"ROOM_ENEMY_INVALID","path":"waves.enemies","message":"Unknown enemy archetype or invalid spawn"})
					continue
				count += 1
				var spawn := Vector2(float(entry[1]),float(entry[2]))
				if points.has("entrance") and spawn.distance_to(points["entrance"]) < min_spawn:
					issues.append({"code":"ROOM_SPAWN_AT_ENTRANCE","path":"waves.enemies","message":"Enemy spawn overlaps player entrance"})
				if not world.valid_position(spawn,20):
					issues.append({"code":"ROOM_SPAWN_BLOCKED","path":"waves.enemies","message":"Spawn overlaps solid geometry"})
				elif points.has("entrance") and not reachable(world,points["entrance"],spawn,float(room.get("player_radius",22)),float(room.get("grid_step",20))):
					issues.append({"code":"ROOM_SPAWN_UNREACHABLE","path":"waves.enemies","message":"Spawn not reachable from entrance"})
		if room["type"] in ["combat","challenge"] and count == 0:
			issues.append({"code":"ROOM_EMPTY_ENCOUNTER","path":"waves","message":"Combat room needs at least one valid enemy"})
	if points.has("entrance"):
		var radius := float(room.get("player_radius",22))
		var step := float(room.get("grid_step",20))
		for key in ["exit","reward"]:
			if points.has(key) and not reachable(world,points["entrance"],points[key],radius,step):
				issues.append({"code":"ROOM_EXIT_UNREACHABLE","path":key,"message":key+" not reachable from entrance"})
		if room["type"] == "treasure" and room.has("pedestals"):
			var pedestals = room.get("pedestals",[])
			if typeof(pedestals) != TYPE_ARRAY or pedestals.is_empty() or int(room.get("choice_count",1)) < 1 or int(room.get("choice_count",1)) > pedestals.size():
				issues.append({"code":"ROOM_PEDESTAL_INVALID","path":"pedestals","message":"Treasure room needs pedestals and a valid choice_count"})
			else:
				for ped in pedestals:
					var at := Vector2(float(ped["position"][0]),float(ped["position"][1]))
					if str(ped.get("kind","")) not in ["artifact","rune"] or not world.valid_position(at,22) or not reachable(world,points["entrance"],at,radius,step):
						issues.append({"code":"ROOM_PEDESTAL_INVALID","path":"pedestals","message":"Pedestal kind/position invalid or unreachable"})
		if room["type"] == "challenge" and room.has("elite") and (typeof(room.get("elite")) != TYPE_DICTIONARY or typeof(room.get("challenge_reward")) != TYPE_DICTIONARY):
			issues.append({"code":"ROOM_CHALLENGE_INVALID","path":"elite","message":"Challenge room needs elite and challenge_reward blocks"})
	values = room.duplicate(true) if issues.is_empty() else {}
	return {"ok":issues.is_empty(),"issues":issues.duplicate(true)}

func marker(name: String) -> Vector2:
	var coords: Array = values[name]
	return Vector2(float(coords[0]),float(coords[1]))

## AD-128. 4-connected grid flood fill; deterministic, no RNG. True when a body of `radius` can walk from `from` to `to`.
static func reachable(world, from: Vector2, to: Vector2, radius: float, step: float = 20.0) -> bool:
	if not world.valid_position(from,radius) or not world.valid_position(to,radius):
		return false
	var goal := Vector2i(roundi(to.x/step),roundi(to.y/step))
	var start := Vector2i(roundi(from.x/step),roundi(from.y/step))
	var seen: Dictionary = {start:true}
	var queue: Array = [start]
	var head := 0
	while head < queue.size():
		var cell: Vector2i = queue[head]
		head += 1
		if cell == goal or Vector2(cell)*step == to:
			return true
		for dir in [Vector2i(1,0),Vector2i(-1,0),Vector2i(0,1),Vector2i(0,-1)]:
			var next: Vector2i = cell+dir
			if seen.has(next) or not world.valid_position(Vector2(next)*step,radius):
				continue
			seen[next] = true
			queue.append(next)
	return false

## AD-202 [PROPOSED FOR PROTOTYPE]. Room design rules (docs/rooms/ROOM_RULES.md) as data-driven issues; `rules` is run_v2.json "room_rules".
## Read-only and deterministic: it rebuilds the geometry exactly as initialize() does but never changes its verdicts.
## Returns {ok, obstacles, interactions, shape, issues:[{code,message}]}.
static func rule_report(room: Dictionary, arena: Dictionary, env_data: Dictionary, rules: Dictionary) -> Dictionary:
	var issues: Array = []
	var layout = room.get("layout",{})
	if typeof(layout) != TYPE_DICTIONARY:
		layout = {}
	var merged: Dictionary = arena.duplicate(true)
	var obstacles := 0
	if layout.get("arena_walls",true) == false:
		merged["walls"] = []
	obstacles += (merged["walls"] as Array).size()
	var layout_walls: Array = []
	for dims in layout.get("walls",[]):
		if typeof(dims) == TYPE_ARRAY and dims.size() == 4:
			layout_walls.append(dims)
	merged["walls"].append_array(layout_walls)
	obstacles += layout_walls.size()
	var world = Geometry.new(merged)
	if layout.has("water") and WaterTiles.validate(layout["water"]).is_empty():
		world.add_ground_blockers(WaterTiles.new(layout["water"]).deep_rects())
	if typeof(layout.get("pits")) == TYPE_ARRAY:
		var pit_rects: Array = []
		for dims in layout["pits"]:
			if typeof(dims) != TYPE_ARRAY or not EnvProps._num_array(dims,4) or float(dims[2]) <= 0.0 or float(dims[3]) <= 0.0:
				pit_rects = []
				break
			pit_rects.append(Rect2(float(dims[0]),float(dims[1]),float(dims[2]),float(dims[3])))
		world.add_ground_blockers(pit_rects)
	var interaction_kinds: Array = rules.get("interaction_kinds",[])
	var interactions := 0
	if layout.has("env_props") and EnvProps.validate(layout["env_props"],env_data.get("kinds",{})).is_empty():
		for prop in EnvProps.new(layout["env_props"],env_data).props:
			if bool(prop["rule"].get("solid_walk",false)):
				world.walls.append(prop["rect"])
				obstacles += 1
			if str(prop["kind"]) in interaction_kinds:
				interactions += 1
	var min_obstacles := int(rules.get("min_obstacles",2))
	var max_obstacles := int(rules.get("max_obstacles",5))
	if obstacles < min_obstacles or obstacles > max_obstacles:
		issues.append({"code":"RULE_OBSTACLES","message":"%d obstacle/cover pieces, need %d-%d" % [obstacles,min_obstacles,max_obstacles]})
	if interactions < int(rules.get("min_interactions",1)):
		issues.append({"code":"RULE_INTERACTION","message":"%d environment interactions, need %d" % [interactions,int(rules.get("min_interactions",1))]})
	var shape := str(room.get("shape",""))
	if shape.is_empty() or shape not in rules.get("shapes",[]):
		issues.append({"code":"RULE_SHAPE","message":"shape '%s' is not one of the allowed shape ids" % shape})
	var entrance := Vector2(float(room["entrance"][0]),float(room["entrance"][1])) if typeof(room.get("entrance")) == TYPE_ARRAY and room["entrance"].size() == 2 else Vector2.ZERO
	var min_spawn := float(rules.get("min_spawn_distance",160))
	var near := 0
	for wave in room.get("waves",[]):
		if typeof(wave) != TYPE_DICTIONARY:
			continue
		for entry in wave.get("enemies",[]):
			if typeof(entry) == TYPE_ARRAY and entry.size() == 3 and Vector2(float(entry[1]),float(entry[2])).distance_to(entrance) < min_spawn:
				near += 1
	if near > 0:
		issues.append({"code":"RULE_SPAWN_NEAR_ENTRANCE","message":"%d spawn(s) closer than %d to the entrance" % [near,int(min_spawn)]})
	# Grid pass: reachable cells from the entrance vs every walkable cell.
	var step := float(rules.get("dead_corner_step",40))
	var radius := float(rules.get("player_radius",22))
	var cols := int(floor(world.bounds.size.x/step))
	var rows := int(floor(world.bounds.size.y/step))
	var walkable: Dictionary = {}
	for gx in range(0,cols+1):
		for gy in range(0,rows+1):
			if world.valid_position(Vector2(gx,gy)*step,radius):
				walkable[Vector2i(gx,gy)] = true
	var start := Vector2i(roundi(entrance.x/step),roundi(entrance.y/step))
	var seen: Dictionary = {start:true}
	var queue: Array = [start]
	var head := 0
	while head < queue.size():
		var cell: Vector2i = queue[head]
		head += 1
		for dir in [Vector2i(1,0),Vector2i(-1,0),Vector2i(0,1),Vector2i(0,-1)]:
			var next: Vector2i = cell+dir
			if not seen.has(next) and walkable.has(next):
				seen[next] = true
				queue.append(next)
	var pockets := 0
	var corners: Array = []
	var cells: Array = walkable.keys()
	cells.sort_custom(func(a, b): return a.x < b.x or (a.x == b.x and a.y < b.y))
	for cell in cells:
		if not seen.has(cell):
			pockets += 1
			continue
		var blocked := 0
		for dir in [Vector2i(1,0),Vector2i(-1,0),Vector2i(0,1),Vector2i(0,-1)]:
			if not walkable.has(cell+dir):
				blocked += 1
		if blocked >= 3:
			corners.append(cell)
	if pockets > 0:
		issues.append({"code":"RULE_POCKET_UNREACHABLE","message":"%d walkable cell(s) cannot be reached from the entrance" % pockets})
	if not corners.is_empty():
		var first: Vector2i = corners[0]
		issues.append({"code":"RULE_DEAD_CORNER","message":"%d dead-corner cell(s), first at (%d,%d)" % [corners.size(),int(first.x*step),int(first.y*step)]})
	return {"ok":issues.is_empty(),"obstacles":obstacles,"interactions":interactions,"shape":shape,"issues":issues}
