extends RefCounted
## TASK-037: pending waves guard against early clear; state has exactly one clear transition.
const Difficulty = preload("res://game/core/difficulty.gd")
const Affixes = preload("res://world/affixes.gd")
const RoomAffixes = preload("res://world/room_affixes.gd")
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
## AD-239: elites get at most one affix; room_index is 1-based within the stage. Defaults keep old callers affix-free.
var room_index := 0
var optional_room := false
var run_seed := 0
## AD-241: room affix runtime (dark/unstable/haunted); "none" rooms leave every hook a no-op.
var room_affix
## AD-242: boss-adjacent event data (events.<id> in run_v2.json); empty = a normal room.
const GATE_FLOOD_TAG := "gate_flood"
var event: Dictionary = {}
var herald_pending := false
## Flood Gate timed mode: the room clears when the timer ends, never on an empty room.
var timed_ticks := 0
var flood_waves := 0

func initialize(template, battle, maximum: int, depth: int = 0, optional: bool = false, seed_value: int = 0, event_data: Dictionary = {}) -> void:
	room_index = depth
	optional_room = optional
	run_seed = seed_value
	room = template
	session = battle
	cap = Difficulty.scale_i(maximum,"spawn_density")
	session.defer_clear = true
	schedule = room.values["waves"].duplicate(true)
	launched.clear()
	clear_emissions = 0
	clear_triggered = false
	cleared_wave_tick = 0
	log.clear()
	started_tick = session.sim.clock.tick
	event = event_data
	var slot = room.values.get("mini_boss_slot")
	herald_pending = event.has("mini_boss") and not slot is Dictionary
	timed_ticks = int(round(float(event.get("duration_seconds",0.0))*float(session.sim.clock.tick_rate)))
	flood_waves = 0
	room_affix = RoomAffixes.new()
	room_affix.setup(room.values)
	session.room_affix = room_affix
	advance()

## AD-241 dark room light radius in world units; 0 = unlimited.
func light_radius() -> float:
	return room_affix.light_radius()

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
		var slot = room.values.get("mini_boss_slot")
		var has_boss: bool = slot is Dictionary and int(slot.get("wave",-1)) == idx
		# AD-242 Herald of the Warden: the event mini-boss joins the room's first launched wave.
		var herald := herald_pending
		if session.alive_enemies() + wave["enemies"].size() + (1 if has_boss or herald else 0) > cap:
			continue
		launched[idx] = now
		var elite := Affixes.elite_slot()
		for i in wave["enemies"].size():
			var spawn: Array = wave["enemies"][i]
			var enemy = session.spawn_enemy(str(spawn[0]),Vector2(float(spawn[1]),float(spawn[2])))
			room_affix.track_spawn(enemy,str(spawn[0]),Vector2(float(spawn[1]),float(spawn[2])))
			if enemy != null and idx == elite[0] and i == elite[1] and room_index > 0:
				var id := Affixes.roll(Affixes.room_seed(run_seed,str(room.values.get("id",""))),room_index,optional_room)
				if id != "":
					Affixes.apply(session,enemy,id)
					log.append({"event":"affix","id":id,"kind":str(spawn[0])})
		log.append({"event":"wave_spawn","index":idx,"tick":now})
		if has_boss:
			var pos: Array = slot["position"]
			if session.spawn_mini_boss(str(slot["id"]),Vector2(float(pos[0]),float(pos[1])),room.values.get("elite",{})) != null:
				log.append({"event":"mini_boss_spawn","id":str(slot["id"]),"tick":now})
		if herald:
			herald_pending = false
			var at: Array = event.get("mini_boss_position",room.values["reward"])
			var id := str(event["mini_boss"])
			var radius := float(session.data.get("mini_bosses",{}).get(id,{}).get("radius",30))
			# The data position may sit in a layout wall: nudge to the nearest open point (deterministic ring search).
			var pos := Vector2(float(at[0]),float(at[1]))
			if not session.world.valid_position(pos,radius):
				pos = RoomAffixes.nearest_open(session.world,Rect2(pos,Vector2.ZERO),pos,radius)
			if session.spawn_mini_boss(id,pos,room.values.get("elite",{})) != null:
				log.append({"event":"mini_boss_spawn","id":id,"tick":now})
	for entry in room_affix.step_haunted(session,now):
		log.append(entry)
	if timed_ticks > 0:
		_step_timed(now)
		return
	# Haunted: a dead wisp owing its respawn holds the clear like an alive enemy.
	if session.alive_enemies() > 0 or room_affix.pending_respawn():
		return
	if launched.size() < schedule.size():
		# Delay the on_clear wave after the previous wave was removed.
		if not clear_triggered:
			clear_triggered = true
			cleared_wave_tick = now
		return
	_clear(now)

func _clear(now: int) -> void:
	clear_emissions += 1
	session.state = "cleared"
	session.clear_tick = session.sim.clock.tick
	log.append({"event":"room_clear","tick":now})

## AD-242 Flood Gate: every wave_interval_seconds another flood_sets rect group rises (tag gate_flood, cumulative);
## at duration_seconds the water drains, leftover enemies are removed (no kill credit) and the room clears once.
func _step_timed(now: int) -> void:
	var interval := maxi(1,int(round(float(event.get("wave_interval_seconds",0.0))*float(session.sim.clock.tick_rate))))
	var sets: Array = event.get("flood_sets",[])
	if now < timed_ticks and not sets.is_empty() and now >= interval*(flood_waves+1):
		if flood_waves < sets.size():
			var entries: Array = []
			for entry in sets[flood_waves]:
				entries.append(entry.merged({"tag":GATE_FLOOD_TAG}))
			if session.water == null:
				session.set_water([])
			session.water.add_entries(entries)
		flood_waves += 1
		log.append({"event":"flood_wave","index":flood_waves,"tick":now})
	if now < timed_ticks:
		return
	if session.water != null:
		session.water.remove_tag(GATE_FLOOD_TAG)
	session.pending_spawns.clear()
	session.enemies = session.enemies.filter(func(enemy): return not enemy.target.alive())
	_clear(now)

## HUD: whole seconds left on the event timer (0 outside a timed event).
func event_seconds_left() -> int:
	if timed_ticks <= 0 or session == null:
		return 0
	var left := maxi(0,timed_ticks-(session.sim.clock.tick-started_tick))
	return int(ceil(float(left)/float(session.sim.clock.tick_rate)))

func is_timed() -> bool:
	return timed_ticks > 0
