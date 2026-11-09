extends CanvasLayer
## AD-187: 'Show FPS' readout (bottom-left). Polls settings.show_fps every frame so the pause-menu toggle applies at once.
const CONFIG_PATH := "res://game/data/perf_run_v1.json"
const MARGIN := 6
const FORMAT := "FPS %d | frame %.1f ms | sim %.1f ms | enemies %d | effects %d"

var settings
var source
var label: Label
var _refresh_ms := 250
var _next_ms := 0

static func format_stats(fps: float, frame_ms: float, sim_ms: float, enemies: int, effects: int) -> String:
	return FORMAT % [roundi(fps), frame_ms, sim_ms, enemies, effects]

func _init() -> void:
	layer = 100
	label = Label.new()
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	label.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_LEFT)
	label.grow_vertical = Control.GROW_DIRECTION_BEGIN
	label.offset_left = MARGIN
	label.offset_bottom = -MARGIN
	label.add_theme_font_size_override("font_size", 12)
	label.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.9))
	label.add_theme_constant_override("outline_size", 4)
	add_child(label)
	visible = false
	var f := FileAccess.open(CONFIG_PATH, FileAccess.READ)
	if f != null:
		var d = JSON.parse_string(f.get_as_text())
		if typeof(d) == TYPE_DICTIONARY:
			_refresh_ms = int(d.get("overlay_refresh_ms", _refresh_ms))

func _process(delta: float) -> void:
	var on: bool = settings != null and settings.show_fps
	visible = on
	if not on:
		return
	var now := Time.get_ticks_msec()
	if now < _next_ms:
		return
	_next_ms = now + _refresh_ms
	var stats: Dictionary = source.perf_stats() if source != null and source.has_method("perf_stats") else {}
	label.text = format_stats(Engine.get_frames_per_second(), delta * 1000.0, float(stats.get("sim_ms", 0.0)),
		int(stats.get("enemies", 0)), int(stats.get("effects", 0)))
