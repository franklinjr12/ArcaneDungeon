extends RefCounted
## AD-235: heal post_boss_heal_pct of max HP after each boss (not mini-bosses), capped at max, toast value from data.
## Discovered by run_tests.gd (run(t)).
const Flow = preload("res://world/run_flow.gd")
const SEED := 20261022

func _kill_all(flow, limit: int = 3000) -> void:
	for i in limit:
		if flow.state != "fighting":
			return
		for enemy in flow.session.enemies:
			if enemy.target.alive():
				enemy.target.receive_damage(100000, "fire", 1, 100)
		flow.step()

func _jump(flow, index: int) -> void:
	flow.run.sequence_index = index
	flow._enter_current()

func _data_pct() -> float:
	var doc: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(Flow.CONFIG_V2))
	return float(doc["post_boss_heal_pct"])

func run(t) -> void:
	var pct := _data_pct()
	t.equal(pct, 0.25, "AD-235 run_v2.json post_boss_heal_pct is 0.25")
	var flow = Flow.new(SEED, Flow.CONFIG_V2)
	t.equal(float(flow.config["post_boss_heal_pct"]), pct, "AD-235 flow reads the value from data")
	var boss_indices: Array = []
	var mini_index := -1
	for i in flow.rooms.size():
		if str(flow.rooms[i].get("type")) == "boss":
			boss_indices.append(i)
		elif mini_index < 0 and flow.rooms[i].has("mini_boss_slot"):
			mini_index = i
	t.equal(boss_indices.size(), 2, "AD-235 v2 sequence has both bosses")
	for index in boss_indices:
		# Heal from a wounded state: hp before/after the kill.
		var wounded = Flow.new(SEED, Flow.CONFIG_V2)
		_jump(wounded, index)
		var health = wounded.session.sim.actor.health
		var max_hp: float = health.maximum
		health.current = max_hp * 0.4
		var before: float = health.current
		_kill_all(wounded)
		t.check(wounded.state in ["cleared","won"], "AD-235 boss %d cleared (final boss wins the run)" % index)
		var expected := minf(max_hp, before + max_hp * pct)
		t.equal(health.current, expected, "AD-235 boss %d heals %.0f%% of max HP" % [index, pct * 100.0])
		t.equal(wounded.run.hp, expected, "AD-235 boss %d run hp carries the heal" % index)
		t.equal(wounded.post_boss_heal, expected - before, "AD-235 boss %d toast amount" % index)
		# Cap at max: a nearly full actor ends exactly at max; the toast reports only what was restored.
		var full = Flow.new(SEED, Flow.CONFIG_V2)
		_jump(full, index)
		health = full.session.sim.actor.health
		max_hp = health.maximum
		health.current = max_hp - 5.0
		_kill_all(full)
		t.equal(health.current, max_hp, "AD-235 boss %d caps at max HP" % index)
		t.equal(full.post_boss_heal, 5.0, "AD-235 boss %d toast reports only the 5 HP restored" % index)
	# Mini-boss kill must not heal.
	if mini_index >= 0:
		var mini = Flow.new(SEED, Flow.CONFIG_V2)
		_jump(mini, mini_index)
		var mhealth = mini.session.sim.actor.health
		mhealth.current = mhealth.maximum * 0.4
		var mbefore: float = mhealth.current
		_kill_all(mini)
		t.equal(mini.state, "cleared", "AD-235 mini-boss room cleared")
		t.equal(mhealth.current, mbefore, "AD-235 mini-boss does not heal")
		t.equal(mini.post_boss_heal, 0.0, "AD-235 mini-boss has no toast amount")
	t.check(mini_index >= 0, "AD-235 v2 sequence has a mini-boss room")
