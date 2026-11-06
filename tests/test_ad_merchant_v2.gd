extends RefCounted
## AD-144 step 1: merchant v2 stock, paid reroll, and the max-mana / dash-charge upgrades.
const State = preload("res://world/run_state.gd")
const Merchant = preload("res://world/merchant.gd")
const Flow = preload("res://world/run_flow.gd")
const Session = preload("res://combat/combat_session.gd")
const IDS := ["essence.fire","essence.water","essence.lightning","essence.cold","essence.force","form.projectile",
	"form.burst","form.orb","form.beam","form.field","mod.homing","mod.split","mod.pierce","mod.chain"]
const SEED := 20261022

func run(t) -> void:
	_stock(t)
	_reroll(t)
	_upgrades(t)
	_dash_charges(t)
	_persistence(t)

func _tuning() -> Dictionary:
	return JSON.parse_string(FileAccess.get_file_as_string(Flow.CONFIG_V2))

func _fresh_run(run_seed: int = SEED):
	var cfg: Dictionary = _tuning()
	var run_state = State.new()
	var formulas := {}
	for id in cfg["initial_formulas"]:
		formulas[id] = {"id":id}
	run_state.initialize(run_seed,cfg,formulas)
	return run_state

func _stock(t) -> void:
	var tuning: Dictionary = _tuning()
	var cfg: Dictionary = tuning["merchant"]
	var counts := {}
	for run_seed in range(SEED,SEED+24):
		var state = _fresh_run(run_seed)
		var stock: Array = Merchant.new(tuning).build(state,IDS)
		t.equal(stock,Merchant.new(tuning).build(state,IDS),"AD-144 same seed gives identical stock")
		var runes: Array = stock.filter(func(item): return item["kind"] == "rune")
		counts[runes.size()] = true
		t.check(runes.size() >= int(cfg["rune_count_min"]) and runes.size() <= int(cfg["rune_count_max"]),"AD-144 rune count within data bounds")
		t.equal(stock.size(),runes.size()+4,"AD-144 stock is runes + 3 upgrades + artifact")
		var tail: Array = stock.slice(runes.size()).map(func(item): return item["id"])
		t.equal(tail.slice(0,3),["upgrade.hp","upgrade.mana","upgrade.dash"],"AD-144 upgrade order")
		t.equal(stock.back()["kind"],"artifact","AD-144 artifact is last")
		for i in runes.size():
			t.equal(stock[i]["kind"],"rune","AD-144 runes lead the stock")
			t.equal(int(stock[i]["price"]),int(cfg["rune_price"]),"AD-144 rune price from data")
	t.check(counts.has(1) and counts.has(2),"AD-144 both 1 and 2 runes appear across seeds")
	var shop = Merchant.new(tuning)
	var items: Array = shop.build(_fresh_run(),IDS)
	var by_id := {}
	for item in items:
		by_id[item["id"]] = item
	t.equal(int(by_id["upgrade.hp"]["price"]),int(cfg["max_hp_upgrade_price"]),"AD-144 hp price from data")
	t.equal(int(by_id["upgrade.mana"]["price"]),int(cfg["max_mana_upgrade_price"]),"AD-144 mana price from data")
	t.equal(int(by_id["upgrade.dash"]["price"]),int(cfg["dash_charge_upgrade_price"]),"AD-144 dash price from data")
	t.equal(by_id["upgrade.mana"]["stat"],"max_mana","AD-144 mana stat")
	t.equal(by_id["upgrade.dash"]["stat"],"dash_charge","AD-144 dash stat")

func _reroll(t) -> void:
	var tuning: Dictionary = _tuning()
	var price := int(tuning["merchant"]["reroll_price"])
	var state = _fresh_run()
	var shop = Merchant.new(tuning)
	var before: Array = shop.build(state,IDS)
	state.currency = price-1
	var poor: Dictionary = shop.reroll(state)
	t.check(not poor["ok"] and poor["reason"] == "INSUFFICIENT_CURRENCY" and state.currency == price-1,"AD-144 unaffordable reroll spends nothing")
	t.check(shop.reroll_available(state) and shop.stock == before,"AD-144 failed reroll leaves stock and marker alone")
	state.currency = price+10
	var done: Dictionary = shop.reroll(state)
	t.check(done["ok"] and done["kind"] == "reroll","AD-144 reroll succeeds")
	t.equal(state.currency,10,"AD-144 reroll costs exactly reroll_price")
	t.check(not shop.reroll_available(state),"AD-144 reroll marker recorded")
	var again: Dictionary = shop.reroll(state)
	t.check(not again["ok"] and again["reason"] == "REROLL_USED" and state.currency == 10,"AD-144 second reroll refused without spending")
	t.equal(done["stock"],shop.stock,"AD-144 reroll returns the new stock")
	var rebuilt: Array = Merchant.new(tuning).build(state,IDS)
	t.equal(rebuilt,shop.stock,"AD-144 rebuild after marker reproduces rerolled stock")
	var other_state = _fresh_run()
	other_state.currency = price
	var other = Merchant.new(tuning)
	other.build(other_state,IDS)
	t.equal(other.reroll(other_state)["stock"],shop.stock,"AD-144 reroll deterministic for the same seed")
	var changed := false
	for run_seed in range(SEED,SEED+12):
		var s = _fresh_run(run_seed)
		s.currency = price
		var m = Merchant.new(tuning)
		var first: Array = m.build(s,IDS)
		var second: Array = m.reroll(s)["stock"]
		changed = changed or first != second
	t.check(changed,"AD-144 reroll changes the offers for some seeds")

