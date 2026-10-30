extends SceneTree
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

func _run() -> void:
	var save = _install_save_sandbox()
	var pack = load("res://scenes/run.tscn")
	expect(pack is PackedScene,"M3 scene loadable")
	if not pack is PackedScene:
		quit(1)
		return
	var control = pack.instantiate()
	root.add_child(control)
	current_scene = control
	await process_frame
	expect(control.flow != null and control.flow.initialized,"run model initialized")
	if control.flow == null or not control.flow.initialized:
		quit(1)
		return
	expect(control.guide.message("combat").contains("Lightning"),"M4 onboarding introduces Wet to Lightning")
	expect(control.tip != null and control.tip.text.contains("TIP"),"M4 context tip visible initially")
	control._guide(false)
	expect(control.tip.text.is_empty(),"M4 tips can be dismissed")
	control._guide(true)
	expect(control.tip.text.contains("TIP"),"M4 tips can be reopened")
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
	expect(control.arena_canvas != null and control.arena_canvas.visible,"combat canvas visible")
	expect(control.sidebar != null and control.sidebar.get_child_count()>5,"run sidebar built")
	control._open_editor(1)
	expect(not control.editor_open,"editor cannot open during combat")
	var run = control.flow
	run.session.enemies[0].target.receive_damage(1000,"fire",1,100)
	run.step()
	control._redraw_panel()
	expect(run.state=="cleared","first room advances to clear state")
	expect(control.context.get_child_count()>2,"reward choice panel created")
	control._choose_reward(0)
	expect(run.reward_collected,"reward button grants item")
	expect(str(run.room.values["id"]) in run.run.collected,"collect event recorded")
	control._exit()
	expect(run.room.values["id"]=="s1_r1","far-away exit button cannot skip door")
	run.session.sim.actor.position = run.room.marker("exit")
	control._exit()
	expect(run.room.values["id"]=="s1_r2","exit button from marker traverses to room 2")
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
	expect(run.mode=="workshop" and control.test_canvas.visible,"test canvas enabled in safe workshop")
	expect(not control.arena_canvas.visible,"combat canvas hidden during workshop")
	expect(control.context.get_child_count()>5,"workshop merchant and test tools visible")
	var previews := false
	for label in control.context.find_children("*","Label",true,false):
		if label.text.contains("Affordable") or label.text.contains("Need "):
			previews = true
	expect(previews,"merchant displays effect preview and affordability")
	control._open_editor(1)
	expect(control.editor_open and control.editor_panel.visible,"structured editor panel opens")
	expect(control.editor_controls.find_children("*","OptionButton",true,false).size()>=2,
		"editor has root Essence and Manifestation selectors")
	var old: Dictionary = run.run.formulas[0].duplicate(true)
	run.editor.set_root("essence.water","form.projectile")
	control._editor_rebuild()
	expect(control.editor_preview.text.contains("VALID"),"editor live validation shows valid draft")
	control._close_editor(false)
	expect(not control.editor_open and run.run.formulas[0]==old,"editor cancel restores original")
	control._open_editor(1)
	run.editor.set_root("essence.water","form.projectile")
	control._editor_rebuild()
	control._close_editor(true)
	expect(run.run.formulas[0]["formula_id"]=="custom.slot_1","editor apply persists formula")
	expect(run.range_sim.loadout.preview(1)["formula_id"]=="custom.slot_1",
		"test range refreshes after apply")
	control._open_editor(0)
	expect(not control.editor_open,"slot 1 cannot be edited")
	expect(control.loadout_slot_buttons[0].disabled and control.loadout_slot_buttons[0].text.contains("LOCKED"),
		"slot 1 button locked")
	control._open_editor(3)
	expect(control.editor_open and control.editor_preview.text.contains("VALID") and control.editor_preview.text.contains("Cooldown") and control.editor_preview.text.contains("cap"),
		"slot 4 opens with cap-aware preview")
	run.editor.set_root("essence.fire","form.projectile")
	run.editor.toggle_modifier("mod.pierce")
	control._editor_rebuild()
	var apply_disabled := false
	for b in control.editor_controls.find_children("*","Button",true,false):
		if b.text.begins_with("Apply"):
			apply_disabled = b.disabled
	expect(control.editor_preview.text.contains("INVALID") and control.editor_preview.text.contains("RUNE_LOCKED") and apply_disabled,
		"invalid formula shows reason, Apply disabled")
	control._close_editor(true)
	expect(control.editor_open and run.run.formulas.size()==2,"invalid formula cannot be equipped")
	run.editor.toggle_modifier("mod.pierce")
	run.editor.set_root("essence.lightning","form.projectile")
	control._editor_rebuild()
	control._close_editor(true)
	expect(run.run.formulas.size()==3 and run.range_sim.loadout.preview(3)["formula_id"]=="custom.slot_3",
		"valid slot 4 applied")
	var cast4: Dictionary = control._test_cast_slot(3,run.range_sim.actor.position+Vector2(200,0))
	expect(cast4.get("accepted",false),"slot 4 casts in range")
	control._reset_test_range()
	expect(run.range_sim.active.size()==0,"reset range clears spells")
	control._test_click(run.range_sim.actor.position+Vector2(200,0),MOUSE_BUTTON_LEFT)
	expect(run.range_sim.active.size()>0,"workshop test click spawns compiled spell")
	control._redraw_panel()
	expect(control.info.text.contains("Triggers"),"testing HUD contains trigger/reaction/status feedback")
	run.session.sim.actor.position = run.room.marker("exit")
	control._exit()
	expect(run.room.values["id"]=="s2_r1","workshop exit leads into next stage")
	for enemy in run.session.enemies:
		enemy.target.receive_damage(10000,"fire",1,100)
	run.step()
	control._redraw_panel()
	expect(run.state=="won","clearing the first stage-2 room wins the slice")
	var texts: Array = []
	for item in control.context.find_children("*","Label",true,false):
		texts.append(item.text)
	var joined := "\n".join(texts)
	expect(joined.contains("RUN SUMMARY") and joined.contains("VICTORY"),"win opens Run Summary: victory")
	expect(joined.contains("Kills") and joined.contains("Spells used"),"summary shows kills and spells used")
	expect(control.summary_retry_button != null and control.summary_retry_button.is_visible_in_tree()
		and control.summary_new_seed_button != null and control.summary_new_seed_button.is_visible_in_tree()
		and control.summary_title_button != null and control.summary_title_button.is_visible_in_tree(),
		"summary has Retry same seed / New seed / Title buttons")
	var seed_before: int = run.run.seed
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
	for item in control.context.find_children("*","Label",true,false):
		texts.append(item.text)
	joined = "\n".join(texts)
	expect(run.state=="dead" and joined.contains("RUN SUMMARY") and joined.contains("DEFEATED"),
		"death opens Run Summary: defeated")
	expect(save.stats()["runs"]==2 and save.stats()["deaths"]==1,"AD-019 death recorded in stats")
	control.summary_new_seed_button.emit_signal("pressed")
	expect(run.run.seed != seed_before and run.room.values["id"]=="s1_r1" and run.run.currency==0
		and run.run.unlocked==run.config["initial_unlocked"],"new seed differs and resets run-local state")
	var sources := ""
	for path in ["res://ui/run_controller.gd","res://ui/main_menu.gd","res://ui/run_canvas.gd"]:
		sources += FileAccess.get_file_as_string(path)
	expect(not sources.contains("recover(") and not sources.contains(".restore("),"no UI path loads a saved run")
	var menu_src := FileAccess.get_file_as_string("res://ui/main_menu.gd")
	expect(not menu_src.contains("Continue") and not menu_src.contains("Resume"),"main menu has no Continue/Resume")
	control._to_title()
	await process_frame
	await process_frame
	expect(current_scene != null and current_scene.scene_file_path=="res://scenes/main.tscn","Title returns to main menu")
	var menu = load("res://scenes/main.tscn").instantiate()
	root.add_child(menu)
	await process_frame
	expect(menu.volume_slider != null and menu.flash_toggle != null and menu.shake_toggle != null,"AD-019 menu has settings row")
	menu.flash_toggle.set_pressed(true)
	menu.shake_toggle.set_pressed(false)
	menu.volume_slider.value = 0.5
	menu.queue_free()
	await process_frame
	var reborn = preload("res://game/core/save_service.gd").new()
	reborn.set_base_dir("user://ad019_smoke/")
	expect(reborn.settings.reduce_flashes and not reborn.settings.screen_shake
		and is_equal_approx(float(reborn.settings.volumes["Master"]),0.5),"AD-019 settings survive restart")
	expect(FileAccess.file_exists("user://ad019_smoke/settings.cfg") and not FileAccess.file_exists("user://ad019_smoke/settings.cfg.tmp"),
		"AD-019 settings file written atomically")
	expect(reborn.stats()["runs"]==2,"AD-019 stats survive restart")
	reborn.free()
	save.set_base_dir("user://")
	quit(1 if failures>0 else 0)
