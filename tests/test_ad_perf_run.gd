extends RefCounted
## AD-187: perf-run core (room setup, percentiles, report schema).
const PerfRun = preload("res://game/core/perf_run.gd")
const Flow = preload("res://world/run_flow.gd")
const TEST_DIR := "user://ad187_test_perf"

func _room(id: String, p95: float) -> Dictionary:
	return {"room_id": id, "stage": 1, "type": "combat", "frames": 600, "enemies_spawned": 5,
		"peak_enemies_alive": 5, "peak_effects": 9,
		"frame_ms": {"p50": 5.0, "p95": p95, "max": 20.0}, "sim_ms": {"p50": 1.0, "p95": 2.0, "max": 3.0}}

func _report(cfg: Dictionary, p95: float = 10.0) -> Dictionary:
	var rooms: Array = []
	for id in cfg["rooms"]:
		rooms.append(_room(str(id), p95))
	return PerfRun.build_report(cfg, rooms, {"lighting": "high", "headless": true,
		"window_size": [1920, 1080], "renderer": "dummy"})

func run(t) -> void:
	var cfg := PerfRun.config()
	t.check(cfg.get("rooms", []) == ["ruins_c07", "cistern_p10", "ruins_boss", "cistern_boss"], "AD-187 config has the four rooms")
	for id in cfg["rooms"]:
		var flow = Flow.new(int(cfg["seed"]), Flow.CONFIG_V2)
		var prep: Dictionary = PerfRun.prepare_room(flow, str(id), cfg)
		t.check(bool(prep["ok"]) and int(prep["enemies_spawned"]) > 0, "AD-187 prepare_room ok " + str(id))
		if not prep["ok"]:
			continue
		for i in 20:
			PerfRun.refill(flow.session)
			flow.step(PerfRun.command(flow.session))
		t.check(flow.state == "fighting", "AD-187 still fighting after 20 ticks " + str(id))
	var bad: Dictionary = PerfRun.prepare_room(Flow.new(int(cfg["seed"]), Flow.CONFIG_V2), "nope", cfg)
	t.check(not bad["ok"], "AD-187 prepare_room rejects unknown room")

	var st: Dictionary = PerfRun.sample_stats([5000, 1000, 3000, 2000, 4000])
	t.check(is_equal_approx(st["p50"], 4.0) and is_equal_approx(st["p95"], 5.0) and is_equal_approx(st["max"], 5.0), "AD-187 sample_stats known array")
	var empty: Dictionary = PerfRun.sample_stats([])
	t.check(empty["p50"] == 0.0 and empty["p95"] == 0.0 and empty["max"] == 0.0, "AD-187 sample_stats empty is zeros")

	var rep := _report(cfg)
	t.check(PerfRun.validate_report(rep).is_empty(), "AD-187 built report validates: " + str(PerfRun.validate_report(rep)))
	var r2 := rep.duplicate(true)
	r2.erase("renderer")
	t.check(not PerfRun.validate_report(r2).is_empty(), "AD-187 missing key is an issue")
	r2 = rep.duplicate(true)
	r2["seed"] = "x"
	t.check(not PerfRun.validate_report(r2).is_empty(), "AD-187 wrong type is an issue")
	r2 = rep.duplicate(true)
	r2["lighting"] = "ultra"
	t.check(not PerfRun.validate_report(r2).is_empty(), "AD-187 unknown lighting is an issue")
	r2 = rep.duplicate(true)
	r2["rooms"].remove_at(3)
	t.check(not PerfRun.validate_report(r2).is_empty(), "AD-187 wrong room list is an issue")
	r2 = rep.duplicate(true)
	r2["rooms"][0]["frame_ms"].erase("p95")
	t.check(not PerfRun.validate_report(r2).is_empty(), "AD-187 missing stats key is an issue")

	var target := float(cfg["target_p95_frame_ms"])
	t.check(bool(_report(cfg, target)["rooms"][0]["pass"]), "AD-187 pass at exactly target")
	t.check(not bool(_report(cfg, target + 0.01)["rooms"][0]["pass"]), "AD-187 fail just above target")

	var path := PerfRun.write_report(rep, TEST_DIR)
	t.check(path != "" and not path.get_file().contains(":"), "AD-187 write_report path has no colon")
	var found := DirAccess.get_files_at(TEST_DIR)
	t.check(found.size() == 1 and found[0].ends_with(".json"), "AD-187 write_report creates one json")
	if path != "":
		var parsed = JSON.parse_string(FileAccess.get_file_as_string(path))
		t.check(parsed is Dictionary and PerfRun.validate_report(parsed).is_empty(), "AD-187 written report parses and validates")
	for f in found:
		DirAccess.remove_absolute(TEST_DIR + "/" + f)
	DirAccess.remove_absolute(TEST_DIR)
