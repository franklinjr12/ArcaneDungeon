extends Control
## M3 playable vertical slice. This is only input/UI; all rules live in RunFlow.
const Flow = preload("res://world/run_flow.gd")
const ArenaCanvas = preload("res://ui/run_canvas.gd")
const TestCanvas = preload("res://ui/sandbox_canvas.gd")
var flow
var arena_canvas
var test_canvas
var sidebar: VBoxContainer
var info: Label
var notices: Label
var context: VBoxContainer
var editor_panel: PanelContainer
var editor_controls: VBoxContainer
var editor_preview: Label
var transition_veil: ColorRect
var current_notice := ""
var cast_pending := -1
var cursor := Vector2(400,440)
var opened_editor_ms := 0
var refresh_counter := 0
var editor_open := false
var scene_key := ""
var modal_actions: Array = []

func _ready() -> void:
	flow = Flow.new()
	_build()
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
	var scroll := ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	panel.add_child(scroll)
	sidebar = VBoxContainer.new()
	sidebar.custom_minimum_size = Vector2(288,0)
	sidebar.add_theme_constant_override("separation",8)
	scroll.add_child(sidebar)
	_button(sidebar,"Back to Menu",func(): get_tree().change_scene_to_file("res://scenes/main.tscn"))
	_heading(sidebar,"ARCANE DUNGEON / M3",21)
	info = Label.new()
	sidebar.add_child(info)
	notices = Label.new()
	notices.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	sidebar.add_child(notices)
	_heading(sidebar,"Actions",15)
	_button(sidebar,"Restart run (R)",func(): _restart())
	_button(sidebar,"Next room at EXIT (E)",func(): _exit())
	_button(sidebar,"Toggle edit policy (F2)",func(): _policy())
	_button(sidebar,"Open spell editor (Q)",func(): _open_editor(0))
	_button(sidebar,"Edit slot 2 (T)",func(): _open_editor(1))
	_button(sidebar,"Toggle debug (F3)",func():
		arena_canvas.show_debug = not arena_canvas.show_debug)
	_heading(sidebar,"Room / Workshop",15)
	context = VBoxContainer.new()
	context.add_theme_constant_override("separation",6)
	sidebar.add_child(context)
	var help := Label.new()
	help.text = "WASD move, mouse aim\nLMB/RMB cast, Space dodge\nE exit (when nearby)\nQ/T edit, R restart\nF2 edit policy / F3 debug\nWorkshop: test, buy, edit"
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

func _heading(parent: Node, title: String, fontsize: int = 15) -> void:
	var label := Label.new()
	label.text = title
	label.add_theme_font_size_override("font_size",fontsize)
	parent.add_child(label)

func _button(parent: Node, label: String, action: Callable) -> Button:
	var b := Button.new()
	b.text = label
	b.custom_minimum_size.y = 31
	b.pressed.connect(action)
	parent.add_child(b)
	return b

func _world_click(point: Vector2, button: int) -> void:
	if editor_open or flow.state != "fighting":
		return
	cursor = point
	cast_pending = 0 if button == MOUSE_BUTTON_LEFT else 1

func _test_click(point: Vector2, button: int) -> void:
	if editor_open or flow.state != "workshop":
		return
	var slot := 0 if button == MOUSE_BUTTON_LEFT else 1
	var dir: Vector2 = (point-flow.range_sim.actor.position).normalized()
	var result: Dictionary = flow.test_cast(slot,dir)
	current_notice = "Test cast: "+str(result.get("reason",""))
	_update_labels()

func _input(event: InputEvent) -> void:
	if not event is InputEventKey or not event.pressed or event.echo or editor_open:
		return
	match event.keycode:
		KEY_E: _exit()
		KEY_R: _restart()
		KEY_Q: _open_editor(0)
		KEY_T: _open_editor(1)
		KEY_F2: _policy()
		KEY_F3: arena_canvas.show_debug = not arena_canvas.show_debug

