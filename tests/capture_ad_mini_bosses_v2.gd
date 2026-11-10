extends SceneTree
## AD-200 elite mini-boss screenshots (developer capture, not a test: needs a display). Run:
##   xvfb-run -a /usr/local/bin/godot --path . --script res://tests/capture_ad_mini_bosses_v2.gd -- docs/rooms/mini_bosses_v2
## Runs the real ruins_challenge_v1 and cistern_challenge_v1 rooms on live data. To reach each beat the capture narrows the
## current phase pool to one entry, sets boss HP fractions and places the player; the boss code path itself is unchanged.
const Art = preload("res://ui/pixel_art_renderer.gd")
const Minion = preload("res://combat/boss_moves/elite_minion.gd")
const SEED := 20261110
const COLD := "essence.cold"
const ROOMS := {"ruins_adept_elite":["res://world/data/rooms_ruins_v1.json","ruins_challenge_v1"],
	"cistern_crystal_elite":["res://world/data/rooms_cistern_v1.json","cistern_challenge_v1"]}
const EXPECTED := ["adept_blink_telegraph", "adept_fan_volley", "adept_homing_skull", "adept_phase2_decoy", "crystal_float_channels",
	"crystal_beam_telegraph", "crystal_beam_sweep", "crystal_electrified_water", "crystal_cold_frozen_water", "crystal_phase2_small_crystals"]
var out_dir := "res://docs/rooms/mini_bosses_v2"
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

## Fresh run.tscn whose current room is the live challenge room of `id`, entered until the elite has spawned.
func _stage(id: String) -> void:
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
	var doc: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(ROOMS[id][0]))
	flow.rooms[flow.run.sequence_index] = doc["room_templates"][ROOMS[id][1]].duplicate(true)
	flow._enter_current()
	boss = null
	for i in 120:
		await _tick()
		for e in flow.session.enemies:
			if e.has_method("advance") and e.get("tuning") != null and str(e.tuning.get("kind", "")) in ["fallen_adept", "storm_crystal"] and not (e is Minion):
				boss = e
		if boss != null:
			break
	Art.use_art_export = false
	control._redraw_panel()

func _only(key: String) -> void:
	var pool: Array = boss.tuning["phases"][boss.phase - 1]["pool"]
	var keep: Array = pool.filter(func(e): return str(e.get("pattern", "")) == key or (e.has("combo") and key == "combo") or (e.has("move") and str(e["move"]["mode"]) == key))
	boss.tuning["phases"][boss.phase - 1]["pool"] = keep
	boss._combo_queue.clear()
	boss._last_key = ""

func _place_player(distance: float) -> void:
	var actor = flow.session.sim.actor
	for step in 24:
		var at: Vector2 = boss.target.position + Vector2.RIGHT.rotated(PI + float(step) * 0.5236) * distance
		if flow.session.world.valid_position(at, actor.radius + 4.0):
			actor.position = at
			return

func _to_phase2() -> void:
	boss.target.health.current = boss.target.health.maximum * 0.45
	for i in 400:
		await _tick()
		if boss.state != "roar" and boss.phase >= 2 and i > 5:
			break

func _until(cond: Callable, extra: int = 0) -> bool:
	for i in 1200:
		await _tick()
		if cond.call():
			for j in extra:
				await _tick()
			return true
	return false

func _windup_of(attack: String) -> Callable:
	return func(): return boss.state == "windup" and boss._windup_attack == attack and boss.state_tick >= int(boss.intent.snapshot().get("telegraph_ticks", 40)) * 2 / 3

func _minions(kind: String) -> Array:
	return flow.session.enemies.filter(func(e): return e is Minion and e.kind == kind and e.target.alive())

func _run() -> void:
	# Elite fallen adept (Ruins challenge room).
	await _stage("ruins_adept_elite")
	_only("blink")
	_place_player(300.0)
	if await _until(_windup_of("blink")):
		await _shot("adept_blink_telegraph")
	await _stage("ruins_adept_elite")
	_only("fan")
	_place_player(300.0)
	if await _until(func(): return boss.state == "windup" and boss._windup_attack == "fan", 0) and await _until(func(): return boss.state != "windup", 14):
		await _shot("adept_fan_volley")
	await _stage("ruins_adept_elite")
	_only("homing_skull")
	_place_player(330.0)
	if await _until(func(): return _minions("homing_skull").size() > 0, 45):
		await _shot("adept_homing_skull")
	await _stage("ruins_adept_elite")
	await _to_phase2()
	_only("fan")
	_place_player(330.0)
	if await _until(func(): return _minions("decoy").size() > 0 and boss.state == "windup" and boss.state_tick >= 20):
		await _shot("adept_phase2_decoy")
	# Elite storm crystal (Cistern challenge room).
	await _stage("cistern_crystal_elite")
	_only("pulse")
	_place_player(420.0)
	for i in 150:
		await _tick()
	await _shot("crystal_float_channels")
	await _stage("cistern_crystal_elite")
	_only("beam_sweep")
	_place_player(420.0)
	if await _until(_windup_of("beam_sweep")):
		await _shot("crystal_beam_telegraph")
	if await _until(func(): return boss.state == "casting", 40):
		await _shot("crystal_beam_sweep")
	await _stage("cistern_crystal_elite")
	_only("electrify")
	_place_player(420.0)
	if await _until(func(): return flow.session.water != null and not flow.session.water.state_view().is_empty(), 10):
		await _shot("crystal_electrified_water")
		# Cold answer: a real Cold projectile fired into the pool freezes the cells it crosses into safe ground.
		var sim = flow.session.sim
		var pool_rect: Rect2 = flow.session.water.state_view()[0]["rect"] if flow.session.water.state_view()[0].has("rect") else Rect2()
		var target: Vector2 = pool_rect.get_center() if pool_rect.size != Vector2.ZERO else boss.target.position
		sim.loadout.allow_edit = true
		sim.equip(1, {"schema_version": 1, "formula_id": "cap.cold", "display_name": "cold",
			"root": {"essence_id": COLD, "manifestation_id": "form.projectile", "modifier_ids": [], "params": {}}})
		sim.loadout.slots[1]["cooldown"] = 0
		sim.mana = 120.0
		var from: Vector2 = sim.actor.position
		sim.try_cast(1, from, (target - from).normalized())
		for i in 40:
			await _tick()
		await _shot("crystal_cold_frozen_water")
	await _stage("cistern_crystal_elite")
	await _to_phase2()
	_only("pulse")
	_place_player(420.0)
	if await _until(func(): return _minions("storm_crystal").size() > 0, 20):
		await _shot("crystal_phase2_small_crystals")
	var missing: Array = EXPECTED.filter(func(n): return not saved.get(n, false))
	print("CAPTURED: ", saved.keys(), " MISSING: ", missing)
	quit(0)
