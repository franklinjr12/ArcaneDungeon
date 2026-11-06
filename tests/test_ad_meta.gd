extends RefCounted
## AD-145: meta progress (discoveries, milestones) and profile schema v2 migration.
const Service = preload("res://game/core/save_service.gd")
const Meta = preload("res://world/meta_progress.gd")
const DIR := "user://ad145_test/"

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

func _ids(prefix: String, n: int) -> Array:
	var out: Array = []
	for i in n:
		out.append("%s_%02d" % [prefix, i])
	return out

func run(t) -> void:
	_clean()
	var svc = Service.new()
	svc.set_base_dir(DIR)
	t.equal(svc.meta(), Meta.empty_meta(), "AD-145 default meta empty")
	t.equal(svc.locked_runes(), ["trigger.on_expire", "trigger.timer"], "AD-145 default locked runes")
	t.equal(svc.locked_artifacts(), ["archivists_quill", "echo_chamber", "gravity_lens", "shatterheart", "stormglass"], "AD-145 default locked artifacts")
	# Persistence across instances.
	svc.record_run({"outcome": "lost", "seed": 5, "discovered": {"runes": ["form.burst", "essence.fire"], "enemies": ["rust_golem"]}})
	var svc2 = Service.new()
	svc2.set_base_dir(DIR)
	t.equal(svc2.meta()["discovered"]["runes"], ["essence.fire", "form.burst"], "AD-145 discovery persists (sorted)")
	t.equal(svc2.meta()["discovered"]["enemies"], ["rust_golem"], "AD-145 enemy discovery persists")
	t.equal(svc2.stats()["runs"], 1, "AD-145 stats kept with meta")
	# Merge idempotent and sorted.
	var m := Meta.empty_meta()
	var a := Meta.merge(m, {"runes": ["b", "a", "b"]})
	t.equal(a["runes"], ["a", "b"], "AD-145 merge returns new sorted unique")
	t.equal(Meta.merge(m, {"runes": ["a", "b"]})["runes"], [], "AD-145 merge idempotent")
	t.equal(m["discovered"]["runes"], ["a", "b"], "AD-145 merged list sorted")
	# Milestones.
	var before := Meta.empty_meta()
	var after := Meta.empty_meta()
	Meta.merge(after, {"reactions": ["chill_freeze", "wet_lightning_arc"]})
	t.equal(Meta.milestones_met(after), ["reactions_2"], "AD-145 reactions milestone met")
	t.equal(Meta.newly_met(before, after), ["reactions_2"], "AD-145 newly met")
	t.check("trigger.timer" not in Meta.locked_runes(after) and "stormglass" not in Meta.locked_artifacts(after), "AD-145 milestone unlocks leave locked lists")
	t.check("trigger.on_expire" in Meta.locked_runes(after), "AD-145 other milestone stays locked")
	Meta.merge(after, {"runes": _ids("r", 8), "enemies": _ids("e", 6), "artifacts": _ids("x", 4)})
	t.equal(Meta.milestones_met(after), ["runes_8", "reactions_2", "enemies_6", "artifacts_4"], "AD-145 all milestones in data order")
	t.equal([Meta.locked_runes(after), Meta.locked_artifacts(after)], [[], []], "AD-145 nothing locked after all milestones")
	# record_discoveries reports milestones and persists.
	var res: Dictionary = svc2.record_discoveries({"reactions": ["chill_freeze", "fire_thaw_steam"]})
	t.equal(res["milestones"], ["reactions_2"], "AD-145 record_discoveries milestone")
	t.equal(res["new"]["reactions"], ["chill_freeze", "fire_thaw_steam"], "AD-145 record_discoveries new ids")
	t.check("trigger.timer" not in svc2.locked_runes(), "AD-145 unlock changes the pool")
	# Unlocks never touch stats.
	var stats_before: Dictionary = svc2.stats()
	svc2.record_discoveries({"enemies": _ids("e", 6)})
	t.equal(svc2.stats(), stats_before, "AD-145 milestones change no stat keys")
	# v1 file migrates with stats kept.
	_write("profile.json", JSON.stringify({"schema_version": 1, "stats": {"runs": 4, "wins": 1, "deaths": 3, "best_time_seconds": 50.0, "last_seed": 9}}))
	svc2.load_profile()
	t.equal(svc2.profile["schema_version"], 2, "AD-145 v1 migrated to v2")
	t.equal(svc2.meta(), Meta.empty_meta(), "AD-145 v1 gets empty meta")
	t.equal(svc2.stats()["runs"], 4, "AD-145 v1 stats kept")
	# Invalid meta / junk -> quarantined, defaults.
	_write("profile.json", JSON.stringify({"schema_version": 2, "stats": Service.DEFAULT_STATS, "meta": {"discovered": {"runes": 5, "reactions": [], "enemies": [], "artifacts": []}}}))
	svc2.load_profile()
	t.equal(svc2.meta(), Meta.empty_meta(), "AD-145 invalid meta -> defaults")
	t.equal(_corrupt_count(), 1, "AD-145 invalid meta quarantined")
	_write("profile.json", JSON.stringify({"schema_version": 2, "stats": Service.DEFAULT_STATS, "meta": {"discovered": {"runes": [1], "reactions": [], "enemies": [], "artifacts": []}}}))
	svc2.load_profile()
	t.equal(_corrupt_count(), 2, "AD-145 non-string ids quarantined")
	_write("profile.json", "{not json")
	svc2.load_profile()
	t.equal(_corrupt_count(), 3, "AD-145 non-JSON quarantined")
	_write("profile.json", JSON.stringify({"schema_version": 3, "stats": {}}))
	svc2.load_profile()
	t.equal(_corrupt_count(), 4, "AD-145 future version quarantined")
	t.equal(svc2.profile, Service.default_profile(), "AD-145 defaults after quarantine")
	_clean()
	DirAccess.remove_absolute(DIR)
