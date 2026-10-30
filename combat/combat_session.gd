extends RefCounted
## M2 combat orchestration: reuses M1 SpellRunner and common MagicTarget/Health.
const Runner = preload("res://magic/runtime/spell_runner.gd")
const Geometry = preload("res://world/arena_geometry.gd")
const Player = preload("res://combat/player_combat.gd")
const Enemy = preload("res://combat/enemy_combat.gd")
const Boss = preload("res://combat/boss_combat.gd")
const DamageEvent = preload("res://combat/damage_event.gd")
const Projectile = preload("res://magic/runtime/projectile_effect.gd")
const TUNING_FILE := "res://combat/combat_tuning_v1.json"
const SAMPLES_FILE := "res://magic/data/sandbox_samples_v1.json"
var data: Dictionary = {}
var samples: Dictionary = {}
var sim
var world
var player
var enemies: Array = []
var enemy_shots: Array = []
var feedback: Array = []
var damage_events: Array = []
var ai_transitions: Array = []
var _attack_ids: Dictionary = {}
var _death_ids: Dictionary = {}
var seed := 5160
var scenario := "single"
var loadout_index := 0
var state := "playing"
var defer_clear := false
var clear_tick := -1
var attacks_received := 0
var damage_received := 0.0
var reactions := 0
var elapsed_frame_ms := 0.0
var initialized := false
var debug_overlay := false
var reduce_flashes := false
## AD-020: output-only audio sink (Callable(cue_id, position)); never read back by the simulation.
var audio_sink: Callable
var _audio_hits := 0
var _audio_reactions := 0
var _audio_extinguish := 0
var _audio_dashes := 0
var _audio_dead := false
const NON_CAST_REJECTIONS := ["DASH_LOCKOUT","CASTER_DEAD","PAUSED","MODAL_OPEN"]

func _init(run_seed: int = 5160, scenario_id: String = "single", starter_index: int = 0) -> void:
	var parsed = JSON.parse_string(FileAccess.get_file_as_string(TUNING_FILE))
	var spells = JSON.parse_string(FileAccess.get_file_as_string(SAMPLES_FILE))
	if typeof(parsed) != TYPE_DICTIONARY or typeof(spells) != TYPE_DICTIONARY:
		return
	data = parsed
	for formula in spells["formulas"]:
		samples[str(formula["formula_id"])] = formula
	initialized = true
	restart(run_seed,scenario_id,starter_index)

func restart(run_seed: int = -1, scenario_id: String = "", starter_index: int = -1) -> void:
	if not initialized:
		return
	if run_seed >= 0:
		seed = run_seed
	if not scenario_id.is_empty():
		scenario = scenario_id
	if starter_index >= 0:
		loadout_index = starter_index
	if not data["scenarios"].has(scenario):
		scenario = "single"
	loadout_index = posmod(loadout_index,data["starter_loadouts"].size())
	sim = Runner.new(seed)
	world = Geometry.new(data["arena"])
	sim.bounds = world.bounds
	sim.collision_walls = world.walls.duplicate()
	sim.actor.health.maximum = float(data["player"]["max_hp"])
	sim.actor.health.reset()
	sim.actor.radius = float(data["player"]["radius"])
	sim.actor.position = Vector2(float(data["arena"]["player_spawn"][0]),float(data["arena"]["player_spawn"][1]))
	player = Player.new(sim,world,data["player"])
	enemies.clear()
	enemy_shots.clear()
	feedback.clear()
	damage_events.clear()
	ai_transitions.clear()
	_attack_ids.clear()
	_death_ids.clear()
	_audio_hits = 0
	_audio_reactions = 0
	_audio_extinguish = 0
	_audio_dashes = 0
	_audio_dead = false
	state = "playing"
	defer_clear = false
	clear_tick = -1
	attacks_received = 0
	damage_received = 0.0
	reactions = 0
	elapsed_frame_ms = 0.0
	var starter: Array = data["starter_loadouts"][loadout_index]
	sim.equip_starter_loadout([samples[str(starter[0])],samples[str(starter[1])]])
	sim.loadout.allow_edit = false
	for spec in data["scenarios"][scenario]["enemies"]:
		spawn_enemy(str(spec[0]),Vector2(float(spec[1]),float(spec[2])))

func spawn_enemy(kind: String, at: Vector2):
	if not data["enemies"].has(kind) or not world.valid_position(at,float(data["enemies"][kind]["radius"])):
		return null
	var p: Dictionary = data["enemies"][kind]
	var target = sim.add_target(at,Vector2.ZERO,float(p["hp"]))
	target.radius = float(p["radius"])
	target.tags = ["enemy",kind]
	var enemy = Enemy.new(target,kind,p)
	enemies.append(enemy)
	return enemy

