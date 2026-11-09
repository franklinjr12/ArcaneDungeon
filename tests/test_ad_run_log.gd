extends RefCounted
## AD-183: local per-run JSON log (user:// only, no network) and summary timer.
const Flow = preload("res://world/run_flow.gd")
const Driver = preload("res://tests/m3_run_driver.gd")
const RunLog = preload("res://game/core/run_log.gd")
const BuildInfo = preload("res://game/core/build_info.gd")
const SEED := 20261022
const DIR := "user://ad183_test_runs/"
const OFF_FILE := "user://ad183_demo_off.json"

func _clean() -> void:
	DirAccess.make_dir_recursive_absolute(DIR)
	for f in DirAccess.get_files_at(DIR):
		DirAccess.remove_absolute(DIR + f)

func _jsons() -> Array:
	var out: Array = []
	for f in DirAccess.get_files_at(DIR):
		if f.ends_with(".json"):
			out.append(f)
	out.sort()
	return out

func _read(file: String) -> Dictionary:
	var parsed = JSON.parse_string(FileAccess.get_file_as_string(DIR + file))
	return parsed if parsed is Dictionary else {}

func run(t) -> void:
	_clean()
	RunLog.dir_override = DIR
	RunLog.file_override = ""
	_lost(t)
	_spells(t)
	_won_and_guards(t)
	_toggle(t)
	_resume(t)
	_static_checks(t)
	_clean()
	DirAccess.remove_absolute(OFF_FILE)
	RunLog.dir_override = ""
	RunLog.file_override = ""

func _lost(t) -> void:
	var flow = Flow.new(SEED)
	t.equal(Driver.fight(flow,4600)["state"],"cleared","AD-183 room 1 cleared")
	flow.choose_reward(0)
	Driver.reach_exit(flow)
	var victim = null
	for i in 600:
		for enemy in flow.session.enemies:
			if enemy.target.alive():
				victim = enemy
				break
		if victim != null:
			break
		flow.step({})
	t.check(victim != null,"AD-183 room 2 has a live enemy")
	if victim == null:
		return
	var kind := str(victim.kind)
	flow.session.damage_player(victim.target.id,99999.0,"physical")
	flow.step({})
	t.equal(flow.state,"dead","AD-183 scripted run dies")
	var files := _jsons()
	t.equal(files.size(),1,"AD-183 exactly one log file")
	if files.is_empty():
		return
	var d := _read(files[0])
	t.equal(d.get("build_version"),BuildInfo.version(),"AD-183 build version")
	t.equal(int(d.get("seed",0)),SEED,"AD-183 seed")
	t.equal(d.get("result"),"lost","AD-183 result")
	t.check(not str(d.get("started_at","")).is_empty() and not str(d.get("ended_at","")).is_empty(),"AD-183 start/end times")
	t.check(d.get("death") is Dictionary and d["death"].get("cause") == kind and d["death"].get("room_id") == str(flow.room.values["id"]),"AD-183 death cause and room")
	var rooms: Array = d.get("rooms",[])
	t.equal(rooms.size(),2,"AD-183 two rooms logged")
	if rooms.size() == 2:
		t.check(float(rooms[0]["seconds"]) > 0.0,"AD-183 room 1 seconds")
		t.check(float(rooms[1]["damage_taken"]) > 0.0,"AD-183 room 2 damage")
	var sum := 0
	var deaths: Dictionary = d.get("enemy_deaths",{})
	for k in deaths:
		sum += int(deaths[k])
	t.check(not deaths.is_empty() and sum >= flow.kills,"AD-183 enemy deaths counted")
	t.check(d.get("artifacts") is Array and d.get("spells_crafted") is Array,"AD-183 artifacts and spells arrays")
	t.check(absf(float(d.get("total_seconds",-1.0)) - float(flow.summary()["seconds"])) < 0.001,"AD-183 log and summary timer agree")
	# Double finish writes nothing more.
	t.equal(flow.run_log.finish("lost",[],null),ERR_ALREADY_EXISTS,"AD-183 second finish rejected")
	t.equal(_jsons().size(),1,"AD-183 no extra file after double finish")

