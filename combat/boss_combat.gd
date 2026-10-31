extends RefCounted
## TASK-042 telegraphed phase boss using the same MagicTarget and hostile projectile pipeline.
const AttackIntent = preload("res://combat/attack_intent.gd")
var target
var kind := "undead_warden"
var tuning: Dictionary
var state := "acquire"
var state_tick := 0
var cycle := 0
var death_announced := false
var transitions: Array = []
var intent
var phase := 1

func _init(target_entity, settings: Dictionary) -> void:
	target = target_entity
	tuning = settings.duplicate(true)
	tuning["color"] = "#e8c38b"
	tuning["attack_range"] = float(settings["telegraph_radius"])
	tuning["telegraph_ticks"] = int(settings["windup_ticks"])

func _state(to: String, tick: int) -> void:
	if state == to:
		return
	transitions.append({"from":state,"to":to,"tick":tick,"enemy_id":target.id})
	state = to
	state_tick = 0

func advance(session) -> void:
	if not target.alive():
		_state("dead",session.sim.clock.tick)
		if not death_announced:
			death_announced = true
			session.on_enemy_death(self)
		return
	if session.state != "playing":
		return
	var hp_fraction: float = target.health.current/target.health.maximum
	if hp_fraction <= float(tuning["phase_threshold"]):
		phase = 2
	state_tick += 1
	match state:
		"acquire":
			_start_windup(session)
		"windup":
			var duration := int(tuning["second_phase_windup_ticks"]) if phase == 2 else int(tuning["windup_ticks"])
			if state_tick >= duration:
				_fire(session)
				_state("recover",session.sim.clock.tick)
		"recover":
			if state_tick >= int(tuning["recovery_ticks"]):
				_start_windup(session)

func _start_windup(session) -> void:
	var attack := "radial" if cycle%2 == 0 else "targeted"
	intent = AttackIntent.new({"kind":attack,"origin":target.position,
		"telegraph_ticks":int(tuning["second_phase_windup_ticks"]) if phase == 2 else int(tuning["windup_ticks"]),
		"range":float(tuning["telegraph_radius"])})
	tuning["telegraph_ticks"] = intent.snapshot()["telegraph_ticks"]
	_state("windup",session.sim.clock.tick)
	session._notify("! BOSS "+attack.to_upper(),target.position)

func _fire(session) -> void:
	if not target.alive() or not session.sim.actor.alive():
		return
	if cycle%2 == 0:
		var number := int(tuning["radial_shots"])
		for index in number:
			var heading := Vector2.RIGHT.rotated(TAU*float(index)/float(number))
			session.spawn_enemy_projectile(target.id,target.position,heading,float(tuning["radial_damage"]),float(tuning["shot_speed"]))
	else:
		var aim: Vector2 = (session.sim.actor.position-target.position).normalized()
		session.spawn_enemy_projectile(target.id,target.position,aim,float(tuning["shot_damage"]),float(tuning["shot_speed"]),float(tuning["shot_spread"]))
	cycle += 1
