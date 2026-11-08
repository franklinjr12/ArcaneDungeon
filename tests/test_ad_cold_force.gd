extends RefCounted
## AD-131: Cold/Force essences and data-driven state-rule reactions (keyed on target states + hit channel).
const Runner = preload("res://magic/runtime/spell_runner.gd")
const Target = preload("res://combat/magic_target.gd")
const Resolver = preload("res://combat/interaction_resolver.gd")
const Store = preload("res://combat/target_store.gd")
const Session = preload("res://combat/combat_session.gd")
const Golden = preload("res://tests/ad_cold_force_golden_generator.gd")

func _payload(essence: String, damage: float = 10.0) -> Dictionary:
	return {"team":1,"cast_id":3,"root_cast_id":3,"formula_id":"test","essence_id":essence,"damage":damage,"caster_id":1}

func _ids(outcome: Dictionary) -> Array:
	return outcome["reactions"].map(func(r): return r["id"])

func run(t) -> void:
	var settings: Dictionary = Runner.new(131).settings
	var res = Resolver.new(settings)
	var store = Store.new()
	var enemy = Target.new(10,2,Vector2(300,300),500)
	store.add(enemy)
	# Chill threshold: 2 hits keep Chilled, the 3rd freezes.
	var out: Dictionary = res.resolve(_payload("essence.cold"),enemy,store,0)
	t.check(out["accepted"] and out["reactions"].is_empty(),"AD-131 first cold hit: no reaction")
	res.resolve(_payload("essence.cold"),enemy,store,1)
	t.equal(enemy.status.stacks("chilled",1),2,"AD-131 two cold hits stack Chilled to 2")
	t.check(not enemy.status.has("frozen",1),"AD-131 two cold hits do not freeze")
	out = res.resolve(_payload("essence.cold"),enemy,store,2)
	t.check(enemy.status.has("frozen",2) and not enemy.status.has("chilled"),"AD-131 3 Chilled stacks = Frozen, Chilled removed")
	t.equal(_ids(out),["chill_freeze"],"AD-131 chill_freeze reaction recorded")
	t.equal(enemy.status.stacks("missing",2),0,"AD-131 stacks() is 0 for missing state")
	t.equal(enemy.status.stacks("frozen",2+int(settings["statuses"]["frozen"]["duration_ticks"])),0,"AD-131 stacks() is 0 once expired")
	# Frozen + Force = Shatter.
	out = res.resolve(_payload("essence.force",10.0),enemy,store,3)
	t.equal(_ids(out),["frozen_force_shatter"],"AD-131 Frozen + Force shatters")
	t.check(out["reactions"][0]["bonus_damage"] > 0.0,"AD-131 shatter deals bonus damage")
	t.check(not enemy.status.has("frozen",3) and enemy.status.has("brittle",3),"AD-131 shatter removes Frozen, applies Brittle")
	t.check(out.has("knockback"),"AD-131 shatter hit still carries knockback")
	# Brittle multiplies the next hit.
	var plain = Target.new(11,2,Vector2(900,900),500)
	var base: float = res.resolve(_payload("essence.neutral",20.0),plain,store,4)["damage"]
	var brit: float = res.resolve(_payload("essence.neutral",20.0),enemy,store,4)["damage"]
	t.check(absf(brit - base*float(settings["statuses"]["brittle"]["damage_taken_mult"])) < 0.001,"AD-131 Brittle multiplies incoming damage")
	# Wet + Cold = instant Frozen.
	var wet_t = Target.new(12,2,Vector2(300,600),500)
	store.add(wet_t)
	res.resolve(_payload("essence.water"),wet_t,store,10)
	out = res.resolve(_payload("essence.cold"),wet_t,store,11)
	t.check(wet_t.status.has("frozen",11) and not wet_t.status.has("wet") and not wet_t.status.has("chilled"),"AD-131 Wet + Cold = Frozen immediately")
	t.equal(_ids(out),["wet_cold_freeze"],"AD-131 wet_cold_freeze reaction recorded")
	# Fire thaws Chilled/Frozen into Steam; blinds nearby enemies only.
	for state in ["chilled","frozen"]:
		var s2 = Store.new()
		var core = Target.new(20,2,Vector2(500,300),500)
		var near = Target.new(21,2,Vector2(560,300),500)
		var far = Target.new(22,2,Vector2(500,700),500)
		var friend = Target.new(23,1,Vector2(520,300),500)
		for n in [core,near,far,friend]:
			s2.add(n)
		core.status.apply(state,0,settings["statuses"][state])
		out = res.resolve(_payload("essence.fire"),core,s2,5)
		t.equal(_ids(out),["fire_thaw_steam"],"AD-131 Fire on %s thaws into Steam" % state)
		t.check(not core.status.has("chilled") and not core.status.has("frozen"),"AD-131 %s removed by Fire" % state)
		t.check(not core.status.has("burning"),"AD-131 thawing Fire does not apply Burning (%s)" % state)
		t.check(core.status.has("blinded",5) and near.status.has("blinded",5),"AD-131 Steam blinds target and in-radius enemy (%s)" % state)
		t.check(not far.status.has("blinded") and not friend.status.has("blinded"),"AD-131 Steam skips out-of-radius enemy and attacker team (%s)" % state)
		t.equal(out["reactions"][0]["affected_ids"],[20,21],"AD-131 Steam affected ids sorted (%s)" % state)
	# Knockback is data, boss-immune.
	var plain2 = Target.new(30,2,Vector2(100,100),500)
	out = res.resolve(_payload("essence.force"),plain2,store,6)
	t.equal(float(out["knockback"]["force"]),float(settings["channels"]["essence.force"]["knockback_force"]),"AD-131 Force reports knockback")
	t.check(out["reactions"].is_empty(),"AD-131 Force on a clean target: no reaction")
	var boss = Target.new(31,2,Vector2(150,100),500)
	boss.tags = ["boss"]
	out = res.resolve(_payload("essence.force"),boss,store,6)
	t.check(not out.has("knockback"),"AD-131 boss ignores knockback")
	# Unrelated hits.
	var clean = Target.new(32,2,Vector2(200,100),500)
	out = res.resolve(_payload("essence.fire"),clean,store,7)
	t.check(out["reactions"] is Array and out["reactions"].is_empty() and clean.status.has("burning"),"AD-131 Fire on a clean target: Burning, no reactions")
	# Wet + Lightning arc unchanged.
	var a = Target.new(40,2,Vector2(100,400),500)
	var b = Target.new(41,2,Vector2(160,400),500)
	for n in [a,b]:
		store.add(n)
		n.status.apply("wet",8,settings["statuses"]["wet"])
	out = res.resolve(_payload("essence.lightning"),a,store,9)
	t.equal(int(out["reaction"]["target_id"]),41,"AD-131 Wet lightning arc output unchanged")
	t.check(out["reactions"].is_empty(),"AD-131 arc hit adds no new reactions")
	_sim_tests(t)
	_enemy_tests(t)
	_golden_tests(t)

