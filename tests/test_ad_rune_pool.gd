extends RefCounted
## AD-135: all 20 player runes are reachable through reward and merchant pools; deterministic, no duplicates.
const Reward = preload("res://world/reward_generator.gd")
const Merchant = preload("res://world/merchant.gd")
const Registry = preload("res://magic/data/rune_registry.gd")
const SEEDS := 1000

class FakeRun:
	var seed := 0
	var unlocked: Array = []
	var purchases: Array = []

func _config() -> Dictionary:
	return JSON.parse_string(FileAccess.get_file_as_string("res://world/data/run_v2.json"))

func run(t) -> void:
	var config := _config()
	var registry = Registry.new()
	t.check(registry.load_seed()["ok"],"AD-135 registry loads")
	var player_ids: Array = registry.get_ids()
	var builtin_ids: Array = registry.get_builtin_ids()
	t.equal(player_ids.size(),20,"AD-135 registry has 20 player runes")
	var pool: Array = config["reward_pool"]
	var sorted_pool := pool.duplicate()
	sorted_pool.sort()
	t.equal(sorted_pool,player_ids,"AD-135 data pool is exactly the 20 non-builtin runes")
	var weights: Dictionary = config["rarity_weights"]
	for id in player_ids:
		t.check(weights.has(str(config["rune_rarity"].get(id,""))),"AD-135 rarity weight for "+id)
		for key in ["rune."+id+".name","rune."+id+".desc"]:
			t.check(TranslationServer.translate(key) != key,"AD-135 translated "+key)
	var rewards = Reward.new(config,builtin_ids)
	var offered: Dictionary = {}
	var stocked: Dictionary = {}
	var merchant = Merchant.new(config)
	for s in SEEDS:
		var run_state := FakeRun.new()
		run_state.seed = s
		run_state.unlocked = ["essence.neutral"] if s % 2 == 0 else []
		var picks: Array = rewards.choices(run_state,"room_x")
		var seen: Dictionary = {}
		for card in picks:
			if card["kind"] != "rune":
				continue
			var id: String = card["id"]
			if not (id in player_ids) or seen.has(id) or id == "essence.neutral":
				t.check(false,"AD-135 bad offer %s seed %d" % [id,s])
			seen[id] = true
			offered[id] = true
		if picks != rewards.choices(run_state,"room_x"):
			t.check(false,"AD-135 reward not deterministic seed %d" % s)
		var stock: Array = merchant.build(run_state,player_ids + builtin_ids)
		var runes: Array = stock.filter(func(i): return i["kind"] == "rune")
		if runes.size() != 1 or runes[0]["rune_id"] not in player_ids or runes[0]["rune_id"] in run_state.unlocked:
			t.check(false,"AD-135 bad merchant stock seed %d" % s)
		else:
			stocked[runes[0]["rune_id"]] = true
		if stock != merchant.build(run_state,player_ids + builtin_ids):
			t.check(false,"AD-135 merchant not deterministic seed %d" % s)
	t.equal(offered.size(),20,"AD-135 rewards offer every rune over %d seeds" % SEEDS)
	t.equal(stocked.size(),20,"AD-135 merchant stocks every rune over %d seeds" % SEEDS)
	var all_unlocked := FakeRun.new()
	all_unlocked.unlocked = player_ids.duplicate()
	t.equal(merchant.build(all_unlocked,player_ids).filter(func(i): return i["kind"] == "rune").size(),0,"AD-135 nothing stocked when all unlocked")
