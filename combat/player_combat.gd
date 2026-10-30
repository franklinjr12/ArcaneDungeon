extends RefCounted
## Deterministic command consumer (TASK-026–027), independent from Godot Input.
var tuning: Dictionary
var sim
var world
var dash_left := 0
var dash_cooldown := 0
var recovery_left := 0
var invulnerable_left := 0
var dash_heading := Vector2.RIGHT
var facing := Vector2.RIGHT
var modal := false
var dashes := 0
var casts := 0
var last_message := ""
var hit_flash := 0

func _init(runtime, geometry, parameters: Dictionary) -> void:
	sim = runtime
	world = geometry
	tuning = parameters.duplicate(true)

func reset() -> void:
	dash_left = 0
	dash_cooldown = 0
	recovery_left = 0
	invulnerable_left = 0
	facing = Vector2.RIGHT
	dash_heading = Vector2.RIGHT
	dashes = 0
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
	var dash_request: bool = bool(command.get("dash",false))
	if dash_request and dash_cooldown == 0 and dash_left == 0 and recovery_left == 0:
		dash_heading = delta.normalized() if not delta.is_zero_approx() else facing
		dash_left = int(tuning["dash_duration_ticks"])
		invulnerable_left = int(tuning["dash_invulnerable_ticks"])
		dash_cooldown = int(tuning["dash_cooldown_ticks"])
		dashes += 1
	var wanted: Vector2 = delta*float(tuning["move_speed"])/float(sim.clock.tick_rate)
	if dash_left > 0:
		wanted = dash_heading*float(tuning["dash_speed"])/float(sim.clock.tick_rate)
	sim.actor.position = world.move_body(sim.actor.position,wanted,sim.actor.radius)
	var cast_slot: int = int(command.get("cast",-1))
	if cast_slot >= 0:
		if dash_left > 0 or recovery_left > 0:
			last_message = "DASH_LOCKOUT"
			return {"accepted":false,"reason":last_message}
		var plan = sim.loadout.get_plan(cast_slot)
		if plan == null:
			var empty_result: Dictionary = sim.try_cast(cast_slot,sim.actor.position,facing)
			last_message = str(empty_result["reason"])
			return empty_result
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
	if dash_left > 0:
		dash_left -= 1
		if dash_left == 0:
			recovery_left = int(tuning["dash_recovery_ticks"])
	elif recovery_left > 0:
		recovery_left -= 1
	dash_cooldown = maxi(0,dash_cooldown-1)
	invulnerable_left = maxi(0,invulnerable_left-1)
	hit_flash = maxi(0,hit_flash-1)
