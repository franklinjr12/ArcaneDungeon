extends RefCounted
## AD-019: player settings model (audio volumes per bus, accessibility toggles, telemetry opt-in).
const InputActions = preload("res://ui/input_actions.gd")
const BUSES := ["Master", "SFX", "Ambience", "UI", "Music", "EnemySFX"]
const WINDOW_MODES := ["windowed", "fullscreen", "borderless"]
const UI_SCALE_MIN := 0.9
const UI_SCALE_MAX := 1.5
const UI_SCALE_STEP := 0.1
const LIGHTING_MODES := ["high", "low", "off"]
const FRAME_LIMITS := [0, 30, 60, 120]
const DEFAULTS := {
	"volumes": {"Master": 1.0, "SFX": 1.0, "Ambience": 1.0, "UI": 1.0, "Music": 1.0, "EnemySFX": 1.0},
	"reduce_flashes": false,
	"screen_shake": true,
	"telemetry_opt_in": false,
	"tips_enabled": true,
	"window_mode": "windowed",
	"lighting": "high",
	"show_fps": false,
	"ui_scale": 1.0,
	"mute_unfocused": false,
	"vsync": true,
	"frame_limit": 0,
	"schema_version": 1,
}

var volumes: Dictionary = {}
var reduce_flashes: bool = false
var screen_shake: bool = true
var telemetry_opt_in: bool = false
var tips_enabled: bool = true
var window_mode: String = "windowed"
var lighting: String = "high"
var show_fps: bool = false
var ui_scale: float = 1.0
var mute_unfocused: bool = false
var vsync: bool = true
## 0 = unlimited.
var frame_limit: int = 0
## action -> Array of event dicts (InputActions.event_to_dict); empty means project defaults.
var bindings: Dictionary = {}

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
	tips_enabled = d["tips_enabled"]
	window_mode = d["window_mode"]
	lighting = d["lighting"]
	show_fps = d["show_fps"]
	ui_scale = d["ui_scale"]
	mute_unfocused = d["mute_unfocused"]
	vsync = d["vsync"]
	frame_limit = d["frame_limit"]
	bindings = {}

func to_config(cfg: ConfigFile) -> void:
	cfg.set_value("meta", "schema_version", DEFAULTS["schema_version"])
	for bus in volumes:
		cfg.set_value("audio", str(bus), clampf(float(volumes[bus]), 0.0, 1.0))
	cfg.set_value("accessibility", "reduce_flashes", reduce_flashes)
	cfg.set_value("accessibility", "screen_shake", screen_shake)
	cfg.set_value("privacy", "telemetry_opt_in", telemetry_opt_in)
	cfg.set_value("accessibility", "tips_enabled", tips_enabled)
	cfg.set_value("display", "window_mode", window_mode)
	cfg.set_value("display", "lighting", lighting)
	cfg.set_value("display", "show_fps", show_fps)
	cfg.set_value("display", "ui_scale", snap_ui_scale(ui_scale))
	cfg.set_value("accessibility", "mute_unfocused", mute_unfocused)
	cfg.set_value("display", "vsync", vsync)
	cfg.set_value("display", "frame_limit", frame_limit)
	for action in bindings:
		cfg.set_value("controls", str(action), bindings[action])

func from_config(cfg: ConfigFile) -> void:
	reset()
	for bus in cfg.get_section_keys("audio") if cfg.has_section("audio") else PackedStringArray():
		var v = cfg.get_value("audio", bus, "")
		if typeof(v) == TYPE_FLOAT or typeof(v) == TYPE_INT:
			volumes[bus] = clampf(float(v), 0.0, 1.0)
	reduce_flashes = _bool(cfg, "accessibility", "reduce_flashes", reduce_flashes)
	screen_shake = _bool(cfg, "accessibility", "screen_shake", screen_shake)
	telemetry_opt_in = _bool(cfg, "privacy", "telemetry_opt_in", telemetry_opt_in)
	tips_enabled = _bool(cfg, "accessibility", "tips_enabled", tips_enabled)
	show_fps = _bool(cfg, "display", "show_fps", show_fps)
	mute_unfocused = _bool(cfg, "accessibility", "mute_unfocused", mute_unfocused)
	vsync = _bool(cfg, "display", "vsync", vsync)
	var limit = cfg.get_value("display", "frame_limit", "")
	if typeof(limit) == TYPE_INT and limit in FRAME_LIMITS:
		frame_limit = limit
	var mode = cfg.get_value("display", "window_mode", "")
	if typeof(mode) == TYPE_STRING and mode in WINDOW_MODES:
		window_mode = mode
	var light = cfg.get_value("display", "lighting", "")
	if typeof(light) == TYPE_STRING and light in LIGHTING_MODES:
		lighting = light
	var scale = cfg.get_value("display", "ui_scale", "")
	if typeof(scale) == TYPE_FLOAT or typeof(scale) == TYPE_INT:
		ui_scale = snap_ui_scale(float(scale))
	for action in cfg.get_section_keys("controls") if cfg.has_section("controls") else PackedStringArray():
		var v = cfg.get_value("controls", action, null)
		if action in InputActions.REBINDABLE and typeof(v) == TYPE_ARRAY and not v.is_empty() and _all_decode(v):
			bindings[action] = v

