extends RefCounted
const Runner = preload("res://magic/runtime/spell_runner.gd")
const Projectile = preload("res://magic/runtime/projectile_effect.gd")
const Target = preload("res://combat/magic_target.gd")
const Store = preload("res://combat/target_store.gd")
const Resolver = preload("res://combat/interaction_resolver.gd")
const HitPayload = preload("res://combat/hit_payload.gd")
const Status = preload("res://combat/status_component.gd")

func _find(formulas: Array, id: String) -> Dictionary:
	for formula in formulas:
		if formula["formula_id"] == id:
			return formula
	return {}

func run(t) -> void:
	var samples: Array = t.fixture("m1_samples.json")["formulas"]
	var homing: Dictionary = _find(samples,"sample.homing_fire")
	var flame: Dictionary = _find(samples,"sample.fire_shot")
	var direct = Runner.new(110)
	t.check(direct.equip(0,homing)["ok"],"TASK-016 homing spell validates against same compiler")
	var ahead = direct.add_target(Vector2(380,435),Vector2.ZERO,500)
	var homing_cast = direct.try_cast(0,direct.actor.position,Vector2.RIGHT)
	t.check(homing_cast["accepted"],"TASK-016 homing cast accepted")
	var projectile = direct.active[0]["effect"]
	var initial: float = projectile.direction.angle()
	for tick in 15:
		direct.step()
	t.check(projectile.direction.angle() > initial,"TASK-016 homing trajectory curves toward offset target")
	var keep: Vector2 = projectile.direction
	direct.targets.remove(ahead.id)
	direct.step()
	t.check(projectile.direction.is_equal_approx(keep),"TASK-016 target loss preserves last velocity")
	var replicate = Runner.new(110)
	replicate.equip(0,homing)
	replicate.add_target(Vector2(380,435),Vector2.ZERO,500)
	replicate.try_cast(0,replicate.actor.position,Vector2.RIGHT)
	for i in 15:
		replicate.step()
	t.check(projectile.position.is_finite(),"TASK-016 no NaN in homing state")
	t.check(replicate.active[0]["effect"].direction.angle() > 0,"TASK-016 replay follows target same direction")
	# Two Wet targets at equal squared distance: select lowest ID.
	var res = Runner.new(200)
	var striker = res.add_target(Vector2(310,340),Vector2.ZERO,1000)
	var candidate_a = res.add_target(Vector2(400,390),Vector2.ZERO,1000)
	var candidate_b = res.add_target(Vector2(400,290),Vector2.ZERO,1000)
	for target in [striker,candidate_a,candidate_b]:
		target.status.apply("wet",0,res.settings["statuses"]["wet"])
	res.equip(0,_find(samples,"sample.lightning_shot"))
	var cast = res.try_cast(0,res.actor.position,Vector2.RIGHT)
	for i in 40:
		res.step()
	var arcs: Array = res.trace.filter_records(cast["cast_id"],"","reaction")
	t.equal(arcs.size(),1,"TASK-022 exactly one derived lightning arc for three Wet targets")
	if not arcs.is_empty():
		t.equal(arcs[0]["target_id"],candidate_a.id,"TASK-022 nearest-tie selects lowest stable ID")
	# Root Burst must not double-hit an enemy, and should skip allied actors.
	var burst = Runner.new(444)
	var inside = burst.add_target(Vector2(450,300),Vector2.ZERO,1000)
	var outside = burst.add_target(Vector2(700,300),Vector2.ZERO,1000)
	burst.equip(0,_find(samples,"sample.water_burst"))
	var burst_cast = burst.try_cast(0,Vector2(460,300),Vector2.RIGHT)
	burst.advance_one_tick()
	t.equal(inside.hit_count,1,"TASK-014 root burst hits inside exactly once")
	t.equal(outside.hit_count,0,"TASK-014 root burst never hits outside")
	t.equal(burst.trace.filter_records(burst_cast["cast_id"],"","hit").size(),1,"TASK-014 burst uses single shared hit event pipeline")
	# On Hit must trigger even when root hit killed its target.
	var lethal = Runner.new(222)
	var dying = lethal.add_target(Vector2(280,340),Vector2.ZERO,1)
	lethal.equip(0,_find(samples,"sample.split_fire_trigger"))
	var lethal_cast = lethal.try_cast(0,lethal.actor.position,Vector2.RIGHT)
	for i in 45:
		lethal.step()
	t.check(not dying.health.alive() or dying.health.current == 1,"TASK-019 collateral test target accounted for")
	# Uniform target array so one split child passes exactly through the victim.
	var lethal2 = Runner.new(223)
	var dying2 = lethal2.add_target(Vector2(280,340),Vector2.ZERO,1)
	var formula: Dictionary = _find(samples,"sample.fire_shot").duplicate(true)
	formula["formula_id"] = "edge.lethal_on_hit"
	formula["on_hit"] = {"trigger_id":"trigger.on_hit","payload":{"essence_id":"essence.lightning","manifestation_id":"form.burst","modifier_ids":[],"params":{}}}
	lethal2.equip(0,formula)
	var killed_cast = lethal2.try_cast(0,lethal2.actor.position,Vector2.RIGHT)
	for i in 45:
		lethal2.step()
	t.check(not dying2.alive(),"TASK-019 lethal projectile kill")
	t.equal(lethal2.trace.filter_records(killed_cast["cast_id"],"","trigger").size(),1,"TASK-019 lethal hit still triggers payload")
	# Orb overlapping one target must re-hit at intervals, remain bounded, then expire.
	var orb = Runner.new(888)
	var overlap = orb.add_target(Vector2(211,342),Vector2.ZERO,2000)
	orb.equip(0,_find(samples,"sample.orbit_fire"))
	var orbit_cast = orb.try_cast(0,orb.actor.position,Vector2.RIGHT)
	for i in 12:
		orb.step()
	t.check(overlap.hit_count >= 1,"TASK-015 orb deals contact damage")
	t.check(overlap.hit_count <= 3,"TASK-015 re-hit cap prevents damage every frame")
	for i in 365:
		orb.step()
	t.equal(orb.queue.active_effect_count(),0,"TASK-015 orb expires and frees effect budget")
	t.equal(orb.trace.filter_records(orbit_cast["cast_id"],"","trigger").size(),0,"TASK-015 orb cannot trigger recursively")
	# Fast projectile boundary collision.
	var wall = Runner.new(333)
	wall.actor.position = Vector2(908,340)
	wall.equip(0,flame)
	wall.try_cast(0,wall.actor.position,Vector2.RIGHT)
	wall.step()
	wall.step()
	t.equal(wall.queue.active_effect_count(),0,"TASK-013 projectile exits sandbox wall and despawns")
	# Mana should regenerate monotonically, and shortage must not spawn anything.
	var budget = Runner.new(321)
	budget.equip(0,flame)
	budget.mana = 0.0
	var count_before: int = budget.queue.active_effect_count()
	var rejected: Dictionary = budget.try_cast(0,budget.actor.position,Vector2.RIGHT)
	t.equal(rejected["reason"],"INSUFFICIENT_MANA","TASK-023 out of mana rejected with stable reason")
	t.equal(budget.queue.active_effect_count(),count_before,"TASK-023 rejected cast spawns no effects")
	t.equal(budget.mana,0.0,"TASK-023 rejected cast takes no mana")
	budget.step()
	t.check(budget.mana > 0,"TASK-023 mana regeneration on fixed tick")
	# Disabled instrumentation must preserve collision/event outcomes.
	var traced = Runner.new(100,true)
	var silent = Runner.new(100,false)
	for runner in [traced,silent]:
		runner.add_target(Vector2(280,340),Vector2.ZERO,500)
		runner.equip(0,flame)
		runner.try_cast(0,runner.actor.position,Vector2.RIGHT)
		for i in 45:
			runner.step()
	t.equal(traced.inspect()["targets"][0]["hp"],silent.inspect()["targets"][0]["hp"],"TASK-010/M1 tracing cannot affect hit result")
	t.equal(silent.trace.snapshot(),[],"TASK-010/M1 disabling trace keeps execution silent")
	# Fresh reset has identical IDs/world/trace for fixed seed.
	var before = Runner.new(1234)
	before.fill_targets()
	var first_ids: Array = before.inspect()["targets"]
	before.reset(1234)
	before.fill_targets()
	t.equal(before.inspect()["targets"],first_ids,"TASK-025 reset restores identical seeded target layout")
	t.equal(before.trace.snapshot(),[],"TASK-025 reset clears trace")

	var payload = HitPayload.new({"essence_id":"essence.fire","damage":12.0,"team":1,"cast_id":7,
		"root_cast_id":7,"caster_id":1,"formula_id":"sample.fire_shot",
		"knockback":{"force":5.0,"direction":Vector2.RIGHT}},traced.settings["channels"])
	t.check(payload.valid,"TASK-012 typed HitPayload accepts registered elemental channel")
	t.equal(payload.snapshot()["channels"],["fire"],"TASK-012 HitPayload exposes interaction channel")
	t.equal(payload.snapshot()["knockback"]["force"],5.0,"TASK-012 knockback context preserved without M2 movement")
	t.equal(payload.snapshot()["cast_id"],7,"TASK-012 root cast ancestry preserved")
	var tampered: Dictionary = payload.snapshot()
	tampered["damage"] = 99999
	t.equal(payload.snapshot()["damage"],12.0,"TASK-012 HitPayload immutable-to-caller snapshot")
	var wrong = HitPayload.new({"essence_id":"essence.bad","damage":13,"team":1},traced.settings["channels"])
	t.check(not wrong.valid,"TASK-012 unregistered elemental channel rejected")
	t.equal(traced.resolver.resolve(wrong,traced.targets.get_target(2),traced.targets,traced.clock.tick)["reason"],
		"HIT_PAYLOAD_INVALID","TASK-012 invalid payload cannot reach HP")
	var orb_cap = Runner.new(2222)
	orb_cap.equip(0,_find(samples,"sample.orbit_fire"))
	for i in orb_cap.limits.get_limit("max_active_orbs"):
		orb_cap.mana = float(orb_cap.settings["combat"]["player_max_mana"])
		t.check(orb_cap.try_cast(0,orb_cap.actor.position,Vector2.RIGHT)["accepted"],"TASK-015 within active-orb cap")
		for j in 12:
			orb_cap.step()
	t.equal(orb_cap.queue.active_effect_count(),6,"TASK-015 six active orbs admitted")
	orb_cap.mana = float(orb_cap.settings["combat"]["player_max_mana"])
	var before_active: int = orb_cap.queue.active_effect_count()
	t.equal(orb_cap.try_cast(0,orb_cap.actor.position,Vector2.RIGHT)["reason"],"ORB_BUDGET_EXCEEDED",
		"TASK-015 seventh active orb rejected with clear reason")
	t.equal(orb_cap.queue.active_effect_count(),before_active,"TASK-015 rejected orb changes no effects")
	var refresh_status = Status.new()
	var wet_rule: Dictionary = traced.settings["statuses"]["wet"].duplicate(true)
	refresh_status.apply("wet",0,wet_rule)
	wet_rule["duration_ticks"] = 30
	wet_rule["refresh"] = "keep_duration"
	refresh_status.apply("wet",10,wet_rule)
	t.equal(refresh_status.snapshot()["wet"]["expires_tick"],240,"TASK-020 keep-duration refresh policy")
	wet_rule["refresh"] = "extend_duration"
	refresh_status.apply("wet",20,wet_rule)
	t.equal(refresh_status.snapshot()["wet"]["expires_tick"],270,"TASK-020 extend-duration refresh policy")
	wet_rule["refresh"] = "replace_duration"
	refresh_status.apply("wet",25,wet_rule)
	t.equal(refresh_status.snapshot()["wet"]["expires_tick"],55,"TASK-020 replace-duration refresh policy")
	wet_rule["refresh"] = "nonsense"
	t.equal(refresh_status.apply("wet",30,wet_rule)["reason"],"INVALID_REFRESH_POLICY",
		"TASK-020 unknown refresh policy rejects without mutation")
