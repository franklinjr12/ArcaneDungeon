extends RefCounted
## AD-187: Show FPS setting persistence and overlay text.
const Settings = preload("res://game/core/settings.gd")
const PerfOverlay = preload("res://debug/perf_overlay.gd")

func run(t) -> void:
	var s = Settings.new()
	t.check(not s.show_fps, "AD-187 show_fps defaults false")
	s.show_fps = true
	var cfg := ConfigFile.new()
	s.to_config(cfg)
	var r = Settings.new()
	r.from_config(cfg)
	t.check(r.show_fps, "AD-187 show_fps round trips")
	cfg.set_value("display", "show_fps", "yes")
	r.from_config(cfg)
	t.check(not r.show_fps, "AD-187 non-bool show_fps falls back to false")
	var line: String = PerfOverlay.format_stats(60.0, 16.4, 2.1, 12, 34)
	for n in ["60", "16.4", "2.1", "12", "34"]:
		t.check(line.contains(n), "AD-187 format_stats contains " + n)
