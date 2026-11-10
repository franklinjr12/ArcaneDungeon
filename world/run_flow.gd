extends RefCounted
## TASK-038/039/041/043/047/048: linear run coordinator, no persistent M1 effects across rooms.
const Difficulty = preload("res://game/core/difficulty.gd")
const State = preload("res://world/run_state.gd")
const Room = preload("res://world/room_template.gd")
const Encounter = preload("res://world/encounter_director.gd")
const Reward = preload("res://world/reward_generator.gd")
const Merchant = preload("res://world/merchant.gd")
const RunLog = preload("res://game/core/run_log.gd")
const Artifacts = preload("res://world/artifacts.gd")
const AudioDirector = preload("res://game/audio/audio_director.gd")
const Editor = preload("res://magic/editor/spell_editor.gd")
const Session = preload("res://combat/combat_session.gd")
const Runner = preload("res://magic/runtime/spell_runner.gd")
const ExperimentLog = preload("res://debug/experiment_log.gd")
const CONFIG := "res://world/data/vertical_slice_v1.json"
const CONFIG_V2 := "res://world/data/run_v2.json"
const SAVE_VERSION := 1
const PRESET_SLOT_OFFSET := 1
const SAMPLES := "res://magic/data/sandbox_samples_v1.json"
var config: Dictionary = {}
var config_path := ""
## Resolved room sequence for this run (v1: config["rooms"]; v2: seeded stage build).
var rooms: Array = []
var formulas: Dictionary = {}
var run
var session
var room
var encounter
var rewards
var merchant
## AD-144: base max mana of the current room before the merchant bonus.
var _base_max_mana := 0.0
var editor
var range_sim
var state := "uninitialized"
var reward_options: Array = []
var reward_collected := false
var boss_defeated_events := 0
var transition_count := 0
var edit_policy := "workshop_only"
var mode := "combat"
var initialized := false
var outcome := ""
var win_events := 0
# Run-local summary counters (not in RunState, so the save schema is untouched).
# ticks_elapsed counts fighting-state step() calls only (combat time, deterministic).
var rooms_cleared := 0
var kills := 0
var ticks_elapsed := 0
var spells_used := 0
var _counted_kills: Dictionary = {}
var run_log = RunLog.new()
var logs: Array = []
var experiment = ExperimentLog.new()
var _prior_reactions := 0
var room_reactions := 0
var resonant_clear := false
## AD-145: meta locks (opt-in, default empty) and per-run discovery tracking.
var meta_locked_runes: Array = []
var meta_locked_artifacts: Array = []
var _seen_enemies: Dictionary = {}
## AD-194: newest-8 first-sighting log [{kind,tick}] for the HUD popup. Presentation only, never saved or snapshotted.
var first_encounters: Array = []
var _seen_reactions: Dictionary = {}
## AD-084: read-only UI signals. arcs banks arcs from replaced sims; use arc_total() for the live count.
var wet_kills := 0
var arcs := 0
## AD-130: opt-in Sigil Desk prelude (not part of rooms/sequence_index/save schema).
var prelude := false
var prelude_built := false
var prelude_tested := false
## AD-020: output-only audio sink (Callable(cue_id, position)); the simulation never reads it.
var audio_sink: Callable

func _init(run_seed: int = -1, config_path: String = CONFIG) -> void:
	self.config_path = config_path
	var parsed = JSON.parse_string(FileAccess.get_file_as_string(config_path))
	var formula_data = JSON.parse_string(FileAccess.get_file_as_string(SAMPLES))
	if typeof(parsed) != TYPE_DICTIONARY or typeof(formula_data) != TYPE_DICTIONARY or int(parsed.get("schema_version",0)) != 1:
		push_error("M3 configuration missing/invalid")
		return
	config = parsed
	for value in formula_data["formulas"]:
		formulas[str(value["formula_id"])] = value
	initialized = true
	start_new(run_seed if run_seed >= 0 else int(config["seed"]))

## AD-138: cfg.room_templates plus the templates of every cfg.room_template_files entry (pool rules copied onto each).
static func merged_templates(cfg: Dictionary) -> Dictionary:
	var merged: Dictionary = cfg.get("room_templates",{}).duplicate(true)
	for path in cfg.get("room_template_files",[]):
		var doc = JSON.parse_string(FileAccess.get_file_as_string(str(path)))
		if typeof(doc) != TYPE_DICTIONARY:
			push_error("Room template file invalid: %s" % path)
			continue
		var rules: Dictionary = doc.get("rules",{})
		for id in doc.get("room_templates",{}):
			var entry: Dictionary = doc["room_templates"][id].duplicate(true)
			for key in ["min_spawn_distance","player_radius","grid_step"]:
				if rules.has(key):
					entry[key] = rules[key]
			merged[str(id)] = entry
	return merged

