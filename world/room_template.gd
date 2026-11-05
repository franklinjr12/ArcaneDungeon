extends Resource
## TASK-036. Lightweight validated Resource wrapper around versioned room dictionaries.
const Geometry = preload("res://world/arena_geometry.gd")
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
		for dims in layout.get("walls",[]):
			if typeof(dims) != TYPE_ARRAY or dims.size() != 4:
				issues.append({"code":"ROOM_LAYOUT_INVALID","path":"layout.walls","message":"Wall requires x,y,w,h"})
				continue
			merged["walls"].append(dims)
	var world = Geometry.new(merged)
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
