extends SceneTree
## AD-264 rendered frame-time bench: Drowned Archivist storm_conduct on the full cistern, rendering ON (needs a display).
## Run: xvfb-run -a -s "-screen 0 1920x1080x24" /usr/local/bin/godot --path . --script res://tests/bench/archivist_storm_render_bench.gd [-- --size=1920x1080 --frames=60 --budget-ms=33]
## Opens the real run.tscn on cistern_boss (like tests/capture_ad_final_boss_v2.gd), steps it with run_controller.perf_step,
## measures wall time per frame (vsync off) before and after the boss's real _fire_storm_pulse electrifies the water:
## "_wall" = full frame incl. GPU raster; "_cpu" = sim + every canvas _draw (GDScript draw-command recording) up to
## RenderingServer.frame_pre_draw, so software GL on a VM does not swamp the number.
## Then times the water draw path piece by piece on a probe canvas. Exits 1 when an electrified cpu frame is over budget
## (the AD-256 a) target), 2 when it cannot run (headless display / room missing). Read-only on game code.
const Art = preload("res://ui/pixel_art_renderer.gd")
const Elite = preload("res://combat/boss_moves/elite_patterns.gd")
const SEED := 20261110
const PROBE_FRAMES := 30

var size := Vector2i(1920, 1080)
var frames := 60
var budget_ms := 33.0
var control
var flow
var canvas
var boss

## Probe canvas: times the water draw pieces inside a real _draw (same calls the arena canvas makes).
class Probe extends Control:
	var session
	var offset := Vector2.ZERO
	var samples: Dictionary = {}
	var counts: Dictionary = {}

	func _add(key: String, usec: int) -> void:
		if not samples.has(key):
			samples[key] = []
		samples[key].append(usec)

	func _draw() -> void:
		if session == null:
			return
		var water = session.water
		Art._glow_queue.clear()
		var t := Time.get_ticks_usec()
		Art.draw_water(self, session, offset, false)
		_add("Art.draw_water (total)", Time.get_ticks_usec() - t)
		var glows: int = Art._glow_queue.size()
		t = Time.get_ticks_usec()
		Art.draw_actor_glows(self)
		_add("Art.draw_actor_glows (water glows only)", Time.get_ticks_usec() - t)
		Art._glow_queue.clear()
		t = Time.get_ticks_usec()
		Art._draw_water_states(self, session, offset, session.sim.clock.tick, false)
		_add("Art._draw_water_states", Time.get_ticks_usec() - t)
		t = Time.get_ticks_usec()
		var view: Array = water.state_view()
		_add("WaterTiles.state_view", Time.get_ticks_usec() - t)
		t = Time.get_ticks_usec()
		var deeps: Array[Rect2] = water.deep_rects()
		_add("WaterTiles.deep_rects", Time.get_ticks_usec() - t)
		t = Time.get_ticks_usec()
		var tiles: Array = water.view()
		_add("WaterTiles.view", Time.get_ticks_usec() - t)
		# Per-cell pieces of _draw_water_states, each looped over every state cell.
		var tick: int = session.sim.clock.tick
		var picks: Array = []
		t = Time.get_ticks_usec()
		for item in view:
			var rect: Rect2 = item["cell_rect"]
			var deep := false
			for d in deeps:
				deep = deep or d.has_point(rect.get_center())
			picks.append(Art.water_state_tag(str(item["state"]), deep, Vector2i(floori(rect.position.x / 32.0), floori(rect.position.y / 32.0)), tick, false))
		_add("loop: deep test + water_state_tag", Time.get_ticks_usec() - t)
		t = Time.get_ticks_usec()
		for pick in picks:
			if not pick.is_empty():
				Art.extra_sheet_frame(Art.WATER_STATES, pick["tag"], int(pick["index"]))
		_add("loop: extra_sheet_frame", Time.get_ticks_usec() - t)
		var sh: Dictionary = Art.extra_sheet(Art.WATER_STATES)
		t = Time.get_ticks_usec()
		for pick in picks:
			if not pick.is_empty():
				FileAccess.file_exists(str(sh["json"]))
				ResourceLoader.exists(str(sh["png"]))
				if sh.get("glow_png") != null:
					ResourceLoader.exists(str(sh["glow_png"]))
		_add("loop: file_exists/ResourceLoader.exists only", Time.get_ticks_usec() - t)
		var comparisons := [0]
		var copy := view.duplicate()
		copy.sort_custom(func(a, b):
			comparisons[0] += 1
			return a["cell_rect"].position.y < b["cell_rect"].position.y)
		var base_cells := 0
		for tile in tiles:
			var r: Rect2 = tile["rect"]
			base_cells += ceili(r.size.x / 32.0) * ceili(r.size.y / 32.0)
		var drawn := picks.filter(func(p): return not p.is_empty()).size()
		var glow := 1 if sh.get("glow_png") != null else 0
		counts = {"state_cells": view.size(), "deep_rects": deeps.size(), "deep_has_point_calls": view.size() * deeps.size(),
			"water_state_tag_calls": view.size(), "extra_sheet_frame_calls": drawn,
			"fs_exists_calls": drawn * (2 + glow), "sort_custom_lambda_calls_approx": comparisons[0],
			"base_water_tiles": tiles.size(), "base_cell_draws": base_cells,
			"state_cell_draws": drawn, "glow_queue_adds": drawn * glow, "glow_draws": glows}

