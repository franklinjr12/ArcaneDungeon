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
	_optional_tests(t)
	_full_run_tests(t)

func _kill_all(flow, limit: int = 3000) -> void:
	for i in limit:
		if flow.state != "fighting":
			return
		for enemy in flow.session.enemies:
			if enemy.target.alive():
				enemy.target.receive_damage(100000,"fire",1,100)
		flow.step()

func _entered(flow) -> Array:
	var out: Array = []
	for entry in flow.logs:
		if entry["kind"] == "room_enter":
			out.append(str(entry["id"]))
	return out

## Clears combat rooms (reward 0) until the next room is the optional one; returns false if the run left that path.
func _advance_to_optional(flow) -> bool:
	for guard in 40:
		if flow.state == "fighting":
			_kill_all(flow)
		if flow.state == "cleared" and not flow.reward_collected and flow.room.values["type"] != "boss":
			flow.choose_reward(0)
		if flow.next_is_optional():
			return true
		if flow.state not in ["cleared","workshop"]:
			return false
		flow.session.sim.actor.position = flow.room.marker("exit")
		flow.try_exit(flow.room.marker("exit"))
	return false

func _optional_tests(t) -> void:
	var skipper = Flow.new(SEED,Flow.CONFIG_V2)
	t.check(_advance_to_optional(skipper),"AD-127 reaches the optional door")
	t.check(skipper.state == "cleared" and skipper.room.values["type"] == "combat","AD-127 door is in a cleared combat room")
	var skipped_id: String = str(skipper.rooms[skipper.run.sequence_index+1]["id"])
	t.equal(skipped_id,"ruins_treasure","AD-127 ruins optional room is the treasure room")
	var result: Dictionary = skipper.try_exit(skipper.room.marker("exit"),false)
	t.check(result["ok"],"AD-127 optional room can be skipped")
	t.equal(skipper.room.values["type"],"boss","AD-127 skip lands in the boss room")
	t.check(not (skipped_id in _entered(skipper)),"AD-127 skipped optional room was never entered")
	t.check(skipper.logs.any(func(e): return e["kind"] == "optional_skipped" and e["id"] == skipped_id),"AD-127 skip is logged")
	t.equal(skipper.state,"fighting","AD-127 boss room starts fighting")

	var taker = Flow.new(SEED,Flow.CONFIG_V2)
	t.check(_advance_to_optional(taker),"AD-127 taker reaches the optional door")
	t.check(taker.try_exit(taker.room.marker("exit"),true)["ok"],"AD-127 optional room can be taken")
	t.equal(str(taker.room.values["id"]),"ruins_treasure","AD-127 taking enters the treasure room")
	t.equal(taker.state,"cleared","AD-127 treasure room starts cleared")
	t.check(not taker.reward_options.is_empty(),"AD-127 treasure room offers rewards")
	t.check(taker.choose_reward(0)["ok"],"AD-127 treasure reward can be chosen")
	var snap: Dictionary = taker.snapshot()
	t.check(taker.try_exit(taker.room.marker("exit"))["ok"],"AD-127 treasure room leads to the boss")
	t.equal(taker.room.values["type"],"boss","AD-127 after treasure comes the boss")
	t.check(taker.next_is_optional() == false,"AD-127 boss room has no optional next")
	var other = Flow.new(SEED,Flow.CONFIG_V2)
	t.check(other.recover(snap.get("run"))["ok"] and str(other.room.values["id"]) == "ruins_treasure","AD-127 recover restores the same v2 room id")

## Drives a whole v2 run on placeholder content. Returns the flow.
func _scripted_run(run_seed: int, take_optional: bool):
	var flow = Flow.new(run_seed,Flow.CONFIG_V2)
	var workshop_snapshot := {}
	for guard in 80:
		if flow.state == "fighting":
			_kill_all(flow)
		if flow.state == "won" or flow.state == "dead":
			break
		if flow.state == "cleared" and not flow.reward_collected and flow.room.values["type"] != "boss":
			flow.choose_reward(0)
		if flow.state == "workshop" and workshop_snapshot.is_empty():
			workshop_snapshot = flow.snapshot()
		var pos: Vector2 = flow.room.marker("exit")
		flow.session.sim.actor.position = pos
		flow.try_exit(pos,take_optional)
	if not workshop_snapshot.is_empty():
		var again = Flow.new(run_seed,Flow.CONFIG_V2)
		again.recover(workshop_snapshot["run"])
		flow.logs.append({"kind":"test_recovered_room","id":str(again.room.values["id"]),"expected":str(workshop_snapshot["room_id"])})
	return flow

func _full_run_tests(t) -> void:
	for run_seed in [SEED,7,12345]:
		for take_optional in [false,true]:
			var label := "seed %d optional %s" % [run_seed,str(take_optional)]
			var flow = _scripted_run(run_seed,take_optional)
			var ids: Array = _entered(flow)
			t.equal(flow.state,"won","AD-127 %s ends won" % label)
			t.equal(flow.summary()["outcome"],"won","AD-127 %s summary won" % label)
			t.equal(flow.win_events,1,"AD-127 %s win fires once" % label)
			t.equal(ids.count("workshop"),1,"AD-127 %s workshop entered once" % label)
			t.equal(str(flow.room.values["id"]),"cistern_boss","AD-127 %s last room is cistern boss" % label)
			var first_cistern := ids.size()
			for i in ids.size():
				if ids[i].begins_with("cistern"):
					first_cistern = mini(first_cistern,i)
			t.check(ids.find("workshop") >= 0 and ids.find("workshop") < first_cistern,"AD-127 %s workshop precedes cistern" % label)
			t.equal(ids.has("ruins_treasure"),take_optional,"AD-127 %s ruins treasure matches choice" % label)
			for entry in flow.logs:
				if entry["kind"] == "test_recovered_room":
					t.equal(entry["id"],entry["expected"],"AD-127 %s workshop recover restores room id" % label)
			t.equal(flow.step()["reason"],"NOT_FIGHTING","AD-127 %s no stepping after win" % label)
			t.equal(flow.try_exit(flow.room.marker("exit"))["reason"],"DOOR_LOCKED","AD-127 %s exit refused after win" % label)
	t.equal(_entered(_scripted_run(SEED,true)),_entered(_scripted_run(SEED,true)),"AD-127 same seed gives identical room_enter sequence")
