extends Control
const ReduceMotion = preload("res://ui/reduce_motion.gd")
const VisualTheme = preload("res://ui/pixel_theme.gd")
## M3 playable vertical slice. This is only input/UI; all rules live in RunFlow.
const Flow = preload("res://world/run_flow.gd")
const ArenaCanvas = preload("res://ui/run_canvas.gd")
const TestCanvas = preload("res://ui/sandbox_canvas.gd")
const PortraitHUD = preload("res://ui/pixel_hud.gd")
const ShopCard = preload("res://art/export/ui/ad_ui_tooltip_and_shop_card.png")
const RewardCard = preload("res://art/export/ui/ad_ui_reward_card.png")
const Prompts = preload("res://ui/onboarding_prompts.gd")
const Art = preload("res://ui/pixel_art_renderer.gd")
const InputActions = preload("res://ui/input_actions.gd")
const PauseMenu = preload("res://ui/pause_menu.gd")
const MerchantScript = preload("res://world/merchant.gd")
var flow
var guide = Prompts.new()
var tip: Label
var tip_panel: PanelContainer
var notice_panel: PanelContainer
var objective: Label
var coins_label: Label
var pause_button: Button
var workshop_holder: MarginContainer
var workshop_column: VBoxContainer
var reward_overlay: CenterContainer
var reward_panel: PanelContainer
var summary_overlay: Control
var shop_overlay: Control
var shop_panel: PanelContainer
var shop_list: VBoxContainer
var shop_open := false
var _shop_offered := false
var shop_reopen_button: Button
var shop_close_button: Button
var summary_panel: PanelContainer
var dev_panel: PanelContainer
var dev_label: Label
## null = resolve from OS.is_debug_build() in _ready (same meaning as main_menu.show_debug_entries); tests set false before add_child.
var show_dev_tools = null
var _notice_seen := ""
var _notice_until_ms := 0
var _last_wet_kills := 0
var _last_arcs := 0
const TELEMETRY_INDEX := {"room1":3,"first_reward":4,"first_workshop":5}
var arena_canvas
var test_canvas
var portrait_hud # alias of arena_canvas.slot_hud (the only HP/MP display)
var info: Label
var notices: Label
var context: VBoxContainer
var editor_panel: PanelContainer
var editor_dock: MarginContainer
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
var arena_area: Control
const SCREEN_MARGIN := 6
const WORKSHOP_PANEL_WIDTH := 360.0
const TOP_BAR_HEIGHT := 44
const NOTICE_MS := 5000
const TEST_RANGE_SIZE := Vector2(916,650)
const EDITOR_SIZE := Vector2(500,665)
var _prev_mouse_mode := Input.MOUSE_MODE_VISIBLE

func _ready() -> void:
	VisualTheme.apply(self)
	if show_dev_tools == null:
		show_dev_tools = OS.is_debug_build()
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
			flow.experiment.begin_session()
		_settings.apply_audio()
	if save != null:
		guide.load_seen(save.profile["stats"].get("onboarding_seen", []))
	_build()
	current_notice = stage_banner()
	_redraw_panel()
	_debug_shot_entry()

