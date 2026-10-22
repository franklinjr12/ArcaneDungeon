extends SceneTree
const Flow = preload("res://world/run_flow.gd")
const Driver = preload("res://tests/m3_run_driver.gd")
func _initialize() -> void:
	call_deferred("_run")
func _run() -> void:
	var flow = Flow.new(20261022)
	print("M3_START:",JSON.stringify({"state":flow.state,"room":flow.room.values["id"]}))
	for i in 6:
		if flow.mode != "workshop":
			var result = Driver.fight(flow,4500)
			print("M3_FIGHT:",JSON.stringify({"room":flow.room.values["id"],"result":result,
				"currency":flow.run.currency,"hp":flow.run.hp,"state":flow.state}))
			if flow.state != "cleared":
				print("M3_FAILED_FIGHT:",flow.room.values["id"])
				quit(1)
				return
			if flow.room.values["type"] == "combat" and not flow.reward_options.is_empty():
				var reward = flow.choose_reward(0)
				print("M3_REWARD:",JSON.stringify(reward))
		else:
			print("M3_WORKSHOP:",JSON.stringify({"currency":flow.run.currency,"unlocked":flow.run.unlocked,
				"shop":flow.merchant.stock}))
			var buy = flow.buy(0)
			print("M3_BUY:",JSON.stringify(buy))
			var open = flow.open_editor(0)
			print("M3_EDIT_OPEN:",JSON.stringify(open))
			if open["ok"]:
				flow.editor.set_root("essence.water","form.projectile")
				for id in flow.run.unlocked:
					if str(id).begins_with("mod."):
						flow.editor.toggle_modifier(id)
						break
				print("M3_EDIT_VALID:",JSON.stringify(flow.editor.validate()))
				print("M3_APPLY:",JSON.stringify(flow.close_editor(true,10.0)))
			print("M3_TEST:",JSON.stringify(flow.test_cast(0,Vector2.RIGHT)))
		if i < 5:
			var next: Dictionary = Driver.reach_exit(flow)
			print("M3_EXIT:",JSON.stringify(next))
			if not next["ok"]:
				quit(2)
				return
	print("M3_DONE:",JSON.stringify(flow.snapshot()))
	quit()
