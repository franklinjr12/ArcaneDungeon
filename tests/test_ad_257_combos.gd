extends RefCounted
## AD-257: elemental combos beat single-skill spam. Numbers live in combat/combat_tuning_v1.json key "combos".
const Runner = preload("res://magic/runtime/spell_runner.gd")
const Session = preload("res://combat/combat_session.gd")

const TUNING_PATH := "res://combat/combat_tuning_v1.json"
const SEEDS := [257001, 257002, 257003]
const WINDOW_TICKS := 600
const CADENCE := 8

var _current := ""

func run(t) -> void:
	test_ad_257_a_lightning_on_wet_extra_ticks(t)
	test_ad_257_b_shatter_stun_and_immunity(t)
	test_ad_257_c_melt_and_instant_freeze(t)
	test_ad_257_d_combo_dps_bar(t)
	test_ad_257_e_popup_and_hit_stop(t)

## The "combos" block, or {} (callers check keys via _need so a missing block fails instead of crashing).
func _combos() -> Dictionary:
	var file := FileAccess.open(TUNING_PATH,FileAccess.READ)
	if file == null:
		return {}
	var parsed = JSON.parse_string(file.get_as_text())
	if typeof(parsed) != TYPE_DICTIONARY or typeof(parsed.get("combos")) != TYPE_DICTIONARY:
		return {}
	return parsed["combos"]

func _need(t, combos: Dictionary, path: String) -> bool:
	var node: Variant = combos
	for key in path.split("."):
		if typeof(node) != TYPE_DICTIONARY or not node.has(key):
			t.check(false,"%s: combat_tuning_v1.json combos.%s exists" % [_current,path])
			return false
		node = node[key]
	return true

func _val(combos: Dictionary, path: String) -> Variant:
	var node: Variant = combos
	for key in path.split("."):
		node = node[key]
	return node

func _shot(essence: String) -> Dictionary:
	return {"schema_version":1,"formula_id":"test."+essence,"display_name":essence,
		"root":{"essence_id":essence,"manifestation_id":"form.projectile","modifier_ids":[],"params":{}}}

func _status(r, id: String) -> Dictionary:
	return r.settings["statuses"][id]

## One cast of `essence` at a single target `pre`-statused; runs 90 ticks. Returns [runner, target].
func _single_hit(seed_value: int, pre: String, essence: String):
	var r = Runner.new(seed_value)
	var target = r.add_target(r.actor.position + Vector2(300,0),Vector2.ZERO,100000.0)
	if pre != "":
		target.status.apply(pre,0,_status(r,pre))
	r.equip(0,_shot(essence))
	r.mana = 60.0
	r.try_cast(0,r.actor.position,Vector2.RIGHT)
	for i in 90:
		r.step()
	return [r,target]

# a) Lightning on a Wet target adds combos.conduct.extra_ticks damage ticks of the hit's own damage.
func test_ad_257_a_lightning_on_wet_extra_ticks(t) -> void:
	_current = "test_ad_257_a_lightning_on_wet_extra_ticks"
	var combos := _combos()
	if not _need(t,combos,"conduct.extra_ticks"):
		return
	var extra_ticks := int(_val(combos,"conduct.extra_ticks"))
	t.equal(extra_ticks,3,"test_ad_257_a_lightning_on_wet_extra_ticks: conduct.extra_ticks is 3")
	var dry = _single_hit(257001,"","essence.lightning")
	var wet = _single_hit(257001,"wet","essence.lightning")
	var dry_total: float = dry[1].total_received
	var wet_total: float = wet[1].total_received
	t.check(dry_total > 0.0,"test_ad_257_a_lightning_on_wet_extra_ticks: dry lightning hit deals damage (%.2f)" % dry_total)
	t.check(wet_total > dry_total,"test_ad_257_a_lightning_on_wet_extra_ticks: lightning on Wet deals more total damage (%.2f vs %.2f)" % [wet_total,dry_total])
	var tick_damage: float = float(dry[1].damage_log[0]["amount"]) if not dry[1].damage_log.is_empty() and dry[1].damage_log[0].has("amount") else dry_total
	t.check(absf((wet_total-dry_total) - extra_ticks*tick_damage) < 0.01*maxf(1.0,tick_damage),
		"test_ad_257_a_lightning_on_wet_extra_ticks: wet-lightning extra damage == %d ticks of the hit damage (extra %.2f, tick %.2f)" % [extra_ticks,wet_total-dry_total,tick_damage])

