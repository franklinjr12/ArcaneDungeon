extends RefCounted
## AD-031 GDD v1.0 conformance: scripted seed-20261022 slice with the 4-slot starter loadout and a
## two-build warden check (no single element required, GDD v1.0 section 4 step 4). Real commands only.
const Flow = preload("res://world/run_flow.gd")
const Driver = preload("res://tests/m3_run_driver.gd")
const SEED := 20261022
const FIRE_B := "sample.orbit_fire"
const FIRE_UNLOCKS := ["form.orb"]
const ESSENCES := ["essence.fire","essence.lightning","essence.water"]

func _slice(t) -> Dictionary:
	var flow = Flow.new(SEED)
	var loadout = flow.session.sim.loadout
	t.equal(loadout.slots.size(),4,"AD-031 loadout has 4 slots")
	for slot in 3:
		t.check(loadout.get_plan(slot)!=null,"AD-031 starter slot %d holds a plan" % slot)
	t.check(not flow._slot_has_spell(flow.session.sim,3),"AD-031 slot 4 starts empty")
	var rooms: Array = []
	var casts := 0
	for index in 4:
		rooms.append(str(flow.room.values["id"]))
		var result: Dictionary = Driver.fight(flow,4600)
		casts += int(result["casts"])
		t.equal(result["state"],"cleared","AD-031 %s cleared with unmodified starter loadout" % rooms[index])
		if index < 3:
			t.check(flow.choose_reward(0)["ok"],"AD-031 %s reward chosen" % rooms[index])
		t.check(Driver.reach_exit(flow)["ok"],"AD-031 %s exit reached" % rooms[index])
	t.equal(flow.room.values["id"],"workshop","AD-031 route reaches workshop")
	t.check(Driver.reach_exit(flow)["ok"],"AD-031 workshop exit reached")
	rooms.append(str(flow.room.values["id"]))
	var last: Dictionary = Driver.fight(flow,4600)
	casts += int(last["casts"])
	return {"state":flow.state,"win_events":flow.win_events,"boss_defeated_events":flow.boss_defeated_events,
		"tick":last["tick"],"hp":last["hp"],"casts":casts,"rooms":rooms,"summary":flow.summary()}

func _boss_build(ids: Array, extra_unlocks: Array = []) -> Dictionary:
	var flow = Flow.new(SEED)
	flow.run.sequence_index = 3
	for rune in extra_unlocks:
		if not flow.run.unlocked.has(rune):
			flow.run.unlocked.append(rune)
	var formulas: Array = []
	for id in ids:
		formulas.append(flow.formulas[id].duplicate(true))
	flow.run.formulas = formulas
	var enter: Dictionary = flow._enter_current()
	var result: Dictionary = Driver.fight(flow,5000)
	return {"enter_ok":enter["ok"],"state":result["state"],"boss_defeated_events":flow.boss_defeated_events,
		"tick":result["tick"],"hp":result["hp"],"casts":result["casts"]}

func _elements(ids: Array) -> Array:
	var flow = Flow.new(SEED)
	var found: Array = []
	for id in ids:
		var text: String = JSON.stringify(flow.formulas[id])
		for essence in ESSENCES:
			if text.contains(essence) and not found.has(essence):
				found.append(essence)
	found.sort()
	return found

func run(t) -> void:
	var first: Dictionary = _slice(t)
	t.equal(first["state"],"won","AD-031 scripted slice reaches slice complete")
	t.equal(first["win_events"],1,"AD-031 win fires exactly once")
	t.equal(first["boss_defeated_events"],1,"AD-031 boss defeated exactly once")
	t.equal(first["rooms"].size(),5,"AD-031 visited 3 combat rooms, boss, stage-two room")
	t.equal(_slice(t),first,"AD-031 scripted slice is deterministic twice")

	var builds := {"fire":["sample.fire_shot",FIRE_B],
		"water_lightning":["sample.water_burst","sample.lightning_shot"]}
	var unlocks := {"fire":FIRE_UNLOCKS,"water_lightning":[]}
	var used: Dictionary = {}
	for key in builds:
		var ids: Array = builds[key]
		var result: Dictionary = _boss_build(ids,unlocks[key])
		t.check(result["enter_ok"],"AD-031 %s build valid at boss entrance" % key)
		t.equal(result["state"],"cleared","AD-031 warden beaten by %s build" % key)
		t.equal(result["boss_defeated_events"],1,"AD-031 warden death once with %s build" % key)
		t.equal(_boss_build(ids,unlocks[key]),result,"AD-031 %s build deterministic twice" % key)
		used[key] = _elements(ids)
	t.check(not used["fire"].has("essence.water") and not used["fire"].has("essence.lightning"),
		"AD-031 Fire build uses only Fire")
	t.check(not used["water_lightning"].has("essence.fire"),"AD-031 Water+Lightning build uses no Fire")
	var union: Array = used["fire"].duplicate()
	for essence in used["water_lightning"]:
		if not union.has(essence):
			union.append(essence)
	union.sort()
	t.equal(union,ESSENCES.duplicate(),"AD-031 winning builds together cover all three elements")
	for key in used:
		t.check(used[key].size()<ESSENCES.size(),"AD-031 %s build lacks an element: none is required" % key)