func _physics_process(_delta: float) -> void:
	if flow == null or not flow.initialized:
		return
	if not editor_open:
		if flow.state == "fighting":
			var dir := Input.get_vector("move_left","move_right","move_up","move_down")
			var aim: Vector2 = (arena_canvas.world_from_local(arena_canvas.get_local_mouse_position())-flow.session.sim.actor.position).normalized()
			if aim.is_zero_approx():
				aim = flow.session.player.facing
			var command := {"move":dir,"aim":aim,"cast":cast_pending,"cursor":cursor,
				"dodge":Input.is_action_just_pressed("dodge")}
			flow.step(command)
		elif flow.state in ["cleared","workshop"]:
			flow.move_after_clear({"move":Input.get_vector("move_left","move_right","move_up","move_down"),
				"aim":flow.session.player.facing})
		if flow.state == "workshop" and flow.range_sim != null:
			flow.range_sim.step()
	cast_pending = -1
	arena_canvas.queue_redraw()
	test_canvas.queue_redraw()
	refresh_counter += 1
	if refresh_counter%7 == 0:
		var key: String = str(flow.run.sequence_index)+":"+flow.state+":"+str(flow.reward_collected)
		if key != scene_key:
			_redraw_panel()
		else:
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
	arena_canvas.visible = flow.mode != "workshop"
	test_canvas.visible = flow.mode == "workshop"
	test_canvas.runner = flow.range_sim
	_clear(context)
	if flow.state == "dead":
		_heading(context,"DEFEATED — Restart to retry")
	elif flow.state == "error":
		_heading(context,"RUN DATA ERROR")
	elif flow.state == "fighting":
		_heading(context,"DEFEAT THE ENCOUNTER")
		if flow.encounter != null:
			_heading(context,"Waves scheduled: "+str(flow.encounter.schedule.size()),12)
	elif flow.state == "cleared":
		if flow.run.sequence_index == flow.config["rooms"].size()-1:
			_heading(context,"VERTICAL SLICE COMPLETE!",16)
			_button(context,"Replay from stage 1",func(): _restart())
		else:
			_heading(context,"ROOM CLEARED. EXIT UNLOCKED.")
		if flow.room.values["type"] != "boss" and not flow.reward_collected:
			_heading(context,"Choose ONE rune or currency:",13)
			for i in flow.reward_options.size():
				var item: Dictionary = flow.reward_options[i]
				var caption := ""
				if item["kind"] == "rune":
					var rune = flow.session.sim.registry.get_rune(str(item["id"]))
					caption = "Learn "+str(item["id"])+" — "+str(rune.snapshot()["description"])
				else:
					caption = "Take +"+str(item["amount"])+" currency"
				_button(context,caption,_choose_reward.bind(i))
		if flow.edit_policy == "cleared_room":
			_heading(context,"Quick edit allowed (no shop/test)",12)
		_button(context,"Advance at exit →",func(): _exit())
	elif flow.state == "workshop":
		_heading(context,"SAFE WORKSHOP",15)
		_heading(context,"Merchant — buy once per item",13)
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
		_button(context,"Reset test targets + mana",func():
			flow.enter_test_range()
			test_canvas.runner = flow.range_sim
			current_notice = "Safe test range reset")
		_button(context,"Prepare two Wet cluster targets",func():
			flow.prepare_wet_cluster()
			current_notice = "Wet cluster prepared: lightning arc can be tested")
		_button(context,"Refill test mana",func():
			flow.refill_test_mana()
			current_notice = "Test mana refilled")
		_button(context,"Continue to stage 2 at exit",func(): _exit())
	_update_labels()