## Deterministic room order. v1 configs carry a fixed "rooms" list; v2 builds each stage from a seeded pool shuffle.
static func build_sequence(cfg: Dictionary, run_seed: int) -> Array:
	if cfg.has("rooms"):
		return cfg["rooms"].duplicate(true)
	var out: Array = []
	var templates: Dictionary = merged_templates(cfg)
	var stage_index := 0
	for stage in cfg.get("stages", []):
		var rng := RandomNumberGenerator.new()
		var hash_value := 2166136261
		for c in ("%d:%s" % [run_seed, str(stage["id"])]).to_utf8_buffer():
			hash_value = ((hash_value ^ int(c))*16777619) & 0x7fffffff
		rng.seed = hash_value
		var pool: Array = stage["pool"].duplicate()
		var wanted: int = rng.randi_range(int(stage["combat_rooms"]["min"]),int(stage["combat_rooms"]["max"]))
		if pool.size() < int(stage["combat_rooms"]["max"]):
			push_error("Stage %s pool smaller than combat_rooms.max" % stage["id"])
			return []
		for i in range(pool.size()-1,0,-1):
			var j := rng.randi_range(0,i)
			var swap = pool[i]
			pool[i] = pool[j]
			pool[j] = swap
		var ids: Array = pool.slice(0,wanted)
		ids.append(stage["optional_room"])
		if bool(stage.get("workshop_before_boss",false)):
			ids.append("workshop")
		ids.append(stage["boss_room"])
		if bool(stage.get("workshop_after",false)):
			ids.append("workshop")
		var in_stage := 0
		for id in ids:
			if not templates.has(str(id)):
				push_error("Room template missing: %s" % id)
				return []
			var entry: Dictionary = templates[str(id)].duplicate(true)
			if str(id) == str(stage["optional_room"]):
				entry["optional"] = true
			entry["stage"] = stage_index
			entry["room"] = in_stage
			in_stage += 1
			out.append(entry)
		stage_index += 1
	return out

func _cue(id: String, at = null) -> void:
	if audio_sink.is_valid():
		audio_sink.call(id,at)

## AD-151: artifact pickup/purchase cue via the data-driven event map; output-only.
func _artifact_cue(id: String) -> void:
	var cue := str(AudioDirector.load_events().get("artifact:" + id,""))
	if cue != "":
		_cue(cue)

func set_meta_locks(runes: Array, artifacts: Array) -> void:
	meta_locked_runes = runes.duplicate()
	meta_locked_artifacts = artifacts.duplicate()

## AD-145: sorted unique ids seen this run, per Compendium category.
func discoveries() -> Dictionary:
	var seen_runes: Array = run.unlocked.duplicate() if run != null else []
	var seen_artifacts: Array = run.artifacts.duplicate() if run != null else []
	var out := {"runes":[],"reactions":_seen_reactions.keys(),"enemies":_seen_enemies.keys(),"artifacts":[]}
	for id in seen_runes:
		if str(id) not in out["runes"]:
			out["runes"].append(str(id))
	for id in seen_artifacts:
		if str(id) not in out["artifacts"]:
			out["artifacts"].append(str(id))
	for key in out:
		out[key].sort()
	return out

func _track_enemies() -> void:
	for enemy in session.enemies:
		if str(enemy.kind) != "":
			if not _seen_enemies.has(str(enemy.kind)):
				first_encounters.append({"kind":str(enemy.kind),"tick":ticks_elapsed})
				while first_encounters.size() > 8:
					first_encounters.pop_front()
			_seen_enemies[str(enemy.kind)] = true

func start_new(run_seed: int) -> void:
	_seen_enemies.clear()
	first_encounters.clear()
	_seen_reactions.clear()
	run = State.new()
	run.initialize(run_seed,config,formulas)
	rooms = build_sequence(config,run_seed)
	boss_defeated_events = 0
	transition_count = 0
	outcome = ""
	win_events = 0
	rooms_cleared = 0
	kills = 0
	ticks_elapsed = 0
	spells_used = 0
	prelude = false
	prelude_built = false
	prelude_tested = false
	edit_policy = str(config["edit_policy"])
	logs.clear()
	if session != null:
		session.player.shield = 0
	experiment.record("run_restart")
	run_log = RunLog.new()
	run_log.begin(run_seed)
	_enter_current()

func _live_arcs(sim) -> int:
	if sim == null:
		return 0
	var count := 0
	for entry in sim.trace.filter_records(-1,"","reaction"):
		if str(entry.get("reason","")) == "wet_lightning_arc":
			count += 1
	return count

func arc_total() -> int:
	return arcs + _live_arcs(session.sim if session != null else null) + _live_arcs(range_sim)

func _bank_arcs() -> void:
	arcs += _live_arcs(session.sim if session != null else null) + _live_arcs(range_sim)

