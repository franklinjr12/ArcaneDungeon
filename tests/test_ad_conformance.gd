extends RefCounted
## AD-031 GDD v1.0 conformance: scripted seed-20261022 slice with the 4-slot starter loadout and a
## two-build warden check (no single element required, GDD v1.0 section 4 step 4). Real commands only.
const Flow = preload("res://world/run_flow.gd")
const Driver = preload("res://tests/m3_run_driver.gd")
const Art = preload("res://ui/pixel_art_renderer.gd")
const SEED := 20261022
const FIRE_B := "sample.orbit_fire"
const FIRE_UNLOCKS := ["form.orb"]
const ESSENCES := ["essence.fire","essence.lightning","essence.water"]

func _slice(t) -> Dictionary:
	var flow = Flow.new(SEED)
	flow.experiment.configure(true)
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
		"tick":last["tick"],"hp":last["hp"],"casts":casts,"rooms":rooms,"summary":flow.summary(),
		"slice_complete":int(flow.experiment.summary()["counts"].get("slice_complete",0)),
		"distinct_spells_built":flow.experiment.summary()["distinct_spells_built"]}

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

func _check_p1_default(t, when: String) -> void:
	t.check(not Art.use_art_export,"AD-041 F6 art-export flag is off %s" % when)
	var map: Dictionary = Art.export_map()
	var manifest: Dictionary = Art.export_manifest()
	t.check(not Art.fx_frame("projectile.fire",0).is_empty(),"AD-041 P1 FX resolves by default %s" % when)
	for key in ["hud/slot_bar","hud/reward_card","damage_glyphs","icons"]:
		var parts: PackedStringArray = key.split("/")
		var stem = map[parts[0]][parts[1]] if parts.size() > 1 else map[parts[0]]
		t.check(manifest.has(stem) and str(manifest[stem].get("png","")) != "","AD-041 P1 %s asset %s present %s" % [key,stem,when])
	t.check(str(map["rune_icons"].get("essence.fire","")) != "","AD-041 P1 rune icon mapped %s" % when)
	t.check(not Art.damage_glyph_layout("flame","12").is_empty(),"AD-041 P1 damage glyph layout %s" % when)

func run(t) -> void:
	_check_p1_default(t,"at start")
	var first: Dictionary = _slice(t)
	_check_p1_default(t,"after route")
	t.equal(first["slice_complete"],1,"AD-041 scripted route records slice_complete once")
	t.check(first["distinct_spells_built"] >= 0,"AD-041 distinct spells built reported")
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
