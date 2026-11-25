extends RefCounted
## AD-240: 12 new artifacts with combo tags. Step 1: data, tags, tag-biased rewards, card tag, meta unlocks.
const Artifacts = preload("res://world/artifacts.gd")
const Reward = preload("res://world/reward_generator.gd")
const Flow = preload("res://world/run_flow.gd")
const Meta = preload("res://world/meta_progress.gd")
const Runner = preload("res://magic/runtime/spell_runner.gd")
const Session = preload("res://combat/combat_session.gd")
const IDS := ["thunderhead","frostbrand","kindling","undertow","overcharge","shard_mail",
	"quicksilver_ink","conduit_coil","tidecaller_shell","mirror_glyph","grave_salt","fracture_lens"]
const TAGS := ["reaction","form","trigger","defence"]
const META_LOCKED := ["grave_salt","mirror_glyph","conduit_coil","thunderhead"]

func run(t) -> void:
	_data(t)
	_tag_bias(t)
	_card_tag(t)
	_meta_unlocks(t)
	test_thunderhead(t)
	test_frostbrand(t)
	test_kindling(t)
	test_conduit_coil(t)
	test_undertow(t)
	test_overcharge(t)
	test_quicksilver_ink(t)
	test_mirror_glyph(t)
	test_fracture_lens(t)
	test_shard_mail(t)
	test_tidecaller_shell(t)
	test_grave_salt(t)

func _csv_keys() -> Dictionary:
	var keys := {}
	var csv := FileAccess.open("res://i18n/strings_en.csv", FileAccess.READ)
	csv.get_csv_line()
	while not csv.eof_reached():
		var row := csv.get_csv_line()
		if row.size() >= 2:
			keys[row[0]] = true
	return keys

func _tuning() -> Dictionary:
	return JSON.parse_string(FileAccess.get_file_as_string(Flow.CONFIG_V2))

func _run(seed_value: int, held: Array):
	var State = load("res://world/run_state.gd")
	var cfg: Dictionary = _tuning()
	var state = State.new()
	var formulas := {}
	for id in cfg["initial_formulas"]:
		formulas[id] = {"id":id}
	state.initialize(seed_value,cfg,formulas)
	state.artifacts = held.duplicate()
	return state

func _data(t) -> void:
	var defs: Dictionary = Artifacts.definitions()
	var keys := _csv_keys()
	t.equal(defs.size(),24,"AD-240 config has 24 artifacts")
	for id in defs:
		var def: Dictionary = defs[id]
		t.check(str(def.get("tag","")) in TAGS,"AD-240 %s has a valid tag" % id)
		t.equal(Artifacts.tag_of(id),str(def.get("tag","")),"AD-240 tag_of reads data for "+id)
		t.check(keys.has(str(def.get("name_key",""))) and keys.has(str(def.get("desc_key",""))),"AD-240 %s name/desc keys exist" % id)
		t.check(not def.get("params",{}).is_empty(),"AD-240 %s tunables live in params" % id)
	for id in IDS:
		t.check(defs.has(id),"AD-240 new artifact present: "+id)
	t.equal(Artifacts.tag_of("nope"),"","AD-240 tag_of unknown is empty")
	for tag in TAGS:
		t.check(keys.has("run.reward.artifact_tag_"+tag),"AD-240 tag label key exists: "+tag)
	t.equal(float(Artifacts.config().get("tag_bias",0.0)),0.4,"AD-240 tag_bias comes from data")

func _offered(seed_value: int, held: Array) -> String:
	var run_state = _run(seed_value,held)
	var card: Dictionary = Reward.artifact_choice(run_state,seed_value * 7919 + 13,true)
	return str(card.get("id",""))

