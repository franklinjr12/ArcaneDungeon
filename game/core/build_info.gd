extends RefCounted
## AD-157: version/build stamp for the title screen and tester logs. Data only, no sim access.

static func version() -> String:
	return str(ProjectSettings.get_setting("application/config/version", "0.0.0"))

static func stamp() -> String:
	return str(ProjectSettings.get_setting("application/config/build_stamp", "dev"))

static func platform() -> String:
	return OS.get_name()

static func label() -> String:
	return "v%s (%s, %s)" % [version(), stamp(), "debug" if OS.is_debug_build() else "release"]

static func as_dict() -> Dictionary:
	return {"version": version(), "build_stamp": stamp(), "platform": platform(), "debug": OS.is_debug_build()}
