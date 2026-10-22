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
	if room["type"] not in ["combat","boss","workshop"]:
		issues.append({"code":"ROOM_TYPE_INVALID","path":"type","message":"Unsupported room type"})
	if str(room["scene"]).is_empty() or not ResourceLoader.exists(str(room["scene"])):
		issues.append({"code":"ROOM_SCENE_MISSING","path":"scene","message":"Arena scene unavailable"})
	var world = Geometry.new(arena)
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
				if points.has("entrance") and spawn.distance_to(points["entrance"]) < 45:
					issues.append({"code":"ROOM_SPAWN_AT_ENTRANCE","path":"waves.enemies","message":"Enemy spawn overlaps player entrance"})
				if not world.valid_position(spawn,20):
					issues.append({"code":"ROOM_SPAWN_BLOCKED","path":"waves.enemies","message":"Spawn overlaps solid geometry"})
		if room["type"] == "combat" and count == 0:
			issues.append({"code":"ROOM_EMPTY_ENCOUNTER","path":"waves","message":"Combat room needs at least one valid enemy"})
	values = room.duplicate(true) if issues.is_empty() else {}
	return {"ok":issues.is_empty(),"issues":issues.duplicate(true)}

func marker(name: String) -> Vector2:
	var coords: Array = values[name]
	return Vector2(float(coords[0]),float(coords[1]))
