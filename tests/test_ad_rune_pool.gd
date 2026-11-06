extends RefCounted
## AD-135: all 20 player runes are reachable through reward and merchant pools; deterministic, no duplicates.
const Reward = preload("res://world/reward_generator.gd")
const Merchant = preload("res://world/merchant.gd")
const Registry = preload("res://magic/data/rune_registry.gd")
const Compiler = preload("res://magic/compile/spell_compiler.gd")
const SEEDS := 1000
const ESSENCES := ["essence.fire","essence.water","essence.lightning","essence.cold","essence.force"]
const FORMS := ["form.projectile","form.burst","form.orb","form.beam","form.field"]
const TRIGGERS := ["trigger.on_hit","trigger.on_kill","trigger.on_expire","trigger.timer"]
const NEW_RUNES := ["essence.cold","essence.force","form.beam","form.field","mod.chain","mod.expand","mod.rapid","trigger.on_kill","trigger.on_expire","trigger.timer"]

class FakeRun:
	var seed := 0
	var unlocked: Array = []
	var purchases: Array = []
	var artifacts: Array = []

func _config() -> Dictionary:
	return JSON.parse_string(FileAccess.get_file_as_string("res://world/data/run_v2.json"))

func run(t) -> void:
	_balance_sweep(t)
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

func _formula(essence: String, form: String, mods: Array, trigger: String = "", payload_essence: String = "") -> Dictionary:
	var formula := {"schema_version":2,"formula_id":"sweep","display_name":"sweep",
		"root":{"essence_id":essence,"manifestation_id":form,"modifier_ids":mods,"params":{}}}
	if trigger != "":
		formula["on_hit"] = {"trigger_id":trigger,"payload":{"essence_id":payload_essence,"manifestation_id":"form.burst","modifier_ids":[],"params":{}}}
	return formula

## Sandbox-style sweep of every legal combo against the PROPOSED balance_targets (magic_balance_v1.json).
func _balance_sweep(t) -> void:
	var registry = Registry.new()
	registry.load_seed()
	var targets: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://magic/data/magic_balance_v1.json"))["balance_targets"]
	var cap := int(JSON.parse_string(FileAccess.get_file_as_string("res://magic/data/spell_limits_v1.json"))["max_complexity"])
	var max_mana := float(JSON.parse_string(FileAccess.get_file_as_string("res://magic/data/magic_balance_v1.json"))["combat"]["player_max_mana"])
	var compiler = Compiler.new(registry,cap)
	var unlocked: Array = registry.get_ids()
	var mod_sets: Array = [[]]
	var mods: Array = registry.list_by_category("modifier").map(func(r): return r["id"])
	for i in mods.size():
		mod_sets.append([mods[i]])
		for j in range(i + 1,mods.size()):
			mod_sets.append([mods[i],mods[j]])
	var count := 0
	var min_mana := 100000
	var max_seen_mana := 0
	var min_cd := 100000
	var max_cd := 0
	var max_cx := 0
	var legal_runes: Dictionary = {}
	var bad := 0
	for e in ESSENCES:
		for f in FORMS:
			for ms in mod_sets:
				var variants: Array = [["",""]]
				for tr_id in TRIGGERS:
					for pe in ESSENCES:
						variants.append([tr_id,pe])
				var base_mana := -1
				for v in variants:
					var out: Dictionary = compiler.compile(_formula(e,f,ms,v[0],v[1]),unlocked)
					if not out["ok"]:
						continue
					var snap: Dictionary = out["compiled_spell"].snapshot()
					var mana := int(snap["mana_cost"])
					var cd := int(snap["cooldown_ticks"])
					var cx := int(snap["complexity"])
					count += 1
					min_mana = mini(min_mana,mana)
					max_seen_mana = maxi(max_seen_mana,mana)
					min_cd = mini(min_cd,cd)
					max_cd = maxi(max_cd,cd)
					max_cx = maxi(max_cx,cx)
					for id in [e,f,v[0]] + ms:
						legal_runes[id] = true
					if v[0] == "":
						base_mana = mana
					var root_mana := mana
					if v[0] != "":
						root_mana = base_mana
						if mana - base_mana > int(targets["trigger_mana_premium_max"]):
							bad += 1
					if root_mana > int(targets["max_root_mana"]) or mana > int(targets["max_total_mana"]) or cd > int(targets["max_cooldown_ticks"]) or int(max_mana / mana) < int(targets["min_casts_from_full_mana"]) or cx > cap:
						bad += 1
						print("AD-135 target miss: %s" % JSON.stringify(_formula(e,f,ms,v[0],v[1])["root"]) + " trig=%s mana=%d cd=%d cx=%d" % [v[0],mana,cd,cx])
	t.equal(bad,0,"AD-135 every legal combo meets balance_targets")
	t.check(count > 0,"AD-135 sweep found legal combos")
	for id in NEW_RUNES:
		t.check(legal_runes.has(id),"AD-135 a legal combo exists for "+id)
	# Core combo: form + essence + any-form modifier + trigger with Burst payload must fit the cap.
	var headroom := 1000
	for e in ESSENCES:
		for f in FORMS:
			for m in ["mod.chain","mod.expand","mod.rapid"]:
				for tr_id in TRIGGERS:
					var out: Dictionary = compiler.compile(_formula(e,f,[m],tr_id,"essence.fire"),unlocked)
					if out["ok"]:
						headroom = mini(headroom,cap - int(out["compiled_spell"].snapshot()["complexity"]))
	t.check(headroom >= int(targets["min_complexity_headroom_for_core_combo"]),"AD-135 core combos fit complexity cap (min headroom %d)" % headroom)
	print("AD-135 sweep: %d legal formulas, mana %d..%d, cooldown %d..%d, max complexity %d/%d, min core headroom %d" % [count,min_mana,max_seen_mana,min_cd,max_cd,max_cx,cap,headroom])
