extends SceneTree
## AD-252 step 1: the Drowned Archivist (cistern_boss) floods a new shallow-water set at 0.66 and a larger one at 0.33.
const TestContext = preload("res://tests/test_context.gd")
const Session = preload("res://combat/combat_session.gd")
const LIVE_FILE := "res://world/data/run_v2.json"
const ARENA_TAG := "boss_arena"
const ANCHOR_MARGIN := 70.0
const SPAWN_MARGIN := 40.0
const ARENA_SIZE := Vector2(1300.0, 900.0)

## Discovered by run_tests.gd (run(t)) and also runnable directly: --script res://tests/test_ad_boss2_arena.gd
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
	test_ad_252_a_water_changes_at_both_thresholds(t)
	test_ad_252_a_no_overlap_with_anchors_and_spawn(t)

func _doc() -> Dictionary:
	return JSON.parse_string(FileAccess.get_file_as_string(LIVE_FILE))

## Water rects of a phase's arena_change; empty when the phase has none.
func _phase_water(boss: Dictionary, phase_index: int) -> Array:
	var phases: Array = boss.get("phases", [])
	if phase_index >= phases.size():
		return []
	var transition: Dictionary = phases[phase_index].get("transition", {})
	return transition.get("arena_change", {}).get("water", [])

func _area(water: Array) -> float:
	var total := 0.0
	for entry in water:
		total += float(entry["rect"][2]) * float(entry["rect"][3])
	return total

func _rect_valid(entry: Variant) -> bool:
	if not entry is Dictionary or str(entry.get("kind", "")) != "shallow":
		return false
	var rect = entry.get("rect", null)
	if not rect is Array or rect.size() != 4:
		return false
	for v in rect:
		if not (v is int or v is float):
			return false
	return true

func _rect_of(entry: Dictionary) -> Rect2:
	var r: Array = entry["rect"]
	return Rect2(float(r[0]), float(r[1]), float(r[2]), float(r[3]))

func _tagged(s) -> Array:
	if s.water == null:
		return []
	return s.water.view().filter(func(e): return e.get("tag", "") == ARENA_TAG)

func _step_to_phase(s, boss, hp_fraction: float, phase: int) -> void:
	boss.target.health.current = boss.target.health.maximum * hp_fraction
	for i in 400:
		s.step()
		if boss.state != "roar" and boss.phase >= phase:
			break

func test_ad_252_a_water_changes_at_both_thresholds(t) -> void:
	var doc := _doc()
	var boss: Dictionary = doc["bosses"]["cistern_boss"]
	var phases: Array = boss["phases"]
	t.check(phases.size() >= 3 and is_equal_approx(float(phases[1]["threshold"]), 0.66) and is_equal_approx(float(phases[2]["threshold"]), 0.33), "AD-252 cistern_boss has phases at 0.66 and 0.33")
	var w2 := _phase_water(boss, 1)
	var w3 := _phase_water(boss, 2)
	t.check(not w2.is_empty(), "AD-252 phase 2 (0.66) transition has arena_change water")
	t.check(not w3.is_empty(), "AD-252 phase 3 (0.33) transition has arena_change water")
	t.check(w2.all(_rect_valid) and w3.all(_rect_valid), "AD-252 every flood entry is a shallow 4-number rect")
	t.check(_area(w3) > _area(w2), "AD-252 the phase 3 flood is larger than the phase 2 flood")
	var stays := true
	for entry in w2:
		stays = stays and w3.any(func(e): return e.get("rect", []) == entry.get("rect", null))
	t.check(not w2.is_empty() and stays, "AD-252 the phase 3 set contains every phase 2 rect so the flood stays")

	var s = Session.new(1981, "empty", 0)
	s.defer_clear = true
	s.set_water(doc["room_templates"]["cistern_boss"]["layout"]["water"])
	var cfg: Dictionary = boss.duplicate(true)
	var live_boss = s.spawn_boss(cfg, Vector2(float(cfg["position"][0]), float(cfg["position"][1])))
	for i in 10:
		s.step()
	var before := _tagged(s).size()
	t.equal(before, 0, "AD-252 no arena water in phase 1")
	_step_to_phase(s, live_boss, 0.6, 1)
	var mid := _tagged(s)
	t.check(mid.size() > before, "AD-252 crossing 0.66 floods tagged boss_arena water")
	var mid_area := _area(mid)
	_step_to_phase(s, live_boss, 0.3, 2)
	var late := _tagged(s)
	t.check(late.size() >= mid.size() and _area(late) > mid_area, "AD-252 crossing 0.33 floods a larger tagged set (%d -> %d)" % [mid.size(), late.size()])

func test_ad_252_a_no_overlap_with_anchors_and_spawn(t) -> void:
	var doc := _doc()
	var boss: Dictionary = doc["bosses"]["cistern_boss"]
	var pools: Array = boss["pools"]
	var entrance: Array = doc["room_templates"]["cistern_boss"]["entrance"]
	var spawn := Vector2(float(entrance[0]), float(entrance[1]))
	t.equal(pools.size(), 3, "AD-252 cistern_boss has 3 pool anchors")
	var arena := Rect2(Vector2.ZERO, ARENA_SIZE)
	var checked := 0
	for idx in [1, 2]:
		var water := _phase_water(boss, idx)
		t.check(not water.is_empty(), "AD-252 phase %d has water rects to check" % (idx + 1))
		for entry in water:
			if not _rect_valid(entry):
				continue
			checked += 1
			var rect := _rect_of(entry)
			t.check(arena.encloses(rect), "AD-252 phase %d rect %s lies within the arena" % [idx + 1, str(entry["rect"])])
			t.check(not spawn_hit(rect, spawn), "AD-252 phase %d rect %s keeps off the player spawn" % [idx + 1, str(entry["rect"])])
			for p in pools:
				var at := Vector2(float(p[0]), float(p[1]))
				t.check(not rect.grow(ANCHOR_MARGIN).has_point(at), "AD-252 phase %d rect %s keeps off pool anchor %s" % [idx + 1, str(entry["rect"]), str(p)])
	t.check(checked > 0, "AD-252 at least one flood rect was checked")

func spawn_hit(rect: Rect2, spawn: Vector2) -> bool:
	return rect.grow(SPAWN_MARGIN).has_point(spawn)
