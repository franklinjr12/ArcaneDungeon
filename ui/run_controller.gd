extends Control
const ReduceMotion = preload("res://ui/reduce_motion.gd")
const VisualTheme = preload("res://ui/pixel_theme.gd")
## M3 playable vertical slice. This is only input/UI; all rules live in RunFlow.
const Flow = preload("res://world/run_flow.gd")
const ArenaCanvas = preload("res://ui/run_canvas.gd")
const TestCanvas = preload("res://ui/sandbox_canvas.gd")
const PortraitHUD = preload("res://ui/pixel_hud.gd")
const SkinA = preload("res://ui/skin_a.gd")
const Overlay = preload("res://ui/skin_a_overlay.gd")
const Artifacts = preload("res://world/artifacts.gd")
const Prompts = preload("res://ui/onboarding_prompts.gd")
const Art = preload("res://ui/pixel_art_renderer.gd")
const InputActions = preload("res://ui/input_actions.gd")
var aim_source = InputActions.default_aim_source()
const PauseMenu = preload("res://ui/pause_menu.gd")
const FeedbackSnapshot = preload("res://ui/feedback_snapshot.gd")
const LoadoutView = preload("res://ui/loadout_view.gd")
const EditorView = preload("res://ui/skin_a_editor.gd")
const MerchantScript = preload("res://world/merchant.gd")
const PerfOverlay = preload("res://debug/perf_overlay.gd")
var flow
var config_path: String = Flow.CONFIG_V2
var guide = Prompts.new()
var tip: Label
var tip_panel: PanelContainer
var notice_panel: PanelContainer
var objective: Label
var objective_panel: PanelContainer
var top_toasts: VBoxContainer
var coins_label: Label
var pause_button: Button
var loadout_view
var loadout_view_button: Button
var workshop_holder: MarginContainer
var workshop_column: VBoxContainer
var reward_overlay: Overlay ## AD-153: skin A reward pick (ad_ui_screen_reward_layout.json)
var summary_overlay: Overlay ## AD-153: skin A run summary (summary_win / summary_lose layouts)
var shop_overlay: Overlay ## AD-153: skin A merchant (ad_ui_screen_merchant_layout.json)
var reward_cards: Array = [] ## card_N sprite nodes, one per reward option
var reward_take_buttons: Array = []
var shop_cards: Array = [] ## offer_N sprite nodes, one per stock item
var shop_buy_buttons: Array = []
var _shop_detail: Array = [] ## [title, tag, desc] labels of the merchant detail panel
var shop_open := false
var _shop_offered := false
var shop_reopen_button: Button
var desk_skip_button: Button
var shop_reroll_button: Button
var shop_close_button: Button
var dev_panel: PanelContainer
var dev_label: Label
## null = resolve from OS.is_debug_build() in _ready (same meaning as main_menu.show_debug_entries); tests set false before add_child.
var show_dev_tools = null
var _notice_seen := ""
var _notice_until_ms := 0
var _last_wet_kills := 0
var _last_arcs := 0
const TELEMETRY_INDEX := {"room1":3,"first_reward":4,"first_workshop":5,"telegraph":6,"spells_are_runes":7}
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
var editor_scroll: ScrollContainer
var editor_buttons: HBoxContainer
var editor_view
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
var last_sim_usec := 0
var perf_overlay
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
## Edges of the HUD groups in 640x360 layout px (ad_ui_screen_hud_layout.json).
const HUD_ARTIFACT_LEFT := 499.0
const HUD_BOSS_BOTTOM := 46.0
const HUD_STATUS_BOTTOM := 80.0
const NOTICE_MS := 5000
const TEST_RANGE_SIZE := Vector2(916,650)
const DESK_DOOR_RADIUS := 34.0
const EDITOR_SIZE := Vector2(632,665) # AD-153: 296 canvas px at x2 (skin A editor column) plus the panel frame and scrollbar
var _prev_mouse_mode := Input.MOUSE_MODE_VISIBLE
var feedback_snapshot
var _report_paused_clocks := false
var _report_prev_mouse_mode := Input.MOUSE_MODE_VISIBLE

func _ready() -> void:
	VisualTheme.apply(self)
	if show_dev_tools == null:
		show_dev_tools = OS.is_debug_build()
	flow = Flow.new(-1, config_path)
	var resume_save = get_node_or_null("/root/SaveService")
	var resumed := false
	if resume_save != null:
		var wanted: bool = resume_save.resume_requested
		resume_save.resume_requested = false
		if wanted:
			resumed = flow.resume(resume_save.load_run())
			if resumed:
				current_notice = tr("run.notice.resumed")
			else:
				_drop_save()
				current_notice = tr("run.notice.resume_failed")
		else:
			_drop_save()
	if not resumed:
		_begin_desk()
	_director = get_node_or_null("/root/AudioDirector")
	if _director != null:
		flow.audio_sink = _director.play
		_director.play("amb.workshop" if flow.mode == "workshop" else "amb.ruins")
		_director.play("music." + flow.music_context_for_room())
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
	editor_panel.add_theme_stylebox_override("panel",SkinA.stylebox("ad_ui_panel_large",16))
	editor_dock.add_child(editor_panel)
	resized.connect(_fit_editor_panel)
	var editor_body := VBoxContainer.new()
	editor_body.add_theme_constant_override("separation",8)
	editor_panel.add_child(editor_body)
	editor_scroll = ScrollContainer.new()
	editor_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	editor_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	editor_body.add_child(editor_scroll)
	editor_controls = VBoxContainer.new()
	editor_controls.custom_minimum_size = Vector2(EditorView.WIDTH*EditorView.SC,0)
	editor_controls.add_theme_constant_override("separation",int(4*EditorView.SC))
	editor_scroll.add_child(editor_controls)
	editor_buttons = HBoxContainer.new()
	editor_buttons.add_theme_constant_override("separation",int(4*EditorView.SC))
	editor_body.add_child(editor_buttons)
	editor_view = EditorView.new()
	_build_dev_overlay()
	loadout_view = LoadoutView.new()
	add_child(loadout_view)
	loadout_view.close_requested.connect(close_loadout_view)
	pause_menu = PauseMenu.new()
	pause_menu.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	pause_menu.visible = false
	add_child(pause_menu)
	feedback_snapshot = FeedbackSnapshot.new()
	feedback_snapshot.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(feedback_snapshot)
	feedback_snapshot.closed.connect(_on_report_closed)
	pause_menu.resume_requested.connect(close_pause)
	pause_menu.retry_confirmed.connect(_pause_retry)
	pause_menu.quit_confirmed.connect(_pause_quit)
	pause_menu.save_quit_confirmed.connect(_save_and_quit)
	pause_menu.tips_toggled.connect(_toggle_tips)
	pause_menu.loadout_requested.connect(func():
		close_pause()
		open_loadout_view())
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
	_heading(workshop_column,tr("run.loadout"))
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

