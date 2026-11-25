extends RefCounted
## AD-240: 12 new artifacts with combo tags. Step 1: data, tags, tag-biased rewards, card tag, meta unlocks.
const Artifacts = preload("res://world/artifacts.gd")
const Reward = preload("res://world/reward_generator.gd")
const Flow = preload("res://world/run_flow.gd")
const Meta = preload("res://world/meta_progress.gd")
const Runner = preload("res://magic/runtime/spell_runner.gd")
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
func _sim(essence: String, ids):
	var r = Runner.new(143)
	r.settings["combat"]["regen_mana_per_tick"] = 0.0
	r.mana = float(r.settings["combat"]["player_max_mana"])
	var formula := {"schema_version":2,"formula_id":"test.ad240","display_name":"t",
		"root":{"essence_id":essence,"manifestation_id":"form.projectile","modifier_ids":[],"params":{}}}
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