## Shared room/session/loadout setup for _enter_current and the Sigil Desk prelude.
func _build_room(entry: Dictionary) -> Dictionary:
	var template = Room.new()
	var geometry: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://combat/combat_tuning_v1.json"))
	var verdict: Dictionary = template.initialize(entry,geometry["arena"],geometry["enemies"].keys())
	if not verdict["ok"]:
		state = "error"
		return verdict
	room = template
	mode = "workshop" if room.values["type"] == "workshop" else "combat"
	var carried_shield: int = session.player.shield if session != null else 0
	session = Session.new(run.seed+run.sequence_index,"empty",0)
	session.defer_clear = true
	# AD-138: per-room layout walls and water join the shared arena (rooms without layout are untouched).
	var layout = room.values.get("layout",{})
	if typeof(layout) == TYPE_DICTIONARY:
		# AD-202: layout.arena_walls = false removes the shared arena walls; layout walls and props are appended below.
		if layout.get("arena_walls",true) == false:
			for dims in geometry["arena"]["walls"]:
				var shared := Rect2(float(dims[0]),float(dims[1]),float(dims[2]),float(dims[3]))
				session.world.walls.erase(shared)
				session.sim.collision_walls.erase(shared)
		for dims in layout.get("walls",[]):
			var wall := Rect2(float(dims[0]),float(dims[1]),float(dims[2]),float(dims[3]))
			session.world.walls.append(wall)
			session.sim.collision_walls.append(wall)
		if layout.has("pits"):
			session.pits = []
			for dims in layout["pits"]:
				session.pits.append(Rect2(float(dims[0]),float(dims[1]),float(dims[2]),float(dims[3])))
			session.world.add_ground_blockers(session.pits)
		if layout.has("water"):
			session.set_water(layout["water"])
		if layout.has("env_props"):
			session.set_env_props(layout["env_props"])
	session.audio_sink = _cue
	session.sim.actor.position = room.marker("entrance")
	session.sim.actor.health.maximum = run.max_hp
	session.sim.actor.health.current = run.hp
	# Owner request 2026-11-05: mana fully regenerates on every room change.
	_base_max_mana = float(session.sim.settings["combat"]["player_max_mana"])
	session.sim.settings["combat"]["player_max_mana"] = _base_max_mana+run.max_mana_bonus
	session.player.set_dash_bonus(run.dash_charges_bonus)
	run.mana = float(session.sim.settings["combat"]["player_max_mana"])
	session.sim.mana = run.mana
	session.sim.loadout.unlocked = run.unlocked.duplicate(true)
	session.sim.loadout.allow_edit = true
	var result: Dictionary = session.sim.equip_starter_loadout(run.formulas)
	if not result["ok"]:
		state = "error"
		return {"ok":false,"reason":"RUN_LOADOUT_INVALID","issues":result["issues"]}
	session.sim.loadout.allow_edit = false
	reward_options.clear()
	reward_collected = false
	_counted_kills.clear()
	editor = Editor.new(run,session.sim.registry,session.sim.loadout.slots.size()-PRESET_SLOT_OFFSET)
	merchant = null
	range_sim = null
	encounter = null
	rewards = Reward.new(config,meta_locked_runes,meta_locked_artifacts)
	_attach_artifacts()
	session.player.shield = carried_shield
	return {"ok":true}

## AD-143: the room sim gets a holder built from the run, so newly gained artifacts apply at once.
func _attach_artifacts() -> void:
	if session == null:
		return
	if session.sim.artifacts == null:
		session.sim.artifacts = Artifacts.new(run.artifacts)
	else:
		for id in run.artifacts:
			session.sim.artifacts.add(str(id))

## Output-only: music context for the current room (workshop, boss, else the stage's music_context).
func music_context_for_room() -> String:
	if mode == "workshop":
		return "workshop"
	if room != null and room.values.get("type","") == "boss":
		return "boss"
	var idx: int = run.sequence_index if run != null else 0
	if idx >= 0 and idx < rooms.size():
		var stages: Array = config.get("stages",[])
		var s := int(rooms[idx].get("stage",0))
		if s >= 0 and s < stages.size():
			return str(stages[s].get("music_context","ruins"))
	return "ruins"

func _enter_current() -> Dictionary:
	_bank_arcs()
	var built: Dictionary = _build_room(rooms[run.sequence_index])
	if not built["ok"]:
		return built
	if mode == "workshop":
		session.state = "cleared"
		state = "workshop"
		merchant = Merchant.new(config)
		merchant.excluded_artifacts = meta_locked_artifacts.duplicate()
		merchant.build(run,session.sim.registry.get_ids(),meta_locked_runes)
		enter_test_range()
	elif room.values["type"] == "treasure":
		# Optional reward room: no enemies, the reward cards are available immediately.
		session.state = "cleared"
		state = "cleared"
		reward_options = rewards.choices(run,str(room.values["id"]),true)
	elif room.values["type"] == "boss":
		var p: Dictionary = config["bosses"][str(room.values["boss"])] if room.values.has("boss") and config.has("bosses") else config["boss"]
		if session.spawn_boss(p,Vector2(float(p["position"][0]),float(p["position"][1]))) == null:
			state = "error"
			return {"ok":false,"reason":"BOSS_SPAWN_BLOCKED"}
		state = "fighting"
	else:
		encounter = Encounter.new()
		encounter.initialize(room,session,int(config["max_active_enemies"]))
		state = "fighting"
	_prior_reactions = 0
	room_reactions = 0
	resonant_clear = false
	_cue("amb.workshop" if mode == "workshop" else "amb.ruins")
	_cue("music." + music_context_for_room())
	experiment.record("room_enter",{"room_index":run.sequence_index})
	run_log.enter_room(run.sequence_index,str(room.values["id"]),str(room.values["type"]),ticks_elapsed)
	logs.append({"kind":"room_enter","id":room.values["id"],"index":run.sequence_index})
	return {"ok":true}

func prelude_available() -> bool:
	var desk = config.get("sigil_desk")
	return desk is Dictionary and bool(desk.get("enabled",false))