## AD-153: the skin A HUD (pixel_hud.gd) owns HP/MP, stage, coins and artifacts. This bar keeps the goal line (below the
## status row), the toasts, and the Pause / Loadout buttons, positioned clear of the HUD by `_layout_top_bar`.
func _build_top_bar() -> void:
	var bar := Control.new()
	bar.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(bar)
	objective_panel = PanelContainer.new()
	objective_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	bar.add_child(objective_panel)
	objective = Label.new()
	objective.name = "Objective"
	objective.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	objective.custom_minimum_size.x = 360
	objective.add_theme_color_override("font_color",Color("#efbc65"))
	objective_panel.add_child(objective)
	coins_label = Label.new() # mirrors the coin count the HUD draws; kept for tests and screen readers
	coins_label.name = "Coins"
	coins_label.visible = false
	bar.add_child(coins_label)
	pause_button = _button(bar,tr("run.btn.pause"),func(): open_pause())
	pause_button.name = "PauseButton"
	pause_button.focus_mode = Control.FOCUS_NONE # Space is the dash key; a focused button would also fire on it
	pause_button.custom_minimum_size = Vector2(120,34)
	loadout_view_button = _button(bar,tr("run.btn.loadout_view"),func(): open_loadout_view())
	loadout_view_button.name = "LoadoutViewButton"
	loadout_view_button.focus_mode = Control.FOCUS_NONE
	loadout_view_button.custom_minimum_size = Vector2(150,34)
	loadout_view_button.visible = false
	var toasts := VBoxContainer.new()
	toasts.mouse_filter = Control.MOUSE_FILTER_IGNORE
	toasts.custom_minimum_size.x = 460
	toasts.set_anchors_and_offsets_preset(Control.PRESET_CENTER_TOP,Control.PRESET_MODE_MINSIZE)
	toasts.offset_left = -230 # centred on the screen, clear of the right-hand panel
	toasts.offset_right = 230
	toasts.add_theme_constant_override("separation",4)
	bar.add_child(toasts)
	top_toasts = toasts
	tip = Label.new()
	tip_panel = _toast(toasts,tip)
	notices = Label.new()
	notice_panel = _toast(toasts,notices)
	get_viewport().size_changed.connect(_layout_top_bar)
	_layout_top_bar()

## Pixel-scale and HUD-free top edge for the top bar. While the arena HUD is up (combat), the buttons sit left of the
## artifact column and below the boss block; in the workshop (no HUD) they keep the original top-right spot.
func _layout_top_bar() -> void:
	if pause_button == null:
		return
	var view := get_viewport_rect().size
	var sc := floorf(SkinA.canvas_scale(view))
	var hud_up: bool = arena_canvas != null and arena_canvas.visible
	var edge := float(SCREEN_MARGIN+4)
	var right := view.x-edge
	var top := edge
	if hud_up:
		right = view.x-SCREEN_MARGIN-(SkinA.CANVAS.x-HUD_ARTIFACT_LEFT)*sc-8.0
		top = SCREEN_MARGIN+HUD_BOSS_BOTTOM*sc+4.0
	pause_button.set_anchors_and_offsets_preset(Control.PRESET_TOP_LEFT)
	pause_button.position = Vector2(right-120,top)
	pause_button.size = Vector2(120,34)
	loadout_view_button.set_anchors_and_offsets_preset(Control.PRESET_TOP_LEFT)
	loadout_view_button.position = Vector2(right-120-8-150,top)
	loadout_view_button.size = Vector2(150,34)
	objective_panel.position = Vector2(SCREEN_MARGIN+4,SCREEN_MARGIN+HUD_STATUS_BOTTOM*sc+4.0 if hud_up else edge)
	top_toasts.set_anchors_and_offsets_preset(Control.PRESET_CENTER_TOP,Control.PRESET_MODE_MINSIZE)
	top_toasts.offset_left = -230
	top_toasts.offset_right = 230
	top_toasts.offset_top = top+34.0+8.0

## Centred, non-pausing panels: reward choice (cleared combat room) and the run summary modal (dead / won).
func _build_overlays() -> void:
	reward_overlay = Overlay.new(false)
	reward_overlay.director = _director
	add_child(reward_overlay)
	summary_overlay = Overlay.new(true)
	summary_overlay.director = _director
	add_child(summary_overlay)
	shop_overlay = Overlay.new(true)
	shop_overlay.director = _director
	add_child(shop_overlay)
	perf_overlay = PerfOverlay.new()
	perf_overlay.settings = _settings
	perf_overlay.source = self
	add_child(perf_overlay)

## AD-187: numbers for the Show FPS overlay.
func perf_stats() -> Dictionary:
	var enemies := 0
	var effects := 0
	if flow != null and flow.session != null:
		for e in flow.session.enemies:
			if e.target.alive():
				enemies += 1
		effects = flow.session.sim.queue.active_effect_count()
	return {"sim_ms": last_sim_usec / 1000.0, "enemies": enemies, "effects": effects}

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
	_button(box,tr("run.btn.toggle_policy"),func(): _policy())
	_button(box,tr("run.btn.export_telemetry"),func(): _export_metrics())
	_button(box,tr("run.btn.dev_kill_all"),func(): _dev_kill_all())
	_button(box,tr("run.btn.dev_skip_room"),func(): _dev_skip_room())
	_button(box,tr("run.btn.dev_next_stage"),func(): _dev_next_stage())

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
	editor_panel.custom_minimum_size = Vector2(minf(EDITOR_SIZE.x,size.x*0.5),0)

func is_paused() -> bool:
	return (pause_menu != null and pause_menu.visible) or (feedback_snapshot != null and feedback_snapshot.is_open())

func open_report() -> void:
	if flow == null or not flow.initialized or feedback_snapshot.is_open():
		return
	var image = FeedbackSnapshot.capture(get_viewport())
	_report_paused_clocks = can_pause() and not pause_menu.visible
	if _report_paused_clocks:
		_set_clocks_paused(true)
	_report_prev_mouse_mode = Input.mouse_mode
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	feedback_snapshot.open(image, flow.run_log.to_dict())

func _on_report_closed(saved_path: String) -> void:
	if _report_paused_clocks:
		_set_clocks_paused(false)
	_report_paused_clocks = false
	Input.mouse_mode = _report_prev_mouse_mode
	if not saved_path.is_empty():
		current_notice = tr("report.saved")
		if not pause_menu.visible:
			_update_labels()

func can_pause() -> bool:
	return not editor_open and flow.state in ["fighting","cleared","workshop"]

func can_view_loadout() -> bool:
	return flow != null and flow.state == "cleared" and not editor_open and not is_paused()

func is_loadout_view_open() -> bool:
	return loadout_view != null and loadout_view.visible

func open_loadout_view() -> void:
	if can_view_loadout():
		loadout_view.show_for(flow)

func close_loadout_view() -> void:
	if loadout_view != null:
		loadout_view.visible = false

func open_pause() -> void:
	if not can_pause() or is_paused():
		return
	close_loadout_view()
	_set_clocks_paused(true)
	_prev_mouse_mode = Input.mouse_mode
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	pause_menu.set_tips_visible(not guide.dismissed)
	pause_menu.set_save_available(flow.can_save())
	var seconds := int(flow.summary()["seconds"])
	pause_menu.set_run_info(tr("pause.run_info") % [int(flow.room.values.get("stage",0))+1,int(flow.rooms_cleared)+1,seconds/60,seconds%60])
	pause_menu.visible = true

func close_pause() -> void:
	if not is_paused():
		return
	if pause_menu.is_settings_open():
		pause_menu.close_settings()
	if pause_menu.is_controls_open():
		pause_menu.close_controls()
	guide.refresh_bindings()
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

func _autosave() -> void:
	var save = get_node_or_null("/root/SaveService")
	if save != null and flow.can_save():
		save.save_run(flow.save_payload())

func _drop_save() -> void:
	var save = get_node_or_null("/root/SaveService")
	if save != null:
		save.delete_run()

## AD-146: the run is not over, so nothing is recorded; Continue resumes in this workshop.
func _save_and_quit() -> void:
	if not flow.can_save():
		return
	_autosave()
	_stats_recorded = true
	close_pause()
	_to_title()

