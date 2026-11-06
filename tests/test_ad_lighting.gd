extends RefCounted
## AD-148: lighting quality setting (High/Low/Off) defaults, persistence and validation.
const Settings = preload("res://game/core/settings.gd")

func _load(value) -> Settings:
	var cfg := ConfigFile.new()
	if value != null:
		cfg.set_value("display", "lighting", value)
	var s := Settings.new()
	s.from_config(cfg)
	return s

func run(t) -> void:
	t.equal(Settings.LIGHTING_MODES, ["high", "low", "off"], "AD-148 lighting modes")
	t.equal(Settings.new().lighting, "high", "AD-148 lighting defaults to high")
	for m in ["low", "off"]:
		var s := Settings.new()
		s.lighting = m
		var cfg := ConfigFile.new()
		s.to_config(cfg)
		var back := Settings.new()
		back.from_config(cfg)
		t.equal(back.lighting, m, "AD-148 lighting %s round-trips" % m)
	t.equal(_load("ultra").lighting, "high", "AD-148 invalid string falls back")
	t.equal(_load(3).lighting, "high", "AD-148 non-string falls back")
	t.equal(_load(null).lighting, "high", "AD-148 missing key loads high")