## Owner request 2026-11-05: the desk is optional practice unless the config sets "required": true.
func prelude_required() -> bool:
	return prelude_available() and bool(config["sigil_desk"].get("required",true))

func prelude_ready() -> bool:
	if not prelude_built:
		return false
	return prelude_tested or not bool(config["sigil_desk"].get("require_test_cast",true))

## Call right after start_new: puts the player at the Sigil Desk (workshop template) before room 1.
func enter_prelude() -> Dictionary:
	if not prelude_available():
		return {"ok":false,"reason":"PRELUDE_UNAVAILABLE"}
	if run.sequence_index != 0 or rooms_cleared > 0 or ticks_elapsed > 0 or state == "dead":
		return {"ok":false,"reason":"PRELUDE_TOO_LATE"}
	var desk: Dictionary = config["sigil_desk"]
	var templates: Dictionary = config.get("room_templates",{})
	if not templates.has(str(desk["room_template"])):
		return {"ok":false,"reason":"PRELUDE_ROOM_MISSING"}
	for id in desk["runes"]:
		if not run.unlocked.has(str(id)):
			run.unlocked.append(str(id))
	_bank_arcs()
	var built: Dictionary = _build_room(templates[str(desk["room_template"])])
	if not built["ok"]:
		return built
	mode = "workshop"
	state = "workshop"
	session.state = "cleared"
	prelude = true
	prelude_built = false
	prelude_tested = false
	enter_test_range()
	_cue("amb.workshop")
	_cue("music.workshop")
	experiment.record("prelude_enter")
	logs.append({"kind":"prelude_enter","id":room.values["id"]})
	return {"ok":true}

func finish_prelude(skipped: bool) -> Dictionary:
	if editor != null and editor.allowed:
		return {"ok":false,"reason":"EDITOR_OPEN"}
	if not skipped and not (prelude and prelude_ready()):
		return {"ok":false,"reason":"PRELUDE_INCOMPLETE"}
	prelude = false
	experiment.record("prelude_skipped" if skipped else "prelude_complete")
	logs.append({"kind":"prelude_skipped" if skipped else "prelude_complete"})
	return _enter_current()

func _slot_has_spell(runner, slot: int) -> bool:
	return slot >= 0 and slot < runner.loadout.slots.size() and runner.loadout.slots[slot]["compiled"] != null

func step(command: Dictionary = {}) -> Dictionary:
	if state != "fighting":
		return {"ok":false,"reason":"NOT_FIGHTING"}
	if not command.is_empty():
		var issued: Dictionary = session.issue(command)
		var cast_slot: int = int(command.get("cast",-1))
		if _slot_has_spell(session.sim,cast_slot):
			if bool(issued.get("accepted",false)):
				spells_used += 1
				run_log.add_elements(Reward.essences_of(session.sim.loadout.slots[cast_slot]["formula"]))
			experiment.record("dungeon_cast",{"room_index":run.sequence_index,"slot":cast_slot,
				"cast_accepted":bool(issued.get("accepted",false))},session.sim.loadout.slots[cast_slot]["formula"])
	var wet_ids: Array = []
	for enemy in session.enemies:
		if enemy.target.alive() and enemy.target.status.has("wet",session.sim.clock.tick):
			wet_ids.append(enemy)
	session.step()
	ticks_elapsed += 1
	# AD-150: coins released by broken props join the run purse (props exist only in rooms whose layout lists them).
	if session.env_props != null and session.env_props.pending_coins > 0:
		run.currency += session.env_props.pending_coins
		session.env_props.pending_coins = 0
		_cue("sfx.pickup.currency",session.sim.actor.position)
	for enemy in wet_ids:
		if not enemy.target.alive():
			wet_kills += 1
	for enemy in session.enemies:
		if not enemy.target.alive() and not _counted_kills.has(enemy.target.id):
			_counted_kills[enemy.target.id] = true
			kills += 1
			run_log.add_enemy_death(str(enemy.kind))
	experiment.mark_tick(session.sim.clock.tick)
	_track_enemies()
	var reaction_records: Array = session.sim.trace.filter_records(-1,"","reaction")
	var reactions_now: int = reaction_records.size()
	for i in range(_prior_reactions,reactions_now):
		var reason := str(reaction_records[i].get("reason",""))
		if reason != "":
			_seen_reactions[reason] = true
			if reason in Reward.combo_reaction_ids():
				room_reactions += 1
				run_log.add_reaction(reason)
	if reactions_now > _prior_reactions:
		experiment.record("reaction",{"room_index":run.sequence_index,"reaction_count":reactions_now-_prior_reactions})
	_prior_reactions = reactions_now
	if encounter != null:
		encounter.advance()
	run_log.sample(ticks_elapsed,session.damage_received,session.sim.clock.tick_rate)
	if session.state == "dead":
		state = "dead"
		outcome = "lost"
		run_log.finish("lost",run.artifacts,_death_cause())
		experiment.record("death",{"room_index":run.sequence_index})
	elif session.state == "cleared" or (room.values["type"] == "boss" and session.alive_enemies() == 0):
		_finish_combat()
	return {"ok":true,"state":state}

