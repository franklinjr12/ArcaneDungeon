extends RefCounted
## AD-143 step 1: artifact data, holder, run persistence and the reward/merchant/treasure sources.
const Artifacts = preload("res://world/artifacts.gd")
const State = preload("res://world/run_state.gd")
const Reward = preload("res://world/reward_generator.gd")
const Merchant = preload("res://world/merchant.gd")
const Flow = preload("res://world/run_flow.gd")
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
