extends SceneTree
## AD-039 PR screenshots (not a test: needs a display). Run:
##   xvfb-run -a /usr/local/bin/godot --path . --script res://tests/capture_p1_fx.gd -- /tmp/ad039_shots
const Art = preload("res://ui/pixel_art_renderer.gd")
const Flow = preload("res://world/run_flow.gd")
const Driver = preload("res://tests/m3_run_driver.gd")
const Canvas = preload("res://ui/combat_canvas.gd")
const SEED := 20261022
var out_dir := "user://ad039_shots"
var canvas
var saved: Dictionary = {}

func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	if args.size() > 0:
		out_dir = args[0]
	DirAccess.make_dir_recursive_absolute(out_dir)
	root.size = Vector2i(1280, 720)
	call_deferred("_run")

func _shot(name: String) -> void:
	if saved.has(name):
		return
	canvas.queue_redraw()
	await process_frame
	await RenderingServer.frame_post_draw
	var err := root.get_texture().get_image().save_png("%s/%s.png" % [out_dir, name])
	saved[name] = err == OK
	print("CAPTURE ", name, " ", "ok" if err == OK else "ERR %d" % err)

func _new_canvas(flow) -> void:
	if canvas != null:
		canvas.queue_free()
	canvas = Canvas.new()
	canvas.size = Vector2(1280, 720)
	canvas.view_rect = Rect2(0, 0, 1280, 720)
	root.add_child(canvas)
	canvas.session = flow.session

func _has(events: Dictionary, names: Array) -> bool:
	for n in names:
		if not events.has(n):
			return false
	return true

func _run() -> void:
	var flow = Flow.new(SEED)
	_new_canvas(flow)
	await process_frame
	Art.use_art_export = false
	await _shot("slice_1x_f6_off")
	Art.use_art_export = true
	await _shot("slice_1x_f6_on")
	Art.use_art_export = false
	# Event-triggered shots while the scripted policy fights through the route.
	var wanted := {
		"telegraph_circle": ["telegraph.circle"],
		"boss_dash_lane": ["telegraph.dash_lane"],
		"status_wet": ["status.wet"], "status_burning": ["status.burning"]}
	var memo: Dictionary = {}
	var all_seen: Dictionary = {}
	for index in 4:
		if index == 3:
			flow.run.sequence_index = 3
			flow._enter_current()
			_new_canvas(flow)
		memo = {}
		for i in 4600:
			if flow.state != "fighting":
				break
			Driver.fight(flow, 1)
			canvas.session = flow.session
			var seen: Dictionary = {}
			for item in Art.collect_fx(flow.session, flow.session.sim.clock.tick, memo):
				seen[item["event"]] = true
				all_seen[item["event"]] = true
			for name in wanted:
				if not saved.has(name) and _has(seen, wanted[name]):
					await _shot(name)
		if index < 3:
			flow.choose_reward(0)
			Driver.reach_exit(flow)
	# One shot per element: scripted burst spell (projectile -> on-hit burst) cast at the nearest enemy.
	for el in ["fire", "water", "lightning"]:
		var room = Flow.new(SEED)
		_new_canvas(room)
		room.session.sim.loadout.unlocked = room.run.unlocked.duplicate(true)
		var formula := {"display_name": el + " burst", "formula_id": "ad039." + el, "schema_version": 1,
			"root": {"essence_id": "essence." + el, "manifestation_id": "form.projectile", "modifier_ids": [], "params": {}},
			"on_hit": {"trigger_id": "trigger.on_hit", "payload": {"essence_id": "essence." + el, "manifestation_id": "form.burst", "modifier_ids": [], "params": {}}}}
		room.session.sim.loadout.allow_edit = true
		for rune in ["essence." + el, "form.projectile", "form.burst", "trigger.on_hit"]:
			if not room.session.sim.loadout.unlocked.has(rune):
				room.session.sim.loadout.unlocked.append(rune)
		var eq: Dictionary = room.session.sim.equip(1, formula)
		var fx_memo: Dictionary = {}
		for i in 240:
			var foe = Driver._nearest(room.session)
			var target_at: Vector2 = foe.target.position if foe != null else room.session.sim.actor.position + Vector2.RIGHT * 100
			var dir: Vector2 = (target_at - room.session.sim.actor.position).normalized()
			room.step({"move": Vector2.ZERO, "aim": dir, "cursor": target_at, "cast": 1 if foe != null and i % 40 == 0 else -1, "dash": false})
			canvas.session = room.session
			var now: Dictionary = {}
			for item in Art.collect_fx(room.session, room.session.sim.clock.tick, fx_memo):
				now[item["event"]] = true
			if now.has("projectile." + el):
				await _shot(el + "_1_projectile")
			if now.has("impact." + el) and now.has("burst." + el):
				await _shot(el + "_2_impact_burst")
				break
	# Damage numbers: all three symbols over a live enemy.
	var room = Flow.new(SEED)
	_new_canvas(room)
	await process_frame
	var enemy = room.session.enemies[0]
	for channel in ["fire", "water", "lightning"]:
		enemy.target.receive_damage(12.0, channel, 1, 1.0)
		room.step()
		await process_frame
	await _shot("damage_numbers_3_symbols")
	# Status overlays on an enemy.
	var cfg = room.session.sim.settings["statuses"]
	for sid in ["wet", "burning", "charged"]:
		enemy.target.status.apply(sid, room.session.sim.clock.tick, cfg[sid], {"team": 0})
	await _shot("status_wet_burning_charged")
	print("CAPTURED: ", saved.keys(), " MISSING: ", wanted.keys().filter(func(k): return not saved.has(k)))
	quit(0)
