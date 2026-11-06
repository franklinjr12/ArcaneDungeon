extends RefCounted
## AD-146 step 1: workshop-only run save (SaveService run.json) and RunFlow.resume.
const Service = preload("res://game/core/save_service.gd")
const Flow = preload("res://world/run_flow.gd")
const SEED := 20261022
const DIR := "user://ad146_test/"

func _clean() -> void:
	DirAccess.make_dir_recursive_absolute(DIR)
	for f in DirAccess.get_files_at(DIR):
		DirAccess.remove_absolute(DIR + f)

func run(t) -> void:
	_clean()
	_gating(t)
	_roundtrip(t)
	_files(t)
	_clean()

func _kill_all(flow) -> void:
	for i in 3000:
		if flow.state != "fighting":
			return
		for enemy in flow.session.enemies:
			if enemy.target.alive():
				enemy.target.receive_damage(100000,"fire",1,100)
		flow.step()

## Plays the seeded v2 route until the workshop; returns once state == "workshop".
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

func _gating(t) -> void:
	var flow = Flow.new(SEED,Flow.CONFIG_V2)
	t.check(flow.state == "fighting" and not flow.can_save() and flow.save_payload().is_empty(),"AD-146 no save while fighting")
	_kill_all(flow)
	t.check(flow.state == "cleared" and not flow.can_save() and flow.save_payload().is_empty(),"AD-146 no save in a cleared combat room")
	var fresh = Flow.new(SEED,Flow.CONFIG_V2)
	if fresh.prelude_available():
		t.check(fresh.enter_prelude()["ok"] and fresh.prelude and not fresh.can_save() and fresh.save_payload().is_empty(),"AD-146 no save during the prelude")

func _roundtrip(t) -> void:
	var flow = Flow.new(SEED,Flow.CONFIG_V2)
	t.check(_to_workshop(flow),"AD-146 reached the workshop")
	if flow.state != "workshop":
		return
	flow.run.currency += 500
	var bought := false
	for i in flow.merchant.stock.size():
		if flow.buy(i)["ok"]:
			bought = true
			break
	t.check(bought,"AD-146 bought a workshop item")
	t.check(flow.reroll()["ok"],"AD-146 rerolled the merchant stock")
	t.check(flow.can_save(),"AD-146 workshop can save")
	var payload: Dictionary = flow.save_payload()
	var svc = Service.new()
	svc.set_base_dir(DIR)
	t.equal(svc.save_run(payload),OK,"AD-146 run saved")
	t.check(svc.has_run(),"AD-146 has_run after save")
	var snap: Dictionary = flow.snapshot()
	var run_snap: Dictionary = flow.run.snapshot()
	var stock: Array = flow.merchant.stock.duplicate(true)
	var bought_map: Dictionary = flow.merchant.bought.duplicate(true)
	var summary: Dictionary = flow.summary()
	var found: Dictionary = flow.discoveries()
	var hp: float = flow.run.hp
	var arcs: int = flow.arc_total()
	svc.free()
	flow = null
	var svc2 = Service.new()
	svc2.set_base_dir(DIR)
	var flow2 = Flow.new(-1,Flow.CONFIG_V2)
	var r: Dictionary = flow2.resume(svc2.load_run())
	t.check(r.get("ok",false),"AD-146 resume ok: "+str(r))
	t.equal(flow2.snapshot(),snap,"AD-146 snapshot restored exactly")
	t.equal(flow2.run.snapshot(),run_snap,"AD-146 run state restored exactly")
	t.equal(flow2.merchant.stock,stock,"AD-146 merchant stock restored")
	t.equal(flow2.merchant.bought,bought_map,"AD-146 merchant bought restored")
	t.equal(flow2.summary(),summary,"AD-146 summary restored")
	t.equal(flow2.discoveries(),found,"AD-146 discoveries restored")
	t.equal(flow2.arc_total(),arcs,"AD-146 arcs restored")
	t.check(flow2.state == "workshop" and flow2.session.sim.actor.health.current == hp,"AD-146 resumed in the workshop with saved hp")

	# (c) combat index rejected, nothing changed.
	var bad: Dictionary = svc2.load_run()
	bad["run"]["sequence_index"] = 0
	var flow3 = Flow.new(-1,Flow.CONFIG_V2)
	var before: Dictionary = flow3.snapshot()
	var rej: Dictionary = flow3.resume(bad)
	t.check(not rej["ok"] and rej["reason"] == "RUN_SAVE_NOT_WORKSHOP" and flow3.snapshot() == before,"AD-146 combat index rejected, run untouched")
	# (e) config mismatch.
	var other = Flow.new(-1,Flow.CONFIG)
	var mm: Dictionary = other.resume(svc2.load_run())
	t.check(not mm["ok"] and mm["reason"] == "RUN_SAVE_CONFIG_MISMATCH","AD-146 config mismatch rejected")
	var neg: Dictionary = svc2.load_run()
	neg["counters"]["kills"] = -1
	t.check(not Flow.new(-1,Flow.CONFIG_V2).resume(neg)["ok"],"AD-146 negative counter rejected")
	var badstock: Dictionary = svc2.load_run()
	badstock["merchant_stock"] = [{"kind":"rune","rune_id":"nope","price":1,"id":"x"}]
	t.check(not Flow.new(-1,Flow.CONFIG_V2).resume(badstock)["ok"],"AD-146 bad stock rejected")
	t.check(not Flow.new(-1,Flow.CONFIG_V2).resume("junk")["ok"],"AD-146 non-dictionary rejected")
	svc2.free()

func _files(t) -> void:
	_clean()
	var f := FileAccess.open(DIR + "run.json",FileAccess.WRITE)
	f.store_string("{not json")
	f.close()
	var svc = Service.new()
	svc.set_base_dir(DIR)
	t.check(svc.has_run() and svc.load_run().is_empty() and not svc.has_run(),"AD-146 corrupt run.json loads empty and is quarantined")
	var quarantined := false
	for name in DirAccess.get_files_at(DIR):
		quarantined = quarantined or name.begins_with("run.json.corrupt-")
	t.check(quarantined,"AD-146 corrupt run kept as run.json.corrupt-*")
	t.equal(svc.save_run({"version":1}),OK,"AD-146 save_run writes")
	svc.delete_run()
	t.check(not svc.has_run() and not FileAccess.file_exists(DIR + "run.json.tmp"),"AD-146 delete_run removes the file")
	svc.free()
