extends RefCounted
const Baseline = preload("res://tests/m2_baseline_driver.gd")
const Geometry = preload("res://world/arena_geometry.gd")
const Session = preload("res://combat/combat_session.gd")
func run(t) -> void:
	var cases: Dictionary = t.fixture("m2_baseline_v1.json")
	t.equal(cases["schema_version"],1,"TASK-035 explicit versioned combat baseline")
	t.equal(cases["cases"].size(),6,"TASK-035 3 scenarios tested with 2 starter loadouts")
	for sample in cases["cases"]:
		var scenario: String = str(sample["scenario"])
		var loadout: int = int(sample["loadout"])
		var outcome: Dictionary = Baseline.simulate(scenario,loadout)
		for key in ["seed","scenario","loadout","completed","result","ticks","damage_received","casts","dodges","reactions",
			"enemies_remaining","hp_remaining"]:
			t.equal(outcome[key],sample[key],"TASK-035 %s build %d deterministic %s" % [scenario,loadout,key])
		t.check(outcome["completed"],"TASK-035 %s build %d playable without direct HP manipulation" % [scenario,loadout])
		t.check(outcome["ticks"] < 2400,"TASK-035 %s build %d clears within allowed replay" % [scenario,loadout])
		t.check(outcome["avg_sim_fps"] > 60.0,"TASK-035 %s build %d headless simulation above 60 tps" % [scenario,loadout])
	var spell = Session.new(9876,"single",0)
	var enemy = spell.enemies[0]
	enemy.target.position = spell.sim.actor.position+Vector2(280,0)
	spell.player.modal = false
	spell.player.dodge_left = 0
	# Root Burst has finite cast range and respects line of sight in combat.
	var far = spell.issue({"aim":Vector2.RIGHT,"cast":1,"cursor":Vector2(1200,450)})
	t.equal(far["reason"],"BURST_OUT_OF_RANGE","TASK-034 out-of-range Burst provides explicit rejection")
	t.equal(spell.sim.queue.active_effect_count(),0,"TASK-034 invalid Burst has no spawned effects")
	spell.sim.actor.position = Vector2(510,260)
	var obstructed = spell.issue({"aim":Vector2.RIGHT,"cast":1,"cursor":Vector2(730,260)})
	t.equal(obstructed["reason"],"BURST_OCCLUDED","TASK-033 Burst cannot target through wall")
	var projectile = Session.new(122,"single",0)
	projectile.sim.actor.position = Vector2(510,250)
	projectile.enemies[0].target.position = Vector2(745,250)
	var allowed = projectile.issue({"aim":Vector2.RIGHT,"cast":0})
	t.check(allowed["accepted"],"TASK-033 root Projectile launches normally toward wall")
	for i in 90:
		projectile.sim.step()
	t.equal(projectile.enemies[0].target.health.current,float(projectile.enemies[0].tuning["hp"]),
		"TASK-033 player spell projectile cannot tunnel through solid wall")
	var line = projectile.world
	t.check(line.navigate_direction(Vector2(510,250),Vector2(745,250),17).length() > 0.9,
		"TASK-033 deterministic navigation finds direction around obstacle")
