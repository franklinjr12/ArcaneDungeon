extends RefCounted
## AD-133: Chain, Expand and Rapid modifiers (compile-time scaling and validation).
const Runner = preload("res://magic/runtime/spell_runner.gd")

const FORMS := ["form.projectile","form.burst","form.orb","form.beam","form.field"]
const NEW_MODS := ["mod.chain","mod.expand","mod.rapid"]

func _formula(form: String, modifiers: Array = [], essence: String = "essence.fire") -> Dictionary:
	return {"schema_version":2,"formula_id":"test.%s.%s" % [form,"_".join(modifiers)],"display_name":form,
		"root":{"essence_id":essence,"manifestation_id":form,"modifier_ids":modifiers,"params":{}}}

func _plan(form: String, modifiers: Array) -> Dictionary:
	var r = Runner.new(133)
	var equipped: Dictionary = r.equip(0,_formula(form,modifiers))
	if not equipped["ok"]:
		printerr("equip failed: ",equipped)
		return {}
	return r.loadout.get_plan(0).snapshot()

func run(t) -> void:
	_compile(t)
	_expand(t)
	_rapid(t)
	_order(t)
	_chain(t)
	_expand_runtime(t)
	_rapid_runtime(t)
	_order_runtime(t)
	_determinism(t)
	_stress(t)

func _compile(t) -> void:
	var r = Runner.new(133)
	for form in FORMS:
		for mod in NEW_MODS:
			t.check(r.equip(0,_formula(form,[mod]))["ok"],"AD-133 %s + %s compiles" % [form,mod])
	var homing: Dictionary = r.equip(1,_formula("form.beam",["mod.homing"]))
	t.contains_issue(homing["issues"],"MODIFIER_INCOMPATIBLE","AD-133 homing on beam still incompatible")
	var payload := _formula("form.projectile")
	payload["on_hit"] = {"trigger_id":"trigger.on_hit","payload":{"essence_id":"essence.fire","manifestation_id":"form.burst","modifier_ids":["mod.chain"],"params":{}}}
	t.contains_issue(r.equip(2,payload)["issues"],"PAYLOAD_MODIFIER_FORBIDDEN","AD-133 payload modifier still forbidden")

func _approx(a, b) -> bool:
	return absf(float(a) - float(b)) < 0.001

func _expand(t) -> void:
	for form in FORMS:
		var plain := _plan(form,[])
		var plan := _plan(form,["mod.expand"])
		var p: Dictionary = plain_params(plain)
		var q: Dictionary = plan_params(plan)
		var scaled: Array = {"form.projectile":["radius","speed"],"form.burst":["burst_radius"],"form.orb":["orb_radius","angular_speed"],
			"form.beam":["beam_length","tick_interval_ticks"],"form.field":["field_radius","tick_interval_ticks"]}[form]
		var factors: Dictionary = {"radius":1.5,"speed":0.7,"burst_radius":1.5,"orb_radius":1.5,"angular_speed":0.7,"beam_length":1.5,"field_radius":1.5}
		for key in scaled:
			if key == "tick_interval_ticks":
				t.equal(int(q[key]),ceili(float(p[key]) / 0.7 - 0.0001),"AD-133 %s expand %s" % [form,key])
			else:
				t.check(_approx(q[key],minf(float(p[key]) * factors[key],_max_of(plan,key))),"AD-133 %s expand %s scaled" % [form,key])
		if form == "form.burst":
			t.equal(int(plan["cooldown_ticks"]),ceili(float(plain["cooldown_ticks"]) / 0.7 - 0.0001),"AD-133 burst expand slows cooldown")

func plain_params(plan: Dictionary) -> Dictionary:
	return plan["root"]["params"]

func plan_params(plan: Dictionary) -> Dictionary:
	return plan["root"]["params"]

func _max_of(plan: Dictionary, key: String) -> float:
	return float(plan["root"]["manifestation"]["params"][key]["max"])

func _rapid(t) -> void:
	for form in FORMS:
		var plain := _plan(form,[])
		var plan := _plan(form,["mod.rapid"])
		t.check(int(plan["cooldown_ticks"]) < int(plain["cooldown_ticks"]),"AD-133 %s rapid shortens cooldown" % form)
		t.check(_approx(plan["root"]["params"]["base_damage"],float(plain["root"]["params"]["base_damage"]) * 0.7),"AD-133 %s rapid damage x0.7" % form)

func _order(t) -> void:
	for form in FORMS:
		var a := _plan(form,["mod.chain","mod.expand","mod.rapid"])
		var b := _plan(form,["mod.rapid","mod.expand","mod.chain"])
		t.equal(a["root"]["params"],b["root"]["params"],"AD-133 %s modifier order has no effect on params" % form)
		t.equal(a["cooldown_ticks"],b["cooldown_ticks"],"AD-133 %s modifier order has no effect on cooldown" % form)

## --- Runtime (chain, expand, rapid x form) ---

