extends RefCounted
## AD-233: Arcane Ink currency in the profile (schema v3): migration, config, record_run, round trip.
const Service = preload("res://game/core/save_service.gd")
const Meta = preload("res://world/meta_progress.gd")
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

func run(t) -> void:
	_config(t)
	_migration(t)
	_record(t)
	_round_trip(t)

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
	t.equal([svc.profile["schema_version"], svc.ink(), svc.meta()["discovered"]], [3, 0, disc], "AD-233 v2 file loads as v3")
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
