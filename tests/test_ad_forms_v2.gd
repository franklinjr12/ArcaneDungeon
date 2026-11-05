extends RefCounted
## AD-132: Beam and Field forms (channelled line, ground zone) with pulse budgets.
const Runner = preload("res://magic/runtime/spell_runner.gd")
const Golden = preload("res://tests/ad_forms_golden_generator.gd")

func _formula(form: String, essence: String = "essence.fire", modifiers: Array = []) -> Dictionary:
	return {"schema_version":2,"formula_id":"test.%s.%s" % [form,essence],"display_name":form,
		"root":{"essence_id":essence,"manifestation_id":form,"modifier_ids":modifiers,"params":{}}}

func _runner(form: String, essence: String = "essence.fire", seed_value: int = 132):
	var r = Runner.new(seed_value)
	r.settings["combat"]["regen_mana_per_tick"] = 0.0
	r.mana = float(r.settings["combat"]["player_max_mana"])
	var equipped: Dictionary = r.equip(0,_formula(form,essence))
	if not equipped["ok"]:
		printerr("equip failed: ",equipped)
	return r

func _params(r) -> Dictionary:
	return r.loadout.get_plan(0).snapshot()["root"]["params"]

func _step(r, ticks: int) -> void:
	for i in ticks:
		r.step()

## Pulse hits on one target, from the typed hit trace (target.hit_count also counts Burning ticks).
func _hits(r, target) -> int:
	return r.trace.filter_records(-1,"","hit").filter(func(e): return int(e["target_id"]) == target.id).size()

func _count(r, kind: String) -> int:
	return r.trace.filter_records(-1,"",kind).size()

func run(t) -> void:
	_compile_and_validate(t)
	_beam_hits(t)
	_beam_wall(t)
	_beam_mana(t)
	_beam_channel(t)
	_field(t)
	_golden_tests(t)
	_stress(t)
	_determinism(t)

func _compile_and_validate(t) -> void:
	var r = Runner.new(132)
	t.check(r.equip(0,_formula("form.beam"))["ok"],"AD-132 beam formula equips")
	t.check(r.equip(1,_formula("form.field","essence.cold"))["ok"],"AD-132 field formula equips")
	var bad: Dictionary = r.equip(2,_formula("form.beam","essence.fire",["mod.pierce"]))
	t.check(not bad["ok"],"AD-132 beam + pierce rejected")
	t.contains_issue(bad["issues"],"MODIFIER_INCOMPATIBLE","AD-132 beam + pierce is MODIFIER_INCOMPATIBLE")

func _beam_hits(t) -> void:
	var r = _runner("form.beam")
	var p := _params(r)
	var on_line = r.add_target(Vector2(300,340),Vector2.ZERO,100000.0)
	var off_line = r.add_target(Vector2(300,340.0+18.0+float(p["beam_width"])*0.5+4.0),Vector2.ZERO,100000.0)
	var behind = r.add_target(Vector2(140.0+float(p["beam_length"])+60.0,340),Vector2.ZERO,100000.0)
	t.check(r.try_cast(0,r.actor.position,Vector2.RIGHT)["accepted"],"AD-132 beam cast accepted")
	var ticks := 60
	_step(r,ticks)
	var interval := int(p["tick_interval_ticks"])
	var expected := int(ceil(float(ticks)/float(interval)))
	t.equal(_hits(r,on_line),expected,"AD-132 beam pulses on the line = ceil(ticks/interval)")
	t.equal(_hits(r,off_line),0,"AD-132 target offset beyond width gets no beam hits")
	t.equal(_hits(r,behind),0,"AD-132 target beyond beam length gets no beam hits")
	t.equal(r.trace.filter_records(-1,"","hit").size(),expected,"AD-132 hit trace count matches pulses")
	var first: Dictionary = r.trace.filter_records(-1,"","hit")[0]
	t.equal(int(first["tick"]),1,"AD-132 first beam pulse on the first tick after cast")
	_step(r,int(p["lifetime_ticks"]))
	t.equal(r.queue.active_effect_count(),0,"AD-132 beam releases its effect at lifetime end")
	t.check(not r.is_channelling(),"AD-132 not channelling after lifetime")
	t.equal(_hits(r,on_line),int(ceil(float(p["lifetime_ticks"])/float(interval))),"AD-132 full-lifetime beam pulse count")

