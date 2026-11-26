extends SceneTree
## AD-253 step 1: Drowned Archivist shield readability: shielded tint pulse, tethers to live wisps, shield-break flash.
const TestContext = preload("res://tests/test_context.gd")
const FX_FILE := "res://world/data/boss_fx.json"
const CANVAS := "res://ui/combat_canvas.gd"
const TPS := 60
const FX_KEYS := ["tint_color", "tint_alpha_min", "tint_alpha_max", "pulse_period_s", "tether_color", "tether_width", "tether_alpha", "break_flash_s", "max_flashes_per_s"]

## Discovered by run_tests.gd (run(t)) and also runnable directly: --script res://tests/test_ad_boss2_shield_fx.gd
func _initialize() -> void:
	var t := TestContext.new()
	run(t)
	print("TEST SUMMARY: %d passed / %d failed" % [t.passed, t.failed])
	for failure in t.failures:
		printerr("FAILED: ", failure)
	if t.failed == 0:
		print("PASS")
	quit(1 if t.failed > 0 else 0)

func run(t) -> void:
	test_ad_253_a_data_file(t)
	test_ad_253_a_shielded_state(t)
	test_ad_253_a_tint_pulses(t)
	test_ad_253_a_tethers_follow_live_wisps(t)
	test_ad_253_a_break_clears_and_flashes(t)
	test_ad_253_a_flash_rate_limit(t)
	test_ad_253_a_never_shielded(t)

func _fx() -> Dictionary:
	if not FileAccess.file_exists(FX_FILE):
		return {}
	var doc = JSON.parse_string(FileAccess.get_file_as_string(FX_FILE))
	if doc is Dictionary and doc.get("wisp_shield", null) is Dictionary:
		return doc["wisp_shield"]
	return {}

func _canvas():
	return load(CANVAS)

## Calls the static API; returns {} when it (or the data) is missing so the caller's checks fail on assertions.
func _step(memo: Dictionary, shielded: bool, wisps: Array, tick: int, fx: Dictionary) -> Dictionary:
	var c = _canvas()
	if c == null or not c.has_method("shield_fx_step") or fx.is_empty():
		return {}
	var r = c.shield_fx_step(memo, shielded, wisps, tick, fx)
	return r if r is Dictionary else {}

func _wisps(n: int) -> Array:
	var out := []
	for i in n:
		out.append(Vector2(100.0 + 40.0 * i, 200.0))
	return out

func _tint(r: Dictionary) -> float:
	return float(r.get("tint_alpha", -1.0))

func _flash(r: Dictionary) -> float:
	return float(r.get("flash_alpha", -1.0))

func _tethers(r: Dictionary) -> Array:
	return r.get("tethers", [null])

func test_ad_253_a_data_file(t) -> void:
	t.check(FileAccess.file_exists(FX_FILE), "ad_253 a0: boss_fx.json exists")
	var fx := _fx()
	t.check(not fx.is_empty(), "ad_253 a0: boss_fx.json parses with a wisp_shield dict")
	for key in FX_KEYS:
		t.check(fx.has(key), "ad_253 a0: wisp_shield has " + key)
	for key in ["tint_color", "tether_color"]:
		var col = fx.get(key, null)
		var ok: bool = col is Array and (col.size() == 3 or col.size() == 4)
		if ok:
			for v in col:
				ok = ok and (v is int or v is float)
		t.check(ok, "ad_253 a0: %s is an array of 3 or 4 numbers" % key)
	t.check(_canvas() != null and _canvas().has_method("shield_fx_step"), "ad_253 a0: combat_canvas exposes static shield_fx_step")

func test_ad_253_a_shielded_state(t) -> void:
	var fx := _fx()
	var r := _step({}, true, _wisps(3), 0, fx)
	var lo := float(fx.get("tint_alpha_min", 0.0))
	var hi := float(fx.get("tint_alpha_max", 0.0))
	t.check(_tint(r) > 0.0, "ad_253 a1: shielded tint_alpha > 0")
	t.check(_tint(r) >= lo and _tint(r) <= hi and hi > 0.0, "ad_253 a1: tint_alpha within [min, max]")
	t.equal(_tethers(r).size(), 3, "ad_253 a1: 3 live wisps -> 3 tethers")
	t.equal(_flash(r), 0.0, "ad_253 a1: no flash while shield is up")
	var wisps := _wisps(3)
	var tethers := _tethers(r)
	var same := tethers.size() == 3
	for i in mini(tethers.size(), 3):
		same = same and tethers[i] == wisps[i]
	t.check(same, "ad_253 a1: tethers target the wisp positions in order")