func _finish_combat() -> void:
	if state != "fighting":
		return
	session.state = "cleared"
	session.enemy_shots.clear()
	# Exiting combat cancels dash locks so cleared-room walking obeys input.
	session.player.dash_left = 0
	session.player.recovery_left = 0
	session.player.invulnerable_left = 0
	session.player.dash_cooldown = 0
	session.player.bonus_dashes_left = session.player.dash_charges_bonus
	# Old projectiles remain only in this room and are discarded on transition.
	state = "cleared"
	rooms_cleared += 1
	var resonant_cfg: Dictionary = config.get("resonant_clear",{})
	resonant_clear = not resonant_cfg.is_empty() and room_reactions >= int(resonant_cfg["min_reactions"])
	if resonant_clear:
		run_log.mark_resonant()
	_cue("sfx.room.cleared",session.sim.actor.position)
	run.hp = session.sim.actor.health.current
	run.mana = session.sim.mana
	var lantern = session.sim.artifacts
	if lantern != null and lantern.has("warding_lantern"):
		session.player.shield = int(lantern.param("warding_lantern","shield_hits",1))
	if room.values["type"] == "boss":
		boss_defeated_events += 1
	if run.sequence_index >= rooms.size()-1:
		# Final room cleared: run complete, no reward choice.
		outcome = "won"
		win_events += 1
		experiment.record("slice_complete",{"room_index":run.sequence_index})
		state = "won"
		run_log.finish("won",run.artifacts,null)
		reward_collected = true
		reward_options.clear()
	elif room.values["type"] == "boss":
		run.currency += Difficulty.scale_i(int(config["boss_currency"]),"coin_rate",0)
		if resonant_clear:
			run.currency += Difficulty.scale_i(int(resonant_cfg["bonus_coins"]),"coin_rate",0)
		_cue("sfx.pickup.currency",session.sim.actor.position)
		reward_collected = true
	else:
		reward_options = rewards.choices(run,str(room.values["id"]),false,resonant_clear)
	experiment.record("room_clear",{"room_index":run.sequence_index})
	logs.append({"kind":"combat_clear","id":room.values["id"]})

func _death_cause() -> Dictionary:
	var kind := "unknown"
	var channel := ""
	if not session.damage_events.is_empty():
		var last: Dictionary = session.damage_events.back()
		channel = str(last.get("channel",""))
		for enemy in session.enemies:
			if enemy.target.id == int(last.get("source_id",-1)):
				kind = str(enemy.kind)
				break
	return {"cause":kind,"channel":channel,"room_id":str(room.values["id"]),"room_index":run.sequence_index}

func summary() -> Dictionary:
	return {"outcome":outcome,"seed":run.seed,"rooms_cleared":rooms_cleared,"kills":kills,
		"ticks":ticks_elapsed,"seconds":float(ticks_elapsed)/float(session.sim.clock.tick_rate),
		"spells_used":spells_used,"reactions_triggered":run_log.reactions_triggered,
		"elements_used":run_log.elements_used.size(),"spells_crafted":run_log.spells_crafted.size()}

func retry_same_seed() -> void:
	start_new(run.seed)

func start_new_seed() -> void:
	# Deterministic successor seed (not a gameplay tunable): hash of the current seed, 31-bit positive.
	var next_seed: int = ("%d:next" % run.seed).hash() & 0x7fffffff
	if next_seed == run.seed:
		next_seed += 1
	start_new(next_seed)

func choose_reward(index: int) -> Dictionary:
	if state != "cleared" or room.values["type"] not in ["combat","challenge","treasure"] or reward_collected:
		return {"ok":false,"reason":"REWARD_NOT_AVAILABLE"}
	if index < 0 or index >= reward_options.size():
		return {"ok":false,"reason":"REWARD_INDEX_INVALID"}
	var id: String = str(room.values["id"])
	if id in run.collected:
		return {"ok":false,"reason":"REWARD_ALREADY_COLLECTED"}
	var option: Dictionary = reward_options[index]
	var outcome: Dictionary
	if option["kind"] == "rune":
		outcome = run.unlock(str(option["id"]),Difficulty.scale_i(int(config["duplicate_reward_currency"]),"coin_rate",0))
	elif option["kind"] == "artifact":
		var added: Dictionary = run.add_artifact(str(option["id"]))
		if not added["ok"]:
			return added
		outcome = {"ok":true,"kind":"artifact","id":str(option["id"])}
		_artifact_cue(str(option["id"]))
		_attach_artifacts()
	else:
		run.currency += int(option["amount"])
		outcome = {"ok":true,"kind":"currency","currency":int(option["amount"])}
	var bonus := int(option.get("bonus_coins",0))
	if bonus > 0:
		run.currency += bonus
		outcome["bonus_coins"] = bonus
	run.collected.append(id)
	reward_collected = true
	session.sim.loadout.unlocked = run.unlocked.duplicate(true)
	_cue("ui.reward_pick")
	_cue("sfx.pickup.rune" if outcome.get("kind","") == "unlock" else "sfx.pickup.currency")
	experiment.record("rune_choice",{"room_index":run.sequence_index,"rune_index":index})
	logs.append({"kind":"reward","room":id,"item":option.duplicate(true)})
	return outcome