func _runner(form: String, modifiers: Array, points: Array, essence: String = "essence.fire", fid: String = "") -> Array:
	var r = Runner.new(133)
	r.settings["combat"]["regen_mana_per_tick"] = 0.0
	r.mana = float(r.settings["combat"]["player_max_mana"])
	var formula := _formula(form,modifiers,essence)
	if not fid.is_empty():
		formula["formula_id"] = fid
	var equipped: Dictionary = r.equip(0,formula)
	if not equipped["ok"]:
		printerr("equip failed: ",equipped)
	var made: Array = []
	for point in points:
		made.append(r.add_target(point,Vector2.ZERO,100000.0))
	return [r,made]

func _kind(r, kind: String) -> Array:
	return r.trace.filter_records(-1,"",kind)

func _hits_on(r, target) -> int:
	return _kind(r,"hit").filter(func(e): return int(e["target_id"]) == target.id).size()

func _cast(r, form: String) -> void:
	var point = Vector2(300,340) if form == "form.field" else null
	r.try_cast(0,r.actor.position,Vector2.RIGHT,point)

func _step(r, ticks: int) -> void:
	for i in ticks:
		r.step()

## Primary in contact; two chain targets further on; one out of range of everything.
const CHAIN_LAYOUT := {
	"form.projectile":[Vector2(300,340),Vector2(400,340),Vector2(500,340),Vector2(500,600)],
	"form.burst":[Vector2(200,340),Vector2(300,340),Vector2(400,340),Vector2(700,340)],
	"form.orb":[Vector2(212,340),Vector2(312,340),Vector2(412,340),Vector2(700,340)],
	"form.beam":[Vector2(200,340),Vector2(200,440),Vector2(200,540),Vector2(700,340)],
	"form.field":[Vector2(300,340),Vector2(400,340),Vector2(500,340),Vector2(700,340)],
}

func _chain(t) -> void:
	for form in FORMS:
		var made := _runner(form,["mod.chain"],CHAIN_LAYOUT[form])
		var r = made[0]
		var ts: Array = made[1]
		_cast(r,form)
		for i in 80:
			r.step()
			if not _kind(r,"hit").is_empty():
				break
		t.check(not _kind(r,"hit").is_empty(),"AD-133 %s chain: primary hit landed" % form)
		var chains := _kind(r,"chain")
		t.equal(chains.size(),2,"AD-133 %s chain: exactly chain_count jumps after the first hit" % form)
		if chains.size() == 2:
			t.equal([int(chains[0]["target_id"]),int(chains[1]["target_id"])],[ts[1].id,ts[2].id],"AD-133 %s chain: nearest-first order" % form)
			t.equal(int(chains[0]["source_id"]),ts[0].id,"AD-133 %s chain: first jump leaves the primary" % form)
			t.equal(int(chains[1]["source_id"]),ts[1].id,"AD-133 %s chain: second jump leaves the first chain target" % form)
		t.equal(_hits_on(r,ts[3]),0,"AD-133 %s chain: far target untouched" % form)
		t.check(_hits_on(r,ts[1]) > 0 and _hits_on(r,ts[2]) > 0,"AD-133 %s chain: chained targets are damaged" % form)
		_step(r,500)
		var seen := {}
		var dup := false
		for c in _kind(r,"chain"):
			dup = dup or seen.has(int(c["target_id"]))
			seen[int(c["target_id"])] = true
		t.check(not dup,"AD-133 %s chain: no target chained twice over the full lifetime" % form)
		t.check(not seen.has(ts[0].id),"AD-133 %s chain: primary never chained" % form)
		t.check(_kind(r,"chain").size() <= r.limits.get_limit("max_chain_targets"),"AD-133 %s chain: bounded by max_chain_targets" % form)
		t.equal(r._chain_seen.size(),0,"AD-133 %s chain: seen set pruned after the cast" % form)
	# Plain spells never chain.
	var plain := _runner("form.burst",[],CHAIN_LAYOUT["form.burst"])
	_cast(plain[0],"form.burst")
	_step(plain[0],5)
	t.equal(_kind(plain[0],"chain").size(),0,"AD-133 spells without chain emit no chain traces")

func _reach_scene(form: String, modifiers: Array) -> Array:
	var pos: Vector2 = {"form.projectile":Vector2(300,371),"form.burst":Vector2(240,340),"form.orb":Vector2(249,340),
		"form.beam":Vector2(540,340),"form.field":Vector2(420,340)}[form]
	var made := _runner(form,modifiers,[pos])
	if form == "form.field":
		made[0].try_cast(0,made[0].actor.position,Vector2.RIGHT,Vector2(330,340))
	else:
		_cast(made[0],form)
	_step(made[0],150)
	return [made[0],made[1][0]]

