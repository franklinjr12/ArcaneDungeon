extends RefCounted
## TASK-042 telegraphed phase boss using the same MagicTarget and hostile projectile pipeline.
const Difficulty = preload("res://game/core/difficulty.gd")
const AttackIntent = preload("res://combat/attack_intent.gd")
const Pool = preload("res://combat/boss_moves/boss_pattern_pool.gd")
const Movement = preload("res://combat/boss_moves/boss_movement.gd")
const Lurk = preload("res://combat/enemy_behaviours/water_lurk.gd")
const FLOOD_TAG := "archivist_flood"
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
## AD-142: attack chosen when the current windup started; flood bookkeeping for the optional `phases` path.
var _windup_attack := ""
var _reset_cycle_after_fire := false
var flood_count := 0
var flood_age := -1
## AD-198: opt-in weighted pool state. Own RNG (seeded lazily) so the shared sim stream is never consumed.
var _rng: RandomNumberGenerator
var _last_key := ""
var _combo_queue: Array = []
var _combo_gap := 0
var _current_entry: Dictionary = {}
## AD-198 movement: `submerged` is a sim + presentation flag (the renderer hides the boss); the rest is the move in progress.
var submerged := false
var strafe_flipped := false
var _move: Dictionary = {}
var _move_from := Vector2.ZERO
var _move_to := Vector2.ZERO

## Pool and movement issues for a boss settings dictionary (empty = valid).
static func validate(settings: Dictionary) -> Array:
	return Pool.validate(settings)+Movement.validate(settings)

func _init(target_entity, settings: Dictionary) -> void:
	target = target_entity
	tuning = settings.duplicate(true)
	kind = str(settings.get("kind","undead_warden"))
	var elite_damage := float(settings.get("elite_damage_multiplier",1.0))
	for key in ["radial_damage","shot_damage","pulse_damage"]:
		if tuning.has(key):
			tuning[key] = Difficulty.scale_f(float(tuning[key])*elite_damage,"enemy_damage")
	if tuning.has("shot_speed"):
		tuning["shot_speed"] = Difficulty.scale_f(float(tuning["shot_speed"]),"enemy_speed")
	for key in ["windup_ticks","second_phase_windup_ticks"]:
		if tuning.has(key):
			tuning[key] = Difficulty.scale_i(int(tuning[key]),"telegraph_length")
	var floor_ticks := int(tuning.get("min_telegraph_ticks",0))
	for key in ["windup_ticks","second_phase_windup_ticks"]:
		if tuning.has(key):
			tuning[key] = maxi(int(tuning[key]),floor_ticks)
	if not tuning.has("patterns"):
		tuning["patterns"] = ["radial","targeted"]
	if settings.has("phases"):
		_init_phases(elite_damage,floor_ticks)
	tuning["color"] = str(settings.get("color","#e8c38b"))
	tuning["attack_range"] = float(settings["telegraph_radius"])
	tuning["telegraph_ticks"] = int(tuning["windup_ticks"])

## AD-142: per-phase windups and the new damage keys get the same Difficulty scaling and telegraph floor as the 2-phase path.
func _init_phases(elite_damage: float, floor_ticks: int) -> void:
	for key in ["water_bolt_damage","storm_pulse_damage"]:
		if tuning.has(key):
			tuning[key] = Difficulty.scale_f(float(tuning[key])*elite_damage,"enemy_damage")
	for entry in tuning["phases"]:
		entry["windup_ticks"] = maxi(Difficulty.scale_i(int(entry["windup_ticks"]),"telegraph_length"),floor_ticks)
		for pooled in entry.get("pool",[]):
			if not pooled.has("move"):
				continue
			var move: Dictionary = pooled["move"]
			if move.has("damage"):
				move["damage"] = Difficulty.scale_f(float(move["damage"])*elite_damage,"enemy_damage")
			for key in ["telegraph_ticks","emerge_telegraph_ticks"]:
				if move.has(key):
					move[key] = maxi(Difficulty.scale_i(int(move[key]),"telegraph_length"),floor_ticks)
	tuning["windup_ticks"] = int(tuning["phases"][0]["windup_ticks"])
	tuning["patterns"] = tuning["phases"][0].get("patterns",[])

func _state(to: String, tick: int) -> void:
	if state == to:
		return
	transitions.append({"from":state,"to":to,"tick":tick,"enemy_id":target.id})
	state = to
	state_tick = 0

