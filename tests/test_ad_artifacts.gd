extends RefCounted
## AD-143 step 1: artifact data, holder, run persistence and the reward/merchant/treasure sources.
const Artifacts = preload("res://world/artifacts.gd")
const State = preload("res://world/run_state.gd")
const Reward = preload("res://world/reward_generator.gd")
const Merchant = preload("res://world/merchant.gd")
const Flow = preload("res://world/run_flow.gd")
const Runner = preload("res://magic/runtime/spell_runner.gd")
const Session = preload("res://combat/combat_session.gd")
const SEED := 20261022
const IDS := ["rebound_sigil","residue_crystal","shatterheart","momentum_rune","echo_chamber","stormglass",
	"tidewalkers_boots","ember_heart","gravity_lens","split_prism","archivists_quill","warding_lantern"]

func run(t) -> void:
	_config(t)
	_holder(t)
	_persistence(t)
	_rewards(t)
	_merchant(t)
	_treasure(t)
	_momentum_rune(t)
	_echo_chamber(t)
	_split_prism(t)
	_rebound_sigil(t)
	_stormglass(t)
	_gravity_lens(t)
	_residue_crystal(t)
	_no_artifacts_identical(t)

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

func _fresh_run():
	var cfg: Dictionary = _tuning()
	var run_state = State.new()
	var formulas := {}
	for id in cfg["initial_formulas"]:
		formulas[id] = {"id":id}
	run_state.initialize(SEED,cfg,formulas)
	return run_state

func _config(t) -> void:
	var cfg: Dictionary = Artifacts.load_config()
	var defs: Dictionary = cfg["artifacts"]
	var keys := _csv_keys()
	t.equal(defs.size(),12,"AD-143 config has 12 artifacts")
	for id in IDS:
		t.check(defs.has(id),"AD-143 artifact present: "+id)
		var def: Dictionary = defs.get(id,{})
		t.check(keys.has(str(def.get("name_key",""))) and keys.has(str(def.get("desc_key",""))),"AD-143 %s name/desc keys exist in CSV" % id)
		t.check(not def.get("hooks",[]).is_empty() and def.get("hooks",[]).all(func(h): return h in Artifacts.HOOKS),"AD-143 %s hooks are known" % id)
	t.check(keys.has("run.shop.artifact_label"),"AD-143 shop label key exists")
	t.equal(int(cfg["max_held"]),6,"AD-143 max_held comes from data")
	t.equal(Artifacts.max_held(),int(cfg["max_held"]),"AD-143 max_held accessor reads data")

func _holder(t) -> void:
	var held = Artifacts.new()
	t.check(held.is_empty(),"AD-143 holder starts empty")
	t.check(not held.can_add("nope") and held.add("nope")["reason"] == "ARTIFACT_UNKNOWN","AD-143 unknown id rejected")
	t.check(held.add("split_prism")["ok"] and held.has("split_prism"),"AD-143 add works")
	t.equal(held.add("split_prism")["reason"],"ARTIFACT_DUPLICATE","AD-143 duplicate rejected")
	t.equal(held.param("split_prism","extra_projectiles"),1,"AD-143 param read from data")
	t.equal(held.param("split_prism","missing",7),7,"AD-143 param default")
	held.state["x"] = 1
	held.reset_room()
	t.check(held.state.is_empty(),"AD-143 reset_room clears counters")
	for id in IDS.slice(0,5):
		if id != "split_prism":
			t.check(held.add(id)["ok"],"AD-143 fill "+id)
	t.equal(held.ids().size(),Artifacts.max_held(),"AD-143 holder is full")
	var over: Dictionary = held.add(IDS[11])
	t.check(not over["ok"] and over["reason"] == "ARTIFACT_LIMIT" and not held.can_add(IDS[11]),"AD-143 limit rejects the 7th")