func spawn_boss(settings: Dictionary, at: Vector2):
	if not world.valid_position(at,float(settings["radius"])):
		return null
	var target = sim.add_target(at,Vector2.ZERO,float(settings["hp"]))
	target.radius = float(settings["radius"])
	target.tags = ["enemy","boss","undead_warden"]
	var boss = Boss.new(target,settings)
	enemies.append(boss)
	return boss

func issue(command: Dictionary) -> Dictionary:
	if state != "playing":
		return {"accepted":false,"reason":"COMBAT_ENDED"}
	var slot: int = int(command.get("cast",-1))
	var essence := "neutral"
	if slot >= 0:
		var plan = sim.loadout.get_plan(slot)
		if plan != null:
			essence = str(plan.snapshot()["root"]["essence"]["id"]).trim_prefix("essence.")
	var result: Dictionary = player.process_command(command)
	if audio_sink.is_valid():
		if player.dashes > _audio_dashes:
			_cue("sfx.dash",sim.actor.position)
		if slot >= 0:
			if bool(result.get("accepted",false)):
				_cue("sfx.cast." + (essence if essence in ["fire","water","lightning"] else "neutral"),sim.actor.position)
			elif str(result.get("reason","")) not in NON_CAST_REJECTIONS:
				_cue("sfx.cast.rejected",sim.actor.position)
	_audio_dashes = player.dashes
	return result

## AD-020: read-only audio sink call; silent when no sink is attached.
func _cue(id: String, at = null) -> void:
	if audio_sink.is_valid():
		audio_sink.call(id,at)

func step() -> void:
	if state != "playing" or sim.clock.paused:
		return
	var start_usec: int = Time.get_ticks_usec()
	player.step_timers()
	sim.step()
	# AI progresses once after all player spells for the tick.
	var audio_before: Array = []
	if audio_sink.is_valid():
		for enemy in enemies:
			audio_before.append([enemy.state,int(enemy.get("phase")) if enemy.get("phase") != null else 1])
	for enemy in enemies:
		enemy.advance(self)
	if audio_sink.is_valid():
		_audio_step(audio_before)
	advance_enemy_projectiles()
	if not sim.actor.alive() and state == "playing":
		state = "dead"
		if not _audio_dead:
			_audio_dead = true
			_cue("sfx.player.death",sim.actor.position)
		_notify("DEFEAT - R to retry",sim.actor.position)
		# Input commands are rejected once state becomes dead.
		# Active effects are cleared on explicit retry, never survive restart.
	if state == "playing" and not defer_clear and alive_enemies() == 0:
		state = "cleared"
		clear_tick = sim.clock.tick
		_notify("ARENA CLEARED - 1/2/3 next, R replay",sim.actor.position)
	var new_reactions: int = sim.trace.filter_records(-1,"","reaction").size()
	if new_reactions > reactions:
		_notify("ARC x%d" % [new_reactions-reactions],sim.actor.position)
		reactions = new_reactions
	var age: int = sim.clock.tick-68
	feedback = feedback.filter(func(v): return int(v["tick"]) >= age)
	elapsed_frame_ms = float(Time.get_ticks_usec()-start_usec)/1000.0

## AD-020: derive audio cues from this tick's trace/AI changes. Reads only; mutates audio cursors.
func _audio_step(before: Array) -> void:
	var hits: int = sim.trace.filter_records(-1,"","hit").size()
	if hits > _audio_hits:
		_cue("sfx.hit.generic",sim.actor.position)
	_audio_hits = hits
	var arcs: int = sim.trace.filter_records(-1,"","reaction").size()
	if arcs > _audio_reactions:
		_cue("sfx.react.arc",sim.actor.position)
	_audio_reactions = arcs
	var removed := 0
	for entry in sim.trace.filter_records(-1,"","status"):
		if str(entry.get("reason","")) == "burning:removed":
			removed += 1
	if removed > _audio_extinguish:
		_cue("sfx.react.extinguish",sim.actor.position)
	_audio_extinguish = removed
	for index in enemies.size():
		var enemy = enemies[index]
		var at: Vector2 = enemy.target.position
		if enemy.state == "windup" and before[index][0] != "windup":
			if "boss" in enemy.target.tags:
				_cue("sfx.boss.tele_a" if int(enemy.cycle)%2 == 0 else "sfx.boss.tele_b",at)
			else:
				_cue("sfx.tele." + enemy.kind,at)
		if enemy.get("phase") != null and int(enemy.get("phase")) == 2 and int(before[index][1]) == 1:
			_cue("sfx.boss.phase",at)

func alive_enemies() -> int:
	var count := 0
	for enemy in enemies:
		if enemy.target.alive():
			count += 1
	return count