func _shot(essence: String) -> Dictionary:
	return {"schema_version":1,"formula_id":"test."+essence,"display_name":essence,
		"root":{"essence_id":essence,"manifestation_id":"form.projectile","modifier_ids":[],"params":{}}}

## Casts `essences` in order (one shot each, spaced out) at a dummy 300px to the right of the actor.
func _fire_sequence(seed_value: int, essences: Array, tags: Array = []):
	var r = Runner.new(seed_value)
	var dummy = r.add_target(Vector2(440,340),Vector2.ZERO,5000.0)
	if not tags.is_empty():
		dummy.tags = tags
	for essence in essences:
		r.equip(0,_shot(str(essence)))
		r.try_cast(0,r.actor.position,Vector2.RIGHT)
		for i in 60:
			r.step()
			r.mana = 120.0
			r.loadout.cooldown_tick()
	return [r,dummy]

func _sim_tests(t) -> void:
	# Force pushes along the aim direction, impulse decays to zero.
	var r = Runner.new(131)
	var dummy = r.add_target(Vector2(440,340),Vector2.ZERO,5000.0)
	var start_x: float = dummy.position.x
	r.equip(0,_shot("essence.force"))
	t.check(r.try_cast(0,r.actor.position,Vector2.RIGHT)["accepted"],"AD-131 force shot casts")
	var saw_impulse := false
	for i in 120:
		r.step()
		if not dummy.impulse.is_zero_approx():
			saw_impulse = true
	t.check(saw_impulse,"AD-131 force hit sets an impulse")
	t.check(dummy.position.x > start_x + 20.0 and absf(dummy.position.y-340.0) < 0.5,"AD-131 force pushes along aim direction")
	t.check(dummy.impulse.is_zero_approx(),"AD-131 impulse decays to zero")
	var settled: Vector2 = dummy.position
	for i in 10:
		r.step()
	t.equal(dummy.position,settled,"AD-131 target at rest after knockback")
	# Bosses are knockback-immune.
	var pair: Array = _fire_sequence(131,["essence.force"],["boss"])
	t.equal(pair[1].position,Vector2(440,340),"AD-131 boss tag is not pushed")
	# Knockback never leaves bounds.
	var edge = Runner.new(131)
	var near_edge = edge.add_target(Vector2(edge.bounds.end.x-30.0,340),Vector2.ZERO,5000.0)
	edge.equip(0,_shot("essence.force"))
	edge.actor.position = Vector2(near_edge.position.x-200.0,340)
	edge.try_cast(0,edge.actor.position,Vector2.RIGHT)
	for i in 120:
		edge.step()
		t.check(edge.bounds.grow(-near_edge.radius+0.01).has_point(near_edge.position),"AD-131 knockback stays inside bounds")
	# Walls stop knockback.
	var wall_r = Runner.new(131)
	var wall_t = wall_r.add_target(Vector2(440,340),Vector2.ZERO,5000.0)
	wall_r.collision_walls = [Rect2(Vector2(480,300),Vector2(40,80))]
	wall_t.impulse = Vector2(420,0)
	for i in 60:
		wall_r.step()
	t.check(wall_t.position.x + wall_t.radius <= 480.0 and wall_t.position.x > 440.0,"AD-131 knockback stops at walls")
	# Water then Cold shots record the shared-rule reaction trace.
	var wc: Array = _fire_sequence(131,["essence.water","essence.cold"])
	var trace_text: String = wc[0].trace_json()
	t.check(trace_text.contains("wet_cold_freeze"),"AD-131 trace records reaction wet_cold_freeze")
	t.check(wc[1].status.has("frozen",wc[0].clock.tick-60) or wc[1].status.snapshot().has("frozen") or trace_text.contains("frozen:applied"),"AD-131 wet+cold freezes target")
	# Frozen + Force shatter reaction carries bonus damage.
	var sh: Array = _fire_sequence(131,["essence.water","essence.cold","essence.force"])
	t.check(sh[0].trace_json().contains("frozen_force_shatter"),"AD-131 trace records frozen_force_shatter")
	# Determinism.
	var seq := ["essence.water","essence.cold","essence.force","essence.fire"]
	t.equal(_fire_sequence(77,seq)[0].trace_json(),_fire_sequence(77,seq)[0].trace_json(),"AD-131 same seed and casts yield identical trace")

