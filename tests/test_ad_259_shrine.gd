extends RefCounted
## AD-259 step 1: the prototype spell test area becomes an in-world Shrine room (altar + coin statue + practice idol).
## API these tests pin (implemented in steps 2-3):
##  Data  world/data/run_v2.json top-level `shrine`: enabled, interact_radius, room_art_key,
##        altar {art_key,prompt,position[x,y]}, statue {art_key,prompt,position[x,y]},
##        practice_idol {art_key,prompt,position[x,y],optional:true}. Prices stay in the `merchant` block.
##  Flow  shrine_objects() -> [{id: altar|statue|idol, art_key, prompt, position}] (empty outside workshop mode)
##        shrine_nearest(pos) -> id within interact_radius else ""
##        shrine_interact(id,pos) -> {ok:false,reason:"TOO_FAR"} | altar {ok,kind:"altar",options} | statue {ok,kind:"statue",stock} | idol {ok,kind:"idol"}
##        altar_options (rewards.choices once per shrine visit), altar_taken, choose_altar(index) unlocks like choose_reward
##        statue purchases still go through flow.buy(index); the idol never gates leaving the shrine.
##  UI    ui/run_controller.gd: const shrine_ui_in_world := true and func _shrine_prompt_text; no debug panel in shrine rooms.
const Flow = preload("res://world/run_flow.gd")
const SEED := 20261022
const BANNED := ["debug","DEBUG","F1","dev","[test]","interact","choose_reward"]

func run(t) -> void:
	test_ad_259_a_altar_and_statue(t)
	test_ad_259_b_practice_idol_optional(t)
	test_ad_259_c_in_world_prompts(t)
	test_ad_259_d_placeholder_art_keys(t)

func _cfg() -> Dictionary:
	return JSON.parse_string(FileAccess.get_file_as_string(Flow.CONFIG_V2))

func _shrine_cfg() -> Dictionary:
	var shrine = _cfg().get("shrine",{})
	return shrine if shrine is Dictionary else {}

func _kill_all(flow, limit: int = 3000) -> void:
	for i in limit:
		if flow.state != "fighting":
			return
		for enemy in flow.session.enemies:
			if enemy.target.alive():
				enemy.target.receive_damage(100000,"fire",1,100)
		flow.step()

## Drives a v2 run to the first between-floor workshop (the shrine room).
func _shrine_flow(run_seed: int = SEED):
	var flow = Flow.new(run_seed,Flow.CONFIG_V2)
	for guard in 80:
		if flow.state == "fighting":
			_kill_all(flow)
		if flow.state == "workshop" and not flow.prelude:
			return flow
		if flow.state == "won" or flow.state == "dead":
			break
		if flow.state == "cleared" and not flow.reward_collected and flow.room.values["type"] != "boss":
			flow.choose_reward(0)
		var pos: Vector2 = flow.room.marker("exit")
		flow.session.sim.actor.position = pos
		flow.try_exit(pos,true)
	return null

func _object(flow, id: String) -> Dictionary:
	if not flow.has_method("shrine_objects"):
		return {}
	for obj in flow.shrine_objects():
		if str(obj.get("id","")) == id:
			return obj
	return {}

