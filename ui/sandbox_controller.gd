extends Control
const VisualTheme = preload("res://ui/pixel_theme.gd")
## TASK-025 interaction playground, not production M2 player controller.
const Runner = preload("res://magic/runtime/spell_runner.gd")
const Canvas = preload("res://ui/sandbox_canvas.gd")
const Profiler = preload("res://debug/stress_profiler.gd")
var sim
var samples: Array = []
var surface
var stats: Label
var details: Label
var inspection: Label
var trace_label: Label
var slot_label: Label
var pause_button: Button
var slot := 0
var inspected_id := -1
var run_seed_value := 12345
var last_notice := ""
var refresh_count := 0

func _ready() -> void:
	VisualTheme.apply(self)
	var file := FileAccess.open("res://magic/data/sandbox_samples_v1.json",FileAccess.READ)
	if file == null:
		push_error("M1 samples missing")
		return
	var parsed = JSON.parse_string(file.get_as_text())
	if typeof(parsed) != TYPE_DICTIONARY or not parsed.has("formulas"):
		push_error("Invalid M1 samples")
		return
	samples = parsed["formulas"]
	sim = Runner.new(run_seed_value)
	if not sim.initialized:
		return
	sim.fill_targets()
	sim.equip(0,samples[0])
	sim.equip(1,samples[1])
	_build()
	_refresh()

func _build() -> void:
	var background := ColorRect.new()
	background.color = Color("#0c1320")
	background.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(background)
	var side := PanelContainer.new()
	side.position = Vector2(8,8)
	side.size = Vector2(305,704)
	add_child(side)
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation",4)
	side.add_child(col)
	# Navigation smoke test expects the first Button to be Back.
	var home := Button.new()
	home.text = "Back to Menu"
	home.custom_minimum_size.y = 28
	col.add_child(home)
	home.pressed.connect(func(): get_tree().change_scene_to_file("res://scenes/main.tscn"))
	var title := Label.new()
	title.text = "MAGIC SANDBOX  /  M1"
	title.add_theme_font_size_override("font_size",20)
	col.add_child(title)
	var hint := Label.new()
	hint.text = "LMB/RMB cast • WASD debug move"
	hint.add_theme_font_size_override("font_size",11)
	col.add_child(hint)
	slot_label = Label.new()
	col.add_child(slot_label)
	var buttons := HBoxContainer.new()
	col.add_child(buttons)
	for i in 2:
		var btn := Button.new()
		btn.text = "Equip to slot "+str(i+1)
		btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		btn.pressed.connect(_select_slot.bind(i))
		buttons.add_child(btn)
	var caption := Label.new()
	caption.text = "Select formula for highlighted slot"
	col.add_child(caption)
	for index in samples.size():
		var btn := Button.new()
		btn.text = "%d. %s" % [index+1,str(samples[index]["display_name"])]
		btn.alignment = HORIZONTAL_ALIGNMENT_LEFT
		btn.custom_minimum_size.y = 25
		btn.pressed.connect(_equip_sample.bind(index))
		col.add_child(btn)
	var grid := GridContainer.new()
	grid.columns = 3
	col.add_child(grid)
	for entry in [["Reset","reset"],["Mana","mana"],["Pause","pause"],["Step","step"],["Dummy","dummy"],["Moving","moving"],["Stress","stress"],["Profile","profile"],["Export","export"],["Seed+","seed"]]:
		var b := Button.new()
		b.text = entry[0]
		b.custom_minimum_size = Vector2(87,28)
		b.pressed.connect(_command.bind(entry[1]))
		grid.add_child(b)
		if entry[1] == "pause":
			pause_button = b
	details = Label.new()
	details.add_theme_font_size_override("font_size",10)
	col.add_child(details)
	stats = Label.new()
	stats.add_theme_font_size_override("font_size",11)
	col.add_child(stats)
	inspection = Label.new()
	inspection.add_theme_font_size_override("font_size",10)
	col.add_child(inspection)
	trace_label = Label.new()
	trace_label.add_theme_font_size_override("font_size",10)
	col.add_child(trace_label)
	surface = Canvas.new()
	surface.position = Vector2(324,20)
	surface.size = Vector2(920,680)
	surface.runner = sim
	add_child(surface)
	surface.world_click.connect(_cast_or_inspect)

func _select_slot(index: int) -> void:
	slot = index
	_refresh()

func _equip_sample(index: int) -> void:
	var result: Dictionary = sim.equip(slot,samples[index])
	last_notice = "Equipped "+str(samples[index]["display_name"]) if result["ok"] else str(result["reason"])
	_refresh()