func _pause_quit() -> void:
	_drop_save()
	var save = get_node_or_null("/root/SaveService")
	if save != null and not _stats_recorded:
		var s: Dictionary = flow.summary()
		s["outcome"] = "abandoned"
		s["discovered"] = flow.discoveries()
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
	var slot := InputActions.cast_slot_for_mouse_button(button)
	if slot < 0:
		return
	cursor = point
	cast_pending = slot

func _test_click(point: Vector2, button: int) -> void:
	if is_paused() or editor_open or flow.state != "workshop":
		return
	var slot := InputActions.cast_slot_for_mouse_button(button)
	if slot >= 0:
		_test_cast_slot(slot,point)

func _test_cast_slot(slot: int, point: Vector2) -> Dictionary:
	var dir: Vector2 = (point-flow.range_sim.actor.position).normalized()
	var result: Dictionary = flow.test_cast(slot,dir)
	if bool(result.get("accepted",false)):
		guide.note_test_cast()
	current_notice = tr("run.notice.test_cast") % [slot+1,str(result.get("reason",""))]
	_update_labels()
	return result

func _reset_test_range() -> void:
	flow.enter_test_range()
	test_canvas.runner = flow.range_sim
	current_notice = tr("run.notice.range_reset")
	_update_labels()

func _input(event: InputEvent) -> void:
	if feedback_snapshot != null and feedback_snapshot.is_open():
		if event.is_action_pressed("pause") and not event.is_echo():
			feedback_snapshot.cancel()
			get_viewport().set_input_as_handled()
		return
	if event.is_action_pressed("report") and not event.is_echo():
		open_report()
		get_viewport().set_input_as_handled()
		return
	if is_paused():
		if event.is_action_pressed("pause") and not event.is_echo():
			pause_menu.handle_cancel()
		get_viewport().set_input_as_handled()
		return
	if event.is_action_pressed("dash") and (reward_overlay.has_button_focus() or shop_overlay.has_button_focus()):
		get_viewport().set_input_as_handled() # Space is the dash key and also "accept": never let it press a focused offer
		return
	if editor_open or not event.is_pressed() or event.is_echo():
		return
	if is_loadout_view_open():
		if event.is_action_pressed("loadout_view") or event.is_action_pressed("pause"):
			close_loadout_view()
		get_viewport().set_input_as_handled()
		return
	var fighting: bool = flow.state == "fighting"
	var slot := InputActions.cast_slot_for_event(event)
	if slot >= 0 and not event is InputEventMouseButton and fighting:
		cursor = aim_source.world_point(arena_canvas,flow.session.sim.actor.position)
		cast_pending = slot
	elif slot >= 0 and not event is InputEventMouseButton and flow.state == "workshop" and flow.range_sim != null:
		_test_cast_slot(slot,aim_source.world_point(test_canvas,flow.range_sim.actor.position))
	elif _reward_index(event) >= 0 and flow.state == "cleared" and not flow.reward_collected \
			and _reward_index(event) < flow.reward_options.size():
		_choose_reward(_reward_index(event))
	elif event.is_action_pressed("loadout_view"):
		open_loadout_view()
	elif event.is_action_pressed("interact"):
		_exit()
	elif event.is_action_pressed("pause") and shop_overlay.visible:
		_set_shop_open(false)
	elif event.is_action_pressed("pause"):
		open_pause()
	elif event.is_action_pressed("run_retry"):
		_retry_same_seed()
	elif event.is_action_pressed("reset_test_range"):
		if flow.state == "workshop": _reset_test_range()
	elif event.is_action_pressed("dev_policy"):
		if dev_tools_enabled(): _policy()
	elif event.is_action_pressed("dev_overlay"):
		if dev_tools_enabled(): toggle_dev_overlay()
	elif event.is_action_pressed("dev_art_export"):
		if dev_tools_enabled(): Art.toggle_art_export(); arena_canvas.queue_redraw()

func _reward_index(event: InputEvent) -> int:
	for i in 9:
		if event.is_action_pressed("choose_reward_%d" % (i+1)):
			return i
	return -1

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
	var sim_start := Time.get_ticks_usec()
	if not editor_open:
		if flow.state == "fighting":
			var dir := Input.get_vector("move_left","move_right","move_up","move_down")
			var aim: Vector2 = (aim_source.world_point(arena_canvas,flow.session.sim.actor.position)-flow.session.sim.actor.position).normalized()
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
			_desk_door_walk()
	last_sim_usec = Time.get_ticks_usec() - sim_start
	cast_pending = -1
	arena_canvas.queue_redraw()
	portrait_hud.queue_redraw()
	test_canvas.queue_redraw()
	refresh_counter += 1
	if refresh_counter%7 == 0:
		var key: String = str(flow.run.sequence_index)+":"+flow.state+":"+str(flow.reward_collected)
		if key != scene_key:
			if flow.state == "cleared" and not flow.reward_collected and not flow.reward_options.is_empty():
				current_notice = tr("run.notice.room_cleared") % flow.reward_options.size()
			_redraw_panel()
		else:
			_update_labels()

## Sigil Desk door sits on the right edge of the test range; walking into it leaves (same as F).
func desk_door_position() -> Vector2:
	return Vector2(test_canvas.size.x-44.0,test_canvas.size.y*0.5)

func _desk_door_walk() -> void:
	if not flow.prelude or editor_open or (flow.prelude_required() and not flow.prelude_ready()):
		return
	if flow.range_sim.actor.position.distance_to(desk_door_position()) <= DESK_DOOR_RADIUS:
		_exit()

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
		current_notice = tr("run.notice.opt_in_first")
	else:
		var a: Error = flow.experiment.export_json()
		var b: Error = flow.experiment.export_csv()
		current_notice = tr("run.notice.export_ok") if a == OK and b == OK else tr("run.notice.export_failed")
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
	arena_canvas.environment_id = 2 if int(flow.room.values.get("stage",0))>=1 else (1 if flow.room.values["type"]=="boss" else 0)
	arena_canvas.lighting_stage = int(flow.room.values.get("stage",0))
	arena_canvas.lighting_room_type = str(flow.room.values.get("type","combat"))
	arena_canvas.lighting_props = flow.room.values.get("layout",{}).get("props",[])
	portrait_hud.queue_redraw()
	arena_canvas.visible = flow.mode != "workshop"
	_layout_top_bar()
	test_canvas.visible = flow.mode == "workshop"
	test_canvas.runner = flow.range_sim
	test_canvas.door_at = desk_door_position() if flow.prelude else Vector2.INF
	test_canvas.door_open = flow.prelude and (not flow.prelude_required() or flow.prelude_ready())
	loadout_view_button.visible = flow.state == "cleared"
	if flow.state != "cleared":
		close_loadout_view()
	_rebuild_loadout()
	_clear(context)
	if scroll != null:
		scroll.scroll_vertical = 0
	summary_retry_button = null
	desk_skip_button = null
	summary_new_seed_button = null
	summary_title_button = null
	var in_summary: bool = flow.state in ["dead","won"]
	var reward_choice: bool = flow.state == "cleared" and flow.room.values["type"] != "boss" and not flow.reward_collected
	var in_workshop: bool = flow.state == "workshop"
	workshop_holder.visible = in_workshop and not editor_open
	reward_overlay.visible = reward_choice
	summary_overlay.visible = in_summary
	_place_context(workshop_column)
	if in_summary:
		_build_summary_panel()
	elif flow.state == "error":
		_heading(context,tr("run.error.run_data"))
	elif reward_choice:
		_build_reward_panel()
	elif flow.state == "cleared" and flow.next_is_optional():
		_button(context,tr("run.btn.door_optional"),func(): _exit(true))
		_button(context,tr("run.btn.door_skip"),func(): _exit(false))
	elif in_workshop and flow.prelude:
		_build_desk_panel()
	elif in_workshop:
		shop_reopen_button = _button(context,tr("run.btn.open_merchant"),func(): _set_shop_open(true))
		_heading(context,tr("run.range.heading"))
		_button(context,tr("run.btn.reset_targets"),func(): _reset_test_range())
		_button(context,tr("run.btn.prepare_wet"),func():
			flow.prepare_wet_cluster()
			current_notice = tr("run.notice.wet_prepared"))
		_button(context,tr("run.btn.refill_mana"),func():
			flow.refill_test_mana()
			current_notice = tr("run.notice.mana_refilled"))
		_button(context,tr("run.btn.continue_stage2"),func(): _exit())
	if in_workshop and not flow.prelude:
		if not _shop_offered:
			_shop_offered = true
			shop_open = true
		_build_shop_panel()
	else:
		_shop_offered = false
		shop_open = false
	_sync_shop()
	reward_overlay.focus_default()
	_update_labels()