func test_ad_259_a_altar_and_statue(t) -> void:
	var cfg: Dictionary = _cfg()
	var shrine: Dictionary = _shrine_cfg()
	t.check(not shrine.is_empty() and bool(shrine.get("enabled",false)),"AD-259a data has an enabled shrine block")
	var flow = _shrine_flow()
	t.check(flow != null,"AD-259a reached a workshop room")
	if flow == null:
		return
	t.check(flow.has_method("shrine_objects"),"AD-259a flow.shrine_objects exists")
	if not flow.has_method("shrine_objects"):
		return
	var ids: Array = flow.shrine_objects().map(func(o): return str(o.get("id","")))
	ids.sort()
	t.equal(ids,["altar","idol","statue"],"AD-259a shrine has altar, statue and idol")
	var altar: Dictionary = _object(flow,"altar")
	var statue: Dictionary = _object(flow,"statue")
	var altar_pos: Vector2 = altar.get("position",Vector2(-9999,-9999))
	var statue_pos: Vector2 = statue.get("position",Vector2(-9999,-9999))
	t.check(flow.has_method("shrine_nearest") and flow.shrine_nearest(altar_pos) == "altar","AD-259a nearest at altar position is altar")
	t.check(flow.has_method("shrine_nearest") and flow.shrine_nearest(Vector2(-99999,-99999)) == "","AD-259a nothing nearby when far away")
	# Out of range.
	var far: Vector2 = altar_pos + Vector2(float(shrine.get("interact_radius",64.0))+500.0,0)
	for id in ["altar","statue","idol"]:
		var refused: Dictionary = flow.shrine_interact(id,far) if flow.has_method("shrine_interact") else {}
		t.equal(refused.get("reason",""),"TOO_FAR","AD-259a %s out of range -> TOO_FAR" % id)
		t.check(not bool(refused.get("ok",true)),"AD-259a %s out of range is not ok" % id)
	# Altar: choose once.
	var seen: Dictionary = flow.shrine_interact("altar",altar_pos) if flow.has_method("shrine_interact") else {}
	t.check(bool(seen.get("ok",false)) and seen.get("kind","") == "altar","AD-259a altar interaction ok")
	var options: Array = seen.get("options",[])
	t.check(not options.is_empty(),"AD-259a altar offers choices")
	t.check("altar_options" in flow and flow.altar_options.size() == options.size(),"AD-259a flow.altar_options stores the choices")
	var again: Dictionary = flow.shrine_interact("altar",altar_pos) if flow.has_method("shrine_interact") else {}
	t.equal(again.get("options",[]),options,"AD-259a choices are generated once per visit")
	var unlocked_before: int = flow.run.unlocked.size()
	var picked: Dictionary = flow.choose_altar(0) if flow.has_method("choose_altar") else {}
	t.check(bool(picked.get("ok",true)) and picked.has("kind"),"AD-259a choose_altar returns a reward outcome")
	if not options.is_empty() and options[0].get("kind","") == "rune":
		t.check(flow.run.unlocked.size() >= unlocked_before and flow.run.unlocked.has(str(options[0]["id"])),"AD-259a altar pick unlocks the rune")
	t.check("altar_taken" in flow and flow.altar_taken,"AD-259a altar_taken set after choosing")
	var second: Dictionary = flow.choose_altar(0) if flow.has_method("choose_altar") else {"ok":true}
	t.check(not bool(second.get("ok",true)),"AD-259a second choose_altar rejected")
	# Statue: stock prices from the merchant data block.
	var sold: Dictionary = flow.shrine_interact("statue",statue_pos) if flow.has_method("shrine_interact") else {}
	t.check(bool(sold.get("ok",false)) and sold.get("kind","") == "statue","AD-259a statue interaction ok")
	var stock: Array = sold.get("stock",[])
	t.check(not stock.is_empty(),"AD-259a statue has stock")
	var merchant_cfg: Dictionary = cfg["merchant"]
	var price_key := {"upgrade.hp":"max_hp_upgrade_price","upgrade.mana":"max_mana_upgrade_price","upgrade.dash":"dash_charge_upgrade_price"}
	var hp_index := -1
	for i in stock.size():
		var id := str(stock[i].get("id",""))
		if price_key.has(id):
			t.equal(int(stock[i]["price"]),int(merchant_cfg[price_key[id]]),"AD-259a statue %s price from merchant data" % id)
		if id == "upgrade.hp":
			hp_index = i
	t.check(hp_index >= 0,"AD-259a statue sells the max hp upgrade")
	if hp_index < 0:
		return
	var price := int(stock[hp_index]["price"])
	flow.run.currency = price-1
	var poor: Dictionary = flow.buy(hp_index)
	t.check(not bool(poor.get("ok",true)),"AD-259a buy with too few coins fails")
	t.equal(flow.run.currency,price-1,"AD-259a failed buy leaves coins untouched")
	flow.run.currency = price+5
	var max_before: float = flow.run.max_hp
	var bought: Dictionary = flow.buy(hp_index)
	t.check(bool(bought.get("ok",false)),"AD-259a buy with enough coins succeeds")
	t.equal(flow.run.currency,5,"AD-259a purchase spends exactly the price")
	t.check(flow.run.max_hp > max_before,"AD-259a hp upgrade applied")

