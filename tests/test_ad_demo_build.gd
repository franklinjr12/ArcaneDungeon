extends RefCounted
## AD-157: build stamp + opt-in local session/crash logs.
const BuildInfo = preload("res://game/core/build_info.gd")
const Log = preload("res://debug/experiment_log.gd")
const DIR := "user://ad157_test_logs"
const LOCK := "user://ad157_test.lock"

func _files() -> Array:
	var out: Array = []
	var d := DirAccess.open(DIR)
	if d != null:
		for f in d.get_files():
			out.append(f)
	return out

func _clean() -> void:
	for f in _files():
		DirAccess.remove_absolute(ProjectSettings.globalize_path(DIR + "/" + f))
	DirAccess.remove_absolute(ProjectSettings.globalize_path(DIR))
	DirAccess.remove_absolute(ProjectSettings.globalize_path(LOCK))

func run(t) -> void:
	_clean()
	t.check(BuildInfo.label() != "" and BuildInfo.label().contains(BuildInfo.version()), "AD-157 build label contains version")
	var off = Log.new()
	off.begin_session(LOCK, DIR)
	off.end_session(LOCK, DIR)
	t.equal(off.write_session_log(DIR), ERR_UNAVAILABLE, "AD-157 disabled log refuses to write")
	t.equal(_files().size(), 0, "AD-157 disabled log writes no files")
	t.check(not FileAccess.file_exists(LOCK), "AD-157 disabled log writes no lock")
	var on = Log.new()
	on.configure(true)
	on.begin_session(LOCK, DIR)
	on.end_session(LOCK, DIR)
	var sessions: Array = _files().filter(func(f): return f.begins_with("session_") and f.ends_with(".json"))
	t.equal(sessions.size(), 1, "AD-157 enabled end_session writes one session json")
	if sessions.size() == 1:
		var parsed = JSON.parse_string(FileAccess.get_file_as_string(DIR + "/" + sessions[0]))
		t.check(parsed is Dictionary and parsed.has("build") and parsed["build"].has("version"), "AD-157 session json has build.version")
	_clean()
	FileAccess.open(LOCK, FileAccess.WRITE).store_string("1")
	var crashed = Log.new()
	crashed.configure(true)
	crashed.begin_session(LOCK, DIR)
	t.equal(_files().filter(func(f): return f.begins_with("crash_")).size(), 1, "AD-157 stale lock writes crash log")
	_clean()
	FileAccess.open(LOCK, FileAccess.WRITE).store_string("1")
	var quiet = Log.new()
	quiet.begin_session(LOCK, DIR)
	t.equal(_files().size(), 0, "AD-157 stale lock with logging off writes nothing")
	_clean()