func _spells(t) -> void:
	var flow = Flow.new(SEED,Flow.CONFIG_V2)
	t.check(_to_workshop(flow),"AD-183 reached workshop")
	if flow.state != "workshop":
		return
	t.check(flow.open_editor(0)["ok"],"AD-183 editor opens")
	flow.editor.set_root("essence.water","form.projectile")
	t.check(flow.close_editor(true,1.0)["ok"],"AD-183 editor applies")
	var spells: Array = flow.run_log.to_dict()["spells_crafted"]
	t.check(spells.size() >= 1 and str(spells[0]["formula_id"]) != "","AD-183 crafted spell logged")

func _won_and_guards(t) -> void:
	var before := _jsons().size()
	var flow2 = Flow.new(SEED)
	flow2.run.sequence_index = flow2.rooms.size()-1
	flow2._enter_current()
	flow2._finish_combat()
	t.equal(flow2.state,"won","AD-183 final room won")
	var files := _jsons()
	t.equal(files.size(),before+1,"AD-183 win writes a second file")
	var won := 0
	for f in files:
		var d := _read(f)
		if d.get("result") == "won":
			won += 1
			t.check(d.get("death") == null,"AD-183 win has no death")
	t.equal(won,1,"AD-183 one won log")
	RunLog.dir_override = "res://x/"
	var flow3 = Flow.new(SEED)
	t.equal(flow3.run_log.finish("won",[],null),ERR_INVALID_PARAMETER,"AD-183 non user:// dir rejected")
	RunLog.dir_override = DIR

func _toggle(t) -> void:
	var before := _jsons().size()
	var f := FileAccess.open(OFF_FILE,FileAccess.WRITE)
	f.store_string('{"schema_version":1,"run_log_enabled":false}')
	f.close()
	RunLog.file_override = OFF_FILE
	t.check(not RunLog.enabled(),"AD-183 toggle off reads false")
	var flow = Flow.new(SEED)
	t.equal(flow.run_log.finish("lost",[],null),ERR_UNAVAILABLE,"AD-183 disabled finish unavailable")
	t.equal(_jsons().size(),before,"AD-183 disabled writes no file")
	RunLog.file_override = ""
	t.check(RunLog.enabled(),"AD-183 shipped data enables the log")

func _kill_all(flow) -> void:
	for i in 3000:
		if flow.state != "fighting":
			return
		for enemy in flow.session.enemies:
			if enemy.target.alive():
				enemy.target.receive_damage(100000,"fire",1,100)
		flow.step()

func _to_workshop(flow) -> bool:
	for guard in 60:
		if flow.state == "workshop":
			return true
		if flow.state == "fighting":
			_kill_all(flow)
		if flow.state == "cleared" and not flow.reward_collected and flow.room.values["type"] != "boss":
			flow.choose_reward(0)
		if flow.state != "cleared":
			return false
		flow.session.sim.actor.position = flow.room.marker("exit")
		flow.try_exit(flow.room.marker("exit"),false)
	return false

func _resume(t) -> void:
	var flow = Flow.new(SEED,Flow.CONFIG_V2)
	if not _to_workshop(flow):
		t.check(false,"AD-183 resume setup reaches workshop")
		return
	var before: int = flow.run_log.to_dict()["rooms"].size()
	var payload = JSON.parse_string(JSON.stringify(flow.save_payload()))
	var fresh = Flow.new(SEED,Flow.CONFIG_V2)
	t.check(fresh.resume(payload)["ok"],"AD-183 resume ok")
	var d: Dictionary = fresh.run_log.to_dict()
	t.check(d["resumed"] == true and d["rooms"].size() >= before,"AD-183 resume keeps earlier rooms and flags resumed")
	payload.erase("run_log")
	var older = Flow.new(SEED,Flow.CONFIG_V2)
	t.check(older.resume(payload)["ok"] and older.run_log.to_dict()["resumed"] == true,"AD-183 save without run_log still loads")

func _static_checks(t) -> void:
	var ui := FileAccess.get_file_as_string("res://ui/run_controller.gd")
	t.check(ui.contains("run.summary.l_time"),"AD-183 summary timer label wired")
	for name in ["win","lose"]:
		var layout := FileAccess.get_file_as_string("res://assets/ui/layouts/ad_ui_screen_summary_%s_layout.json" % name)
		t.check(layout.contains("st2_l"),"AD-183 %s summary layout has stat rows" % name)
	var src := FileAccess.get_file_as_string("res://game/core/run_log.gd")
	for word in ["HTTPRequest","HTTPClient","StreamPeerTCP","PacketPeerUDP","WebSocket","shell_open"]:
		t.check(not src.contains(word),"AD-183 no network: " + word)