func _expand_runtime(t) -> void:
	for form in FORMS:
		var plain := _reach_scene(form,[])
		var wide := _reach_scene(form,["mod.expand"])
		t.equal(_hits_on(plain[0],plain[1]),0,"AD-133 %s plain misses the edge target" % form)
		t.check(_hits_on(wide[0],wide[1]) > 0,"AD-133 %s expand reaches the edge target" % form)
	# Slower: fewer pulses / less travel over the same ticks.
	for form in ["form.beam","form.field"]:
		var counts: Array = []
		for mods in [[],["mod.expand"]]:
			var made := _runner(form,mods,[Vector2(300,340)])
			if form == "form.field":
				made[0].try_cast(0,made[0].actor.position,Vector2.RIGHT,Vector2(300,340))
			else:
				_cast(made[0],form)
			_step(made[0],120)
			counts.append(_hits_on(made[0],made[1][0]))
		t.check(counts[1] < counts[0],"AD-133 %s expand pulses slower (%s vs %s)" % [form,counts[1],counts[0]])
	var travel: Array = []
	var swept: Array = []
	for mods in [[],["mod.expand"]]:
		var proj := _runner("form.projectile",mods,[])
		_cast(proj[0],"form.projectile")
		_step(proj[0],10)
		travel.append(proj[0].active[0]["effect"].position.x-140.0)
		var orb := _runner("form.orb",mods,[])
		_cast(orb[0],"form.orb")
		_step(orb[0],30)
		swept.append(orb[0].active[0]["effect"].angle)
	t.check(travel[1] < travel[0],"AD-133 expanded projectile travels less per tick")
	t.check(swept[1] < swept[0],"AD-133 expanded orb sweeps less per tick")

func _rapid_runtime(t) -> void:
	for form in FORMS:
		var amounts: Array = []
		var cooldowns: Array = []
		for mods in [[],["mod.rapid"]]:
			var made := _runner(form,mods,[{"form.orb":Vector2(212,340),"form.burst":Vector2(200,340),"form.field":Vector2(300,340)}.get(form,Vector2(240,340))])
			var r = made[0]
			_cast(r,form)
			var plan: Dictionary = r.loadout.get_plan(0).snapshot()
			t.equal(int(r.loadout.slots[0]["cooldown"]),int(plan["cooldown_ticks"]),"AD-133 %s slot cooldown equals plan cooldown" % form)
			cooldowns.append(int(r.loadout.slots[0]["cooldown"]))
			_step(r,40)
			var hits := _kind(r,"hit")
			amounts.append(int(hits[0]["amount"]) if not hits.is_empty() else -1)
		t.check(amounts[0] > 0 and amounts[1] > 0 and amounts[1] < amounts[0],"AD-133 %s rapid hit amount lower (%s vs %s)" % [form,amounts[1],amounts[0]])
		t.check(cooldowns[1] < cooldowns[0],"AD-133 %s rapid cooldown lower (%s vs %s)" % [form,cooldowns[1],cooldowns[0]])

func _order_runtime(t) -> void:
	var traces: Array = []
	for mods in [["mod.chain","mod.expand","mod.rapid"],["mod.rapid","mod.chain","mod.expand"]]:
		var made := _runner("form.projectile",mods,CHAIN_LAYOUT["form.projectile"],"essence.fire","same")
		_cast(made[0],"form.projectile")
		_step(made[0],100)
		traces.append(made[0].trace_json())
	t.equal(traces[0],traces[1],"AD-133 modifier order gives identical runtime traces")
	t.check(traces[0].contains("\"chain\""),"AD-133 order trace includes chain jumps")

func _determinism(t) -> void:
	var traces: Array = []
	var points: Array = []
	for i in 6:
		points.append(Vector2(300.0+float(i)*45.0,340.0+float(i%2)*20.0))
	for n in 2:
		var made := _runner("form.projectile",["mod.chain","mod.expand","mod.rapid"],points,"essence.lightning")
		_cast(made[0],"form.projectile")
		_step(made[0],200)
		traces.append(made[0].trace_json())
	t.equal(traces[0],traces[1],"AD-133 same seed gives identical chain+expand+rapid lightning traces")
	t.check(traces[0].contains("\"chain\""),"AD-133 determinism trace includes chain jumps")

func _stress(t) -> void:
	var points: Array = []
	for i in 20:
		points.append(Vector2(220.0+float(i)*15.0,340))
	var made := _runner("form.beam",["mod.chain"],points)
	var r = made[0]
	_cast(r,"form.beam")
	for i in 400:
		r.mana = 120.0
		r.step()
	var per_root := {}
	for kind in ["hit","chain"]:
		for e in _kind(r,kind):
			per_root[e["root_cast_id"]] = int(per_root.get(e["root_cast_id"],0))+1
	for root_id in per_root:
		t.check(int(per_root[root_id]) <= r.limits.get_limit("max_events_per_root_cast"),"AD-133 chain beam events per root within cap (%s)" % per_root[root_id])
	t.equal(r.queue.active_effect_count(),0,"AD-133 chain beam stress drains active effects")
	t.equal(r.active.size(),0,"AD-133 chain beam stress leaves no runner effects")
	t.equal(r._chain_seen.size(),0,"AD-133 chain beam stress empties the seen set")
