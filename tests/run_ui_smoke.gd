extends SceneTree
const SkinA = preload("res://ui/skin_a.gd")
var failures := 0
func _initialize() -> void:
	call_deferred("_run")
func expect(success: bool, what: String) -> void:
	if success:
		print("M3 UI PASS: ",what)
	else:
		failures += 1
		printerr("M3 UI FAIL: ",what)

func _install_save_sandbox():
	var save = root.get_node_or_null("SaveService")
	if save == null:
		save = preload("res://game/core/save_service.gd").new()
		save.name = "SaveService"
		root.add_child(save)
	var dir := "user://ad019_smoke/"
	DirAccess.make_dir_recursive_absolute(dir)
	for f in DirAccess.get_files_at(dir):
		DirAccess.remove_absolute(dir + f)
	save.set_base_dir(dir)
	return save

func run_spawns(flow) -> Array:
	var out: Array = []
	for enemy in flow.session.enemies:
		out.append([enemy.kind,enemy.target.position])
	return out

func spawns_equal(a: Array, b: Array) -> bool:
	if a.size() != b.size() or a.is_empty():
		return false
	for i in a.size():
		if a[i][0] != b[i][0] or not a[i][1].is_equal_approx(b[i][1]):
			return false
	return true

func _esc_event() -> InputEventKey:
	var ev := InputEventKey.new()
	ev.keycode = KEY_ESCAPE
	ev.physical_keycode = KEY_ESCAPE
	ev.pressed = true
	return ev