func advance(session) -> void:
	if not target.alive():
		submerged = false
		target.untargetable = false
		_drain_flood(session)
		_state("dead",session.sim.clock.tick)
		if not death_announced:
			death_announced = true
			session.on_enemy_death(self)
		return
	if session.state != "playing":
		return
	var hp_fraction: float = target.health.current/target.health.maximum
	if tuning.has("phases"):
		_update_phase(hp_fraction,session.sim.clock.tick)
	elif hp_fraction <= float(tuning["phase_threshold"]):
		phase = 2
	if flood_age >= 0:
		flood_age += 1
		if flood_age >= int(tuning["flood_duration_ticks"]):
			_drain_flood(session)
	state_tick += 1
	match state:
		"acquire":
			_walk(session)
			_start_windup(session)
		"windup":
			var duration := int(intent.snapshot()["telegraph_ticks"]) if tuning.has("phases") else (int(tuning["second_phase_windup_ticks"]) if phase == 2 else int(tuning["windup_ticks"]))
			if state_tick >= duration:
				_finish_windup(session)
		"moving":
			_move_tick(session)
		"submerged":
			if state_tick >= int(_move["submerged_ticks"]):
				_open_move_windup(session,"emerge",float(_move["radius"]),int(_move["emerge_telegraph_ticks"]),_pick_anchor(session,_move,target.position))
		"recover":
			_walk(session)
			var wait := _combo_gap if not _combo_queue.is_empty() else int(tuning["recovery_ticks"])
			if state_tick >= wait:
				_start_windup(session)

## Continuous phase movement; only called from acquire/recover so a telegraph never moves.
func _walk(session) -> void:
	if tuning.has("phases") and tuning["phases"][phase-1].has("movement"):
		Movement.continuous_step(self,session,tuning["phases"][phase-1]["movement"])

func _has_pool() -> bool:
	return tuning.has("phases") and tuning["phases"][phase-1].has("pool")

func _attack() -> String:
	if _has_pool():
		return _windup_attack
	var patterns: Array = tuning["phases"][phase-1]["patterns"] if tuning.has("phases") else tuning["patterns"]
	return str(patterns[cycle%patterns.size()])

## Phase = highest index whose threshold >= hp fraction; it only ever increases and restarts the pattern cycle.
func _update_phase(hp_fraction: float, tick: int) -> void:
	var reached := phase
	var phases: Array = tuning["phases"]
	for index in phases.size():
		if hp_fraction <= float(phases[index]["threshold"]):
			reached = maxi(reached,index+1)
	if reached == phase:
		return
	transitions.append({"from":"phase%d" % phase,"to":"phase%d" % reached,"tick":tick,"enemy_id":target.id})
	phase = reached
	_combo_queue.clear()
	_last_key = ""
	_current_entry = {}
	if state == "windup":
		_reset_cycle_after_fire = true
	else:
		cycle = 0

func _range_key(attack: String) -> String:
	match attack:
		"pulse":
			return "pulse_radius"
		"wet_zone":
			return "wet_zone_radius"
		"storm_pulse":
			return "storm_pulse_radius"
	return "telegraph_radius"

## Next pattern for a pool phase: the queued combo member, else a fresh weighted pick (flood is blocked while flooded).
func _pool_attack(session) -> String:
	if not _combo_queue.is_empty():
		return str(_combo_queue.pop_front())
	if _rng == null:
		_rng = RandomNumberGenerator.new()
		_rng.seed = int(session.seed)*31+int(target.id)
	_current_entry = Pool.pick(tuning["phases"][phase-1]["pool"],_last_key,["flood"] if flood_age >= 0 else [],_rng)
	if _current_entry.has("move"):
		return Pool.entry_key(_current_entry)
	if not _current_entry.has("combo"):
		return str(_current_entry.get("pattern",""))
	var combo: Array = _current_entry["combo"].duplicate()
	var first := str(combo.pop_front())
	_combo_queue = combo
	_combo_gap = int(_current_entry.get("gap_ticks",12))
	return first

