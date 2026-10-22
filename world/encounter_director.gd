extends RefCounted
## TASK-037: pending waves guard against early clear; state has exactly one clear transition.
var room
var session
var schedule: Array = []
var launched: Dictionary = {}
var clear_emissions := 0
var started_tick := 0
var clear_triggered := false
var cleared_wave_tick := 0
var log: Array = []
var cap := 8

func initialize(template, battle, maximum: int) -> void:
	room = template
	session = battle
	cap = maximum
	session.defer_clear = true
	schedule = room.values["waves"].duplicate(true)
	launched.clear()
	clear_emissions = 0
	clear_triggered = false
	cleared_wave_tick = 0
	log.clear()
	started_tick = session.sim.clock.tick
	advance()

func advance() -> void:
	if session.state == "dead" or clear_emissions > 0:
		return
	var now: int = session.sim.clock.tick-started_tick
	for idx in schedule.size():
		if launched.has(idx):
			continue
		var wave: Dictionary = schedule[idx]
		var allowed: bool = (wave["trigger"] == "start" and now >= int(wave["delay_ticks"])) or (
			wave["trigger"] == "on_clear" and clear_triggered and now >= int(wave["delay_ticks"])+cleared_wave_tick)
		if not allowed:
			continue
		if session.alive_enemies() + wave["enemies"].size() > cap:
			continue
		launched[idx] = now
		for spawn in wave["enemies"]:
			session.spawn_enemy(str(spawn[0]),Vector2(float(spawn[1]),float(spawn[2])))
		log.append({"event":"wave_spawn","index":idx,"tick":now})
	if session.alive_enemies() > 0:
		return
	if launched.size() < schedule.size():
		# Delay the on_clear wave after the previous wave was removed.
		if not clear_triggered:
			clear_triggered = true
			cleared_wave_tick = now
		return
	clear_emissions += 1
	session.state = "cleared"
	session.clear_tick = session.sim.clock.tick
	log.append({"event":"room_clear","tick":now})
