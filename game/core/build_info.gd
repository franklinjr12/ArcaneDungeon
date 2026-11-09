extends RefCounted
## AD-157: version/build stamp for the title screen and tester logs. Data only, no sim access.

const FILE := "res://game/data/demo_v1.json"
static var _version := ""
static var _loaded := false

static func version() -> String:
	if not _loaded:
		_loaded = true
		var file := FileAccess.open(FILE, FileAccess.READ)
		var parsed = JSON.parse_string(file.get_as_text()) if file != null else null
		if parsed is Dictionary and parsed.get("version") is String and not parsed["version"].is_empty():
			_version = parsed["version"]
	if not _version.is_empty():
		return _version
	return str(ProjectSettings.get_setting("application/config/version", "0.0.0"))

static func stamp() -> String:
	return str(ProjectSettings.get_setting("application/config/build_stamp", "dev"))

static func platform() -> String:
	return OS.get_name()

static func label() -> String:
	return "v%s (%s, %s)" % [version(), stamp(), "debug" if OS.is_debug_build() else "release"]

static func as_dict() -> Dictionary:
	return {"version": version(), "build_stamp": stamp(), "platform": platform(), "debug": OS.is_debug_build()}
