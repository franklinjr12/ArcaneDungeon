extends RefCounted
## AD-128: Ruins room pool (10 handcrafted templates), treasure and challenge rooms, template validator.
const Room = preload("res://world/room_template.gd")
const Geometry = preload("res://world/arena_geometry.gd")
const PATH := "res://world/data/rooms_ruins_v1.json"

func _verdict(room: Dictionary, rules: Dictionary, tuning: Dictionary) -> Dictionary:
	var copy: Dictionary = room.duplicate(true)
	copy["min_spawn_distance"] = rules["min_spawn_distance"]
	copy["player_radius"] = rules["player_radius"]
	copy["grid_step"] = rules["grid_step"]
	return Room.new().initialize(copy,tuning["arena"],tuning["enemies"].keys())

func run(t) -> void:
	var doc: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(PATH))
	var tuning: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://combat/combat_tuning_v1.json"))
	var rules: Dictionary = doc["rules"]
	t.check(doc["pool"].size() == int(rules["pool_size"]) and doc["pool"].size() == 10,"AD-128 ruins pool has 10 templates")
	var layouts: Dictionary = {}
	for id in doc["room_templates"]:
		var room: Dictionary = doc["room_templates"][id]
		var verdict := _verdict(room,rules,tuning)
		t.check(verdict["ok"],"AD-128 template %s valid %s" % [id,str(verdict.get("issues",[]))])
		layouts[JSON.stringify(room.get("layout",{}))+JSON.stringify(room["waves"])] = true
	t.check(layouts.size() == doc["room_templates"].size(),"AD-128 every template is distinct")
	for id in doc["pool"]:
		t.check(doc["room_templates"][id]["type"] == "combat","AD-128 %s is a combat room" % id)
	var treasure: Dictionary = doc["room_templates"][doc["treasure_room"]]
	t.check(treasure["type"] == "treasure" and int(treasure["choice_count"]) == 1 and treasure["pedestals"].size() >= 2,"AD-128 treasure room offers a 1-of-N pedestal choice")
	var challenge: Dictionary = doc["room_templates"][doc["challenge_room"]]
	t.check(challenge["type"] == "challenge" and challenge.has("elite") and challenge.has("mini_boss_slot"),"AD-128 challenge room has elite block and mini-boss slot")
	# Validator negative cases.
	var base: Dictionary = doc["room_templates"]["ruins_p01"]
	var near: Dictionary = base.duplicate(true)
	near["waves"][0]["enemies"][0] = ["bone_thrall",300,450]
	t.check(not _verdict(near,rules,tuning)["ok"],"AD-128 validator rejects spawn under 160 px from entrance")
	var walled: Dictionary = base.duplicate(true)
	walled["layout"]["walls"] = [[240,0,40,900]]
	var codes: Array = []
	for issue in _verdict(walled,rules,tuning)["issues"]:
		codes.append(issue["code"])
	t.check("ROOM_EXIT_UNREACHABLE" in codes and "ROOM_SPAWN_UNREACHABLE" in codes,"AD-128 validator rejects unreachable exit and spawns")
	var bad_ped: Dictionary = treasure.duplicate(true)
	bad_ped["pedestals"] = []
	t.check(not _verdict(bad_ped,rules,tuning)["ok"],"AD-128 validator rejects treasure room without pedestals")
	var bad_exit: Dictionary = base.duplicate(true)
	bad_exit["exit"] = [5,5]
	t.check(not _verdict(bad_exit,rules,tuning)["ok"],"AD-128 validator rejects exit inside solid geometry")