func _tag_bias(t) -> void:
	var held := ["shatterheart"]
	var tag := Artifacts.tag_of("shatterheart")
	var n := 600
	var biased := 0
	var baseline := 0
	var pool_share := 0.0
	var candidates: Array = Artifacts.definitions().keys().filter(func(id): return id not in held)
	pool_share = float(candidates.filter(func(id): return Artifacts.tag_of(id) == tag).size())/float(candidates.size())
	for i in n:
		if Artifacts.tag_of(_offered(i,held)) == tag:
			biased += 1
		if Artifacts.tag_of(_offered(i,[])) == tag:
			baseline += 1
	var bias := float(Artifacts.config()["tag_bias"])
	var expected := bias+(1.0-bias)*pool_share
	var share := float(biased)/float(n)
	t.check(share > pool_share+0.15,"AD-240 held tag share %.2f clearly above pool share %.2f" % [share,pool_share])
	t.check(absf(share-expected) < 0.07,"AD-240 held tag share %.2f near expected %.2f" % [share,expected])
	t.check(baseline < biased,"AD-240 no-held baseline share is lower than biased")
	# No held artifacts: identical draws to the unbiased path (single randi after the roll).
	var run_state = _run(5,[])
	var settings: Dictionary = Artifacts.config()
	var hash_value := 5 * 7919 + 13
	var random := RandomNumberGenerator.new()
	random.seed = (hash_value ^ int(settings["seed_salt"])) & 0x7fffffff
	random.randf()
	var cands: Array = Artifacts.definitions().keys()
	cands.sort()
	var expect_id: String = cands[random.randi() % cands.size()]
	t.equal(str(Reward.artifact_choice(run_state,hash_value,true).get("id","")),expect_id,"AD-240 no-held draw sequence unchanged")

func _card_tag(t) -> void:
	var keys := _csv_keys()
	for i in 20:
		var card: Dictionary = Reward.artifact_choice(_run(i,[]),i+100,true)
		t.check(card.has("tag") and card["tag"] in TAGS,"AD-240 artifact card %d carries a tag" % i)
		t.equal(card["tag"],Artifacts.tag_of(str(card["id"])),"AD-240 card tag matches data %d" % i)
		t.check(keys.has("run.reward.artifact_tag_"+str(card["tag"])),"AD-240 card tag has a UI string %d" % i)

func _meta_unlocks(t) -> void:
	var locked: Array = Meta.locked_artifacts(Meta.empty_meta())
	for id in META_LOCKED:
		t.check(id in locked,"AD-240 %s locked by default" % id)
	var tuning: Dictionary = _tuning()
	for i in 80:
		var card: Dictionary = Reward.artifact_choice(_run(i,[]),i+500,true,locked)
		t.check(card.is_empty() or card["id"] not in locked,"AD-240 locked artifacts excluded from rewards %d" % i)
	var seen := {}
	for i in 400:
		var card: Dictionary = Reward.artifact_choice(_run(i,[]),i+900,true,[])
		seen[card["id"]] = true
	for id in META_LOCKED:
		t.check(seen.has(id),"AD-240 %s offered once unlocked" % id)
	t.check(not tuning.is_empty(),"AD-240 run tuning loads")


## --- Step 2: reaction artifacts (thunderhead, frostbrand, kindling, conduit_coil) ---------------------

## Sim with no mana regen; `ids` null means no holder at all.
func _sim(essence: String, ids, form: String = "form.projectile"):
	var r = Runner.new(143)
	r.settings["combat"]["regen_mana_per_tick"] = 0.0
	r.mana = float(r.settings["combat"]["player_max_mana"])
	var formula := {"schema_version":2,"formula_id":"test.ad240","display_name":"t",
		"root":{"essence_id":essence,"manifestation_id":form,"modifier_ids":[],"params":{}}}
	var equipped: Dictionary = r.equip(0,formula)
	if not equipped["ok"]:
		printerr("equip failed: ",equipped)
	if ids != null:
		r.artifacts = Artifacts.new(ids)
	return r

func _fire(r, ticks: int = 40) -> void:
	r.mana = float(r.settings["combat"]["player_max_mana"])
	r.try_cast(0,r.actor.position,Vector2.RIGHT)
	for i in ticks:
		r.step()

func _status(r, target, id: String) -> void:
	target.status.apply(id,r.clock.tick,r.settings["statuses"][id],{})

func _arcs(r) -> Array:
	return r.trace.filter_records(-1,"","reaction").filter(func(e): return e["reason"] == "wet_lightning_arc")

