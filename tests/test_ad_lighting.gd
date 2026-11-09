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
	_readability(t)

func _data_checks(t) -> void:
	var d := Lighting.load_data()
	t.equal(int(d.get("version", 0)), 1, "AD-148 lighting_v1 parses, version 1")
	var spell := {"projectile": [0.9, 0.8], "orb": [0.8, 0.9], "field": [0.6, 1.6], "burst": [1.2, 1.6]}
	for k in ["ruins", "ruins_boss", "cistern", "cistern_boss", "workshop"]:
		t.check(d.get("stages", {}).has(k), "AD-165 stage key " + k)
		var sl: Dictionary = Lighting.stage_config(k).get("spell_lights", {})
		for kind in spell:
			t.check(sl.has(kind) and is_equal_approx(float(sl[kind]["energy"]), spell[kind][0]) and is_equal_approx(float(sl[kind]["texture_scale"]), spell[kind][1]), "AD-165 %s spell light %s unchanged" % [k, kind])
	t.equal(d["modes"]["off"]["player_light"], false, "AD-165 off mode has no player light")
	t.equal(Lighting.biome_key(1, "workshop"), "workshop", "AD-165 biome workshop")
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
		t.equal(lighting._player.visible, mode[0] != "off", "AD-165 player light visibility on " + mode[0])
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

const TEX := "res://assets/pixel/"

static func _lum(c: Color) -> float:
	return 0.2126 * c.r + 0.7152 * c.g + 0.0722 * c.b

static func _mean_color(path: String) -> Color:
	var file := ProjectSettings.globalize_path(path)
	var img: Image = Image.load_from_file(file)
	if img == null:
		img = (load(path) as Texture2D).get_image()
	var sum := Vector3.ZERO
	var n := 0
	for y in img.get_height():
		for x in img.get_width():
			var c := img.get_pixel(x, y)
			if c.a > 0.5:
				sum += Vector3(c.r, c.g, c.b)
				n += 1
	return Color(sum.x / n, sum.y / n, sum.z / n) if n > 0 else Color.WHITE

func _enter(flow, index: int) -> void:
	flow.run.sequence_index = index
	flow._enter_current()

func _readability(t) -> void:
	var cfg: Dictionary = Lighting.load_data()["readability"]
	var min_fraction := float(cfg["min_fraction"])
	var step := float(cfg["sample_step_px"])
	var floor_color := _mean_color(TEX + "dungeon_tiles.png")
	var enemy_color := Color(0, 0, 0)
	var sheets := ["pursuer_sheet.png", "ranged_sheet.png", "flanker_sheet.png", "boss_sheet.png"]
	for s in sheets:
		var c := _mean_color(TEX + s)
		enemy_color += Color(c.r / sheets.size(), c.g / sheets.size(), c.b / sheets.size())
	var floor_u := _lum(floor_color)
	var enemy_u := _lum(enemy_color)
	t.check(floor_u > 0.0 and enemy_u > 0.0, "AD-165 unlit luminance sampled")
	for k in ["ruins", "ruins_boss", "cistern", "cistern_boss"]:
		var f := Lighting.ambient_factor(k)
		for u in [["floor", floor_color, floor_u], ["enemy", enemy_color, enemy_u]]:
			var ratio: float = _lum(Color(u[1].r * f.r, u[1].g * f.g, u[1].b * f.b)) / u[2]
			t.check(ratio >= min_fraction, "AD-165 ambient-only %s %s ratio %.2f >= %.2f" % [k, u[0], ratio, min_fraction])
	var flow = Flow.new(SEED, Flow.CONFIG_V2)
	for stage in [0, 1]:
		for rtype in ["combat", "boss"]:
			var idx := -1
			for i in flow.rooms.size():
				if int(flow.rooms[i].get("stage", -1)) == stage and str(flow.rooms[i].get("type", "")) == rtype:
					idx = i
					break
			t.check(idx >= 0, "AD-165 scripted %s room for stage %d exists" % [rtype, stage])
			if idx < 0:
				continue
			_enter(flow, idx)
			if flow.session.enemies.is_empty():
				Driver.fight(flow, 30)
			var key := Lighting.biome_key(stage, rtype)
			var props: Array = flow.room.values.get("layout", {}).get("props", [])
			var bounds: Rect2 = flow.session.world.bounds
			var player := _far_corner(bounds, props)
			var worst := INF
			var where := ""
			var y := bounds.position.y
			while y <= bounds.end.y:
				var x := bounds.position.x
				while x <= bounds.end.x:
					var f := Lighting.light_factor_at(key, Vector2(x, y), props, bounds, player)
					var r := _lum(Color(floor_color.r * f.r, floor_color.g * f.g, floor_color.b * f.b)) / floor_u
					if r < worst:
						worst = r
						where = "floor %s" % Vector2(x, y)
					x += step
				y += step
			for e in flow.session.enemies:
				var p: Vector2 = e.target.position
				var f := Lighting.light_factor_at(key, p, props, bounds, player)
				var r := _lum(Color(enemy_color.r * f.r, enemy_color.g * f.g, enemy_color.b * f.b)) / enemy_u
				if r < worst:
					worst = r
					where = "enemy %s" % p
			t.check(worst >= min_fraction, "AD-165 %s stage %d darkest %s ratio %.2f >= %.2f" % [rtype, stage, where, worst, min_fraction])

func _far_corner(bounds: Rect2, props: Array) -> Vector2:
	var best := bounds.position
	var best_d := -1.0
	for corner in [bounds.position, Vector2(bounds.end.x, bounds.position.y), Vector2(bounds.position.x, bounds.end.y), bounds.end]:
		var nearest := INF
		for p in props:
			if p is Array and p.size() >= 3:
				nearest = minf(nearest, corner.distance_to(Vector2(float(p[1]), float(p[2]))))
		if nearest > best_d:
			best_d = nearest
			best = corner
	return best
