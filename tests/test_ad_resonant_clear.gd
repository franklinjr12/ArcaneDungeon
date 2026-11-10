extends RefCounted
## AD-195: reward cards bias toward runes that complete a reaction with the current loadout.
const Reward = preload("res://world/reward_generator.gd")
const Flow = preload("res://world/run_flow.gd")
const RunLog = preload("res://game/core/run_log.gd")
const SEEDS := 2000
const SEED := 20261022

class FakeRun:
	var seed := 0
	var unlocked: Array = []
	var purchases: Array = []
	var artifacts: Array = []
	var formulas: Array = []

class BareRun:
	var seed := 7
	var unlocked: Array = []
	var purchases: Array = []
	var artifacts: Array = []

func _config() -> Dictionary:
	return JSON.parse_string(FileAccess.get_file_as_string("res://world/data/run_v2.json"))

func _water_run(config: Dictionary, s: int) -> FakeRun:
	var r := FakeRun.new()
	r.seed = s
	r.unlocked = config["initial_unlocked"].duplicate()
	r.formulas = [{"root":{"essence_id":"essence.water","manifestation_id":"form.projectile","modifier_ids":[],"params":{}}}]
	return r

func _cold_share(config: Dictionary) -> float:
	var rewards = Reward.new(config)
	var hits := 0
	for s in range(1,SEEDS+1):
		var cards: Array = rewards.choices(_water_run(config,s),"room_1")
		if not cards.is_empty() and cards[0].get("id","") == "essence.cold":
			hits += 1
	return float(hits)/SEEDS

func run(t) -> void:
	_bias(t)
	_clear_rule(t)
	_generator(t)
	_log(t)

func _bias(t) -> void:
	var config := _config()
	var all: Array = ["essence.fire","essence.water","essence.lightning","essence.cold","essence.force","form.beam"]
	var with_water: Array = Reward.reaction_completers(all,["essence.water"])
	t.check("essence.cold" in with_water,"AD-195 water+cold completes a reaction")
	t.check("essence.force" not in with_water,"AD-195 force needs frozen, not offered with water only")
	t.check("form.beam" not in with_water,"AD-195 only essences complete reactions")
	t.check("essence.force" in Reward.reaction_completers(all,["essence.water","essence.cold"]),"AD-195 force completes with water+cold")
	t.equal(float(config.get("reaction_bias_weight",0.0)),0.4,"AD-195 run_v2 bias weight is 0.4")
	var share := _cold_share(config)
	t.check(share >= 0.40 and share <= 0.49,"AD-195 biased Cold share in band: %f" % share)
	var plain := config.duplicate(true)
	plain.erase("reaction_bias_weight")
	var unbiased := _cold_share(plain)
	t.check(unbiased < 0.15,"AD-195 unbiased Cold share low: %f" % unbiased)
	var zero := config.duplicate(true)
	zero["reaction_bias_weight"] = 0.0
	var plain_rewards = Reward.new(plain)
	var zero_rewards = Reward.new(zero)
	var biased_rewards = Reward.new(config)
	for s in [1,2,3,17,99]:
		t.equal(plain_rewards.choices(_water_run(plain,s),"room_2"),zero_rewards.choices(_water_run(zero,s),"room_2"),"AD-195 absent key equals weight 0 seed %d" % s)
		var a: Array = biased_rewards.choices(_water_run(config,s),"room_2")
		t.equal(a,biased_rewards.choices(_water_run(config,s),"room_2"),"AD-195 deterministic seed %d" % s)
		var ids: Array = []
		for card in a:
			if card["kind"] == "rune":
				t.check(card["id"] not in ids,"AD-195 no duplicate ids seed %d" % s)
				ids.append(card["id"])
	var bare := BareRun.new()
	t.check(not biased_rewards.choices(bare,"room_1").is_empty(),"AD-195 run without formulas does not crash")

func _clear_flow(reason: String, count: int):
	var flow = Flow.new(SEED,Flow.CONFIG_V2)
	if flow.prelude:
		flow.finish_prelude(true)
	for i in count:
		flow.session.sim.trace.record("reaction",{"reason":reason,"tick":0})
	for i in 3000:
		if flow.state != "fighting":
			break
		for enemy in flow.session.enemies:
			if enemy.target.alive():
				enemy.target.receive_damage(100000,"fire",1,100)
		flow.step()
	return flow

