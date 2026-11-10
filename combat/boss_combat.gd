extends RefCounted
## TASK-042 telegraphed phase boss using the same MagicTarget and hostile projectile pipeline.
const Difficulty = preload("res://game/core/difficulty.gd")
const AttackIntent = preload("res://combat/attack_intent.gd")
const Pool = preload("res://combat/boss_moves/boss_pattern_pool.gd")
const Movement = preload("res://combat/boss_moves/boss_movement.gd")
const Hazards = preload("res://combat/boss_moves/boss_hazards.gd")
const Warden = preload("res://combat/boss_moves/warden_patterns.gd")
const Elite = preload("res://combat/boss_moves/elite_patterns.gd")
const Archivist = preload("res://combat/boss_moves/archivist_patterns.gd")
const Lurk = preload("res://combat/enemy_behaviours/water_lurk.gd")
const EnvProps = preload("res://world/env_props.gd")
const FLOOD_TAG := "archivist_flood"
const ARENA_TAG := "boss_arena"
## AD-200: a blink never lands on an anchor within this many px of the boss, so it always really moves.
const BLINK_MIN_MOVE := 8.0
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
## AD-198 arena hazards: created only when a phase has `hazards`.
var _hazards
## AD-198 beats: `staggered` is a sim + presentation flag (+damage window); a roar deferred by a move in progress waits in `_pending_roar`.
var staggered := false
var _pending_roar := false
var _arena_water := false
## AD-199: leap shockwave/burst entries still running (empty unless a leap move has `shockwave`) and ticks since the phase began (timed summon).
var _aftermath: Array = []
var _summon_age := 0
## AD-199: ticks the current stagger lasts (a debris stun can differ from tuning.stagger.ticks) and how many env_props events the boss has read.
var _stagger_ticks := 0
var _env_event_index := 0
## AD-200: index of the float_path waypoint being approached (-1 = not chosen yet) and the beam sweep in progress ({} = none; _beam_dir alternates each cast).
var _waypoint := -1
var _beam: Dictionary = {}
var _beam_dir := 1.0
## AD-201: sim + presentation flag, true while a `wisp_shield` boss owns a live wisp (target.damage_scale is then the shield multiplier).
var shielded := false

## Pool, movement, hazard, transition and stagger issues for a boss settings dictionary (empty = valid).
static func validate(settings: Dictionary) -> Array:
	return Pool.validate(settings)+Movement.validate(settings)+Hazards.validate(settings)+_validate_beats(settings)+Warden.validate(settings)+Elite.validate(settings)+Archivist.validate(settings)

static func _number_from(value, minimum: float) -> bool:
	return (typeof(value) == TYPE_INT or typeof(value) == TYPE_FLOAT) and float(value) >= minimum

