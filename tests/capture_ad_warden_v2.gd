extends SceneTree
## AD-199 Undead Warden v2 boss-room screenshots (developer capture, not a test: needs a display). Run:
##   xvfb-run -a /usr/local/bin/godot --path . --script res://tests/capture_ad_warden_v2.gd -- docs/rooms/warden_v2
## Runs the real ruins_boss room on live data. To reach each beat the capture narrows the current phase pool to one entry,
## sets boss HP fractions and places the player; the Warden code path itself is unchanged.
const Art = preload("res://ui/pixel_art_renderer.gd")
const Flow = preload("res://world/run_flow.gd")
const SEED := 20261022
const FORCE := "essence.force"
const EXPECTED := ["phase1_combo_arc", "phase1_overhead_slam", "phase1_spear_line", "phase1_grave_rise", "phase2_leap_telegraph",
	"phase2_shockwave_ring", "phase2_pillars", "phase2_debris_stun", "phase3_enrage"]
var out_dir := "res://docs/rooms/warden_v2"
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

## Fresh run.tscn opened on the ruins_boss room with the live Warden.
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
		if str(flow.rooms[i]["id"]) == "ruins_boss":
			flow.run.sequence_index = i
	flow._enter_current()
	boss = flow.session.enemies[0]
	Art.use_art_export = false
	control._redraw_panel()

## Keeps only the pool entry whose pattern/combo/move matches `key` in the boss's current phase.
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

func _to_phase(fraction: float) -> void:
	boss.target.health.current = boss.target.health.maximum * fraction
	for i in 400:
		await _tick()
		if boss.state != "roar" and boss.phase >= (2 if fraction > 0.25 else 3) and i > 5:
			break

## Ticks until `cond` holds (max 900), then `extra` more ticks.
func _until(cond: Callable, extra: int = 0) -> bool:
	for i in 900:
		await _tick()
		if cond.call():
			for j in extra:
				await _tick()
			return true
	return false

func _windup_of(attack: String) -> Callable:
	return func(): return boss.state == "windup" and boss._windup_attack == attack and boss.state_tick >= int(boss.tuning["telegraph_ticks"]) * 2 / 3

func _run() -> void:
	await _stage()
	_only("combo")
	_place_player(200.0)
	if await _until(_windup_of("sweep_1")):
		await _shot("phase1_combo_arc")
	if await _until(_windup_of("overhead_slam")):
		await _shot("phase1_overhead_slam")
	for pair in [["phase1_spear_line", "spear_line", 330.0], ["phase1_grave_rise", "grave_rise", 300.0]]:
		await _stage()
		_only(pair[1])
		_place_player(pair[2])
		if await _until(_windup_of(pair[1])):
			await _shot(pair[0])
	# Phase 2: leap telegraph, then the shockwave ring a few ticks after landing.
	await _stage()
	await _to_phase(0.5)
	_only("leap")
	_place_player(380.0)
	if await _until(_windup_of("leap")):
		await _shot("phase2_leap_telegraph")
	var flew := await _until(func(): return boss.state == "moving")
	if flew and await _until(func(): return boss.state != "moving", 30):
		await _shot("phase2_shockwave_ring")
	# Pillars standing, then Force breaks one beside the boss for the debris stun.
	await _stage()
	await _to_phase(0.5)
	_place_player(330.0)
	await _shot("phase2_pillars")
	var pillar = flow.session.env_props.props[2]
	boss.target.position = Vector2(pillar["rect"].get_center()) + Vector2(0, 100)
	flow.session.env_props._apply(pillar, FORCE, flow.session.sim.clock.tick)
	for i in 6:
		await _tick()
	await _shot("phase2_debris_stun")
	# Phase 3: enraged combo with the timed summon.
	await _stage()
	await _to_phase(0.5)
	await _to_phase(0.2)
	_only("combo")
	_place_player(200.0)
	await _until(func(): return boss.state == "windup" and boss._windup_attack == "sweep_1" and boss.state_tick >= int(boss.tuning["telegraph_ticks"]) * 2 / 3 and flow.session.enemies.size() > 1)
	await _shot("phase3_enrage")
	var missing: Array = EXPECTED.filter(func(n): return not saved.get(n, false))
	print("CAPTURED: ", saved.keys(), " MISSING: ", missing)
	quit(0)