## Session with one frozen enemy 200 px in front of the player; returns [session, enemy].
func _frozen_enemy_session(seed_value: int, kind: String = "bone_thrall"):
	var s = Session.new(seed_value,"empty",0)
	var enemy = s.spawn_enemy(kind,s.sim.actor.position+Vector2(200,0))
	return [s,enemy]

func _freeze(s, enemy) -> void:
	enemy.target.status.apply("frozen",s.sim.clock.tick,s.sim.settings["statuses"]["frozen"])

## Casts Force at `enemy` (already Frozen) and steps until it was hit or 90 ticks pass.
func _force_hit(s, enemy) -> void:
	s.sim.loadout.allow_edit = true
	s.sim.equip(0,_shot("essence.force"))
	s.sim.loadout.slots[0]["cooldown"] = 0
	s.sim.mana = 120.0
	var before: int = enemy.target.hit_count
	s.sim.try_cast(0,s.sim.actor.position,(enemy.target.position-s.sim.actor.position).normalized())
	for i in 90:
		s.step()
		if enemy.target.hit_count > before:
			break

func _stuns(enemy) -> Array:
	return enemy.transitions.filter(func(x): return x["to"] == "stunned")

# b) Force on Frozen shatters: big hit + stun; per-target stun immunity.
func test_ad_257_b_shatter_stun_and_immunity(t) -> void:
	_current = "test_ad_257_b_shatter_stun_and_immunity"
	var combos := _combos()
	for key in ["shatter.stun_ticks","shatter.stun_immunity_ticks","shatter.bonus_damage_scale"]:
		if not _need(t,combos,key):
			return
	var stun_ticks := int(_val(combos,"shatter.stun_ticks"))
	var immunity := int(_val(combos,"shatter.stun_immunity_ticks"))
	t.equal(stun_ticks,60,"test_ad_257_b_shatter_stun_and_immunity: shatter stun is 60 ticks (1.0 s)")
	t.equal(immunity,360,"test_ad_257_b_shatter_stun_and_immunity: stun immunity is 360 ticks (6 s)")
	var pair = _frozen_enemy_session(257002)
	var s = pair[0]
	var enemy = pair[1]
	var other = s.spawn_enemy("bone_thrall",s.sim.actor.position+Vector2(200,120))
	t.check(enemy != null and other != null,"test_ad_257_b_shatter_stun_and_immunity: enemies spawned")
	if enemy == null or other == null:
		return
	_freeze(s,enemy)
	var hp0: float = enemy.target.health.current if "current" in enemy.target.health else 0.0
	_force_hit(s,enemy)
	t.check(not enemy.target.status.has("frozen",s.sim.clock.tick),"test_ad_257_b_shatter_stun_and_immunity: shatter removes Frozen")
	var stuns := _stuns(enemy)
	t.equal(stuns.size(),1,"test_ad_257_b_shatter_stun_and_immunity: shatter stuns the frozen enemy once")
	if stuns.is_empty():
		return
	var landed: int = stuns[0]["tick"]
	t.equal(enemy.stun_until,landed+stun_ticks-1,"test_ad_257_b_shatter_stun_and_immunity: stun lasts combos.shatter.stun_ticks")
	var plain = Session.new(257002,"empty",0)
	var dummy = plain.spawn_enemy("bone_thrall",plain.sim.actor.position+Vector2(200,0))
	_force_hit(plain,dummy)
	var big: float = enemy.target.total_received
	t.check(big >= dummy.target.total_received + dummy.target.total_received*float(_val(combos,"shatter.bonus_damage_scale")) - 0.01,
		"test_ad_257_b_shatter_stun_and_immunity: shatter hit >= plain force hit * (1 + bonus scale) (%.2f vs %.2f)" % [big,dummy.target.total_received])
	# Re-freeze and re-shatter inside the immunity window: damaged but not stunned again.
	for i in stun_ticks+10:
		s.step()
	var received: float = enemy.target.total_received
	_freeze(s,enemy)
	_force_hit(s,enemy)
	t.equal(_stuns(enemy).size(),1,"test_ad_257_b_shatter_stun_and_immunity: no second stun inside the immunity window")
	t.check(enemy.target.total_received > received,"test_ad_257_b_shatter_stun_and_immunity: the immune re-shatter still hits")
	# Immunity is per target: a second enemy still stuns.
	_freeze(s,other)
	_force_hit(s,other)
	t.equal(_stuns(other).size(),1,"test_ad_257_b_shatter_stun_and_immunity: a second enemy still stuns while the first is immune")
	# After the window the first enemy stuns again.
	while s.sim.clock.tick < landed+immunity+1:
		s.step()
	_freeze(s,enemy)
	_force_hit(s,enemy)
	t.equal(_stuns(enemy).size(),2,"test_ad_257_b_shatter_stun_and_immunity: stuns again after combos.shatter.stun_immunity_ticks")

