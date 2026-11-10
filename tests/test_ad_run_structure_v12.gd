extends RefCounted
## AD-224: run v2 is 3 combat rooms, the optional room, a Sigil Desk visit, then the boss, per stage.
const Flow = preload("res://world/run_flow.gd")
const SEED := 20261022

func _kill_all(flow, limit: int = 3000) -> void:
	for i in limit:
		if flow.state != "fighting":
			return
		for enemy in flow.session.enemies:
			if enemy.target.alive():
				enemy.target.receive_damage(100000,"fire",1,100)
		flow.step()

## Drives a whole v2 run; at each workshop visit records merchant and restore state into `visits`.
func _scripted_run(run_seed: int, take_optional: bool, visits: Array):
	var flow = Flow.new(run_seed,Flow.CONFIG_V2)
	var last_visit := ""
	for guard in 80:
		if flow.state == "fighting":
			_kill_all(flow)
		if flow.state == "won" or flow.state == "dead":
			break
		if flow.state == "cleared" and not flow.reward_collected and flow.room.values["type"] != "boss":
			flow.choose_reward(0)
		if flow.state == "workshop":
			var key := "%d" % flow.run.sequence_index
			if key != last_visit:
				last_visit = key
				visits.append({
					"merchant":flow.merchant != null and not flow.merchant.stock.is_empty(),
					"mana":flow.range_sim.mana,"hp":flow.range_sim.actor.health.maximum,
					"next_is_boss":str(flow.rooms[flow.run.sequence_index+1]["type"]) == "boss"})
		var pos: Vector2 = flow.room.marker("exit")
		flow.session.sim.actor.position = pos
		flow.try_exit(pos,take_optional)
	return flow

func run(t) -> void:
	var cfg: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(Flow.CONFIG_V2))
	for run_seed in range(1,21):
		var rooms: Array = Flow.build_sequence(cfg,run_seed)
		t.equal(rooms.size(),12,"AD-224 seed %d has 12 entries" % run_seed)
		for stage_index in 2:
			var types: Array = []
			for r in rooms:
				if int(r["stage"]) == stage_index:
					types.append("optional" if bool(r.get("optional",false)) else str(r["type"]))
			t.equal(types,["combat","combat","combat","optional","workshop","boss"],"AD-224 seed %d stage %d order" % [run_seed,stage_index])
		for r in rooms:
			if bool(r.get("optional",false)):
				t.check(str(r["type"]) in ["treasure","challenge"],"AD-224 optional room type")
	for take_optional in [true,false]:
		var visits: Array = []
		var flow = _scripted_run(SEED,take_optional,visits)
		var label := "optional %s" % str(take_optional)
		t.equal(flow.state,"won","AD-224 %s run ends won" % label)
		var counts := {"combat":0,"optional":0,"workshop":0,"boss":0}
		for r in flow.run_log.rooms:
			var type := str(r.get("type",""))
			if type in ["treasure","challenge"]:
				type = "optional"
			if counts.has(type):
				counts[type] += 1
		t.equal(counts,{"combat":6,"optional":2 if take_optional else 0,"workshop":2,"boss":2},"AD-224 %s room counts" % label)
		t.equal(visits.size(),2,"AD-224 %s two desk visits" % label)
		for v in visits:
			t.check(v["merchant"],"AD-224 %s merchant has stock at the desk" % label)
			t.equal(v["mana"],float(cfg["workshop_restore_mana"]),"AD-224 %s desk restores mana" % label)
			t.equal(v["hp"],float(cfg["workshop_restore_hp"]),"AD-224 %s desk restores hp" % label)
			t.check(v["next_is_boss"],"AD-224 %s desk leads to the boss" % label)
	t.equal(Flow.new(SEED).rooms.size(),6,"AD-224 v1 config keeps 6 rooms")
