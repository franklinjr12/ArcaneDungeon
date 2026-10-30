extends Control
const VisualTheme = preload("res://ui/pixel_theme.gd")
## Combat arena scene: input adapter and readable debug/HUD, gameplay lives in CombatSession.
const Session = preload("res://combat/combat_session.gd")
const Canvas = preload("res://ui/combat_canvas.gd")
const Art = preload("res://ui/pixel_art_renderer.gd")
const InputActions = preload("res://ui/input_actions.gd")
var session
var canvas
var hud: Label
var status_line: Label
var tips: Label
var overlay: ColorRect
var pending_cast := -1
var target_point := Vector2(400,400)
var seed := 5160
var scenario := "single"
var starter := 0
var refresh_counter := 0

func _ready() -> void:
	VisualTheme.apply(self)
	session = Session.new(seed,scenario,starter)
	_build()
	_refresh()

func _build() -> void:
	var bg := ColorRect.new()
	bg.color = Color("#0b101b")
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(bg)
	var side := PanelContainer.new()
	side.position = Vector2(8,8)
	side.size = Vector2(305,704)
	add_child(side)
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation",9)
	side.add_child(column)
	var back := Button.new()
	back.text = "Back to Menu"
	column.add_child(back)
	back.pressed.connect(func(): get_tree().change_scene_to_file("res://scenes/main.tscn"))
	var header := Label.new()
	header.text = "ARCANE DUNGEON / M2 COMBAT"
	header.add_theme_font_size_override("font_size",18)
	column.add_child(header)
	tips = Label.new()
	tips.text = "WASD/Arrows Move   Mouse Aim\nLMB / RMB / Q / E: Cast slot 1-4\nSPACE Dash   ESC Pause\nR: Retry  TAB: Starter loadout"
	if InputActions.debug_keys_enabled():
		tips.text += "\nF3: Debug  F4: Reduce hit flashes\n1 / 2 / 3: Arena scenario"
	tips.add_theme_font_size_override("font_size",12)
	column.add_child(tips)
	var scenarios := GridContainer.new()
	scenarios.columns = 3
	column.add_child(scenarios)
	for item in [["Single","single"],["Mixed","mixed"],["Cluster","cluster"]]:
		var b := Button.new()
		b.text = item[0]
		b.custom_minimum_size.x = 91
		scenarios.add_child(b)
		b.pressed.connect(_choose_scenario.bind(item[1]))
	var actions := GridContainer.new()
	actions.columns = 2
	column.add_child(actions)
	for item in [["Retry","retry"],["Loadout","loadout"],["Pause Esc","pause"],["Debug F3","debug"],["Flash F4","flash"]]:
		var b := Button.new()
		b.text = item[0]
		b.custom_minimum_size = Vector2(131,34)
		actions.add_child(b)
		b.pressed.connect(_command.bind(item[1]))
	hud = Label.new()
	hud.add_theme_font_size_override("font_size",13)
	column.add_child(hud)
	status_line = Label.new()
	status_line.add_theme_font_size_override("font_size",13)
	column.add_child(status_line)
	canvas = Canvas.new()
	canvas.position = Vector2(329,35)
	canvas.size = Vector2(float(session.data["arena"]["viewport_width"]),float(session.data["arena"]["viewport_height"]))
	canvas.session = session
	add_child(canvas)
	canvas.world_click.connect(_click)
	overlay = ColorRect.new()
	overlay.color = Color("#fff4e1")
	overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
	overlay.position = canvas.position
	overlay.size = canvas.size
	overlay.visible = false
	add_child(overlay)

func _click(point: Vector2, button: int) -> void:
	if session.state != "playing" or session.sim.clock.paused:
		return
	target_point = point
	pending_cast = InputActions.slot_for_mouse_button(button)

