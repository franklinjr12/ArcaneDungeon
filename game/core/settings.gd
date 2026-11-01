extends RefCounted
## AD-019: player settings model (audio volumes per bus, accessibility toggles, telemetry opt-in).
const BUSES := ["Master", "SFX", "Ambience", "UI"]
const DEFAULTS := {
	"volumes": {"Master": 1.0, "SFX": 1.0, "Ambience": 1.0, "UI": 1.0},
	"reduce_flashes": false,
	"screen_shake": true,
	"telemetry_opt_in": false,
	"schema_version": 1,
}

var volumes: Dictionary = {}
var reduce_flashes: bool = false
var screen_shake: bool = true
var telemetry_opt_in: bool = false

func _init() -> void:
	reset()

static func defaults() -> Dictionary:
	return DEFAULTS.duplicate(true)

func reset() -> void:
	var d := defaults()
	volumes = d["volumes"]
	reduce_flashes = d["reduce_flashes"]
	screen_shake = d["screen_shake"]
	telemetry_opt_in = d["telemetry_opt_in"]

func to_config(cfg: ConfigFile) -> void:
	cfg.set_value("meta", "schema_version", DEFAULTS["schema_version"])
	for bus in volumes:
		cfg.set_value("audio", str(bus), clampf(float(volumes[bus]), 0.0, 1.0))
	cfg.set_value("accessibility", "reduce_flashes", reduce_flashes)
	cfg.set_value("accessibility", "screen_shake", screen_shake)
	cfg.set_value("privacy", "telemetry_opt_in", telemetry_opt_in)

func from_config(cfg: ConfigFile) -> void:
	reset()
	for bus in cfg.get_section_keys("audio") if cfg.has_section("audio") else PackedStringArray():
		var v = cfg.get_value("audio", bus, "")
		if typeof(v) == TYPE_FLOAT or typeof(v) == TYPE_INT:
			volumes[bus] = clampf(float(v), 0.0, 1.0)
	reduce_flashes = _bool(cfg, "accessibility", "reduce_flashes", reduce_flashes)
	screen_shake = _bool(cfg, "accessibility", "screen_shake", screen_shake)
	telemetry_opt_in = _bool(cfg, "privacy", "telemetry_opt_in", telemetry_opt_in)

static func _bool(cfg: ConfigFile, section: String, key: String, fallback: bool) -> bool:
	var v = cfg.get_value(section, key, "")
	return v if typeof(v) == TYPE_BOOL else fallback

func apply_audio() -> void:
	for bus in volumes:
		var idx := AudioServer.get_bus_index(str(bus))
		if idx >= 0:
			AudioServer.set_bus_volume_db(idx, linear_to_db(float(volumes[bus])))