func _arc_scene(ids, wet_third: bool = false) -> Array:
	var r = _sim("essence.lightning",ids)
	var a = r.add_target(Vector2(300,340),Vector2.ZERO,100000.0)
	var b = r.add_target(Vector2(380,340),Vector2.ZERO,100000.0)
	var c = r.add_target(Vector2(460,340),Vector2.ZERO,100000.0)
	r.add_target(Vector2(540,340),Vector2.ZERO,100000.0)
	_status(r,a,"wet")
	_status(r,b,"wet")
	if wet_third:
		_status(r,c,"wet")
	_fire(r)
	return [r,a,b,c]

func test_thunderhead(t) -> void:
	var plain: Array = _arc_scene(null)
	var held: Array = _arc_scene(["thunderhead"])
	var extra := int(held[0].artifacts.param("thunderhead","extra_jumps"))
	t.equal(_arcs(plain[0]).size(),1,"AD-240 thunderhead: without it a wet hit arcs once")
	t.equal(_arcs(held[0]).size(),1+extra,"AD-240 thunderhead: wet arc gains extra_jumps")
	t.check(held[3].health.current < held[3].health.maximum and plain[3].health.current == plain[3].health.maximum,"AD-240 thunderhead: the extra jump reaches the third enemy only with it")
	var both: Array = _arc_scene(["stormglass","thunderhead"])
	var storm: Array = _arc_scene(["stormglass"])
	var storm_jumps := int(storm[0].artifacts.param("stormglass","extra_jumps"))
	t.equal(_arcs(storm[0]).size(),1+storm_jumps,"AD-240 thunderhead: stormglass baseline jumps")
	t.equal(_arcs(both[0]).size(),1+storm_jumps+extra,"AD-240 thunderhead: stacks additively with stormglass")
	var dry = _sim("essence.lightning",["thunderhead"])
	dry.add_target(Vector2(300,340),Vector2.ZERO,100000.0)
	dry.add_target(Vector2(380,340),Vector2.ZERO,100000.0)
	_fire(dry)
	t.equal(_arcs(dry).size(),0,"AD-240 thunderhead: dry targets still do not arc")
	t.equal(int(held[0].trace.filter_records(-1,"","hit")[0]["amount"]),int(plain[0].trace.filter_records(-1,"","hit")[0]["amount"]),"AD-240 thunderhead: direct damage unchanged")
	t.equal(int(_arcs(held[0])[0]["amount"]),int(_arcs(plain[0])[0]["amount"]),"AD-240 thunderhead: first arc damage unchanged")

func _frozen_force(ids, freeze: bool) -> float:
	var r = _sim("essence.force",ids)
	var target = r.add_target(Vector2(300,340),Vector2.ZERO,100000.0)
	if freeze:
		_status(r,target,"frozen")
	_fire(r)
	return target.health.maximum-target.health.current

func test_frostbrand(t) -> void:
	var plain := _frozen_force(null,true)
	var held := _frozen_force(["frostbrand"],true)
	var scale := float(Artifacts.new(["frostbrand"]).param("frostbrand","force_scale"))
	t.check(plain > 0.0 and held > plain,"AD-240 frostbrand: a frozen target takes more force damage")
	var rule: Dictionary = {}
	var cfg: Dictionary = Runner.new(143).settings
	for entry in cfg["reactions"]["rules"]:
		if entry["id"] == "frozen_force_shatter":
			rule = entry
	var direct := _frozen_force(null,false)
	var expected := (float(rule["bonus_damage_scale"])+scale)/float(rule["bonus_damage_scale"])
	t.check(absf((held-direct)/maxf(0.001,(plain-direct))-expected) < 0.05,"AD-240 frostbrand: bonus is the shatter scale plus force_scale from data")
	t.equal(_frozen_force(["frostbrand"],false),direct,"AD-240 frostbrand: unfrozen targets take unchanged damage")

func _kindle_scene(ids, burning: bool, far_gap: float = 0.0) -> Array:
	var r = _sim("essence.lightning",ids)
	var first = r.add_target(Vector2(300,340),Vector2.ZERO,1.0)
	var near = r.add_target(Vector2(300,390),Vector2.ZERO,100000.0)
	var out = r.add_target(Vector2(300,340+far_gap),Vector2.ZERO,100000.0)
	if burning:
		_status(r,first,"burning")
	_fire(r)
	return [r,first,near,out]

