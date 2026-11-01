extends Control
const VisualTheme = preload("res://ui/pixel_theme.gd")
## M3 playable vertical slice. This is only input/UI; all rules live in RunFlow.
const Flow = preload("res://world/run_flow.gd")
const ArenaCanvas = preload("res://ui/run_canvas.gd")
const TestCanvas = preload("res://ui/sandbox_canvas.gd")
const PortraitHUD = preload("res://ui/pixel_hud.gd")
const RuneAtlas = preload("res://assets/pixel/rune_icons.png")
const Prompts = preload("res://ui/onboarding_prompts.gd")
const Art = preload("res://ui/pixel_art_renderer.gd")
const InputActions = preload("res://ui/input_actions.gd")
const PauseMenu = preload("res://ui/pause_menu.gd")
const MerchantScript = preload("res://world/merchant.gd")
var flow
var guide = Prompts.new()
var tip: Label
var arena_canvas
var test_canvas
var sidebar: VBoxContainer
var portrait_hud
var info: Label
var notices: Label
var context: VBoxContainer
var editor_panel: PanelContainer
var editor_controls: VBoxContainer
var editor_preview: Label
var transition_veil: ColorRect
var current_notice := ""
var summary_retry_button: Button
var summary_new_seed_button: Button
var summary_title_button: Button
var cast_pending := -1
var cursor := Vector2(400,440)
var opened_editor_ms := 0
var refresh_counter := 0
var editor_open := false
var loadout_list: VBoxContainer
var loadout_slot_buttons: Array = []
var scene_key := ""
var modal_actions: Array = []
var display_frame_samples: Array = []
var low_fps := 0.0
var _stats_recorded := false
var _settings
var _director
var flavour: Dictionary = MerchantScript.load_flavour()
var _rift_shown := false
var pause_menu
var scroll: ScrollContainer
var _prev_mouse_mode := Input.MOUSE_MODE_VISIBLE

func _ready() -> void:
	VisualTheme.apply(self)
	flow = Flow.new()
	_director = get_node_or_null("/root/AudioDirector")
	if _director != null:
		flow.audio_sink = _director.play
		_director.play("amb.workshop" if flow.mode == "workshop" else "amb.ruins")
	var save = get_node_or_null("/root/SaveService")
	if save != null:
		_settings = save.settings
		if _settings.telemetry_opt_in:
			flow.experiment.configure(true)
		_settings.apply_audio()
	if save != null:
		guide.load_seen(save.profile["stats"].get("onboarding_seen", []))
	_build()
	current_notice = stage_banner()
	_redraw_panel()