func move_after_clear(command: Dictionary) -> Dictionary:
	if state not in ["cleared","workshop"] or session.player.modal:
		return {"accepted":false,"reason":"NO_MOVEMENT"}
	# Only movement and aim are allowed between encounters.
	var safe: Dictionary = {"move":command.get("move",Vector2.ZERO),"aim":command.get("aim",Vector2.RIGHT),"cast":-1,"dash":false}
	return session.player.process_command(safe)

## True when the next room is an optional one the player may skip at the door.
func next_is_optional() -> bool:
	var next_index: int = run.sequence_index+1
	return next_index < rooms.size() and bool(rooms[next_index].get("optional",false))

func try_exit(position: Vector2, take_optional: bool = true) -> Dictionary:
	if editor != null and editor.allowed:
		return {"ok":false,"reason":"EDITOR_OPEN"}
	if state not in ["cleared","workshop"]:
		return {"ok":false,"reason":"DOOR_LOCKED"}
	if prelude:
		return finish_prelude(not prelude_ready() and not prelude_required())
	# Workshop is drawn as the test range only (no visible door), so leaving it is a menu action.
	if mode != "workshop" and position.distance_to(room.marker("exit")) > 72.0:
		return {"ok":false,"reason":"EXIT_TOO_FAR"}
	if run.sequence_index >= rooms.size()-1:
		return {"ok":false,"reason":"SLICE_COMPLETE"}
	if session != null and session.sim.actor.alive():
		if mode != "workshop":
			run.hp = session.sim.actor.health.current
			run.mana = session.sim.mana
	if not take_optional and next_is_optional():
		logs.append({"kind":"optional_skipped","id":rooms[run.sequence_index+1]["id"]})
		run.sequence_index += 1
	run.sequence_index += 1
	transition_count += 1
	var outcome: Dictionary = _enter_current()
	if outcome["ok"]:
		logs.append({"kind":"transition","index":run.sequence_index})
	return outcome

func enter_test_range() -> Dictionary:
	if mode != "workshop":
		return {"ok":false,"reason":"TEST_ONLY_WORKSHOP"}
	arcs += _live_arcs(range_sim)
	range_sim = Runner.new(run.seed)
	range_sim.loadout.unlocked = run.unlocked.duplicate(true)
	var result: Dictionary = range_sim.equip_starter_loadout(run.formulas)
	if not result["ok"]:
		return result
	range_sim.actor.health.maximum = Difficulty.scale_f(float(config["workshop_restore_hp"]),"player_hp")
	range_sim.actor.health.reset()
	range_sim.mana = Difficulty.scale_f(float(config["workshop_restore_mana"]),"player_mana")
	range_sim.fill_targets()
	return {"ok":true}

func prepare_wet_cluster() -> Dictionary:
	if mode != "workshop" or range_sim == null:
		return {"ok":false,"reason":"TEST_ONLY_WORKSHOP"}
	var targets_list: Array = range_sim.targets.all()
	var applied := 0
	for target in targets_list:
		if target.id == range_sim.actor.id:
			continue
		target.status.apply("wet",range_sim.clock.tick,range_sim.settings["statuses"]["wet"],
			{"cast_id":0,"root_cast_id":0,"formula_id":"test_preset.wet","team":range_sim.actor.team})
		applied += 1
		if applied >= 2:
			break
	return {"ok":applied == 2,"count":applied}

func refill_test_mana() -> Dictionary:
	if range_sim == null or mode != "workshop":
		return {"ok":false,"reason":"TEST_ONLY_WORKSHOP"}
	range_sim.mana = Difficulty.scale_f(float(config["workshop_restore_mana"]),"player_mana")
	return {"ok":true}

func test_cast(slot: int, direction: Vector2) -> Dictionary:
	if mode != "workshop" or range_sim == null:
		return {"accepted":false,"reason":"TEST_ONLY_WORKSHOP"}
	var result: Dictionary = range_sim.try_cast(slot,range_sim.actor.position,direction)
	if prelude and bool(result["accepted"]) and slot == int(config["sigil_desk"]["formula_index"])+PRESET_SLOT_OFFSET:
		prelude_tested = true
	if _slot_has_spell(range_sim,slot):
		experiment.record("test_cast",{"slot":slot,"is_workshop":true,"cast_accepted":result["accepted"]},range_sim.loadout.slots[slot]["formula"])
	return result

func open_editor(slot: int) -> Dictionary:
	if editor != null and editor.allowed:
		return {"ok":false,"reason":"EDITOR_ALREADY_OPEN"}
	if state == "fighting" or state == "dead":
		return {"ok":false,"reason":"COMBAT_LOCKED"}
	if mode != "workshop" and (state != "cleared" or edit_policy != "cleared_room"):
		return {"ok":false,"reason":"POLICY_WORKSHOP_ONLY"}
	editor = Editor.new(run,session.sim.registry,session.sim.loadout.slots.size()-PRESET_SLOT_OFFSET)
	var result: Dictionary = editor.open(slot)
	if result["ok"]:
		if prelude and slot == int(config["sigil_desk"]["formula_index"]):
			editor.set_guided(config["sigil_desk"]["runes"])
		session.player.modal = true
		experiment.record("editor_open",{"room_index":run.sequence_index,"slot":slot})
		logs.append({"kind":"editor_open","slot":slot,"room":room.values["id"]})
	return result