func _persistence(t) -> void:
	var state = _fresh_run()
	t.check(state.artifacts.is_empty(),"AD-143 initialize clears artifacts")
	t.check(state.add_artifact("ember_heart")["ok"] and state.add_artifact("shatterheart")["ok"],"AD-143 run adds artifacts")
	t.equal(state.add_artifact("ember_heart")["reason"],"ARTIFACT_DUPLICATE","AD-143 run rejects duplicate")
	t.equal(state.add_artifact("bogus")["reason"],"ARTIFACT_UNKNOWN","AD-143 run rejects unknown")
	t.equal(state.snapshot()["artifacts"],["ember_heart","shatterheart"],"AD-143 snapshot carries artifacts")
	var flow = Flow.new(SEED,Flow.CONFIG_V2)
	flow.run.artifacts = state.artifacts.duplicate()
	var snap: Dictionary = flow.run.snapshot()
	var registry = flow.session.sim.registry
	var max_rooms: int = flow.rooms.size()
	var restored = State.new()
	t.check(restored.restore(snap,registry,max_rooms)["ok"],"AD-143 snapshot restores")
	t.equal(restored.artifacts,["ember_heart","shatterheart"],"AD-143 artifacts round-trip")
	var legacy: Dictionary = snap.duplicate(true)
	legacy.erase("artifacts")
	var old = State.new()
	t.check(old.restore(legacy,registry,max_rooms)["ok"] and old.artifacts.is_empty(),"AD-143 snapshot without the key restores")
	for bad in [["bogus"],["ember_heart","ember_heart"],"ember_heart",IDS.slice(0,7)]:
		var broken: Dictionary = snap.duplicate(true)
		broken["artifacts"] = bad
		t.equal(State.new().restore(broken,registry,max_rooms)["reason"],"RUN_ARTIFACTS_INVALID","AD-143 invalid artifacts rejected: "+str(bad))

func _rewards(t) -> void:
	var tuning: Dictionary = _tuning()
	var state = _fresh_run()
	var gen = Reward.new(tuning)
	var plain: Array = gen.choices(state,"ruins_combat_a")
	var forced: Array = gen.choices(state,"ruins_combat_a",true)
	t.equal(forced.back()["kind"],"artifact","AD-143 forced reward offers an artifact card")
	t.check(Artifacts.is_known(str(forced.back()["id"])) and forced.back().has("behaviour_key") and forced.back().has("rarity"),"AD-143 artifact card is complete")
	t.equal(forced.slice(0,forced.size()-1),plain.filter(func(o): return o["kind"] != "artifact"),"AD-143 rune options unchanged by the artifact card")
	t.equal(forced,gen.choices(state,"ruins_combat_a",true),"AD-143 artifact card deterministic")
	state.artifacts = Artifacts.new().ids()
	var full = Artifacts.new()
	for id in IDS.slice(0,6):
		full.add(id)
	state.artifacts = full.ids()
	t.check(gen.choices(state,"ruins_combat_a",true).all(func(o): return o["kind"] != "artifact"),"AD-143 no card when full")
	state.artifacts = ["ember_heart"]
	t.check(gen.choices(state,"ruins_combat_a",true).all(func(o): return o["id"] != "ember_heart" if o["kind"] == "artifact" else true),"AD-143 held artifact never offered")
	var shown := 0
	for n in 40:
		var room_id := "room_%d" % n
		var unforced: Array = gen.choices(_fresh_run(),room_id)
		if unforced.back()["kind"] == "artifact":
			shown += 1
	t.check(shown > 0 and shown < 40,"AD-143 unforced cards follow reward_artifact_chance")

func _merchant(t) -> void:
	var tuning: Dictionary = _tuning()
	var state = _fresh_run()
	var shop = Merchant.new(tuning)
	var stock: Array = shop.build(state,["essence.fire","essence.cold","essence.force","form.orb","mod.homing"])
	var last: Dictionary = stock.back()
	t.equal(last["kind"],"artifact","AD-143 merchant stocks an artifact")
	t.equal(stock[0]["kind"],"rune","AD-143 stock[0] still the rune")
	t.equal(stock[1]["id"],"upgrade.hp","AD-143 stock[1] still the HP upgrade")
	t.check(int(last["price"]) > int(tuning["merchant"]["rune_price"]),"AD-143 artifact priced above runes")
	t.equal(stock,Merchant.new(tuning).build(state,["essence.fire","essence.cold","essence.force","form.orb","mod.homing"]),"AD-143 merchant deterministic")
	t.check(Merchant.item_label(last).begins_with("Artifact: ") and not Merchant.item_label(last).contains("artifact."),"AD-143 artifact label translated")
	var poor: Dictionary = shop.purchase(2,state)
	t.equal(poor["reason"],"INSUFFICIENT_CURRENCY","AD-143 needs currency")
	state.currency = int(last["price"])+5
	var bought: Dictionary = shop.purchase(2,state)
	t.check(bought["ok"] and bought["kind"] == "artifact","AD-143 purchase succeeds")
	t.check(state.artifacts == [last["artifact_id"]] and state.currency == 5,"AD-143 purchase adds artifact and takes currency")
	var again = Merchant.new(tuning)
	again.build(state,["essence.fire"])
	var full = Artifacts.new()
	for id in IDS.slice(0,6):
		full.add(id)
	state.artifacts = full.ids()
	state.currency = 500
	var blocked = Merchant.new(tuning)
	blocked.stock = [{"id":"artifact.split_prism","kind":"artifact","artifact_id":"rebound_sigil","price":10}]
	var refused: Dictionary = blocked.purchase(0,state)
	t.check(refused["reason"] == "ARTIFACT_LIMIT" and state.currency == 500,"AD-143 full holder refuses before taking currency")
	state.artifacts = ["rebound_sigil"]
	var dup: Dictionary = blocked.purchase(0,state)
	t.check(dup["reason"] == "ARTIFACT_DUPLICATE" and state.currency == 500,"AD-143 duplicate refuses before taking currency")

