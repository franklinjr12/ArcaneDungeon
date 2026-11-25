extends SceneTree
## AD-236 step 1: boss 1 (ruins_warden) is the quality reference and must not drift.
## The fixture holds the master values of bosses.ruins_warden. Live data is compared against it,
## and the headline values are asserted explicitly so a regenerated fixture cannot hide a change.
const TestContext = preload("res://tests/test_context.gd")
const RUN_PATH := "res://world/data/run_v2.json"
const FIXTURE := "boss1_frozen/ruins_warden.json"
const DATA_DIR := "res://world/data"

## Discovered by run_tests.gd (run(t)) and also runnable directly: --script res://tests/test_ad_boss1_frozen.gd
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
	var live = _load_json(RUN_PATH)
	var frozen = t.fixture(FIXTURE)
	t.check(live is Dictionary and live.has("bosses"), "run_v2 has bosses block")
	t.check(frozen is Dictionary, "boss1 fixture loads")
	if not (live is Dictionary and live.has("bosses")) or not (frozen is Dictionary):
		return
	var warden = live["bosses"].get("ruins_warden", null)
	t.check(warden is Dictionary, "bosses.ruins_warden exists")
	if not warden is Dictionary:
		return
	_deep_compare(t, warden, frozen, "ruins_warden")
	_headline(t, warden, frozen)
	_other_hp(t)

func _load_json(path: String) -> Variant:
	return JSON.parse_string(FileAccess.get_file_as_string(path))

## Recursive equality that treats int and float numbers as equal when their values match.
## Reports the first differing key path.
func _deep_compare(t, actual: Variant, expected: Variant, path: String) -> void:
	if actual is Dictionary and expected is Dictionary:
		var keys_a: Array = actual.keys()
		var keys_e: Array = expected.keys()
		keys_a.sort()
		keys_e.sort()
		if keys_a != keys_e:
			t.check(false, "boss1 key set differs at %s: fixture %s live %s" % [path, str(keys_e), str(keys_a)])
			return
		for key in keys_e:
			_deep_compare(t, actual[key], expected[key], "%s.%s" % [path, str(key)])
		return
	if actual is Array and expected is Array:
		if actual.size() != expected.size():
			t.check(false, "boss1 array size differs at %s: fixture %d live %d" % [path, expected.size(), actual.size()])
			return
		for i in expected.size():
			_deep_compare(t, actual[i], expected[i], "%s[%d]" % [path, i])
		return
	if (actual is int or actual is float) and (expected is int or expected is float):
		t.check(absf(float(actual) - float(expected)) < 0.000001,
			"boss1 value differs at %s: fixture %s live %s" % [path, str(expected), str(actual)])
		return
	t.check(typeof(actual) == typeof(expected) and actual == expected,
		"boss1 value differs at %s: fixture %s live %s" % [path, str(expected), str(actual)])

func _near(t, actual: Variant, expected: Variant, label: String) -> void:
	t.check(actual != null and absf(float(actual) - float(expected)) < 0.000001,
		"%s: expected %s got %s" % [label, str(expected), str(actual)])

func _headline(t, w: Dictionary, f: Dictionary) -> void:
	_near(t, w.get("hp"), 1800, "headline hp")
	_near(t, w.get("windup_ticks"), 48, "headline windup_ticks")
	_near(t, w.get("second_phase_windup_ticks"), 33, "headline second_phase_windup_ticks")
	_near(t, w.get("recovery_ticks"), 44, "headline recovery_ticks")
	_near(t, w.get("phase_threshold"), 0.5, "headline phase_threshold")
	_near(t, w.get("radial_damage"), 9, "headline radial_damage")
	_near(t, w.get("shot_damage"), 16, "headline shot_damage")
	var melee: Dictionary = w.get("melee", {})
	_near(t, melee.get("sweep_1", {}).get("windup_ticks"), 40, "headline sweep_1 windup")
	_near(t, melee.get("sweep_2", {}).get("windup_ticks"), 32, "headline sweep_2 windup")
	_near(t, melee.get("overhead_slam", {}).get("windup_ticks"), 48, "headline overhead_slam windup")
	_near(t, melee.get("sweep_1", {}).get("damage"), 14, "headline sweep_1 damage")
	_near(t, melee.get("sweep_2", {}).get("damage"), 14, "headline sweep_2 damage")
	_near(t, melee.get("overhead_slam", {}).get("damage"), 24, "headline overhead_slam damage")
	_near(t, w.get("spear_line", {}).get("windup_ticks"), 54, "headline spear_line windup")
	_near(t, w.get("spear_line", {}).get("damage"), 16, "headline spear_line damage")
	_near(t, w.get("grave_rise", {}).get("windup_ticks"), 54, "headline grave_rise windup")
	var phases: Array = w.get("phases", [])
	t.equal(phases.size(), f.get("phases", []).size(), "headline phases array size matches fixture")

## No other data file may change the warden's hp: any dictionary under a ruins_warden key must keep 1800.
func _other_hp(t) -> void:
	var dir := DirAccess.open(DATA_DIR)
	if dir == null:
		t.check(false, "data dir accessible: " + DATA_DIR)
		return
	for filename in dir.get_files():
		if not filename.ends_with(".json"):
			continue
		var data = _load_json(DATA_DIR + "/" + filename)
		_find_warden_hp(t, data, filename)

func _find_warden_hp(t, node: Variant, filename: String) -> void:
	if node is Dictionary:
		for key in node.keys():
			if key == "ruins_warden" and node[key] is Dictionary and node[key].has("hp"):
				_near(t, node[key]["hp"], 1800, "ruins_warden hp in " + filename)
			_find_warden_hp(t, node[key], filename)
	elif node is Array:
		for item in node:
			_find_warden_hp(t, item, filename)
