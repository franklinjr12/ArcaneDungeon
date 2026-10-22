extends RefCounted
## M2 combat orchestration: reuses M1 SpellRunner and common MagicTarget/Health.
const Runner = preload("res://magic/runtime/spell_runner.gd")
const Geometry = preload("res://world/arena_geometry.gd")
const Player = preload("res://combat/player_combat.gd")
const Enemy = preload("res://combat/enemy_combat.gd")
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
var clear_tick := -1
var attacks_received := 0
var damage_received := 0.0
var reactions := 0
var elapsed_frame_ms := 0.0
var initialized := false
var debug_overlay := false
var reduce_flashes := false

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
	state = "playing"
	clear_tick = -1
	attacks_received = 0
	damage_received = 0.0
	reactions = 0
	elapsed_frame_ms = 0.0
	for n in 2:
		var spell: String = str(data["starter_loadouts"][loadout_index][n])
		sim.equip(n,samples[spell])
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

func issue(command: Dictionary) -> Dictionary:
	if state != "playing":
		return {"accepted":false,"reason":"COMBAT_ENDED"}
	return player.process_command(command)

func step() -> void:
	if state != "playing" or sim.clock.paused:
		return
	var start_usec: int = Time.get_ticks_usec()
	player.step_timers()
	sim.step()
	# AI progresses once after all player spells for the tick.
	for enemy in enemies:
		enemy.advance(self)
	advance_enemy_projectiles()
	if not sim.actor.alive() and state == "playing":
		state = "dead"
		_notify("DEFEAT - R to retry",sim.actor.position)
		# Input commands are rejected once state becomes dead.
		# Active effects are cleared on explicit retry, never survive restart.
	if state == "playing" and alive_enemies() == 0:
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
		_notify("DODGED",sim.actor.position)
		return {"accepted":false,"reason":"INVULNERABLE"}
	var event = DamageEvent.new(source_id,source.team,sim.actor.id,amount,channel,attack_id,sim.clock.tick)
	var dealt: float = sim.actor.receive_damage(amount,channel,source.team,float(sim.settings["combat"]["armor_scale"]))
	if dealt > 0:
		damage_received += dealt
		attacks_received += 1
		player.hit_flash = int(data["player"]["hit_flash_ticks"])
		damage_events.append(event.snapshot().merged({"dealt":dealt,"tick":sim.clock.tick}))
		_notify("-%d HP" % roundi(dealt),sim.actor.position)
	return {"accepted":dealt>0,"damage":dealt,"reason":"HIT" if dealt>0 else "BLOCKED"}

func on_enemy_death(enemy) -> void:
	if _death_ids.has(enemy.target.id):
		return
	_death_ids[enemy.target.id] = true
	enemy.target.status.clear()
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
		"dodges":player.dodges,"casts":player.casts,"damage_taken":damage_received,"hits_received":attacks_received,
		"reactions":reactions,"enemy_shots":enemy_shots.size(),"effects":sim.queue.active_effect_count(),
		"frame_ms":elapsed_frame_ms,"foes":foe_data}