func _kill_all(flow) -> void:
	for i in 3000:
		if flow.state != "fighting":
			return
		for enemy in flow.session.enemies:
			if enemy.target.alive():
				enemy.target.receive_damage(100000,"fire",1,100)
		flow.step()

func _treasure(t) -> void:
	var flow = Flow.new(SEED,Flow.CONFIG_V2)
	var reached := false
	for guard in 40:
		if flow.state == "fighting":
			_kill_all(flow)
		if flow.state == "cleared" and not flow.reward_collected and flow.room.values["type"] != "boss":
			flow.choose_reward(0)
		if flow.next_is_optional():
			reached = true
			break
		if flow.state not in ["cleared","workshop"]:
			break
		flow.session.sim.actor.position = flow.room.marker("exit")
		flow.try_exit(flow.room.marker("exit"))
	t.check(reached and flow.try_exit(flow.room.marker("exit"),true)["ok"],"AD-143 reaches the treasure room")
	t.equal(str(flow.room.values["id"]),"ruins_treasure","AD-143 in the treasure room")
	var index := -1
	for i in flow.reward_options.size():
		if flow.reward_options[i]["kind"] == "artifact":
			index = i
	t.check(index >= 0,"AD-143 treasure room offers an artifact card")
	if index < 0:
		return
	var id: String = str(flow.reward_options[index]["id"])
	var outcome: Dictionary = flow.choose_reward(index)
	t.check(outcome["ok"] and outcome["kind"] == "artifact" and outcome["id"] == id,"AD-143 choosing the card succeeds")
	t.check(flow.run.artifacts.has(id) and flow.session.sim.artifacts.has(id),"AD-143 artifact added to run and active in the sim")

## --- AD-143 step 2: cast/hit/dash hooks -------------------------------------------------------------

func _formula(form: String, essence: String = "essence.fire", modifiers: Array = []) -> Dictionary:
	return {"schema_version":2,"formula_id":"test.%s.%s" % [form,essence],"display_name":form,
		"root":{"essence_id":essence,"manifestation_id":form,"modifier_ids":modifiers,"params":{}}}

## A sim with no mana regen and the given artifact ids (null = no holder at all).
func _sim(form: String, essence: String = "essence.fire", modifiers: Array = [], ids = []):
	var r = Runner.new(143)
	r.settings["combat"]["regen_mana_per_tick"] = 0.0
	r.mana = float(r.settings["combat"]["player_max_mana"])
	t_equip(r,_formula(form,essence,modifiers))
	if ids != null:
		r.artifacts = Artifacts.new(ids)
	return r

func t_equip(r, formula: Dictionary) -> void:
	var equipped: Dictionary = r.equip(0,formula)
	if not equipped["ok"]:
		printerr("equip failed: ",equipped)

func _step(r, ticks: int) -> void:
	for i in ticks:
		r.step()

## Casts slot 0 once the slot is ready again (mana is topped up so only the artifact effect is observed).
func _cast(r) -> Dictionary:
	r.mana = float(r.settings["combat"]["player_max_mana"])
	for i in 120:
		var result: Dictionary = r.try_cast(0,r.actor.position,Vector2.RIGHT)
		if result["accepted"]:
			return result
		r.step()
	return {"accepted":false}

func _count(r, kind: String) -> int:
	return r.trace.filter_records(-1,"",kind).size()