func test_ad_259_b_practice_idol_optional(t) -> void:
	var shrine: Dictionary = _shrine_cfg()
	t.check(shrine.has("practice_idol") and bool(shrine["practice_idol"].get("optional",false)),"AD-259b practice idol is flagged optional in data")
	var flow = _shrine_flow()
	t.check(flow != null,"AD-259b reached a workshop room")
	if flow == null:
		return
	var idol: Dictionary = _object(flow,"idol")
	t.check(not idol.is_empty(),"AD-259b idol exists in the shrine")
	if idol.is_empty():
		return
	var out: Dictionary = flow.shrine_interact("idol",idol["position"])
	t.check(bool(out.get("ok",false)) and out.get("kind","") == "idol","AD-259b idol interaction ok")
	t.check(flow.range_sim != null,"AD-259b practice range sim exists")
	var cast: Dictionary = flow.test_cast(0,Vector2.RIGHT)
	t.check(cast.has("accepted"),"AD-259b test_cast still works at the idol")
	# A fresh visit leaves the shrine without ever touching the idol, altar or statue.
	var fresh = _shrine_flow(SEED+1)
	t.check(fresh != null,"AD-259b second run reached a workshop")
	if fresh == null:
		return
	var index_before: int = fresh.run.sequence_index
	var pos: Vector2 = fresh.room.marker("exit")
	var left: Dictionary = fresh.try_exit(pos,true)
	t.check(bool(left.get("ok",false)) and fresh.run.sequence_index > index_before,"AD-259b can leave the shrine without using the idol")

func _prompt_ok(t, text: String, label: String) -> void:
	t.check(text.strip_edges() != "",label+" prompt non-empty")
	for word in BANNED:
		t.check(not text.contains(word),"%s prompt has no '%s'" % [label,word])

func test_ad_259_c_in_world_prompts(t) -> void:
	var shrine: Dictionary = _shrine_cfg()
	for id in ["altar","statue","practice_idol"]:
		var block: Dictionary = shrine.get(id,{})
		t.check(block.get("prompt","") is String,"AD-259c %s prompt is data text" % id)
		_prompt_ok(t,str(block.get("prompt","")),"AD-259c "+id)
	var flow = _shrine_flow()
	if flow != null and flow.has_method("shrine_objects"):
		for obj in flow.shrine_objects():
			_prompt_ok(t,str(obj.get("prompt","")),"AD-259c flow "+str(obj.get("id","")))
	else:
		t.check(false,"AD-259c flow exposes shrine_objects")
	var source := FileAccess.get_file_as_string("res://ui/run_controller.gd")
	t.check(source.contains("func _shrine_prompt_text"),"AD-259c controller has _shrine_prompt_text")
	t.check(source.contains("const shrine_ui_in_world") and source.contains("shrine_ui_in_world := true"),"AD-259c controller declares shrine_ui_in_world == true")

func test_ad_259_d_placeholder_art_keys(t) -> void:
	var shrine: Dictionary = _shrine_cfg()
	var keys: Array = [str(shrine.get("room_art_key",""))]
	for id in ["altar","statue","practice_idol"]:
		keys.append(str(shrine.get(id,{}).get("art_key","")))
	var rx := RegEx.new()
	rx.compile("^shrine\\.[a-z0-9_]+(\\.[a-z0-9_]+)*$")
	for key in keys:
		t.check(key != "" and rx.search(key) != null,"AD-259d art key '%s' is a shrine.* lowercase key" % key)
	var unique := {}
	for key in keys:
		unique[key] = true
	t.equal(unique.size(),keys.size(),"AD-259d art keys are unique")
	for path in ["res://world/run_flow.gd","res://ui/run_controller.gd"]:
		var source := FileAccess.get_file_as_string(path)
		for key in keys:
			if key != "":
				t.check(not source.contains(key),"AD-259d %s does not hardcode '%s'" % [path,key])