## BOSS_TRANSITION_PARAM (roar_ticks >= 1, shallow arena water with [x,y,w,h]) and BOSS_STAGGER_PARAM (ticks >= 1, multiplier > 1).
static func _validate_beats(settings: Dictionary) -> Array:
	var issues: Array = []
	var phases = settings.get("phases",[])
	for p in (phases.size() if typeof(phases) == TYPE_ARRAY else 0):
		if typeof(phases[p]) != TYPE_DICTIONARY or not phases[p].has("transition"):
			continue
		var path := "phases[%d].transition" % p
		var transition = phases[p]["transition"]
		if typeof(transition) != TYPE_DICTIONARY or not _number_from(transition.get("roar_ticks"),1.0):
			issues.append({"code":"BOSS_TRANSITION_PARAM","path":path+".roar_ticks","message":"roar_ticks must be a number >= 1"})
			continue
		var change = transition.get("arena_change",{})
		var water = change.get("water",[]) if typeof(change) == TYPE_DICTIONARY else null
		if typeof(water) != TYPE_ARRAY:
			issues.append({"code":"BOSS_TRANSITION_PARAM","path":path+".arena_change","message":"arena_change.water must be an array"})
			continue
		for w in water.size():
			var entry = water[w]
			var rect = entry.get("rect") if typeof(entry) == TYPE_DICTIONARY else null
			var kind := str(entry.get("kind","")) if typeof(entry) == TYPE_DICTIONARY else ""
			if kind != "shallow" or typeof(rect) != TYPE_ARRAY or rect.size() != 4 or not rect.all(func(v): return _number_from(v,-INF)):
				issues.append({"code":"BOSS_TRANSITION_PARAM","path":"%s.arena_change.water[%d]" % [path,w],"message":"arena water must be shallow with rect [x,y,w,h]"})
		if change.has("props") and not EnvProps.validate(change["props"],EnvProps.load_data().get("kinds",{})).is_empty():
			issues.append({"code":"BOSS_TRANSITION_PARAM","path":path+".arena_change.props","message":"arena_change.props must be valid env prop entries"})
	if settings.has("stagger"):
		var stagger = settings["stagger"]
		if typeof(stagger) != TYPE_DICTIONARY or not _number_from(stagger.get("ticks"),1.0):
			issues.append({"code":"BOSS_STAGGER_PARAM","path":"stagger.ticks","message":"ticks must be a number >= 1"})
		elif not _number_from(stagger.get("damage_taken_multiplier"),0.0) or float(stagger["damage_taken_multiplier"]) <= 1.0:
			issues.append({"code":"BOSS_STAGGER_PARAM","path":"stagger.damage_taken_multiplier","message":"damage_taken_multiplier must be a number > 1"})
	return issues

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
		_enter_hazards()
	tuning["color"] = str(settings.get("color","#e8c38b"))
	tuning["attack_range"] = float(settings["telegraph_radius"])
	tuning["telegraph_ticks"] = int(tuning["windup_ticks"])