func _build() -> void:
	var bg := ColorRect.new()
	bg.color = Color("#0b1320")
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(bg)
	var margin := MarginContainer.new()
	margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	margin.mouse_filter = Control.MOUSE_FILTER_IGNORE
	for side in ["left","top","right","bottom"]:
		margin.add_theme_constant_override("margin_"+side,SCREEN_MARGIN)
	add_child(margin)
	var layout := HBoxContainer.new()
	layout.mouse_filter = Control.MOUSE_FILTER_IGNORE
	layout.add_theme_constant_override("separation",SCREEN_MARGIN)
	margin.add_child(layout)
	arena_area = Control.new()
	arena_area.name = "ArenaArea"
	arena_area.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	arena_area.size_flags_vertical = Control.SIZE_EXPAND_FILL
	arena_area.mouse_filter = Control.MOUSE_FILTER_IGNORE
	arena_area.clip_contents = true
	layout.add_child(arena_area)
	arena_canvas = ArenaCanvas.new()
	arena_canvas.settings = _settings
	arena_canvas.session = flow.session
	arena_canvas.run_flow = flow
	arena_area.add_child(arena_canvas)
	portrait_hud = arena_canvas.slot_hud # the bottom HUD is the only HP/MP display
	arena_canvas.world_click.connect(_world_click)
	test_canvas = TestCanvas.new()
	test_canvas.size = TEST_RANGE_SIZE
	test_canvas.runner = flow.range_sim
	test_canvas.visible = false
	arena_area.add_child(test_canvas)
	test_canvas.world_click.connect(_test_click)
	transition_veil = ColorRect.new()
	transition_veil.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	transition_veil.color = Color("#0b1320")
	transition_veil.modulate.a = 0
	transition_veil.mouse_filter = Control.MOUSE_FILTER_IGNORE
	arena_area.add_child(transition_veil)
	shop_overlay = Control.new()
	shop_overlay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	shop_overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
	shop_overlay.visible = false
	arena_area.add_child(shop_overlay)
	var shop_centre := CenterContainer.new()
	shop_centre.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	shop_centre.mouse_filter = Control.MOUSE_FILTER_IGNORE
	shop_overlay.add_child(shop_centre)
	shop_panel = PanelContainer.new()
	shop_panel.mouse_filter = Control.MOUSE_FILTER_STOP
	shop_centre.add_child(shop_panel)
	shop_list = VBoxContainer.new()
	shop_list.add_theme_constant_override("separation",6)
	shop_panel.add_child(shop_list)
	arena_area.resized.connect(_fit_test_canvas)
	arena_area.resized.connect(_fit_arena)
	get_window().size_changed.connect(_fit_arena)
	_build_workshop_panel(layout)
	_build_top_bar()
	_build_overlays()
	editor_dock = MarginContainer.new()
	editor_dock.add_theme_constant_override("margin_top",TOP_BAR_HEIGHT)
	editor_dock.mouse_filter = Control.MOUSE_FILTER_IGNORE
	editor_dock.visible = false
	layout.add_child(editor_dock)
	editor_panel = PanelContainer.new()
	editor_panel.visible = false
	editor_dock.add_child(editor_panel)
	resized.connect(_fit_editor_panel)
	var editor_scroll := ScrollContainer.new()
	editor_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	editor_panel.add_child(editor_scroll)
	editor_controls = VBoxContainer.new()
	editor_controls.custom_minimum_size = Vector2(470,0)
	editor_controls.add_theme_constant_override("separation",9)
	editor_scroll.add_child(editor_controls)
	_build_dev_overlay()
	pause_menu = PauseMenu.new()
	pause_menu.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	pause_menu.visible = false
	add_child(pause_menu)
	pause_menu.resume_requested.connect(close_pause)
	pause_menu.retry_confirmed.connect(_pause_retry)
	pause_menu.quit_confirmed.connect(_pause_quit)
	pause_menu.tips_toggled.connect(_toggle_tips)
	_fit_editor_panel()

## Workshop is a safe room, so it gets a side panel (merchant, test range tools, loadout, test feedback); combat has none.
func _build_workshop_panel(layout: HBoxContainer) -> void:
	workshop_holder = MarginContainer.new()
	workshop_holder.add_theme_constant_override("margin_top",TOP_BAR_HEIGHT)
	workshop_holder.visible = false
	workshop_holder.mouse_filter = Control.MOUSE_FILTER_IGNORE
	layout.add_child(workshop_holder)
	var panel := PanelContainer.new()
	panel.custom_minimum_size = Vector2(WORKSHOP_PANEL_WIDTH,0)
	workshop_holder.add_child(panel)
	scroll = ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	panel.add_child(scroll)
	workshop_column = VBoxContainer.new()
	workshop_column.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	workshop_column.custom_minimum_size = Vector2(WORKSHOP_PANEL_WIDTH-24,0)
	workshop_column.add_theme_constant_override("separation",6)
	scroll.add_child(workshop_column)
	context = VBoxContainer.new()
	context.add_theme_constant_override("separation",6)
	workshop_column.add_child(context)
	_heading(workshop_column,"Loadout")
	loadout_list = VBoxContainer.new()
	loadout_list.add_theme_constant_override("separation",4)
	workshop_column.add_child(loadout_list)
	info = Label.new()
	info.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	workshop_column.add_child(info)