func _beam_wall(t) -> void:
	var r = _runner("form.beam")
	var front = r.add_target(Vector2(200,340),Vector2.ZERO,100000.0)
	var behind = r.add_target(Vector2(330,340),Vector2.ZERO,100000.0)
	r.collision_walls = [Rect2(260,300,20,80)]
	r.try_cast(0,r.actor.position,Vector2.RIGHT)
	_step(r,40)
	t.check(_hits(r,front) > 0,"AD-132 target in front of the wall is still hit")
	t.equal(_hits(r,behind),0,"AD-132 wall stops the beam: target behind it gets 0 hits")
	var beam = r.active[0]["effect"]
	t.check(absf(beam.end_point.x-260.0) < 0.01,"AD-132 beam end point clipped at the wall face")
	# Bounds also clip the line.
	var edge = _runner("form.beam")
	edge.actor.position = Vector2(edge.bounds.end.x-50.0,340)
	edge.try_cast(0,edge.actor.position,Vector2.RIGHT)
	_step(edge,1)
	t.check(edge.active[0]["effect"].end_point.x <= edge.bounds.end.x+0.01,"AD-132 beam clipped at arena bounds")

func _beam_mana(t) -> void:
	var r = _runner("form.beam")
	var p := _params(r)
	var cost := float(p["mana_per_tick"])
	var upfront := float(r.loadout.get_plan(0).snapshot()["mana_cost"])
	var dummy = r.add_target(Vector2(300,340),Vector2.ZERO,100000.0)
	r.mana = 120.0
	r.try_cast(0,r.actor.position,Vector2.RIGHT)
	t.equal(r.mana,120.0-upfront,"AD-132 beam pays plan mana up front")
	r.step()
	t.equal(r.mana,120.0-upfront-cost,"AD-132 beam pays mana_per_tick on the pulse")
	_step(r,int(p["tick_interval_ticks"])-1)
	t.equal(r.mana,120.0-upfront-cost,"AD-132 no mana paid between pulses")
	r.step()
	t.equal(r.mana,120.0-upfront-2.0*cost,"AD-132 second pulse pays again")
	# Starved beam ends early.
	var low = _runner("form.beam")
	var starved = low.add_target(Vector2(300,340),Vector2.ZERO,100000.0)
	low.mana = upfront+cost*2.0+cost*0.5
	low.try_cast(0,low.actor.position,Vector2.RIGHT)
	_step(low,60)
	t.equal(_hits(low,starved),2,"AD-132 beam hits only for pulses it can pay")
	t.equal(low.active.size(),0,"AD-132 starved beam removed from active")
	t.equal(low.queue.active_effect_count(),0,"AD-132 starved beam releases its effect")
	var cleanup: Array = low.trace.filter_records(-1,"","cleanup")
	t.equal(str(cleanup[0].get("reason","")),"no_mana","AD-132 starved beam cleanup reason is no_mana")
	t.equal(_count(low,"cost_paid"),3,"AD-132 cost_paid traced for cast + 2 pulses")

func _beam_channel(t) -> void:
	var r = _runner("form.beam")
	var dummy = r.add_target(Vector2(300,340),Vector2.ZERO,100000.0)
	t.check(not r.is_channelling(),"AD-132 not channelling before cast")
	r.try_cast(0,r.actor.position,Vector2.RIGHT)
	t.check(r.is_channelling(),"AD-132 channelling after beam cast")
	r.equip(1,_formula("form.beam","essence.water"))
	r.loadout.slots[1]["cooldown"] = 0
	var second: Dictionary = r.try_cast(1,r.actor.position,Vector2.RIGHT)
	t.equal(second["reason"],"BEAM_BUDGET_EXCEEDED","AD-132 second beam rejected while one is active")
	r.set_channel_aim(Vector2.ZERO)
	t.equal(r.active[0]["effect"].aim,Vector2.RIGHT,"AD-132 zero aim input ignored")
	r.set_channel_aim(Vector2.UP)
	r.step()
	t.equal(_hits(r,dummy),0,"AD-132 re-aimed beam leaves the old line")
	r.stop_channel()
	t.check(not r.is_channelling(),"AD-132 stop_channel clears channelling")
	_step(r,2)
	t.equal(r.queue.active_effect_count(),0,"AD-132 released beam frees its effect slot")
	t.equal(str(r.trace.filter_records(-1,"","cleanup")[0].get("reason","")),"released","AD-132 release reason traced")
	t.check(r.try_cast(1,r.actor.position,Vector2.RIGHT)["accepted"],"AD-132 new beam allowed after release")