## AD-142: per-phase windups and the new damage keys get the same Difficulty scaling and telegraph floor as the 2-phase path.
func _init_phases(elite_damage: float, floor_ticks: int) -> void:
	for key in ["water_bolt_damage","storm_pulse_damage"]:
		if tuning.has(key):
			tuning[key] = Difficulty.scale_f(float(tuning[key])*elite_damage,"enemy_damage")
	for key in ["beam_sweep","electrify"]:
		if tuning.has(key):
			tuning[key]["damage"] = Difficulty.scale_f(float(tuning[key]["damage"])*elite_damage,"enemy_damage")
	for key in ["book_pages","storm_conduct"]:
		if tuning.has(key):
			tuning[key]["damage"] = Difficulty.scale_f(float(tuning[key]["damage"])*elite_damage,"enemy_damage")
	if tuning.has("homing_skull"):
		tuning["homing_skull"]["damage"] = Difficulty.scale_f(float(tuning["homing_skull"]["damage"])*elite_damage,"enemy_damage")
	var warden_attacks: Array = tuning.get("melee",{}).values()
	if tuning.has("spear_line"):
		warden_attacks.append(tuning["spear_line"])
	for attack in warden_attacks:
		attack["damage"] = Difficulty.scale_f(float(attack["damage"])*elite_damage,"enemy_damage")
	for entry in tuning["phases"]:
		entry["windup_ticks"] = maxi(Difficulty.scale_i(int(entry["windup_ticks"]),"telegraph_length"),floor_ticks)
		for pooled in entry.get("pool",[]):
			if not pooled.has("move"):
				continue
			var move: Dictionary = pooled["move"]
			if move.has("damage"):
				move["damage"] = Difficulty.scale_f(float(move["damage"])*elite_damage,"enemy_damage")
			if move.has("shockwave"):
				move["shockwave"]["damage"] = Difficulty.scale_f(float(move["shockwave"]["damage"])*elite_damage,"enemy_damage")
			for key in ["telegraph_ticks","emerge_telegraph_ticks"]:
				if move.has(key):
					move[key] = maxi(Difficulty.scale_i(int(move[key]),"telegraph_length"),floor_ticks)
		for hazard in entry.get("hazards",[]):
			if hazard.has("damage"):
				hazard["damage"] = Difficulty.scale_f(float(hazard["damage"])*elite_damage,"enemy_damage")
			if hazard.has("warn_ticks"):
				hazard["warn_ticks"] = maxi(Difficulty.scale_i(int(hazard["warn_ticks"]),"telegraph_length"),floor_ticks)
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
		if staggered or state == "roar" or _pending_roar or shielded:
			shielded = false
			staggered = false
			_pending_roar = false
			target.damage_scale = 1.0
		if _arena_water:
			_arena_water = false
			if session.water != null:
				session.water.remove_tag(ARENA_TAG)
		_drain_flood(session)
		if _hazards != null:
			_hazards.clear(self,session)
		if tuning.has("spear_line"):
			Warden.cancel_warnings(self,session)
		if not _aftermath.is_empty():
			_aftermath.clear()
			session.remove_hazards_from(target.id,["boss_ring"])
		if tuning.has("beam_sweep") or tuning.has("electrify"):
			Elite.cancel(self,session)
		_state("dead",session.sim.clock.tick)
		if not death_announced:
			death_announced = true
			if tuning.has("electrify") or tuning.has("storm_conduct"):
				session.clear_water_shock()
			if tuning.has("grave_rise") or tuning.has("homing_skull") or tuning.has("decoy") or tuning.has("small_crystals") or tuning.has("book_pages") or tuning.has("wisp_shield"):
				_dismiss_thralls(session)
			session.on_enemy_death(self)
		return
	if session.state != "playing":
		return
	if tuning.has("water_freeze") and session.water != null:
		Elite.freeze_water(self,session)
	var hp_fraction: float = target.health.current/target.health.maximum
	if tuning.has("phases"):
		_update_phase(hp_fraction,session.sim.clock.tick,session)
	elif hp_fraction <= float(tuning["phase_threshold"]):
		phase = 2
	if flood_age >= 0:
		flood_age += 1
		if flood_age >= int(tuning["flood_duration_ticks"]):
			_drain_flood(session)
	state_tick += 1
	if _hazards != null:
		_hazards.advance(self,session)
	Warden.advance(self,session)
	match state:
		"acquire":
			_walk(session)
			_start_windup(session)
		"windup":
			var duration := int(intent.snapshot()["telegraph_ticks"]) if tuning.has("phases") else (int(tuning["second_phase_windup_ticks"]) if phase == 2 else int(tuning["windup_ticks"]))
			if state_tick >= duration:
				_finish_windup(session)
		"casting":
			Elite.casting_tick(self,session)
		"moving":
			_move_tick(session)
		"submerged":
			if state_tick >= int(_move["submerged_ticks"]):
				var exit_pool := Archivist.uses_pools(_move)
				var exit_at: Vector2 = Archivist.exit_point(self,session,_move) if exit_pool else _pick_anchor(session,_move,target.position)
				_open_move_windup(session,"emerge",float(_move["radius"]),int(_move["emerge_telegraph_ticks"]),exit_at,{"pool_ripple":true} if exit_pool else {})
		"roar":
			if state_tick >= int(tuning["phases"][phase-1]["transition"]["roar_ticks"]):
				_end_roar(session)
		"stagger":
			if state_tick >= _stagger_ticks:
				staggered = false
				target.damage_scale = 1.0
				_start_windup(session)
		"recover":
			_walk(session)
			var wait := _combo_gap if not _combo_queue.is_empty() else int(tuning["recovery_ticks"])
			if state_tick >= wait:
				_start_windup(session)
	if tuning.has("wisp_shield"):
		_refresh_shield(session)

## AD-201: once per advance, after the state logic. The shield beats stagger (and the plain 1.0 a finished stagger writes); the roar's 0 stays.
## When the last wisp dies the multiplier returns to the stagger one if staggered, else 1.0.
func _refresh_shield(session) -> void:
	if state == "roar":
		return
	if Archivist.live_wisps(self,session) > 0:
		shielded = true
		target.damage_scale = float(tuning["wisp_shield"]["damage_taken_multiplier"])
	elif shielded:
		shielded = false
		target.damage_scale = float(tuning["stagger"]["damage_taken_multiplier"]) if staggered and tuning.has("stagger") else 1.0

## Continuous phase movement; only called from acquire/recover so a telegraph never moves.
func _walk(session) -> void:
	if tuning.has("phases") and tuning["phases"][phase-1].has("movement"):
		Movement.continuous_step(self,session,tuning["phases"][phase-1]["movement"])