func _toast(parent: Control, label: Label) -> PanelContainer:
	var holder := PanelContainer.new()
	holder.visible = false
	holder.mouse_filter = Control.MOUSE_FILTER_IGNORE
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.custom_minimum_size.x = 440 # a fixed wrap width keeps the toast height stable
	holder.add_child(label)
	parent.add_child(holder)
	return holder

## Top-left objective + coins, top-centre toasts, top-right pause button.
func _build_top_bar() -> void:
	var bar := Control.new()
	bar.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(bar)
	var objective_panel := PanelContainer.new()
	objective_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	objective_panel.position = Vector2(SCREEN_MARGIN+4,SCREEN_MARGIN+4)
	bar.add_child(objective_panel)
	var objective_box := VBoxContainer.new()
	objective_panel.add_child(objective_box)
	objective = Label.new()
	objective.name = "Objective"
	objective.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	objective.custom_minimum_size.x = 360
	objective.add_theme_color_override("font_color",Color("#efbc65"))
	objective_box.add_child(objective)
	var coin_row := HBoxContainer.new()
	objective_box.add_child(coin_row)
	var coin := TextureRect.new()
	coin.texture = PortraitHUD.ui_icon_texture("coin")
	coin.custom_minimum_size = Vector2(20,20)
	coin.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	coin.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	coin.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	coin_row.add_child(coin)
	coins_label = Label.new()
	coins_label.name = "Coins"
	coin_row.add_child(coins_label)
	pause_button = _button(bar,"Pause (Esc)",func(): open_pause())
	pause_button.name = "PauseButton"
	pause_button.focus_mode = Control.FOCUS_NONE # Space is the dash key; a focused button would also fire on it
	pause_button.custom_minimum_size = Vector2(120,34)
	pause_button.set_anchors_and_offsets_preset(Control.PRESET_TOP_RIGHT)
	pause_button.offset_left = -(SCREEN_MARGIN+4+120)
	pause_button.offset_right = -(SCREEN_MARGIN+4)
	pause_button.offset_top = SCREEN_MARGIN+4
	pause_button.offset_bottom = SCREEN_MARGIN+4+34
	var toasts := VBoxContainer.new()
	toasts.mouse_filter = Control.MOUSE_FILTER_IGNORE
	toasts.custom_minimum_size.x = 460
	toasts.set_anchors_and_offsets_preset(Control.PRESET_CENTER_TOP,Control.PRESET_MODE_MINSIZE)
	toasts.offset_top = SCREEN_MARGIN+4
	toasts.offset_left = -230 # centred on the screen, clear of the right-hand panel
	toasts.offset_right = 230
	toasts.add_theme_constant_override("separation",4)
	bar.add_child(toasts)
	tip = Label.new()
	tip_panel = _toast(toasts,tip)
	notices = Label.new()
	notice_panel = _toast(toasts,notices)

## Centred, non-pausing panels: reward choice (cleared combat room) and the run summary modal (dead / won).
func _build_overlays() -> void:
	reward_overlay = CenterContainer.new()
	reward_overlay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	reward_overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
	reward_overlay.visible = false
	add_child(reward_overlay)
	reward_panel = PanelContainer.new()
	reward_overlay.add_child(reward_panel)
	summary_overlay = Control.new()
	summary_overlay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	summary_overlay.mouse_filter = Control.MOUSE_FILTER_STOP
	summary_overlay.visible = false
	add_child(summary_overlay)
	var dim := ColorRect.new()
	dim.color = Color(0,0,0,0.6)
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	dim.mouse_filter = Control.MOUSE_FILTER_IGNORE
	summary_overlay.add_child(dim)
	var centre := CenterContainer.new()
	centre.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	centre.mouse_filter = Control.MOUSE_FILTER_IGNORE
	summary_overlay.add_child(centre)
	summary_panel = PanelContainer.new()
	summary_panel.custom_minimum_size.x = 380
	centre.add_child(summary_panel)

