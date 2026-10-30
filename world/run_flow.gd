extends RefCounted
## TASK-038/039/041/043/047/048: linear run coordinator, no persistent M1 effects across rooms.
const State = preload("res://world/run_state.gd")
const Room = preload("res://world/room_template.gd")
const Encounter = preload("res://world/encounter_director.gd")
const Reward = preload("res://world/reward_generator.gd")
const Merchant = preload("res://world/merchant.gd")
const Editor = preload("res://magic/editor/spell_editor.gd")
const Session = preload("res://combat/combat_session.gd")
const Runner = preload("res://magic/runtime/spell_runner.gd")
const ExperimentLog = preload("res://debug/experiment_log.gd")
const CONFIG := "res://world/data/vertical_slice_v1.json"
const PRESET_SLOT_OFFSET := 1
const SAMPLES := "res://magic/data/sandbox_samples_v1.json"
var config: Dictionary = {}
var formulas: Dictionary = {}
var run
var session
var room
var encounter
var rewards
var merchant
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
var logs: Array = []
var experiment = ExperimentLog.new()
var _prior_reactions := 0

func _init(run_seed: int = -1) -> void:
	var parsed = JSON.parse_string(FileAccess.get_file_as_string(CONFIG))
	var formula_data = JSON.parse_string(FileAccess.get_file_as_string(SAMPLES))
	if typeof(parsed) != TYPE_DICTIONARY or typeof(formula_data) != TYPE_DICTIONARY or int(parsed.get("schema_version",0)) != 1:
		push_error("M3 configuration missing/invalid")
		return
	config = parsed
	for value in formula_data["formulas"]:
		formulas[str(value["formula_id"])] = value
	initialized = true
	start_new(run_seed if run_seed >= 0 else int(config["seed"]))

func start_new(run_seed: int) -> void:
	run = State.new()
	run.initialize(run_seed,config,formulas)
	boss_defeated_events = 0
	transition_count = 0
	edit_policy = str(config["edit_policy"])
	logs.clear()
	experiment.record("run_restart")
	_enter_current()

func _enter_current() -> Dictionary:
	var template = Room.new()
	var geometry: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://combat/combat_tuning_v1.json"))
	var verdict: Dictionary = template.initialize(config["rooms"][run.sequence_index],geometry["arena"],geometry["enemies"].keys())
	if not verdict["ok"]:
		state = "error"
		return verdict
	room = template
	mode = "workshop" if room.values["type"] == "workshop" else "combat"
	session = Session.new(run.seed+run.sequence_index,"empty",0)
	session.defer_clear = true
	session.sim.actor.position = room.marker("entrance")
	session.sim.actor.health.maximum = run.max_hp
	session.sim.actor.health.current = run.hp
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
	editor = Editor.new(run,session.sim.registry)
	merchant = null
	range_sim = null
	encounter = null
	rewards = Reward.new(config)
	if mode == "workshop":
		session.state = "cleared"
		state = "workshop"
		merchant = Merchant.new(config)
		merchant.build(run,session.sim.registry.get_ids())
		enter_test_range()
	elif room.values["type"] == "boss":
		var p: Dictionary = config["boss"]
		if session.spawn_boss(p,Vector2(float(p["position"][0]),float(p["position"][1]))) == null:
			state = "error"
			return {"ok":false,"reason":"BOSS_SPAWN_BLOCKED"}
		state = "fighting"
	else:
		encounter = Encounter.new()
		encounter.initialize(room,session,int(config["max_active_enemies"]))
		state = "fighting"
	_prior_reactions = 0
	experiment.record("room_enter",{"room_index":run.sequence_index})
	logs.append({"kind":"room_enter","id":room.values["id"],"index":run.sequence_index})
	return {"ok":true}

func _slot_has_spell(runner, slot: int) -> bool:
	return slot >= 0 and slot < runner.loadout.slots.size() and runner.loadout.slots[slot]["compiled"] != null

func step(command: Dictionary = {}) -> Dictionary:
	if state != "fighting":
		return {"ok":false,"reason":"NOT_FIGHTING"}
	if not command.is_empty():
		var issued: Dictionary = session.issue(command)
		var cast_slot: int = int(command.get("cast",-1))
		if _slot_has_spell(session.sim,cast_slot):
			experiment.record("dungeon_cast",{"room_index":run.sequence_index,"slot":cast_slot,
				"cast_accepted":bool(issued.get("accepted",false))},session.sim.loadout.slots[cast_slot]["formula"])
	session.step()
	experiment.mark_tick(session.sim.clock.tick)
	var reactions_now: int = session.sim.trace.filter_records(-1,"","reaction").size()
	if reactions_now > _prior_reactions:
		experiment.record("reaction",{"room_index":run.sequence_index,"reaction_count":reactions_now-_prior_reactions})
	_prior_reactions = reactions_now
	if encounter != null:
		encounter.advance()
	if session.state == "dead":
		state = "dead"
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
	session.player.dodge_left = 0
	session.player.recovery_left = 0
	session.player.invulnerable_left = 0
	session.player.dodge_cooldown = 0
	# Old projectiles remain only in this room and are discarded on transition.
	state = "cleared"
	run.hp = session.sim.actor.health.current
	run.mana = session.sim.mana
	if room.values["type"] == "boss":
		boss_defeated_events += 1
		run.currency += int(config["boss_currency"])
		reward_collected = true
	else:
		reward_options = rewards.choices(run,str(room.values["id"]))
	experiment.record("room_clear",{"room_index":run.sequence_index})
	logs.append({"kind":"combat_clear","id":room.values["id"]})