## Starts the current phase's hazard schedule (the controller exists only for bosses that define hazards).
func _enter_hazards() -> void:
	var specs: Array = tuning["phases"][phase-1].get("hazards",[])
	if _hazards == null and specs.is_empty():
		return
	if _hazards == null:
		_hazards = Hazards.new()
	_hazards.enter_phase(specs)

## Boss RNG, seeded lazily from the session seed and boss id; never the shared sim stream.
func rng(session) -> RandomNumberGenerator:
	if _rng == null:
		_rng = RandomNumberGenerator.new()
		_rng.seed = int(session.seed)*31+int(target.id)
	return _rng

func _has_pool() -> bool:
	return tuning.has("phases") and tuning["phases"][phase-1].has("pool")

func _attack() -> String:
	if _has_pool():
		return _windup_attack
	var patterns: Array = tuning["phases"][phase-1]["patterns"] if tuning.has("phases") else tuning["patterns"]
	return str(patterns[cycle%patterns.size()])

## Phase = highest index whose threshold >= hp fraction; it only ever increases and restarts the pattern cycle.
func _update_phase(hp_fraction: float, tick: int, session) -> void:
	var reached := phase
	var phases: Array = tuning["phases"]
	for index in phases.size():
		if hp_fraction <= float(phases[index]["threshold"]):
			reached = maxi(reached,index+1)
	if reached == phase:
		return
	transitions.append({"from":"phase%d" % phase,"to":"phase%d" % reached,"tick":tick,"enemy_id":target.id})
	phase = reached
	_summon_age = 0
	_combo_queue.clear()
	_last_key = ""
	_current_entry = {}
	_pending_roar = false
	if _hazards != null:
		_hazards.clear(self,session)
	if phases[phase-1].has("transition"):
		_roar_or_defer(session)
		return
	if state != "roar":
		_enter_hazards()
	if state == "windup":
		_reset_cycle_after_fire = true
	else:
		cycle = 0

## AD-198: the roar starts now unless the boss is mid-move (moving, submerged, or emerging); then it waits for the move to end.
func _roar_or_defer(session) -> void:
	var emerging: bool = state == "windup" and str(intent.snapshot()["kind"]) == "emerge"
	if state == "moving" or state == "submerged" or emerging or state == "roar":
		_pending_roar = true
	else:
		_begin_roar(session,1)

## `lead` is the ticks of this advance that already counted: the roar spans exactly roar_ticks ticks after the one that began it.
func _begin_roar(session, lead: int) -> void:
	var transition: Dictionary = tuning["phases"][phase-1]["transition"]
	intent = null
	_combo_queue.clear()
	_windup_attack = ""
	_current_entry = {}
	_reset_cycle_after_fire = false
	_pending_roar = false
	cycle = 0
	staggered = false
	target.damage_scale = 0.0
	if _hazards != null:
		_hazards.clear(self,session)
	if tuning.has("spear_line"):
		Warden.cancel_warnings(self,session)
	if tuning.has("beam_sweep") or tuning.has("electrify"):
		Elite.cancel(self,session)
	transitions.append({"from":"phase%d" % phase,"to":"roar","tick":session.sim.clock.tick,"enemy_id":target.id})
	state = "roar"
	state_tick = -lead
	_apply_arena_change(session,transition.get("arena_change",{}))
	Elite.queue_decoy(self,session)
	Elite.queue_crystals(self,session)
	session._notify("! BOSS ROAR",target.position)
	if phase != 2:
		session._event_cue("phase:"+kind,target.position,"sfx.boss.phase")

## AD-199: a debris stun (cracked pillar broken near the boss) cuts the current action and opens the same damage window as a big-move stagger.
func stun(session, ticks: int) -> void:
	intent = null
	_windup_attack = ""
	_combo_queue.clear()
	_current_entry = {}
	Warden.cancel_warnings(self,session)
	if tuning.has("beam_sweep") or tuning.has("electrify"):
		Elite.cancel(self,session)
	staggered = true
	target.damage_scale = float(tuning["stagger"]["damage_taken_multiplier"])
	_stagger_ticks = ticks
	if state == "stagger":
		state_tick = 0
	else:
		_state("stagger",session.sim.clock.tick)
	session._notify("STAGGERED",target.position)

