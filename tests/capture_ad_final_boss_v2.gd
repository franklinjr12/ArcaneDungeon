extends SceneTree
## AD-201 Drowned Archivist v2 boss-room screenshots (developer capture, not a test: needs a display). Run:
##   xvfb-run -a /usr/local/bin/godot --path . --script res://tests/capture_ad_final_boss_v2.gd -- docs/rooms/archivist_v2
## Runs the real cistern_boss room on live data. To reach each beat the capture narrows the current phase pool to one entry,
## sets boss HP fractions and places the player; the Archivist code path itself is unchanged.
const Art = preload("res://ui/pixel_art_renderer.gd")
const SEED := 20261110
const POOLS := [Vector2(510, 215), Vector2(510, 685), Vector2(775, 450)]
const EXPECTED := ["phase1_pool_ripple", "phase1_emerge_splash", "phase1_book_pages", "phase2_tide_wave_gap", "phase2_freeze_stun",
	"phase3_electrified_water", "phase3_wisp_shield"]
var out_dir := "res://docs/rooms/archivist_v2"
var control
var flow
var canvas
var boss
var saved: Dictionary = {}

func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	if args.size() > 0:
		out_dir = args[0]
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(out_dir))
	root.size = Vector2i(1280, 720)
	call_deferred("_run")

func _path(name: String) -> String:
	return "%s/%s.png" % [ProjectSettings.globalize_path(out_dir), name]

func _shot(name: String) -> void:
	control.portrait_hud.queue_redraw()
	canvas.queue_redraw()
	await process_frame
	await RenderingServer.frame_post_draw
	var err := root.get_texture().get_image().save_png(_path(name))
	saved[name] = err == OK
	print("CAPTURE ", name, " ", "ok" if err == OK else "ERR %d" % err)

func _tick() -> void:
	var actor = flow.session.sim.actor
	actor.health.current = actor.health.maximum
	flow.step({})
	canvas.queue_redraw()
	await process_frame

## Fresh run.tscn opened on the cistern_boss room with the live Archivist.
func _stage() -> void:
	if control != null:
		control.queue_free()
		await process_frame
	control = load("res://scenes/run.tscn").instantiate()
	root.add_child(control)
	current_scene = control
	control.set_physics_process(false)
	control._stats_recorded = true
	await process_frame
	flow = control.flow
	canvas = control.arena_canvas
	for i in flow.rooms.size():
		if str(flow.rooms[i]["id"]) == "cistern_boss":
			flow.run.sequence_index = i
	flow._enter_current()
	boss = flow.session.enemies[0]
	Art.use_art_export = false
	control._redraw_panel()

## Keeps only the pool entry whose pattern or move mode matches `key` in the boss's current phase.
func _only(key: String) -> void:
	var pool: Array = boss.tuning["phases"][boss.phase - 1]["pool"]
	boss.tuning["phases"][boss.phase - 1]["pool"] = pool.filter(func(e): return str(e.get("pattern", "")) == key or (e.has("move") and str(e["move"]["mode"]) == key))
	boss._combo_queue.clear()
	boss._last_key = ""

func _place_player(at: Vector2) -> void:
	flow.session.sim.actor.position = at

func _to_phase(fraction: float) -> void:
	boss.target.health.current = boss.target.health.maximum * fraction
	for i in 400:
		await _tick()
		if boss.state != "roar" and boss.phase >= (2 if fraction > 0.25 else 3) and i > 5:
			break

## Ticks until `cond` holds (max 1500), then `extra` more ticks.
func _until(cond: Callable, extra: int = 0) -> bool:
	for i in 1500:
		await _tick()
		if cond.call():
			for j in extra:
				await _tick()
			return true
	return false

func _emerging() -> bool:
	return boss.state == "windup" and str(boss.intent.snapshot()["kind"]) == "emerge"

func _pages() -> Array:
	return flow.session.enemies.filter(func(e): return e.kind == "book_page" and e.target.alive())

func _wisps() -> Array:
	return flow.session.enemies.filter(func(e): return e.kind == "lantern_wisp" and e.target.alive())

func _run() -> void:
	# Phase 1: dive; the ripple at the exit pool, then the splash ring just after the emerge.
	await _stage()
	_only("submerge")
	_place_player(Vector2(1100, 450))
	if await _until(func(): return _emerging() and boss.state_tick >= 25):
		await _shot("phase1_pool_ripple")
	if await _until(func(): return not _emerging() and boss.state != "submerged", 6):
		await _shot("phase1_emerge_splash")
	# Phase 1: pages in flight, one Burning (a Fire hit; it dies on its next tick).
	await _stage()
	_only("page_throw")
	_place_player(Vector2(900, 450))
	if await _until(func(): return _pages().size() >= 2, 20):
		var pages := _pages()
		pages[0].target.status.apply("burning", flow.session.sim.clock.tick, flow.session.sim.settings["statuses"]["burning"], {"source_id": 0})
		await _shot("phase1_book_pages")
	# Phase 2: the tide wave with its gap, moving (a few ticks past the warning).
	await _stage()
	await _to_phase(0.5)
	_place_player(Vector2(1100, 600))
	var wave := func() -> Array: return flow.session.hazards.filter(func(h): return h["kind"] == "boss_tide_wave")
	if await _until(func(): return not wave.call().is_empty() and not wave.call()[0]["telegraph"], 40):
		await _shot("phase2_tide_wave_gap")
	# Phase 2: every pool frozen; the dive surfaces on ice and the boss is stunned.
	await _stage()
	await _to_phase(0.5)
	_only("submerge")
	_place_player(Vector2(1100, 450))
	for p in POOLS:
		flow.session.water.freeze_circle(p, 70.0, 100000)
	if await _until(func(): return boss.state == "stagger", 20):
		await _shot("phase2_freeze_stun")
	# Phase 3: storm pulse conducting through the water.
	await _stage()
	await _to_phase(0.5)
	await _to_phase(0.2)
	_only("storm_pulse")
	_place_player(Vector2(900, 450))
	if await _until(func(): return not flow.session.water_shock.is_empty(), 25):
		await _shot("phase3_electrified_water")
	# Phase 3: two wisps and the shield bubble.
	await _stage()
	await _to_phase(0.5)
	await _to_phase(0.2)
	_only("summon_wisps")
	_place_player(Vector2(900, 450))
	if await _until(func(): return boss.shielded and _wisps().size() >= 2, 15):
		await _shot("phase3_wisp_shield")
	var missing: Array = EXPECTED.filter(func(n): return not saved.get(n, false))
	print("CAPTURED: ", saved.keys(), " MISSING: ", missing)
	quit(0)
