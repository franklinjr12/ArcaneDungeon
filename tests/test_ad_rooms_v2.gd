extends RefCounted
## AD-241: room affix data and template validation (dark / unstable / haunted).
const Room = preload("res://world/room_template.gd")

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
