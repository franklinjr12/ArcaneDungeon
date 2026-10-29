extends RefCounted
## AD-011a: built-in essence.neutral is hidden from collection, rewards, shop and player formulas.
const Registry = preload("res://magic/data/rune_registry.gd")
const Validator = preload("res://magic/compile/spell_validator.gd")
const Flow = preload("res://world/run_flow.gd")
const RunState = preload("res://world/run_state.gd")
const Reward = preload("res://world/reward_generator.gd")
const Merchant = preload("res://world/merchant.gd")
const COLLECTIBLE := ["essence.fire","essence.lightning","essence.water","form.burst","form.orb","form.projectile","mod.homing","mod.pierce","mod.split","trigger.on_hit"]

func run(t) -> void:
	var registry = Registry.new()
	t.check(registry.load_seed()["ok"],"AD-011 seed registry loads")
	t.check(registry.is_builtin("essence.neutral"),"AD-011a registry flags essence.neutral builtin")
	var neutral = registry.get_rune("essence.neutral")
	t.check(neutral != null and neutral.category() == "essence","AD-011a neutral resolves as essence")
	t.equal(registry.get_builtin_ids(),["essence.neutral"],"AD-011a only builtin is neutral")
	t.check("essence.neutral" not in registry.get_ids(),"AD-011a neutral not collectible")
	for entry in registry.list_by_category("essence"):
		t.check(entry["id"] != "essence.neutral","AD-011a neutral hidden from palette list")
	t.equal(registry.get_ids(),COLLECTIBLE,"AD-011e ten collectible runes unchanged")
	var file := FileAccess.open(Registry.SEED_PATH,FileAccess.READ)
	var data: Dictionary = JSON.parse_string(file.get_as_text())
	for entry in data["runes"]:
		if entry["id"] in COLLECTIBLE:
			var snap: Dictionary = registry.get_rune(entry["id"]).snapshot()
			t.check(not registry.is_builtin(entry["id"]),"AD-011e not builtin: "+entry["id"])
			for key in ["mana_cost","cooldown_ticks","complexity_weight"]:
				t.equal(snap[key],int(entry[key]),"AD-011e %s %s" % [entry["id"],key])
	var flow = Flow.new(20261022)
	var builtin_ids: Array = registry.get_builtin_ids()
	var rewards = Reward.new(flow.config,builtin_ids)
	var merchant = Merchant.new(flow.config)
	var leaked := false
	for seed in range(1,1001):
		var run_state = RunState.new()
		run_state.initialize(seed,flow.config,flow.formulas)
		for option in rewards.choices(run_state,"room_1"):
			if option.get("id","") == "essence.neutral":
				leaked = true
		for item in merchant.build(run_state,registry.get_all_ids(),builtin_ids):
			if item.get("rune_id","") == "essence.neutral":
				leaked = true
	t.check(not leaked,"AD-011b neutral never rewarded or sold over 1000 seeds")
	var validator = Validator.new(registry)
	var formula: Dictionary = flow.formulas[flow.config["initial_formulas"][0]].duplicate(true)
	formula["root"]["essence_id"] = "essence.neutral"
	var all_ids: Array = registry.get_all_ids()
	var result: Dictionary = validator.validate(formula,all_ids)
	t.check(not result["ok"],"AD-011c player formula with neutral rejected")
	t.contains_issue(result["issues"],"RUNE_BUILTIN_FORBIDDEN","AD-011c stable builtin issue code")
