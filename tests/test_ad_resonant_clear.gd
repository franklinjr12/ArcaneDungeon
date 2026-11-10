extends RefCounted
## AD-195: reward cards bias toward runes that complete a reaction with the current loadout.
const Reward = preload("res://world/reward_generator.gd")
const SEEDS := 2000

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
