extends RefCounted
## AD-224: run v2 is 3 combat rooms, the optional room, a Sigil Desk visit, then the boss, per stage.
const Flow = preload("res://world/run_flow.gd")
const Reward = preload("res://world/reward_generator.gd")
const Artifacts = preload("res://world/artifacts.gd")
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

	_reward_guarantee(t,cfg)

func _kinds(cards: Array) -> Array:
	var kinds: Array = []
	for c in cards:
		kinds.append(str(c["kind"]))
	return kinds

func _reward_guarantee(t, cfg: Dictionary) -> void:
	t.equal(int(cfg["room_reward_currency"]),40,"AD-224 room currency is 40")
	var empty_cfg: Dictionary = cfg.duplicate(true)
	empty_cfg["reward_pool"] = []
	var flow = Flow.new(SEED,Flow.CONFIG_V2)
	var cards: Array = Reward.new(empty_cfg).choices(flow.run,"x",false)
	t.check("artifact" in _kinds(cards),"AD-224 empty pool still offers an artifact")
	var coins := 0
	for c in cards:
		if str(c["kind"]) == "currency":
			coins += 1
			t.equal(int(c["amount"]),int(cfg["room_reward_currency"]),"AD-224 currency card amount")
	t.equal(coins,1,"AD-224 one currency card")
	var off_cfg: Dictionary = empty_cfg.duplicate(true)
	off_cfg["reward_guarantee_item"] = false
	var off: Array = Reward.new(off_cfg).choices(flow.run,"x",false)
	t.check(_kinds(off).size() <= _kinds(cards).size(),"AD-224 flag off never offers more cards")
	var full = Flow.new(SEED,Flow.CONFIG_V2)
	full.run.artifacts.clear()
	for id in Artifacts.definitions().keys():
		if full.run.artifacts.size() < Artifacts.max_held():
			full.run.artifacts.append(str(id))
	t.equal(full.run.artifacts.size(),Artifacts.max_held(),"AD-224 artifacts filled to the limit")
	var capped: Array = Reward.new(empty_cfg).choices(full.run,"x",false)
	t.check("artifact" not in _kinds(capped),"AD-224 no artifact card at the held limit")
	for run_seed in range(1,21):
		var f = Flow.new(run_seed,Flow.CONFIG_V2)
		for r in Flow.build_sequence(cfg,run_seed):
			if str(r["type"]) == "combat":
				var k := _kinds(Reward.new(cfg).choices(f.run,str(r["id"]),false))
				t.check("rune" in k or "artifact" in k,"AD-224 seed %d %s offers an item" % [run_seed,str(r["id"])])