## Dev-only F3 overlay: only built when show_dev_tools (and debug keys) are on; starts hidden.
func _build_dev_overlay() -> void:
	if not dev_tools_enabled():
		return
	dev_panel = PanelContainer.new()
	dev_panel.visible = false
	dev_panel.position = Vector2(SCREEN_MARGIN+4,TOP_BAR_HEIGHT+60)
	add_child(dev_panel)
	var box := VBoxContainer.new()
	dev_panel.add_child(box)
	dev_label = Label.new()
	box.add_child(dev_label)
	_button(box,"Toggle edit policy (F2)",func(): _policy())
	_button(box,"Export telemetry JSON + CSV",func(): _export_metrics())

func dev_tools_enabled() -> bool:
	return show_dev_tools == true and InputActions.debug_keys_enabled()

func toggle_dev_overlay() -> void:
	if dev_panel == null:
		return
	dev_panel.visible = not dev_panel.visible
	arena_canvas.show_debug = dev_panel.visible
	_update_labels()

## AD-091: smallest world view the arena should show; texel 3 is used when it still fits.
const MIN_VIEW_WORLD := Vector2(900,600)

## Physical pixels per art texel (2, or 3 when the arena area still shows MIN_VIEW_WORLD world units at that scale).
static func arena_texel(area_px: Vector2) -> int:
	var view_at_3 := area_px/1.5
	return 3 if view_at_3.x >= MIN_VIEW_WORLD.x and view_at_3.y >= MIN_VIEW_WORLD.y else 2

## Physical pixels per logical unit under the window stretch.
func _physical_scale() -> float:
	var s: float = get_viewport().get_final_transform().get_scale().x
	return s if s > 0.0 else 1.0

## Integer pixel scale for the arena: one art texel (2 world units) = `texel` whole physical pixels.
func _fit_arena() -> void:
	if arena_canvas == null or arena_area == null:
		return
	var s := _physical_scale()
	var area_px := arena_area.size*s
	var zoom := float(arena_texel(area_px))/(2.0*s)
	var whole := area_px.floor()
	arena_canvas.scale = Vector2(zoom,zoom)
	arena_canvas.size = whole/s/zoom
	arena_canvas.position = ((area_px-whole)*0.5).floor()/s
	if arena_canvas.slot_hud != null:
		arena_canvas.slot_hud.fit_to_canvas()
	arena_canvas.queue_redraw()

## Workshop test range keeps its logical size (movement bounds depend on it) and is scaled down to fit.
func _fit_test_canvas() -> void:
	if test_canvas == null or arena_area == null:
		return
	var area := arena_area.size
	var factor := minf(1.0,minf(area.x/TEST_RANGE_SIZE.x,area.y/TEST_RANGE_SIZE.y))
	var whole := floorf(TEST_RANGE_SIZE.x*factor)/TEST_RANGE_SIZE.x
	if whole > 0.0:
		factor = minf(factor,whole)
	test_canvas.scale = Vector2(factor,factor)
	test_canvas.position = ((area-TEST_RANGE_SIZE*factor)*0.5).floor()

func _fit_editor_panel() -> void:
	if editor_panel == null:
		return
	editor_panel.custom_minimum_size = Vector2(minf(EDITOR_SIZE.x,size.x*0.45),0)

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
	pause_menu.set_tips_visible(not guide.dismissed)
	pause_menu.visible = true

func close_pause() -> void:
	if not is_paused():
		return
	if pause_menu.is_settings_open():
		pause_menu.close_settings()
	if pause_menu.is_controls_open():
		pause_menu.close_controls()
	if pause_menu.is_confirm_open():
		pause_menu.cancel_confirm()
	pause_menu.visible = false
	_set_clocks_paused(false)
	Input.mouse_mode = _prev_mouse_mode

func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_CLOSE_REQUEST or what == NOTIFICATION_PREDELETE:
		if flow != null:
			flow.experiment.end_session()

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
	if bool(result.get("accepted",false)):
		guide.note_test_cast()
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
				if dev_tools_enabled(): _policy()
			KEY_F3:
				if dev_tools_enabled(): toggle_dev_overlay()
			KEY_F6:
				if dev_tools_enabled(): Art.toggle_art_export(); arena_canvas.queue_redraw()

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
	var key = flavour.get("room_names", {}).get(room_id, "")
	return tr(str(key)) if key != "" else room_id

