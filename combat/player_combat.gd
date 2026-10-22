extends RefCounted
## Deterministic command consumer (TASK-026–027), independent from Godot Input.
var tuning: Dictionary
var sim
var world
var dodge_left := 0
var dodge_cooldown := 0
var recovery_left := 0
var invulnerable_left := 0
var dodge_heading := Vector2.RIGHT
var facing := Vector2.RIGHT
var modal := false
var dodges := 0
var casts := 0
var last_message := ""
var hit_flash := 0

func _init(runtime, geometry, parameters: Dictionary) -> void:
	sim = runtime
	world = geometry
	tuning = parameters.duplicate(true)

func reset() -> void:
	dodge_left = 0
	dodge_cooldown = 0
	recovery_left = 0
	invulnerable_left = 0
	facing = Vector2.RIGHT
	dodge_heading = Vector2.RIGHT
	dodges = 0
	casts = 0
	last_message = ""
	hit_flash = 0
	modal = false

func can_act() -> bool:
	return sim.actor.alive() and not sim.clock.paused and not modal

func invulnerable() -> bool:
	return invulnerable_left > 0 and sim.actor.alive()

func process_command(command: Dictionary) -> Dictionary:
	if not can_act():
		return {"accepted":false,"reason":"CASTER_DEAD" if not sim.actor.alive() else ("PAUSED" if sim.clock.paused else "MODAL_OPEN")}
	var delta: Vector2 = command.get("move",Vector2.ZERO)
	delta = delta.limit_length(1.0)
	var aim: Vector2 = command.get("aim",facing)
	if not aim.is_zero_approx():
		facing = aim.normalized()
	var dodge_request: bool = bool(command.get("dodge",false))
	if dodge_request and dodge_cooldown == 0 and dodge_left == 0 and recovery_left == 0:
		dodge_heading = delta.normalized() if not delta.is_zero_approx() else facing
		dodge_left = int(tuning["dodge_duration_ticks"])
		invulnerable_left = int(tuning["dodge_invulnerable_ticks"])
		dodge_cooldown = int(tuning["dodge_cooldown_ticks"])
		dodges += 1
	var wanted: Vector2 = delta*float(tuning["move_speed"])/float(sim.clock.tick_rate)
	if dodge_left > 0:
		wanted = dodge_heading*float(tuning["dodge_speed"])/float(sim.clock.tick_rate)
	sim.actor.position = world.move_body(sim.actor.position,wanted,sim.actor.radius)
	var cast_slot: int = int(command.get("cast",-1))
	if cast_slot >= 0:
		if dodge_left > 0 or recovery_left > 0:
			last_message = "DODGE_LOCKOUT"
			return {"accepted":false,"reason":last_message}
		var plan = sim.loadout.get_plan(cast_slot)
		if plan == null:
			last_message = "SLOT_EMPTY"
			return {"accepted":false,"reason":last_message}
		var source: Vector2 = sim.actor.position
		var cast_aim := facing
		if str(plan.snapshot()["root"]["manifestation"]["id"]) == "form.burst":
			source = command.get("cursor",sim.actor.position+facing*90)
			if source.distance_to(sim.actor.position) > float(tuning["max_burst_distance"]):
				last_message = "BURST_OUT_OF_RANGE"
				return {"accepted":false,"reason":last_message}
			if not world.clear_sight(sim.actor.position,source):
				last_message = "BURST_OCCLUDED"
				return {"accepted":false,"reason":last_message}
		var result: Dictionary = sim.try_cast(cast_slot,source,cast_aim)
		last_message = "CAST" if result["accepted"] else str(result["reason"])
		if result["accepted"]:
			casts += 1
		return result
	return {"accepted":true,"reason":"MOVE"}

func step_timers() -> void:
	if sim.clock.paused:
		return
	if dodge_left > 0:
		dodge_left -= 1
		if dodge_left == 0:
			recovery_left = int(tuning["dodge_recovery_ticks"])
	elif recovery_left > 0:
		recovery_left -= 1
	dodge_cooldown = maxi(0,dodge_cooldown-1)
	invulnerable_left = maxi(0,invulnerable_left-1)
	hit_flash = maxi(0,hit_flash-1)
