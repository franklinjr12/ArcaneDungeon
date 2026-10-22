extends RefCounted
const Flow = preload("res://world/run_flow.gd")
const Boss = preload("res://combat/boss_combat.gd")
const State = preload("res://world/run_state.gd")
const Session = preload("res://combat/combat_session.gd")
const Driver = preload("res://tests/m3_run_driver.gd")

func run(t) -> void:
	var flow = Flow.new(20261022)
	var native: Dictionary = flow.run.snapshot()
	var text_representation: String = JSON.stringify(native)
	var parsed = JSON.parse_string(text_representation)
	var restored = State.new()
	var valid: Dictionary = restored.restore(parsed,flow.session.sim.registry,flow.config["rooms"].size())
	t.check(valid["ok"],"TASK-039 serialized JSON round trip is accepted")
	if valid["ok"]:
		t.equal(restored.snapshot()["seed"],native["seed"],"TASK-039 seed preserved through JSON")
		t.equal(restored.snapshot()["formulas"],native["formulas"],"TASK-039 formula arrays preserved through JSON")
	var boss_config: Dictionary = flow.config["boss"]
	var scenario = Session.new(1325,"empty",0)
	scenario.defer_clear = true
	var boss = scenario.spawn_boss(boss_config,Vector2(1030,450))
	t.check(boss != null,"TASK-042 boss uses shared M2 target store")
	t.equal(boss.state,"acquire","TASK-042 boss begins in acquire state")
	t.equal(boss.target.health.maximum,float(boss_config["hp"]),"TASK-042 tunable boss HP loaded")
	boss.advance(scenario)
	t.equal(boss.state,"windup","TASK-042 boss radial pattern begins with telegraph")
	t.equal(boss.intent.snapshot()["kind"],"radial","TASK-042 boss first pattern radial")
	t.equal(scenario.enemy_shots.size(),0,"TASK-042 telegraph before radial bullets")
	for tick in int(boss_config["windup_ticks"])-1:
		boss.advance(scenario)
	t.equal(scenario.enemy_shots.size(),0,"TASK-042 no radial bullet during windup")
	boss.advance(scenario)
	t.equal(scenario.enemy_shots.size(),int(boss_config["radial_shots"]),"TASK-042 radial pattern fires only after telegraph")
	t.equal(boss.state,"recover","TASK-042 radial pattern has recovery")
	scenario.enemy_shots.clear()
	for i in int(boss_config["recovery_ticks"]):
		boss.advance(scenario)
	t.equal(boss.state,"windup","TASK-042 next attack starts new windup")
	t.equal(boss.intent.snapshot()["kind"],"targeted","TASK-042 boss alternating targeted pattern")
	for i in int(boss_config["windup_ticks"])-1:
		boss.advance(scenario)
	t.equal(scenario.enemy_shots.size(),0,"TASK-042 targeted shot not launched early")
	boss.advance(scenario)
	t.equal(scenario.enemy_shots.size(),1,"TASK-042 targeted shot launched after windup")
	boss.target.health.current = boss.target.health.maximum*0.45
	boss.advance(scenario)
	t.equal(boss.phase,2,"TASK-042 boss enters second phase below threshold")
	for i in int(boss_config["recovery_ticks"]):
		boss.advance(scenario)
	t.equal(boss.state,"windup","TASK-042 phase 2 starts telegraph")
	t.equal(int(boss.tuning["telegraph_ticks"]),int(boss_config["second_phase_windup_ticks"]),
		"TASK-042 phase 2 telegraph faster but still finite")
	var alone = Session.new(7777,"empty",0)
	alone.defer_clear = true
	var captive = alone.spawn_boss(boss_config,Vector2(1030,450))
	captive.target.receive_damage(9999,"fire",alone.sim.actor.team,100)
	for i in 5:
		alone.step()
	t.equal(alone._death_ids.size(),1,"TASK-042 dead boss emits one and only one death")
	t.check(not captive.target.alive(),"TASK-042 boss susceptible to ordinary elemental attack")
	t.equal(alone.enemy_shots.size(),0,"TASK-042 dead boss cannot continue launching bullets")
	for build in [0,2]:
		var playable = Flow.new(20261022)
		playable.run.sequence_index = 3
		if build == 2:
			playable.run.formulas = [playable.formulas["sample.water_burst"].duplicate(true),
				playable.formulas["sample.lightning_shot"].duplicate(true)]
		var enter: Dictionary = playable._enter_current()
		t.check(enter["ok"],"TASK-042 build %d is valid at boss entrance" % build)
		var result: Dictionary = Driver.fight(playable,5000)
		t.equal(result["state"],"cleared","TASK-042 boss beaten using legal build %d" % build)
		t.equal(playable.boss_defeated_events,1,"TASK-042 boss death emitted once with build %d" % build)