func _start_windup(session) -> void:
	var attack := ""
	if _has_pool():
		attack = _pool_attack(session)
	else:
		attack = _attack()
		if attack == "flood" and flood_age >= 0:
			cycle += 1
			attack = _attack()
	if attack.begins_with("move:"):
		_start_move(session,_current_entry["move"])
		return
	_windup_attack = attack
	var ticks := int(tuning["phases"][phase-1]["windup_ticks"]) if tuning.has("phases") else (int(tuning["second_phase_windup_ticks"]) if phase == 2 else int(tuning["windup_ticks"]))
	var fields := {"kind":attack,"origin":target.position,"telegraph_ticks":ticks,"range":float(tuning[_range_key(attack)])}
	if attack == "wet_zone":
		fields["target"] = session.sim.actor.position
	elif attack == "flood":
		fields["rects"] = _flood_entries().map(func(entry): return entry["rect"])
	_open_windup(session,attack,fields)

func _open_windup(session, attack: String, fields: Dictionary) -> void:
	intent = AttackIntent.new(fields)
	tuning["telegraph_ticks"] = intent.snapshot()["telegraph_ticks"]
	tuning["attack_range"] = float(fields["range"])
	_state("windup",session.sim.clock.tick)
	session._notify("! BOSS "+attack.to_upper(),target.position)

## AD-198: a discrete move counts as one no-repeat step. Reposition has no telegraph; leap and submerge reuse a slam windup.
func _start_move(session, spec: Dictionary) -> void:
	_move = spec
	_last_key = "move:%s" % str(spec["mode"])
	_move_from = target.position
	match str(spec["mode"]):
		"reposition":
			_move_to = _pick_anchor(session,spec,target.position)
			_state("moving",session.sim.clock.tick)
		"leap":
			var landing: Vector2
			if str(spec.get("target","player")) == "anchor":
				landing = _pick_anchor(session,spec,target.position)
			else:
				landing = session.world.nearest_open_point(session.sim.actor.position,tuning.get("anchors",[]),target.radius,target.position)
			_move_to = landing
			_open_move_windup(session,"leap",float(spec["radius"]),int(spec["telegraph_ticks"]),landing)
		"submerge":
			_open_move_windup(session,"submerge",float(spec["radius"]),int(spec["telegraph_ticks"]),target.position)

## Anchor relative to the player (farthest = retreat, nearest = ambush); the boss's own spot when no anchor fits.
func _pick_anchor(session, spec: Dictionary, fallback: Vector2) -> Vector2:
	return session.world.pick_anchor(tuning.get("anchors",[]),session.sim.actor.position,target.radius,str(spec.get("anchor_pick","farthest")) == "farthest",fallback)

func _open_move_windup(session, kind: String, radius: float, ticks: int, landing: Vector2) -> void:
	_move_to = landing
	_windup_attack = kind
	_open_windup(session,kind,{"kind":kind,"origin":target.position,"telegraph_ticks":ticks,"range":radius,"telegraph_shape":"slam","landing":landing})

func _finish_windup(session) -> void:
	match str(intent.snapshot()["kind"]):
		"leap":
			_state("moving",session.sim.clock.tick)
		"submerge":
			submerged = true
			target.untargetable = true
			_state("submerged",session.sim.clock.tick)
		"emerge":
			target.position = _move_to
			submerged = false
			target.untargetable = false
			if float(_move.get("damage",0.0)) > 0.0:
				_slam_damage(session)
			_end_move(session)
		_:
			_fire(session)
			_state("recover",session.sim.clock.tick)

func _slam_damage(session) -> void:
	var player = session.sim.actor
	if player.alive() and _move_to.distance_to(player.position) <= float(_move["radius"])+player.radius:
		session.damage_player(target.id,float(_move["damage"]),str(_move.get("channel","physical")))

func _end_move(session) -> void:
	if _reset_cycle_after_fire:
		_reset_cycle_after_fire = false
		cycle = 0
	_state("recover",session.sim.clock.tick)

func _move_tick(session) -> void:
	if str(_move["mode"]) == "leap":
		var flight := int(_move["flight_ticks"])
		if state_tick >= flight:
			target.position = _move_to
			_slam_damage(session)
			_end_move(session)
		else:
			target.position = Lurk.step_free(session,target.position,(_move_to-_move_from)/float(flight),target.radius)
		return
	var gap: Vector2 = _move_to-target.position
	if gap.length() <= 6.0 or state_tick >= int(_move["max_ticks"]):
		_end_move(session)
		return
	var step := float(_move["speed"])/float(session.sim.clock.tick_rate)
	target.position = session.world.move_body(target.position,session.world.navigate_direction(target.position,_move_to,target.radius)*minf(step,gap.length()),target.radius)

