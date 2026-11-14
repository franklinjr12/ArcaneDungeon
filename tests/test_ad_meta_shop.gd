extends SceneTree
## AD-234: Scriptorium upgrades: config, purchase/respec logic, persistence, bonuses.
## Discovered by run_tests.gd (run(t)) and also runnable directly: --script res://tests/test_ad_meta_shop.gd
const TestContext = preload("res://tests/test_context.gd")
const Service = preload("res://game/core/save_service.gd")
const Meta = preload("res://world/meta_progress.gd")
const DIR := "user://ad234_test/"

func _clean() -> void:
	DirAccess.make_dir_recursive_absolute(DIR)
	for f in DirAccess.get_files_at(DIR):
		DirAccess.remove_absolute(DIR + f)

func _initialize() -> void:
	var t := TestContext.new()
	run(t)
	print("TEST SUMMARY: %d passed / %d failed" % [t.passed, t.failed])
	for failure in t.failures:
		printerr("FAILED: ", failure)
	quit(1 if t.failed > 0 else 0)

func run(t) -> void:
	_config(t)
	_purchase(t)
	_cannot_buy(t)
	_respec(t)
	_bonuses(t)
	_legacy_and_validation(t)

func _service(ink: int):
	_clean()
	var svc = Service.new()
	svc.set_base_dir(DIR)
	svc.record_run({"outcome": "lost", "seed": 1, "ink_earned": ink})
	return svc

func _reload():
	var svc = Service.new()
	svc.set_base_dir(DIR)
	svc.load_profile()
	return svc

func _done(svc) -> void:
	svc.free()
	_clean()
	DirAccess.remove_absolute(DIR)

func _config(t) -> void:
	t.equal(Meta.upgrade_ids(), ["max_hp", "max_mana", "mana_regen"], "AD-234 upgrade ids")
	t.equal(float(Meta.upgrade_def("max_hp")["per_tier"]), 6.0, "AD-234 max_hp per tier")
	t.equal(float(Meta.upgrade_def("max_mana")["per_tier"]), 6.0, "AD-234 max_mana per tier")
	t.equal(float(Meta.upgrade_def("mana_regen")["per_tier"]), 0.04, "AD-234 mana_regen per tier")
	for id in Meta.upgrade_ids():
		t.equal(Meta.max_tier(id), 5, "AD-234 5 tiers: %s" % id)
		var costs: Array = []
		for c in Meta.upgrade_def(id)["costs"]:
			costs.append(int(c))
		t.equal(costs, [15, 25, 40, 60, 85], "AD-234 costs: %s" % id)

func _purchase(t) -> void:
	var svc = _service(100)
	t.check(svc.buy_upgrade("max_hp"), "AD-234 buy tier 1")
	t.equal(svc.ink(), 85, "AD-234 ink deducted by tier-1 cost")
	t.check(svc.buy_upgrade("max_hp"), "AD-234 buy tier 2")
	t.equal(svc.ink(), 60, "AD-234 ink deducted by tier-2 cost")
	var svc2 = _reload()
	t.equal(svc2.ink(), 60, "AD-234 ink persists")
	t.equal(Meta.tier(svc2.meta(), "max_hp"), 2, "AD-234 tier persists")
	t.equal(Meta.tier(svc2.meta(), "max_mana"), 0, "AD-234 other tiers untouched")
	svc2.free()
	_done(svc)

func _cannot_buy(t) -> void:
	var svc = _service(14)
	t.check(not svc.buy_upgrade("max_mana"), "AD-234 cannot buy without ink")
	t.equal(svc.ink(), 14, "AD-234 ink unchanged on failed buy")
	t.equal(Meta.tier(svc.meta(), "max_mana"), 0, "AD-234 tier unchanged on failed buy")
	t.check(not svc.buy_upgrade("nope"), "AD-234 unknown id not buyable")
	_done(svc)
	svc = _service(1000)
	for i in 5:
		t.check(svc.buy_upgrade("mana_regen"), "AD-234 buy regen tier %d" % (i + 1))
	var ink_before: int = svc.ink()
	t.equal(Meta.next_cost(svc.meta(), "mana_regen"), -1, "AD-234 maxed next_cost -1")
	t.check(not svc.buy_upgrade("mana_regen"), "AD-234 cannot buy past tier 5")
	t.equal(svc.ink(), ink_before, "AD-234 ink unchanged past max")
	_done(svc)

func _respec(t) -> void:
	var svc = _service(200)
	svc.buy_upgrade("max_hp")
	svc.buy_upgrade("max_hp")
	svc.buy_upgrade("mana_regen")
	t.equal(svc.ink(), 200 - 15 - 25 - 15, "AD-234 ink after buys")
	t.equal(svc.respec_upgrades(), 55, "AD-234 respec returns spent ink")
	t.equal(svc.ink(), 200, "AD-234 respec refunds exactly")
	t.equal(svc.meta()["upgrades"], {}, "AD-234 respec clears tiers")
	var svc2 = _reload()
	t.equal(svc2.ink(), 200, "AD-234 respec persists ink")
	t.equal(svc2.meta()["upgrades"], {}, "AD-234 respec persists tiers")
	t.equal(svc2.respec_upgrades(), 0, "AD-234 empty respec refunds 0")
	svc2.free()
	_done(svc)

func _bonuses(t) -> void:
	var b := Meta.bonuses(Meta.empty_meta())
	t.equal([b["max_hp"], b["max_mana"], b["mana_regen_mult"]], [0.0, 0.0, 1.0], "AD-234 no upgrades: no bonus")
	var m := Meta.empty_meta()
	m["ink"] = 1000
	for i in 3:
		Meta.buy(m, "max_hp")
	for i in 5:
		Meta.buy(m, "max_mana")
	for i in 2:
		Meta.buy(m, "mana_regen")
	b = Meta.bonuses(m)
	t.equal(b["max_hp"], 18.0, "AD-234 max_hp bonus")
	t.equal(b["max_mana"], 30.0, "AD-234 max_mana bonus")
	t.check(absf(b["mana_regen_mult"] - 1.08) < 0.0001, "AD-234 regen multiplier")

func _legacy_and_validation(t) -> void:
	var legacy := Meta.empty_meta()
	legacy.erase("upgrades")
	t.check(Meta.valid_meta(legacy) and legacy["upgrades"] == {}, "AD-234 legacy meta without upgrades valid")
	var fl := Meta.empty_meta()
	fl["upgrades"] = {"max_hp": 2.0}
	t.check(Meta.valid_meta(fl) and typeof(fl["upgrades"]["max_hp"]) == TYPE_INT, "AD-234 float tier normalised")
	for bad in [[], {"bogus": 1}, {"max_hp": -1}, {"max_hp": 6}, {"max_hp": "2"}, {"max_hp": 1.5}]:
		var m := Meta.empty_meta()
		m["upgrades"] = bad
		t.check(not Meta.valid_meta(m), "AD-234 invalid upgrades rejected: %s" % str(bad))