func close_editor(apply_changes: bool, duration_seconds: float = 0.0) -> Dictionary:
	if editor == null or not editor.allowed:
		return {"ok":false,"reason":"EDITOR_CLOSED"}
	if apply_changes:
		var result: Dictionary = editor.apply()
		if not result["ok"]:
			_cue("ui.editor_error")
			return result
		var edit_slot: int = editor.slot
		session.sim.loadout.allow_edit = true
		session.sim.loadout.unlocked = run.unlocked.duplicate(true)
		var equipped: Dictionary = session.sim.equip(edit_slot+PRESET_SLOT_OFFSET,run.formulas[edit_slot])
		session.sim.loadout.allow_edit = false
		if not equipped["ok"]:
			return equipped
		run_log.add_spell(str(run.formulas[edit_slot].get("formula_id","")),edit_slot,run.sequence_index,run.formulas[edit_slot])
		if prelude and edit_slot == int(config["sigil_desk"]["formula_index"]):
			prelude_built = true
		experiment.record("formula_edit",{"room_index":run.sequence_index,"slot":edit_slot},run.formulas[edit_slot])
		if mode == "workshop":
			# Reset only test runtime, never the run's HP/currency/progression.
			enter_test_range()
	else:
		editor.cancel()
	session.player.modal = false
	run.edit_count += 1
	if mode != "workshop":
		run.quick_edit_count += 1
	run.edit_seconds += maxf(0,duration_seconds)
	experiment.record("editor_close",{"room_index":run.sequence_index,"duration_ms":roundi(duration_seconds*1000.0)})
	logs.append({"kind":"editor_close","applied":apply_changes,"seconds":duration_seconds})
	return {"ok":true}

func buy(index: int) -> Dictionary:
	if mode != "workshop" or merchant == null:
		return {"ok":false,"reason":"SHOP_ONLY_WORKSHOP"}
	var outcome: Dictionary = merchant.purchase(index,run)
	if outcome["ok"]:
		_cue("ui.purchase")
		if outcome["kind"] == "rune":
			_cue("sfx.pickup.rune")
		elif outcome["kind"] == "artifact":
			_artifact_cue(str(merchant.stock[index].get("artifact_id","")))
		experiment.record("purchase",{"room_index":run.sequence_index,"price":int(merchant.stock[index]["price"])})
		session.sim.loadout.unlocked = run.unlocked.duplicate(true)
		_attach_artifacts()
		if outcome["kind"] == "upgrade":
			session.sim.actor.health.maximum = run.max_hp
			session.sim.actor.health.current = run.hp
			session.sim.settings["combat"]["player_max_mana"] = _base_max_mana+run.max_mana_bonus
			session.sim.mana = run.mana
			session.player.set_dash_bonus(run.dash_charges_bonus)
	return outcome

func reroll() -> Dictionary:
	if mode != "workshop" or merchant == null:
		return {"ok":false,"reason":"SHOP_ONLY_WORKSHOP"}
	var outcome: Dictionary = merchant.reroll(run)
	if outcome["ok"]:
		_cue("ui.purchase")
		experiment.record("merchant_reroll",{"room_index":run.sequence_index,"price":int(merchant.config.get("reroll_price",0))})
	return outcome

func change_edit_policy(value: String) -> bool:
	if value not in ["workshop_only","cleared_room"]:
		return false
	edit_policy = value
	return true

func snapshot() -> Dictionary:
	return {"state":state,"room_id":room.values["id"],"index":run.sequence_index,
		"mode":mode,"door_open":state in ["cleared","workshop"],"rewards":reward_options.duplicate(true),
		"collected":reward_collected,"run":run.snapshot(),"boss_events":boss_defeated_events,
		"outcome":outcome,"win_events":win_events,"prelude":prelude}

func recover(saved: Variant) -> Dictionary:
	var validated = State.new()
	if typeof(saved) == TYPE_DICTIONARY and typeof(saved.get("seed")) in [TYPE_INT,TYPE_FLOAT]:
		rooms = build_sequence(config,int(saved["seed"]))
	var result: Dictionary = validated.restore(saved,session.sim.registry,rooms.size())
	if not result["ok"]:
		return result
	run = validated
	return _enter_current()

## AD-146: the run may only be saved while resting in the workshop (never mid-combat, prelude or editor).
func can_save() -> bool:
	return initialized and mode == "workshop" and state == "workshop" and not prelude \
		and not (editor != null and editor.allowed)

func save_payload() -> Dictionary:
	if not can_save():
		return {}
	var enemies: Array = _seen_enemies.keys()
	var reactions: Array = _seen_reactions.keys()
	enemies.sort()
	reactions.sort()
	return {"version":SAVE_VERSION,"config_path":config_path,"run":run.snapshot(),
		"counters":{"rooms_cleared":rooms_cleared,"kills":kills,"ticks_elapsed":ticks_elapsed,
			"spells_used":spells_used,"wet_kills":wet_kills,"arcs":arc_total(),
			"boss_defeated_events":boss_defeated_events,"transition_count":transition_count},
		"seen_enemies":enemies,"seen_reactions":reactions,
		"meta_locked_runes":meta_locked_runes.duplicate(),"meta_locked_artifacts":meta_locked_artifacts.duplicate(),
		"merchant_stock":merchant.stock.duplicate(true),"edit_policy":edit_policy,"run_log":run_log.snapshot()}

