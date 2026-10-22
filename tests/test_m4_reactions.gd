extends RefCounted
## TASK-050: cross-spell semantics and combat lifecycle regression extensions.
const Runner = preload("res://magic/runtime/spell_runner.gd")
const Target = preload("res://combat/magic_target.gd")
const Status = preload("res://combat/status_component.gd")
const Resolver = preload("res://combat/interaction_resolver.gd")
const Session = preload("res://combat/combat_session.gd")
const Store = preload("res://combat/target_store.gd")
const Flow = preload("res://world/run_flow.gd")

func _samples() -> Dictionary:
	var data: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://magic/data/sandbox_samples_v1.json"))
	var out := {}
	for value in data["formulas"]:
		out[str(value["formula_id"])] = value
	return out

func _payload(essence: String) -> Dictionary:
	return {"team":1,"cast_id":12,"root_cast_id":12,"formula_id":"test",
		"essence_id":essence,"damage":12.0,"caster_id":1}

func run(t) -> void:
	var r = Runner.new(5150)
	var settings: Dictionary = r.settings
	var cases := _samples()
	var burn = Status.new()
	var fire: Dictionary = settings["statuses"]["burning"]
	var wet: Dictionary = settings["statuses"]["wet"]
	t.check(burn.apply("burning",0,fire)["ok"],"TASK-050 burning initially accepted")
	var initial: int = int(burn.snapshot()["burning"]["expires_tick"])
	var due: Array = burn.tick(30,settings["statuses"])
	t.check(due.any(func(e):return e["type"]=="dot"),"TASK-050 Burning DOT fires at fixed period")
	burn.apply("burning",35,fire)
	t.equal(int(burn.snapshot()["burning"]["expires_tick"]),initial+35,"TASK-050 repeated Burning refreshes duration")
	t.equal(burn.tick(initial+35,settings["statuses"])[0]["type"],"expired","TASK-050 no DOT on expiration boundary")
	var water = Status.new()
	water.apply("wet",7,wet)
	t.check(water.has("wet",246),"TASK-050 Wet exists before expiration tick")
	t.check(not water.has("wet",247),"TASK-050 Wet not valid at exact expiry")
	water.tick(247,settings["statuses"])
	t.check(not water.has("wet"),"TASK-050 expired Wet removed from memory")
	var enemy = Target.new(100,2,Vector2(280,340),100)
	var store = Store.new()
	store.add(enemy)
	var resolution = Resolver.new(settings)
	var hit: Dictionary = resolution.resolve(_payload("essence.fire"),enemy,store,0)
	t.check(hit["accepted"] and enemy.status.has("burning"),"TASK-050 Fire applies Burning through shared resolver")
	var drop: Dictionary = resolution.resolve(_payload("essence.water"),enemy,store,10)
	t.check(drop["accepted"],"TASK-050 Water hit accepted")
	t.check(not enemy.status.has("burning"),"TASK-050 Water removes Burning instantly")
	t.check(enemy.status.has("wet"),"TASK-050 Water installs Wet")
	var best_a = Target.new(101,2,Vector2(340,390),100)
	var best_b = Target.new(102,2,Vector2(340,290),100)
	for node in [best_a,best_b]:
		store.add(node)
		node.status.apply("wet",10,wet)
	var arc: Dictionary = resolution.resolve(_payload("essence.lightning"),enemy,store,12)["reaction"]
	t.equal(arc["target_id"],best_a.id,"TASK-050 Wet lightning tie chooses lowest stable target ID")
	t.equal(resolution.resolve_arc(arc,best_a),float(arc["damage"]),"TASK-050 Arc hit uses shared damage")
	t.check(best_a.status.has("wet"),"TASK-050 Arc does not consume Wet")
	store.remove(best_a.id)
	t.equal(resolution.resolve_arc(arc,best_a),0.0,"TASK-050 target removed after scheduling arc receives no damage")
	store.remove(best_b.id)
	t.check(resolution.resolve(_payload("essence.lightning"),enemy,store,14)["reaction"].is_empty(),
		"TASK-050 zero eligible arc targets causes no derived hit")
	var allied = Target.new(103,1,Vector2(260,340),100)
	store.add(allied)
	t.equal(resolution.resolve(_payload("essence.fire"),allied,store,15)["reason"],"INELIGIBLE_TARGET",
		"TASK-050 friendly fire disabled across all elements")
	var resisted = Target.new(104,2,Vector2(320,340),100,18,0,{"lightning":0.5})
	store.add(resisted)
	t.equal(resolution.resolve(_payload("essence.lightning"),resisted,store,15)["damage"],6.0,
		"TASK-050 lightning resistance applies to element attack")
	# Expired Wet must not react on a simultaneous lightning hit, but current Wet does.
	var expired = Target.new(105,2,Vector2(360,340),500)
	var still_wet = Target.new(106,2,Vector2(370,340),500)
	store.add(expired)
	store.add(still_wet)
	expired.status.apply("wet",0,{"duration_ticks":5})
	still_wet.status.apply("wet",0,{"duration_ticks":30})
	t.check(resolution.resolve(_payload("essence.lightning"),expired,store,5)["reaction"].is_empty(),
		"TASK-050 same-tick expiry prevents expired Wet from reacting")
	expired.status.apply("wet",6,{"duration_ticks":30})
	t.equal(resolution.resolve(_payload("essence.lightning"),expired,store,6)["reaction"]["target_id"],still_wet.id,
		"TASK-050 active Wet can react before end-of-tick expiry pass")
	var casualty = Target.new(107,2,Vector2(390,340),1)
	store.add(casualty)
	resolution.resolve(_payload("essence.fire"),casualty,store,8)
	t.check(not casualty.alive(),"TASK-050 lethal Fire hit")
	t.check(casualty.status.snapshot().is_empty(),"TASK-050 death cannot retain new status")
	var replay_signatures: Array = []
	for loop in 2:
		var scenario = Runner.new(7878)
		scenario.equip(0,cases["sample.water_burst"])
		scenario.equip(1,cases["sample.lightning_shot"])
		var one = scenario.add_target(Vector2(335,340),Vector2.ZERO,500)
		var two = scenario.add_target(Vector2(380,340),Vector2.ZERO,500)
		scenario.try_cast(0,Vector2(350,340),Vector2.RIGHT)
		for i in 2:
			scenario.step()
		scenario.try_cast(1,scenario.actor.position,Vector2.RIGHT)
		for i in 40:
			scenario.step()
		replay_signatures.append(scenario.trace_json())
	t.equal(replay_signatures[0],replay_signatures[1],"TASK-050 identical commands/seed yield identical normalized causal traces")
	var boss = Session.new(180,"empty",0)
	boss.defer_clear = true
	var boss_data: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://world/data/vertical_slice_v1.json"))["boss"]
	var target = boss.spawn_boss(boss_data,Vector2(1030,450))
	var hp_before: float = target.target.health.current
	resolution.resolve(_payload("essence.fire"),target.target,boss.sim.targets,0)
	resolution.resolve(_payload("essence.water"),target.target,boss.sim.targets,1)
	resolution.resolve(_payload("essence.lightning"),target.target,boss.sim.targets,2)
	t.check(target.target.health.current<hp_before,"TASK-050 boss has no special elemental immunity in prototype")
	var flow = Flow.new(150)
	var mob = flow.session.enemies[0]
	mob.target.receive_damage(1000,"fire",1,100)
	flow.step()
	t.equal(flow.choose_reward(0)["ok"],true,"TASK-050 one reward after kill")
	t.equal(flow.choose_reward(0)["reason"],"REWARD_NOT_AVAILABLE","TASK-050 repeated death cannot give double reward")