static func _all_decode(entries: Array) -> bool:
	for d in entries:
		if typeof(d) != TYPE_DICTIONARY or InputActions.dict_to_event(d) == null:
			return false
	return true

static func snap_ui_scale(v: float) -> float:
	if is_nan(v) or is_inf(v):
		return DEFAULTS["ui_scale"]
	return snappedf(clampf(v, UI_SCALE_MIN, UI_SCALE_MAX), UI_SCALE_STEP)

static func _bool(cfg: ConfigFile, section: String, key: String, fallback: bool) -> bool:
	var v = cfg.get_value(section, key, "")
	return v if typeof(v) == TYPE_BOOL else fallback

func apply_audio() -> void:
	for bus in volumes:
		var idx := AudioServer.get_bus_index(str(bus))
		if idx >= 0:
			AudioServer.set_bus_volume_db(idx, linear_to_db(float(volumes[bus])))

func apply_bindings() -> void:
	InputActions.apply_bindings(bindings)

## Test seam: when set, receives set_mode/set_borderless/set_size/set_position/get_mode/is_borderless/
## screen_position/screen_size calls instead of the real DisplayServer (and is used even when headless).
var display = null

## Flips fullscreen <-> windowed ('borderless' goes to fullscreen).
func toggle_fullscreen() -> void:
	window_mode = "windowed" if window_mode == "fullscreen" else "fullscreen"

## Applies UI scale, frame limit, window mode and vsync. Never resizes a windowed window (keeps `--resolution WxH`
## runs intact) except when leaving borderless/fullscreen, which restores the project window size.
func apply_display(window: Window) -> void:
	if window != null:
		window.content_scale_factor = snap_ui_scale(ui_scale)
	Engine.max_fps = frame_limit
	var backend = display
	if backend == null:
		if DisplayServer.get_name() == "headless":
			return
		DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_ENABLED if vsync else DisplayServer.VSYNC_DISABLED)
		backend = _RealDisplay.new(window)
	var current: int = backend.get_mode()
	var borderless := window_mode == "borderless"
	var was_borderless: bool = backend.is_borderless()
	var fullscreen := window_mode == "fullscreen"
	var want := DisplayServer.WINDOW_MODE_FULLSCREEN if fullscreen else DisplayServer.WINDOW_MODE_WINDOWED
	var was_fullscreen := current == DisplayServer.WINDOW_MODE_FULLSCREEN
	if fullscreen and was_borderless:
		backend.set_borderless(false)
		was_borderless = false
	if current != want:
		backend.set_mode(want)
	if was_borderless != borderless:
		backend.set_borderless(borderless)
	if want != DisplayServer.WINDOW_MODE_WINDOWED:
		return
	var spos: Vector2i = backend.screen_position()
	var ssize: Vector2i = backend.screen_size()
	if borderless:
		backend.set_position(spos)
		backend.set_size(ssize)
	elif was_borderless or was_fullscreen:
		var size := Vector2i(int(ProjectSettings.get_setting("display/window/size/viewport_width")),
				int(ProjectSettings.get_setting("display/window/size/viewport_height")))
		backend.set_size(size)
		backend.set_position(spos + (ssize - size) / 2)

## Real window backend: prefers the root Window's mode so the Window node cannot revert a DisplayServer change.
class _RealDisplay:
	var win: Window
	func _init(w: Window) -> void:
		win = w
	func get_mode() -> int:
		return win.mode if win != null else DisplayServer.window_get_mode()
	func is_borderless() -> bool:
		return DisplayServer.window_get_flag(DisplayServer.WINDOW_FLAG_BORDERLESS)
	func set_mode(m: int) -> void:
		if win != null:
			win.mode = Window.MODE_FULLSCREEN if m == DisplayServer.WINDOW_MODE_FULLSCREEN else Window.MODE_WINDOWED
		else:
			DisplayServer.window_set_mode(m)
	func set_borderless(b: bool) -> void:
		DisplayServer.window_set_flag(DisplayServer.WINDOW_FLAG_BORDERLESS, b)
	func set_size(v: Vector2i) -> void:
		DisplayServer.window_set_size(v)
	func set_position(v: Vector2i) -> void:
		DisplayServer.window_set_position(v)
	func screen_position() -> Vector2i:
		return DisplayServer.screen_get_position(DisplayServer.window_get_current_screen())
	func screen_size() -> Vector2i:
		return DisplayServer.screen_get_size(DisplayServer.window_get_current_screen())