func _upgrades(t) -> void:
	var tuning: Dictionary = _tuning()
	var cfg: Dictionary = tuning["merchant"]
	var state = _fresh_run()
	state.currency = 1000
	var shop = Merchant.new(tuning)
	var stock: Array = shop.build(state,IDS)
	var idx := {}
	for i in stock.size():
		idx[stock[i]["id"]] = i
	var hp_before: float = state.max_hp
	t.check(shop.purchase(idx["upgrade.hp"],state)["ok"],"AD-144 hp upgrade bought")
	t.equal(state.max_hp,hp_before+float(cfg["max_hp_upgrade_amount"]),"AD-144 hp upgrade raises max_hp")
	var mana_before: float = state.mana
	t.check(shop.purchase(idx["upgrade.mana"],state)["ok"],"AD-144 mana upgrade bought")
	t.equal(state.max_mana_bonus,float(cfg["max_mana_upgrade_amount"]),"AD-144 mana upgrade raises max_mana_bonus")
	t.equal(state.mana,mana_before+float(cfg["max_mana_upgrade_amount"]),"AD-144 mana upgrade raises mana")
	t.check(shop.purchase(idx["upgrade.dash"],state)["ok"],"AD-144 dash upgrade bought")
	t.equal(state.dash_charges_bonus,int(cfg["dash_charge_upgrade_amount"]),"AD-144 dash upgrade raises dash_charges_bonus")
	t.equal(shop.purchase(idx["upgrade.mana"],state)["reason"],"ALREADY_BOUGHT","AD-144 upgrades are once per run")
	var csv := FileAccess.get_file_as_string("res://i18n/strings_en.csv")
	for key in ["run.shop.mana_label","run.shop.dash_label","run.shop.max_mana","run.shop.dash_charge","run.shop.reroll","run.shop.reroll_used"]:
		t.check(csv.contains(key+","),"AD-144 i18n key "+key)

func _dash_charges(t) -> void:
	var recovery := 0
	for bonus in [1,0]:
		var session = Session.new(144)
		var player = session.player
		player.set_dash_bonus(bonus)
		t.check(session.issue({"dash":true})["accepted"] and player.dashes == 1,"AD-144 first dash accepted")
		t.check(player.dash_cooldown > 0,"AD-144 first dash starts the cooldown")
		for i in 200:
			if player.dash_left == 0 and player.recovery_left == 0:
				break
			session.step()
		t.check(player.dash_cooldown > 0,"AD-144 cooldown still running after dash recovery")
		session.issue({"dash":true})
		if bonus == 1:
			t.equal(player.dashes,2,"AD-144 bonus charge allows a second dash during cooldown")
			t.equal(player.bonus_dashes_left,0,"AD-144 bonus charge consumed")
			for i in 200:
				if player.dash_left == 0 and player.recovery_left == 0:
					break
				session.step()
			session.issue({"dash":true})
			t.equal(player.dashes,2,"AD-144 third dash refused while cooldown runs")
			for i in 600:
				if player.dash_cooldown == 0:
					break
				session.step()
			t.equal(player.bonus_dashes_left,1,"AD-144 bonus charge refills when the cooldown ends")
		else:
			t.equal(player.dashes,1,"AD-144 no bonus: second dash refused during cooldown")

func _persistence(t) -> void:
	var flow = Flow.new(SEED,Flow.CONFIG_V2)
	var registry = flow.session.sim.registry
	var max_rooms: int = flow.rooms.size()
	var state = flow.run
	state.max_mana_bonus = 20.0
	state.dash_charges_bonus = 2
	state.mana = state.mana+20.0
	var snap: Dictionary = state.snapshot()
	t.check(snap["max_mana_bonus"] == 20.0 and snap["dash_charges_bonus"] == 2,"AD-144 snapshot carries both bonuses")
	var restored = State.new()
	var outcome: Dictionary = restored.restore(JSON.parse_string(JSON.stringify(snap)),registry,max_rooms)
	t.check(outcome["ok"],"AD-144 snapshot with bonuses restores: "+str(outcome))
	t.check(restored.max_mana_bonus == 20.0 and restored.dash_charges_bonus == 2 and restored.mana == state.mana,"AD-144 bonuses round-trip")
	var old: Dictionary = snap.duplicate(true)
	old.erase("max_mana_bonus")
	old.erase("dash_charges_bonus")
	old["mana"] = minf(float(old["mana"]),120.0)
	var legacy = State.new()
	t.check(legacy.restore(old,registry,max_rooms)["ok"] and legacy.max_mana_bonus == 0.0 and legacy.dash_charges_bonus == 0,"AD-144 snapshot without bonus keys still restores")
	var bad: Dictionary = snap.duplicate(true)
	bad["dash_charges_bonus"] = 1.5
	t.equal(State.new().restore(bad,registry,max_rooms)["reason"],"RUN_UPGRADES_INVALID","AD-144 fractional dash bonus rejected")
	bad = snap.duplicate(true)
	bad["max_mana_bonus"] = -1
	t.equal(State.new().restore(bad,registry,max_rooms)["reason"],"RUN_UPGRADES_INVALID","AD-144 negative mana bonus rejected")