func _build() -> void:
	var bg := ColorRect.new()
	bg.color = Color("#0b1320")
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(bg)
	var panel := PanelContainer.new()
	panel.position = Vector2(6,5)
	panel.size = Vector2(312,709)
	add_child(panel)
	scroll = ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	panel.add_child(scroll)
	sidebar = VBoxContainer.new()
	sidebar.custom_minimum_size = Vector2(288,0)
	sidebar.add_theme_constant_override("separation",8)
	scroll.add_child(sidebar)
	_button(sidebar,"Back to Menu",func(): get_tree().change_scene_to_file("res://scenes/main.tscn"),"ui.cancel")
	_heading(sidebar,"ARCANE DUNGEON / M4",21)
	portrait_hud = PortraitHUD.new()
	portrait_hud.flow = flow
	sidebar.add_child(portrait_hud)
	_heading(sidebar,"Room / Workshop",15)
	context = VBoxContainer.new()
	context.add_theme_constant_override("separation",6)
	sidebar.add_child(context)
	info = Label.new()
	sidebar.add_child(info)
	tip = Label.new()
	tip.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	tip.add_theme_font_size_override("font_size",11)
	sidebar.add_child(tip)
	var help_actions := HBoxContainer.new()
	sidebar.add_child(help_actions)
	_button(help_actions,"Dismiss tips",func(): _guide(false))
	_button(help_actions,"Show tips",func(): _guide(true))
	_button(sidebar,"Opt in / out of local telemetry",func():
		flow.experiment.configure(not flow.experiment.enabled)
		var save = get_node_or_null("/root/SaveService")
		if save != null:
			save.settings.telemetry_opt_in = flow.experiment.enabled
			save.save_settings()
		current_notice = "Local telemetry "+("ENABLED (export only)" if flow.experiment.enabled else "OFF / cleared")
		_update_labels())
	_button(sidebar,"Export opt-in JSON + CSV",func(): _export_metrics())
	notices = Label.new()
	notices.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	sidebar.add_child(notices)
	_heading(sidebar,"Actions",15)
	_button(sidebar,"Restart run (R)",func(): _retry_same_seed())
	_button(sidebar,"Next room at EXIT (F)",func(): _exit())
	_button(sidebar,"Toggle edit policy (F2)",func(): _policy())
	_button(sidebar,"Toggle debug (F3)",func():
		arena_canvas.show_debug = not arena_canvas.show_debug)
	_heading(sidebar,"Loadout",15)
	loadout_list = VBoxContainer.new()
	loadout_list.add_theme_constant_override("separation",4)
	sidebar.add_child(loadout_list)
	var help := Label.new()
	help.text = "WASD/Arrows move, mouse aim\nLMB/RMB/Q/E cast slots 1-4\nSpace dash, Esc pause\nF exit (when nearby), R retry same seed\nWorkshop: test, buy, edit\nWorkshop: T reset range, Q/E test slots 3-4"
	if InputActions.debug_keys_enabled():
		help.text += "\nF2 edit policy / F3 debug"
	help.add_theme_font_size_override("font_size",11)
	sidebar.add_child(help)
	arena_canvas = ArenaCanvas.new()
	arena_canvas.position = Vector2(325,35)
	arena_canvas.size = Vector2(916,650)
	arena_canvas.session = flow.session
	arena_canvas.run_flow = flow
	add_child(arena_canvas)
	arena_canvas.world_click.connect(_world_click)
	test_canvas = TestCanvas.new()
	test_canvas.position = arena_canvas.position
	test_canvas.size = arena_canvas.size
	test_canvas.runner = flow.range_sim
	test_canvas.visible = false
	add_child(test_canvas)
	test_canvas.world_click.connect(_test_click)
	transition_veil = ColorRect.new()
	transition_veil.position = arena_canvas.position
	transition_veil.size = arena_canvas.size
	transition_veil.color = Color("#0b1320")
	transition_veil.modulate.a = 0
	transition_veil.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(transition_veil)
	editor_panel = PanelContainer.new()
	editor_panel.position = Vector2(380,30)
	editor_panel.size = Vector2(500,665)
	editor_panel.visible = false
	add_child(editor_panel)
	var editor_scroll := ScrollContainer.new()
	editor_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	editor_panel.add_child(editor_scroll)
	editor_controls = VBoxContainer.new()
	editor_controls.custom_minimum_size = Vector2(470,0)
	editor_controls.add_theme_constant_override("separation",9)
	editor_scroll.add_child(editor_controls)
	pause_menu = PauseMenu.new()
	pause_menu.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	pause_menu.visible = false
	add_child(pause_menu)
	pause_menu.resume_requested.connect(close_pause)
	pause_menu.retry_confirmed.connect(_pause_retry)
	pause_menu.quit_confirmed.connect(_pause_quit)

func is_paused() -> bool:
	return pause_menu != null and pause_menu.visible

func can_pause() -> bool:
	return not editor_open and flow.state in ["fighting","cleared","workshop"]

func open_pause() -> void:
	if not can_pause() or is_paused():
		return
	_set_clocks_paused(true)
	_prev_mouse_mode = Input.mouse_mode
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	pause_menu.visible = true

func close_pause() -> void:
	if not is_paused():
		return
	if pause_menu.is_settings_open():
		pause_menu.close_settings()
	if pause_menu.is_confirm_open():
		pause_menu.cancel_confirm()
	pause_menu.visible = false
	_set_clocks_paused(false)
	Input.mouse_mode = _prev_mouse_mode