func test_kindling(t) -> void:
	var held: Array = _kindle_scene(["kindling"],true)
	var plain: Array = _kindle_scene(null,true)
	t.check(not held[1].alive() and not plain[1].alive(),"AD-240 kindling: the burning enemy dies in both scenes")
	t.check(held[2].status.has("burning"),"AD-240 kindling: a nearby enemy catches fire")
	t.check(not plain[2].status.has("burning"),"AD-240 kindling: no artifact, no spread")
	t.check(held[0].trace.filter_records(-1,"","status").any(func(e): return e["reason"] == "burning:applied" and int(e["target_id"]) == held[2].id),"AD-240 kindling: the spread is traced")
	var radius := float(held[0].artifacts.param("kindling","radius"))
	var far: Array = _kindle_scene(["kindling"],true,radius+60.0)
	t.check(not far[1].alive() and far[2].status.has("burning"),"AD-240 kindling: far scene still spreads inside the radius")
	t.check(not far[3].status.has("burning"),"AD-240 kindling: nothing outside the radius ignites")
	var cold: Array = _kindle_scene(["kindling"],false)
	t.check(not cold[1].alive() and not cold[2].status.has("burning"),"AD-240 kindling: a non-burning kill spreads nothing")
	var ticks := int(held[0].artifacts.param("kindling","duration_ticks"))
	for i in ticks+10:
		held[0].step()
	t.check(not held[2].status.has("burning"),"AD-240 kindling: the spread burn ends after duration_ticks")

func _conduit_scene(ids, burning: bool) -> Array:
	var r = _sim("essence.lightning",ids)
	var hit = r.add_target(Vector2(300,340),Vector2.ZERO,100000.0)
	var near = r.add_target(Vector2(300,390),Vector2.ZERO,100000.0)
	if burning:
		_status(r,hit,"burning")
	_fire(r)
	return [r,hit,near]

func test_conduit_coil(t) -> void:
	var held: Array = _conduit_scene(["conduit_coil"],true)
	var plain: Array = _conduit_scene(null,true)
	var bursts: Array = held[0].trace.filter_records(-1,"","artifact").filter(func(e): return e["reason"] == "artifact.conduit_coil")
	t.equal(bursts.size(),1,"AD-240 conduit coil: a burning target hit by lightning overloads once")
	t.check(held[2].health.current < held[2].health.maximum,"AD-240 conduit coil: the overload hurts a neighbour")
	t.equal(plain[2].health.current,plain[2].health.maximum,"AD-240 conduit coil: no artifact, no overload")
	var dealt: float = held[2].health.maximum-held[2].health.current
	t.check(dealt <= float(held[0].artifacts.param("conduit_coil","damage")),"AD-240 conduit coil: overload damage is capped by data")
	var dry: Array = _conduit_scene(["conduit_coil"],false)
	t.equal(dry[0].trace.filter_records(-1,"","artifact").size(),0,"AD-240 conduit coil: a non-burning target does not overload")
	t.equal(dry[2].health.current,dry[2].health.maximum,"AD-240 conduit coil: nothing is damaged without a burning target")
	var fire = _sim("essence.fire",["conduit_coil"])
	var burning_target = fire.add_target(Vector2(300,340),Vector2.ZERO,100000.0)
	_status(fire,burning_target,"burning")
	_fire(fire)
	t.equal(fire.trace.filter_records(-1,"","artifact").size(),0,"AD-240 conduit coil: non-lightning damage does not overload")
	for step_more in 60:
		held[0].step()
	t.equal(held[0].trace.filter_records(-1,"","artifact").filter(func(e): return e["reason"] == "artifact.conduit_coil").size(),1,"AD-240 conduit coil: the overload never recurses")


## --- Step 3: trigger and form artifacts (undertow, overcharge, quicksilver_ink, mirror_glyph, fracture_lens) ---

func _pulled(ids, wet: bool) -> float:
	var r = _sim("essence.lightning",ids)
	var target = r.add_target(Vector2(300,340),Vector2.ZERO,100000.0)
	if wet:
		_status(r,target,"wet")
	var before: float = target.position.distance_to(r.actor.position)
	_fire(r,60)
	return before-target.position.distance_to(r.actor.position)