func choose_reward(index: int) -> Dictionary:
	if state != "cleared" or room.values["type"] != "combat" or reward_collected:
		return {"ok":false,"reason":"REWARD_NOT_AVAILABLE"}
	if index < 0 or index >= reward_options.size():
		return {"ok":false,"reason":"REWARD_INDEX_INVALID"}
	var id: String = str(room.values["id"])
	if id in run.collected:
		return {"ok":false,"reason":"REWARD_ALREADY_COLLECTED"}
	var option: Dictionary = reward_options[index]
	var outcome: Dictionary
	if option["kind"] == "rune":
		outcome = run.unlock(str(option["id"]),int(config["duplicate_reward_currency"]))
	else:
		run.currency += int(option["amount"])
		outcome = {"ok":true,"kind":"currency","currency":int(option["amount"])}
	run.collected.append(id)
	reward_collected = true
	session.sim.loadout.unlocked = run.unlocked.duplicate(true)
	experiment.record("rune_choice",{"room_index":run.sequence_index,"rune_index":index})
	logs.append({"kind":"reward","room":id,"item":option.duplicate(true)})
	return outcome

func move_after_clear(command: Dictionary) -> Dictionary:
	if state not in ["cleared","workshop"] or session.player.modal:
		return {"accepted":false,"reason":"NO_MOVEMENT"}
	# Only movement and aim are allowed between encounters.
	var safe: Dictionary = {"move":command.get("move",Vector2.ZERO),"aim":command.get("aim",Vector2.RIGHT),"cast":-1,"dodge":false}
	return session.player.process_command(safe)

func try_exit(position: Vector2) -> Dictionary:
	if editor != null and editor.allowed:
		return {"ok":false,"reason":"EDITOR_OPEN"}
	if state not in ["cleared","workshop"]:
		return {"ok":false,"reason":"DOOR_LOCKED"}
	if position.distance_to(room.marker("exit")) > 72.0:
		return {"ok":false,"reason":"EXIT_TOO_FAR"}
	if run.sequence_index >= config["rooms"].size()-1:
		return {"ok":false,"reason":"SLICE_COMPLETE"}
	if session != null and session.sim.actor.alive():
		if mode != "workshop":
			run.hp = session.sim.actor.health.current
			run.mana = session.sim.mana
	run.sequence_index += 1
	transition_count += 1
	var outcome: Dictionary = _enter_current()
	if outcome["ok"]:
		logs.append({"kind":"transition","index":run.sequence_index})
	return outcome

func enter_test_range() -> Dictionary:
	if mode != "workshop":
		return {"ok":false,"reason":"TEST_ONLY_WORKSHOP"}
	range_sim = Runner.new(run.seed)
	range_sim.loadout.unlocked = run.unlocked.duplicate(true)
	var result: Dictionary = range_sim.equip_starter_loadout(run.formulas)
	if not result["ok"]:
		return result
	range_sim.actor.health.maximum = float(config["workshop_restore_hp"])
	range_sim.actor.health.reset()
	range_sim.mana = float(config["workshop_restore_mana"])
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
	range_sim.mana = float(config["workshop_restore_mana"])
	return {"ok":true}

func test_cast(slot: int, direction: Vector2) -> Dictionary:
	if mode != "workshop" or range_sim == null:
		return {"accepted":false,"reason":"TEST_ONLY_WORKSHOP"}
	var result: Dictionary = range_sim.try_cast(slot,range_sim.actor.position,direction)
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
	editor = Editor.new(run,session.sim.registry)
	var result: Dictionary = editor.open(slot)
	if result["ok"]:
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
			return result
		var edit_slot: int = editor.slot
		session.sim.loadout.allow_edit = true
		session.sim.loadout.unlocked = run.unlocked.duplicate(true)
		var equipped: Dictionary = session.sim.equip(edit_slot+PRESET_SLOT_OFFSET,run.formulas[edit_slot])
		session.sim.loadout.allow_edit = false
		if not equipped["ok"]:
			return equipped
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
		experiment.record("purchase",{"room_index":run.sequence_index,"price":int(merchant.stock[index]["price"])})
		session.sim.loadout.unlocked = run.unlocked.duplicate(true)
		if outcome["kind"] == "upgrade":
			session.sim.actor.health.maximum = run.max_hp
			session.sim.actor.health.current = run.hp
	return outcome

func change_edit_policy(value: String) -> bool:
	if value not in ["workshop_only","cleared_room"]:
		return false
	edit_policy = value
	return true

func snapshot() -> Dictionary:
	return {"state":state,"room_id":room.values["id"],"index":run.sequence_index,
		"mode":mode,"door_open":state in ["cleared","workshop"],"rewards":reward_options.duplicate(true),
		"collected":reward_collected,"run":run.snapshot(),"boss_events":boss_defeated_events}

func recover(saved: Variant) -> Dictionary:
	var validated = State.new()
	var result: Dictionary = validated.restore(saved,session.sim.registry,config["rooms"].size())
	if not result["ok"]:
		return result
	run = validated
	return _enter_current()
