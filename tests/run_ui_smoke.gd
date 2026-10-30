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

func _run() -> void:
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
	control._open_editor(0)
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
	control._open_editor(0)
	expect(control.editor_open and control.editor_panel.visible,"structured editor panel opens")
	expect(control.editor_controls.find_children("*","OptionButton",true,false).size()>=2,
		"editor has root Essence and Manifestation selectors")
	var old: Dictionary = run.run.formulas[0].duplicate(true)
	run.editor.set_root("essence.water","form.projectile")
	control._editor_rebuild()
	expect(control.editor_preview.text.contains("VALID"),"editor live validation shows valid draft")
	control._close_editor(false)
	expect(not control.editor_open and run.run.formulas[0]==old,"editor cancel restores original")
	control._open_editor(0)
	run.editor.set_root("essence.water","form.projectile")
	control._editor_rebuild()
	control._close_editor(true)
	expect(run.run.formulas[0]["formula_id"]=="custom.slot_1","editor apply persists formula")
	expect(run.range_sim.loadout.preview(1)["formula_id"]=="custom.slot_1",
		"test range refreshes after apply")
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
	var endcard := false
	for item in control.context.find_children("*","Label",true,false):
		if item.text.contains("VERTICAL SLICE COMPLETE"):
			endcard = true
	expect(endcard,"clearing final room displays completion and replay action")
	control._restart()
	expect(run.room.values["id"]=="s1_r1" and run.run.currency==0,
		"restart action clears all run progression")
	quit(1 if failures>0 else 0)
