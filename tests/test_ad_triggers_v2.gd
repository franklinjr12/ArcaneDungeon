extends RefCounted
## AD-134: On Kill, On Expire and Timer triggers (data, validation and compile). Values are proposed.
const Runner = preload("res://magic/runtime/spell_runner.gd")
const Golden = preload("res://tests/ad_triggers_golden_generator.gd")

const FORMS := ["form.projectile","form.burst","form.orb","form.beam","form.field"]
const LASTING := ["form.projectile","form.orb","form.beam","form.field"]
const NEW_TRIGGERS := ["trigger.on_kill","trigger.on_expire","trigger.timer"]

func _formula(form: String, trigger: String = "", payload_form: String = "form.burst", payload_mods: Array = []) -> Dictionary:
	var formula := {"schema_version":2,"formula_id":"test.%s.%s" % [form,trigger],"display_name":form,
		"root":{"essence_id":"essence.fire","manifestation_id":form,"modifier_ids":[],"params":{}}}
	if trigger != "":
		formula["on_hit"] = {"trigger_id":trigger,"payload":{"essence_id":"essence.water","manifestation_id":payload_form,"modifier_ids":payload_mods,"params":{}}}
	return formula

func run(t) -> void:
	_compile(t)
	_rejections(t)
	_payload_rules(t)
	_plan_snapshot(t)
	_runtime(t)
	_golden_tests(t)

func _compile(t) -> void:
	var r = Runner.new(134)
	for form in FORMS:
		t.check(r.equip(0,_formula(form,"trigger.on_kill"))["ok"],"AD-134 On Kill compiles on %s" % form)
	for trigger in ["trigger.on_expire","trigger.timer"]:
		for form in LASTING:
			t.check(r.equip(0,_formula(form,trigger))["ok"],"AD-134 %s compiles on %s" % [trigger,form])
	t.check(r.equip(0,_formula("form.projectile","trigger.on_hit"))["ok"],"AD-134 On Hit still compiles on projectile")

func _rejections(t) -> void:
	var r = Runner.new(134)
	for trigger in ["trigger.on_expire","trigger.timer"]:
		t.contains_issue(r.equip(0,_formula("form.burst",trigger))["issues"],"TRIGGER_INCOMPATIBLE","AD-134 %s rejected on burst" % trigger)
	t.contains_issue(r.equip(0,_formula("form.orb","trigger.on_hit"))["issues"],"TRIGGER_INCOMPATIBLE","AD-134 On Hit on orb still rejected")
	var bogus: Dictionary = r.equip(0,_formula("form.projectile","trigger.bogus"))
	var codes: Array = []
	for issue in bogus["issues"]:
		codes.append(issue["code"])
	t.check(not bogus["ok"] and ("RUNE_UNKNOWN" in codes or "TRIGGER_UNKNOWN" in codes),"AD-134 unknown trigger rejected")

func _payload_rules(t) -> void:
	var r = Runner.new(134)
	for trigger in NEW_TRIGGERS:
		t.contains_issue(r.equip(0,_formula("form.projectile",trigger,"form.orb"))["issues"],"PAYLOAD_FORM_INVALID","AD-134 %s non-burst payload rejected" % trigger)
		t.contains_issue(r.equip(0,_formula("form.projectile",trigger,"form.burst",["mod.chain"]))["issues"],"PAYLOAD_MODIFIER_FORBIDDEN","AD-134 %s payload modifier rejected" % trigger)

func _plan_snapshot(t) -> void:
	var r = Runner.new(134)
	r.equip(0,_formula("form.projectile","trigger.timer"))
	var plan: Dictionary = r.loadout.get_plan(0).snapshot()
	t.equal(int(plan["on_hit"]["trigger_params"]["interval_ticks"]),30,"AD-134 timer plan interval_ticks default")
	r.equip(1,_formula("form.projectile","trigger.on_kill"))
	t.equal(r.loadout.get_plan(1).snapshot()["on_hit"]["trigger_params"],{},"AD-134 on kill has no trigger params")
	r.equip(2,_formula("form.projectile","trigger.on_hit"))
	var on_hit_mana := int(r.loadout.get_plan(2).snapshot()["mana_cost"])
	var costs := {"trigger.on_kill":6,"trigger.on_expire":5,"trigger.timer":7}
	for trigger in NEW_TRIGGERS:
		r.equip(3,_formula("form.projectile",trigger))
		var with_trigger := int(r.loadout.get_plan(3).snapshot()["mana_cost"])
		t.equal(with_trigger - on_hit_mana,int(costs[trigger]) - 5,"AD-134 %s mana includes trigger rune cost" % trigger)

