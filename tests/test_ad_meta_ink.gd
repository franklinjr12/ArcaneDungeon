extends SceneTree
## AD-233: Arcane Ink currency in the profile (schema v3): migration, config, record_run, round trip.
## Discovered by run_tests.gd (run(t)) and also runnable directly: --script res://tests/test_ad_meta_ink.gd
const TestContext = preload("res://tests/test_context.gd")
const Service = preload("res://game/core/save_service.gd")
const Meta = preload("res://world/meta_progress.gd")
const Flow = preload("res://world/run_flow.gd")
const SEED := 20261022
const DIR := "user://ad233_test/"

func _clean() -> void:
	DirAccess.make_dir_recursive_absolute(DIR)
	for f in DirAccess.get_files_at(DIR):
		DirAccess.remove_absolute(DIR + f)

func _write(name: String, text: String) -> void:
	var f := FileAccess.open(DIR + name, FileAccess.WRITE)
	f.store_string(text)
	f.close()

func _corrupt_count() -> int:
	var n := 0
	for f in DirAccess.get_files_at(DIR):
		if f.begins_with("profile.json.corrupt-"):
			n += 1
	return n

func _initialize() -> void:
	var t := TestContext.new()
	run(t)
	print("TEST SUMMARY: %d passed / %d failed" % [t.passed, t.failed])
	for failure in t.failures:
		printerr("FAILED: ", failure)
	quit(1 if t.failed > 0 else 0)

func run(t) -> void:
	_config(t)
	_migration(t)
	_record(t)
	_round_trip(t)
	_flow_events(t)
	_flow_exits(t)
	_flow_save_payload(t)
	_flow_profile(t)

func _config(t) -> void:
	var r := Meta.ink_rules()
	t.equal([int(r.get("room_cleared", -1)), int(r.get("mini_boss", -1)), int(r.get("boss", -1)), int(r.get("new_stage", -1)), int(r.get("run_won", -1))], [3, 8, 20, 5, 15], "AD-233 ink earn rules")
	t.equal(Service.SCHEMA_VERSION, 3, "AD-233 schema v3")
	t.equal(Service.default_profile()["meta"]["ink"], 0, "AD-233 default ink 0")
	t.equal(Meta.empty_meta()["ink"], 0, "AD-233 empty_meta ink 0")
	var m := Meta.empty_meta()
	t.equal(Meta.add_ink(m, 5), 5, "AD-233 add_ink total")
	t.equal(Meta.add_ink(m, -4), 5, "AD-233 add_ink ignores negatives")
	var no_ink := Meta.empty_meta()
	no_ink.erase("ink")
	t.check(Meta.valid_meta(no_ink) and no_ink["ink"] == 0, "AD-233 missing ink valid as 0")
	var fl := Meta.empty_meta()
	fl["ink"] = 7.0
	t.check(Meta.valid_meta(fl) and typeof(fl["ink"]) == TYPE_INT, "AD-233 float ink normalised")
	for bad in [-1, 2.5, "3"]:
		var b := Meta.empty_meta()
		b["ink"] = bad
		t.check(not Meta.valid_meta(b), "AD-233 invalid ink rejected: %s" % str(bad))

func _migration(t) -> void:
	var disc := {"runes": ["a"], "reactions": ["chill_freeze"], "enemies": [], "artifacts": []}
	var stats := {"runs": 4, "wins": 1, "deaths": 3, "best_time_seconds": 50.0, "last_seed": 9}
	var v2 := Service.migrate({"schema_version": 2, "stats": stats, "meta": {"discovered": disc}})
	t.equal(v2["schema_version"], 3, "AD-233 v2 -> v3")
	t.equal(v2["meta"]["discovered"], disc, "AD-233 v2 discoveries kept")
	t.equal(v2["stats"], stats, "AD-233 v2 stats kept")
	t.equal(v2["meta"]["ink"], 0, "AD-233 v2 ink defaults 0")
	var v1 := Service.migrate({"schema_version": 1, "stats": stats})
	t.equal([v1["schema_version"], v1["meta"]["ink"]], [3, 0], "AD-233 v1 reaches v3")
	var v0 := Service.migrate({"runs": 5, "wins": 2, "best_time": 50.0})
	t.equal([v0["schema_version"], v0["meta"]["ink"]], [3, 0], "AD-233 v0 reaches v3")
	_clean()
	_write("profile.json", JSON.stringify({"schema_version": 2, "stats": stats, "meta": {"discovered": disc}}))
	var svc = Service.new()
	svc.set_base_dir(DIR)
	svc.load_profile()
	t.equal([svc.profile["schema_version"], svc.ink(), svc.meta()["discovered"]], [3, 0, disc.merged({"affixes": []})], "AD-233 v2 file loads as v3")
	_write("profile.json", JSON.stringify({"schema_version": 3, "stats": stats, "meta": {"discovered": disc, "ink": -2}}))
	svc.load_profile()
	t.equal(_corrupt_count(), 1, "AD-233 negative ink quarantined")
	t.equal(svc.ink(), 0, "AD-233 defaults after quarantine")
	svc.free()
	_clean()
	DirAccess.remove_absolute(DIR)