func _set_clocks_paused(on: bool) -> void:
	flow.session.sim.clock.set_paused(on)
	if flow.range_sim != null and flow.range_sim.get("clock") != null:
		flow.range_sim.clock.set_paused(on)

func _pause_retry() -> void:
	close_pause()
	_retry_same_seed()

func _pause_quit() -> void:
	var save = get_node_or_null("/root/SaveService")
	if save != null and not _stats_recorded:
		var s: Dictionary = flow.summary()
		s["outcome"] = "abandoned"
		save.record_run(s)
		_stats_recorded = true
	close_pause()
	_to_title()

func _heading(parent: Node, title: String, fontsize: int = 15) -> void:
	var label := Label.new()
	label.text = title
	label.add_theme_font_size_override("font_size",fontsize)
	if fontsize>=14:
		label.add_theme_color_override("font_color",Color("#efbc65"))
	parent.add_child(label)

func _button(parent: Node, label: String, action: Callable, press_cue: String = "ui.confirm") -> Button:
	var b := Button.new()
	if _director != null:
		_director.bind_button(b,press_cue)
	b.text = label
	b.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	b.custom_minimum_size.y = 31
	b.pressed.connect(action)
	parent.add_child(b)
	return b

func _world_click(point: Vector2, button: int) -> void:
	if is_paused() or editor_open or flow.state != "fighting":
		return
	cursor = point
	cast_pending = InputActions.slot_for_mouse_button(button)

func _test_click(point: Vector2, button: int) -> void:
	if is_paused() or editor_open or flow.state != "workshop":
		return
	_test_cast_slot(InputActions.slot_for_mouse_button(button),point)

func _test_cast_slot(slot: int, point: Vector2) -> Dictionary:
	var dir: Vector2 = (point-flow.range_sim.actor.position).normalized()
	var result: Dictionary = flow.test_cast(slot,dir)
	current_notice = "Test cast slot %d: %s" % [slot+1,str(result.get("reason",""))]
	_update_labels()
	return result

func _reset_test_range() -> void:
	flow.enter_test_range()
	test_canvas.runner = flow.range_sim
	current_notice = "Safe test range reset"
	_update_labels()

func _input(event: InputEvent) -> void:
	if is_paused():
		if event is InputEventKey:
			if event.pressed and not event.echo and event.is_action_pressed("pause"):
				pause_menu.handle_cancel()
			get_viewport().set_input_as_handled()
		return
	if editor_open or not event.is_pressed() or event.is_echo():
		return
	var fighting: bool = flow.state == "fighting"
	var slot := InputActions.cast_slot_for_event(event)
	if slot >= 2 and fighting:
		cursor = arena_canvas.world_from_local(arena_canvas.get_local_mouse_position())
		cast_pending = slot
	elif slot >= 2 and flow.state == "workshop" and flow.range_sim != null:
		_test_cast_slot(slot,test_canvas.get_local_mouse_position())
	elif event is InputEventKey and event.keycode >= KEY_1 and event.keycode <= KEY_9 			and flow.state == "cleared" and not flow.reward_collected 			and event.keycode-KEY_1 < flow.reward_options.size():
		_choose_reward(event.keycode-KEY_1)
	elif event.is_action_pressed("interact"):
		_exit()
	elif event.is_action_pressed("pause"):
		open_pause()
	elif event is InputEventKey:
		match event.keycode:
			KEY_R: _retry_same_seed()
			KEY_T:
				if flow.state == "workshop": _reset_test_range()
			KEY_F2:
				if InputActions.debug_keys_enabled(): _policy()
			KEY_F3:
				if InputActions.debug_keys_enabled(): arena_canvas.show_debug = not arena_canvas.show_debug
			KEY_F6:
				if InputActions.debug_keys_enabled(): Art.toggle_art_export(); arena_canvas.queue_redraw()

