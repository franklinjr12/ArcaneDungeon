extends RefCounted
## AD-131: Cold/Force essences and data-driven state-rule reactions (keyed on target states + hit channel).
const Runner = preload("res://magic/runtime/spell_runner.gd")
const Target = preload("res://combat/magic_target.gd")
const Resolver = preload("res://combat/interaction_resolver.gd")
const Store = preload("res://combat/target_store.gd")

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