## AD-153: kit card art per kind (rune / artifact / upgrade); falls back to the common frame when a rarity has none.
static func card_rarity(kind: String, rarity: String) -> String:
	return rarity if SkinA.has_sprite("ad_ui_card_%s_%s" % [kind,rarity]) else "common"

static func card_sprite(kind: String, rarity: String) -> String:
	return "ad_ui_card_%s_%s" % [kind,card_rarity(kind,rarity)]

## Rune art: the demo icon atlas by rune name (essence.cold -> cold), else the MVP rune icon.
func _rune_art(rune_id: String) -> Texture2D:
	var short := rune_id.get_slice(".",1)
	return SkinA.icon(short) if SkinA.has_icon(short) else PortraitHUD.rune_icon_texture(rune_id)

## Rect of a layout label's row spanning a band's width (centred text).
func _band(o: Overlay, band_id: String, label_id: String) -> Dictionary:
	var band: Dictionary = o.rect_of(band_id)
	var row: Dictionary = o.rect_of(label_id)
	return {"x":band["x"],"y":row["y"],"w":band["w"],"h":row["h"]}

## One kit card (sprite, rarity, name, art) from the card widget `template` shifted by dx canvas px.
func _kit_card(o: Overlay, template: String, node_id: String, dx: float, kind: String, rarity: String, card_name: String, art: Texture2D) -> TextureRect:
	var card_tex := card_sprite(kind,rarity)
	var card := o.picture(node_id,SkinA.region(card_tex),o.rect_of(template,dx))
	card.set_meta("sprite",card_tex)
	var head: Dictionary = o.region_of(template,"header",dx)
	head["y"] += 2.0
	head["h"] = 7.0
	o.text(node_id+"_rarity",tr("run.rarity."+card_rarity(kind,rarity)),head,"selected",HORIZONTAL_ALIGNMENT_CENTER)
	o.picture(node_id+"_icon",art,o.region_of(template,"icon",dx))
	var label_box: Dictionary = o.region_of(template,"text",dx)
	label_box["y"] += 2.0
	label_box["h"] = 16.0
	o.text(node_id+"_name",card_name.to_upper(),label_box,"normal",HORIZONTAL_ALIGNMENT_CENTER,2)
	return card

## AD-153: reward pick per ad_ui_screen_reward_layout.json. Offers, order and keys 1-N come from the flow unchanged.
func _build_reward_panel() -> void:
	var o: Overlay = reward_overlay
	o.begin("reward")
	reward_cards.clear()
	reward_take_buttons.clear()
	o.picture("title_header",SkinA.region("ad_ui_header"),o.rect_of("title_header"))
	o.text("title",tr("run.reward.title"),_band(o,"title_header","title"),"selected",HORIZONTAL_ALIGNMENT_CENTER)
	var room_number := int(flow.room.values.get("room",flow.run.sequence_index))+1
	o.text("subtitle",tr("run.reward.subtitle") % room_number,{"x":0.0,"y":o.rect_of("subtitle")["y"],"w":SkinA.CANVAS.x,"h":7.0},"normal",HORIZONTAL_ALIGNMENT_CENTER)
	o.picture("ico_coin",SkinA.icon_or_mvp("coin"),{"x":520.0,"y":11.0,"w":16.0,"h":16.0})
	o.text("coins_txt",tr("run.reward.coins") % flow.run.currency,{"x":540.0,"y":o.rect_of("coins_txt")["y"],"w":76.0,"h":7.0},"selected",HORIZONTAL_ALIGNMENT_RIGHT)
	var count: int = flow.reward_options.size()
	var step := 200.0 if count <= 3 else floorf(448.0/float(count-1))
	var card_one: Dictionary = o.rect_of("card_1")
	var order: Array = []
	for i in count:
		var item: Dictionary = flow.reward_options[i]
		var centre := SkinA.CANVAS.x*0.5+(float(i)-float(count-1)*0.5)*step
		var dx: float = centre-(card_one["x"]+card_one["w"]*0.5)
		var kind := "upgrade"
		var rarity := "common"
		var card_name := tr("run.reward.coins_name") % int(item.get("amount",0))
		var desc := tr("run.reward.coins_desc")
		var tag_key := "run.reward.tag_currency"
		var art: Texture2D = SkinA.icon_or_mvp("coin")
		if item["kind"] in ["rune","artifact"]:
			kind = str(item["kind"])
			rarity = str(item.get("rarity","common"))
			card_name = tr(str(item["name_key"]))
			desc = tr(str(item["behaviour_key"]))
			tag_key = "run.reward.tag_"+kind
			art = _rune_art(str(item["id"])) if kind == "rune" else SkinA.icon_or_mvp("upgrade")
		var card := _kit_card(o,"card_1","card_%d" % (i+1),dx,kind,rarity,card_name,art)
		reward_cards.append(card)
		var tip_w := minf(160.0,step-8.0)
		var tip: Dictionary = o.rect_of("info_1")
		tip["x"] = centre-tip_w*0.5
		tip["w"] = tip_w
		o.frame("info_%d" % (i+1),"ad_ui_panel_tooltip",tip)
		var inner_x: float = tip["x"]+8.0
		var inner_w := tip_w-16.0
		o.text("info_%d_title" % (i+1),card_name.to_upper(),{"x":inner_x,"y":o.rect_of("info_1_title")["y"],"w":inner_w,"h":7.0},"selected")
		o.text("info_%d_tag" % (i+1),(tr(tag_key) % tr("run.rarity."+card_rarity(kind,rarity))).to_upper(),{"x":inner_x,"y":o.rect_of("info_1_tag")["y"],"w":inner_w,"h":7.0},"hover")
		var rule: Dictionary = o.rect_of("divider_11")
		o.rule("divider_%d" % (i+1),"ad_ui_divider_plain",{"x":inner_x,"y":rule["y"],"w":inner_w,"h":rule["h"]})
		o.text("info_%d_desc" % (i+1),desc.to_upper(),{"x":inner_x,"y":o.rect_of("info_1_desc_0")["y"],"w":inner_w,"h":40.0},"normal",HORIZONTAL_ALIGNMENT_LEFT,4)
		var take := o.button("btn_take_%d" % (i+1),tr("run.reward.take"),_choose_reward.bind(i),o.rect_of("btn_take_1",dx))
		reward_take_buttons.append(take)
		order.append("btn_take_%d" % (i+1))
	var hint_y: float = o.rect_of("hint")["y"]
	o.text("hint",tr("run.reward.keys").to_upper(),{"x":0.0,"y":hint_y,"w":SkinA.CANVAS.x,"h":7.0},"disabled",HORIZONTAL_ALIGNMENT_CENTER)
	var notes: Array = [tr("run.hint.advance")]
	if flow.edit_policy == "cleared_room":
		notes.push_front(tr("run.hint.quick_edit"))
	o.text("hint_notes","   ".join(notes).to_upper(),{"x":96.0,"y":hint_y+10.0,"w":448.0,"h":16.0},"disabled",HORIZONTAL_ALIGNMENT_CENTER,2)
	o.finish(order)