## Rift line is returned once per run (reset on retry / new seed).
func stage_banner() -> String:
	if _rift_shown:
		return ""
	_rift_shown = true
	return tr(str(flavour.get("rift_line", "")))

func _guide(show: bool) -> void:
	if show:
		guide.reopen()
	else:
		guide.dismiss()
	_update_labels()

## Pause menu "Hide/Show tips": flips the dismissed state.
func _toggle_tips() -> void:
	_guide(guide.dismissed)
	pause_menu.set_tips_visible(not guide.dismissed)

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
	var in_summary: bool = flow.state in ["dead","won"]
	var reward_choice: bool = flow.state == "cleared" and flow.room.values["type"] != "boss" and not flow.reward_collected
	var in_workshop: bool = flow.state == "workshop"
	workshop_holder.visible = in_workshop and not editor_open
	reward_overlay.visible = reward_choice
	summary_overlay.visible = in_summary
	_place_context(summary_panel if in_summary else (reward_panel if reward_choice else workshop_column))
	if in_summary:
		_build_summary_panel()
	elif flow.state == "error":
		_heading(context,"RUN DATA ERROR")
	elif reward_choice:
		var heading := Label.new()
		heading.text = "ROOM CLEARED — choose ONE reward"
		heading.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		heading.add_theme_color_override("font_color",Color("#efbc65"))
		context.add_child(heading)
		var row := HBoxContainer.new()
		row.alignment = BoxContainer.ALIGNMENT_CENTER
		row.add_theme_constant_override("separation",12)
		context.add_child(row)
		for i in flow.reward_options.size():
			var item: Dictionary = flow.reward_options[i]
			var caption := ""
			if item["kind"] == "rune":
				caption = str(item["name"])+"\n"+str(item["behaviour"])
			else:
				caption = "+"+str(item["amount"])+" currency"
			var card := _button(row,"%d) %s" % [i+1,caption],_choose_reward.bind(i))
			card.custom_minimum_size = Vector2(180,240)
			card.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
			card.icon_alignment = HORIZONTAL_ALIGNMENT_CENTER
			card.vertical_icon_alignment = VERTICAL_ALIGNMENT_TOP
			_skin_reward_button(card,item)
		var keys := Label.new()
		keys.text = "Keys 1-3 or click a card"
		keys.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		context.add_child(keys)
		if flow.edit_policy == "cleared_room":
			_hint(context,"Quick edit allowed (no shop/test)")
		_hint(context,"Advance at exit (F) after choosing")
	elif in_workshop:
		shop_reopen_button = _button(context,"Open merchant",func(): _set_shop_open(true))
		_heading(context,"Testing range: no progression/rewards")
		_button(context,"Reset test targets + mana (T)",func(): _reset_test_range())
		_button(context,"Prepare Wet cluster (2 targets)",func():
			flow.prepare_wet_cluster()
			current_notice = "Wet cluster prepared: lightning arc can be tested")
		_button(context,"Refill test mana",func():
			flow.refill_test_mana()
			current_notice = "Test mana refilled")
		_button(context,"Continue to stage 2 (F)",func(): _exit())
	if in_workshop:
		if not _shop_offered:
			_shop_offered = true
			shop_open = true
		_build_shop_panel()
	else:
		_shop_offered = false
		shop_open = false
	_sync_shop()
	_update_labels()

func _sync_shop() -> void:
	if shop_overlay != null:
		shop_overlay.visible = shop_open and flow != null and flow.state == "workshop" and not editor_open
	if workshop_holder != null and flow != null:
		workshop_holder.visible = flow.state == "workshop" and not editor_open
	if editor_dock != null:
		editor_dock.visible = editor_open
		_fit_editor_panel()
		_fit_test_canvas.call_deferred()

func _set_shop_open(on: bool) -> void:
	shop_open = on
	_sync_shop()