func damage_player(source_id: int, amount: float, channel: String, attack_id: int = -1) -> Dictionary:
	if state != "playing" or not sim.actor.alive():
		return {"accepted":false,"reason":"DEAD"}
	var source = sim.targets.get_target(source_id)
	if source == null or not source.alive() or source.team == sim.actor.team:
		return {"accepted":false,"reason":"SOURCE_INVALID"}
	if attack_id < 0:
		attack_id = sim.clock.next_id("attack")
	if _attack_ids.has(attack_id):
		return {"accepted":false,"reason":"ALREADY_APPLIED"}
	_attack_ids[attack_id] = true
	if player.invulnerable():
		_cue("sfx.dash.iframe",sim.actor.position)
		_notify("DASH_EVADE",sim.actor.position)
		return {"accepted":false,"reason":"INVULNERABLE"}
	var event = DamageEvent.new(source_id,source.team,sim.actor.id,amount,channel,attack_id,sim.clock.tick)
	var dealt: float = sim.actor.receive_damage(amount,channel,source.team,float(sim.settings["combat"]["armor_scale"]))
	if dealt > 0:
		damage_received += dealt
		attacks_received += 1
		player.hit_flash = int(data["player"]["hit_flash_ticks"])
		_cue("sfx.player.hurt",sim.actor.position)
		damage_events.append(event.snapshot().merged({"dealt":dealt,"tick":sim.clock.tick}))
		_notify("-%d HP" % roundi(dealt),sim.actor.position)
	return {"accepted":dealt>0,"damage":dealt,"reason":"HIT" if dealt>0 else "BLOCKED"}

func on_enemy_death(enemy) -> void:
	if _death_ids.has(enemy.target.id):
		return
	_death_ids[enemy.target.id] = true
	enemy.target.status.clear()
	if "boss" in enemy.target.tags:
		_cue("sfx.boss.death",enemy.target.position)
	ai_transitions.append_array(enemy.transitions.duplicate(true))
	_notify("%s DOWN" % enemy.kind.to_upper(),enemy.target.position)

func spawn_enemy_projectile(source_id: int, origin: Vector2, direction: Vector2, amount: float, speed: float, spread: float = 0.0) -> void:
	if state != "playing" or direction.is_zero_approx():
		return
	var source = sim.targets.get_target(source_id)
	if source == null or not source.alive():
		return
	var heading: Vector2 = direction.rotated(deg_to_rad(spread)).normalized()
	enemy_shots.append({"id":sim.clock.next_id("enemy_shot"),"attack_id":sim.clock.next_id("attack"),"source_id":source_id,
		"position":origin+heading*(source.radius+12),"direction":heading,"speed":speed,
		"damage":amount,"age":0,"radius":float(data["enemy_projectile"]["radius"])})
	_notify("! SHOT",origin)

func advance_enemy_projectiles() -> void:
	for projectile in enemy_shots.duplicate():
		var source = sim.targets.get_target(int(projectile["source_id"]))
		if source == null or not source.alive():
			enemy_shots.erase(projectile)
			continue
		projectile["age"] += 1
		if projectile["age"] > int(data["enemy_projectile"]["lifetime_ticks"]):
			enemy_shots.erase(projectile)
			continue
		var start: Vector2 = projectile["position"]
		var destination: Vector2 = start+projectile["direction"]*float(projectile["speed"])/float(sim.clock.tick_rate)
		var wall_time := 1.0
		for wall in world.walls:
			wall_time = minf(wall_time,Projectile.segment_wall_time(start,destination,wall,float(projectile["radius"])))
		if not world.bounds.has_point(destination):
			wall_time = minf(wall_time,Projectile._bounds_exit_time(start,destination,world.bounds))
		var hit_time: float = Projectile._segment_circle_time(start,destination,sim.actor.position,float(projectile["radius"])+sim.actor.radius)
		if hit_time >= 0.0 and hit_time <= wall_time and state == "playing":
			damage_player(int(projectile["source_id"]),float(projectile["damage"]),"physical",int(projectile["attack_id"]))
			enemy_shots.erase(projectile)
		elif wall_time < 0.99999:
			enemy_shots.erase(projectile)
		else:
			projectile["position"] = destination

func _notify(message: String, at: Vector2) -> void:
	feedback.append({"label":message,"position":at,"tick":sim.clock.tick})

func snapshot() -> Dictionary:
	var foe_data: Array = []
	for foe in enemies:
		foe_data.append({"id":foe.target.id,"kind":foe.kind,"state":foe.state,"hp":foe.target.health.current,
			"position":foe.target.position,"alive":foe.target.alive()})
	return {"seed":seed,"scenario":scenario,"tick":sim.clock.tick,"state":state,"player_hp":sim.actor.health.current,
		"player_position":sim.actor.position,"player_mana":sim.mana,"enemy_count":alive_enemies(),
		"dashes":player.dashes,"casts":player.casts,"damage_taken":damage_received,"hits_received":attacks_received,
		"reactions":reactions,"enemy_shots":enemy_shots.size(),"effects":sim.queue.active_effect_count(),
		"frame_ms":elapsed_frame_ms,"foes":foe_data}
