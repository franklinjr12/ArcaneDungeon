extends RefCounted
## AD-088: telegraph alpha/tint come from world/data/presentation_v1.json and stay in design ranges.
const Art = preload("res://ui/pixel_art_renderer.gd")
const RM = preload("res://ui/reduce_motion.gd")
const Flow = preload("res://world/run_flow.gd")
const Driver = preload("res://tests/m3_run_driver.gd")
const Canvas = preload("res://ui/combat_canvas.gd")
const EVENTS := ["telegraph.circle", "telegraph.line", "telegraph.dash_lane"]

func run(t) -> void:
	var data = JSON.parse_string(FileAccess.get_file_as_string("res://world/data/presentation_v1.json"))
	t.check(data is Dictionary and int(data.get("version", 0)) == 1, "presentation_v1 parses, version 1")
	if not (data is Dictionary):
		return
	for ev in EVENTS:
		var st: Dictionary = data["telegraph_style"].get(ev, {})
		t.check(not st.is_empty(), "%s in telegraph_style" % ev)
		if st.is_empty():
			continue
		var tint := Color(String(st["tint"]))
		var pk: Dictionary = st["pulse"]
		for p in [0.0, 0.5, 0.74]:
			var c := Art.telegraph_colors(ev, p)
			t.check(is_equal_approx(c["fill"].a, float(st["fill_alpha"])), "%s fill alpha from data @%s" % [ev, p])
			t.check(is_equal_approx(c["outline"].a, float(st["outline_alpha"])), "%s outline alpha from data @%s" % [ev, p])
			t.check(is_equal_approx(c["fill"].r, tint.r) and is_equal_approx(c["fill"].g, tint.g) and is_equal_approx(c["fill"].b, tint.b), "%s tint from data" % ev)
		for i in 21:
			var c := Art.telegraph_colors(ev, i * 0.05)
			t.check(c["fill"].a >= 0.25 - 0.0001 and c["fill"].a <= 0.35 + 0.0001, "%s fill alpha in range @%d" % [ev, i])
			t.check(c["outline"].a >= 0.70 - 0.0001 and c["outline"].a <= 0.85 + 0.0001, "%s outline alpha in range @%d" % [ev, i])
		var mid := Art.telegraph_colors(ev, 0.5)
		var edge := Art.telegraph_colors(ev, 0.75)
		var end := Art.telegraph_colors(ev, 1.0)
		t.check(end["fill"].a > mid["fill"].a and end["outline"].a > mid["outline"].a, "%s brightens late" % ev)
		t.check(is_equal_approx(end["fill"].a, float(pk["fill_alpha_peak"])) and is_equal_approx(end["outline"].a, float(pk["outline_alpha_peak"])), "%s peak at 1.0" % ev)
		t.check(is_equal_approx(edge["fill"].a, float(st["fill_alpha"])) and is_equal_approx(edge["outline"].a, float(st["outline_alpha"])), "%s base at 0.75" % ev)
		t.check(tint.g >= 0.3 and not (tint.r > 0.9 and tint.g < 0.2 and tint.b < 0.2), "%s tint not pure red" % ev)
		var fp := RM.fx_draw_params(true, ev, 12)
		t.check(int(fp["age"]) == 12 and fp["modulate"] == Color.WHITE, "%s never suppressed by reduce-flash" % ev)
	var flow = Flow.new(20261022)
	var found := {}
	for room_index in 4:
		if room_index == 3:
			flow.run.sequence_index = 3
			flow._enter_current()
		var memo: Dictionary = {}
		for i in 4600:
			if flow.state != "fighting" or not found.is_empty():
				break
			Driver.fight(flow, 1)
			for item in Art.collect_fx(flow.session, flow.session.sim.clock.tick, memo):
				if String(item["event"]).begins_with("telegraph."):
					found = item
					break
		if not found.is_empty():
			break
		if room_index < 3:
			flow.choose_reward(0)
			Driver.reach_exit(flow)
	t.check(not found.is_empty(), "live session produced a telegraph item")
	if not found.is_empty():
		t.check(int(found.get("window", 0)) > 0 and int(found["age"]) <= int(found["window"]), "telegraph item carries window >= age")

	_ad089(t)

func _ad089(t) -> void:
	t.check(Art.ranged_telegraph_length(560.0) == 96.0, "AD-089 long range capped at 96")
	t.check(Art.ranged_telegraph_length(60.0) == 60.0, "AD-089 short range kept")
	t.check(Art.ranged_telegraph_length(0.0) == 96.0, "AD-089 no range -> cap")
	var capped := true
	for r in [1.0, 50.0, 96.0, 97.0, 300.0, 5000.0]:
		capped = capped and Art.ranged_telegraph_length(r) <= 96.0
	t.check(capped, "AD-089 telegraph length never above 96")
	t.check(not Canvas.countdown_visible(false) and Canvas.countdown_visible(true), "AD-089 countdown only in debug")
	var seg: Array = Canvas.aim_tick_segment(Vector2(10, 10), Vector2(300, 90))
	t.check(seg.size() == 2 and is_equal_approx(seg[0].distance_to(seg[1]), 24.0), "AD-089 aim tick is 24 px")
	t.check(Canvas.aim_tick_segment(Vector2(5, 5), Vector2(5, 5)).is_empty(), "AD-089 degenerate aim tick empty")
	var flow = Flow.new(20261022)
	var seen_line := false
	var order_ok := true
	var both := 0
	for room_index in 4:
		if room_index == 3:
			flow.run.sequence_index = 3
			flow._enter_current()
		var memo: Dictionary = {}
		for i in 4600:
			if flow.state != "fighting":
				break
			Driver.fight(flow, 1)
			var last_tel := -1
			var first_hostile := 1 << 30
			var list: Array = Art.collect_fx(flow.session, flow.session.sim.clock.tick, memo)
			for idx in list.size():
				var ev := String(list[idx]["event"])
				if ev.begins_with("telegraph."):
					last_tel = idx
					if ev == "telegraph.line":
						seen_line = true
						var range_cap := 96.0
						for e in flow.session.enemies:
							if e.kind == "fallen_adept":
								range_cap = maxf(range_cap, 0.0)
								t.check(float(list[idx]["length"]) <= minf(96.0, float(e.tuning["attack_range"])) + 0.001, "AD-089 adept telegraph length capped")
								break
				elif ev == "enemy.bolt" or ev == "boss.bullet":
					first_hostile = mini(first_hostile, idx)
			if last_tel >= 0 and first_hostile < (1 << 30):
				both += 1
				order_ok = order_ok and last_tel < first_hostile
		if room_index < 3 and flow.state == "fighting":
			break
		if room_index < 3:
			flow.choose_reward(0)
			Driver.reach_exit(flow)
	t.check(seen_line, "AD-089 live session produced a fallen_adept telegraph.line")
	t.check(order_ok, "AD-089 telegraphs drawn before hostile bolts (%d mixed frames)" % both)