func _build_shop_panel() -> void:
	_clear(shop_list)
	var title := Label.new()
	title.text = tr(str(flavour.get("merchant", {}).get("title", "Merchant")))+" — buy once per item"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_color_override("font_color",Color("#efbc65"))
	shop_list.add_child(title)
	var greet := Label.new()
	greet.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	greet.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	greet.custom_minimum_size.x = 380
	greet.text = tr(flow.merchant.greeting(flow.run.seed))
	shop_list.add_child(greet)
	var row := HBoxContainer.new()
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_theme_constant_override("separation",8)
	shop_list.add_child(row)
	for i in flow.merchant.stock.size():
		var item: Dictionary = flow.merchant.stock[i]
		var affordable: bool = int(item["price"]) <= flow.run.currency
		var card := PanelContainer.new()
		var box := StyleBoxTexture.new()
		var tex := AtlasTexture.new()
		tex.atlas = ShopCard
		tex.region = Rect2(48,0,48,48)
		box.texture = tex
		box.draw_center = false # the card art bakes in a RUNE label and price; keep only its frame
		for side in ["left","right","top","bottom"]:
			box.set("texture_margin_"+side,4)
			box.set("content_margin_"+side,8)
		card.add_theme_stylebox_override("panel",box)
		card.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
		row.add_child(card)
		var col := VBoxContainer.new()
		col.custom_minimum_size.x = 150
		col.add_theme_constant_override("separation",4)
		card.add_child(col)
		var b := _button(col,str(item["label"])+" / "+str(item["price"])+" coins",_buy.bind(i))
		b.disabled = flow.merchant.bought.has(item["id"]) or not affordable
		b.icon = PortraitHUD.rune_icon_texture(str(item["rune_id"])) if item["kind"] == "rune" else PortraitHUD.ui_icon_texture("hp")
		b.expand_icon = false
		b.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		b.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
		var detail := Label.new()
		detail.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		detail.custom_minimum_size.x = 150 # a wrapped label needs a width or it measures one character per line
		var explanation := ""
		if item["kind"] == "rune":
			var rune = flow.session.sim.registry.get_rune(str(item["rune_id"]))
			var desc_key := "rune.%s.desc" % item["rune_id"]
			explanation = str(item["rune_id"])
			if rune != null:
				explanation = tr(desc_key) if tr(desc_key) != desc_key else str(rune.snapshot()["description"])
		else:
			explanation = "Increase max HP by %d (run-persistent)" % int(item["amount"])
		detail.text = explanation+" | "+("Purchased" if flow.merchant.bought.has(item["id"]) else ("Affordable" if affordable else "Need "+str(int(item["price"])-flow.run.currency)+" coins"))
		col.add_child(detail)
	shop_close_button = _button(shop_list,"Close shop",func(): _set_shop_open(false),"ui.cancel")

func _hint(parent: Node, text: String) -> void:
	var label := Label.new()
	label.text = text
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.custom_minimum_size.x = 380 # a wrapped label needs a width or it measures one character per line
	parent.add_child(label)

## `context` holds the per-state content; it lives in whichever panel is visible for the state.
func _place_context(target: Node) -> void:
	if context.get_parent() == target:
		return
	if context.get_parent() != null:
		context.get_parent().remove_child(context)
	target.add_child(context)
	if target == workshop_column:
		workshop_column.move_child(context,0)

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
	_update_objective()
	var test_text := ""
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
		test_text = "TEST hits %d / active %d / mana %.0f\nStatuses %s | Reactions %d\nTriggers %d | Budget warnings %d" % [
			flow.range_sim.total_hit_count,flow.range_sim.queue.active_effect_count(),flow.range_sim.mana,
			",".join(statuses),reactions,triggers,caps]
	info.text = test_text
	notices.text = current_notice
	if current_notice != _notice_seen:
		_notice_seen = current_notice
		_notice_until_ms = Time.get_ticks_msec()+NOTICE_MS
	notice_panel.visible = current_notice != "" and Time.get_ticks_msec() < _notice_until_ms
	pause_button.disabled = not can_pause()
	_update_dev_label()
	if tip != null:
		_watch_hint_signals()
		var active := ""
		if flow.mode == "workshop":
			active = "first_workshop"
		elif flow.state == "fighting" and str(flow.room.values["id"]) == "s1_r1":
			active = "room1"
		elif flow.state == "cleared" and not flow.reward_collected:
			active = "first_reward"
		var hint: String = guide.next_hint()
		if guide.HINT_IDS.has(guide.current) and not guide.dismissed and hint == "":
			active = guide.current
		elif hint != "" and (active == "" or guide.seen.has(active)):
			active = hint  # an unseen AD-042 tip is shown first, then the pending hint takes over
		if active != "" and not guide.trigger(active).is_empty():
			_persist_tip(active)
			guide.pending.erase(active)
			var index: int = guide.HINT_INDEX[active] if guide.HINT_INDEX.has(active) else int(TELEMETRY_INDEX.get(active,-1))
			flow.experiment.record("prompt_shown",{"prompt_index":index})
		if guide.current != active:
			guide.current = ""
		tip.text = ("TIP: " + guide.text()) if guide.text() != "" else ""
		tip_panel.visible = tip.text != ""
	if editor_open: # the docked editor owns the top-right; toasts must not cover its heading
		tip_panel.visible = false
		notice_panel.visible = false

