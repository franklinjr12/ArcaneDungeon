extends RefCounted
## AD-011a: built-in essence.neutral is hidden from collection, rewards, shop and player formulas.
const Registry = preload("res://magic/data/rune_registry.gd")
const Validator = preload("res://magic/compile/spell_validator.gd")
const Flow = preload("res://world/run_flow.gd")
const RunState = preload("res://world/run_state.gd")
const Reward = preload("res://world/reward_generator.gd")
const Merchant = preload("res://world/merchant.gd")
const Compiler = preload("res://magic/compile/spell_compiler.gd")
const Runner = preload("res://magic/runtime/spell_runner.gd")
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

	# (d) basic bolt compiles, is cheaper than every starter preset, casts and deals neutral damage
	var loaded: Dictionary = Compiler.load_builtin_definition()
	t.check(loaded["ok"],"AD-011d basic bolt definition loads")
	var definition: Dictionary = loaded["definition"]
	var compiler = Compiler.new(registry)
	var built: Dictionary = compiler.compile_builtin(definition)
	t.check(built["ok"],"AD-011d basic bolt compiles")
	var plan: Dictionary = built["compiled_spell"].snapshot()
	t.equal(plan["mana_cost"],3,"AD-011d basic bolt mana cost 3")
	t.equal(plan["cooldown_ticks"],int(definition["cooldown_ticks"]),"AD-011d basic bolt cooldown from data")
	t.equal(plan["root"]["essence"]["id"],"essence.neutral","AD-011d basic bolt root essence neutral")
	var tuning: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://combat/combat_tuning_v1.json"))
	var preset_ids := {}
	for loadout in tuning["starter_loadouts"]:
		for id in loadout:
			preset_ids[id] = true
	for id in flow.config["initial_formulas"]:
		preset_ids[id] = true
	for id in preset_ids:
		var preset: Dictionary = compiler.compile(flow.formulas[id],registry.get_ids())
		t.check(preset["ok"] and plan["mana_cost"] < preset["compiled_spell"].snapshot()["mana_cost"],"AD-011d cheaper mana than "+id)
		t.check(preset["ok"] and plan["cooldown_ticks"] <= preset["compiled_spell"].snapshot()["cooldown_ticks"],"AD-011d cooldown not longer than "+id)
	var bad: Dictionary = definition.duplicate(true)
	bad["extra"] = 1
	t.contains_issue(compiler.compile_builtin(bad)["issues"],"BUILTIN_DEFINITION_INVALID","AD-011d malformed definition rejected")
	var player_def: Dictionary = definition.duplicate(true)
	player_def["formula"] = flow.formulas[flow.config["initial_formulas"][0]].duplicate(true)
	t.contains_issue(compiler.compile_builtin(player_def)["issues"],"BUILTIN_DEFINITION_INVALID","AD-011d player formula rejected from builtin path")
	var runner = Runner.new(20261029)
	var dummy = runner.add_target(Vector2(300,340))
	t.check(runner.equip_builtin(0,definition)["ok"],"AD-011d basic bolt equips")
	t.equal(runner.loadout.check_slot(0),"READY","AD-011d builtin slot recompiles ready")
	var start_hp: float = dummy.health.current
	var cast: Dictionary = runner.try_cast(0,runner.actor.position,Vector2.RIGHT)
	t.check(cast["accepted"],"AD-011d basic bolt casts")
	for i in 120:
		runner.step()
	t.check(dummy.health.current < start_hp,"AD-011d basic bolt damages target")
	t.equal(runner.settings["channels"]["essence.neutral"]["channel"],"neutral","AD-011d neutral damage channel configured")
	t.check(runner.recent_damage.size() > 0 and float(runner.recent_damage[0]["damage"]) > 0.0,"AD-011d neutral damage recorded")
	t.check(runner.equip(0,flow.formulas[flow.config["initial_formulas"][0]])["ok"],"AD-011d plain equip replaces builtin")
	t.check(runner.loadout.slots[0]["builtin_definition"].is_empty(),"AD-011d plain equip clears builtin definition")