func _initialize() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--size="):
			var p := arg.substr(7).split("x")
			size = Vector2i(int(p[0]), int(p[1]))
		elif arg.begins_with("--frames="):
			frames = int(arg.substr(9))
		elif arg.begins_with("--budget-ms="):
			budget_ms = float(arg.substr(12))
	call_deferred("_run")

static func _stats(values: Array) -> Dictionary:
	if values.is_empty():
		return {"n": 0, "mean": 0.0, "p50": 0.0, "p95": 0.0, "max": 0.0, "over": 0}
	var sorted := values.duplicate()
	sorted.sort()
	var total := 0.0
	for v in sorted:
		total += float(v)
	return {"n": sorted.size(), "mean": total / sorted.size() / 1000.0, "p50": float(sorted[sorted.size() / 2]) / 1000.0,
		"p95": float(sorted[clampi(roundi(sorted.size() * 0.95), 0, sorted.size() - 1)]) / 1000.0, "max": float(sorted[-1]) / 1000.0}

func _line(label: String, frame_us: Array, sim_us: Array) -> Dictionary:
	var f := _stats(frame_us)
	var s := _stats(sim_us)
	var over := frame_us.filter(func(v): return float(v) / 1000.0 > budget_ms).size()
	print("AD264_RENDER_BENCH phase=%s size=%dx%d frames=%d frame_ms mean=%.2f p50=%.2f p95=%.2f max=%.2f over_%dms=%d sim_ms mean=%.2f max=%.2f" % [
		label, size.x, size.y, f["n"], f["mean"], f["p50"], f["p95"], f["max"], int(budget_ms), over, s["mean"], s["max"]])
	f["over"] = over
	return f

## Steps the real run screen `n` frames. Returns {wall, cpu, sim, glow} per frame (us / count): wall = frame to frame incl.
## GPU raster; cpu = perf_step through every canvas _draw up to RenderingServer.frame_pre_draw (raster excluded).
## `keep_lit` re-fires the storm pulse whenever the water goes dark.
func _measure(n: int, keep_lit: bool) -> Dictionary:
	var out := {"wall": [], "cpu": [], "sim": [], "glow": []}
	var session = flow.session
	await RenderingServer.frame_post_draw
	var last := Time.get_ticks_usec()
	for i in n:
		session.sim.actor.health.current = session.sim.actor.health.maximum
		if keep_lit and session.water.state_view().filter(func(c): return c["state"] == "electrified").is_empty():
			boss._fire_storm_pulse(session)
		var t0 := Time.get_ticks_usec()
		control.perf_step({})
		out["sim"].append(control.last_sim_usec)
		await RenderingServer.frame_pre_draw
		out["cpu"].append(Time.get_ticks_usec() - t0)
		out["glow"].append(Art._glow_queue.size())
		await RenderingServer.frame_post_draw
		var now := Time.get_ticks_usec()
		out["wall"].append(now - last)
		last = now
	return out