## --- Runtime (On Kill, On Expire, Timer; depth 1, event budgets) ---

## Returns [runner, targets]; targets are [position, hp] pairs. High-HP dummies unless a kill is wanted.
func _scene(form: String, trigger: String, targets: Array = [], payload_essence: String = "essence.lightning", seed_value: int = 134) -> Array:
	var r = Runner.new(seed_value)
	r.settings["combat"]["regen_mana_per_tick"] = 0.0
	var formula := _formula(form,trigger)
	formula["on_hit"]["payload"]["essence_id"] = payload_essence
	var equipped: Dictionary = r.equip(0,formula)
	if not equipped["ok"]:
		printerr("equip failed: ",equipped)
	var made: Array = []
	for item in targets:
		made.append(r.add_target(item[0],Vector2.ZERO,float(item[1])))
	r.mana = float(r.settings["combat"]["player_max_mana"])
	return [r,made]

func _cast(r, form: String, point = null) -> void:
	if form == "form.field" and point == null:
		point = Vector2(300,340)
	t_accept(r.try_cast(0,r.actor.position,Vector2.RIGHT,point))

func t_accept(result: Dictionary) -> void:
	if not result["accepted"]:
		printerr("cast rejected: ",result)

func _kind(r, type: String) -> Array:
	return r.trace.filter_records(-1,"",type)

func _triggers(r, reason: String) -> Array:
	return _kind(r,"trigger").filter(func(e): return str(e.get("reason","")) == reason)

func _step(r, ticks: int) -> void:
	for i in ticks:
		r.step()

func _step_until_idle(r, limit: int = 800) -> int:
	for i in limit:
		r.step()
		if r.active.is_empty() and r.queue.pending_count() == 0 and r._deferred_burst_cleanup.is_empty():
			return i+1
	return limit

func _budget_records(r, reason: String) -> Array:
	return _kind(r,"budget_exceeded").filter(func(e): return str(e["reason"]) == reason)

func _settled(t, r, label: String) -> void:
	t.equal(r.queue.active_effect_count(),0,"%s: all effect reservations released" % label)
	t.equal(r.active.size(),0,"%s: no runner effects left" % label)
	t.equal(r.queue.pending_count(),0,"%s: no pending events" % label)

func _spawns_at(r, pos: Vector2, depth: int) -> int:
	return _kind(r,"spawn").filter(func(e): return int(e["depth"]) == depth and absf(float(e["position"]["x"])-pos.x) < 0.01 and absf(float(e["position"]["y"])-pos.y) < 0.01).size()

func _runtime(t) -> void:
	_on_kill(t)
	_on_expire(t)
	_timer(t)
	_budgets(t)
	_stress(t)
	_determinism(t)