func _process(delta: float) -> void:
	if delta > 0 and delta < 2.0:
		var fps := 1.0/delta
		display_frame_samples.append(fps)
		if display_frame_samples.size() > 120:
			display_frame_samples.remove_at(0)
		low_fps = fps if low_fps <= 0.0 else minf(low_fps,fps)

func _physics_process(_delta: float) -> void:
	if flow == null or not flow.initialized:
		return
	if is_paused():
		cast_pending = -1
		return
	if not editor_open:
		if flow.state == "fighting":
			var dir := Input.get_vector("move_left","move_right","move_up","move_down")
			var aim: Vector2 = (arena_canvas.world_from_local(arena_canvas.get_local_mouse_position())-flow.session.sim.actor.position).normalized()
			if aim.is_zero_approx():
				aim = flow.session.player.facing
			var command := {"move":dir,"aim":aim,"cast":cast_pending,"cursor":cursor,
				"dash":Input.is_action_just_pressed("dash")}
			flow.step(command)
		elif flow.state in ["cleared","workshop"]:
			flow.move_after_clear({"move":Input.get_vector("move_left","move_right","move_up","move_down"),
				"aim":flow.session.player.facing})
		if flow.state == "workshop" and flow.range_sim != null:
			_move_test_mage(Input.get_vector("move_left","move_right","move_up","move_down"))
			flow.range_sim.step()
	cast_pending = -1
	arena_canvas.queue_redraw()
	portrait_hud.queue_redraw()
	test_canvas.queue_redraw()
	refresh_counter += 1
	if refresh_counter%7 == 0:
		var key: String = str(flow.run.sequence_index)+":"+flow.state+":"+str(flow.reward_collected)
		if key != scene_key:
			if flow.state == "cleared" and not flow.reward_collected and not flow.reward_options.is_empty():
				current_notice = "Room cleared! Pick a reward (keys 1-%d), then walk to EXIT and press F" % flow.reward_options.size()
			_redraw_panel()
		else:
			_update_labels()

func _move_test_mage(dir: Vector2) -> void:
	# The visible workshop mage lives in the test range; walk it inside the range canvas.
	var speed: float = float(flow.session.player.tuning["move_speed"])/float(flow.range_sim.clock.tick_rate)
	var bounds := Rect2(Vector2(20,20),test_canvas.size-Vector2(40,40))
	var actor = flow.range_sim.actor
	actor.position = (actor.position+dir.limit_length(1.0)*speed).clamp(bounds.position,bounds.end)

func room_display_name(room_id: String) -> String:
	return str(flavour.get("room_names", {}).get(room_id, room_id))

## Rift line is returned once per run (reset on retry / new seed).
func stage_banner() -> String:
	if _rift_shown:
		return ""
	_rift_shown = true
	return str(flavour.get("rift_line", ""))

func _guide(show: bool) -> void:
	if show:
		guide.reopen()
	else:
		guide.dismiss()
	_update_labels()

func _export_metrics() -> void:
	if not flow.experiment.enabled:
		current_notice = "Opt in first; data are kept locally and never uploaded."
	else:
		var a: Error = flow.experiment.export_json()
		var b: Error = flow.experiment.export_csv()
		current_notice = "Local files: user://arcane_m4_experiment.{json,csv}" if a == OK and b == OK else "Export failed"
	_update_labels()

func _clear(container: Node) -> void:
	for child in container.get_children():
		container.remove_child(child)
		child.queue_free()