func _report(label: String, m: Dictionary) -> Dictionary:
	_line(label + "_wall", m["wall"], m["sim"])
	var cpu := _line(label + "_cpu", m["cpu"], m["sim"])
	var g: Array = m["glow"].duplicate()
	g.sort()
	print("AD264_RENDER_BENCH phase=%s glow_queue max=%d" % [label, int(g[-1]) if not g.is_empty() else 0])
	return cpu

func _run() -> void:
	if DisplayServer.get_name() == "headless":
		print("AD264_RENDER_BENCH_SKIP display=headless (run under xvfb-run without --headless)")
		quit(2)
		return
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	Engine.max_fps = 0
	DisplayServer.window_set_size(size)
	root.size = size
	control = load("res://scenes/run.tscn").instantiate()
	control.perf_seed = SEED
	root.add_child(control)
	current_scene = control
	control.set_physics_process(false)
	control._stats_recorded = true
	await process_frame
	flow = control.flow
	canvas = control.arena_canvas
	var found := false
	for i in flow.rooms.size():
		if str(flow.rooms[i]["id"]) == "cistern_boss":
			flow.run.sequence_index = i
			found = true
	if not found:
		print("AD264_RENDER_BENCH_SKIP cistern_boss room missing")
		quit(2)
		return
	flow._enter_current()
	control._redraw_panel()
	boss = flow.session.enemies[0]
	# Only the storm pulse in the pool so the boss itself also fires storm_conduct on its cycle.
	for phase in boss.tuning["phases"]:
		phase["pool"] = phase["pool"].filter(func(e): return str(e.get("pattern", "")) == "storm_pulse") if phase["pool"].any(func(e): return str(e.get("pattern", "")) == "storm_pulse") else phase["pool"]
	var water = flow.session.water
	print("AD264_RENDER_BENCH_ENV display=%s renderer=%s adapter=%s window=%s viewport=%s canvas_size=%s canvas_scale=%s art_export=%s cpus=%d godot=%s" % [
		DisplayServer.get_name(), RenderingServer.get_current_rendering_driver_name(), RenderingServer.get_video_adapter_name(),
		DisplayServer.window_get_size(), root.get_visible_rect().size, canvas.size, canvas.scale, Art.use_art_export,
		OS.get_processor_count(), Engine.get_version_info()["string"]])
	print("AD264_RENDER_BENCH_ROOM water_tiles=%d storm_conduct=%s" % [water.view().size(), JSON.stringify(boss.tuning.get("storm_conduct", {}))])
	await _measure(20, false)  # warm-up: texture loads, first-frame caches
	var calm_stats := _report("calm", await _measure(frames, false))
	boss._fire_storm_pulse(flow.session)
	var lit_cells: int = water.state_view().filter(func(c): return c["state"] == "electrified").size()
	print("AD264_RENDER_BENCH_TRIGGER storm_conduct electrified_cells=%d water_shock=%s" % [lit_cells, JSON.stringify(flow.session.water_shock)])
	var lit_stats := _report("electrified", await _measure(frames, true))
	# Probe without raster so llvmpipe threads do not skew the per-function numbers (glows are only queued, not drawn).
	RenderingServer.render_loop_enabled = false
	var probe := Probe.new()
	probe.session = flow.session
	probe.offset = canvas.camera_offset()
	probe.size = Vector2(size)
	probe.modulate = Color(1, 1, 1, 0)
	root.add_child(probe)
	for i in PROBE_FRAMES:
		if water.state_view().is_empty():
			boss._fire_storm_pulse(flow.session)
		probe.queue_redraw()
		await process_frame
	for key in probe.samples:
		var st := _stats(probe.samples[key])
		print("AD264_RENDER_BENCH_PROFILE fn=\"%s\" calls_per_frame=1 mean_ms=%.3f max_ms=%.3f" % [key, st["mean"], st["max"]])
	RenderingServer.render_loop_enabled = true
	print("AD264_RENDER_BENCH_COUNTS %s" % JSON.stringify(probe.counts))
	var ok: bool = int(lit_stats["over"]) == 0 and float(lit_stats["max"]) <= budget_ms
	print("AD264_RENDER_BENCH_RESULT ok=%s cpu_electrified_max_ms=%.2f cpu_calm_max_ms=%.2f budget_ms=%.1f" % [ok, lit_stats["max"], calm_stats["max"], budget_ms])
	quit(0 if ok else 1)