func _on_kill(t) -> void:
	var made := _scene("form.projectile","trigger.on_kill",[[Vector2(300,340),1.0]])
	var r = made[0]
	_cast(r,"form.projectile")
	_step_until_idle(r)
	var fired := _triggers(r,"trigger.on_kill")
	t.equal(fired.size(),1,"AD-134 on kill: exactly one trigger for one kill")
	t.equal(_kind(r,"trigger").size(),1,"AD-134 on kill: no other trigger records")
	if fired.size() == 1:
		t.equal(int(fired[0]["depth"]),1,"AD-134 on kill: trigger depth 1")
		t.equal(int(fired[0]["target_id"]),made[1][0].id,"AD-134 on kill: trigger names the killed target")
		t.check(_spawns_at(r,made[1][0].position,1) == 1,"AD-134 on kill: payload spawns at the killed target")
	_settled(t,r,"AD-134 on kill projectile")
	# Survivor: no trigger.
	var tough := _scene("form.projectile","trigger.on_kill",[[Vector2(300,340),100000.0]])
	_cast(tough[0],"form.projectile")
	_step_until_idle(tough[0])
	t.check(not _kind(tough[0],"hit").is_empty(),"AD-134 on kill: survivor was hit")
	t.equal(_kind(tough[0],"trigger").size(),0,"AD-134 on kill: no trigger when the target survives")
	# Burst root: two kills, two triggers.
	var burst := _scene("form.burst","trigger.on_kill",[[Vector2(200,340),1.0],[Vector2(200,360),1.0]])
	_cast(burst[0],"form.burst")
	_step_until_idle(burst[0])
	t.equal(_triggers(burst[0],"trigger.on_kill").size(),2,"AD-134 on kill: burst root killing two targets gives two triggers")
	_settled(t,burst[0],"AD-134 on kill burst")
	# Field root: two kills in one pulse, two triggers.
	var field := _scene("form.field","trigger.on_kill",[[Vector2(300,340),1.0],[Vector2(310,340),1.0],[Vector2(310,400),100000.0]])
	_cast(field[0],"form.field")
	_step_until_idle(field[0])
	t.equal(_triggers(field[0],"trigger.on_kill").size(),2,"AD-134 on kill: field root killing two targets gives two triggers")
	_settled(t,field[0],"AD-134 on kill field")
	# Depth stays 1: the payload kills a second 1-HP target and nothing further fires.
	var chain := _scene("form.projectile","trigger.on_kill",[[Vector2(300,340),1.0],[Vector2(330,340),1.0]])
	_cast(chain[0],"form.projectile")
	_step_until_idle(chain[0])
	var hits_on_second := _kind(chain[0],"hit").filter(func(e): return int(e["target_id"]) == chain[1][1].id)
	t.check(not chain[1][1].alive() and not hits_on_second.is_empty(),"AD-134 on kill: payload burst kills the second target")
	t.equal(_kind(chain[0],"trigger").size(),1,"AD-134 on kill: payload kill fires no further trigger")
	t.check(_kind(chain[0],"trigger").all(func(e): return int(e["depth"]) == 1),"AD-134 on kill: every trigger stays at depth 1")

func _on_expire(t) -> void:
	var made := _scene("form.projectile","trigger.on_expire")
	var r = made[0]
	_cast(r,"form.projectile")
	var effect = r.active[0]["effect"]
	_step_until_idle(r)
	var fired := _triggers(r,"trigger.on_expire")
	t.equal(fired.size(),1,"AD-134 on expire: projectile in empty space fires exactly once")
	var cleanup := _kind(r,"cleanup").filter(func(e): return int(e["effect_id"]) == effect.id)
	if fired.size() == 1 and cleanup.size() == 1:
		t.equal(int(fired[0]["tick"]),int(cleanup[0]["tick"]),"AD-134 on expire: fires on the cleanup tick")
		t.equal(int(fired[0]["depth"]),1,"AD-134 on expire: trigger depth 1")
		t.check(_spawns_at(r,effect.position,1) == 1,"AD-134 on expire: payload spawns at the projectile's final position")
	_settled(t,r,"AD-134 on expire projectile")
	# Beam released by the player ends at its end point.
	var beam := _scene("form.beam","trigger.on_expire")
	_cast(beam[0],"form.beam")
	_step(beam[0],20)
	var tip: Vector2 = beam[0].active[0]["effect"].end_point
	beam[0].stop_channel()
	_step_until_idle(beam[0])
	t.equal(_triggers(beam[0],"trigger.on_expire").size(),1,"AD-134 on expire: released beam fires once")
	t.check(_spawns_at(beam[0],tip,1) == 1,"AD-134 on expire: beam payload lands at end_point")
	_settled(t,beam[0],"AD-134 on expire beam")
	# Field fires at its centre.
	var field := _scene("form.field","trigger.on_expire")
	_cast(field[0],"form.field")
	var centre: Vector2 = field[0].active[0]["effect"].position
	_step_until_idle(field[0])
	t.equal(_triggers(field[0],"trigger.on_expire").size(),1,"AD-134 on expire: field fires once")
	t.check(_spawns_at(field[0],centre,1) == 1,"AD-134 on expire: field payload lands at its centre")
	_settled(t,field[0],"AD-134 on expire field")
	# Orb expires too.
	var orb := _scene("form.orb","trigger.on_expire")
	_cast(orb[0],"form.orb")
	_step_until_idle(orb[0])
	t.equal(_triggers(orb[0],"trigger.on_expire").size(),1,"AD-134 on expire: orb fires once")
	_settled(t,orb[0],"AD-134 on expire orb")

