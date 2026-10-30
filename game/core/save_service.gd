extends Node
## AD-019: autoload SaveService. Settings (user://settings.cfg) and local stats (user://profile.json):
## versioned, atomic writes, corrupt files are quarantined and replaced by defaults.
const Settings = preload("res://game/core/settings.gd")
const ErrorLog = preload("res://game/core/error_log.gd")
const SCHEMA_VERSION := 1
const SETTINGS_FILE := "settings.cfg"
const PROFILE_FILE := "profile.json"
const DEFAULT_STATS := {"runs": 0, "wins": 0, "deaths": 0, "best_time_seconds": -1.0, "last_seed": -1}

var base_dir := "user://"
var settings = Settings.new()
var profile: Dictionary = default_profile()

func _ready() -> void:
	load_all()
	settings.apply_audio()

static func default_profile() -> Dictionary:
	return {"schema_version": SCHEMA_VERSION, "stats": DEFAULT_STATS.duplicate(true)}

func set_base_dir(dir: String) -> void:
	base_dir = dir if dir.ends_with("/") else dir + "/"
	DirAccess.make_dir_recursive_absolute(base_dir)
	load_all()

func _path(file: String) -> String:
	return base_dir + file

func load_all() -> void:
	load_settings()
	load_profile()

func load_settings() -> void:
	settings = Settings.new()
	var path := _path(SETTINGS_FILE)
	if not FileAccess.file_exists(path):
		return
	var cfg := ConfigFile.new()
	if cfg.load(path) != OK:
		_quarantine(path)
		return
	settings.from_config(cfg)

func load_profile() -> void:
	profile = default_profile()
	var path := _path(PROFILE_FILE)
	if not FileAccess.file_exists(path):
		return
	var json := JSON.new()  # instance parse: no engine ERROR line on bad input
	var parsed = json.data if json.parse(FileAccess.get_file_as_string(path)) == OK else null
	if typeof(parsed) != TYPE_DICTIONARY or int(parsed.get("schema_version", 0)) > SCHEMA_VERSION:
		_quarantine(path)
		return
	var migrated := migrate(parsed)
	if not _valid_profile(migrated):
		_quarantine(path)
		return
	profile = migrated

static func migrate(data: Dictionary) -> Dictionary:
	var d := data.duplicate(true)
	var version := int(d.get("schema_version", 0))
	while version < SCHEMA_VERSION:
		match version:
			0: d = _migrate_v0_to_v1(d)
			_: break
		version = int(d.get("schema_version", version + 1))
	return d

static func _migrate_v0_to_v1(d: Dictionary) -> Dictionary:
	var stats: Dictionary = d["stats"].duplicate() if typeof(d.get("stats")) == TYPE_DICTIONARY else {}
	for key in ["runs", "wins", "deaths", "last_seed"]:
		if d.has(key):
			stats[key] = d[key]
	if d.has("best_time"):
		stats["best_time_seconds"] = d["best_time"]
	for key in DEFAULT_STATS:
		if not stats.has(key):
			stats[key] = DEFAULT_STATS[key]
	return {"schema_version": 1, "stats": stats}

static func _is_num(v) -> bool:
	return typeof(v) == TYPE_INT or typeof(v) == TYPE_FLOAT

static func _valid_profile(p: Dictionary) -> bool:
	if int(p.get("schema_version", -1)) != SCHEMA_VERSION or typeof(p.get("stats")) != TYPE_DICTIONARY:
		return false
	var s: Dictionary = p["stats"]
	for key in ["runs", "wins", "deaths"]:
		if not _is_num(s.get(key)) or float(s[key]) < 0.0 or float(s[key]) != floorf(float(s[key])):
			return false
		s[key] = int(s[key])
	if not _is_num(s.get("last_seed")) or not _is_num(s.get("best_time_seconds")):
		return false
	s["last_seed"] = int(s["last_seed"])
	s["best_time_seconds"] = float(s["best_time_seconds"])
	return s["wins"] <= s["runs"] and (s["best_time_seconds"] >= 0.0 or s["best_time_seconds"] == -1.0)

func save_settings() -> Error:
	var cfg := ConfigFile.new()
	settings.to_config(cfg)
	return _atomic_write(_path(SETTINGS_FILE), cfg.encode_to_text())

func save_profile() -> Error:
	return _atomic_write(_path(PROFILE_FILE), JSON.stringify(profile, "\t"))

func _atomic_write(path: String, text: String) -> Error:
	var tmp := path + ".tmp"
	var file := FileAccess.open(tmp, FileAccess.WRITE)
	if file == null:
		return FileAccess.get_open_error()
	file.store_string(text)
	file.flush()
	var err := file.get_error()
	file.close()
	if err == OK:
		err = DirAccess.rename_absolute(tmp, path)
		if err != OK and FileAccess.file_exists(path):
			DirAccess.remove_absolute(path)
			err = DirAccess.rename_absolute(tmp, path)
	if err != OK and FileAccess.file_exists(tmp):
		DirAccess.remove_absolute(tmp)
	return err

func _quarantine(path: String) -> void:
	var stamp := int(Time.get_unix_time_from_system())
	var dest := "%s.corrupt-%d" % [path, stamp]
	var n := 1
	while FileAccess.file_exists(dest):
		dest = "%s.corrupt-%d-%d" % [path, stamp, n]
		n += 1
	DirAccess.copy_absolute(path, dest)
	DirAccess.remove_absolute(path)
	ErrorLog.record("SAVE_CORRUPT_QUARANTINED", path)

func record_run(summary: Dictionary) -> void:
	var s: Dictionary = profile["stats"]
	s["runs"] += 1
	if summary.get("outcome", "") == "won":
		s["wins"] += 1
		var secs := float(summary.get("seconds", 0.0))
		if s["best_time_seconds"] < 0.0 or secs < s["best_time_seconds"]:
			s["best_time_seconds"] = secs
	elif summary.get("outcome", "") == "lost":
		s["deaths"] += 1
	s["last_seed"] = int(summary.get("seed", -1))
	save_profile()

func stats() -> Dictionary:
	return profile["stats"].duplicate()