func _clear_rule(t) -> void:
	t.check(Reward.combo_reaction_ids().size() > 0 and "chill_freeze" not in Reward.combo_reaction_ids(),"AD-195 combo ids exclude chill_freeze")
	var two = _clear_flow("wet_cold_freeze",2)
	t.equal(two.state,"cleared","AD-195 2-reaction room cleared")
	t.check(not two.resonant_clear,"AD-195 2 reactions not resonant")
	var three = _clear_flow("wet_cold_freeze",3)
	t.check(three.resonant_clear,"AD-195 3 reactions resonant")
	t.equal(three.run_log.resonant_clears,1,"AD-195 run log counts resonant clear")
	t.equal(three.summary()["reactions_triggered"],3,"AD-195 summary counts reactions")
	for key in ["reactions_triggered","elements_used","spells_crafted"]:
		t.check(three.summary().has(key),"AD-195 summary has "+key)
	var chill = _clear_flow("chill_freeze",3)
	t.check(not chill.resonant_clear,"AD-195 chill_freeze does not count")

func _generator(t) -> void:
	var config := _config()
	var rewards = Reward.new(config)
	var coins := int(config["resonant_clear"]["bonus_coins"])
	var order: Array = config["resonant_clear"]["rarity_order"]
	var stepped := 0
	for s in range(1,60):
		var base: Array = rewards.choices(_water_run(config,s),"room_1",false,false)
		var res: Array = rewards.choices(_water_run(config,s),"room_1",false,true)
		t.equal(base,rewards.choices(_water_run(config,s),"room_1"),"AD-195 non-resonant unchanged seed %d" % s)
		t.equal(res.size(),base.size(),"AD-195 same card count seed %d" % s)
		for i in base.size():
			if base[i]["kind"] == "rune":
				if res[i].has("bonus_coins"):
					t.equal(int(res[i]["bonus_coins"]),coins,"AD-195 rune bonus coins seed %d" % s)
				else:
					stepped += 1
					t.equal(order.find(res[i]["rarity"]),order.find(base[i]["rarity"])+1,"AD-195 one tier up seed %d" % s)
			elif base[i]["kind"] == "currency":
				t.equal(int(res[i]["amount"]),int(base[i]["amount"])+coins,"AD-195 currency grows seed %d" % s)
			else:
				t.equal(int(res[i].get("bonus_coins",0)),coins,"AD-195 artifact bonus seed %d" % s)
	t.check(stepped > 0,"AD-195 some cards step up")
	var rare := config.duplicate(true)
	for id in rare["rune_rarity"]:
		rare["rune_rarity"][id] = "rare"
	var rare_rewards = Reward.new(rare)
	for card in rare_rewards.choices(_water_run(rare,5),"room_1",false,true):
		if card["kind"] == "rune":
			t.equal(int(card.get("bonus_coins",0)),coins,"AD-195 max rarity gives coins")
	var off := config.duplicate(true)
	off.erase("resonant_clear")
	t.equal(Reward.new(off).choices(_water_run(off,3),"room_1",false,true),Reward.new(off).choices(_water_run(off,3),"room_1"),"AD-195 no block means feature off")
	var flow = Flow.new(SEED,Flow.CONFIG_V2)
	if flow.prelude:
		flow.finish_prelude(true)
	for i in 3000:
		if flow.state != "fighting":
			break
		for enemy in flow.session.enemies:
			if enemy.target.alive():
				enemy.target.receive_damage(100000,"fire",1,100)
		flow.step()
	flow.reward_options = [{"kind":"currency","amount":10,"bonus_coins":25}]
	var before: int = flow.run.currency
	var out: Dictionary = flow.choose_reward(0)
	t.equal(flow.run.currency,before+35,"AD-195 choose_reward adds bonus coins")
	t.equal(int(out.get("bonus_coins",0)),25,"AD-195 outcome reports bonus")

func _log(t) -> void:
	var log := RunLog.new()
	log.begin(1)
	log.enter_room(0,"r1","combat",0)
	log.add_reaction("wet_cold_freeze")
	log.add_elements(["essence.water","essence.neutral","essence.fire","essence.water"])
	log.mark_resonant()
	log.add_spell("f1",0,0,{"a":1})
	var d := log.to_dict()
	t.equal(d["reactions_triggered"],1,"AD-195 log reactions")
	t.equal(d["elements_used"],["essence.fire","essence.water"],"AD-195 log elements sorted without neutral")
	t.equal(d["resonant_clears"],1,"AD-195 log resonant clears")
	t.equal(d["rooms"][0]["reactions"],1,"AD-195 room reactions")
	t.equal(d["rooms"][0]["resonant"],true,"AD-195 room resonant")
	t.equal(d["spells_crafted"].size(),1,"AD-195 spells crafted grows")
	var back := RunLog.new()
	back.restore(log.snapshot(),1)
	t.equal(back.reactions_triggered,1,"AD-195 restore reactions")
	t.equal(back.elements_used,["essence.fire","essence.water"],"AD-195 restore elements")
	t.equal(back.resonant_clears,1,"AD-195 restore resonant")
	var old := RunLog.new()
	old.restore({"rooms":[]},1)
	t.equal(old.reactions_triggered,0,"AD-195 old snapshot reactions 0")
	t.equal(old.elements_used,[],"AD-195 old snapshot elements empty")