func _momentum_rune(t) -> void:
	var session = Session.new(143)
	session.sim.artifacts = Artifacts.new(["momentum_rune"])
	session.sim.settings["combat"]["regen_mana_per_tick"] = 0.0
	var sim = session.sim
	var full: float = float(sim.settings["combat"]["player_max_mana"])
	sim.mana = full
	t.check(session.issue({"dash":true})["accepted"] and session.player.dashes == 1,"AD-143 momentum: dash accepted")
	t.equal(int(sim.artifacts.state.get("momentum",0)),int(sim.artifacts.param("momentum_rune","free_casts")),"AD-143 momentum: dash arms free_casts")
	for i in 120:
		if session.player.dash_left == 0 and session.player.recovery_left == 0:
			break
		session.step()
	sim.mana = full
	var free: Dictionary = session.issue({"cast":1})
	t.check(free["accepted"],"AD-143 momentum: post-dash cast accepted")
	t.equal(sim.mana,full,"AD-143 momentum: post-dash cast costs no mana")
	t.equal(int(sim.trace.filter_records(int(free["cast_id"]),"","cost_paid")[0]["amount"]),0,"AD-143 momentum: cost_paid records 0")
	for i in 120:
		if sim.loadout.check_slot(1) == "READY":
			break
		session.step()
	session.issue({"cast":1})
	t.check(sim.mana < full,"AD-143 momentum: the next cast pays mana again")

func _echo_chamber(t) -> void:
	var r = _sim("form.projectile","essence.fire",[],["echo_chamber"])
	var every := int(r.artifacts.param("echo_chamber","every"))
	var target = r.add_target(Vector2(420,340),Vector2.ZERO,100000.0)
	for i in every-1:
		_cast(r)
	t.equal(_count(r,"artifact"),0,"AD-143 echo: no echo before the every-th cast")
	var spawned: int = _count(r,"spawn")
	var fifth: Dictionary = _cast(r)
	t.equal(_count(r,"artifact"),1,"AD-143 echo: the every-th cast echoes once")
	t.equal(r.trace.filter_records(-1,"","artifact")[0]["reason"],"artifact.echo_chamber","AD-143 echo: trace reason")
	t.equal(_count(r,"spawn")-spawned,2,"AD-143 echo: the fifth cast spawns twice")
	_step(r,60)
	var amounts := {}
	for hit in r.trace.filter_records(-1,"","hit"):
		amounts[int(hit["cast_id"])] = int(hit["amount"])
	var echo_id := int(r.trace.filter_records(-1,"","artifact")[0]["cast_id"])
	t.check(echo_id != int(fifth["cast_id"]) and amounts.has(echo_id) and amounts.has(int(fifth["cast_id"])),"AD-143 echo: own cast id, both hit")
	t.check(amounts[echo_id] < amounts[int(fifth["cast_id"])],"AD-143 echo: damage scaled down")
	_cast(r)
	t.equal(_count(r,"artifact"),1,"AD-143 echo: sixth cast does not echo")
	t.check(target.alive(),"AD-143 echo: scenario sanity")

func _split_prism(t) -> void:
	var base = _sim("form.projectile","essence.fire",["mod.split"])
	var prism = _sim("form.projectile","essence.fire",["mod.split"],["split_prism"])
	_cast(base)
	_cast(prism)
	var extra := int(prism.artifacts.param("split_prism","extra_projectiles"))
	t.equal(_count(prism,"spawn"),_count(base,"spawn")+extra,"AD-143 split prism: +extra_projectiles on a Split cast")
	var plain = _sim("form.projectile","essence.fire",[],["split_prism"])
	_cast(plain)
	t.equal(_count(plain,"spawn"),1,"AD-143 split prism: no effect without Split")

func _rebound_sigil(t) -> void:
	var wall := Rect2(300,300,20,80)
	var plain = _sim("form.projectile","essence.fire",[],null)
	plain.collision_walls = [wall]
	_cast(plain)
	_step(plain,60)
	t.equal(plain.active.size(),0,"AD-143 rebound: without the artifact the projectile dies at the wall")
	var r = _sim("form.projectile","essence.fire",[],["rebound_sigil"])
	r.collision_walls = [wall]
	_cast(r)
	var bounced := false
	for i in 60:
		r.step()
		if not r.active.is_empty() and r.active[0]["effect"].bounces_left == 0:
			bounced = true
			break
	t.check(bounced and r.active.size() == 1 and not r.active[0]["effect"].expired,"AD-143 rebound: projectile survives the wall contact")
	var effect = r.active[0]["effect"]
	t.check(effect.direction.x < 0.0,"AD-143 rebound: it now travels the opposite way")
	var x: float = effect.position.x
	_step(r,3)
	t.check(not effect.expired and effect.position.x < x,"AD-143 rebound: and keeps moving away from the wall")
	_step(r,200)
	t.equal(r.active.size(),0,"AD-143 rebound: bounces are limited, it expires at the bounds")

