extends RefCounted
## AD-148: lighting quality setting (High/Low/Off) defaults, persistence and validation.
const Settings = preload("res://game/core/settings.gd")
const Lighting = preload("res://ui/lighting.gd")
const Canvas = preload("res://ui/combat_canvas.gd")
const Flow = preload("res://world/run_flow.gd")
const Driver = preload("res://tests/m3_run_driver.gd")
const SEED := 20261022

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
	_data_checks(t)
	_functional(t)
	_determinism(t)

func _data_checks(t) -> void:
	var d := Lighting.load_data()
	t.equal(int(d.get("version", 0)), 1, "AD-148 lighting_v1 parses, version 1")
	for k in ["ruins", "ruins_boss", "cistern", "cistern_boss"]:
		t.check(d.get("ambient", {}).has(k), "AD-148 ambient key " + k)
	t.equal(int(d["modes"]["high"]["spell_light_cap"]), 24, "AD-148 high cap is 24")
	t.check(int(d["modes"]["low"]["spell_light_cap"]) <= 24, "AD-148 low cap <= high")
	t.equal(int(d["modes"]["off"]["spell_light_cap"]), 0, "AD-148 off cap is 0")
	t.equal(Lighting.biome_key(0, "combat"), "ruins", "AD-148 biome ruins")
	t.equal(Lighting.biome_key(0, "boss"), "ruins_boss", "AD-148 biome ruins boss")
	t.equal(Lighting.biome_key(1, "combat"), "cistern", "AD-148 biome cistern")
	t.equal(Lighting.biome_key(2, "boss"), "cistern_boss", "AD-148 biome cistern boss")
	t.equal(Lighting.mode_config("bogus"), Lighting.mode_config("high"), "AD-148 unknown mode falls back to high")

func _make_canvas(flow, mode: String):
	var canvas = Canvas.new()
	var s := Settings.new()
	s.lighting = mode
	canvas.settings = s
	canvas.session = flow.session
	canvas.size = Vector2(916, 650)
	(Engine.get_main_loop() as SceneTree).root.add_child(canvas)
	return canvas

func _sync(canvas, flow, stage: int = 0, room_type: String = "combat", props: Array = []) -> void:
	canvas.lighting.sync(canvas, flow.session, canvas.settings, stage, room_type, props)

func _functional(t) -> void:
	var flow = Flow.new(SEED)
	var canvas = _make_canvas(flow, "high")
	var lighting = canvas.lighting
	t.equal(lighting.pool_size(), 24, "AD-148 pool sized to the high cap")
	t.equal(canvas.light_mask, Lighting.arena_mask(), "AD-148 arena canvas on the arena light mask")
	t.equal(canvas.slot_hud.light_mask, 0, "AD-148 slot HUD never lit")
	for i in 30:
		flow.session.sim.visuals.append({"kind": "burst", "position": Vector2(300 + i * 10, 400), "essence": "essence.fire", "until": 99999})
	t.equal(Lighting.spell_light_sources(flow.session).size(), 30, "AD-148 sources keep sim order, uncapped")
	for mode in [["high", 24], ["low", int(Lighting.mode_config("low")["spell_light_cap"])], ["off", 0]]:
		canvas.settings.lighting = mode[0]
		for n in 3:
			_sync(canvas, flow, 0, "combat", [["brazier", 400, 450]])
		t.equal(lighting.active_spell_lights(), mode[1], "AD-148 %s spell lights capped at %d" % [mode[0], mode[1]])
		t.equal(lighting.pool_size(), 24, "AD-148 pool does not grow on " + mode[0])
		t.equal(lighting._ambient.visible, mode[0] != "off", "AD-148 ambient visibility on " + mode[0])
		var prop_visible := false
		for l in lighting._room_lights:
			prop_visible = prop_visible or l.visible
		t.equal(prop_visible, mode[0] != "off", "AD-148 prop lights visibility on " + mode[0])
	canvas.settings.lighting = "high"
	_sync(canvas, flow, 1, "boss")
	t.equal(lighting._room_lights.size(), 5, "AD-148 cistern boss: 4 fixed lights + boss fill")
	lighting.hide_all()
	t.equal(lighting.active_spell_lights(), 0, "AD-148 hide_all clears spell lights")
	canvas.queue_free()

func _run_ticks(flow, canvas) -> Array:
	var on_tick := func(_f): canvas.lighting.sync(canvas, flow.session, canvas.settings, 0, "combat", [["brazier", 400, 450]])
	Driver.fight(flow, 400, on_tick)
	return [flow.session.sim.trace_json(), flow.session.sim.clock.tick, flow.session.sim.clock._rng.state]

func _determinism(t) -> void:
	var a = Flow.new(SEED)
	var ca = _make_canvas(a, "high")
	var b = Flow.new(SEED)
	var cb = _make_canvas(b, "off")
	var ra := _run_ticks(a, ca)
	var rb := _run_ticks(b, cb)
	t.check(ra[1] > 0, "AD-148 determinism run advanced ticks")
	t.check(ra == rb, "AD-148 sim trace/tick/RNG identical with lighting high vs off")
	ca.queue_free()
	cb.queue_free()