func _redraw_panel() -> void:
	if flow == null:
		return
	scene_key = str(flow.run.sequence_index)+":"+flow.state+":"+str(flow.reward_collected)
	arena_canvas.session = flow.session
	arena_canvas.environment_id = 2 if flow.run.sequence_index>=5 else (1 if flow.room.values["type"]=="boss" else 0)
	portrait_hud.queue_redraw()
	arena_canvas.visible = flow.mode != "workshop"
	test_canvas.visible = flow.mode == "workshop"
	test_canvas.runner = flow.range_sim
	_rebuild_loadout()
	_clear(context)
	if scroll != null:
		scroll.scroll_vertical = 0
	summary_retry_button = null
	summary_new_seed_button = null
	summary_title_button = null
	if flow.state in ["dead","won"]:
		_build_summary_panel()
	elif flow.state == "error":
		_heading(context,"RUN DATA ERROR")
	elif flow.state == "fighting":
		_heading(context,"DEFEAT THE ENCOUNTER")
		if flow.encounter != null:
			_heading(context,"Waves scheduled: "+str(flow.encounter.schedule.size()),12)
	elif flow.state == "cleared":
		_heading(context,"ROOM CLEARED. EXIT UNLOCKED.")
		if flow.room.values["type"] != "boss" and not flow.reward_collected:
			_heading(context,"Choose ONE reward:",13)
			for i in flow.reward_options.size():
				var item: Dictionary = flow.reward_options[i]
				var caption := ""
				if item["kind"] == "rune":
					caption = str(item["name"])+": "+str(item["behaviour"])
				else:
					caption = "+"+str(item["amount"])+" currency"
				_button(context,"%d) %s" % [i+1,caption],_choose_reward.bind(i))
		if flow.edit_policy == "cleared_room":
			_heading(context,"Quick edit allowed (no shop/test)",12)
		_button(context,"Advance at exit →",func(): _exit())
	elif flow.state == "workshop":
		_heading(context,"SAFE WORKSHOP",15)
		_heading(context,str(flavour.get("merchant", {}).get("title", "Merchant"))+" — buy once per item",13)
		var greet := Label.new()
		greet.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		greet.text = flow.merchant.greeting(flow.run.seed)
		context.add_child(greet)
		for i in flow.merchant.stock.size():
			var item: Dictionary = flow.merchant.stock[i]
			var affordable: bool = int(item["price"]) <= flow.run.currency
			var b := _button(context,str(item["label"])+" / "+str(item["price"])+" coins",
				_buy.bind(i))
			b.disabled = flow.merchant.bought.has(item["id"]) or not affordable
			var detail := Label.new()
			detail.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
			detail.add_theme_font_size_override("font_size",11)
			var explanation := ""
			if item["kind"] == "rune":
				var rune = flow.session.sim.registry.get_rune(str(item["rune_id"]))
				explanation = str(rune.snapshot()["description"]) if rune != null else str(item["rune_id"])
			else:
				explanation = "Increase max HP by %d (run-persistent)" % int(item["amount"])
			detail.text = explanation+" | "+("Purchased" if flow.merchant.bought.has(item["id"]) else ("Affordable" if affordable else "Need "+str(int(item["price"])-flow.run.currency)+" coins"))
			context.add_child(detail)
		_heading(context,"Testing range: no progression/rewards",12)
		_button(context,"Reset test targets + mana (T)",func(): _reset_test_range())
		_button(context,"Prepare Wet cluster (2 targets)",func():
			flow.prepare_wet_cluster()
			current_notice = "Wet cluster prepared: lightning arc can be tested")
		_button(context,"Refill test mana",func():
			flow.refill_test_mana()
			current_notice = "Test mana refilled")
		_button(context,"Continue to stage 2 (F)",func(): _exit())
	_update_labels()

func _rebuild_loadout() -> void:
	_clear(loadout_list)
	loadout_slot_buttons = []
	var b := _button(loadout_list,"Slot 1: Basic Bolt [LOCKED]",func(): _open_editor(0))
	b.disabled = true
	loadout_slot_buttons.append(b)
	for n in range(2,5):
		var fi := n-2
		var label := str(flow.run.formulas[fi]["display_name"]) if fi < flow.run.formulas.size() else "(empty)"
		var sb := _button(loadout_list,"Slot %d: %s — Edit" % [n,label],_open_editor.bind(n-1))
		sb.disabled = fi > flow.run.formulas.size()
		loadout_slot_buttons.append(sb)