## Compact top-left objective: room display name + goal for the current state, then the coin count.
func _update_objective() -> void:
	var goal := ""
	if flow.mode == "workshop":
		goal = "Safe Workshop"
	elif flow.state == "fighting":
		goal = "Defeat the Warden" if flow.room.values["type"] == "boss" else "Defeat the Undead"
	elif flow.state == "cleared":
		goal = "Exit unlocked - press F at the exit"
	var title := room_display_name(str(flow.room.values["id"]))
	objective.text = title if goal == "" else title+" - "+goal
	coins_label.text = "%d" % flow.run.currency

func _update_dev_label() -> void:
	if dev_panel == null or not dev_panel.visible:
		return
	var text := "Render FPS %.0f / observed low %.0f\nEdit policy: %s" % [Engine.get_frames_per_second(),low_fps,flow.edit_policy]
	if flow.encounter != null:
		text += "\nWaves scheduled: "+str(flow.encounter.schedule.size())
	if flow.mode == "workshop" and flow.range_sim != null:
		var trace = flow.range_sim.trace
		text += "\nTrace: %d reactions, %d triggers, %d budget warnings" % [
			trace.filter_records(-1,"","reaction").size(),trace.filter_records(-1,"","trigger").size(),
			trace.filter_records(-1,"","budget_exceeded").size()]
	dev_label.text = text

## AD-084: read-only watch on run-flow counters; never pauses the sim or opens dialogs.
func _watch_hint_signals() -> void:
	if flow.mode == "workshop":
		guide.note_workshop(3 - flow.run.formulas.size())
		if flow.run.formulas.size() >= 3 and guide.current == "workshop_empty_slot":
			guide.current = ""
	if flow.wet_kills > _last_wet_kills:
		guide.note_wet_kill()
	_last_wet_kills = flow.wet_kills
	var arc_now: int = flow.arc_total()
	if arc_now > _last_arcs and guide.note_arc():
		_persist_tip("wet_try_lightning")
	_last_arcs = arc_now

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
		current_notice = tr(flow.merchant.purchase_line(flow.run.purchases.size()))
	_redraw_panel()

func _build_summary_panel() -> void:
	var stats: Dictionary = flow.summary()
	var save = get_node_or_null("/root/SaveService")
	if save != null and not _stats_recorded:
		_stats_recorded = true
		save.record_run(stats)
	_heading(context,"RUN SUMMARY — "+("VICTORY" if flow.state == "won" else "DEFEATED"),18)
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
	var buttons := HBoxContainer.new()
	buttons.alignment = BoxContainer.ALIGNMENT_CENTER
	buttons.add_theme_constant_override("separation",8)
	context.add_child(buttons)
	summary_retry_button = _button(buttons,"Retry same seed",func(): _retry_same_seed())
	summary_new_seed_button = _button(buttons,"New seed",func(): _new_seed())
	summary_title_button = _button(buttons,"Title",func(): _to_title(),"ui.cancel")
	for b in [summary_retry_button,summary_new_seed_button,summary_title_button]:
		b.autowrap_mode = TextServer.AUTOWRAP_OFF # a wrapping button in a row shrinks to one character per line
		b.custom_minimum_size.x = 110

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
	flow.experiment.end_session()
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
	if ReduceMotion.flashes_reduced(_settings, null):
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
	_sync_shop()
	opened_editor_ms = Time.get_ticks_msec()
	editor_panel.visible = true
	_editor_rebuild()
	_update_labels()

