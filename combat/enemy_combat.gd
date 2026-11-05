extends RefCounted
## Shared AI state machine; archetypes differ by data-composed behaviour components
## (tuning["behaviours"], see combat/enemy_behaviours/registry.gd).
const Difficulty = preload("res://game/core/difficulty.gd")
const Behaviours = preload("res://combat/enemy_behaviours/registry.gd")
const AttackIntent = preload("res://combat/attack_intent.gd")
var target
var kind := ""
var tuning: Dictionary
var state := "idle"
var state_tick := 0
var cooldown := 0
var intent
var death_announced := false
var transitions: Array = []
var heading := Vector2.LEFT
var behaviours: Array = []
var ai: Dictionary = {}
var _movers: Array = []
var _attacker = null

func _init(enemy_target, archetype: String, config: Dictionary) -> void:
	target = enemy_target
	kind = archetype
	tuning = config.duplicate(true)
	for key in ["damage"]:
		if tuning.has(key):
			tuning[key] = Difficulty.scale_f(float(tuning[key]),"enemy_damage")
	for key in ["move_speed","projectile_speed"]:
		if tuning.has(key):
			tuning[key] = Difficulty.scale_f(float(tuning[key]),"enemy_speed")
	if tuning.has("telegraph_ticks"):
		tuning["telegraph_ticks"] = Difficulty.scale_i(int(tuning["telegraph_ticks"]),"telegraph_length")
	behaviours = Behaviours.build(tuning.get("behaviours",[]))
	ai = tuning.get("enemy_ai",{})
	for behaviour in behaviours:
		match str(behaviour.get_script().get_script_constant_map().get("ROLE","")):
			"movement":
				_movers.append(behaviour)
			"attack":
				if _attacker == null:
					_attacker = behaviour

func change_state(next: String, tick: int) -> void:
	if state == next:
		return
	transitions.append({"tick":tick,"from":state,"to":next,"enemy_id":target.id})
	state = next
	state_tick = 0

func _move(session, desired: Vector2) -> void:
	if desired.is_zero_approx():
		return
	var speed := float(tuning["move_speed"])
	if target.status.has("chilled",session.sim.clock.tick):
		speed *= float(session.sim.settings["statuses"]["chilled"].get("move_scale",1.0))
	var displacement := desired.normalized()*speed/float(session.sim.clock.tick_rate)
	var before: Vector2 = target.position
	target.position = session.world.move_body(target.position,displacement,target.radius)
	# If a direct approach is blocked, choose a deterministic side to navigate.
	if target.position.distance_squared_to(before) < displacement.length_squared()*float(ai.get("blocked_move_ratio",0.06)):
		for candidate in [desired.rotated(PI/2.0),desired.rotated(-PI/2.0)]:
			var test_point: Vector2 = session.world.move_body(before,candidate.normalized()*displacement.length(),target.radius)
			if test_point.distance_squared_to(before) > 1.0:
				target.position = test_point
				break
	for other in session.enemies:
		if other == self or not other.target.alive():
			continue
		var diff: Vector2 = target.position-other.target.position
		var minimum: float = target.radius+other.target.radius+float(ai.get("separation_padding",2.0))
		if diff.length_squared() < minimum*minimum:
			var apart: Vector2 = diff.normalized() if not diff.is_zero_approx() else Vector2(1 if target.id < other.target.id else -1,0)
			target.position = session.world.move_body(target.position,apart*float(ai.get("separation_push",3.0)),target.radius)

func advance(session) -> void:
	if not target.alive():
		change_state("dead",session.sim.clock.tick)
		if not death_announced:
			death_announced = true
			session.on_enemy_death(self)
			for behaviour in behaviours:
				behaviour.on_death(self,session)
		return
	if session.state != "playing":
		return
	# Frozen: the whole brain is suspended (no movement, state progress, cooldown or windup completion).
	if target.status.has("frozen",session.sim.clock.tick):
		return
	state_tick += 1
	cooldown = maxi(0,cooldown-1)
	var player = session.sim.actor
	if not player.alive():
		return
	var toward: Vector2 = player.position-target.position
	var distance: float = toward.length()
	var sight: bool = session.world.clear_sight(target.position,player.position,8.0)
	var ctx := {"toward":toward,"distance":distance,"sight":sight,"player":player}
	for behaviour in behaviours:
		behaviour.tick(self,session,ctx)
	match state:
		"idle":
			if distance < float(tuning["perception_radius"]):
				change_state("acquire",session.sim.clock.tick)
		"acquire":
			change_state("chase",session.sim.clock.tick)
		"chase":
			var movement := Vector2.ZERO
			for i in _movers.size():
				var step: Vector2 = _movers[i].movement(self,session,ctx)
				movement = step if i == 0 else movement+step
			_move(session,movement)
			if _attacker != null and cooldown == 0 and distance <= float(tuning["attack_range"]) and sight and _attacker.wants_attack(self,session,ctx):
				intent = AttackIntent.new(_attacker.build_attack(self,ctx))
				change_state("windup",session.sim.clock.tick)
		"windup":
			if state_tick >= int(tuning["telegraph_ticks"]):
				_execute_attack(session)
				change_state("recover",session.sim.clock.tick)
		"recover":
			if state_tick >= int(tuning["recovery_ticks"]):
				intent = null
				cooldown = int(tuning["cooldown_ticks"])
				change_state("chase",session.sim.clock.tick)

func _execute_attack(session) -> void:
	if not target.alive() or not session.sim.actor.alive():
		return
	var player = session.sim.actor
	if not session.world.clear_sight(target.position,player.position,8):
		return
	if _attacker != null:
		_attacker.execute_attack(self,session)