func _update_labels() -> void:
	if flow == null:
		return
	var values: Dictionary = flow.snapshot()
	info.text = "Stage %d / Room %d\n%s [%s]\nHP %.0f/%.0f   Mana %.0f\nCoins %d / Unlocked runes %d\nDash CD %d\nSlot1 Basic Bolt\nSlot2 %s\nSlot3 %s\nSlot4 %s\nEdit policy: %s" % [
		int(flow.room.values["stage"])+1,int(flow.room.values["room"])+1,
		room_display_name(str(flow.room.values["id"])),flow.state.to_upper(),flow.run.hp if flow.state != "fighting" else flow.session.sim.actor.health.current,
		flow.run.max_hp,flow.session.sim.mana,flow.run.currency,flow.run.unlocked.size(),
		flow.session.player.dash_cooldown,
		_slot_name(0),_slot_name(1),_slot_name(2),flow.edit_policy]
	info.text += "\nRender FPS %.0f / observed low %.0f" % [
		Engine.get_frames_per_second(),low_fps]
	if flow.mode == "workshop" and flow.range_sim != null:
		var trace = flow.range_sim.trace
		var reactions: int = trace.filter_records(-1,"","reaction").size()
		var triggers: int = trace.filter_records(-1,"","trigger").size()
		var caps: int = trace.filter_records(-1,"","budget_exceeded").size()
		var statuses: Array = []
		for item in flow.range_sim.inspect()["targets"]:
			for state_id in item["states"]:
				if state_id not in statuses:
					statuses.append(state_id)
		info.text += "\nTEST hits %d / active %d / mana %.0f\nStatuses %s | Reactions %d\nTriggers %d | Budget warnings %d" % [
			flow.range_sim.total_hit_count,flow.range_sim.queue.active_effect_count(),flow.range_sim.mana,
			",".join(statuses),reactions,triggers,caps]
	notices.text = current_notice
	if tip != null:
		var active := ""
		if flow.mode == "workshop":
			active = "first_workshop"
		elif flow.state == "fighting" and str(flow.room.values["id"]) == "s1_r1":
			active = "room1"
		elif flow.state == "cleared" and not flow.reward_collected:
			active = "first_reward"
		if active != "" and not guide.trigger(active).is_empty():
			_persist_tip(active)
		if guide.current != active:
			guide.current = ""
		tip.text = ("TIP: " + guide.text()) if guide.text() != "" else ""

func _persist_tip(id: String) -> void:
	var save = get_node_or_null("/root/SaveService")
	if save == null:
		return
	var ids: Array = save.profile["stats"].get("onboarding_seen", [])
	if not ids.has(id):
		ids.append(id)
		save.profile["stats"]["onboarding_seen"] = ids
		save.save_profile()

func _choose_reward(i: int) -> void:
	var result: Dictionary = flow.choose_reward(i)
	current_notice = "Reward: "+str(result.get("kind",result.get("reason","")))
	_redraw_panel()

func _buy(i: int) -> void:
	var result: Dictionary = flow.buy(i)
	current_notice = "Merchant: "+str(result.get("kind",result.get("reason","")))
	if result.get("ok",false):
		current_notice = flow.merchant.purchase_line(flow.run.purchases.size())
	_redraw_panel()

func _build_summary_panel() -> void:
	var stats: Dictionary = flow.summary()
	var save = get_node_or_null("/root/SaveService")
	if save != null and not _stats_recorded:
		_stats_recorded = true
		save.record_run(stats)
	_heading(context,"RUN SUMMARY — "+("VICTORY" if flow.state == "won" else "DEFEATED"),16)
	var seconds := int(stats["seconds"])
	for line in ["Rooms cleared: %d" % int(stats["rooms_cleared"]),"Kills: %d" % int(stats["kills"]),
			"Time: %d:%02d" % [seconds/60,seconds%60],"Spells used: %d" % int(stats["spells_used"]),
			"Seed: %d" % int(stats["seed"])]:
		var label := Label.new()
		label.text = line
		context.add_child(label)
	if save != null:
		var totals: Dictionary = save.stats()
		var label := Label.new()
		var best: float = totals["best_time_seconds"]
		label.text = "Runs: %d  Wins: %d  Best: %s" % [totals["runs"],totals["wins"],
			("%d:%02d" % [int(best)/60,int(best)%60]) if best >= 0.0 else "--"]
		context.add_child(label)
	summary_retry_button = _button(context,"Retry same seed",func(): _retry_same_seed())
	summary_new_seed_button = _button(context,"New seed",func(): _new_seed())
	summary_title_button = _button(context,"Title",func(): _to_title(),"ui.cancel")