func _timer(t) -> void:
	var made := _scene("form.field","trigger.timer")
	var r = made[0]
	var duration := int(r.loadout.get_plan(0).snapshot()["root"]["params"]["field_duration_ticks"])
	var interval := int(r.loadout.get_plan(0).snapshot()["on_hit"]["trigger_params"]["interval_ticks"])
	var start: int = r.clock.tick
	_cast(r,"form.field")
	var centre: Vector2 = r.active[0]["effect"].position
	var field_id: int = r.active[0]["effect"].id
	_step_until_idle(r)
	var fired := _triggers(r,"trigger.timer")
	# A field is alive for D ticks (spawn+1..spawn+D) and cleans up on spawn+D+1, so it fires floor(D/interval) times.
	var expected := int(floor(float(duration)/float(interval)))
	t.check(expected >= 1,"AD-134 timer: field lasts long enough to fire (%d)" % expected)
	t.equal(fired.size(),expected,"AD-134 timer: field fires floor(D/interval) times")
	var ticks: Array = fired.map(func(e): return int(e["tick"])-start)
	var want: Array = []
	for k in range(1,expected+1):
		want.append(k*interval)
	t.equal(ticks,want,"AD-134 timer: fires at spawn + interval*k")
	t.check(_spawns_at(r,centre,1) == expected,"AD-134 timer: field payloads land at the field centre")
	var field_cleanup := _kind(r,"cleanup").filter(func(e): return int(e["effect_id"]) == field_id)
	t.equal(field_cleanup.size(),1,"AD-134 timer: field cleaned up once")
	t.equal(int(field_cleanup[0]["tick"])-start,duration+1,"AD-134 timer: field cleanup tick is spawn + D + 1")
	t.check(fired.is_empty() or int(fired.back()["tick"]) < int(field_cleanup[0]["tick"]),"AD-134 timer: nothing fires on or after the cleanup tick")
	_step(r,interval*3)
	t.equal(_triggers(r,"trigger.timer").size(),expected,"AD-134 timer: no fire after the field is gone")
	_settled(t,r,"AD-134 timer field")
	# Orb: payload at the orb's position.
	var orb := _scene("form.orb","trigger.timer")
	_cast(orb[0],"form.orb")
	var orb_effect = orb[0].active[0]["effect"]
	_step(orb[0],interval)
	var orb_fired := _triggers(orb[0],"trigger.timer")
	t.equal(orb_fired.size(),1,"AD-134 timer: orb fires at the first interval")
	t.check(_spawns_at(orb[0],orb_effect.position,1) == 1,"AD-134 timer: orb payload lands at the orb position")
	_step_until_idle(orb[0])
	_settled(t,orb[0],"AD-134 timer orb")
	# Timer never fires on an expiry tick: lifetime shorter than the interval gives zero fires.
	var short := _scene("form.projectile","trigger.timer")
	var short_start: int = short[0].clock.tick
	_cast(short[0],"form.projectile")
	var short_id: int = short[0].active[0]["effect"].id
	_step_until_idle(short[0])
	var short_cleanup := int(_kind(short[0],"cleanup").filter(func(e): return int(e["effect_id"]) == short_id)[0]["tick"])
	var short_fired := _triggers(short[0],"trigger.timer")
	t.equal(short_fired.size(),int(floor(float(short_cleanup-short_start-1)/float(interval))),"AD-134 timer: projectile fires only while alive")
	t.check(short_fired.all(func(e): return int(e["tick"]) < short_cleanup),"AD-134 timer: projectile never fires on its expiry tick")