func _field(t) -> void:
	var r = _runner("form.field")
	var p := _params(r)
	var inside = r.add_target(Vector2(330,340),Vector2.ZERO,100000.0)
	var outside = r.add_target(Vector2(330.0+float(p["field_radius"])+40.0,340),Vector2.ZERO,100000.0)
	t.check(r.try_cast(0,r.actor.position,Vector2.RIGHT,Vector2(330,340))["accepted"],"AD-132 field cast accepted")
	t.equal(r.active[0]["effect"].position,Vector2(330,340),"AD-132 field centred on target point")
	var duration := int(p["field_duration_ticks"])
	var interval := int(p["tick_interval_ticks"])
	_step(r,duration+5)
	t.equal(_hits(r,inside),int(ceil(float(duration)/float(interval))),"AD-132 field pulses = ceil(duration/interval)")
	t.equal(_hits(r,outside),0,"AD-132 target outside the field radius unaffected")
	t.equal(r.queue.active_effect_count(),0,"AD-132 field releases its effect on expiry")
	# Cold field chills, then freezes via the status rules.
	var cold = _runner("form.field","essence.cold")
	var victim = cold.add_target(Vector2(330,340),Vector2.ZERO,100000.0)
	cold.try_cast(0,cold.actor.position,Vector2.RIGHT,Vector2(330,340))
	_step(cold,1)
	t.check(victim.status.has("chilled",cold.clock.tick),"AD-132 cold field applies Chilled")
	_step(cold,int(_params(cold)["tick_interval_ticks"])*2)
	t.check(victim.status.has("frozen",cold.clock.tick),"AD-132 repeated cold pulses reach Frozen")
	# Range clamp, aim fallback, wall clamp.
	var far = _runner("form.field")
	far.try_cast(0,far.actor.position,Vector2.RIGHT,Vector2(900,340))
	var reach := float(_params(far)["cast_range"])
	t.check(absf(far.active[0]["effect"].position.x-(140.0+reach)) < 0.01,"AD-132 target_point beyond cast_range is clamped")
	var aimed = _runner("form.field")
	aimed.try_cast(0,aimed.actor.position,Vector2.DOWN)
	t.check(aimed.active[0]["effect"].position.is_equal_approx(Vector2(140,340.0+reach)),"AD-132 no target point uses aim * cast_range")
	var walled = _runner("form.field")
	walled.collision_walls = [Rect2(200,300,20,80)]
	walled.try_cast(0,walled.actor.position,Vector2.RIGHT,Vector2(330,340))
	t.check(walled.active[0]["effect"].position.x <= 200.01,"AD-132 field centre stops at the first wall")
	# Field budget.
	var cap = _runner("form.field")
	var limit: int = cap.limits.get_limit("max_active_fields")
	for i in limit:
		cap.loadout.slots[0]["cooldown"] = 0
		t.check(cap.try_cast(0,cap.actor.position,Vector2.RIGHT)["accepted"],"AD-132 field %d within budget" % (i+1))
	cap.loadout.slots[0]["cooldown"] = 0
	var mana_before: float = cap.mana
	t.equal(cap.try_cast(0,cap.actor.position,Vector2.RIGHT)["reason"],"FIELD_BUDGET_EXCEEDED","AD-132 field over budget rejected")
	t.equal(cap.mana,mana_before,"AD-132 field budget rejection costs no mana")