func _retry_same_seed() -> void:
	close_pause()
	_close_visual_editor()
	_stats_recorded = false
	_rift_shown = false
	flow.retry_same_seed()
	current_notice = "Retry same seed: currencies / runes reset"
	_redraw_panel()

func _new_seed() -> void:
	close_pause()
	_close_visual_editor()
	_stats_recorded = false
	_rift_shown = false
	flow.start_new_seed()
	current_notice = "New seed: currencies / runes reset"
	_redraw_panel()

func _to_title() -> void:
	close_pause()
	get_tree().change_scene_to_file("res://scenes/main.tscn")

func _exit() -> void:
	if editor_open:
		return
	var result: Dictionary = flow.try_exit(flow.session.sim.actor.position)
	current_notice = "Door: "+str(result.get("reason","OPEN") if result["ok"] == false else "NEXT ROOM")
	if result["ok"]:
		_flash_transition()
	_redraw_panel()

func _flash_transition() -> void:
	if _settings != null and _settings.reduce_flashes:
		return
	transition_veil.modulate.a = 0.85
	var tween := create_tween()
	tween.tween_property(transition_veil,"modulate:a",0.0,0.4)

func _policy() -> void:
	var next := "cleared_room" if flow.edit_policy == "workshop_only" else "workshop_only"
	flow.change_edit_policy(next)
	current_notice = "Edit policy: "+next+" (test switch, not final rule)"
	_redraw_panel()

func _slot_name(fi: int) -> String:
	return str(flow.run.formulas[fi]["display_name"]) if fi < flow.run.formulas.size() else "(empty)"

func _open_editor(index: int) -> void:
	if editor_open:
		return
	if index <= 0:
		current_notice = "Slot 1 is locked (Basic Bolt) — cannot edit"
		_update_labels()
		return
	var result: Dictionary = flow.open_editor(index-1)
	if not result["ok"]:
		current_notice = "Editor: "+str(result.get("reason","BLOCKED"))
		_update_labels()
		return
	editor_open = true
	opened_editor_ms = Time.get_ticks_msec()
	editor_panel.visible = true
	_editor_rebuild()
	_update_labels()

