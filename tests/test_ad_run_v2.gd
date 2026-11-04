extends RefCounted
## AD-127: run v2 seeded stage sequence (room pool shuffle, optional room, boss, workshop).
const Flow = preload("res://world/run_flow.gd")
const Room = preload("res://world/room_template.gd")
const SEED := 20261022

func _ids(rooms: Array) -> Array:
	var out: Array = []
	for r in rooms:
		out.append(str(r["id"]))
	return out

func run(t) -> void:
	var cfg: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(Flow.CONFIG_V2))
	var tuning: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://combat/combat_tuning_v1.json"))
	t.check(_ids(Flow.build_sequence(cfg,SEED)) == _ids(Flow.build_sequence(cfg,SEED)),"AD-127 same seed gives the same room order")
	var orders: Dictionary = {}
	for run_seed in range(1,21):
		var rooms: Array = Flow.build_sequence(cfg,run_seed)
		orders[",".join(_ids(rooms))] = true
		t.check(rooms.back()["id"] == "cistern_boss","AD-127 seed %d ends on cistern boss" % run_seed)
		for stage_index in 2:
			var stage_rooms: Array = rooms.filter(func(r): return int(r["stage"]) == stage_index)
			var seen: Dictionary = {}
			var combat := 0
			var phase := 0 # 0 combat, 1 optional, 2 boss, 3 workshop
			var shape_ok := true
			for i in stage_rooms.size():
				var r: Dictionary = stage_rooms[i]
				t.check(not seen.has(r["id"]),"AD-127 seed %d stage %d no repeated template %s" % [run_seed,stage_index,r["id"]])
				seen[r["id"]] = true
				t.check(int(r["room"]) == i,"AD-127 room index is stage-local")
				match str(r["type"]):
					"combat":
						combat += 1
						shape_ok = shape_ok and phase == 0 and not r.has("optional")
					"treasure", "challenge":
						shape_ok = shape_ok and phase == 0 and bool(r.get("optional",false))
						phase = 1
					"boss":
						shape_ok = shape_ok and phase == 1
						phase = 2
					"workshop":
						shape_ok = shape_ok and phase == 2 and stage_index == 0
						phase = 3
			t.check(combat >= 5 and combat <= 6,"AD-127 seed %d stage %d combat count %d" % [run_seed,stage_index,combat])
			t.check(shape_ok,"AD-127 seed %d stage %d order is combat, optional, boss, workshop" % [run_seed,stage_index])
			t.check(phase == (3 if stage_index == 0 else 2),"AD-127 stage %d ends correctly" % stage_index)
	t.check(orders.size() >= 2,"AD-127 different seeds give different orders")
	for id in cfg["room_templates"]:
		var verdict: Dictionary = Room.new().initialize(cfg["room_templates"][id],tuning["arena"],tuning["enemies"].keys())
		t.check(verdict["ok"],"AD-127 template %s valid %s" % [id,str(verdict.get("issues",[]))])
	var flow = Flow.new(SEED,Flow.CONFIG_V2)
	t.check(flow.initialized and flow.state == "fighting","AD-127 v2 flow starts fighting")
	t.check(str(flow.room.values["id"]).begins_with("ruins_c"),"AD-127 v2 flow starts in a ruins combat room")
	t.check(Flow.new(SEED).rooms.size() == 6,"AD-127 v1 fixture keeps 6 rooms")
