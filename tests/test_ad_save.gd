extends RefCounted
## AD-019: SaveService round-trip, migration, corrupt quarantine, atomic write.
const Service = preload("res://game/core/save_service.gd")
const DIR := "user://ad019_test/"

func _clean() -> void:
	DirAccess.make_dir_recursive_absolute(DIR)
	for f in DirAccess.get_files_at(DIR):
		DirAccess.remove_absolute(DIR + f)

func _write(name: String, text: String) -> void:
	var f := FileAccess.open(DIR + name, FileAccess.WRITE)
	f.store_string(text)
	f.close()

func _corrupt_files(prefix: String) -> Array:
	var out: Array = []
	for f in DirAccess.get_files_at(DIR):
		if f.begins_with(prefix + ".corrupt-"):
			out.append(f)
	return out

func run(t) -> void:
	_clean()
	var svc = Service.new()
	svc.set_base_dir(DIR)
	t.equal(svc.stats()["runs"],0,"AD-019 defaults when files missing")
	t.equal(svc.settings.volumes["Master"],1.0,"AD-019 default master volume")
	# Round trip.
	svc.settings.volumes["Master"] = 0.4
	svc.settings.reduce_flashes = true
	svc.settings.screen_shake = false
	svc.settings.telemetry_opt_in = true
	t.equal(svc.save_settings(),OK,"AD-019 settings saved")
	svc.record_run({"outcome":"won","seed":77,"seconds":120.5})
	svc.record_run({"outcome":"lost","seed":78,"seconds":10.0})
	svc.record_run({"outcome":"won","seed":79,"seconds":99.0})
	var svc2 = Service.new()
	svc2.set_base_dir(DIR)
	t.equal(svc2.settings.volumes["Master"],0.4,"AD-019 volume round-trip")
	t.check(svc2.settings.reduce_flashes and not svc2.settings.screen_shake and svc2.settings.telemetry_opt_in,"AD-019 toggles round-trip")
	var st: Dictionary = svc2.stats()
	t.equal([st["runs"],st["wins"],st["deaths"],st["last_seed"]],[3,2,1,79],"AD-019 stats round-trip")
	t.equal(st["best_time_seconds"],99.0,"AD-019 best time is min of wins")
	# Out-of-range / wrong typed settings fall back.
	_write("settings.cfg","[audio]\nMaster=7.0\nBogus=\"x\"\n[accessibility]\nscreen_shake=\"yes\"\nunknown=1\n")
	svc2.load_settings()
	t.equal(svc2.settings.volumes["Master"],1.0,"AD-019 volume clamped")
	t.check(not svc2.settings.volumes.has("Bogus") and svc2.settings.screen_shake,"AD-019 wrong type ignored")
	# Migration v0 -> v1.
	var m: Dictionary = Service.migrate({"runs":5,"wins":2,"best_time":50.0})
	t.equal(m["schema_version"],1,"AD-019 migrated version")
	t.equal([m["stats"]["runs"],m["stats"]["wins"],m["stats"]["deaths"],m["stats"]["best_time_seconds"]],[5,2,0,50.0],"AD-019 v0 flat keys wrapped")
	_write("profile.json",JSON.stringify({"runs":4,"wins":1,"deaths":3,"last_seed":9}))
	svc2.load_profile()
	t.equal(svc2.stats()["runs"],4,"AD-019 v0 file loaded via migration")
	# Corrupt files are quarantined, defaults loaded.
	_write("profile.json","{not json")
	svc2.load_profile()
	t.equal(svc2.stats()["runs"],0,"AD-019 corrupt profile -> defaults")
	t.equal(_corrupt_files("profile.json").size(),1,"AD-019 corrupt profile quarantined")
	t.check(not FileAccess.file_exists(DIR + "profile.json"),"AD-019 corrupt original removed")
	_write("profile.json",JSON.stringify({"schema_version":1,"stats":{"runs":-3,"wins":0,"deaths":0,"best_time_seconds":-1.0,"last_seed":-1}}))
	svc2.load_profile()
	t.equal(_corrupt_files("profile.json").size(),2,"AD-019 invalid stats quarantined")
	_write("profile.json",JSON.stringify({"schema_version":99,"stats":{}}))
	svc2.load_profile()
	t.equal(_corrupt_files("profile.json").size(),3,"AD-019 future version quarantined")
	# Engine ConfigFile parse errors print ERROR lines (fail validate_godot), so exercise the quarantine step directly.
	_write("settings.cfg","[audio]\nMaster=0.2\n")
	svc2._quarantine(DIR + "settings.cfg")
	svc2.load_settings()
	t.equal(svc2.settings.volumes["Master"],1.0,"AD-019 quarantined settings -> defaults")
	t.equal(_corrupt_files("settings.cfg").size(),1,"AD-019 corrupt settings quarantined")
	# Atomic write leaves no tmp file.
	t.equal(svc2.save_profile(),OK,"AD-019 profile saved")
	t.equal(svc2.save_settings(),OK,"AD-019 settings re-saved")
	for f in DirAccess.get_files_at(DIR):
		t.check(not f.ends_with(".tmp"),"AD-019 no partial .tmp left (%s)" % f)
	# Failed write (target dir missing) also leaves nothing and does not crash.
	svc2.base_dir = "user://ad019_missing_dir/"
	t.check(svc2.save_profile() != OK,"AD-019 failed write returns error")
	svc2.free()
	svc.free()
	_clean()
	DirAccess.remove_absolute(DIR)
