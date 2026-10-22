extends RefCounted
## Shared AI state machine; archetypes differ by tunable navigation and attacks.
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

func _init(enemy_target, archetype: String, config: Dictionary) -> void:
	target = enemy_target
	kind = archetype
	tuning = config.duplicate(true)

func change_state(next: String, tick: int) -> void:
	if state == next:
		return
	transitions.append({"tick":tick,"from":state,"to":next,"enemy_id":target.id})
	state = next
	state_tick = 0

func _move(session, desired: Vector2) -> void:
	if desired.is_zero_approx():
		return
	var displacement := desired.normalized()*float(tuning["move_speed"])/float(session.sim.clock.tick_rate)
	var before: Vector2 = target.position
	target.position = session.world.move_body(target.position,displacement,target.radius)
	# If a direct approach is blocked, choose a deterministic side to navigate.
	if target.position.distance_squared_to(before) < displacement.length_squared()*0.06:
		for candidate in [desired.rotated(PI/2.0),desired.rotated(-PI/2.0)]:
			var test_point: Vector2 = session.world.move_body(before,candidate.normalized()*displacement.length(),target.radius)
			if test_point.distance_squared_to(before) > 1.0:
				target.position = test_point
				break
	for other in session.enemies:
		if other == self or not other.target.alive():
			continue
		var diff: Vector2 = target.position-other.target.position
		var minimum: float = target.radius+other.target.radius+2.0
		if diff.length_squared() < minimum*minimum:
			var apart: Vector2 = diff.normalized() if not diff.is_zero_approx() else Vector2(1 if target.id < other.target.id else -1,0)
			target.position = session.world.move_body(target.position,apart*3.0,target.radius)

func advance(session) -> void:
	if not target.alive():
		change_state("dead",session.sim.clock.tick)
		if not death_announced:
			death_announced = true
			session.on_enemy_death(self)
		return
	if session.state != "playing":
		return
	state_tick += 1
	cooldown = maxi(0,cooldown-1)
	var player = session.sim.actor
	if not player.alive():
		return
	var toward: Vector2 = player.position-target.position
	var distance: float = toward.length()
	var sight: bool = session.world.clear_sight(target.position,player.position,8.0)
	match state:
		"idle":
			if distance < float(tuning["perception_radius"]):
				change_state("acquire",session.sim.clock.tick)
		"acquire":
			change_state("chase",session.sim.clock.tick)
		"chase":
			var preferred: float = float(tuning["preferred_range"])
			var movement := Vector2.ZERO
			if kind == "pursuer":
				if distance > preferred:
					movement = session.world.navigate_direction(target.position,player.position,target.radius)
			elif kind == "ranged":
				if distance > preferred+45.0 or not sight:
					movement = session.world.navigate_direction(target.position,player.position,target.radius)
				elif distance < preferred-60.0:
					movement = -toward.normalized()
			else:
				# Flanker orbits with bounded lateral steering and no teleporting.
				var sign_side := 1.0 if target.id % 2 == 0 else -1.0
				movement = toward.normalized().rotated(sign_side*PI/2.0)*float(tuning["strafe_factor"])
				if distance > preferred+35.0:
					movement += session.world.navigate_direction(target.position,player.position,target.radius)*0.75
				elif distance < preferred-50.0:
					movement -= toward.normalized()*0.75
			_move(session,movement)
			if cooldown == 0 and distance <= float(tuning["attack_range"]) and sight:
				var attack := {"source_id":target.id,"kind":kind,"geometry":str(tuning["attack_kind"]),
					"origin":target.position,"direction":toward.normalized(),"range":float(tuning["attack_range"]),
					"telegraph_ticks":int(tuning["telegraph_ticks"]),"damage":float(tuning["damage"])}
				intent = AttackIntent.new(attack)
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
	var direction: Vector2 = (player.position-target.position).normalized()
	if kind == "pursuer":
		if target.position.distance_to(player.position) <= float(tuning["attack_range"])+player.radius:
			session.damage_player(target.id,float(tuning["damage"]),"physical")
	else:
		session.spawn_enemy_projectile(target.id,target.position,direction,float(tuning["damage"]),
			float(tuning["projectile_speed"]),float(tuning.get("spread_degrees",0)))