func _stress(t) -> void:
	var cap: int
	var beam = _runner("form.beam")
	cap = beam.limits.get_limit("max_targets_per_pulse")
	for i in 20:
		beam.add_target(Vector2(220.0+float(i)*15.0,340),Vector2.ZERO,100000.0)
	beam.try_cast(0,beam.actor.position,Vector2.RIGHT)
	beam.step()
	t.equal(_count(beam,"hit"),cap,"AD-132 beam pulse hits capped at max_targets_per_pulse")
	var exceeded: Array = beam.trace.filter_records(-1,"","budget_exceeded").filter(func(e): return e["reason"] == "targets_per_pulse")
	t.equal(exceeded.size(),1,"AD-132 targets_per_pulse budget_exceeded traced once")
	var hit_targets: Array = beam.trace.filter_records(-1,"","hit").map(func(e): return e["target_id"])
	var sorted_ids := hit_targets.duplicate()
	sorted_ids.sort()
	t.equal(hit_targets,sorted_ids,"AD-132 capped beam hits are the nearest targets in stable order")
	_step(beam,400)
	var per_root := {}
	for entry in beam.trace.filter_records(-1,"","hit"):
		per_root[entry["root_cast_id"]] = int(per_root.get(entry["root_cast_id"],0))+1
	for root_id in per_root:
		t.check(int(per_root[root_id]) <= beam.limits.get_limit("max_events_per_root_cast"),"AD-132 beam events per root within cap")
	t.equal(beam.queue.active_effect_count(),0,"AD-132 beam stress ends with no active effects")
	var field = _runner("form.field")
	for i in 20:
		field.add_target(Vector2(300.0+float(i%5)*6.0,330.0+float(floori(float(i)/5.0))*6.0),Vector2.ZERO,100000.0)
	field.try_cast(0,field.actor.position,Vector2.RIGHT,Vector2(300,340))
	field.step()
	t.equal(_count(field,"hit"),cap,"AD-132 field pulse hits capped at max_targets_per_pulse")
	t.equal(field.trace.filter_records(-1,"","budget_exceeded").filter(func(e): return e["reason"] == "targets_per_pulse").size(),1,"AD-132 field cap traced once")
	# Spam every form for 600 ticks with free mana.
	var spam = Runner.new(7)
	spam.equip(0,_formula("form.beam"))
	spam.equip(1,_formula("form.field","essence.cold"))
	for i in 20:
		spam.add_target(Vector2(220.0+float(i)*15.0,340),Vector2.ZERO,1000000.0)
	var accepted := 0
	for tick in 600:
		spam.mana = 120.0
		for slot in 2:
			spam.loadout.slots[slot]["cooldown"] = 0
			if spam.try_cast(slot,spam.actor.position,Vector2.RIGHT,Vector2(300,340))["accepted"]:
				accepted += 1
		spam.step()
		t.check(spam._active_count("beam") <= spam.limits.get_limit("max_active_beams") and spam._active_count("field") <= spam.limits.get_limit("max_active_fields"),"AD-132 spam stays inside form budgets")
		if not spam.queue.active_effect_count() <= spam.limits.get_limit("max_active_effects"):
			t.check(false,"AD-132 spam exceeded max_active_effects")
			break
	t.check(accepted > 2,"AD-132 spam casts keep being accepted as effects expire")
	spam.loadout.slots[0]["cooldown"] = 999999
	spam.loadout.slots[1]["cooldown"] = 999999
	for i in 700:
		spam.mana = 120.0
		spam.step()
	t.equal(spam.queue.active_effect_count(),0,"AD-132 spam drains to zero active effects")
	t.equal(spam.active.size(),0,"AD-132 spam leaves no runner effects")

func _determinism(t) -> void:
	var traces: Array = []
	for n in 2:
		var r = Runner.new(132)
		r.equip(0,_formula("form.beam"))
		r.equip(1,_formula("form.field","essence.cold"))
		for i in 8:
			r.add_target(Vector2(240.0+float(i)*30.0,340.0+float(i%3)*10.0),Vector2.ZERO,100000.0)
		r.try_cast(0,r.actor.position,Vector2.RIGHT)
		r.try_cast(1,r.actor.position,Vector2.RIGHT,Vector2(330,340))
		_step(r,240)
		traces.append(r.trace_json())
	t.equal(traces[0],traces[1],"AD-132 same seed gives identical beam/field traces")
	t.check(traces[0].length() > 100,"AD-132 determinism trace is non-trivial")

func _golden_tests(t) -> void:
	var expected: Dictionary = t.fixture("ad_forms_traces_v1.json")
	for scenario in Golden.SCENARIOS:
		var played: Dictionary = Golden.play(scenario)
		t.check(not played["accepted"].has(false),"AD-132 "+scenario+" scripted cast accepted")
		t.equal(Golden.normalize(played["run"].trace.snapshot()),expected[scenario],"AD-132 "+scenario+" golden trace")
	var line: Dictionary = Golden.play("beam_line_pulses")
	t.equal(_hits(line["run"],line["targets"][0]),_hits(line["run"],line["targets"][1]),"AD-132 beam_line_pulses hits both targets equally")
	var wall: Dictionary = Golden.play("beam_wall_stop")
	t.equal(_hits(wall["run"],wall["targets"][1]),0,"AD-132 beam_wall_stop spares the target behind the wall")
	t.check(wall["targets"][0].hit_count > 0,"AD-132 beam_wall_stop hits the near target")
	var field: Dictionary = Golden.play("field_cold_freeze")
	t.check(field["targets"][0].status.has("frozen"),"AD-132 field_cold_freeze ends Frozen")