func _apply_arena_change(session, change: Dictionary) -> void:
	if bool(change.get("clear_hazards",false)):
		session.remove_hazards_from(target.id)
		_drain_flood(session)
		if session.water != null:
			session.water.remove_tag(ARENA_TAG)
	if change.has("props"):
		_place_props(session,change["props"])
	var water: Array = change.get("water",[])
	if water.is_empty():
		return
	if session.water == null:
		session.set_water([])
	session.water.remove_tag(ARENA_TAG)
	session.water.add_entries(water.map(func(entry): return {"kind":str(entry["kind"]),"rect":entry["rect"].duplicate(),"tag":ARENA_TAG}))
	_arena_water = true

## AD-199: installs the arena props, then moves the player or the boss out of any new pillar to the nearest open point.
func _place_props(session, props: Array) -> void:
	session.set_env_props(props)
	var anchors: Array = tuning.get("anchors",[])
	for body in [session.sim.actor,target]:
		if not session.world.valid_position(body.position,body.radius):
			body.position = session.world.nearest_open_point(body.position,anchors,body.radius,body.position)

func _end_roar(session) -> void:
	target.damage_scale = 1.0
	if _pending_roar:
		_begin_roar(session,0)
		return
	_enter_hazards()
	_state("acquire",session.sim.clock.tick)

## AD-198: after a finished `big` entry (last combo member, landed leap, finished emerge) the boss is staggered instead of recovering.
func _after_move_or_attack(session) -> void:
	if _pending_roar:
		_begin_roar(session,0)
	elif bool(_current_entry.get("big",false)) and _combo_queue.is_empty() and tuning.has("stagger"):
		staggered = true
		target.damage_scale = float(tuning["stagger"]["damage_taken_multiplier"])
		_stagger_ticks = int(tuning["stagger"]["ticks"])
		_state("stagger",session.sim.clock.tick)
		session._notify("STAGGERED",target.position)
	else:
		_state("recover",session.sim.clock.tick)

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
	var pool: Array = tuning["phases"][phase-1]["pool"]
	var blocked: Array = ["flood"] if flood_age >= 0 else []
	var distance: float = session.sim.actor.position.distance_to(target.position)
	for entry in pool:
		if (entry.has("max_range") and distance > float(entry["max_range"])) or (entry.has("min_range") and distance < float(entry["min_range"])):
			blocked.append(Pool.entry_key(entry))
	_current_entry = Pool.pick(pool,_last_key,blocked,rng(session))
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
	if Warden.handles(tuning,attack):
		_open_windup(session,attack,Warden.windup_fields(self,session,attack))
		return
	if Elite.handles(tuning,attack):
		_open_windup(session,attack,Elite.windup_fields(self,session,attack))
		return
	if Archivist.handles(tuning,attack):
		_open_windup(session,attack,Archivist.windup_fields(self,session,attack))
		return
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
	if tuning.has("decoy"):
		Elite.mirror_windup(self,session,attack,fields)
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
		"blink":
			var away: Array = tuning.get("anchors",[]).filter(func(anchor): return _anchor_vector(anchor).distance_to(target.position) > BLINK_MIN_MOVE)
			var landing: Vector2 = session.world.pick_anchor(away,session.sim.actor.position,target.radius,str(spec.get("anchor_pick","farthest")) == "farthest",target.position)
			_open_move_windup(session,"blink",float(spec["radius"]),int(spec["blink_ticks"]),landing)

static func _anchor_vector(anchor) -> Vector2:
	return anchor if anchor is Vector2 else Vector2(float(anchor[0]),float(anchor[1]))

## Anchor relative to the player (farthest = retreat, nearest = ambush); the boss's own spot when no anchor fits.
func _pick_anchor(session, spec: Dictionary, fallback: Vector2) -> Vector2:
	return session.world.pick_anchor(tuning.get("anchors",[]),session.sim.actor.position,target.radius,str(spec.get("anchor_pick","farthest")) == "farthest",fallback)

