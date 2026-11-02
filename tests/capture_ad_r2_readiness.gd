extends SceneTree
## AD-041 playtest-readiness screenshot set (developer capture, not a test: needs a display). Run:
##   xvfb-run -a /usr/local/bin/godot --path . --script res://tests/capture_ad_r2_readiness.gd -- docs/playtests/ad_r2_readiness
## Every shot uses the P1 default visuals (Art.use_art_export = false) except p0_f6_comparison.
const Art = preload("res://ui/pixel_art_renderer.gd")
const Driver = preload("res://tests/m3_run_driver.gd")
const SEED := 20261022
const EXPECTED := ["hud", "fire_cast", "fire_status", "water_cast", "water_status", "lightning_cast", "lightning_status",
	"wet_lightning_arc", "telegraph_bone_thrall", "telegraph_fallen_adept", "telegraph_grave_hound", "telegraph_undead_warden",
	"warden_phase_cue", "reward_pick", "editor_rejection", "run_summary", "hitbox_mage", "hitbox_bone_thrall",
	"hitbox_fallen_adept", "hitbox_grave_hound", "hitbox_undead_warden", "p0_f6_comparison"]
const STATUS_OF := {"fire": "burning", "water": "wet", "lightning": "charged"}
var out_dir := "res://docs/playtests/ad_r2_readiness"
var control
var flow
var canvas
var memo: Dictionary = {}
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

func _grab() -> Image:
	control.portrait_hud.queue_redraw()
	canvas.queue_redraw()
	await process_frame
	await RenderingServer.frame_post_draw
	return root.get_texture().get_image()

func _shot(name: String) -> void:
	if saved.has(name):
		return
	var err := (await _grab()).save_png(_path(name))
	saved[name] = err == OK
	print("CAPTURE ", name, " ", "ok" if err == OK else "ERR %d" % err)

## Zoomed crop (nearest, scale 2) around a world position with the hitbox overlay already enabled.
func _crop_shot(name: String, world_at: Vector2, half: int) -> void:
	var img := await _grab()
	var centre: Vector2 = canvas.position + canvas.local_from_world(world_at)
	var rect := Rect2i(Vector2i(centre) - Vector2i(half, half), Vector2i(half * 2, half * 2)).intersection(Rect2i(Vector2i.ZERO, img.get_size()))
	var part := img.get_region(rect)
	part.resize(part.get_width() * 2, part.get_height() * 2, Image.INTERPOLATE_NEAREST)
	var err := part.save_png(_path(name))
	saved[name] = err == OK
	print("CAPTURE ", name, " ", "ok" if err == OK else "ERR %d" % err)

## Fresh run.tscn on the seeded route. The controller's own physics step is off; this script drives the flow.
func _stage(room_index: int = 0, keep_encounter: bool = false) -> void:
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
	if room_index != 0:
		flow.run.sequence_index = room_index
		flow._enter_current()
	if not keep_encounter:
		flow.encounter = null
		if flow.room.values["type"] != "boss":
			for enemy in flow.session.enemies:
				flow.session.sim.targets.remove(enemy.target.id)
			flow.session.enemies.clear()
	control._redraw_panel()
	memo = {}
	Art.use_art_export = false

## One sim tick, one rendered frame, with the mage kept alive. Returns the FX events seen this tick.
func _tick(command: Dictionary = {}) -> Dictionary:
	var actor = flow.session.sim.actor
	actor.health.current = actor.health.maximum
	flow.step(command)
	canvas.queue_redraw()
	await process_frame
	var seen: Dictionary = {}
	for item in Art.collect_fx(flow.session, flow.session.sim.clock.tick, memo):
		seen[item["event"]] = item
	return seen

func _spawn(kind: String, from: Vector2, offsets: Array):
	for offset in offsets:
		var foe = flow.session.spawn_enemy(kind, from + offset)
		if foe != null:
			foe.target.health.maximum = 9999.0
			foe.target.health.current = 9999.0
			return foe
	return null