# c) Fire on Frozen melts into Wet + burst; Cold on Wet freezes instantly.
func test_ad_257_c_melt_and_instant_freeze(t) -> void:
	_current = "test_ad_257_c_melt_and_instant_freeze"
	var combos := _combos()
	for key in ["melt.bonus_damage_scale","melt.apply","freeze.label"]:
		if not _need(t,combos,key):
			return
	t.check(float(_val(combos,"melt.bonus_damage_scale")) > 0.0,"test_ad_257_c_melt_and_instant_freeze: melt.bonus_damage_scale > 0")
	t.equal(_val(combos,"melt.apply"),"wet","test_ad_257_c_melt_and_instant_freeze: melt applies wet")
	var melt = _single_hit(257003,"frozen","essence.fire")
	var plain = _single_hit(257003,"","essence.fire")
	t.check(not melt[1].status.has("frozen",melt[0].clock.tick),"test_ad_257_c_melt_and_instant_freeze: fire removes Frozen")
	t.check(melt[1].status.has("wet",melt[0].clock.tick),"test_ad_257_c_melt_and_instant_freeze: fire on Frozen leaves the target Wet")
	t.check(melt[1].total_received > plain[1].total_received*(1.0+0.99*float(_val(combos,"melt.bonus_damage_scale"))),
		"test_ad_257_c_melt_and_instant_freeze: melt deals a bonus burst (%.2f vs %.2f)" % [melt[1].total_received,plain[1].total_received])
	var cold = _single_hit(257003,"wet","essence.cold")
	t.check(cold[1].status.has("frozen",cold[0].clock.tick) or cold[0].trace.filter_records(-1,"","reaction").any(func(e): return e["reason"] == "wet_cold_freeze"),
		"test_ad_257_c_melt_and_instant_freeze: cold on Wet freezes instantly")
	var rules: Array = cold[0].settings["reactions"].get("rules",[])
	var rule = rules.filter(func(x): return x.get("id") == "wet_cold_freeze")
	t.check(rule.size() == 1 and rule[0].has("bonus_damage_scale"),"test_ad_257_c_melt_and_instant_freeze: wet_cold_freeze scale comes from data")

## Damage dealt over WINDOW_TICKS to a pack of 4 stationary dummies by cycling `rotation` essences every CADENCE ticks.
func _pack_damage(seed_value: int, rotation: Array) -> float:
	var r = Runner.new(seed_value)
	var pack: Array = []
	for i in 4:
		pack.append(r.add_target(r.actor.position + Vector2(300,(i-1.5)*40.0),Vector2.ZERO,100000.0))
	for i in rotation.size():
		r.equip(i,_shot(rotation[i]))
	var cast := 0
	for i in WINDOW_TICKS:
		if i % CADENCE == 0:
			var slot: int = cast % rotation.size()
			if r.try_cast(slot,r.actor.position,Vector2.RIGHT)["accepted"]:
				cast += 1
		r.step()
	var total := 0.0
	for p in pack:
		total += p.total_received
	return total