func _build_desk_panel() -> void:
	var slot_ui: int = int(flow.config["sigil_desk"]["formula_index"])+2
	_heading(context,tr("run.desk.heading"))
	var required: bool = flow.prelude_required()
	var step := 0 if not flow.prelude_built else (1 if not flow.prelude_ready() else 2)
	var recipe := PackedStringArray()
	for id in flow.config["sigil_desk"]["runes"]:
		recipe.append(_rune_label(str(id)))
	var lines := [tr("run.desk.step_build") % [slot_ui," + ".join(recipe)],tr("run.desk.step_test") % slot_ui]
	if not required:
		_hint(context,tr("run.desk.optional"))
	for i in lines.size():
		_hint(context,("> " if i == step else "  ")+str(lines[i]).strip_edges())
	_hint(context,("> " if step == 2 or not required else "  ")+tr("run.desk.step_door"))
	_button(context,tr("run.btn.desk_slot") % slot_ui,func(): _open_editor(slot_ui-1))
	_button(context,tr("run.btn.reset_targets"),func(): _reset_test_range())
	var door := _button(context,tr("run.btn.desk_door"),func(): _exit())
	door.disabled = required and not flow.prelude_ready()
	if required and _desk_skippable():
		desk_skip_button = _button(context,tr("run.btn.desk_skip"),func(): _skip_desk(),"ui.cancel")

func _rune_label(id: String) -> String:
	var key := "rune."+id+".name"
	var text := tr(key)
	return id if text == key else text

func _sync_shop() -> void:
	if shop_overlay != null:
		shop_overlay.visible = shop_open and flow != null and flow.state == "workshop" and not editor_open
		shop_overlay.focus_default()
	if workshop_holder != null and flow != null:
		workshop_holder.visible = flow.state == "workshop" and not editor_open and not (shop_overlay != null and shop_overlay.visible)
	if editor_dock != null:
		editor_dock.visible = editor_open
		_fit_editor_panel()
		_fit_test_canvas.call_deferred()

func _set_shop_open(on: bool) -> void:
	shop_open = on
	_sync_shop()

## AD-153: visual-only rarity for upgrade offers (merchant data carries none); matches the merchant mock.
const UPGRADE_RARITY := {"max_hp":"common","max_mana":"common","dash_charge":"rare"}
const UPGRADE_ICONS := {"max_hp":"hp_up","max_mana":"mana_up","dash_charge":"dash_up"}
const SHOP_CARD_AREA := Vector2(24.0,432.0) # canvas x span of the offer cards (left of the side panel)
var _shop_sel := 0
var _shop_views: Array = []

## Card/detail view of one stock item: {kind, rarity, name, art, tag_key, desc}.
func _shop_view(item: Dictionary) -> Dictionary:
	var view := {"kind":"upgrade","rarity":"common","tag_key":"run.reward.tag_upgrade"}
	if item["kind"] == "rune":
		var rune_id := str(item["rune_id"])
		view["kind"] = "rune"
		view["rarity"] = flow.rewards.rarity_of(rune_id,flow.rewards.config)
		view["name"] = _rune_label(rune_id)
		view["art"] = _rune_art(rune_id)
		view["tag_key"] = "run.reward.tag_rune"
		var rune = flow.session.sim.registry.get_rune(rune_id)
		var desc_key := "rune.%s.desc" % rune_id
		view["desc"] = rune_id
		if rune != null:
			view["desc"] = tr(desc_key) if tr(desc_key) != desc_key else str(rune.snapshot()["description"])
	elif item["kind"] == "artifact":
		view["kind"] = "artifact"
		view["rarity"] = Artifacts.rarity_of(str(item["artifact_id"]))
		view["name"] = tr(str(item["label_args"][0]))
		view["art"] = SkinA.icon_or_mvp("upgrade")
		view["tag_key"] = "run.reward.tag_artifact"
		view["desc"] = tr(str(item["desc_key"]))
	else:
		var stat := str(item.get("stat","max_hp"))
		view["rarity"] = UPGRADE_RARITY.get(stat,"common")
		view["name"] = MerchantScript.item_label(item)
		view["art"] = SkinA.icon_or_mvp(UPGRADE_ICONS.get(stat,"hp_up"))
		view["desc"] = tr("run.shop."+stat) % int(item["amount"])
	return view

func _shop_select(i: int) -> void:
	if i < 0 or i >= _shop_views.size() or _shop_detail.size() < 3:
		return
	_shop_sel = i
	var view: Dictionary = _shop_views[i]
	var item: Dictionary = flow.merchant.stock[i]
	var rarity := card_rarity(str(view["kind"]),str(view["rarity"]))
	_shop_detail[0].text = str(view["name"]).to_upper()
	_shop_detail[1].text = ((tr(str(view["tag_key"])) % tr("run.rarity."+rarity))+"   "+tr("run.shop.price_coins") % int(item["price"])).to_upper()
	_shop_detail[2].text = str(view["desc"]).to_upper()