func test_ad_253_a_tint_pulses(t) -> void:
	var fx := _fx()
	var memo := {}
	var lo := float(fx.get("tint_alpha_min", 0.0))
	var hi := float(fx.get("tint_alpha_max", 0.0))
	var ticks := int(ceil(float(fx.get("pulse_period_s", 1.0)) * TPS))
	var seen := {}
	var in_range := hi > 0.0
	for tick in ticks + 1:
		var a := _tint(_step(memo, true, _wisps(2), tick, fx))
		seen[snappedf(a, 0.0001)] = true
		in_range = in_range and a >= lo - 0.0001 and a <= hi + 0.0001 and a > 0.0
	t.check(seen.size() >= 2, "ad_253 a2: tint alpha takes >= 2 distinct values over one pulse period")
	t.check(in_range, "ad_253 a2: pulsing alpha stays within [min, max] and > 0")

func test_ad_253_a_tethers_follow_live_wisps(t) -> void:
	var fx := _fx()
	var memo := {}
	t.equal(_tethers(_step(memo, true, _wisps(3), 0, fx)).size(), 3, "ad_253 a3: 3 live -> 3 tethers")
	t.equal(_tethers(_step(memo, true, _wisps(2), 1, fx)).size(), 2, "ad_253 a3: 2 live -> 2 tethers")
	var r := _step(memo, true, _wisps(1), 2, fx)
	t.equal(_tethers(r).size(), 1, "ad_253 a3: 1 live -> 1 tether")
	t.check(_tint(r) > 0.0, "ad_253 a3: tint stays up with a wisp alive")

func test_ad_253_a_break_clears_and_flashes(t) -> void:
	var fx := _fx()
	var flash_s := float(fx.get("break_flash_s", 99.0))
	t.check(flash_s > 0.0 and flash_s <= 0.1, "ad_253 a4: break_flash_s in (0, 0.1]")
	var memo := {}
	_step(memo, true, _wisps(1), 100, fx)
	var r := _step(memo, false, [], 101, fx)
	t.equal(_tint(r), 0.0, "ad_253 a4: tint gone on the first unshielded step")
	t.check(_tethers(r).is_empty(), "ad_253 a4: tethers gone on the first unshielded step")
	t.check(_flash(r) > 0.0, "ad_253 a4: shield-break flash starts on the first unshielded step")
	var end := _step(memo, false, [], 101 + int(ceil(0.1 * TPS)) + 1, fx)
	t.equal(_flash(end), 0.0, "ad_253 a4: flash over after ceil(0.1 s) + 1 ticks")
	t.equal(_tint(end), 0.0, "ad_253 a4: tint stays off after the break")

func test_ad_253_a_flash_rate_limit(t) -> void:
	var fx := _fx()
	var rate := float(fx.get("max_flashes_per_s", 99.0))
	t.check(float(fx.get("break_flash_s", 0.0)) > 0.0 and rate > 0.0 and rate <= 3.0, "ad_253 a5: break_flash_s > 0 and max_flashes_per_s in (0, 3]")
	var memo := {}
	_step(memo, true, _wisps(1), 100, fx)
	t.check(_flash(_step(memo, false, [], 101, fx)) > 0.0, "ad_253 a5: first break flashes")
	# Second break 9 ticks later: after the first flash ended, inside the 1 / max_flashes_per_s window.
	_step(memo, true, _wisps(1), 108, fx)
	var r := _step(memo, false, [], 110, fx)
	t.equal(_flash(r), 0.0, "ad_253 a5: second break inside the rate window does not flash")
	t.equal(_tint(r), 0.0, "ad_253 a5: second break still clears tint")
	t.check(_tethers(r).is_empty(), "ad_253 a5: second break still clears tethers")

func test_ad_253_a_never_shielded(t) -> void:
	var fx := _fx()
	var memo := {}
	var clean := not fx.is_empty()
	for tick in 30:
		var r := _step(memo, false, [], tick, fx)
		clean = clean and _tint(r) == 0.0 and _tethers(r).is_empty() and _flash(r) == 0.0
	t.check(clean, "ad_253 a6: never-shielded steps give no tint, tethers or flash (no flash at startup)")