# d) Balance bar: best 2-skill combo rotation >= min_ratio x best single-skill spam, on every seed.
func test_ad_257_d_combo_dps_bar(t) -> void:
	_current = "test_ad_257_d_combo_dps_bar"
	var combos := _combos()
	if not _need(t,combos,"balance.min_ratio"):
		return
	var min_ratio := float(_val(combos,"balance.min_ratio"))
	t.equal(min_ratio,1.6,"test_ad_257_d_combo_dps_bar: balance.min_ratio is 1.6")
	var seconds := float(WINDOW_TICKS)/60.0
	for seed_value in SEEDS:
		var best_single := 0.0
		for e in ["essence.lightning","essence.cold","essence.fire","essence.water","essence.force"]:
			best_single = maxf(best_single,_pack_damage(seed_value,[e])/seconds)
		var best_combo := 0.0
		for rot in [["essence.water","essence.lightning"],["essence.water","essence.cold","essence.force"]]:
			best_combo = maxf(best_combo,_pack_damage(seed_value,rot)/seconds)
		print("AD-257 seed %d single %.2f combo %.2f" % [seed_value,best_single,best_combo])
		t.check(best_single > 0.0,"test_ad_257_d_combo_dps_bar: seed %d spamming deals damage" % seed_value)
		t.check(best_combo > best_single,"test_ad_257_d_combo_dps_bar: seed %d combo beats spam" % seed_value)
		t.check(best_combo >= min_ratio*best_single,"test_ad_257_d_combo_dps_bar: seed %d combo DPS >= %.1fx spam (%.2f vs %.2f)" % [seed_value,min_ratio,best_combo,best_single])

# e) Named popup + hit stop per combo; popups expire.
func test_ad_257_e_popup_and_hit_stop(t) -> void:
	_current = "test_ad_257_e_popup_and_hit_stop"
	var combos := _combos()
	if not _need(t,combos,"popup_ticks"):
		return
	var cases := [["conduct","wet","essence.lightning"],["shatter","frozen","essence.force"],
		["melt","frozen","essence.fire"],["freeze","wet","essence.cold"]]
	for c in cases:
		var id: String = c[0]
		if not _need(t,combos,id+".label") or not _need(t,combos,id+".hit_stop_ms"):
			continue
		var ms := int(_val(combos,id+".hit_stop_ms"))
		var label := str(_val(combos,id+".label"))
		t.check(ms >= 50 and ms <= 100,"test_ad_257_e_popup_and_hit_stop: %s hit stop %d ms within 50..100" % [id,ms])
		t.check(label != "" and label.ends_with("!"),"test_ad_257_e_popup_and_hit_stop: %s label '%s' non-empty and ends with '!'" % [id,label])
		var hit = _single_hit(257001,c[1],c[2])
		var r = hit[0]
		var popups: Array = r.get("combo_popups") if r.get("combo_popups") != null else []
		var mine: Array = popups.filter(func(p): return p["id"] == id)
		t.check(mine.size() >= 1,"test_ad_257_e_popup_and_hit_stop: %s emits a combo popup" % id)
		if mine.size() >= 1:
			t.equal(mine[0]["label"],label,"test_ad_257_e_popup_and_hit_stop: %s popup label from data" % id)
		t.equal(r.get("hit_stop_ms"),ms,"test_ad_257_e_popup_and_hit_stop: %s sets sim.hit_stop_ms" % id)
		# Popups expire after popup_ticks.
		var fresh = _single_hit(257001,c[1],c[2])
		for i in int(_val(combos,"popup_ticks"))+5:
			fresh[0].step()
		t.check((fresh[0].get("combo_popups") if fresh[0].get("combo_popups") != null else []).is_empty(),"test_ad_257_e_popup_and_hit_stop: %s popup expires after popup_ticks" % id)