func _update_labels() -> void:
	if flow == null:
		return
	var values: Dictionary = flow.snapshot()
	info.text = "Stage %d / Room %d\n%s [%s]\nHP %.0f/%.0f   Mana %.0f\nCoins %d / Unlocked runes %d\nDodge CD %d\nSlot1 %s\nSlot2 %s\nEdit policy: %s" % [
		int(flow.room.values["stage"])+1,int(flow.room.values["room"])+1,
		flow.room.values["id"],flow.state.to_upper(),flow.run.hp if flow.state != "fighting" else flow.session.sim.actor.health.current,
		flow.run.max_hp,flow.session.sim.mana,flow.run.currency,flow.run.unlocked.size(),
		flow.session.player.dodge_cooldown,
		str(flow.run.formulas[0]["display_name"]),str(flow.run.formulas[1]["display_name"]),flow.edit_policy]
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

func _choose_reward(i: int) -> void:
	var result: Dictionary = flow.choose_reward(i)
	current_notice = "Reward: "+str(result.get("kind",result.get("reason","")))
	_redraw_panel()

func _buy(i: int) -> void:
	var result: Dictionary = flow.buy(i)
	current_notice = "Merchant: "+str(result.get("kind",result.get("reason","")))
	_redraw_panel()

func _restart() -> void:
	_close_visual_editor()
	flow.start_new(flow.run.seed)
	current_notice = "New run: currencies / unlocks reset"
	_redraw_panel()

func _exit() -> void:
	if editor_open:
		return
	var result: Dictionary = flow.try_exit(flow.session.sim.actor.position)
	current_notice = "Door: "+str(result.get("reason","OPEN") if result["ok"] == false else "NEXT ROOM")
	if result["ok"]:
		_flash_transition()
	_redraw_panel()

func _flash_transition() -> void:
	transition_veil.modulate.a = 0.85
	var tween := create_tween()
	tween.tween_property(transition_veil,"modulate:a",0.0,0.4)

func _policy() -> void:
	var next := "cleared_room" if flow.edit_policy == "workshop_only" else "workshop_only"
	flow.change_edit_policy(next)
	current_notice = "Edit policy: "+next+" (test switch, not final rule)"
	_redraw_panel()

func _open_editor(index: int) -> void:
	if editor_open:
		return
	var result: Dictionary = flow.open_editor(index)
	if not result["ok"]:
		current_notice = "Editor: "+str(result.get("reason","BLOCKED"))
		_update_labels()
		return
	editor_open = true
	opened_editor_ms = Time.get_ticks_msec()
	editor_panel.visible = true
	_editor_rebuild()

func _editor_rebuild() -> void:
	_clear(editor_controls)
	var e = flow.editor
	_heading(editor_controls,"SPELL EDITOR / SLOT "+str(e.slot+1),20)
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
		editor_preview.text = "VALID / Mana %d / Complexity %d / Cooldown %d\n%s" % [
			verdict["mana"],verdict["complexity"],verdict["cooldown"],verdict["summary"]]
	else:
		editor_preview.text = "INVALID — cannot apply:\n"
		for issue in verdict["issues"]:
			editor_preview.text += str(issue["code"])+": "+str(issue["message"])+"\n"
	_button(editor_controls,"Undo",func(): e.undo(); _editor_rebuild())
	_button(editor_controls,"Reset draft",func(): e.reset_draft();_editor_rebuild())
	_button(editor_controls,"Cancel (restore original)",func(): _close_editor(false))
	var apply := _button(editor_controls,"Apply valid formula",func(): _close_editor(true))
	apply.disabled = not verdict["ok"]

func _option(parent: Node, list: Array, selection: String) -> OptionButton:
	var option := OptionButton.new()
	parent.add_child(option)
	var current := -1
	for i in list.size():
		var item: Dictionary = list[i]
		option.add_item(str(item["id"])+(" (locked)" if item["locked"] else ""))
		option.set_item_metadata(i,str(item["id"]))
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
	current_notice = "Formula "+("applied" if apply_changes else "cancelled")+" / %.1f s" % duration
	_close_visual_editor()
	_redraw_panel()