func test_undertow(t) -> void:
	var distance := float(Artifacts.new(["undertow"]).param("undertow","pull_distance"))
	var plain := _pulled(null,true)
	var held := _pulled(["undertow"],true)
	t.check(absf((held-plain)-distance) < 2.0,"AD-240 undertow: a wet enemy is pulled pull_distance (%.1f) toward the caster" % (held-plain))
	t.equal(_pulled(["undertow"],false),_pulled(null,false),"AD-240 undertow: dry enemies are not pulled")

func _spend(r) -> float:
	r.mana = float(r.settings["combat"]["player_max_mana"])
	var before: float = r.mana
	var result: Dictionary = r.try_cast(0,r.actor.position,Vector2.RIGHT)
	for i in 120:
		r.step()
	return before-r.mana if result["accepted"] else -1.0

func test_overcharge(t) -> void:
	var every := int(Artifacts.new(["overcharge"]).param("overcharge","every"))
	var plain = _sim("essence.fire",null)
	var held = _sim("essence.fire",["overcharge"])
	for i in every*2:
		var paid_plain := _spend(plain)
		var paid_held := _spend(held)
		var third := (i+1) % every == 0
		t.check(paid_plain > 0.0,"AD-240 overcharge: cast %d costs mana without it" % (i+1))
		t.check((paid_held == 0.0) == third and (third or paid_held == paid_plain),"AD-240 overcharge: cast %d is free only when every %dth" % [i+1,every])
	var both = _sim("essence.fire",["overcharge","momentum_rune"])
	for i in every-1:
		_spend(both)
	both.artifact_dash()
	t.equal(_spend(both),0.0,"AD-240 overcharge: due cast is free with momentum armed")
	t.check(_spend(both) == 0.0,"AD-240 overcharge: momentum free cast is kept for the next cast")
	t.check(_spend(both) > 0.0,"AD-240 overcharge: the cycle resumes afterwards")
	both.artifacts.state.clear()
	t.check(_spend(both) > 0.0,"AD-240 overcharge: the counter is per run state")

func _ink_hits(ids, dash: bool) -> Array:
	var r = _sim("essence.lightning",ids)
	r.add_target(Vector2(300,340),Vector2.ZERO,100000.0)
	r.add_target(Vector2(300,500),Vector2.ZERO,100000.0)
	if dash:
		r.artifact_dash()
	var amounts: Array = []
	for aim in [Vector2.RIGHT,Vector2(1.0,1.0)]:
		r.mana = float(r.settings["combat"]["player_max_mana"])
		r.try_cast(0,r.actor.position,aim)
		for i in 120:
			r.step()
	for entry in r.trace.filter_records(-1,"","hit"):
		amounts.append(int(entry["amount"]))
	return amounts

func test_quicksilver_ink(t) -> void:
	var scale := float(Artifacts.new(["quicksilver_ink"]).param("quicksilver_ink","damage_scale"))
	var plain := _ink_hits(null,true)
	var held := _ink_hits(["quicksilver_ink"],true)
	var idle := _ink_hits(["quicksilver_ink"],false)
	t.equal(plain.size(),2,"AD-240 quicksilver ink: both casts connect")
	t.equal(held[0],roundi(float(plain[0])*(1.0+scale)),"AD-240 quicksilver ink: the cast after a dash deals +damage_scale")
	t.equal(held[1],plain[1],"AD-240 quicksilver ink: the bonus is consumed by that cast")
	t.equal(idle,plain,"AD-240 quicksilver ink: without a dash nothing changes")

func _mirror_scene(ids) -> Array:
	var r = _sim("essence.lightning",ids,"form.beam")
	var origin: Vector2 = r.actor.position
	r.collision_walls = [Rect2(origin.x+100.0,origin.y-250.0,20.0,600.0)]
	var behind = r.add_target(Vector2(origin.x+40.0,origin.y+160.0),Vector2.ZERO,100000.0)
	r.try_cast(0,origin,Vector2(1,1))
	for i in 20:
		r.step()
	return [r,behind]

