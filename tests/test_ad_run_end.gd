extends RefCounted
## AD-018: run end summary, single win event, retry same seed / new seed.
const Flow = preload("res://world/run_flow.gd")
const SEED := 20261022

func _spawns(flow) -> Array:
	var out: Array = []
	for enemy in flow.session.enemies:
		out.append([enemy.target.position, enemy.archetype if "archetype" in enemy else ""])
	return out

func _kill_all(flow, limit: int = 3000) -> void:
	for i in limit:
		if flow.state != "fighting":
			return
		for enemy in flow.session.enemies:
			if enemy.target.alive():
				enemy.target.receive_damage(100000,"fire",1,100)
		flow.step()

func _room1(flow) -> Dictionary:
	_kill_all(flow)
	return {"spawns":_spawns(flow),"cards":flow.reward_options.duplicate(true)}

func run(t) -> void:
	var flow = Flow.new(SEED)
	var fresh = _room1(Flow.new(SEED))
	t.check(not fresh["spawns"].is_empty(),"AD-018 room 1 has spawns")
	# Death -> summary.
	flow.session.sim.actor.receive_damage(100000,"fire",2,100)
	flow.step({"cast":0})
	t.equal(flow.state,"dead","AD-018 HP 0 ends run")
	var lost: Dictionary = flow.summary()
	t.equal(lost["outcome"],"lost","AD-018 summary outcome lost")
	t.equal(lost["seed"],SEED,"AD-018 summary carries seed")
	t.check(lost["ticks"]>=1 and lost["seconds"]>0.0,"AD-018 summary has time")
	# Retry same seed reproduces room 1 spawns and reward cards.
	flow.run.currency = 999
	flow.run.unlocked.append("mod.test")
	flow.retry_same_seed()
	t.equal(flow.run.seed,SEED,"AD-018 retry keeps seed")
	t.equal(flow.outcome,"","AD-018 retry clears outcome")
	t.equal(flow.summary()["ticks"],0,"AD-018 retry resets counters")
	t.equal(flow.run.currency,int(flow.config["initial_currency"]),"AD-018 retry resets currency")
	t.equal(flow.run.unlocked,flow.config["initial_unlocked"],"AD-018 retry resets runes")
	var again: Dictionary = _room1(flow)
	t.equal(again["spawns"],fresh["spawns"],"AD-018 retry reproduces room-1 spawns")
	t.equal(again["cards"],fresh["cards"],"AD-018 retry reproduces reward cards")
	t.equal(flow.rooms_cleared,1,"AD-018 rooms cleared counted")
	t.check(flow.kills>0,"AD-018 kills counted")
	# New seed differs and is deterministic.
	flow.start_new_seed()
	t.check(flow.run.seed != SEED and flow.run.seed >= 0,"AD-018 new seed differs")
	var other = Flow.new(SEED)
	other.start_new_seed()
	t.equal(other.run.seed,flow.run.seed,"AD-018 new seed deterministic")
	t.equal(flow.rooms_cleared,0,"AD-018 new seed resets summary")
	# Win fires once after the stage-2 room.
	var w = Flow.new(SEED)
	w.run.sequence_index = w.config["rooms"].size()-1
	w._enter_current()
	_kill_all(w)
	t.equal(w.state,"won","AD-018 stage-2 clear wins")
	t.equal(w.win_events,1,"AD-018 win fired once")
	t.equal(w.summary()["outcome"],"won","AD-018 summary outcome won")
	t.equal(w.reward_options.size(),0,"AD-018 win grants no reward cards")
	t.equal(w.step()["reason"],"NOT_FIGHTING","AD-018 no stepping after win")
	w._finish_combat()
	t.equal(w.win_events,1,"AD-018 win cannot refire")
	t.equal(w.snapshot()["outcome"],"won","AD-018 snapshot carries outcome")
	t.equal(w.snapshot()["win_events"],1,"AD-018 snapshot carries win_events")
