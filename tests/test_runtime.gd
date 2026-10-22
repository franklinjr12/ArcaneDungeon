extends RefCounted
const Clock = preload("res://game/core/simulation_clock.gd")
const Event = preload("res://magic/runtime/magic_event.gd")
const Limits = preload("res://magic/runtime/spell_limits.gd")
const Queue = preload("res://magic/runtime/magic_event_queue.gd")
const Trace = preload("res://debug/debug_trace.gd")
const Registry = preload("res://magic/data/rune_registry.gd")
const Compiler = preload("res://magic/compile/spell_compiler.gd")
const Codec = preload("res://magic/compile/spell_codec.gd")

func run(t) -> void:
	var a = Clock.new(98212)
	var b = Clock.new(98212)
	var c = Clock.new(98213)
	var random_a: Array = []
	var random_b: Array = []
	var random_c: Array = []
	for i in 8:
		random_a.append(a.random_int(1,1000000))
		random_b.append(b.random_int(1,1000000))
		random_c.append(c.random_int(1,1000000))
	t.equal(random_a,random_b,"TASK-008 same seed reproduces random sequence")
	t.check(random_a != random_c,"TASK-008 different seed affects stochastic sequence")
	t.equal(a.next_id("cast"),1,"TASK-008 first cast ID")
	t.equal(a.next_id("cast"),2,"TASK-008 monotonic cast ID")
	t.equal(a.next_id("effect"),1,"TASK-008 effects use independent ID domain")
	t.equal(a.next_id("event"),1,"TASK-008 events use independent ID domain")
	var clock_advance = Clock.new(4)
	var clock_manual = Clock.new(4)
	t.equal(clock_advance.advance(1.0),60,"TASK-008 one second advances sixty ticks")
	clock_manual.set_paused(true)
	t.equal(clock_manual.advance(3.0),0,"TASK-008 pause halts simulation")
	for i in 60:
		clock_manual.step_once()
	t.equal(clock_advance.tick,clock_manual.tick,"TASK-008 paused debug step matches normal ticks")
	t.equal(clock_manual.advance(1.0),0,"TASK-008 still paused after debugger stepping")
	clock_manual.set_paused(false)
	t.equal(clock_manual.advance(0.5),30,"TASK-008 resume accumulates only unpaused time")
	var targets := [{"id":8,"x":1.0,"y":0.0},{"id":3,"x":-1.0,"y":0.0},{"id":5,"x":3.0,"y":0.0}]
	var order: Array = a.order_targets(targets,Vector2.ZERO)
	t.equal([order[0]["id"],order[1]["id"],order[2]["id"]],[3,8,5],"TASK-008 deterministic distance then target ID tie-break")
	var trace = Trace.new()
	var limits = Limits.new()
	t.check(limits.load_defaults()["ok"],"TASK-009 data-driven limits load")
	t.equal(limits.get_limit("max_events_per_root_cast"),128,"TASK-009 default prototype event budget")
	var clock = Clock.new(55)
	var q = Queue.new(clock,limits,trace)
	t.check(not q.push({"type":"unbounded"}).get("accepted",false),"TASK-009 unrecognized event rejected")
	var arrival: Array = []
	var first = q.push({"type":"hit","cast_id":1,"root_cast_id":1,"source_id":4,"target_id":9})
	t.check(first["accepted"],"TASK-009 first typed event accepted")
	t.check(q.push({"type":"hit","cast_id":1,"root_cast_id":1})["accepted"],"TASK-009 second typed event accepted")
	var nested_result: Dictionary = {}
	var drain_result = q.drain(func(e):
		arrival.append(e["sequence"])
		if e["sequence"] == 1:
			nested_result.merge(q.drain(func(_unused): pass))
			q.push({"type":"trigger","cast_id":1,"root_cast_id":1,"parent_effect_id":5,"depth":1})
	)
	t.check(drain_result["ok"],"TASK-009 drain completes")
	t.equal(arrival,[1,2,3],"TASK-009 FIFO includes deferred callback events")
	t.equal(nested_result.get("reason",""),"REENTRANT_DRAIN","TASK-009 callbacks cannot recursively drain")
	t.equal(q.pending_count(),0,"TASK-009 consumed all queued events")
	var count_accepted := 0
	var overflow_trace = Trace.new()
	var stress_q = Queue.new(Clock.new(7),limits,overflow_trace)
	for i in 10000:
		if stress_q.push({"type":"hit","cast_id":44,"root_cast_id":44,"formula_id":"stress","target_id":i})["accepted"]:
			count_accepted += 1
	t.equal(count_accepted,limits.get_limit("max_events_per_root_cast"),"TASK-009 10k event cascade capped")
	t.equal(stress_q.pending_count(),128,"TASK-009 10k injected events cannot grow unbounded queue")
	t.equal(overflow_trace.filter_records(44,"stress","budget_exceeded").size(),1,"TASK-009 budget exceed logged once per cause")
	var drained := {"count":0}
	stress_q.drain(func(_e): drained["count"] += 1)
	t.equal(drained["count"],128,"TASK-009 stress drain terminates within budget")
	t.check(not stress_q.push({"type":"spawn","cast_id":44,"root_cast_id":44,"depth":2})["accepted"],"TASK-009 maximum event depth rejected")
	t.equal(overflow_trace.filter_records(44,"stress","budget_exceeded").size(),1,"TASK-009 unrelated empty-context event not mislabeled")
	var tuned: Dictionary = limits.snapshot()
	tuned["max_effects_per_cast"] = 2
	tuned["max_active_effects"] = 2
	tuned["max_chain_targets"] = 1
	t.check(limits.configure(tuned)["ok"],"TASK-009 explicit test tuning accepted")
	var spawns = Queue.new(Clock.new(8),limits,Trace.new())
	t.check(spawns.reserve_effect(1,30,1,"x"),"TASK-009 reserve effect one")
	t.check(spawns.reserve_effect(1,30,1,"x"),"TASK-009 reserve effect two")
	t.check(not spawns.reserve_effect(1,30,1,"x"),"TASK-009 per-cast effect budget enforced")
	spawns.release_effect()
	t.equal(spawns.active_effect_count(),1,"TASK-009 release active effect decrements")
	t.check(not spawns.chain_targets_allowed(2,{"cast_id":1}),"TASK-009 max chain target cap enforced")
	t.check(not spawns.rehit_delay_valid(1,{"cast_id":1}),"TASK-009 target rehit delay enforced")
	t.check(not spawns.reserve_effect(2,2000,2),"TASK-009 excessive lifetime rejected")
	var ref_trace = Trace.new()
	var no_trace = Trace.new(false)
	var same_with_trace = Queue.new(Clock.new(9),Limits.new(),ref_trace)
	var same_without_trace = Queue.new(Clock.new(9),Limits.new(),no_trace)
	t.check(same_with_trace.limits.load_defaults()["ok"],"TASK-010 tracing-on limits load")
	t.check(same_without_trace.limits.load_defaults()["ok"],"TASK-010 tracing-off limits load")
	var sequences_on: Array = []
	var sequences_off: Array = []
	for i in 3:
		same_with_trace.push({"type":"hit","cast_id":1})
		same_without_trace.push({"type":"hit","cast_id":1})
	same_with_trace.drain(func(e): sequences_on.append(e["sequence"]))
	same_without_trace.drain(func(e): sequences_off.append(e["sequence"]))
	t.equal(sequences_on,sequences_off,"TASK-010 trace state does not change execution")
	t.equal(no_trace.snapshot(),[],"TASK-010 disabled trace records nothing")
	t.check(ref_trace.snapshot().is_empty(),"TASK-010 instrumentation only records explicitly requested events")
	_golden_scenarios(t)