func _budgets(t) -> void:
	# Per-root event cap lowered: triggers stop, one budget record, the game keeps ticking.
	var made := _scene("form.field","trigger.timer",[[Vector2(300,340),100000.0],[Vector2(310,340),100000.0],[Vector2(300,350),100000.0]])
	var r = made[0]
	var limits: Dictionary = r.limits.snapshot()
	limits["max_events_per_root_cast"] = 3
	r.limits.configure(limits)
	_cast(r,"form.field")
	_step_until_idle(r)
	var root_id: int = _kind(r,"cast_requested")[0]["root_cast_id"]
	var breaches := _budget_records(r,"events_per_cast")
	t.equal(breaches.size(),1,"AD-134 budget: exactly one events_per_cast record for the root")
	if breaches.size() == 1:
		t.equal(int(breaches[0]["root_cast_id"]),root_id,"AD-134 budget: the breach names the root cast")
		t.equal(int(breaches[0]["limit"]),3,"AD-134 budget: the breach carries the lowered limit")
	var counted := _kind(r,"hit").size()+_kind(r,"trigger").size()
	t.check(counted <= 3,"AD-134 budget: hit+trigger events within the lowered cap (%d)" % counted)
	t.check(_kind(r,"trigger").size() <= 3,"AD-134 budget: triggers stop at the cap")
	_step(r,60)
	_settled(t,r,"AD-134 budget breach")
	# Depth breach: a depth-1 context cannot fire a trigger.
	var deep := _scene("form.projectile","trigger.on_kill")
	var d = deep[0]
	_cast(d,"form.projectile")
	var entry: Dictionary = d.active[0]
	var ctx: Dictionary = entry["context"].duplicate(true)
	ctx["depth"] = 1
	t.check(not d._fire_trigger(entry["trigger"],ctx,entry["effect"].id,0,Vector2(300,340)),"AD-134 depth: depth-1 context cannot fire a trigger")
	t.equal(_budget_records(d,"event_depth").size(),1,"AD-134 depth: rejection logs event_depth")
	t.equal(_kind(d,"trigger").size(),0,"AD-134 depth: no trigger record for the rejected push")
	_step_until_idle(d)
	_settled(t,d,"AD-134 depth breach")

func _stress(t) -> void:
	var made := _scene("form.projectile","trigger.on_kill")
	var r = made[0]
	_cast(r,"form.projectile")
	var entry: Dictionary = r.active[0]
	var root_id := int(entry["context"]["root_cast_id"])
	var cap: int = r.limits.get_limit("max_events_per_root_cast")
	var used := int(r.queue._event_counts.get(root_id,0))
	var accepted := 0
	for i in 10000:
		if r._fire_trigger(entry["trigger"],entry["context"],entry["effect"].id,0,Vector2(300,340)):
			accepted += 1
	t.equal(accepted,cap-used,"AD-134 stress: accepted triggers equal the per-root cap minus events already used")
	t.equal(_kind(r,"trigger").size(),accepted,"AD-134 stress: one trigger record per accepted event")
	t.check(_kind(r,"trigger").size() <= cap,"AD-134 stress: trigger records within the cap")
	var ticks := 0
	while r.queue.pending_count() > 0 and ticks < 200:
		r.step()
		ticks += 1
	t.equal(r.queue.pending_count(),0,"AD-134 stress: queue drains within 200 ticks")
	_step_until_idle(r)
	for reason in ["events_per_cast","effects_per_cast","active_effects"]:
		t.check(_budget_records(r,reason).size() <= 1,"AD-134 stress: at most one budget_exceeded for %s" % reason)
	t.equal(_budget_records(r,"events_per_cast").size(),1,"AD-134 stress: one events_per_cast record")
	t.equal(r.queue.active_effect_count(),0,"AD-134 stress: active effect count back to 0")
	t.equal(r.active.size(),0,"AD-134 stress: no runner effects left")
	t.equal(r._contexts.size(),0,"AD-134 stress: no event contexts left")

func _determinism(t) -> void:
	var traces: Array = []
	for n in 2:
		var made := _scene("form.field","trigger.timer",[[Vector2(300,340),100000.0],[Vector2(310,340),100000.0]],"essence.lightning",77)
		_cast(made[0],"form.field")
		_step_until_idle(made[0])
		var kill := _scene("form.projectile","trigger.on_kill",[[Vector2(300,340),1.0],[Vector2(330,340),1.0]],"essence.lightning",77)
		_cast(kill[0],"form.projectile")
		_step_until_idle(kill[0])
		traces.append(made[0].trace_json()+kill[0].trace_json())
	t.equal(traces[0],traces[1],"AD-134 same seed gives identical Timer + On Kill traces")
	t.check(traces[0].contains("trigger.timer") and traces[0].contains("trigger.on_kill"),"AD-134 determinism traces include both triggers")

func _golden_tests(t) -> void:
	var expected: Dictionary = t.fixture("ad_triggers_traces_v1.json")
	for scenario in Golden.SCENARIOS:
		var played: Dictionary = Golden.play(scenario)
		t.check(not played["accepted"].has(false),"AD-134 "+scenario+" scripted casts accepted")
		t.equal(Golden.normalize(played["run"].trace.snapshot()),expected[scenario],"AD-134 "+scenario+" golden trace")