func _offsets(distance: float) -> Array:
	var out: Array = []
	for angle in [0.0, 0.5, -0.5, 1.0, -1.0, 3.14]:
		out.append(Vector2.RIGHT.rotated(angle) * distance)
	return out

func _element_formula(el: String) -> Dictionary:
	return {"display_name": el + " burst", "formula_id": "ad041." + el, "schema_version": 1,
		"root": {"essence_id": "essence." + el, "manifestation_id": "form.projectile", "modifier_ids": [], "params": {}},
		"on_hit": {"trigger_id": "trigger.on_hit", "payload": {"essence_id": "essence." + el, "manifestation_id": "form.burst", "modifier_ids": [], "params": {}}}}

func _equip(el: String) -> void:
	var loadout = flow.session.sim.loadout
	loadout.allow_edit = true
	for rune in ["essence." + el, "form.projectile", "form.burst", "trigger.on_hit"]:
		if not loadout.unlocked.has(rune):
			loadout.unlocked.append(rune)
	var result: Dictionary = flow.session.sim.equip(1, _element_formula(el))
	loadout.allow_edit = false
	if not result["ok"]:
		print("EQUIP FAILED ", el, " ", result)

func _aim(foe) -> Dictionary:
	var at: Vector2 = foe.target.position
	var dir: Vector2 = (at - flow.session.sim.actor.position).normalized()
	return {"move": Vector2.ZERO, "aim": dir, "cursor": at, "cast": -1, "dash": false}

func _cast_scene(el: String) -> void:
	await _stage()
	_equip(el)
	var foe = _spawn("bone_thrall", flow.session.sim.actor.position, _offsets(300.0))
	var hit_tick := -1
	for i in 24:
		await _tick({})
	for i in 260:
		var command := _aim(foe)
		command["cast"] = 1 if i % 45 == 3 else -1
		var seen: Dictionary = await _tick(command)
		var tick: int = flow.session.sim.clock.tick
		if seen.has("projectile." + el) and flow.session.sim.actor.position.distance_to(seen["projectile." + el]["at"]) >= 110.0:
			await _shot(el + "_cast")
		if hit_tick < 0 and seen.has("burst." + el):
			hit_tick = i
			await _shot(el + "_cast")
		if hit_tick >= 0 and i >= hit_tick + 6:
			var cfg: Dictionary = flow.session.sim.settings["statuses"]
			if not foe.target.status.has(STATUS_OF[el], tick):
				foe.target.status.apply(STATUS_OF[el], tick, cfg[STATUS_OF[el]], {"team": 0})
				print("NOTE ", el, " burst did not apply ", STATUS_OF[el], "; applied directly")
			await _shot(el + "_status")
			break

func _arc_scene() -> void:
	await _stage()
	_equip("lightning")
	var first = _spawn("bone_thrall", flow.session.sim.actor.position, _offsets(300.0))
	var second = null
	for offset in [Vector2(70, 0), Vector2(-70, 0), Vector2(0, 70), Vector2(0, -70), Vector2(50, 50), Vector2(-50, -50)]:
		second = _spawn("bone_thrall", first.target.position, [offset])
		if second != null:
			break
	var cfg: Dictionary = flow.session.sim.settings["statuses"]
	for foe in [first, second]:
		if foe != null:
			foe.target.status.apply("wet", flow.session.sim.clock.tick, cfg["wet"], {"team": 0})
	var arc_at := -1
	for i in 24:
		await _tick({})
	for i in 200:
		var command := _aim(first)
		command["cast"] = 1 if i % 45 == 3 else -1
		var seen: Dictionary = await _tick(command)
		for foe in [first, second]:
			if foe != null and not foe.target.status.has("wet", flow.session.sim.clock.tick) and arc_at < 0:
				foe.target.status.apply("wet", flow.session.sim.clock.tick, cfg["wet"], {"team": 0})
		if arc_at < 0 and seen.has("reaction.arc"):
			arc_at = i
		if arc_at >= 0 and i >= arc_at + 2:
			await _shot("wet_lightning_arc")
			break

