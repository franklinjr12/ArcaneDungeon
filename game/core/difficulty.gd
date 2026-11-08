extends RefCounted
## Central difficulty multipliers (AD-126). Every multiplier at 1.0 returns inputs untouched,
## so the simulation stays byte-identical to the unscaled values.
const FILE := "res://game/data/difficulty_v1.json"
## Test-only path override; changing it drops the cached preset.
static var file_override := "":
	set(value):
		file_override = value
		_loaded = false
static var _preset: Dictionary = {}
static var _loaded := false
static var _override: Dictionary = {}

static func _load() -> void:
	if _loaded:
		return
	_loaded = true
	_preset = {}
	var file := FileAccess.open(file_override if not file_override.is_empty() else FILE,FileAccess.READ)
	var parsed = JSON.parse_string(file.get_as_text()) if file != null else null
	if not (parsed is Dictionary) or not (parsed.get("presets") is Dictionary) or not (parsed["presets"].get(str(parsed.get("active",""))) is Dictionary):
		push_error("Difficulty: invalid or missing %s; using 1.0 multipliers" % FILE)
		return
	_preset = parsed["presets"][str(parsed["active"])]

static func mult(key: String) -> float:
	if _override.has(key):
		return float(_override[key])
	_load()
	return float(_preset.get(key,1.0))

static func scale_f(value: float, key: String) -> float:
	var m := mult(key)
	return value if m == 1.0 else value*m

static func scale_i(value: int, key: String, minimum: int = 1) -> int:
	var m := mult(key)
	return value if m == 1.0 else maxi(minimum,roundi(value*m))

static func set_override(values: Dictionary) -> void:
	_override = values.duplicate()

static func clear_override() -> void:
	_override = {}