func _editor_rebuild() -> void:
	_clear(editor_controls)
	var e = flow.editor
	_heading(editor_controls,"SPELL EDITOR / SLOT "+str(e.slot+2),20)
	_heading(editor_controls,"Essence → Manifestation → Modifier → On Hit",12)
	_heading(editor_controls,"Essence",14)
	var essence: OptionButton = _option(editor_controls,e.available("essence"),str(e.draft["root"]["essence_id"]))
	essence.item_selected.connect(func(idx):
		e.set_root(str(essence.get_item_metadata(idx)),str(e.draft["root"]["manifestation_id"]))
		_editor_rebuild())
	_heading(editor_controls,"Manifestation",14)
	var form: OptionButton = _option(editor_controls,e.available("form"),str(e.draft["root"]["manifestation_id"]))
	form.item_selected.connect(func(idx):
		e.set_root(str(e.draft["root"]["essence_id"]),str(form.get_item_metadata(idx)))
		_editor_rebuild())
	_heading(editor_controls,"Projectile modifiers",14)
	for item in e.available("modifier"):
		var b := CheckBox.new()
		b.text = str(item["id"])+(" [LOCKED]" if item["locked"] else "")
		b.button_pressed = str(item["id"]) in e.draft["root"]["modifier_ids"]
		b.disabled = bool(item["locked"]) or str(e.draft["root"]["manifestation_id"]) != "form.projectile"
		editor_controls.add_child(b)
		b.toggled.connect(func(_enabled): e.toggle_modifier(str(item["id"]));_editor_rebuild())
	var onhit := CheckBox.new()
	onhit.text = "On Hit → Burst child"
	onhit.button_pressed = e.draft.has("on_hit")
	onhit.disabled = "trigger.on_hit" not in e.run.unlocked or str(e.draft["root"]["manifestation_id"]) != "form.projectile"
	editor_controls.add_child(onhit)
	onhit.toggled.connect(func(enabled):
		e.set_trigger(enabled)
		_editor_rebuild())
	if e.draft.has("on_hit"):
		_heading(editor_controls,"Child Burst Essence",14)
		var child: OptionButton = _option(editor_controls,e.available("essence"),
			str(e.draft["on_hit"]["payload"]["essence_id"]))
		child.item_selected.connect(func(idx):
			e.change_payload_essence(str(child.get_item_metadata(idx)))
			_editor_rebuild())
	editor_preview = Label.new()
	editor_preview.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	editor_controls.add_child(editor_preview)
	var verdict: Dictionary = e.validate()
	if verdict["ok"]:
		editor_preview.text = "VALID / Mana %d / Cooldown %d ticks / Complexity %d / %d cap\n%s" % [
			verdict["mana"],verdict["cooldown"],verdict["complexity"],verdict["complexity_cap"],verdict["summary"]]
	else:
		editor_preview.text = "INVALID — cannot apply:\n"
		for issue in verdict["issues"]:
			editor_preview.text += str(issue["code"])+": "+str(issue["message"])+"\n"
	_button(editor_controls,"Undo",func(): e.undo(); _editor_rebuild())
	_button(editor_controls,"Reset draft",func(): e.reset_draft();_editor_rebuild())
	_button(editor_controls,"Cancel (restore original)",func(): _close_editor(false),"ui.cancel")
	var apply := _button(editor_controls,"Apply valid formula",func(): _close_editor(true))
	apply.disabled = not verdict["ok"]

func _rune_icon(rune_id: String) -> Texture2D:
	var names := ["essence.fire","essence.water","essence.lightning","form.projectile","form.burst","form.orb",
		"mod.homing","mod.split","mod.pierce","trigger.on_hit"]
	var index := names.find(rune_id)
	if index<0:
		return null
	var texture := AtlasTexture.new()
	texture.atlas = RuneAtlas
	texture.region = Rect2(Vector2(float(index%8*32),float((index/8)*32)),Vector2(32,32))
	return texture

func _option(parent: Node, list: Array, selection: String) -> OptionButton:
	var option := OptionButton.new()
	parent.add_child(option)
	var current := -1
	for i in list.size():
		var item: Dictionary = list[i]
		option.add_item(str(item["id"])+(" (locked)" if item["locked"] else ""))
		option.set_item_metadata(i,str(item["id"]))
		var rune_icon: Texture2D = _rune_icon(str(item["id"]))
		if rune_icon != null:
			option.set_item_icon(i,rune_icon)
		option.set_item_disabled(i,bool(item["locked"]))
		if str(item["id"]) == selection:
			current = i
	if current >= 0:
		option.select(current)
	return option

func _close_visual_editor() -> void:
	editor_open = false
	if editor_panel != null:
		editor_panel.visible = false

func _close_editor(apply_changes: bool) -> void:
	var duration := float(Time.get_ticks_msec()-opened_editor_ms)/1000.0
	var result: Dictionary = flow.close_editor(apply_changes,duration)
	if not result["ok"]:
		current_notice = "Editor: "+str(result.get("reason","INVALID"))
		_editor_rebuild()
		return
	current_notice = ("Formula applied" if apply_changes else "Formula cancelled")+" / %.1f s" % duration
	_close_visual_editor()
	_redraw_panel()