func tuning_telegraph(enemy) -> int:
	return int(enemy.tuning["telegraph_ticks"])

func _enemy_tests(t) -> void:
	# Frozen enemy: brain suspended.
	var s = Session.new(131,"empty",0)
	var adept = s.spawn_enemy("fallen_adept",s.sim.actor.position+Vector2(380,0))
	t.check(adept != null,"AD-131 test enemy spawned")
	if adept == null:
		return
	for i in 4:
		s.step()
	t.equal(adept.state,"windup","AD-131 in-range adept enters windup")
	var frozen_state_tick: int = adept.state_tick
	adept.target.status.apply("frozen",s.sim.clock.tick,s.sim.settings["statuses"]["frozen"])
	for i in int(tuning_telegraph(adept))+5:
		s.step()
	t.equal(adept.state,"windup","AD-131 frozen windup does not complete")
	t.equal(adept.state_tick,frozen_state_tick,"AD-131 frozen enemy does not progress state")
	t.equal(s.enemy_shots.size(),0,"AD-131 frozen windup does not fire")
	var walker = Session.new(131,"empty",0)
	var thrall = walker.spawn_enemy("bone_thrall",walker.sim.actor.position+Vector2(600,0))
	for i in 3:
		walker.step()
	thrall.target.status.apply("frozen",walker.sim.clock.tick,walker.sim.settings["statuses"]["frozen"])
	var rest: Vector2 = thrall.target.position
	for i in 20:
		walker.step()
	t.equal(thrall.target.position,rest,"AD-131 frozen enemy does not move")
	# Chilled slows movement.
	var base = Session.new(131,"empty",0)
	var slow = Session.new(131,"empty",0)
	var a = base.spawn_enemy("bone_thrall",base.sim.actor.position+Vector2(600,0))
	var b = slow.spawn_enemy("bone_thrall",slow.sim.actor.position+Vector2(600,0))
	for i in 3:
		base.step()
		slow.step()
	b.target.status.apply("chilled",slow.sim.clock.tick,slow.sim.settings["statuses"]["chilled"])
	var a0: Vector2 = a.target.position
	var b0: Vector2 = b.target.position
	for i in 10:
		base.step()
		slow.step()
	var scale: float = float(slow.sim.settings["statuses"]["chilled"]["move_scale"])
	var moved_a: float = a.target.position.distance_to(a0)
	var moved_b: float = b.target.position.distance_to(b0)
	t.check(moved_a > 0.0 and absf(moved_b/moved_a-scale) < 0.05,"AD-131 chilled enemy moves at move_scale speed")
	# Blinded ranged enemy never enters windup.
	var blind = Session.new(131,"empty",0)
	var caster = blind.spawn_enemy("fallen_adept",blind.sim.actor.position+Vector2(380,0))
	blind.step()
	caster.target.status.apply("blinded",blind.sim.clock.tick,blind.sim.settings["statuses"]["blinded"])
	var blinded_ticks := int(blind.sim.settings["statuses"]["blinded"]["duration_ticks"])-2
	var windup := false
	for i in blinded_ticks:
		blind.step()
		if caster.state == "windup":
			windup = true
	t.check(not windup,"AD-131 blinded ranged enemy does not start an attack")
	for i in 20:
		blind.step()
		if caster.state == "windup":
			windup = true
	t.check(windup,"AD-131 ranged enemy attacks again after blind expires")