func _flood_entries() -> Array:
	var sets: Array = tuning["flood_sets"]
	return sets[flood_count%sets.size()]

func _drain_flood(session) -> void:
	if flood_age < 0:
		return
	flood_age = -1
	if session.water != null:
		session.water.remove_tag(FLOOD_TAG)

func _fire(session) -> void:
	if not target.alive() or not session.sim.actor.alive():
		return
	var attack := _windup_attack
	if attack == "pulse":
		if session.sim.actor.position.distance_to(target.position) <= float(tuning["pulse_radius"]):
			session.damage_player(target.id,float(tuning["pulse_damage"]),"lightning")
	elif attack == "fan" or attack == "water_bolt":
		var prefix := "water_bolt_" if attack == "water_bolt" else "fan_"
		var number := int(tuning.get(prefix+"shots",5))
		var arc := deg_to_rad(float(tuning.get(prefix+"arc_degrees",50)))
		var damage := float(tuning["water_bolt_damage"]) if attack == "water_bolt" else float(tuning["shot_damage"])
		var centre: Vector2 = (session.sim.actor.position-target.position).normalized()
		for index in number:
			var offset := 0.0 if number <= 1 else arc*(float(index)/float(number-1)-0.5)
			session.spawn_enemy_projectile(target.id,target.position,centre.rotated(offset),damage,float(tuning["shot_speed"]))
	elif attack == "radial":
		var number := int(tuning["radial_shots"])
		for index in number:
			var heading := Vector2.RIGHT.rotated(TAU*float(index)/float(number))
			session.spawn_enemy_projectile(target.id,target.position,heading,float(tuning["radial_damage"]),float(tuning["shot_speed"]))
	elif attack == "wet_zone":
		session.add_hazard({"kind":"puddle","status":"wet","position":intent.snapshot()["target"],
			"radius":float(tuning["wet_zone_radius"]),"duration_ticks":int(tuning["wet_zone_duration_ticks"]),
			"interval_ticks":int(tuning["wet_zone_interval_ticks"]),"source_id":target.id})
	elif attack == "flood":
		_fire_flood(session)
	elif attack == "summon_wisps":
		_fire_summon(session)
	elif attack == "storm_pulse":
		_fire_storm_pulse(session)
	else:
		var aim: Vector2 = (session.sim.actor.position-target.position).normalized()
		session.spawn_enemy_projectile(target.id,target.position,aim,float(tuning["shot_damage"]),float(tuning["shot_speed"]),float(tuning["shot_spread"]))
	if _reset_cycle_after_fire:
		_reset_cycle_after_fire = false
		cycle = 0
	else:
		_last_key = attack
		cycle += 1

func _fire_flood(session) -> void:
	if flood_age >= 0:
		return
	var entries: Array = []
	for entry in _flood_entries():
		entries.append(entry.merged({"tag":FLOOD_TAG}))
	flood_count += 1
	if session.water == null:
		session.set_water([])
	session.water.add_entries(entries)
	flood_age = 0

func _fire_summon(session) -> void:
	var kind := str(tuning.get("wisp_kind","lantern_wisp"))
	var radius := float(session.data["enemies"][kind]["radius"])
	for offset in tuning["wisp_offsets"]:
		if session.summons_owned_by(target.id) >= int(tuning["wisp_cap"]):
			break
		var at: Vector2 = target.position+Vector2(float(offset[0]),float(offset[1]))
		if session.world.valid_position(at,radius):
			session.pending_spawns.append({"kind":kind,"position":at,"summoner_id":target.id})

func _fire_storm_pulse(session) -> void:
	var actor = session.sim.actor
	if target.position.distance_to(actor.position) > float(tuning["storm_pulse_radius"])+actor.radius:
		return
	var result: Dictionary = session.damage_player(target.id,float(tuning["storm_pulse_damage"]),"lightning")
	if result.get("accepted",true) == false:
		return
	var statuses: Dictionary = session.sim.settings["statuses"]
	if statuses.has("charged"):
		actor.status.apply("charged",session.sim.clock.tick,statuses["charged"],{"source_id":target.id})