func _run() -> void:
	var save = _install_save_sandbox()
	var pack = load("res://scenes/run.tscn")
	expect(pack is PackedScene,"M3 scene loadable")
	if not pack is PackedScene:
		quit(1)
		return
	var control = pack.instantiate()
	control.show_dev_tools = false # release-like run: no F3 overlay, no F2/F3/F6
	control.config_path = "res://world/data/vertical_slice_v1.json"
	root.add_child(control)
	current_scene = control
	await process_frame
	expect(control.flow != null and control.flow.initialized,"run model initialized")
	if control.flow == null or not control.flow.initialized:
		quit(1)
		return
	expect(control.tip != null and control.tip.text.contains("TIP") and control.tip.text.contains("Space")
		and control.guide.current=="room1","AD-042 room1 tip shown on first combat")
	control._guide(false)
	expect(control.tip.text.is_empty(),"AD-042 tips can be dismissed")
	control._guide(true)
	expect(not control.tip.text.contains("Space") and control.guide.seen.count("room1")==1,
		"AD-042 room1 tip does not return")
	expect(not control.flow.experiment.enabled,"M4 local telemetry requires opt-in")
	control.flow.experiment.configure(true)
	expect(control.flow.experiment.enabled,"M4 telemetry opt-in enables capture")
	control._export_metrics()
	expect(FileAccess.file_exists("user://arcane_m4_experiment.json"),"M4 UI exports local JSON")
	expect(FileAccess.file_exists("user://arcane_m4_experiment.csv"),"M4 UI exports local CSV")
	control.flow.experiment.configure(false)
	expect(control.flow.experiment.summary()["events"]==0,"M4 opt-out clears in-memory records")
	expect(control.flow.state=="fighting" and control.flow.room.values["id"]=="s1_r1",
		"new game enters first combat")
	var spawns_a: Array = run_spawns(control.flow)
	var seed_a: int = control.flow.run.seed
	var t0: int = control.flow.session.sim.clock.tick
	var e0: int = control.flow.ticks_elapsed
	control.open_pause()
	expect(control.is_paused(),"AD-068 pause opens in combat room")
	expect(Input.mouse_mode == Input.MOUSE_MODE_VISIBLE,"AD-068 cursor visible while paused")
	for i in 10:
		await physics_frame
	expect(control.flow.session.sim.clock.tick == t0 and control.flow.ticks_elapsed == e0,
		"AD-068 sim tick does not advance while paused")
	var rkey := InputEventKey.new()
	rkey.keycode = KEY_R
	rkey.pressed = true
	control._input(rkey)
	expect(control.flow.room.values["id"]=="s1_r1" and control.flow.session.sim.clock.tick == t0,
		"AD-068 gameplay input blocked while paused")
	control.pause_menu.open_settings()
	expect(control.pause_menu.is_settings_open(),"AD-068 pause opens settings")
	control.pause_menu.handle_cancel()
	expect(not control.pause_menu.is_settings_open() and control.is_paused(),"AD-068 cancel closes settings only")
	control.pause_menu.open_controls()
	expect(control.pause_menu.is_settings_open() and control.pause_menu.settings_screen.current_tab == "controls",
		"AD-152 Settings opens and select_tab(controls) works")
	control.pause_menu.handle_cancel()
	expect(not control.pause_menu.is_settings_open() and control.is_paused() and control.pause_menu.panel.visible,
		"AD-092 cancel closes settings")
	expect(control.pause_menu.find_child("QuitButton",true,false).text == "Abandon","AD-152 pause menu leaves via Abandon")
	control.pause_menu.tips_toggled.emit()
	expect(control.guide.dismissed and control.tip.text.is_empty(),"AD-092 pause menu hides tips")
	control.pause_menu.tips_toggled.emit()
	expect(not control.guide.dismissed,"AD-092 pause menu shows tips again")
	control._input(_esc_event())
	expect(not control.is_paused(),"AD-068 Esc closes pause menu")
	for i in 5:
		await physics_frame
	expect(control.flow.session.sim.clock.tick > t0,"AD-068 sim resumes after unpausing")
	control.open_pause()
	control.pause_menu.request_retry()
	expect(control.pause_menu.is_confirm_open() and control.flow.run.seed == seed_a,"AD-068 retry asks for confirmation")
	control.pause_menu.confirm_pending()
	var spawns_b: Array = run_spawns(control.flow)
	var kinds_a: Array = spawns_a.map(func(x): return x[0])
	var kinds_b: Array = spawns_b.map(func(x): return x[0])
	control.open_pause()
	control.pause_menu.request_retry()
	control.pause_menu.confirm_pending()
	expect(not control.is_paused() and control.flow.room.values["id"]=="s1_r1" and control.flow.run.seed == seed_a
		and kinds_a == kinds_b and spawns_equal(run_spawns(control.flow),spawns_b),
		"AD-068 retry gives same seed and room-1 spawns")
	expect(control.arena_canvas != null and control.arena_canvas.visible,"combat canvas visible")
	var old_sidebar: Array = control.find_children("*","ScrollContainer",true,false).filter(func(n): return n.name.to_lower().contains("sidebar"))
	expect(control.get("sidebar") == null and control.find_child("*idebar*",true,false) == null and old_sidebar.is_empty(),
		"AD-092 no run sidebar")
	var view: Vector2 = control.get_viewport_rect().size
	expect(control.arena_area.size.x >= view.x*0.9,"AD-092 arena area spans at least 90% of the viewport width")
	var pause_rect: Rect2 = control.pause_button.get_global_rect()
	expect(control.pause_button.name == "PauseButton" and control.pause_button.is_visible_in_tree()
		and pause_rect.position.x > view.x*0.5 and pause_rect.position.y < view.y*0.2 and pause_rect.end.x <= view.x,
		"AD-092 PauseButton visible top-right")
	expect(control.objective.text.contains(control.room_display_name("s1_r1")) and control.objective.text.contains("Defeat"),
		"AD-092 objective line shows room name and goal")
	expect(control.dev_panel == null and control.portrait_hud == control.arena_canvas.slot_hud,
		"AD-092 no dev overlay when dev tools are off; portrait_hud is the bottom HUD")
	var dev_key := InputEventKey.new()
	dev_key.keycode = KEY_F3
	dev_key.pressed = true
	control._input(dev_key)
	expect(not control.arena_canvas.show_debug,"AD-092 F3 does nothing without dev tools")
	var banned := ["ARCANE DUNGEON / M4","Edit policy","Render FPS","Waves scheduled","telemetry","Toggle debug","Back to Menu"]
	var leaked: Array = []
	for node in control.find_children("*","Control",true,false):
		if (node is Label or node is Button) and node.is_visible_in_tree():
			for word in banned:
				if str(node.text).contains(word):
					leaked.append(str(node.text))
	expect(leaked.is_empty(),"AD-092 no dev/telemetry/Back to Menu text in the visible run UI: "+str(leaked))
	var small_fonts: Array = []
	for node in control.find_children("*","Control",true,false):
		if (node is Label or node is Button) and node.has_theme_font_size_override("font_size") and node.get_theme_font_size("font_size") < 14:
			small_fonts.append(str(node.text))
	expect(small_fonts.is_empty(),"AD-092 run UI text is at least 14 px: "+str(small_fonts))
	control._open_editor(1)
	expect(not control.editor_open,"editor cannot open during combat")
	var run = control.flow
	run.session.enemies[0].target.receive_damage(1000,"fire",1,100)
	run.step()
	control._redraw_panel()
	expect(run.state=="cleared","first room advances to clear state")
	expect(control.reward_overlay.visible and control.reward_overlay.get_child_count()>1,"reward choice panel created")
	expect(control.tip.text.contains("3 cards"),"AD-042 first_reward tip at first clear")
	var view_h: float = control.get_viewport_rect().size.y
	var reward_buttons: Array = control.reward_overlay.find_children("*","Button",true,false)
	expect(not reward_buttons.is_empty() and reward_buttons.all(func(b): return b.get_global_rect().end.y <= view_h),
		"reward buttons on screen at first clear")
	var takes: Array = control.reward_take_buttons
	expect(takes.size()==run.reward_options.size() and takes.size()==control.reward_cards.size() and takes.size()>=3
		and takes.all(func(b): return b.is_visible_in_tree()),
		"AD-153 one TAKE button and one kit card per reward option")
	expect(control.reward_cards.all(func(c): return c.texture != null and SkinA.has_sprite(str(c.get_meta("sprite")))),
		"AD-153 every reward card uses a kit sprite")
	expect(takes.all(func(b): return b.get_global_rect().end.x <= control.get_viewport_rect().size.x and b.get_global_rect().position.x >= 0.0),
		"AD-093 reward cards stay on screen")
	expect(control.reward_overlay.find_children("*","ScrollContainer",true,false).is_empty(),"AD-093 reward cards not inside a ScrollContainer")
	var key_one := InputEventKey.new()
	key_one.keycode = KEY_1
	key_one.pressed = true
	control._input(key_one)
	expect(run.reward_collected,"key 1 grants first reward")
	expect(str(run.room.values["id"]) in run.run.collected,"collect event recorded")
	expect(control.loadout_view_button.is_visible_in_tree(),"AD-147 loadout button visible after clear")
	var tab := InputEventKey.new()
	tab.keycode = KEY_TAB
	tab.physical_keycode = KEY_TAB
	tab.pressed = true
	control._input(tab)
	expect(control.is_loadout_view_open(),"AD-147 Tab opens the loadout view")
	var slot_rows := 0
	for i in 4:
		if control.loadout_view.find_child("LoadoutSlot%d" % i,true,false) != null: slot_rows += 1
	expect(slot_rows==4,"AD-147 view shows 4 slot rows")
	var art_ok: bool = false
	for l in control.loadout_view.find_children("*","Label",true,false):
		if l.text==tr("loadout_view.artifacts") or l.text==tr("loadout_view.no_artifacts"): art_ok = true
	expect(art_ok,"AD-147 view shows artifacts section")
	var view_buttons: Array = control.loadout_view.find_children("*","Button",true,false)
	expect(view_buttons.size()==1 and view_buttons[0].name=="LoadoutCloseButton"
		and control.loadout_view.find_children("*","OptionButton",true,false).is_empty()
		and control.loadout_view.find_children("*","LineEdit",true,false).is_empty(),"AD-147 view is read-only (close button only)")
	control._open_editor(2)
	var edit_try: Dictionary = control.flow.open_editor(1)
	expect(not control.editor_open and not edit_try["ok"] and str(edit_try.get("reason",""))=="POLICY_WORKSHOP_ONLY" and run.edit_policy=="workshop_only",
		"AD-147 editing impossible outside the workshop")
	var room_before = run.room.values["id"]
	var collected_before: bool = run.reward_collected
	control._input(key_one)
	expect(control.is_loadout_view_open() and run.reward_collected==collected_before and run.room.values["id"]==room_before,"AD-147 gameplay keys swallowed while open")
	control._input(tab)
	expect(not control.is_loadout_view_open(),"AD-147 Tab closes the view")
	control.loadout_view_button.emit_signal("pressed")
	expect(control.is_loadout_view_open(),"AD-147 button opens the view")
	control.loadout_view.find_child("LoadoutCloseButton",true,false).emit_signal("pressed")
	expect(not control.is_loadout_view_open(),"AD-147 close button closes the view")
	control.loadout_view_button.emit_signal("pressed")
	control._exit()
	expect(run.room.values["id"]=="s1_r1","far-away exit button cannot skip door")
	run.session.sim.actor.position = run.room.marker("exit")
	control._exit()
	expect(run.room.values["id"]=="s1_r2","exit button from marker traverses to room 2")
	control.open_loadout_view()
	expect(not control.is_loadout_view_open() and not control.loadout_view_button.visible,"AD-147 view closed and button hidden in next room")
	control._policy()
	expect(run.edit_policy=="cleared_room","edit-policy toggle")
	for i in [1,2,3]:
		while run.state=="fighting":
			for enemy in run.session.enemies:
				if enemy.target.alive():
					enemy.target.receive_damage(9999,"fire",1,100)
			run.step()
			for j in 40:
				if run.state != "fighting":
					break
				run.step()
		control._redraw_panel()
		if run.room.values["type"] == "combat":
			control._choose_reward(0)
		run.session.sim.actor.position = run.room.marker("exit")
		control._exit()
	expect(run.room.values["id"]=="workshop","UI traversal reaches workshop after boss")
	expect(save.has_run(),"AD-146 entering the workshop writes a run save")
	control.open_pause()
	expect(control.pause_menu.save_quit_button.visible,"AD-146 Save & Quit visible in workshop pause")
	control.close_pause()
	expect(run.mode=="workshop" and control.test_canvas.visible,"test canvas enabled in safe workshop")
	var w0: int = run.range_sim.clock.tick
	var wpos: Vector2 = run.range_sim.actor.position
	control.open_pause()
	expect(control.is_paused(),"AD-068 pause opens in workshop")
	for i in 10:
		await physics_frame
	expect(run.range_sim.clock.tick == w0 and run.range_sim.actor.position == wpos,
		"AD-068 workshop sim frozen while paused")
	control.close_pause()
	expect(not control.is_paused(),"AD-068 workshop pause closes")
	expect(not control.arena_canvas.visible,"combat canvas hidden during workshop")
	expect(control.tip.text.contains("slot 4"),"AD-042 first_workshop tip on entering workshop")
	expect(control.context.get_child_count()>3,"workshop test tools visible")
	expect(control.shop_overlay.visible and control.is_ancestor_of(control.shop_overlay),"AD-153 shop overlay opens on workshop entry")
	var previews := false
	for b in control.shop_buy_buttons:
		if b.text == control.tr("run.shop.buy") or b.text.begins_with(control.tr("run.shop.need_short").get_slice("%",0)) or b.text == control.tr("run.shop.sold"):
			previews = true
	expect(previews,"merchant displays affordability on each BUY button")
	var stock: Array = control.flow.merchant.stock
	expect(control.shop_cards.size()==stock.size() and control.shop_buy_buttons.size()==stock.size() and stock.size()>=3,
		"AD-153 one offer card and BUY button per stock item")
	expect(control.shop_cards.all(func(c): return SkinA.has_sprite(str(c.get_meta("sprite")))),"AD-153 every merchant offer uses a kit sprite")
	var priced: Array = control.shop_overlay.find_children("price_*","Label",true,false)
	expect(priced.size()==stock.size() and control.shop_overlay.find_children("price_ico_*","TextureRect",true,false).size()==stock.size(),
		"AD-153 merchant offers show price plates with the coin icon")
	for i in stock.size():
		var affordable: bool = int(stock[i]["price"]) <= control.flow.run.currency and not control.flow.merchant.bought.has(stock[i]["id"])
		expect(control.shop_buy_buttons[i].disabled == not affordable,"AD-153 BUY button %d disabled exactly when unaffordable or sold" % i)
	control.shop_close_button.emit_signal("pressed")
	expect(not control.shop_overlay.visible,"AD-093 Close shop hides the shop overlay")
	control.shop_reopen_button.emit_signal("pressed")
	expect(control.shop_overlay.visible,"AD-093 Open merchant reopens the shop overlay")
	control.flow.experiment.configure(true)
	control._update_labels()
	control._update_labels()
	expect(run.run.formulas.size()<3 and control.guide.current=="workshop_empty_slot"
		and control.tip.text.contains(control.guide.tips["workshop_empty_slot"]),
		"AD-084 workshop shows empty-slot hint")
	# The smoke run uses the v1 config, which has no reroll tunables; give the merchant the v2 price.
	control.flow.merchant.config["reroll_price"] = 15
	control._redraw_panel()
	expect(control.shop_reroll_button != null and control.shop_reroll_button.text.contains("15"),"AD-144 merchant shows a reroll button with its price")
	var coins_start: int = run.run.currency
	run.run.currency += 100
	control._redraw_panel()
	var reroll_price := 15
	var coins_before: int = run.run.currency
	expect(not control.shop_reroll_button.disabled,"AD-144 reroll enabled when affordable")
	control.shop_reroll_button.emit_signal("pressed")
	expect(run.run.currency == coins_before-reroll_price,"AD-144 reroll deducts exactly its price")
	expect(control.shop_reroll_button.disabled,"AD-144 reroll button disabled after use")
	run.run.currency = coins_start # keep later guide/telemetry checks on the original economy
	control._redraw_panel()
	control.shop_close_button.emit_signal("pressed") # AD-153: the merchant is a modal; the player leaves it before editing
	control._open_editor(1)
	expect(control.editor_open and control.editor_panel.visible,"structured editor panel opens")
	expect(not (control.editor_panel.get_parent() is CenterContainer),"AD-093 editor is docked, not centred")
	expect(not control.workshop_holder.visible,"AD-093 workshop side panel hidden while editor open")
	var palette_tabs = control.editor_controls.find_child("RunePalette",true,false)
	var palette_ids: Array = []
	for b in control.editor_controls.find_children("*","Button",true,false):
		if b.has_meta("rune_id"):
			palette_ids.append(str(b.get_meta("rune_id")))
	palette_ids.sort()
	expect(palette_tabs is TabContainer and palette_tabs.get_tab_count()==4 and palette_ids.size()==run.session.sim.registry.get_ids().size()
		and palette_ids==run.session.sim.registry.get_ids(),
		"AD-129 editor has RunePalette with 4 category tabs and one button per registered rune")
	var old: Dictionary = run.run.formulas[0].duplicate(true)
	run.editor.set_root("essence.water","form.projectile")
	control._editor_rebuild()
	expect(control.editor_preview.text.contains("VALID"),"editor live validation shows valid draft")
	control._close_editor(false)
	expect(not control.editor_open and run.run.formulas[0]==old,"editor cancel restores original")
	expect(control.workshop_holder.visible,"AD-093 workshop side panel visible again after cancel")
	control._open_editor(1)
	run.editor.set_root("essence.water","form.projectile")
	control._editor_rebuild()
	control._close_editor(true)
	expect(run.run.formulas[0]["formula_id"]=="custom.slot_1","editor apply persists formula")
	expect(control.guide.current=="test_on_dummy" and control.tip.text.contains(control.guide.tips["test_on_dummy"]),
		"AD-084 test_on_dummy shown after first valid edit")
	control._test_cast_slot(1,run.range_sim.actor.position+Vector2(200,0))
	control._update_labels()
	expect(control.guide.current!="test_on_dummy" and control.guide.seen.count("test_on_dummy")==1,
		"AD-084 test cast clears test_on_dummy")
	expect(run.range_sim.loadout.preview(1)["formula_id"]=="custom.slot_1",
		"test range refreshes after apply")
	control._open_editor(0)
	expect(not control.editor_open,"slot 1 cannot be edited")
	expect(control.loadout_slot_buttons[0].disabled and control.loadout_slot_buttons[0].text.contains("LOCKED"),
		"slot 1 button locked")
	control._open_editor(3)
	expect(control.editor_open and control.editor_preview.text.contains("VALID") and control.editor_preview.text.contains("Cooldown") and control.editor_preview.text.contains("cap"),
		"slot 4 opens with cap-aware preview")
	var locked_mod := "mod.pierce" if "mod.pierce" not in run.run.unlocked else "mod.homing"
	if locked_mod in run.run.unlocked:
		locked_mod = "mod.chain"
	run.editor.set_root("essence.fire","form.projectile")
	run.editor.toggle_modifier(locked_mod)
	control._editor_rebuild()
	var apply_disabled := false
	for b in control.editor_controls.find_children("*","Button",true,false):
		if b.text.begins_with("Apply"):
			apply_disabled = b.disabled
	expect(control.editor_preview.text.contains("INVALID") and control.editor_preview.text.contains(control.tr("editor.issue.rune_locked").get_slice(":",0)) and apply_disabled,
		"invalid formula shows reason, Apply disabled")
	control._close_editor(true)
	expect(control.editor_open and run.run.formulas.size()==2,"invalid formula cannot be equipped")
	run.editor.toggle_modifier(locked_mod)
	run.editor.set_root("essence.lightning","form.projectile")
	control._editor_rebuild()
	control._close_editor(true)
	expect(run.run.formulas.size()==3 and run.range_sim.loadout.preview(3)["formula_id"]=="custom.slot_3",
		"valid slot 4 applied")
	var cast4: Dictionary = control._test_cast_slot(3,run.range_sim.actor.position+Vector2(200,0))
	expect(cast4.get("accepted",false),"slot 4 casts in range")
	# AD-135: five new rune combinations built through the editor API
	for rune_id in run.session.sim.registry.get_ids():
		if rune_id not in run.run.unlocked and not rune_id.begins_with("essence.neutral"):
			run.run.unlocked.append(rune_id)
	var combos := [
		["essence.cold","form.beam",["mod.chain"],"",""],
		["essence.force","form.field",["mod.expand"],"trigger.timer","essence.fire"],
		["essence.lightning","form.orb",["mod.rapid"],"trigger.on_expire","essence.water"],
		["essence.fire","form.burst",["mod.chain"],"trigger.on_kill","essence.cold"],
		["essence.water","form.projectile",["mod.pierce","mod.rapid"],"trigger.on_hit","essence.lightning"]]
	for combo in combos:
		control._open_editor(3)
		var ed = run.editor
		ed.set_root(combo[0],combo[1])
		for mod_id in combo[2]:
			ed.toggle_modifier(mod_id)
		if combo[3] != "":
			ed.set_trigger(true,combo[4],combo[3])
		control._editor_rebuild()
		expect(control.editor_preview.text.contains("VALID") and not control.editor_preview.text.contains("INVALID"),
			"AD-135 combo %s shows VALID" % str(combo))
		var before_apply: int = run.run.formulas.size()
		control._close_editor(true)
		expect(not control.editor_open and run.run.formulas.size()==before_apply
			and run.run.formulas[before_apply-1]["root"]["manifestation_id"]==combo[1],
			"AD-135 combo %s applied" % str(combo))
	control._open_editor(3)
	run.editor.set_root("essence.fire","form.burst")
	run.editor.set_trigger(true,"essence.cold","trigger.timer")
	control._editor_rebuild()
	var neg_apply_disabled := false
	for b in control.editor_controls.find_children("*","Button",true,false):
		if b.text.begins_with("Apply"):
			neg_apply_disabled = b.disabled
	expect(control.editor_preview.text.contains(control.tr("editor.issue.trigger_needs_lasting")) and neg_apply_disabled,
		"AD-135 burst + timer shows lasting-form reason, Apply disabled")
	control._close_editor(false)
	run.wet_kills += 1
	control._update_labels()
	expect(control.guide.current=="wet_try_lightning" and control.tip.text.contains("Lightning") and not control.is_paused()
		and not control.editor_open and control.guide.seen.count("wet_try_lightning")==1,
		"AD-084 wet kill shows hint without pausing")
	var shown_before: int = control.guide.shown_count
	run.arcs += 1
	control._update_labels()
	expect(control.guide.arc_seen and control.guide.current=="" and control.guide.shown_count==shown_before,
		"AD-084 arc turns the wet hint off")
	run.wet_kills += 1
	control._update_labels()
	expect(control.guide.current!="wet_try_lightning" and control.guide.seen.count("wet_try_lightning")==1,
		"AD-084 no wet hint after an arc")
	var prompt_records := 0
	for rec in run.experiment.records:
		if rec["type"]=="prompt_shown":
			prompt_records += 1
	expect(prompt_records>=3 and prompt_records<=control.guide.shown_count,
		"AD-084 telemetry counts prompt_shown")
	control._reset_test_range()
	expect(run.range_sim.active.size()==0,"reset range clears spells")
	control._test_click(run.range_sim.actor.position+Vector2(200,0),MOUSE_BUTTON_LEFT)
	expect(run.range_sim.active.size()>0,"workshop test click spawns compiled spell")
	control._redraw_panel()
	expect(control.info.text.contains("Triggers"),"testing HUD contains trigger/reaction/status feedback")
	var mage0: Vector2 = run.range_sim.actor.position
	control._move_test_mage(Vector2.RIGHT)
	expect(run.range_sim.actor.position.x > mage0.x,"workshop WASD moves the visible test-range mage")
	# No visible door in the workshop: the continue button/F works from wherever the player stands.
	control._exit()
	expect(run.room.values["id"]=="s2_r1","workshop exit leads into next stage")
	expect(not save.has_run(),"AD-146 leaving the workshop deletes the run save")
	for enemy in run.session.enemies:
		enemy.target.receive_damage(10000,"fire",1,100)
	run.step()
	control._redraw_panel()
	expect(run.state=="won","clearing the first stage-2 room wins the slice")
	var texts: Array = []
	for item in control.summary_overlay.find_children("*","Label",true,false):
		texts.append(item.text)
	var joined := "\n".join(texts)
	expect(joined.contains(control.tr("run.summary.title_win")) and joined.contains(control.tr("run.summary.victory")),"win opens Run Summary: victory")
	expect(joined.contains(control.tr("run.summary.l_kills")) and joined.contains(control.tr("run.summary.l_spells")),"summary shows kills and spells used")
	expect(control.summary_retry_button != null and control.summary_retry_button.is_visible_in_tree()
		and control.summary_new_seed_button != null and control.summary_new_seed_button.is_visible_in_tree()
		and control.summary_title_button != null and control.summary_title_button.is_visible_in_tree(),
		"summary has Retry same seed / New seed / Title buttons")
	var seed_before: int = run.run.seed
	var persisted: Array = save.profile["stats"].get("onboarding_seen",[])
	for id in ["room1","first_reward","first_workshop"]:
		expect(control.guide.seen.count(id)==1 and persisted.count(id)==1,"AD-042 tip seen/persisted once: "+id)
	var fresh = preload("res://ui/onboarding_prompts.gd").new()
	fresh.load_seen(persisted)
	expect(fresh.trigger("room1")=="" and fresh.trigger("first_reward")=="" and fresh.trigger("first_workshop")=="",
		"AD-042 tips not shown again for same profile")
	expect(save.stats()["runs"]==1 and save.stats()["wins"]==1,"AD-019 win recorded once in stats")
	control._redraw_panel()
	expect(save.stats()["runs"]==1,"AD-019 redrawing summary does not double-count")
	control.summary_retry_button.emit_signal("pressed")
	expect(run.room.values["id"]=="s1_r1" and run.run.currency==0 and run.run.seed==seed_before
		and run.state=="fighting","retry same seed fully resets the run with the same seed")
	run.session.sim.actor.receive_damage(100000,"fire",2,100)
	run.step({"cast":0})
	control._redraw_panel()
	texts.clear()
	for item in control.summary_overlay.find_children("*","Label",true,false):
		texts.append(item.text)
	joined = "\n".join(texts)
	expect(run.state=="dead" and joined.contains(control.tr("run.summary.title_lose")) and joined.contains(control.tr("run.summary.defeated")),
		"death opens Run Summary: defeated")
	expect(save.stats()["runs"]==2 and save.stats()["deaths"]==1,"AD-019 death recorded in stats")
	expect(not save.has_run(),"AD-146 death deletes the run save")
	control.summary_new_seed_button.emit_signal("pressed")
	expect(run.run.seed != seed_before and run.room.values["id"]=="s1_r1" and run.run.currency==0
		and run.run.unlocked==run.config["initial_unlocked"],"new seed differs and resets run-local state")
	var runs_before: int = save.stats()["runs"]
	control.open_pause()
	expect(not control.pause_menu.save_quit_button.visible,"AD-146 Save & Quit hidden when pausing in combat")
	control.pause_menu.request_quit()
	expect(control.pause_menu.is_confirm_open(),"AD-068 quit asks for confirmation")
	control.pause_menu.confirm_pending()
	await process_frame
	await process_frame
	expect(current_scene != null and current_scene.scene_file_path=="res://scenes/main.tscn"
		and save.stats()["runs"]==runs_before+1,"AD-068 quit lands on Title and records abandoned run")
	var sources := ""
	for path in ["res://ui/run_controller.gd","res://ui/main_menu.gd","res://ui/run_canvas.gd"]:
		sources += FileAccess.get_file_as_string(path)
	var ctrl_src := FileAccess.get_file_as_string("res://ui/run_controller.gd")
	expect(ctrl_src.contains("flow.resume(") and not sources.contains("recover("),"AD-146 resume goes through flow.resume, never recover")
	expect(current_scene != null and current_scene.scene_file_path=="res://scenes/main.tscn","Title returns to main menu")
	var menu = load("res://scenes/main.tscn").instantiate()
	root.add_child(menu)
	await process_frame
	menu.open_settings()
	var s = menu.settings_screen
	expect(s.volume_sliders["Master"] != null and s.flash_toggle != null and s.shake_toggle != null,"AD-019 menu has settings row")
	s.flash_toggle.set_pressed(true)
	s.shake_toggle.set_pressed(true)
	s.volume_sliders["Master"].value = 0.5
	menu.queue_free()
	await process_frame
	var reborn = preload("res://game/core/save_service.gd").new()
	reborn.set_base_dir("user://ad019_smoke/")
	expect(reborn.settings.reduce_flashes and not reborn.settings.screen_shake
		and is_equal_approx(float(reborn.settings.volumes["Master"]),0.5),"AD-019 settings survive restart")
	expect(FileAccess.file_exists("user://ad019_smoke/settings.cfg") and not FileAccess.file_exists("user://ad019_smoke/settings.cfg.tmp"),
		"AD-019 settings file written atomically")
	expect(reborn.stats()["runs"]==3,"AD-019 stats survive restart")
	reborn.free()
	save.delete_run()
	save.set_base_dir("user://")
	quit(1 if failures>0 else 0)