func _telegraph_scene(kind: String, distance: float) -> void:
	await _stage()
	var foe = _spawn(kind, flow.session.sim.actor.position, _offsets(distance))
	for i in 300:
		await _tick({})
		if foe.state == "windup" and foe.state_tick >= int(foe.tuning["telegraph_ticks"]) / 2:
			await _shot("telegraph_" + kind)
			break

func _warden_scene() -> void:
	await _stage(3)
	var boss = flow.session.enemies[0]
	flow.session.sim.actor.position = boss.target.position + Vector2(-260, 0)
	for i in 300:
		await _tick({})
		if boss.state == "windup" and boss.state_tick >= int(boss.tuning["telegraph_ticks"]) / 2:
			await _shot("telegraph_undead_warden")
			break
	for i in 200:
		await _tick({})
		if boss.state == "recover":
			break
	boss.target.health.current = boss.target.health.maximum * 0.4
	var phase_at := -1
	for i in 200:
		var seen: Dictionary = await _tick({})
		if phase_at < 0 and (seen.has("boss.phase") or boss.phase == 2):
			phase_at = i
		if phase_at >= 0 and i >= phase_at + 2:
			await _shot("warden_phase_cue")
			break

## Scripted route: reward cards after room 1, then on to the slice win for the summary.
func _route_scene() -> void:
	await _stage(0, true)
	for index in 4:
		var result: Dictionary = Driver.fight(flow, 4600)
		if result["state"] != "cleared":
			print("ROUTE STOPPED room ", index, " state ", result["state"])
			return
		if index < 3:
			control._redraw_panel()
			if index == 0:
				await _shot("reward_pick")
			flow.choose_reward(0)
		Driver.reach_exit(flow)
	Driver.reach_exit(flow)
	Driver.fight(flow, 4600)
	control._redraw_panel()
	await _shot("run_summary")

func _editor_scene() -> void:
	await _stage(4)
	control._open_editor(3)
	flow.editor.set_root("essence.fire", "form.orb")
	control._editor_rebuild()
	await _shot("editor_rejection")

func _hud_scene() -> void:
	await _stage(0, true)
	# Mid-fight: spells cast, cooldowns running, enemy alive, mana partly spent.
	while flow.state == "fighting" and flow.session.player.casts < 9:
		Driver.fight(flow, 3)
	control._redraw_panel()
	await _shot("hud")
	Art.use_art_export = true
	saved.erase("p0_f6_comparison")
	await _shot("p0_f6_comparison")
	Art.use_art_export = false

func _hitbox_scene() -> void:
	for kind in ["bone_thrall", "fallen_adept", "grave_hound"]:
		await _stage()
		canvas.show_debug = true
		var foe = _spawn(kind, flow.session.sim.actor.position, _offsets(260.0))
		for i in 30:
			await _tick(_aim(foe))
		for i in 60:
			if foe.state != "windup":
				break
			await _tick(_aim(foe))
		if kind == "bone_thrall":
			await _crop_shot("hitbox_mage", flow.session.sim.actor.position, 90)
		await _crop_shot("hitbox_" + kind, foe.target.position, 90)
	await _stage(3)
	canvas.show_debug = true
	var boss = flow.session.enemies[0]
	flow.session.sim.actor.position = boss.target.position + Vector2(-260, 0)
	for i in 200:
		await _tick({})
		if boss.state == "recover" and boss.state_tick >= 8:
			break
	await _crop_shot("hitbox_undead_warden", boss.target.position, 130)

func _run() -> void:
	await _hud_scene()
	for el in ["fire", "water", "lightning"]:
		await _cast_scene(el)
	await _arc_scene()
	for pair in [["bone_thrall", 150.0], ["fallen_adept", 300.0], ["grave_hound", 260.0]]:
		await _telegraph_scene(pair[0], pair[1])
	await _warden_scene()
	await _route_scene()
	await _editor_scene()
	await _hitbox_scene()
	var captured: Array = []
	var missing: Array = []
	for name in EXPECTED:
		(captured if saved.get(name, false) else missing).append(name)
	print("CAPTURED: ", captured, " MISSING: ", missing)
	quit(0)