func _golden_scenarios(t) -> void:
	var registry = Registry.new()
	t.check(registry.load_seed()["ok"],"TASK-010 golden scenario rune seed loads")
	var compiler = Compiler.new(registry)
	var spark = t.fixture("spark_burst.json")
	var cost = compiler.compile(spark,registry.get_ids())["compiled_spell"].mana_cost()
	t.equal(cost,28,"TASK-010 sample Spark Burst cost derived from rune contributions")
	var legal = Trace.new()
	legal.record("cast_requested",{"cast_id":1,"root_cast_id":1,"formula_id":"sample.spark_burst","tick":0})
	legal.record("cost_paid",{"cast_id":1,"root_cast_id":1,"formula_id":"sample.spark_burst","amount":cost,"tick":0})
	legal.record("spawn",{"cast_id":1,"root_cast_id":1,"formula_id":"sample.spark_burst","effect_id":1,"parent_effect_id":0,"depth":0,"tick":0})
	legal.record("hit",{"cast_id":1,"root_cast_id":1,"formula_id":"sample.spark_burst","effect_id":1,"target_id":10,"tick":4})
	legal.record("status",{"cast_id":1,"root_cast_id":1,"formula_id":"sample.spark_burst","target_id":10,"reason":"burning","tick":4})
	legal.record("trigger",{"cast_id":1,"root_cast_id":1,"formula_id":"sample.spark_burst","parent_effect_id":1,"depth":1,"tick":4})
	legal.record("spawn",{"cast_id":1,"root_cast_id":1,"formula_id":"sample.spark_burst","effect_id":2,"parent_effect_id":1,"depth":1,"tick":4})
	legal.record("reaction",{"cast_id":1,"root_cast_id":1,"formula_id":"sample.spark_burst","source_id":10,"target_id":11,"reason":"wet_lightning_arc","tick":4})
	legal.record("cleanup",{"cast_id":1,"root_cast_id":1,"formula_id":"sample.spark_burst","effect_id":2,"tick":5})
	t.equal(legal.snapshot(),_normalize_fixture(t.fixture("trace_legal.json")),"TASK-010 legal effect ancestry golden trace")
	t.equal(legal.filter_records(1,"sample.spark_burst","spawn").size(),2,"TASK-010 filter cast/formula/type")
	t.equal(legal.filter_records(7).size(),0,"TASK-010 cast filter excludes unrelated events")
	var leaked = legal.snapshot()
	leaked[0]["type"] = "changed"
	t.equal(legal.snapshot()[0]["type"],"cast_requested","TASK-010 trace snapshots defensive copies")
	var invalid = Trace.new()
	var bad = spark.duplicate(true)
	bad["formula_id"] = "sample.invalid_burst_homing"
	bad["root"]["manifestation_id"] = "form.burst"
	bad["root"]["modifier_ids"] = ["mod.homing"]
	var compiled = compiler.compile(bad,registry.get_ids())
	t.check(not compiled["ok"],"TASK-010 invalid scenario rejected by shared compiler")
	t.contains_issue(compiled["issues"],"MODIFIER_INCOMPATIBLE","TASK-010 contract rejection code")
	invalid.record("cast_requested",{"cast_id":2,"root_cast_id":2,"formula_id":bad["formula_id"],"tick":0})
	invalid.record("rejected",{"cast_id":2,"root_cast_id":2,"formula_id":bad["formula_id"],"reason":"MODIFIER_INCOMPATIBLE","tick":0})
	t.equal(invalid.snapshot(),_normalize_fixture(t.fixture("trace_invalid.json")),"TASK-010 invalid formula golden trace")
	var budget = Trace.new()
	budget.record("cast_requested",{"cast_id":3,"root_cast_id":3,"formula_id":"sample.split_water","tick":0})
	var limits = Limits.new()
	t.check(limits.load_defaults()["ok"],"TASK-010 limits fixture loads")
	var cap = limits.snapshot()
	cap["max_events_per_root_cast"] = 1
	t.check(limits.configure(cap)["ok"],"TASK-010 budget fixture limits configured")
	var q = Queue.new(Clock.new(15),limits,budget)
	t.check(q.push({"type":"hit","cast_id":3,"root_cast_id":3,"formula_id":"sample.split_water"})["accepted"],"TASK-010 first queue item accepted")
	t.check(not q.push({"type":"trigger","cast_id":3,"root_cast_id":3,"formula_id":"sample.split_water"})["accepted"],"TASK-010 second queue item dropped on budget")
	t.equal(budget.snapshot(),_normalize_fixture(t.fixture("trace_budget.json")),"TASK-010 budget overflow golden trace")
	t.equal(legal.export_json("user://arcane_trace_test.json"),OK,"TASK-010 export normalized JSON")
	var file := FileAccess.open("user://arcane_trace_test.json",FileAccess.READ)
	t.check(file != null,"TASK-010 exported trace readable")
	if file != null:
		t.equal(_normalize_fixture(JSON.parse_string(file.get_as_text())),legal.snapshot(),"TASK-010 exported JSON matches trace")
		file.close()

func _normalize_fixture(value: Variant) -> Variant:
	if typeof(value) == TYPE_FLOAT and floor(value) == value:
		return int(value)
	if typeof(value) == TYPE_ARRAY:
		var result: Array = []
		for item in value:
			result.append(_normalize_fixture(item))
		return result
	if typeof(value) == TYPE_DICTIONARY:
		var result: Dictionary = {}
		for key in value:
			result[key] = _normalize_fixture(value[key])
		return result
	return value
