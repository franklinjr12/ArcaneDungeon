extends RefCounted
## AD-193: mana pressure, resonance refunds, reaction bonus damage, alternation beats mono-spam.
const Runner = preload("res://magic/runtime/spell_runner.gd")
const Compiler = preload("res://magic/compile/spell_compiler.gd")
const Target = preload("res://combat/magic_target.gd")
const Resolver = preload("res://combat/interaction_resolver.gd")
const Store = preload("res://combat/target_store.gd")

const CADENCE := 8

func _shot(essence: String) -> Dictionary:
	return {"schema_version":1,"formula_id":"test."+essence,"display_name":essence,
		"root":{"essence_id":essence,"manifestation_id":"form.projectile","modifier_ids":[],"params":{}}}

func _payload(essence: String) -> Dictionary:
	return {"team":1,"cast_id":3,"root_cast_id":3,"formula_id":"test","essence_id":essence,"damage":10.0,"caster_id":1}

## Casts slot 0 every CADENCE ticks for `ticks`; returns {first_reject, accepts, attempts, mana_rejects}.
func _mana_run(r, ticks: int) -> Dictionary:
	var out := {"first_reject":-1,"accepts":0,"attempts":0,"mana_rejects":0,"accepts_after":0,"attempts_after":0}
	for i in ticks:
		if i % CADENCE == 0:
			var res: Dictionary = r.try_cast(0,r.actor.position,Vector2.RIGHT)
			out["attempts"] += 1
			if res["accepted"]:
				out["accepts"] += 1
			elif r.last_rejection == "INSUFFICIENT_MANA":
				out["mana_rejects"] += 1
				if out["first_reject"] < 0:
					out["first_reject"] = i
			if out["first_reject"] >= 0:
				out["attempts_after"] += 1
				if res["accepted"]:
					out["accepts_after"] += 1
		r.step()
	return out

func _mana_tests(t) -> void:
	var fire = Runner.new(193)
	fire.equip(0,_shot("essence.fire"))
	var f: Dictionary = _mana_run(fire,4200)
	print("AD-193 fire first dry tick=%d steady accept rate=%.3f" % [f["first_reject"],float(f["accepts_after"])/maxf(1.0,float(f["attempts_after"]))])
	t.check(f["first_reject"] >= 360 and f["first_reject"] <= 480,"AD-193 fire spam runs dry in 6-8 s (tick %d)" % f["first_reject"])
	var rate: float = float(f["accepts_after"])/maxf(1.0,float(f["attempts_after"]))
	t.check(rate >= 0.60 and rate <= 0.70,"AD-193 fire steady uptime 60-70%% (%.3f)" % rate)
	var bolt = Runner.new(193)
	bolt.equip_builtin(0,Compiler.load_builtin_definition()["definition"])
	var b: Dictionary = _mana_run(bolt,3600)
	t.equal(b["mana_rejects"],0,"AD-193 Basic Bolt never runs out of mana")

## Sets the pre-state, casts one hit, returns [runner, mana_gain_over_regen_baseline setup].
func _react(case_id: String, refund: float):
	var r = Runner.new(193)
	var table: Dictionary = r.settings["reactions"]["resonance"]["mana_refund"]
	if table.has(case_id):
		table[case_id] = refund
	var a = r.add_target(r.actor.position + Vector2(300,0),Vector2.ZERO,100000.0)
	var b = r.add_target(r.actor.position + Vector2(300,60),Vector2.ZERO,100000.0)
	var st: Dictionary = r.settings["statuses"]
	var essence := ""
	match case_id:
		"wet_lightning_arc":
			a.status.apply("wet",0,st["wet"]); b.status.apply("wet",0,st["wet"]); essence = "essence.lightning"
		"wet_cold_freeze":
			a.status.apply("wet",0,st["wet"]); essence = "essence.cold"
		"frozen_force_shatter":
			a.status.apply("frozen",0,st["frozen"]); essence = "essence.force"
		"fire_thaw_steam":
			a.status.apply("chilled",0,st["chilled"]); essence = "essence.fire"
		"water_extinguish":
			a.status.apply("burning",0,st["burning"]); essence = "essence.water"
		"chill_freeze":
			for i in 2:
				a.status.apply("chilled",0,st["chilled"])
			essence = "essence.cold"
	r.equip(0,_shot(essence))
	r.mana = 60.0
	r.try_cast(0,r.actor.position,Vector2.RIGHT)
	for i in 90:
		r.step()
	return r