func _stormglass(t) -> void:
	var plain = _sim("form.projectile","essence.lightning",[],null)
	var storm = _sim("form.projectile","essence.lightning",[],["stormglass"])
	for r in [plain,storm]:
		r.add_target(Vector2(300,340),Vector2.ZERO,100000.0)
		r.add_target(Vector2(400,340),Vector2.ZERO,100000.0)
		r.add_target(Vector2(500,340),Vector2.ZERO,100000.0)
		_cast(r)
		_step(r,40)
	t.equal(plain.trace.filter_records(-1,"","reaction").size(),0,"AD-143 stormglass: dry targets do not arc without it")
	var arcs: Array = storm.trace.filter_records(-1,"","reaction").filter(func(e): return e["reason"] == "wet_lightning_arc")
	t.equal(arcs.size(),1+int(storm.artifacts.param("stormglass","extra_jumps")),"AD-143 stormglass: dry arc plus extra_jumps further arcs")
	var direct: int = int(storm.trace.filter_records(-1,"","hit")[0]["amount"])
	t.check(int(arcs[0]["amount"]) > 0 and int(arcs[0]["amount"]) < direct,"AD-143 stormglass: dry arc hits for reduced damage")
	t.check(int(arcs[0]["target_id"]) != int(arcs[1]["target_id"]) and int(arcs[1]["target_id"]) != int(arcs[0]["source_id"]),"AD-143 stormglass: the jump reaches a new target")

func _gravity_lens(t) -> void:
	var distances: Array = []
	for ids in [[],["gravity_lens"]]:
		var r = _sim("form.orb","essence.fire",[],ids)
		var orbit := float(r.loadout.get_plan(0).snapshot()["root"]["params"]["orbit_radius"])
		var target = r.add_target(r.actor.position+Vector2(orbit+4.0,0),Vector2.ZERO,100000.0)
		_cast(r)
		_step(r,6)
		distances.append(target.position.distance_to(r.actor.position))
	t.check(distances[1] < distances[0]-0.5,"AD-143 gravity lens: an orb hit pulls the target toward the player")

func _residue_crystal(t) -> void:
	var r = _sim("form.burst","essence.fire",[],["residue_crystal"])
	r.add_target(Vector2(215,340),Vector2.ZERO,100000.0)
	var cast: Dictionary = r.try_cast(0,Vector2(215,340),Vector2.RIGHT)
	t.check(cast["accepted"],"AD-143 residue: burst accepted")
	t.equal(r._active_count("field"),1,"AD-143 residue: the burst leaves a field")
	var field = r.active[0]["effect"]
	t.equal(field.radius,float(r.artifacts.param("residue_crystal","field_radius")),"AD-143 residue: field radius from data")
	t.equal(str(field.root["essence"]["id"]),"essence.fire","AD-143 residue: field keeps the burst essence")
	var burst_hits := _count(r,"hit")
	_step(r,int(r.artifacts.param("residue_crystal","pulse_interval_ticks"))+2)
	t.check(_count(r,"hit") > burst_hits,"AD-143 residue: the field pulses damage")
	_step(r,int(r.artifacts.param("residue_crystal","duration_ticks"))+2)
	t.equal(r._active_count("field"),0,"AD-143 residue: the field expires after duration_ticks")
	t.equal(r.queue.active_effect_count(),0,"AD-143 residue: reservations are released")
	var full = _sim("form.burst","essence.fire",[],["residue_crystal"])
	for i in int(full.limits.get_limit("max_active_fields")):
		full.active.append({"kind":"field","effect":Runner.Field.new({"effect_id":900+i,"cast_id":1,"formula_id":"x","caster_id":1,"team":1,
			"root":{"params":{"field_radius":1.0,"field_duration_ticks":9}},"position":Vector2.ZERO}),"context":{},"trigger":{}})
	_cast(full)
	t.equal(full._active_count("field"),int(full.limits.get_limit("max_active_fields")),"AD-143 residue: skipped silently over the field budget")

## The same scripted fight with no holder and with an empty holder must give the identical trace.
func _no_artifacts_identical(t) -> void:
	var traces: Array = []
	for holder in [null,[]]:
		var r = _sim("form.projectile","essence.lightning",["mod.split"],holder)
		r.collision_walls = [Rect2(600,300,20,80)]
		r.add_target(Vector2(300,340),Vector2.ZERO,100000.0)
		r.add_target(Vector2(420,380),Vector2.ZERO,100000.0)
		for i in 6:
			_cast(r)
		_step(r,90)
		var burst = _sim("form.burst","essence.fire",[],holder)
		burst.add_target(Vector2(215,340))
		burst.try_cast(0,Vector2(215,340),Vector2.RIGHT)
		_step(burst,60)
		traces.append(r.trace_json()+burst.trace_json())
	t.check(traces[0].length() > 500,"AD-143 empty holder: scenario trace is non-trivial")
	t.equal(traces[1],traces[0],"AD-143 empty holder: trace identical to no holder")