func _open_move_windup(session, kind: String, radius: float, ticks: int, landing: Vector2, extra: Dictionary = {}) -> void:
	_move_to = landing
	_windup_attack = kind
	_open_windup(session,kind,{"kind":kind,"origin":target.position,"telegraph_ticks":ticks,"range":radius,"telegraph_shape":"slam","landing":landing}.merged(extra))

func _finish_windup(session) -> void:
	match str(intent.snapshot()["kind"]):
		"leap":
			_state("moving",session.sim.clock.tick)
		"submerge":
			submerged = true
			target.untargetable = true
			_state("submerged",session.sim.clock.tick)
		"blink":
			target.position = _move_to
			_end_move(session)
		"beam_sweep":
			Elite.begin_cast(self,session)
		"emerge":
			target.position = _move_to
			submerged = false
			target.untargetable = false
			if Archivist.finish_emerge(self,session,_move):
				return
			if float(_move.get("damage",0.0)) > 0.0:
				_slam_damage(session)
			_end_move(session)
		_:
			_fire(session)
			_after_move_or_attack(session)

func _slam_damage(session) -> void:
	var player = session.sim.actor
	if player.alive() and _move_to.distance_to(player.position) <= float(_move["radius"])+player.radius:
		session.damage_player(target.id,float(_move["damage"]),str(_move.get("channel","physical")))

func _end_move(session) -> void:
	if _reset_cycle_after_fire:
		_reset_cycle_after_fire = false
		cycle = 0
	_after_move_or_attack(session)

func _move_tick(session) -> void:
	if str(_move["mode"]) == "leap":
		var flight := int(_move["flight_ticks"])
		if state_tick >= flight:
			target.position = _move_to
			_slam_damage(session)
			if _move.has("shockwave"):
				Warden.start_aftermath(self,session,_move)
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
	if Warden.handles(tuning,attack):
		Warden.fire(self,session,attack)
	elif Elite.handles(tuning,attack):
		Elite.fire(self,session,attack,target.position)
	elif Archivist.handles(tuning,attack):
		Archivist.fire(self,session)
	elif attack == "pulse":
		if session.sim.actor.position.distance_to(target.position) <= float(tuning["pulse_radius"]):
			session.damage_player(target.id,float(tuning["pulse_damage"]),"lightning")
	elif attack == "fan" or attack == "water_bolt" or attack == "radial":
		_fire_shots(session,attack,target.position,target.id,1.0)
	elif attack == "wet_zone":
		session.add_hazard({"kind":"puddle","status":"wet","position":intent.snapshot()["target"],
			"radius":float(tuning["wet_zone_radius"]),"duration_ticks":int(tuning["wet_zone_duration_ticks"]),
			"interval_ticks":int(tuning["wet_zone_interval_ticks"]),"source_id":target.id})
	elif attack == "flood":
		_fire_flood(session)
	elif attack == "summon_wisps":
		fire_summon(session,str(tuning.get("wisp_kind","lantern_wisp")),tuning["wisp_offsets"],int(tuning["wisp_cap"]))
	elif attack == "storm_pulse":
		_fire_storm_pulse(session)
	else:
		_fire_shots(session,attack,target.position,target.id,1.0)
	if tuning.has("decoy"):
		_decoy_cast(session,attack)
	if _reset_cycle_after_fire:
		_reset_cycle_after_fire = false
		cycle = 0
	else:
		_last_key = attack
		cycle += 1

## Fan / water bolt / radial / targeted shots from `origin`, owned by `source_id` (the boss, or a decoy copying the cast with `mult` damage).
## AD-200: a finished beam sweep counts as a cast of `attack` (same cycle bookkeeping as _fire), then the usual stagger/recover.
func finish_cast(attack: String, session) -> void:
	if _reset_cycle_after_fire:
		_reset_cycle_after_fire = false
		cycle = 0
	else:
		_last_key = attack
		cycle += 1
	_after_move_or_attack(session)