func _refund_tests(t) -> void:
	for id in ["wet_lightning_arc","wet_cold_freeze","frozen_force_shatter","fire_thaw_steam","water_extinguish"]:
		var on = _react(id,12.0)
		var off = _react(id,0.0)
		t.check(absf((on.mana - off.mana) - 12.0) < 0.001,"AD-193 %s refunds 12 mana (%.2f)" % [id,on.mana-off.mana])
		var hit: Array = on.resonance_popups.filter(func(p): return p["id"] == id)
		t.check(hit.size() == 1 and hit[0]["amount"] == 12,"AD-193 %s popup id+amount" % id)
		t.check(off.resonance_popups.is_empty(),"AD-193 %s no popup when refund is 0" % id)
	# chill_freeze (mono-Cold) is single-element: no refund, no popup.
	var cf = _react("chill_freeze",12.0)
	var base = _react("chill_freeze",0.0)
	t.check(cf.resonance_popups.is_empty() and absf(cf.mana-base.mana) < 0.001,"AD-193 chill_freeze does not refund")
	# Dry lightning arc (conductor tag, no Wet) does not refund.
	var dry = Runner.new(193)
	dry.add_target(dry.actor.position + Vector2(300,0),Vector2.ZERO,100000.0).tags = ["conductor"]
	dry.add_target(dry.actor.position + Vector2(300,60),Vector2.ZERO,100000.0)
	dry.equip(0,_shot("essence.lightning"))
	dry.try_cast(0,dry.actor.position,Vector2.RIGHT)
	for i in 90:
		dry.step()
	t.check(dry.resonance_popups.is_empty(),"AD-193 dry conductor arc does not refund")

func _damage_tests(t) -> void:
	var settings: Dictionary = Runner.new(193).settings
	var res = Resolver.new(settings)
	var st: Dictionary = settings["statuses"]
	var cases := [["wet_cold_freeze","essence.cold","wet"],["frozen_force_shatter","essence.force","frozen"],
		["fire_thaw_steam","essence.fire","chilled"],["water_extinguish","essence.water","burning"]]
	for c in cases:
		var store = Store.new()
		var clean = Target.new(10,2,Vector2(300,300),5000)
		var prim = Target.new(11,2,Vector2(900,900),5000)
		store.add(clean); store.add(prim)
		prim.status.apply(c[2],0,st[c[2]])
		var plain: Dictionary = res.resolve(_payload(c[1]),clean,store,1)
		var out: Dictionary = res.resolve(_payload(c[1]),prim,store,1)
		var total := float(out["damage"])
		for e in out["reactions"]:
			total += float(e["bonus_damage"])
		t.check(total > float(plain["damage"])*1.2,"AD-193 %s deals more than the plain hit (%.1f vs %.1f)" % [c[0],total,plain["damage"]])
	var store2 = Store.new()
	var w1 = Target.new(20,2,Vector2(300,300),5000)
	var w2 = Target.new(21,2,Vector2(340,300),5000)
	for w in [w1,w2]:
		store2.add(w)
		w.status.apply("wet",0,st["wet"])
	var arc: Dictionary = res.resolve(_payload("essence.lightning"),w1,store2,1)
	t.check(not arc["reaction"].is_empty() and float(arc["reaction"]["damage"]) > 9.0,"AD-193 conduct arc deals ~x1.5 of the hit (%.1f)" % float(arc["reaction"].get("damage",0)))

## 30 s, one cast attempt per CADENCE ticks at 3 static dummies; returns total damage dealt.
func _sim(mode: String, essence: String) -> float:
	var r = Runner.new(193)
	var dummies: Array = []
	for deg in [-20.0,0.0,20.0]:
		dummies.append(r.add_target(r.actor.position + Vector2.RIGHT.rotated(deg_to_rad(deg))*300.0,Vector2.ZERO,1000000.0))
	if mode == "mono":
		r.equip(0,_shot(essence))
	else:
		r.equip(0,_shot("essence.cold"))
		r.equip(1,_shot("essence.fire"))
	var n := 0
	for i in 1800:
		if i % CADENCE == 0:
			var target = dummies[(n/2 if mode == "alt" else n) % 3]
			var slot := 0 if mode == "mono" else n % 2
			r.try_cast(slot,r.actor.position,(target.position - r.actor.position).normalized())
			n += 1
		r.step()
	var total := 0.0
	for d in dummies:
		total += 1000000.0 - float(d.health.current)
	return total

func _sim_tests(t) -> void:
	var best := 0.0
	var best_id := ""
	for e in ["essence.fire","essence.water","essence.lightning","essence.cold","essence.force"]:
		var d := _sim("mono",e)
		print("AD-193 mono %s 30s damage=%.0f" % [e,d])
		if d > best:
			best = d
			best_id = e
	var alt := _sim("alt","")
	print("AD-193 alt cold+fire 30s damage=%.0f (best mono %s %.0f, ratio %.2f)" % [alt,best_id,best,alt/maxf(1.0,best)])
	t.check(alt >= 1.15*best,"AD-193 alternation >= 1.15x best mono-spam (%.0f vs %.0f)" % [alt,best])
	t.equal(_sim("alt",""),alt,"AD-193 alternation sim is deterministic")

func run(t) -> void:
	_mana_tests(t)
	_refund_tests(t)
	_damage_tests(t)
	_sim_tests(t)