func _reason_count(run, reason: String) -> int:
	var count := 0
	for entry in run.trace.snapshot():
		if entry["type"] == "reaction" and str(entry.get("reason","")) == reason:
			count += 1
	return count

func _golden_tests(t) -> void:
	t.with_frozen_balance(func(): _golden_body(t))

func _golden_body(t) -> void:
	var expected: Dictionary = t.fixture("ad_cold_force_traces_v1.json")
	for scenario in Golden.SCENARIOS:
		var played: Dictionary = Golden.play(scenario)
		t.check(not played["accepted"].has(false),"AD-131 "+scenario+" every scripted cast accepted")
		t.equal(Golden.normalize(played["run"].trace.snapshot()),expected[scenario],"AD-131 "+scenario+" golden trace")
	var chill: Dictionary = Golden.play("chill_to_frozen")
	t.equal(_reason_count(chill["run"],"chill_freeze"),1,"AD-131 chill_to_frozen records chill_freeze once")
	t.check(chill["targets"][0].status.has("frozen",chill["run"].clock.tick) or chill["targets"][0].status.has("frozen"),"AD-131 chill_to_frozen ends Frozen")
	var shatter: Dictionary = Golden.play("wet_cold_force_shatter")
	t.equal(_reason_count(shatter["run"],"wet_cold_freeze"),1,"AD-131 wet_cold_force_shatter freezes Wet target")
	t.equal(_reason_count(shatter["run"],"frozen_force_shatter"),1,"AD-131 wet_cold_force_shatter shatters")
	var victim = shatter["targets"][0]
	t.check(victim.status.has("brittle") and not victim.status.has("frozen"),"AD-131 wet_cold_force_shatter ends Brittle, not Frozen")
	var steam: Dictionary = Golden.play("cold_fire_steam")
	t.equal(_reason_count(steam["run"],"fire_thaw_steam"),1,"AD-131 cold_fire_steam thaws once")
	for target in steam["targets"]:
		t.check(target.status.has("blinded"),"AD-131 cold_fire_steam blinds target %d" % target.id)
	t.check(not steam["targets"][0].status.has("chilled"),"AD-131 cold_fire_steam removes Chilled")
