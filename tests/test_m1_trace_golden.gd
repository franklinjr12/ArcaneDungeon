extends RefCounted
## Regression fixtures for actual M1 execution plans, beyond synthetic M0 trace examples.
const Runner = preload("res://magic/runtime/spell_runner.gd")
const Golden = preload("res://tests/m1_trace_golden_generator.gd")

func run(t) -> void:
	var samples: Dictionary = t.fixture("m1_samples.json")
	var expected: Dictionary = t.fixture("m1_runtime_traces_v1.json")
	for scenario in ["split","pierce"]:
		var formula_id := "sample.split_fire_trigger" if scenario == "split" else "sample.pierce_water_trigger"
		var formula: Dictionary = {}
		for candidate in samples["formulas"]:
			if candidate["formula_id"] == formula_id:
				formula = candidate
				break
		t.check(not formula.is_empty(),"TASK-019 fixture contains "+scenario+" linked spell")
		if formula.is_empty():
			continue
		var r = Runner.new(31415)
		t.check(r.equip(0,formula)["ok"],"TASK-019 "+scenario+" formula equips")
		if scenario == "split":
			for y in [275,340,405]:
				r.add_target(Vector2(325,y),Vector2.ZERO,1000.0)
		else:
			for x in [280,365,450]:
				r.add_target(Vector2(x,340),Vector2.ZERO,1000.0)
		var cast = r.try_cast(0,r.actor.position,Vector2.RIGHT)
		t.check(cast["accepted"],"TASK-019 "+scenario+" cast accepted")
		for i in 75:
			r.step()
		var recorded: Array = Golden.normalize(r.trace.snapshot())
		t.equal(recorded,expected[scenario],"TASK-019 "+scenario+" golden causal trace (type/ancestry/order)")
		t.equal(r.trace.filter_records(cast["cast_id"],"","trigger").size(),3,
			"TASK-019 "+scenario+" actual valid hits produce exactly three triggers")
		var child_spawns := 0
		for event in r.trace.filter_records(cast["cast_id"],"","spawn"):
			if int(event.get("depth",0)) == 1 and int(event.get("parent_effect_id",0)) > 0:
				child_spawns += 1
		t.equal(child_spawns,3,"TASK-019 "+scenario+" three child bursts preserve ancestry")
		t.equal(r.trace.filter_records(cast["cast_id"],"","cost_paid").size(),1,
			"TASK-023 "+scenario+" spends mana once for three children")