func test_mirror_glyph(t) -> void:
	var plain: Array = _mirror_scene(null)
	var held: Array = _mirror_scene(["mirror_glyph"])
	t.equal(plain[1].health.current,plain[1].health.maximum,"AD-240 mirror glyph: without it the beam stops at the wall")
	t.check(held[1].health.current < held[1].health.maximum,"AD-240 mirror glyph: the beam reflects off the wall and hits the enemy")
	var reflects := int(held[0].artifacts.param("mirror_glyph","reflects"))
	var beams: Array = held[0].active.filter(func(e): return e["kind"] == "beam")
	t.check(not beams.is_empty() and beams[0]["effect"].path.size() == 2+reflects,"AD-240 mirror glyph: path has `reflects` extra legs, not more")

func _blast(ids, form: String) -> Array:
	var r = _sim("essence.fire",ids,form)
	var radius_key := "burst_radius" if form == "form.burst" else "field_radius"
	var params: Dictionary = r.loadout.get_plan(0).snapshot()["root"]["params"]
	var base_radius := float(params[radius_key])
	var inner = r.add_target(r.actor.position+Vector2(10,0),Vector2.ZERO,100000.0)
	var ring = r.add_target(r.actor.position+Vector2(0,base_radius+inner.radius+base_radius*0.1),Vector2.ZERO,100000.0)
	r.try_cast(0,r.actor.position,Vector2.RIGHT,r.actor.position)
	for i in 3:
		r.step()
	return [r,inner,ring]

func test_fracture_lens(t) -> void:
	var held_scale := Artifacts.new(["fracture_lens"])
	var size := float(held_scale.param("fracture_lens","size_scale"))
	var damage := float(held_scale.param("fracture_lens","damage_scale"))
	for form in ["form.burst","form.field"]:
		var plain: Array = _blast(null,form)
		var held: Array = _blast(["fracture_lens"],form)
		t.equal(plain[2].health.current,plain[2].health.maximum,"AD-240 fracture lens %s: outside the base radius is untouched" % form)
		t.check(held[2].health.current < held[2].health.maximum,"AD-240 fracture lens %s: the larger radius reaches the ring enemy" % form)
		var dealt_plain: float = plain[1].health.maximum-plain[1].health.current
		var dealt_held: float = held[1].health.maximum-held[1].health.current
		t.check(dealt_plain > 0.0 and absf(dealt_held/dealt_plain-(1.0+damage)) < 0.1,"AD-240 fracture lens %s: damage scaled by damage_scale" % form)
	var bolt = _sim("essence.fire",["fracture_lens"])
	var plain_bolt = _sim("essence.fire",null)
	for r in [bolt,plain_bolt]:
		r.add_target(Vector2(300,340),Vector2.ZERO,100000.0)
		_fire(r)
	t.equal(bolt.trace.filter_records(-1,"","hit")[0]["amount"],plain_bolt.trace.filter_records(-1,"","hit")[0]["amount"],"AD-240 fracture lens: projectile damage is unchanged")
	t.check(size > 0.0 and damage < 0.0,"AD-240 fracture lens: tunables read from data")


## --- Step 4: defence artifacts (shard_mail, tidecaller_shell, grave_salt) ---------------------------------

func _session(ids):
	var s = Session.new(240,"empty",0)
	s.sim.loadout.allow_edit = true
	s.defer_clear = true
	s.sim.settings["combat"]["regen_mana_per_tick"] = 0.0
	if ids != null:
		s.sim.artifacts = Artifacts.new(ids)
	return s

## Shatters a frozen target with a force bolt, then returns [session, hp lost to one 10-damage hit right after].
func _shatter_hit(ids, freeze: bool) -> Array:
	var s = _session(ids)
	var formula := {"schema_version":2,"formula_id":"test.ad240","display_name":"t",
		"root":{"essence_id":"essence.force","manifestation_id":"form.projectile","modifier_ids":[],"params":{}}}
	s.sim.equip(1,formula)
	var foe = s.spawn_enemy("bone_thrall",Vector2(900,800))
	var victim = s.sim.add_target(s.sim.actor.position+Vector2(160,0),Vector2.ZERO,100000.0)
	if freeze:
		_status(s.sim,victim,"frozen")
	s.sim.try_cast(1,s.sim.actor.position,Vector2.RIGHT)
	for i in 40:
		s.sim.step()
	var before: float = s.sim.actor.health.current
	s.damage_player(foe.target.id,10.0,"physical")
	return [s,before-s.sim.actor.health.current]