func _input(event: InputEvent) -> void:
	if not event.is_pressed() or event.is_echo():
		return
	var slot := InputActions.cast_slot_for_event(event)
	if slot >= 2:
		if session.state == "playing" and not session.sim.clock.paused:
			pending_cast = slot
			target_point = canvas.world_from_local(canvas.get_local_mouse_position())
	elif event.is_action_pressed("pause"):
		_command("pause")
	elif event is InputEventKey:
		match event.keycode:
			KEY_TAB: _command("loadout")
			KEY_R: _command("retry")
		if InputActions.debug_keys_enabled():
			match event.keycode:
				KEY_1: _choose_scenario("single")
				KEY_2: _choose_scenario("mixed")
				KEY_3: _choose_scenario("cluster")
				KEY_F3: _command("debug")
				KEY_F4: _command("flash")
				KEY_F6:
					Art.toggle_art_export()
					canvas.queue_redraw()

func _choose_scenario(key: String) -> void:
	scenario = key
	session.restart(seed,scenario,starter)
	pending_cast = -1
	_refresh()

func _command(key: String) -> void:
	match key:
		"retry":
			session.restart(seed,scenario,starter)
			pending_cast = -1
		"loadout":
			starter = (starter+1)%session.data["starter_loadouts"].size()
			session.restart(seed,scenario,starter)
			pending_cast = -1
		"pause":
			if session.state == "playing":
				session.sim.clock.set_paused(not session.sim.clock.paused)
		"debug":
			session.debug_overlay = not session.debug_overlay
			canvas.show_debug = session.debug_overlay
		"flash":
			session.reduce_flashes = not session.reduce_flashes
	_refresh()

func _physics_process(_dt: float) -> void:
	if session == null or not session.initialized:
		return
	var direction := Input.get_vector("move_left","move_right","move_up","move_down")
	var aiming: Vector2 = (canvas.world_from_local(canvas.get_local_mouse_position())-session.sim.actor.position).normalized()
	if aiming.is_zero_approx():
		aiming = session.player.facing
	var command := {"move":direction,"aim":aiming,"cast":pending_cast,
		"cursor":target_point,"dash":Input.is_action_just_pressed("dash")}
	pending_cast = -1
	if session.state == "playing" and not session.sim.clock.paused:
		session.issue(command)
		session.step()
	canvas.queue_redraw()
	refresh_counter += 1
	if refresh_counter % 5 == 0:
		_refresh()
	if overlay != null:
		overlay.visible = session.player.hit_flash > 0 and not session.reduce_flashes and session.player.hit_flash % 3 == 0
		overlay.color = Color(0.95,0.88,0.8,0.055)

func _refresh() -> void:
	if session == null or hud == null:
		return
	var snap: Dictionary = session.snapshot()
	var a: Dictionary = session.sim.loadout.preview(0)
	var b: Dictionary = session.sim.loadout.preview(1)
	var cds: Array = session.sim.loadout.slots
	hud.text = "HP %d / %d\nMANA %d / %d\n\nSLOT 1: %s\nMana %d | CD %d | Complexity %d\n\nSLOT 2: %s\nMana %d | CD %d | Complexity %d\n\nDash %s / %d ticks\nI-FRAMES %d / RECOVER %d\n\nEnemies: %d  Effects: %d" % [
		roundi(snap["player_hp"]),roundi(session.sim.actor.health.maximum),roundi(snap["player_mana"]),
		roundi(float(session.sim.settings["combat"]["player_max_mana"])),
		a.get("formula_id",""),a.get("mana",0),cds[0]["cooldown"],a.get("complexity",0),
		b.get("formula_id",""),b.get("mana",0),cds[1]["cooldown"],b.get("complexity",0),
		"READY" if session.player.dash_cooldown == 0 else "COOLDOWN",
		session.player.dash_cooldown,session.player.invulnerable_left,session.player.recovery_left,
		snap["enemy_count"],snap["effects"]]
	var last_cast: String = str(session.player.last_message)
	var recent: Array = session.sim.trace.snapshot()
	var latest := ""
	for entry in recent:
		if entry["type"] == "reaction":
			latest = "ARC! Wet + Lightning"
		elif entry["type"] == "status":
			latest = str(entry.get("reason",""))
	status_line.text = "State: %s\nCast: %s\nElement: %s\nDamage taken: %.1f\nDashes %d | Casts %d\nFPS %d | Logic %.2fms\n%s" % [
		session.state.to_upper(),last_cast,latest,snap["damage_taken"],snap["dashes"],snap["casts"],
		Engine.get_frames_per_second(),snap["frame_ms"],"FLASHES REDUCED" if session.reduce_flashes else ""]