## AD-153: merchant per ad_ui_screen_merchant_layout.json. Stock, prices, buy/reroll rules are the flow's, unchanged.
func _build_shop_panel() -> void:
	var o: Overlay = shop_overlay
	o.begin("merchant")
	shop_cards.clear()
	shop_buy_buttons.clear()
	_shop_views.clear()
	_shop_detail.clear()
	var stock: Array = flow.merchant.stock
	o.picture("title_header",SkinA.region("ad_ui_header"),o.rect_of("title_header"))
	o.text("title",tr(str(flavour.get("merchant",{}).get("title","Merchant"))).to_upper(),_band(o,"title_header","title"),"selected",HORIZONTAL_ALIGNMENT_CENTER)
	var count: int = stock.size()
	var template_x: float = o.rect_of("offer_1")["x"]
	var step: float = o.rect_of("offer_2")["x"]-template_x
	if count > 5:
		step = floorf((SHOP_CARD_AREA.y-SHOP_CARD_AREA.x-o.rect_of("offer_1")["w"])/float(count-1)) # six offers squeeze in without touching the side panel
	var order: Array = []
	for i in count:
		var item: Dictionary = stock[i]
		var t := "%d" % (mini(i,4)+1) # layout slot used as the template for this offer
		var dx: float = SHOP_CARD_AREA.x+step*float(i)-o.rect_of("offer_"+t)["x"]
		var view := _shop_view(item)
		_shop_views.append(view)
		var sold: bool = flow.merchant.bought.has(item["id"])
		var price := int(item["price"])
		var affordable: bool = price <= flow.run.currency
		var card := _kit_card(o,"offer_"+t,"offer_%d" % (i+1),dx,str(view["kind"]),str(view["rarity"]),str(view["name"]),view["art"])
		shop_cards.append(card)
		o.hotspot("offer_%d_select" % (i+1),_shop_select.bind(i),o.rect_of("offer_"+t,dx)).mouse_entered.connect(_shop_select.bind(i))
		var plate: Dictionary = o.rect_of("price_plate_"+t,dx)
		o.frame("price_plate_%d" % (i+1),"ad_ui_panel_tooltip",plate)
		o.picture("price_ico_%d" % (i+1),SkinA.icon_or_mvp("coin"),o.rect_of("price_ico_"+t,dx))
		o.text("price_%d" % (i+1),str(price),{"x":plate["x"]+24.0,"y":o.rect_of("price_"+t)["y"],"w":plate["w"]-28.0,"h":7.0},"selected" if affordable and not sold else "disabled")
		var buy_text := tr("run.shop.sold") if sold else (tr("run.shop.buy") if affordable else tr("run.shop.need_short") % (price-flow.run.currency))
		var buy := o.button("btn_buy_%d" % (i+1),buy_text,_buy.bind(i),o.rect_of("btn_buy_"+t,dx))
		buy.disabled = sold or not affordable
		buy.focus_entered.connect(_shop_select.bind(i))
		buy.mouse_entered.connect(_shop_select.bind(i))
		shop_buy_buttons.append(buy)
		order.append("btn_buy_%d" % (i+1))
		if sold:
			card.modulate = Color(1,1,1,0.55)
	o.frame("detail","ad_ui_panel_tooltip",o.rect_of("detail"))
	var detail: Dictionary = o.rect_of("detail")
	var inner_x: float = detail["x"]+8.0
	var inner_w: float = detail["w"]-16.0
	_shop_detail.append(o.text("detail_title","",{"x":inner_x,"y":o.rect_of("detail_title")["y"],"w":inner_w,"h":7.0},"selected"))
	_shop_detail.append(o.text("detail_tag","",{"x":inner_x,"y":o.rect_of("detail_tag")["y"],"w":inner_w,"h":7.0},"hover"))
	var rule: Dictionary = o.rect_of("divider_51")
	o.rule("detail_rule","ad_ui_divider_plain",{"x":inner_x,"y":rule["y"],"w":inner_w,"h":rule["h"]})
	_shop_detail.append(o.text("detail_desc","",{"x":inner_x,"y":o.rect_of("detail_desc_0")["y"],"w":inner_w,"h":27.0},"normal",HORIZONTAL_ALIGNMENT_LEFT,3))
	_shop_select(clampi(_shop_sel,0,maxi(count-1,0)))
	o.frame("side_panel","ad_ui_panel_large",o.rect_of("side_panel"))
	o.picture("ico_coin",SkinA.icon_or_mvp("coin"),o.rect_of("ico_coin"))
	o.text("coins_txt",tr("run.shop.coins") % flow.run.currency,o.rect_of("coins_txt"),"selected")
	var side_rule: Dictionary = o.rect_of("divider_56")
	o.rule("side_rule","ad_ui_divider_plain",side_rule)
	var remark: Dictionary = o.rect_of("remark_0")
	o.text("remark",tr(flow.merchant.greeting(flow.run.seed)).to_upper(),{"x":remark["x"],"y":remark["y"],"w":side_rule["w"],"h":27.0},"normal",HORIZONTAL_ALIGNMENT_LEFT,3)
	var reroll_price := int(flow.merchant.config.get("reroll_price",0))
	var can_reroll: bool = flow.merchant.reroll_available(flow.run)
	shop_reroll_button = o.button("btn_reroll",tr("run.shop.reroll_btn") % reroll_price if can_reroll else tr("run.shop.reroll_spent"),_reroll)
	shop_reroll_button.disabled = not can_reroll or flow.run.currency < reroll_price
	o.text("reroll_note",tr("run.shop.reroll_note"),o.rect_of("reroll_note"),"disabled")
	shop_close_button = o.button("btn_leave",tr("run.shop.leave"),func(): _set_shop_open(false),{},"ui.cancel")
	o.text("hint",tr("run.shop.hint"),{"x":0.0,"y":o.rect_of("hint")["y"],"w":SkinA.CANVAS.x,"h":7.0},"disabled",HORIZONTAL_ALIGNMENT_CENTER)
	order.append_array(["btn_reroll","btn_leave"])
	o.finish(order)

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
	var b := _button(loadout_list,tr("run.loadout.slot1"),func(): _open_editor(0))
	b.disabled = true
	loadout_slot_buttons.append(b)
	for n in range(2,5):
		var fi := n-2
		var label := str(flow.run.formulas[fi]["display_name"]) if fi < flow.run.formulas.size() else tr("run.loadout.empty")
		var sb := _button(loadout_list,tr("run.loadout.slot_edit") % [n,label],_open_editor.bind(n-1))
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
		test_text = (tr("run.test.line1")+"\n"+tr("run.test.line2")+"\n"+tr("run.test.line3")) % [
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
	if tip != null and _debug_pinned_tip != "":
		guide.current = _debug_pinned_tip
		tip.text = tr("run.tip") % guide.tips[_debug_pinned_tip]
		tip_panel.visible = true
	elif tip != null:
		if _settings != null:
			guide.enabled = _settings.tips_enabled
		_watch_hint_signals()
		var active := ""
		if flow.prelude and not editor_open:
			active = "spells_are_runes"
		elif flow.mode == "workshop" and not flow.prelude:
			active = "first_workshop"
		elif flow.state == "fighting" and flow.run.sequence_index == 0:
			active = "room1"
		elif flow.state == "cleared" and not flow.reward_collected:
			active = "first_reward"
		var hint: String = guide.next_hint()
		if (guide.HINT_IDS.has(guide.current) or guide.is_timed_active()) and not guide.dismissed and hint == "":
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
		tip.text = (tr("run.tip") % guide.text()) if guide.text() != "" else ""
		tip_panel.visible = tip.text != ""
	if editor_open: # the docked editor owns the top-right; toasts must not cover its heading
		tip_panel.visible = false
		notice_panel.visible = false

## Compact top-left objective: room display name + goal for the current state, then the coin count.
func _update_objective() -> void:
	var goal := ""
	if flow.prelude:
		goal = tr("run.goal.desk")
	elif flow.mode == "workshop":
		goal = tr("run.goal.workshop")
	elif flow.state == "fighting":
		goal = tr("run.goal.warden") if flow.room.values["type"] == "boss" else tr("run.goal.undead")
	elif flow.state == "cleared":
		goal = tr("run.goal.exit")
	var title := room_display_name(str(flow.room.values["id"]))
	objective.text = title if goal == "" else tr("run.objective") % [title,goal]
	coins_label.text = "%d" % flow.run.currency
	portrait_hud.room_title = title

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
	guide.tick(Time.get_ticks_msec())
	if flow.state == "fighting" and flow.session != null:
		for enemy in flow.session.enemies:
			if enemy.state == "windup":
				guide.note_telegraph()
				break
	if flow.mode == "workshop" and not flow.prelude:
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
	current_notice = tr("run.notice.reward") % str(result.get("kind",result.get("reason","")))
	_redraw_panel()

func _buy(i: int) -> void:
	var result: Dictionary = flow.buy(i)
	current_notice = tr("run.notice.merchant") % str(result.get("kind",result.get("reason","")))
	if result.get("ok",false):
		current_notice = tr(flow.merchant.purchase_line(flow.run.purchases.size()))
		_autosave()
	_redraw_panel()

func _reroll() -> void:
	var result: Dictionary = flow.reroll()
	current_notice = tr("run.notice.merchant") % str(result.get("kind",result.get("reason","")))
	if result.get("ok",false):
		_autosave()
	_redraw_panel()

## AD-153: run summary per ad_ui_screen_summary_win/lose_layout.json. Data and button callbacks are the existing ones.
func _build_summary_panel() -> void:
	var stats: Dictionary = flow.summary()
	var save = get_node_or_null("/root/SaveService")
	_drop_save()
	if save != null and not _stats_recorded:
		_stats_recorded = true
		stats["discovered"] = flow.discoveries()
		save.record_run(stats)
	var won: bool = flow.state == "won"
	var o: Overlay = summary_overlay
	o.begin("summary_win" if won else "summary_lose")
	o.frame("panel","ad_ui_panel_large",o.rect_of("panel"))
	o.picture("title_header",SkinA.region("ad_ui_header"),o.rect_of("title_header"))
	var panel: Dictionary = o.rect_of("panel")
	var column := {"x":panel["x"],"w":panel["w"]}
	var span := func(id: String, height: float = 7.0) -> Dictionary: return {"x":column["x"],"y":o.rect_of(id)["y"],"w":column["w"],"h":height}
	o.text("title",tr("run.summary.title_win" if won else "run.summary.title_lose"),span.call("title"),"selected",HORIZONTAL_ALIGNMENT_CENTER)
	o.text("result",tr("run.summary.victory" if won else "run.summary.defeated"),span.call("result",14.0),"selected",HORIZONTAL_ALIGNMENT_CENTER,1,14)
	var stage := int(flow.room.values.get("stage",0))+1
	o.text("result_sub",tr("run.summary.sub_win") if won else tr("run.summary.sub_lose") % stage,span.call("result_sub"),"normal",HORIZONTAL_ALIGNMENT_CENTER)
	o.frame("stats","ad_ui_panel_inset",o.rect_of("stats"))
	var seconds := int(stats["seconds"])
	var rows: Array = []
	if flow.room.values.has("stage"):
		rows.append(["run.summary.l_stage","%d" % stage])
	rows.append_array([["run.summary.l_rooms","%d" % int(stats["rooms_cleared"])],["run.summary.l_time","%d:%02d" % [seconds/60,seconds%60]],
		["run.summary.l_kills","%d" % int(stats["kills"])],["run.summary.l_spells","%d" % int(stats["spells_used"])],
		["run.summary.l_coins","%d" % flow.run.currency]])
	for i in rows.size():
		if not o.has_widget("st%d_l" % i):
			break
		o.text("st%d_l" % i,tr(rows[i][0]),o.rect_of("st%d_l" % i),"disabled")
		o.text("st%d_v" % i,rows[i][1],o.rect_of("st%d_v" % i),"selected")
	o.frame("hdr_loadout","ad_ui_header_small",o.rect_of("hdr_loadout"))
	o.text("label_loadout",tr("run.summary.loadout"),_band(o,"hdr_loadout","label_21"),"selected",HORIZONTAL_ALIGNMENT_CENTER)
	for i in 4:
		var n := i+1
		var view: Dictionary = portrait_hud.slot_view(i)
		var filled: bool = not view.is_empty() and not view["empty"]
		o.picture("spell_%d" % n,SkinA.region("ad_ui_slot24_ready" if filled else "ad_ui_slot24_empty"),o.rect_of("spell_%d" % n))
		if not filled:
			continue
		var ir: Array = o.widgets["spell_%d" % n]["icon_rect"]
		o.picture("spell_%d_icon" % n,_rune_art("essence."+str(view["element"])),{"x":ir[0],"y":ir[1],"w":ir[2],"h":ir[3]})
		o.text("spell_key_%d" % n,str(view["key_label"]),o.rect_of("spell_key_%d" % n),"hover")
		o.text("spell_nm_%d" % n,str(view["name"]).to_upper(),o.rect_of("spell_nm_%d" % n),"normal")
	var held: Array = flow.run.artifacts
	for i in held.size():
		var id := "art_%d" % (i+1)
		if not o.has_widget(id):
			break
		o.picture(id,SkinA.region("ad_ui_slot24_ready"),o.rect_of(id))
		var ar: Array = o.widgets[id]["icon_rect"]
		o.picture(id+"_icon",SkinA.icon_or_mvp("upgrade"),{"x":ar[0],"y":ar[1],"w":ar[2],"h":ar[3]})
	o.text("seed",(tr("run.summary.seed") % int(stats["seed"])).to_upper(),o.rect_of("seed"),"normal")
	if save != null:
		var totals: Dictionary = save.stats()
		var best: float = totals["best_time_seconds"]
		o.text("totals",(tr("run.summary.totals") % [totals["runs"],totals["wins"],
			("%d:%02d" % [int(best)/60,int(best)%60]) if best >= 0.0 else "--"]).to_upper(),o.rect_of("milestone"),"disabled")
	var layout_ids: Array = ["btn_new_run","btn_compendium","btn_main_menu"] if won else ["btn_retry_seed","btn_new_run","btn_main_menu"]
	# The win layout's middle slot (Compendium) keeps the run's Retry same seed action; the lose layout already has it.
	summary_retry_button = o.button("btn_retry_seed",tr("run.btn.retry").to_upper(),func(): _retry_same_seed(),o.rect_of(layout_ids[1] if won else "btn_retry_seed"))
	summary_new_seed_button = o.button("btn_new_run",tr("run.btn.new_seed").to_upper(),func(): _new_seed(),o.rect_of("btn_new_run"))
	summary_title_button = o.button("btn_main_menu",tr("run.btn.title").to_upper(),func(): _to_title(),{},"ui.cancel")
	o.finish(["btn_new_run","btn_retry_seed","btn_main_menu"] if won else ["btn_retry_seed","btn_new_run","btn_main_menu"])

## AD-145: locks are recomputed from the profile before each run starts.
func _apply_meta_locks() -> void:
	var save = get_node_or_null("/root/SaveService")
	if save != null:
		flow.set_meta_locks(save.locked_runes(),save.locked_artifacts())

func _retry_same_seed() -> void:
	close_pause()
	_close_visual_editor()
	_drop_save()
	_stats_recorded = false
	_rift_shown = false
	_apply_meta_locks()
	flow.retry_same_seed()
	_begin_desk()
	current_notice = tr("run.notice.retry")
	_redraw_panel()

func _new_seed() -> void:
	close_pause()
	_close_visual_editor()
	_drop_save()
	_stats_recorded = false
	_rift_shown = false
	_apply_meta_locks()
	flow.start_new_seed()
	_begin_desk()
	current_notice = tr("run.notice.new_seed")
	_redraw_panel()

## AD-130: every new run starts at the Sigil Desk when the config offers it.
func _begin_desk() -> void:
	if flow.prelude_available() and flow.enter_prelude()["ok"]:
		guide.prelude_active = true

func _desk_skippable() -> bool:
	var save = get_node_or_null("/root/SaveService")
	return save != null and bool(save.profile["stats"].get("sigil_desk_done",false))

func _skip_desk() -> void:
	if editor_open:
		return
	flow.finish_prelude(true)
	_after_desk(true)
	_flash_transition()
	_redraw_panel()

## Clears the prelude tip suppression once the desk is over; persists completion on the door path.
func _after_desk(skipped: bool) -> void:
	if flow.prelude:
		return
	guide.prelude_active = false
	if skipped:
		return
	var save = get_node_or_null("/root/SaveService")
	if save == null:
		return
	save.profile["stats"]["sigil_desk_done"] = true
	var ids: Array = save.profile["stats"].get("onboarding_seen", [])
	for id in guide.note_prelude_done():
		if not ids.has(id):
			ids.append(id)
	save.profile["stats"]["onboarding_seen"] = ids
	save.save_profile()

func _to_title() -> void:
	flow.experiment.end_session()
	close_pause()
	get_tree().change_scene_to_file("res://scenes/main.tscn")

func _exit(take_optional: bool = true) -> void:
	if editor_open:
		return
	var was_desk: bool = flow.prelude
	var desk_skipped: bool = was_desk and not flow.prelude_ready()
	var was_workshop: bool = flow.state == "workshop"
	var result: Dictionary = flow.try_exit(flow.session.sim.actor.position, take_optional)
	if was_desk and result["ok"]:
		_after_desk(desk_skipped)
	current_notice = tr("run.notice.door") % (str(result.get("reason","OPEN")) if result["ok"] == false else tr("run.notice.next_room"))
	if result["ok"]:
		if was_workshop:
			_drop_save()
		if flow.state == "workshop":
			_autosave()
		_flash_transition()
	_redraw_panel()

func _flash_transition() -> void:
	if ReduceMotion.flashes_reduced(_settings, null):
		return
	transition_veil.modulate.a = 0.85
	var tween := create_tween()
	tween.tween_property(transition_veil,"modulate:a",0.0,0.4)

## Dev cheat: kill every enemy (waves included) via normal damage + sim steps so clear/reward logic runs as usual.
func _dev_clear_room() -> void:
	for i in 3000:
		if flow.state != "fighting":
			return
		for enemy in flow.session.enemies:
			if enemy.target.alive():
				enemy.target.receive_damage(100000,"fire",1,100)
		flow.step()

func _dev_kill_all() -> void:
	if not dev_tools_enabled() or editor_open:
		return
	_dev_clear_room()
	current_notice = tr("run.notice.dev_cheat") % flow.state
	_redraw_panel()

## Dev cheat: clear, take reward 0, leave by the exit (skips optional rooms). Returns true when a new room was entered.
func _dev_advance() -> bool:
	if editor_open:
		return false
	if flow.prelude:
		flow.finish_prelude(true)
		_after_desk(true)
		return not flow.prelude
	_dev_clear_room()
	if flow.state == "cleared" and not flow.reward_collected and not flow.reward_options.is_empty():
		flow.choose_reward(0)
	if flow.state not in ["cleared","workshop"]:
		return false
	if flow.mode != "workshop":
		flow.session.sim.actor.position = flow.room.marker("exit")
	return flow.try_exit(flow.session.sim.actor.position,false)["ok"]

func _dev_skip_room() -> void:
	if not dev_tools_enabled():
		return
	if _dev_advance():
		_flash_transition()
	current_notice = tr("run.notice.dev_cheat") % str(flow.room.values["id"])
	_redraw_panel()

func _dev_next_stage() -> void:
	if not dev_tools_enabled():
		return
	var start := int(flow.room.values.get("stage",0)) if not flow.prelude else 0
	for guard in 60:
		if not _dev_advance():
			break
		if not flow.prelude and int(flow.room.values.get("stage",0)) > start:
			break
	_flash_transition()
	current_notice = tr("run.notice.dev_cheat") % str(flow.room.values["id"])
	_redraw_panel()

func _policy() -> void:
	var next := "cleared_room" if flow.edit_policy == "workshop_only" else "workshop_only"
	flow.change_edit_policy(next)
	current_notice = tr("run.notice.edit_policy") % next
	_redraw_panel()

func _slot_name(fi: int) -> String:
	return str(flow.run.formulas[fi]["display_name"]) if fi < flow.run.formulas.size() else tr("run.loadout.empty")

func _open_editor(index: int) -> void:
	if editor_open:
		return
	if index <= 0:
		current_notice = tr("run.notice.slot1_locked")
		_update_labels()
		return
	var result: Dictionary = flow.open_editor(index-1)
	if not result["ok"]:
		current_notice = tr("run.notice.editor") % str(result.get("reason","BLOCKED"))
		_update_labels()
		return
	editor_open = true
	_sync_shop()
	opened_editor_ms = Time.get_ticks_msec()
	editor_panel.visible = true
	_editor_rebuild()
	_update_labels()

func _editor_rebuild() -> void:
	var keep := editor_scroll.scroll_vertical
	_clear(editor_controls)
	_clear(editor_buttons)
	editor_view.build(editor_controls,editor_buttons,flow.editor,{"rebuild":_editor_rebuild,"loadout":flow.range_sim.loadout if flow.range_sim != null else null,
		"apply":func(): _close_editor(true),"cancel":func(): _close_editor(false)},_director)
	editor_preview = editor_view.preview
	editor_scroll.set_deferred("scroll_vertical",keep) # a rebuild keeps the player's place in the column

func _close_visual_editor() -> void:
	editor_open = false
	if editor_panel != null:
		editor_panel.visible = false
	_sync_shop()

func _close_editor(apply_changes: bool) -> void:
	var duration := float(Time.get_ticks_msec()-opened_editor_ms)/1000.0
	var result: Dictionary = flow.close_editor(apply_changes,duration)
	if not result["ok"]:
		current_notice = tr("run.notice.editor") % str(result.get("reason","INVALID"))
		_editor_rebuild()
		return
	if apply_changes:
		guide.note_valid_edit()
	current_notice = (tr("run.notice.formula_applied") if apply_changes else tr("run.notice.formula_cancelled"))+tr("run.notice.duration") % duration
	_close_visual_editor()
	_autosave()
	_redraw_panel()

## AD-090: debug-only UI shot-state hook (env AD_UI_SHOT_STATE / AD_UI_SHOT_OUT); inert in release builds.
const DEBUG_TIP_BASE := {"tip_room1":"combat","tip_telegraph":"combat","tip_wet_try_lightning":"combat","tip_first_reward":"reward","tip_first_workshop":"workshop","tip_workshop_empty_slot":"workshop","tip_test_on_dummy":"workshop","tip_spells_are_runes":"sigil_desk"}
var _debug_pinned_tip := ""

func apply_debug_shot_state(state: String) -> bool:
	if not OS.is_debug_build():
		return false
	if DEBUG_TIP_BASE.has(state):
		_debug_pinned_tip = state.trim_prefix("tip_")
		state = DEBUG_TIP_BASE[state]
	if not state in ["combat","reward","loadout","workshop","workshop_editor","merchant","pause","pause_controls","summary","summary_win","sigil_desk"]:
		return false
	if state == "sigil_desk":
		if not flow.prelude and not (flow.prelude_available() and flow.enter_prelude()["ok"]):
			return false
		guide.prelude_active = flow.prelude
		_redraw_panel()
		return true
	if flow.prelude:
		flow.finish_prelude(true)
		guide.prelude_active = false
	if state == "reward" or state == "loadout":
		for i in 3000:
			if flow.state != "fighting":
				break
			for enemy in flow.session.enemies:
				if enemy.target.alive():
					enemy.target.receive_damage(100000,"fire",1,100)
			flow.step()
	elif state == "workshop_editor" or state == "merchant" or state == "workshop":
		for i in flow.rooms.size():
			if str(flow.rooms[i].get("type","")) == "workshop":
				flow.run.sequence_index = i
				break
		flow._enter_current()
	elif state == "summary_win":
		for i in 400:
			if flow.state == "won" or not _dev_advance():
				break
		if flow.state != "won":
			return false
	elif state == "summary":
		flow.session.sim.actor.receive_damage(100000,"fire",2,100)
		flow.step({"cast":0})
	_redraw_panel()
	if state == "workshop_editor":
		_set_shop_open(false)
		_open_editor(1) # slot 0 (Basic Bolt) is locked; slot 1 is the first editable one
	elif state == "merchant":
		_set_shop_open(true)
	elif state == "workshop":
		_set_shop_open(false)
	elif state == "pause":
		open_pause()
	elif state == "pause_controls":
		open_pause()
		pause_menu.open_controls()
	elif state == "loadout":
		open_loadout_view()
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