func test_shard_mail(t) -> void:
	var params := Artifacts.new(["shard_mail"])
	var reduction := float(params.param("shard_mail","reduction"))
	var window := int(params.param("shard_mail","duration_ticks"))
	var plain: Array = _shatter_hit(null,true)
	var held: Array = _shatter_hit(["shard_mail"],true)
	t.check(plain[1] > 0.0,"AD-240 shard mail: a hit lands without it")
	t.check(held[0].sim.trace.filter_records(-1,"","reaction").any(func(e): return e["reason"] == "frozen_force_shatter"),"AD-240 shard mail: the shatter reaction fired")
	t.check(absf(held[1]-plain[1]*(1.0-reduction)) < 0.01,"AD-240 shard mail: damage right after a shatter is cut by `reduction`")
	var no_shatter: Array = _shatter_hit(["shard_mail"],false)
	t.equal(no_shatter[1],plain[1],"AD-240 shard mail: no shatter, no reduction")
	var s = held[0]
	var foe = s.enemies[0]
	s.sim.step()
	var left: int = int(s.sim.artifacts.state["shard_mail_until"])-s.sim.clock.tick
	t.check(left > 0 and left <= window,"AD-240 shard mail: the timer lives in artifacts.state and is at most duration_ticks")
	for i in window+2:
		s.sim.step()
	var hp: float = s.sim.actor.health.current
	s.damage_player(foe.target.id,10.0,"physical")
	t.equal(hp-s.sim.actor.health.current,plain[1],"AD-240 shard mail: the reduction ends after duration_ticks")

func _shell_mana(ids, spot: Vector2) -> float:
	var s = _session(ids)
	s.set_water([{"kind":"shallow","rect":[300,300,500,120]}])
	s.sim.actor.position = spot
	s.sim.mana = 10.0
	for i in 60:
		s.step()
	return s.sim.mana-10.0

func test_tidecaller_shell(t) -> void:
	var per_second := float(Artifacts.new(["tidecaller_shell"]).param("tidecaller_shell","mana_per_second"))
	var wet := _shell_mana(["tidecaller_shell"],Vector2(400,360))
	t.check(absf(wet-per_second) < 0.05,"AD-240 tidecaller shell: one second in water restores mana_per_second (%.2f)" % wet)
	t.equal(_shell_mana(["tidecaller_shell"],Vector2(400,700)),0.0,"AD-240 tidecaller shell: nothing restored on dry ground")
	t.equal(_shell_mana(null,Vector2(400,360)),0.0,"AD-240 tidecaller shell: no artifact, no restore in water")

func _salt_kill(ids, status: String) -> Array:
	var r = _sim("essence.fire",ids)
	var target = r.add_target(Vector2(300,340),Vector2.ZERO,1.0)
	if status != "":
		_status(r,target,status)
	r.actor.health.current = 50.0
	_fire(r)
	return [r,target]

func test_grave_salt(t) -> void:
	var heal := float(Artifacts.new(["grave_salt"]).param("grave_salt","heal"))
	for status in ["wet","burning","frozen"]:
		var held: Array = _salt_kill(["grave_salt"],status)
		t.check(not held[1].alive(),"AD-240 grave salt %s: the target dies" % status)
		t.equal(held[0].actor.health.current,50.0+heal,"AD-240 grave salt %s: killing a reacting target heals `heal`" % status)
		t.equal(held[0].trace.filter_records(-1,"","artifact").filter(func(e): return e["reason"] == "artifact.grave_salt").size(),1,"AD-240 grave salt %s: the heal is traced once" % status)
		var plain: Array = _salt_kill(null,status)
		t.equal(plain[0].actor.health.current,50.0,"AD-240 grave salt %s: no artifact, no heal" % status)
	var bare: Array = _salt_kill(["grave_salt"],"")
	t.check(not bare[1].alive() and bare[0].actor.health.current == 50.0,"AD-240 grave salt: a kill with no reaction status heals nothing")
	var full = _sim("essence.fire",["grave_salt"])
	var victim = full.add_target(Vector2(300,340),Vector2.ZERO,1.0)
	_status(full,victim,"wet")
	_fire(full)
	t.equal(full.actor.health.current,full.actor.health.maximum,"AD-240 grave salt: healing never exceeds max HP")