func _record(t) -> void:
	_clean()
	var svc = Service.new()
	svc.set_base_dir(DIR)
	svc.record_run({"outcome": "lost", "seed": 1, "ink_earned": 11})
	t.equal(svc.ink(), 11, "AD-233 ink kept on death")
	svc.record_run({"outcome": "abandoned", "seed": 2, "ink_earned": 6})
	t.equal(svc.ink(), 17, "AD-233 ink kept on quit and accumulates")
	svc.record_run({"outcome": "won", "seed": 3, "seconds": 90.0, "ink_earned": 38})
	t.equal(svc.ink(), 55, "AD-233 ink kept on win")
	svc.record_run({"outcome": "lost", "seed": 4})
	svc.record_run({"outcome": "lost", "seed": 5, "ink_earned": -9})
	t.equal(svc.ink(), 55, "AD-233 missing or negative ink_earned ignored")
	svc.free()
	_clean()
	DirAccess.remove_absolute(DIR)

func _round_trip(t) -> void:
	_clean()
	var svc = Service.new()
	svc.set_base_dir(DIR)
	svc.record_discoveries({"reactions": ["chill_freeze"]})
	svc.record_run({"outcome": "lost", "seed": 7, "ink_earned": 23})
	var svc2 = Service.new()
	svc2.set_base_dir(DIR)
	svc2.load_profile()
	t.equal(svc2.ink(), 23, "AD-233 ink round-trips")
	t.equal(svc2.meta()["discovered"]["reactions"], ["chill_freeze"], "AD-233 discoveries round-trip")
	t.equal(svc2.stats()["deaths"], 1, "AD-233 stats round-trip")
	svc.free()
	svc2.free()
	_clean()
	DirAccess.remove_absolute(DIR)

func _kill_all(flow, limit: int = 3000) -> void:
	for i in limit:
		if flow.state != "fighting":
			return
		for enemy in flow.session.enemies:
			if enemy.target.alive():
				enemy.target.receive_damage(100000, "fire", 1, 100)
		flow.step()

func _jump(flow, index: int) -> void:
	flow.run.sequence_index = index
	flow._enter_current()