func _cast_or_inspect(point: Vector2, button: int) -> void:
	if button == MOUSE_BUTTON_MIDDLE:
		var nearby: Array = sim.targets.query(point,26,sim.actor.team)
		inspected_id = nearby[0].id if not nearby.is_empty() else -1
		surface.selected_id = inspected_id
		_refresh()
		return
	var source_slot := 0 if button == MOUSE_BUTTON_LEFT else 1
	var plan = sim.loadout.get_plan(source_slot)
	if plan == null:
		return
	var origin: Vector2 = sim.actor.position
	if str(plan.snapshot()["root"]["manifestation"]["id"]) == "form.burst":
		origin = point
	var direction: Vector2 = (point-sim.actor.position).normalized()
	if direction.is_zero_approx():
		direction = Vector2.RIGHT
	var result: Dictionary = sim.try_cast(source_slot,origin,direction)
	last_notice = "Cast "+str(result["cast_id"]) if result["accepted"] else str(result["reason"])
	_refresh()

func _command(command: String) -> void:
	match command:
		"reset":
			sim.reset(run_seed_value)
			sim.fill_targets()
			sim.equip(0,samples[0])
			sim.equip(1,samples[1])
			inspected_id = -1
			surface.selected_id = -1
			last_notice = "Reset reproducibly with seed "+str(run_seed_value)
		"mana":
			sim.mana = float(sim.settings["combat"]["player_max_mana"])
			last_notice = "Mana reset"
		"pause":
			sim.clock.set_paused(not sim.clock.paused)
			last_notice = "Paused" if sim.clock.paused else "Resumed"
		"step":
			sim.advance_one_tick()
			last_notice = "One simulation tick"
		"dummy":
			sim.add_target(surface.hover)
			last_notice = "Stationary dummy spawned"
		"moving":
			sim.add_target(surface.hover,Vector2(80,35))
			last_notice = "Moving dummy spawned"
		"stress":
			var data: Dictionary = sim.stress()
			last_notice = "Stress: %d / 10000 effects, cap %d" % [data["accepted"],data["cap"]]
		"profile":
			var report: Dictionary = Profiler.benchmark(run_seed_value,180,40)
			last_notice = "M4 40 targets: %.2f mean / %.2f p95 ms, hit %d, drop %d" % [
				report["mean_tick_ms"],report["p95_tick_ms"],report["hit_records"],report["budget_drop_records"]]
			print("M4_PROFILE:",JSON.stringify(report))
		"export":
			var result: Error = sim.trace.export_json("user://magic_sandbox_trace.json")
			last_notice = "Trace exported to user://magic_sandbox_trace.json" if result == OK else "Trace export failed"
		"seed":
			run_seed_value += 1
			last_notice = "Next reset seed "+str(run_seed_value)
	if pause_button != null:
		pause_button.text = "Resume" if sim.clock.paused else "Pause"
	_refresh()

func _physics_process(_delta: float) -> void:
	if sim == null or not sim.initialized:
		return
	if not sim.clock.paused:
		# Movement here is purely a sandbox positioning aid. M2 owns player locomotion.
		var direction := Input.get_vector("move_left","move_right","move_up","move_down")
		sim.actor.position += direction * float(sim.settings["sandbox"]["move_debug_speed"])/float(sim.clock.tick_rate)
		sim.actor.position.x = clampf(sim.actor.position.x,20,sim.bounds.end.x-20)
		sim.actor.position.y = clampf(sim.actor.position.y,20,sim.bounds.end.y-20)
	sim.step()
	if surface != null:
		surface.queue_redraw()
	refresh_count += 1
	if refresh_count % 6 == 0:
		_refresh()

func _refresh() -> void:
	if sim == null or stats == null:
		return
	var snapshot: Dictionary = sim.inspect()
	slot_label.text = "Selected edit slot: "+str(slot+1)
	var one: Dictionary = sim.loadout.preview(0)
	var two: Dictionary = sim.loadout.preview(1)
	details.text = "1: %s / %d mana / CD %d / C%d\n2: %s / %d mana / CD %d / C%d" % [
		one.get("formula_id","empty"),one.get("mana",0),one.get("cooldown",0),one.get("complexity",0),
		two.get("formula_id","empty"),two.get("mana",0),two.get("cooldown",0),two.get("complexity",0)]
	stats.text = "tick %d / mana %.1f / active %d\nHits %d / DPS(3s) %.1f / seed %d\nM1 budgets: effects/cast %d; events %d\nactive %d/%d; depth %d; arcs %d" % [
		snapshot["tick"],snapshot["mana"],snapshot["active_effects"],snapshot["total_hits"],snapshot["dps"],snapshot["seed"],
		sim.limits.get_limit("max_effects_per_cast"),sim.limits.get_limit("max_events_per_root_cast"),
		snapshot["active_effects"],sim.limits.get_limit("max_active_effects"),
		sim.limits.get_limit("max_event_depth"),sim.limits.get_limit("max_chain_targets")]
	var observed = sim.targets.get_target(inspected_id)
	inspection.text = "MMB inspect • "+last_notice
	if observed != null:
		inspection.text = "#%d: HP %.0f, hits %d, states %s" % [
			observed.id,observed.health.current,observed.hit_count,
			str(observed.status.snapshot(sim.clock.tick).keys())]
	var records: Array = sim.trace.snapshot()
	var lines: Array = []
	for i in range(maxi(0,records.size()-3),records.size()):
		var row: Dictionary = records[i]