func _fire_shots(session, attack: String, origin: Vector2, source_id: int, mult: float) -> void:
	var speed := float(tuning["shot_speed"])
	if attack == "fan" or attack == "water_bolt":
		var prefix := "water_bolt_" if attack == "water_bolt" else "fan_"
		var number := int(tuning.get(prefix+"shots",5))
		var arc := deg_to_rad(float(tuning.get(prefix+"arc_degrees",50)))
		var damage := (float(tuning["water_bolt_damage"]) if attack == "water_bolt" else float(tuning["shot_damage"]))*mult
		var centre: Vector2 = (session.sim.actor.position-origin).normalized()
		for index in number:
			var offset := 0.0 if number <= 1 else arc*(float(index)/float(number-1)-0.5)
			session.spawn_enemy_projectile(source_id,origin,centre.rotated(offset),damage,speed)
	elif attack == "radial":
		var number := int(tuning["radial_shots"])
		for index in number:
			var heading := Vector2.RIGHT.rotated(TAU*float(index)/float(number))
			session.spawn_enemy_projectile(source_id,origin,heading,float(tuning["radial_damage"])*mult,speed)
	else:
		var aim: Vector2 = (session.sim.actor.position-origin).normalized()
		session.spawn_enemy_projectile(source_id,origin,aim,float(tuning["shot_damage"])*mult,speed,float(tuning["shot_spread"]))

## AD-200: a live decoy listing `attack` in decoy.copies casts it from its own position; only shot patterns and skulls can be copied.
func _decoy_cast(session, attack: String) -> void:
	var decoy = Elite.copies(self,session,attack)
	if decoy == null:
		return
	decoy.end_windup()
	var mult := float(tuning["decoy"]["damage_multiplier"])
	if Elite.handles(tuning,attack):
		Elite.fire(self,session,attack,decoy.target.position,mult)
	elif ["fan","radial","targeted"].has(attack):
		_fire_shots(session,attack,decoy.target.position,decoy.target.id,mult)

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

## Queues `kind` summons at `offsets` from the boss while live + queued summons stay under `cap`.
## `overrides` {hp, radius} rides on the spawn spec; with it an offset that does not fit falls back to the nearest open point.
func fire_summon(session, kind: String, offsets: Array, cap: int, overrides: Dictionary = {}) -> void:
	var radius := float(overrides.get("radius",session.data["enemies"][kind]["radius"]))
	for offset in offsets:
		if session.summons_owned_by(target.id) >= cap:
			break
		var at: Vector2 = target.position+Vector2(float(offset[0]),float(offset[1]))
		if not overrides.is_empty() and not session.world.valid_position(at,radius):
			at = session.world.nearest_open_point(at,tuning.get("anchors",[]),radius,target.position)
		if session.world.valid_position(at,radius):
			var spec := {"kind":kind,"position":at,"summoner_id":target.id}
			if not overrides.is_empty():
				spec["overrides"] = overrides
			session.pending_spawns.append(spec)

## The boss's thralls fall with it so the room can clear; queued ones are dropped.
func _dismiss_thralls(session) -> void:
	session.pending_spawns = session.pending_spawns.filter(func(spec): return int(spec["summoner_id"]) != target.id)
	for enemy in session.enemies:
		var owner_id = enemy.get("summoner_id")
		if owner_id != null and int(owner_id) == target.id and enemy.target.alive():
			enemy.target.receive_damage(enemy.target.health.current+1.0,"neutral",session.sim.actor.team,1.0)

func _fire_storm_pulse(session) -> void:
	if tuning.has("storm_conduct"):
		Elite.electrify_water(self,session,tuning["storm_conduct"])
	var actor = session.sim.actor
	if target.position.distance_to(actor.position) > float(tuning["storm_pulse_radius"])+actor.radius:
		return
	var result: Dictionary = session.damage_player(target.id,float(tuning["storm_pulse_damage"]),"lightning")
	if result.get("accepted",true) == false:
		return
	var statuses: Dictionary = session.sim.settings["statuses"]
	if statuses.has("charged"):
		actor.status.apply("charged",session.sim.clock.tick,statuses["charged"],{"source_id":target.id})