func _flow_events(t) -> void:
	var flow = Flow.new(SEED)
	t.equal(flow.ink_earned, 0, "AD-233 run starts with 0 ink")
	_kill_all(flow)
	t.equal(flow.ink_earned, 3, "AD-233 room_cleared +3")
	flow._finish_combat()
	t.equal(flow.ink_earned, 3, "AD-233 clear credited once")
	_jump(flow, 3)
	t.equal(flow.room.values["type"], "boss", "AD-233 test room is the boss")
	_kill_all(flow)
	t.equal(flow.ink_earned, 23, "AD-233 boss +20 (not room_cleared)")
	t.equal(flow.summary()["ink_earned"], 23, "AD-233 summary carries ink_earned")
	_jump(flow, 4)
	t.equal(flow.ink_earned, 23, "AD-233 workshop earns nothing")
	t.equal(flow.try_exit(Vector2.ZERO)["ok"], true, "AD-233 workshop exit")
	t.equal(flow.ink_earned, 28, "AD-233 new_stage +5 entering stage 1")
	_jump(flow, 5)
	t.equal(flow.ink_earned, 28, "AD-233 re-entering the same room earns no stage ink")
	_kill_all(flow)
	t.equal(flow.ink_earned, 28 + 3 + 15, "AD-233 stage-2 room (final in v1) pays room_cleared + run_won")
	var won = Flow.new(SEED)
	_jump(won, won.rooms.size() - 1)
	_kill_all(won)
	t.equal(won.state, "won", "AD-233 final room wins")
	t.equal(won.ink_earned, 3 + 15, "AD-233 final room_cleared + run_won +15")
	won._finish_combat()
	t.equal(won.ink_earned, 18, "AD-233 run_won credited once")
	won.start_new(SEED)
	t.equal(won.ink_earned, 0, "AD-233 start_new resets ink_earned")
	# Mini-boss rooms (the ones owning a mini_boss_slot) pay mini_boss instead of room_cleared.
	var v2 = Flow.new(SEED, Flow.CONFIG_V2)
	var mini := -1
	for i in v2.rooms.size():
		if v2.rooms[i].has("mini_boss_slot") and str(v2.rooms[i].get("type")) != "boss":
			mini = i
			break
	t.check(mini >= 0, "AD-233 v2 sequence has a mini-boss room")
	if mini >= 0:
		_jump(v2, mini)
		_kill_all(v2)
		t.equal(v2.state, "cleared", "AD-233 mini-boss room cleared")
		t.equal(v2.ink_earned, 8, "AD-233 mini_boss +8")

func _flow_exits(t) -> void:
	# Leaving the last room of stage 0 in the v2 config credits one stage change.
	var flow = Flow.new(SEED, Flow.CONFIG_V2)
	var last_stage0 := -1
	for i in flow.rooms.size():
		if int(flow.rooms[i].get("stage", 0)) == 0:
			last_stage0 = i
	_jump(flow, last_stage0)
	if flow.state == "fighting":
		_kill_all(flow)
	var before: int = flow.ink_earned
	var exit: Dictionary = flow.try_exit(flow.room.marker("exit"))
	t.check(exit["ok"], "AD-233 v2 exit ok: %s" % str(exit))
	t.equal(flow.ink_earned - before, 5, "AD-233 v2 new_stage credited on leaving stage 0")

func _flow_save_payload(t) -> void:
	var flow = Flow.new(SEED)
	_jump(flow, 4)
	flow.ink_earned = 26
	var payload: Dictionary = flow.save_payload()
	t.equal(payload["counters"]["ink_earned"], 26, "AD-233 payload carries ink_earned")
	var restored = Flow.new(SEED)
	var text: String = JSON.stringify(payload)
	t.check(restored.resume(JSON.parse_string(text))["ok"], "AD-233 payload resumes")
	t.equal(restored.ink_earned, 26, "AD-233 Continue keeps ink_earned")
	var old: Dictionary = JSON.parse_string(text)
	old["counters"].erase("ink_earned")
	var legacy = Flow.new(SEED)
	t.check(legacy.resume(old)["ok"], "AD-233 payload without ink_earned still loads")
	t.equal(legacy.ink_earned, 0, "AD-233 missing ink_earned defaults 0")

func _flow_profile(t) -> void:
	# Death keeps the ink, and a fresh SaveService reading the same dir sees it.
	_clean()
	var flow = Flow.new(SEED)
	_kill_all(flow)
	t.check(flow.try_exit(flow.room.marker("exit"))["ok"], "AD-233 walked into room 2")
	flow.session.sim.actor.receive_damage(100000, "fire", 2, 100)
	flow.step({"cast": 0})
	t.equal(flow.summary()["outcome"], "lost", "AD-233 run lost")
	var stats: Dictionary = flow.summary()
	stats["discovered"] = flow.discoveries()
	var svc = Service.new()
	svc.set_base_dir(DIR)
	svc.record_discoveries({"reactions": ["chill_freeze"]})
	svc.record_run(stats)
	t.equal(svc.ink(), 3, "AD-233 death keeps the room's ink in the profile")
	var svc2 = Service.new()
	svc2.set_base_dir(DIR)
	svc2.load_profile()
	t.equal(svc2.ink(), 3, "AD-233 ink survives relaunch")
	t.equal(svc2.meta()["discovered"]["reactions"], ["chill_freeze"], "AD-233 discoveries survive with ink")
	svc.free()
	svc2.free()
	_clean()
	DirAccess.remove_absolute(DIR)