func _editor_rebuild() -> void:
	_clear(editor_controls)
	var e = flow.editor
	_heading(editor_controls,"SPELL EDITOR / SLOT "+str(e.slot+2),20)
	_heading(editor_controls,"Essence → Manifestation → Modifier → On Hit")
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
	return PortraitHUD.rune_icon_texture(rune_id)

## AD-038 reward card art as the button skin (frames: normal, hover, pressed); layout is unchanged.
func _skin_reward_button(b: Button, item: Dictionary) -> void:
	var states := {"normal":0,"hover":1,"focus":1,"pressed":2}
	for state in states:
		var box := StyleBoxTexture.new()
		var tex := AtlasTexture.new()
		tex.atlas = RewardCard
		tex.region = Rect2(states[state]*74,0,74,110)
		box.texture = tex
		box.texture_margin_left = 5
		box.texture_margin_right = 5
		box.texture_margin_top = 5
		box.texture_margin_bottom = 5
		box.content_margin_left = 8
		box.content_margin_right = 8
		box.content_margin_top = 6
		box.content_margin_bottom = 6
		b.add_theme_stylebox_override(state,box)
	b.icon = PortraitHUD.rune_icon_texture(str(item["id"])) if item["kind"] == "rune" else PortraitHUD.ui_icon_texture("coin")
	b.expand_icon = false
	b.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST

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
	_sync_shop()

func _close_editor(apply_changes: bool) -> void:
	var duration := float(Time.get_ticks_msec()-opened_editor_ms)/1000.0
	var result: Dictionary = flow.close_editor(apply_changes,duration)
	if not result["ok"]:
		current_notice = "Editor: "+str(result.get("reason","INVALID"))
		_editor_rebuild()
		return
	if apply_changes:
		guide.note_valid_edit()
	current_notice = ("Formula applied" if apply_changes else "Formula cancelled")+" / %.1f s" % duration
	_close_visual_editor()
	_redraw_panel()

## AD-090: debug-only UI shot-state hook (env AD_UI_SHOT_STATE / AD_UI_SHOT_OUT); inert in release builds.
func apply_debug_shot_state(state: String) -> bool:
	if not OS.is_debug_build() or not state in ["combat","reward","workshop_editor","merchant","pause","summary"]:
		return false
	if state == "reward":
		for i in 3000:
			if flow.state != "fighting":
				break
			for enemy in flow.session.enemies:
				if enemy.target.alive():
					enemy.target.receive_damage(100000,"fire",1,100)
			flow.step()
	elif state == "workshop_editor" or state == "merchant":
		flow.run.sequence_index = flow.config["rooms"].size()-2
		flow._enter_current()
	elif state == "summary":
		flow.session.sim.actor.receive_damage(100000,"fire",2,100)
		flow.step({"cast":0})
	_redraw_panel()
	if state == "workshop_editor":
		_set_shop_open(false)
		_open_editor(1) # slot 0 (Basic Bolt) is locked; slot 1 is the first editable one
	elif state == "merchant":
		_set_shop_open(true)
	elif state == "pause":
		open_pause()
	return true

func _debug_shot_entry() -> void:
	var state := OS.get_environment("AD_UI_SHOT_STATE") if OS.is_debug_build() else ""
	if state == "" or not apply_debug_shot_state(state):
		return
	show_dev_tools = false # matrix shots are release-like: no dev overlay
	if dev_panel != null:
		dev_panel.visible = false
	arena_canvas.show_debug = false
	var path := OS.get_environment("AD_UI_SHOT_OUT")
	if path == "":
		return
	if OS.get_environment("AD_UI_SHOT_FULLSCREEN") == "1":
		DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_FULLSCREEN)
	var delay := OS.get_environment("AD_UI_SHOT_DELAY_MS")
	await get_tree().create_timer((int(delay) if delay != "" else 800) / 1000.0).timeout
	await RenderingServer.frame_post_draw
	var image := get_viewport().get_texture().get_image()
	var error := image.save_png(path)
	print("AD_UI_SHOT saved %s %dx%d" % [path, image.get_width(), image.get_height()])
	get_tree().quit(0 if error == OK else 1)