static func _whole(v) -> bool:
	return typeof(v) in [TYPE_INT,TYPE_FLOAT] and is_finite(float(v)) and float(v) == floorf(float(v))

## JSON turns every number into a float; whole numbers go back to int so restored stock equals the original.
static func _intify(v: Variant) -> Variant:
	if typeof(v) == TYPE_FLOAT and is_finite(v) and v == floorf(v):
		return int(v)
	if typeof(v) == TYPE_DICTIONARY:
		var d := {}
		for k in v:
			d[k] = _intify(v[k])
		return d
	if typeof(v) == TYPE_ARRAY:
		return v.map(_intify)
	return v

func _valid_stock(stock: Variant, rune_ids: Array) -> bool:
	if typeof(stock) != TYPE_ARRAY:
		return false
	for item in stock:
		if typeof(item) != TYPE_DICTIONARY or str(item.get("kind","")) not in ["rune","upgrade","artifact"]:
			return false
		if not _whole(item.get("price")) or float(item["price"]) < 0.0 or typeof(item.get("id")) != TYPE_STRING:
			return false
		if item["kind"] == "rune" and (typeof(item.get("rune_id")) != TYPE_STRING or str(item["rune_id"]) not in rune_ids):
			return false
		if item["kind"] == "artifact" and (typeof(item.get("artifact_id")) != TYPE_STRING or not Artifacts.is_known(str(item["artifact_id"]))):
			return false
	return true

## Restores a payload from save_payload(); only workshop saves are accepted, so there is no way into combat.
func resume(payload: Variant) -> Dictionary:
	if typeof(payload) != TYPE_DICTIONARY:
		return {"ok":false,"reason":"RUN_SAVE_NOT_OBJECT"}
	if not _whole(payload.get("version")) or int(payload["version"]) != SAVE_VERSION:
		return {"ok":false,"reason":"RUN_SAVE_VERSION"}
	if str(payload.get("config_path","")) != config_path:
		return {"ok":false,"reason":"RUN_SAVE_CONFIG_MISMATCH"}
	var counters = payload.get("counters")
	if typeof(counters) != TYPE_DICTIONARY:
		return {"ok":false,"reason":"RUN_SAVE_COUNTERS"}
	for key in ["rooms_cleared","kills","ticks_elapsed","spells_used","wet_kills","arcs","boss_defeated_events","transition_count"]:
		if not _whole(counters.get(key)) or float(counters[key]) < 0.0:
			return {"ok":false,"reason":"RUN_SAVE_COUNTERS"}
	for key in ["seen_enemies","seen_reactions","meta_locked_runes","meta_locked_artifacts"]:
		if typeof(payload.get(key)) != TYPE_ARRAY:
			return {"ok":false,"reason":"RUN_SAVE_LISTS"}
	if str(payload.get("edit_policy","")) not in ["workshop_only","cleared_room"]:
		return {"ok":false,"reason":"RUN_SAVE_EDIT_POLICY"}
	var saved_run = payload.get("run")
	if typeof(saved_run) != TYPE_DICTIONARY or not _whole(saved_run.get("seed")):
		return {"ok":false,"reason":"RUN_NOT_OBJECT"}
	var new_rooms: Array = build_sequence(config,int(saved_run["seed"]))
	var validated = State.new()
	var result: Dictionary = validated.restore(saved_run,session.sim.registry,new_rooms.size())
	if not result["ok"]:
		return result
	if str(new_rooms[validated.sequence_index].get("type","")) != "workshop":
		return {"ok":false,"reason":"RUN_SAVE_NOT_WORKSHOP"}
	if not _valid_stock(payload.get("merchant_stock"),session.sim.registry.get_ids()):
		return {"ok":false,"reason":"RUN_SAVE_STOCK"}
	rooms = new_rooms
	run = validated
	set_meta_locks(payload["meta_locked_runes"],payload["meta_locked_artifacts"])
	rooms_cleared = int(counters["rooms_cleared"])
	kills = int(counters["kills"])
	ticks_elapsed = int(counters["ticks_elapsed"])
	spells_used = int(counters["spells_used"])
	wet_kills = int(counters["wet_kills"])
	boss_defeated_events = int(counters["boss_defeated_events"])
	transition_count = int(counters["transition_count"])
	_seen_enemies.clear()
	first_encounters.clear()
	for id in payload["seen_enemies"]:
		_seen_enemies[str(id)] = true
	_seen_reactions.clear()
	for id in payload["seen_reactions"]:
		_seen_reactions[str(id)] = true
	edit_policy = str(payload["edit_policy"])
	prelude = false
	prelude_built = false
	prelude_tested = false
	outcome = ""
	win_events = 0
	arcs = 0
	run_log = RunLog.new()
	run_log.restore(_intify(payload.get("run_log")),run.seed)
	var entered: Dictionary = _enter_current()
	if not entered.get("ok",false):
		return entered
	merchant.stock = _intify(payload["merchant_stock"])
	arcs = 0
	arcs = int(counters["arcs"]) - arc_total()
	return {"ok":true}
