extends SceneTree
## AD-156: deterministic full-run (2-stage) benchmark. Scripted player only; no gameplay change.
## AD-168: pacing diagnostics (report only): per room fight seconds, waves, enemy HP, player DPS, mana spent/regen, TTK per enemy kind,
## damage taken, boss seconds per phase and a scripted-player sanity check (hit rate, idle ticks). Printed as DIAG_MD_BEGIN/END.
## Run: godot --headless --path . --script res://tests/bench/run_bench.gd [-- --seeds=N|A..B --builds=weak,typical,skilled --results=DIR --trace]
## --seeds=A..B (0-based inclusive SEEDS indices) = chunk mode: one <seed>_<build>.json per play in --results (default user://bench_results), existing
## results with a matching fingerprint are skipped (resumable), no replay. --trace records sim traces (off by default; slower).
const Flow = preload("res://world/run_flow.gd")
const BalanceRunner = preload("res://magic/runtime/spell_runner.gd")
const SEEDS := [20261022, 20261023, 20261024, 20261025, 20261026, 20261027, 20261028, 20261029, 20261030, 20261031,
	20261032, 20261033, 20261034, 20261035, 20261036, 20261037, 20261038, 20261039, 20261040, 20261041]
## Reference builds. rune_pick: first = option 0, new_rune = first locked rune else option 0, priority = RUNE_PRIORITY.
## workshop: none = never edits, simple = water projectile + first earned modifier, best = best legal formulas for slots 0 and 1.
## buy: none, hp = max-HP upgrade only, priority = SHOP_PRIORITY. optional: takes the optional room at the door.
const BUILDS := {
	"weak": {"rune_pick": "first", "workshop": "none", "buy": "none", "optional": false},
	"typical": {"rune_pick": "new_rune", "workshop": "simple", "buy": "hp", "optional": true},
	"skilled": {"rune_pick": "priority", "workshop": "best", "buy": "priority", "optional": true},
}
const RUNE_PRIORITY := ["essence.water", "essence.lightning", "essence.cold", "mod.chain", "mod.pierce", "mod.homing",
	"form.burst", "mod.expand", "essence.force", "form.beam", "form.field", "mod.rapid", "trigger.on_hit"]
const SHOP_PRIORITY := ["upgrade.hp", "rune", "upgrade.mana", "upgrade.dash", "artifact"]
const ESSENCE_ORDER := ["essence.water", "essence.lightning", "essence.cold", "essence.fire"]
const SLOT_MODS := [["mod.chain", "mod.pierce", "mod.homing"], ["mod.expand", "mod.split"]]
const SLOT_FORMS := [["form.projectile"], ["form.burst", "form.projectile"]]
## Room cap: 6 minutes of sim time, so rooms over the 4 minute target stay visible.
const ROOM_CAP_SECONDS := 360
## Max angle error (radians) added to aim and cursor each tick; a human never aims perfectly.
const AIM_JITTER := 0.08
## Chance the player reacts to a telegraph/shot with a dash; the other threats are missed.
const DODGE_CHANCE := 0.7
## Ticks without moving before the bot sidesteps, and how long it holds the sidestep heading.
const NAV_TICKS := 6
## A player shoots a foe this close even when the sight check is blocked (sight uses padding).
const POINT_BLANK := 60.0
const STUCK_TICKS := 6
const NUDGE_TICKS := 12
## Demo Plan v1 section 2 targets.
const WIN_MIN_MINUTES := 30.0
const WIN_MAX_MINUTES := 40.0
const WEAK_DIES_EARLY_RATIO := 0.55
const ROOM_MAX_SECONDS := 240.0
const STARVED_MAX_PERCENT := 20.0

var _record_trace := true

func _initialize() -> void:
	call_deferred("_run")

func _option(prefix: String, fallback: String) -> String:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with(prefix):
			return arg.substr(prefix.length())
	return fallback

func _has_flag(flag: String) -> bool:
	return OS.get_cmdline_user_args().has(flag)

func _run() -> void:
	_record_trace = _has_flag("--trace")
	if ".." in _option("--seeds=", ""):
		_chunk()
		return
	var seeds: Array = SEEDS.slice(0, clampi(int(_option("--seeds=", str(SEEDS.size()))), 1, SEEDS.size()))
	var names: Array = []
	for build in _option("--builds=", ",".join(BUILDS.keys())).split(","):
		if BUILDS.has(build):
			names.append(build)
	if names.is_empty():
		printerr("AD_DEMO_BENCH no valid builds selected")
		quit(1)
		return
	var runs: Array = []
	for build in names:
		for run_seed in seeds:
			runs.append(_play(int(run_seed), build))
	for build in names:
		var again: Dictionary = _play(int(seeds[0]), build)
		var first: Dictionary = runs.filter(func(r): return r["build"] == build)[0]
		if JSON.stringify(first, "", true) != JSON.stringify(again, "", true):
			printerr("AD_DEMO_BENCH nondeterministic: %s seed %d differs" % [build, seeds[0]])
			quit(1)
			return
	var result := {"seeds": seeds, "builds": names, "runs": runs}
	print("AD_DEMO_BENCH:" + JSON.stringify(result, "", true))
	print("BENCH_MD_BEGIN")
	print(_markdown(result))
	print("BENCH_MD_END")
	print("DIAG_MD_BEGIN")
	print(_diag_markdown(result))
	print("DIAG_MD_END")
	quit(0)

func _fingerprint() -> String:
	var paths: Array = []
	for dir in ["res://world/data", "res://combat"]:
		var names := Array(DirAccess.get_files_at(dir)).filter(func(n): return n.ends_with(".json"))
		names.sort()
		for n in names:
			paths.append(dir + "/" + n)
	paths.append_array([BalanceRunner.CONFIG, "res://tests/bench/run_bench.gd"])
	var text := ""
	for path in paths:
		text += FileAccess.get_md5(path)
	return text.md5_text()

func _chunk() -> void:
	var span: PackedStringArray = _option("--seeds=", "").split("..")
	if span.size() != 2 or not span[0].is_valid_int() or not span[1].is_valid_int() or int(span[0]) < 0 or int(span[1]) < int(span[0]) or int(span[1]) >= SEEDS.size():
		printerr("AD_DEMO_BENCH bad --seeds=A..B (0-based inclusive, max %d)" % (SEEDS.size() - 1))
		quit(1)
		return
	var names: Array = []
	for build in _option("--builds=", ",".join(BUILDS.keys())).split(","):
		if BUILDS.has(build):
			names.append(build)
	if names.is_empty():
		printerr("AD_DEMO_BENCH no valid builds selected")
		quit(1)
		return
	var dir := ProjectSettings.globalize_path(_option("--results=", "user://bench_results"))
	DirAccess.make_dir_recursive_absolute(dir)
	var print_id := _fingerprint()
	for build in names:
		for i in range(int(span[0]), int(span[1]) + 1):
			var run_seed: int = SEEDS[i]
			var path := "%s/%d_%s.json" % [dir, run_seed, build]
			if FileAccess.file_exists(path):
				var old = JSON.parse_string(FileAccess.get_file_as_string(path))
				if old is Dictionary and old.get("fingerprint", "") == print_id:
					print("AD_DEMO_BENCH_SKIP seed=%d build=%s" % [run_seed, build])
					continue
			var started := Time.get_ticks_msec()
			var run: Dictionary = _play(run_seed, build)
			var wall: float = (Time.get_ticks_msec() - started) / 1000.0
			var file := FileAccess.open(path + ".tmp", FileAccess.WRITE)
			if file == null:
				printerr("AD_DEMO_BENCH cannot write " + path)
				quit(1)
				return
			file.store_string(JSON.stringify({"fingerprint": print_id, "trace": _record_trace, "wall_seconds": wall, "run": run}, "\t", true))
			file.close()
			if DirAccess.rename_absolute(path + ".tmp", path) != OK:
				printerr("AD_DEMO_BENCH cannot rename " + path)
				quit(1)
				return
			print("AD_DEMO_BENCH_WALL seed=%d build=%s wall_s=%.1f outcome=%s" % [run_seed, build, wall, run["outcome"]])
	quit(0)

func _r(value: float) -> float:
	return snappedf(value, 0.001)

func _bot(run_seed: int, build: String) -> Dictionary:
	var rng := RandomNumberGenerator.new()
	rng.seed = ("%d:%s" % [run_seed, build]).hash()
	return {"rng": rng, "roll": -1, "last": Vector2.INF, "stuck": 0, "nudge_left": 0, "nudges": 0, "nav_age": 0, "nav": Vector2.ZERO}

func _play(run_seed: int, build: String) -> Dictionary:
	var flow = Flow.new(run_seed, Flow.CONFIG_V2)
	var plan: Dictionary = BUILDS[build]
	var bot: Dictionary = _bot(run_seed, build)
	var rooms: Array = []
	var earned: Array = []
	var outcome := "won"
	var rate: int = flow.session.sim.clock.tick_rate
	while true:
		var rec: Dictionary = _enter(flow, plan, earned, rate, bot)
		rooms.append(rec)
		if rec["outcome"] == "dead" or rec["outcome"] == "timeout":
			outcome = rec["outcome"]
			break
		if flow.state == "won":
			break
		var left: Dictionary = _leave(flow, plan, rec, bot)
		if not left.get("ok", false):
			outcome = "error"
			break
	return _record(flow, run_seed, build, outcome, rooms, rate)

func _enter(flow, plan: Dictionary, earned: Array, rate: int, bot: Dictionary) -> Dictionary:
	var index: int = flow.run.sequence_index
	flow.session.sim.trace.enabled = _record_trace
	var rec := {"room": str(flow.room.values["id"]), "stage": int(flow.rooms[index].get("stage", 0)),
		"type": str(flow.room.values["type"]), "outcome": "cleared", "ticks": 0, "sim_seconds": 0.0, "hp_lost": 0.0,
		"mana_starved_ticks": 0, "walk_ticks": 0, "casts": _cast_slots(flow)}
	if flow.state == "workshop":
		rec["outcome"] = "workshop"
		_workshop(flow, plan, earned)
		return rec
	if flow.state == "fighting":
		rec.merge(_fight(flow, rate, bot), true)
	if flow.state == "cleared" and not flow.reward_collected and flow.room.values["type"] != "boss":
		_pick(flow, plan, earned)
	return rec

func _cast_slots(flow) -> Dictionary:
	var casts: Dictionary = {}
	for slot in flow.session.sim.loadout.slots.size():
		casts[str(slot)] = 0
	return casts

func _leave(flow, plan: Dictionary, rec: Dictionary, bot: Dictionary) -> Dictionary:
	if flow.state == "workshop":
		return flow.try_exit(flow.session.sim.actor.position, plan["optional"])
	var walked: Dictionary = _reach_exit(flow, plan["optional"], bot)
	rec["walk_ticks"] = walked.get("walked", 0)
	return walked

func _record(flow, run_seed: int, build: String, outcome: String, rooms: Array, rate: int) -> Dictionary:
	var ticks := 0
	var combat := 0
	var starved := 0
	var longest := 0
	for rec in rooms:
		ticks += rec["ticks"] + rec["walk_ticks"]
		combat += rec["ticks"]
		starved += rec["mana_starved_ticks"]
		longest = maxi(longest, rec["ticks"])
	var last: Dictionary = rooms.back()
	var died_in := ""
	if outcome == "dead" or outcome == "timeout":
		died_in = "stage%d_%s" % [int(last["stage"]) + 1, "boss" if last["type"] == "boss" else "rooms"]
	return {"seed": run_seed, "build": build, "outcome": outcome, "death_room": last["room"] if died_in != "" else "",
		"died_in": died_in, "total_seconds": _r(float(ticks) / rate), "max_room_seconds": _r(float(longest) / rate),
		"starved_percent": _r(100.0 * starved / maxf(1.0, combat)), "rooms_cleared": flow.rooms_cleared, "tick_rate": rate, "rooms": rooms}

func _pick(flow, plan: Dictionary, earned: Array) -> void:
	var index := 0
	var options: Array = flow.reward_options
	if plan["rune_pick"] == "new_rune":
		index = _first_rune(flow, options)
	elif plan["rune_pick"] == "priority":
		index = _priority_rune(flow, options)
	var option: Dictionary = options[index]
	if flow.choose_reward(index).get("ok", false) and option["kind"] == "rune":
		earned.append(str(option["id"]))

func _first_rune(flow, options: Array) -> int:
	for i in options.size():
		if options[i]["kind"] == "rune" and not (str(options[i]["id"]) in flow.run.unlocked):
			return i
	return 0

func _priority_rune(flow, options: Array) -> int:
	var best := -1
	var best_rank := RUNE_PRIORITY.size() + 1
	for i in options.size():
		var id := str(options[i].get("id", ""))
		if options[i]["kind"] != "rune" or id in flow.run.unlocked:
			continue
		var rank: int = RUNE_PRIORITY.find(id)
		rank = RUNE_PRIORITY.size() if rank < 0 else rank
		if rank < best_rank:
			best = i
			best_rank = rank
	return _first_rune(flow, options) if best < 0 else best

func _workshop(flow, plan: Dictionary, earned: Array) -> void:
	if plan["buy"] != "none":
		_shop(flow, plan["buy"])
	if plan["workshop"] == "simple":
		_simple_edit(flow, earned)
	elif plan["workshop"] == "best":
		for slot in 2:
			_best_edit(flow, slot)

func _shop(flow, mode: String) -> void:
	var order: Array = ["upgrade.hp"] if mode == "hp" else SHOP_PRIORITY
	for kind in order:
		for i in flow.merchant.stock.size():
			var item: Dictionary = flow.merchant.stock[i]
			if str(item["id"]) == kind or str(item["kind"]) == kind:
				flow.buy(i)

func _simple_edit(flow, earned: Array) -> void:
	if not flow.open_editor(0).get("ok", false):
		return
	var editor = flow.editor
	var essence := "essence.water"
	if essence in flow.run.unlocked:
		editor.set_root(essence, "form.projectile")
	for id in earned:
		if id.begins_with("mod."):
			editor.toggle_modifier(id)
			break
	_close(flow, editor.validate()["ok"])

func _close(flow, valid: bool) -> void:
	if not valid or not flow.close_editor(true, 0.0).get("ok", false):
		if flow.editor.allowed:
			flow.close_editor(false, 0.0)

func _candidates(flow, slot: int) -> Array:
	var essences: Array = ESSENCE_ORDER.filter(func(id): return id in flow.run.unlocked)
	var mods: Array = SLOT_MODS[slot].filter(func(id): return id in flow.run.unlocked)
	var out: Array = []
	if essences.is_empty():
		return out
	for form in SLOT_FORMS[slot]:
		for n in range(mods.size(), -1, -1):
			out.append({"essence": essences[slot % essences.size()], "form": form, "mods": mods.slice(0, n)})
	return out

func _best_edit(flow, slot: int) -> void:
	for candidate in _candidates(flow, slot):
		if not flow.open_editor(slot).get("ok", false):
			return
		flow.editor.set_root(candidate["essence"], candidate["form"])
		for id in candidate["mods"]:
			flow.editor.toggle_modifier(id)
		var valid: bool = flow.editor.validate()["ok"]
		_close(flow, valid)
		if valid:
			return
	if flow.editor != null and flow.editor.allowed:
		flow.close_editor(false, 0.0)

func _cheapest(session, slots: int) -> float:
	var cheapest := INF
	for idx in slots:
		var spell = session.sim.loadout.get_plan(idx)
		if spell != null:
			cheapest = minf(cheapest, float(spell.snapshot()["mana_cost"]))
	return cheapest

func _view(session, bot: Dictionary) -> Dictionary:
	var actor: Vector2 = session.sim.actor.position
	var foe = _nearest(session)
	var view := {"foe": foe, "actor": actor, "cursor": actor + Vector2.RIGHT * 130, "distance": INF,
		"direction": Vector2.RIGHT, "sight": false, "movement": Vector2.ZERO}
	if foe == null:
		return view
	view["cursor"] = foe.target.position
	var displacement: Vector2 = foe.target.position - actor
	view["distance"] = displacement.length()
	view["direction"] = displacement.normalized() if not displacement.is_zero_approx() else Vector2.RIGHT
	view["sight"] = session.world.clear_sight(actor, foe.target.position, 8)
	view["movement"] = _kite(session, view, bot)
	return view

func _kite(session, view: Dictionary, bot: Dictionary) -> Vector2:
	if view["distance"] > 220 or not view["sight"]:
		return _navigate(session, bot, view["actor"], view["cursor"])
	if view["distance"] < 120:
		return -view["direction"]
	return view["direction"].rotated(PI / 2.0) * 0.4

## Path-finding is re-planned every NAV_TICKS ticks (a player re-aims about that often); between plans the last heading holds.
func _navigate(session, bot: Dictionary, from: Vector2, to: Vector2) -> Vector2:
	if bot["nav_age"] % NAV_TICKS == 0 or bot["nav"].is_zero_approx():
		bot["nav"] = session.world.navigate_direction(from, to, session.sim.actor.radius)
	bot["nav_age"] += 1
	return bot["nav"]

## Steps around a corner the navigation misjudges: after STUCK_TICKS without moving, walk a fixed compass heading for NUDGE_TICKS.
func _nudge(bot: Dictionary, point: Vector2, movement: Vector2) -> Vector2:
	bot["stuck"] = bot["stuck"] + 1 if point.is_equal_approx(bot["last"]) and not movement.is_zero_approx() else 0
	bot["last"] = point
	if bot["stuck"] >= STUCK_TICKS and bot["nudge_left"] == 0:
		bot["nudge_left"] = NUDGE_TICKS
		bot["nudges"] += 1
	if bot["nudge_left"] > 0:
		bot["nudge_left"] -= 1
		return Vector2.UP.rotated(bot["nudges"] * PI / 4.0)
	return movement

## Dash on a close telegraph or shot; the decision is rolled once per threat so DODGE_CHANCE is not retried every tick.
func _dodge(session, view: Dictionary, bot: Dictionary) -> Dictionary:
	var threat := Vector2.ZERO
	if session.player.dash_cooldown == 0:
		threat = _threat(session, view)
	if threat == Vector2.ZERO:
		bot["roll"] = -1
		return {"dash": false}
	if bot["roll"] < 0:
		bot["roll"] = 1 if bot["rng"].randf() < DODGE_CHANCE else 0
	return {"dash": bot["roll"] == 1, "movement": threat}

func _threat(session, view: Dictionary) -> Vector2:
	var actor: Vector2 = view["actor"]
	for enemy in session.enemies:
		if enemy.target.alive() and enemy.state == "windup":
			var deadline: int = int(enemy.tuning["telegraph_ticks"]) - enemy.state_tick
			if deadline <= 7 and actor.distance_to(enemy.target.position) < float(enemy.tuning["attack_range"]) + 65:
				return view["direction"].rotated(PI / 2.0)
	for shot in session.enemy_shots:
		if actor.distance_to(shot["position"]) < 110:
			return shot["direction"].rotated(PI / 2.0)
	return Vector2.ZERO

func _choose_slot(session, view: Dictionary, iteration: int, slots: int) -> int:
	if view["foe"] == null or session.player.dash_left != 0 or session.player.recovery_left != 0:
		return -1
	for k in slots - 1:
		var idx: int = 1 + (iteration + k) % (slots - 1)
		if session.sim.loadout.slots[idx]["cooldown"] > 0:
			continue
		var spell = session.sim.loadout.get_plan(idx)
		if spell != null and session.sim.mana >= float(spell.snapshot()["mana_cost"]) and _fits(session, view, spell):
			return idx
	var bolt = session.sim.loadout.get_plan(0)
	if (view["sight"] or view["distance"] < POINT_BLANK) and bolt != null and session.sim.loadout.slots[0]["cooldown"] == 0 and session.sim.mana >= float(bolt.snapshot()["mana_cost"]):
		return 0
	return -1

func _fits(session, view: Dictionary, spell) -> bool:
	var form: String = str(spell.snapshot()["root"]["manifestation"]["id"])
	if form == "form.projectile":
		return view["sight"]
	if form == "form.burst":
		return view["sight"] and view["distance"] <= float(session.data["player"]["max_burst_distance"]) - 10
	if form == "form.orb":
		return view["distance"] < 160
	return view["sight"] and view["distance"] < 320

func _fight(flow, rate: int, bot: Dictionary) -> Dictionary:
	var session = flow.session
	var slots: int = session.sim.loadout.slots.size()
	var hp_start: float = session.sim.actor.health.current
	var received_start: float = session.damage_received
	var cheapest: float = _cheapest(session, slots)
	var cap: int = ROOM_CAP_SECONDS * rate
	var ticks := 0
	var starved := 0
	var casts: Dictionary = _cast_slots(flow)
	var obs := {"seen": [], "ids": {}, "dealt": 0.0, "hits": 0, "spent": 0.0, "regen": 0.0, "idle": 0, "no_sight": 0, "phase": {}}
	_observe(session, obs, 0)
	for iteration in cap:
		if flow.state != "fighting":
			break
		var view: Dictionary = _view(session, bot)
		var dodge: Dictionary = _dodge(session, view, bot)
		var movement: Vector2 = dodge["movement"] if dodge["dash"] else _nudge(bot, view["actor"], view["movement"])
		var jitter: float = bot["rng"].randf_range(-AIM_JITTER, AIM_JITTER)
		var slot: int = _choose_slot(session, view, iteration, slots)
		if session.sim.mana < cheapest:
			starved += 1
		var mana_before: float = session.sim.mana
		if view["foe"] != null:
			if not view["sight"]:
				obs["no_sight"] += 1
			if slot < 0 and not dodge["dash"] and mana_before >= cheapest:
				obs["idle"] += 1
		var used_before: int = flow.spells_used
		flow.step({"move": movement, "aim": view["direction"].rotated(jitter), "dash": dodge["dash"], "cast": slot,
			"cursor": view["actor"] + (view["cursor"] - view["actor"]).rotated(jitter)})
		ticks += 1
		var mana_delta: float = session.sim.mana - mana_before
		obs["spent" if mana_delta < 0.0 else "regen"] += absf(mana_delta)
		_observe(session, obs, ticks)
		if slot >= 0 and flow.spells_used > used_before:
			casts[str(slot)] += flow.spells_used - used_before
	var label: String = flow.state if flow.state in ["cleared", "won", "dead"] else "timeout"
	var seconds: float = float(ticks) / rate
	var total_casts := 0
	for key in casts:
		total_casts += int(casts[key])
	var total_hp := 0.0
	var ttk_samples := {}
	for entry in obs["seen"]:
		total_hp += entry["max"]
		if entry["death"] >= 0:
			if not ttk_samples.has(entry["kind"]):
				ttk_samples[entry["kind"]] = []
			ttk_samples[entry["kind"]].append(_r(float(entry["death"] - entry["born"]) / rate))
	var kinds: Array = ttk_samples.keys()
	kinds.sort()
	var ttk_by_kind := {}
	var ttk_sorted := {}
	for kind in kinds:
		var st: Dictionary = _stats(ttk_samples[kind])
		ttk_by_kind[kind] = {"n": st["n"], "median": st["median"]}
		ttk_sorted[kind] = ttk_samples[kind]
	var phases := {}
	var phase_keys: Array = obs["phase"].keys()
	phase_keys.sort()
	for key in phase_keys:
		phases[str(key)] = _r(float(obs["phase"][key]) / rate)
	# Waves = encounter director launches (wave_spawn entries); rooms without a director report 0.
	var waves: int = flow.encounter.launched.size() if flow.encounter != null else 0
	var denom: float = maxf(0.001, seconds)
	# hits = (enemy, tick) pairs where an enemy lost HP; mana deltas are net per tick (cost and regen in one tick merge).
	return {"outcome": label, "ticks": ticks, "sim_seconds": _r(seconds),
		"hp_lost": _r(hp_start - session.sim.actor.health.current), "mana_starved_ticks": starved, "casts": casts,
		"fight_seconds": _r(seconds), "waves_spawned": waves, "enemies_spawned": obs["seen"].size(), "total_enemy_hp": _r(total_hp),
		"damage_dealt": _r(obs["dealt"]), "player_dps": _r(obs["dealt"] / denom), "mana_spent": _r(obs["spent"]),
		"mana_regen": _r(obs["regen"]), "mana_regen_per_s": _r(obs["regen"] / denom), "ttk_by_kind": ttk_by_kind,
		"ttk_samples": ttk_sorted, "damage_taken": _r(session.damage_received - received_start), "boss_phase_seconds": phases,
		"hits": obs["hits"], "hit_rate": _r(float(obs["hits"]) / maxf(1.0, float(total_casts))), "idle_ticks": obs["idle"],
		"no_sight_ticks": obs["no_sight"], "idle_percent": _r(100.0 * obs["idle"] / maxf(1.0, float(ticks))),
		"no_sight_percent": _r(100.0 * obs["no_sight"] / maxf(1.0, float(ticks)))}

## Read-only observation after each step: registers new enemies, sums HP lost per enemy, notes deaths and boss phase seconds.
func _observe(session, obs: Dictionary, tick: int) -> void:
	for enemy in session.enemies:
		var id: int = enemy.target.id
		if not obs["ids"].has(id):
			obs["ids"][id] = obs["seen"].size()
			obs["seen"].append({"enemy": enemy, "kind": str(enemy.kind), "born": tick, "max": enemy.target.health.maximum,
				"hp": enemy.target.health.current, "death": -1})
	if tick == 0:
		return
	for entry in obs["seen"]:
		var enemy = entry["enemy"]
		var current: float = enemy.target.health.current
		if current < entry["hp"]:
			obs["dealt"] += entry["hp"] - current
			obs["hits"] += 1
		entry["hp"] = current
		if entry["death"] < 0 and not enemy.target.alive():
			entry["death"] = tick
		var phase = enemy.get("phase")
		if phase != null and enemy.target.alive():
			obs["phase"][int(phase)] = obs["phase"].get(int(phase), 0) + 1

## Walking ticks count toward total sim time (reported as walk_ticks).
func _reach_exit(flow, take_optional: bool, bot: Dictionary, max_ticks: int = 1100) -> Dictionary:
	var exit_point: Vector2 = flow.room.marker("exit")
	for i in max_ticks:
		if flow.session.sim.actor.position.distance_to(exit_point) <= 65:
			var result: Dictionary = flow.try_exit(flow.session.sim.actor.position, take_optional)
			result["walked"] = i
			return result
		var point: Vector2 = flow.session.sim.actor.position
		var direction: Vector2 = _navigate(flow.session, bot, point, exit_point)
		flow.move_after_clear({"move": _nudge(bot, point, direction), "aim": direction})
	return {"ok": false, "reason": "EXIT_NAV_TIMEOUT", "walked": max_ticks}

func _nearest(session):
	var target = null
	var best := INF
	for enemy in session.enemies:
		if not enemy.target.alive():
			continue
		var point: Vector2 = enemy.target.position
		var length: float = point.distance_squared_to(session.sim.actor.position)
		var los: bool = session.world.clear_sight(point, session.sim.actor.position, 8)
		var weighted := length + (50000 if not los else 0)
		if weighted < best:
			best = weighted
			target = enemy
	return target

func _stats(values: Array) -> Dictionary:
	if values.is_empty():
		return {"n": 0, "median": 0, "min": 0, "max": 0}
	var sorted: Array = values.duplicate()
	sorted.sort()
	var n: int = sorted.size()
	var median: float = float(sorted[n / 2]) if n % 2 == 1 else (float(sorted[n / 2 - 1]) + float(sorted[n / 2])) / 2.0
	return {"n": n, "median": _r(median), "min": _r(float(sorted[0])), "max": _r(float(sorted[n - 1]))}

func _of(runs: Array, build: String) -> Array:
	return runs.filter(func(r): return r["build"] == build)

func _col(runs: Array, key: String) -> Array:
	return runs.map(func(r): return r[key])

func _wins(runs: Array) -> Array:
	return runs.filter(func(r): return r["outcome"] == "won")

func _early_deaths(runs: Array) -> int:
	return runs.filter(func(r): return r["died_in"] in ["stage1_rooms", "stage1_boss"]).size()

func _pass(ok: bool) -> String:
	return "PASS" if ok else "NO"

func _markdown(result: Dictionary) -> String:
	var lines: Array = []
	lines.append_array(_seed_table(result))
	lines.append_array(_summary_table(result))
	lines.append_array(_target_table(result))
	lines.append_array(_room_table(result["runs"]))
	return "\n".join(lines)

func _seed_table(result: Dictionary) -> Array:
	var lines: Array = []
	for build in result["builds"]:
		lines.append("**%s**" % build)
		lines.append("")
		lines.append("| seed | outcome | died in | total min | max room s | starved % | rooms cleared |")
		lines.append("|---|---|---|---|---|---|---|")
		for r in _of(result["runs"], build):
			lines.append("| %d | %s | %s | %s | %s | %s | %d |" % [r["seed"], r["outcome"], r["died_in"] if r["died_in"] != "" else "-",
				_r(r["total_seconds"] / 60.0), r["max_room_seconds"], r["starved_percent"], r["rooms_cleared"]])
		lines.append("")
	return lines

func _summary_table(result: Dictionary) -> Array:
	var lines: Array = ["| build | wins | win total min (median/min/max) | dies stage 1 or first boss | max room s | starved % median | starved % max |",
		"|---|---|---|---|---|---|---|"]
	for build in result["builds"]:
		var runs: Array = _of(result["runs"], build)
		var wins: Array = _wins(runs)
		var minutes: Dictionary = _stats(_col(wins, "total_seconds").map(func(s): return s / 60.0))
		var starved: Dictionary = _stats(_col(runs, "starved_percent"))
		lines.append("| %s | %d/%d | %s | %d/%d | %s | %s | %s |" % [build, wins.size(), runs.size(),
			"-" if wins.is_empty() else "%s / %s / %s" % [minutes["median"], minutes["min"], minutes["max"]],
			_early_deaths(runs), runs.size(), _stats(_col(runs, "max_room_seconds"))["max"], starved["median"], starved["max"]])
	lines.append("")
	return lines

func _target_table(result: Dictionary) -> Array:
	var lines: Array = ["| target | weak | typical | skilled |", "|---|---|---|---|"]
	var win_row: Array = []
	var weak_row: Array = []
	var room_row: Array = []
	var mana_row: Array = []
	for build in ["weak", "typical", "skilled"]:
		var runs: Array = _of(result["runs"], build)
		if runs.is_empty():
			win_row.append("n/a")
			weak_row.append("n/a")
			room_row.append("n/a")
			mana_row.append("n/a")
			continue
		var wins: Array = _wins(runs)
		var med: float = _stats(_col(wins, "total_seconds"))["median"] / 60.0
		win_row.append("n/a" if build == "weak" else "%s (median %s min, %d wins)" % [_pass(not wins.is_empty() and med >= WIN_MIN_MINUTES and med <= WIN_MAX_MINUTES), _r(med), wins.size()])
		var need: int = ceili(WEAK_DIES_EARLY_RATIO * runs.size())
		weak_row.append("%s (%d/%d dead early, need %d)" % [_pass(_early_deaths(runs) >= need), _early_deaths(runs), runs.size(), need] if build == "weak" else "n/a")
		var longest: float = _stats(_col(runs, "max_room_seconds"))["max"]
		room_row.append("%s (max %s s)" % [_pass(longest <= ROOM_MAX_SECONDS), longest])
		var starved: float = _stats(_col(runs, "starved_percent"))["median"]
		mana_row.append("%s (median %s%%)" % [_pass(starved < STARVED_MAX_PERCENT), starved])
	lines.append("| winning run 30-40 min sim | " + " | ".join(win_row) + " |")
	lines.append("| weak build dies in stage 1 or at the first boss on most seeds | " + " | ".join(weak_row) + " |")
	lines.append("| no room > 4 min | " + " | ".join(room_row) + " |")
	lines.append("| mana-starved < 20% | " + " | ".join(mana_row) + " |")
	lines.append("")
	return lines

func _room_table(runs: Array) -> Array:
	var by_room: Dictionary = {}
	for r in runs:
		for rec in r["rooms"]:
			if rec["ticks"] == 0:
				continue
			if not by_room.has(rec["room"]):
				by_room[rec["room"]] = {"s": [], "h": []}
			by_room[rec["room"]]["s"].append(rec["sim_seconds"])
			by_room[rec["room"]]["h"].append(rec["hp_lost"])
	var ids: Array = by_room.keys()
	ids.sort()
	var lines: Array = ["| room | n | median s | min s | max s | median HP lost | min HP lost | max HP lost |", "|---|---|---|---|---|---|---|---|"]
	for id in ids:
		var a: Dictionary = _stats(by_room[id]["s"])
		var h: Dictionary = _stats(by_room[id]["h"])
		lines.append("| %s | %d | %s | %s | %s | %s | %s | %s |" % [id, a["n"], a["median"], a["min"], a["max"], h["median"], h["min"], h["max"]])
	return lines

## --- AD-168 diagnostics -------------------------------------------------------------------------------------------

func _fought(runs: Array) -> Array:
	var out: Array = []
	for r in runs:
		for rec in r["rooms"]:
			if rec["ticks"] > 0:
				out.append(rec)
	return out

func _cell(values: Array) -> String:
	var st: Dictionary = _stats(values)
	return "%s / %s / %s" % [st["median"], st["min"], st["max"]]

func _diag_markdown(result: Dictionary) -> String:
	var lines: Array = ["Cells show median / min / max over the seeds unless noted.", ""]
	for build in result["builds"]:
		var runs: Array = _of(result["runs"], build)
		lines.append("### %s" % build)
		lines.append("")
		lines.append_array(_diag_rooms(runs))
		lines.append_array(_diag_kinds(runs))
		lines.append_array(_diag_bosses(runs))
		lines.append_array(_diag_sanity(runs))
		lines.append_array(_diag_totals(runs))
	return "\n".join(lines)

func _diag_rooms(runs: Array) -> Array:
	var by_room: Dictionary = {}
	for rec in _fought(runs):
		if not by_room.has(rec["room"]):
			by_room[rec["room"]] = []
		by_room[rec["room"]].append(rec)
	var ids: Array = by_room.keys()
	ids.sort()
	var lines: Array = ["Per room:", "", "| room | n | fight s | waves | enemies | enemy HP | player DPS | dmg taken | mana spent | mana regen | starved % |",
		"|---|---|---|---|---|---|---|---|---|---|---|"]
	for id in ids:
		var recs: Array = by_room[id]
		var starved: Array = recs.map(func(r): return 100.0 * r["mana_starved_ticks"] / maxf(1.0, float(r["ticks"])))
		lines.append("| %s | %d | %s | %s | %s | %s | %s | %s | %s | %s | %s |" % [id, recs.size(), _cell(_key(recs, "fight_seconds")),
			_cell(_key(recs, "waves_spawned")), _cell(_key(recs, "enemies_spawned")), _cell(_key(recs, "total_enemy_hp")),
			_cell(_key(recs, "player_dps")), _cell(_key(recs, "damage_taken")), _cell(_key(recs, "mana_spent")),
			_cell(_key(recs, "mana_regen")), _cell(starved)])
	lines.append("")
	return lines

func _key(recs: Array, key: String) -> Array:
	return recs.map(func(r): return r[key])

func _diag_kinds(runs: Array) -> Array:
	var by_kind: Dictionary = {}
	for rec in _fought(runs):
		for kind in rec["ttk_samples"]:
			if not by_kind.has(kind):
				by_kind[kind] = []
			by_kind[kind].append_array(rec["ttk_samples"][kind])
	var kinds: Array = by_kind.keys()
	kinds.sort()
	var lines: Array = ["Time to kill per enemy kind (seconds from first sight to death):", "", "| kind | killed | TTK s (median / min / max) |", "|---|---|---|"]
	for kind in kinds:
		lines.append("| %s | %d | %s |" % [kind, by_kind[kind].size(), _cell(by_kind[kind])])
	lines.append("")
	return lines

func _diag_bosses(runs: Array) -> Array:
	var by_room: Dictionary = {}
	for rec in _fought(runs):
		if rec["boss_phase_seconds"].is_empty():
			continue
		if not by_room.has(rec["room"]):
			by_room[rec["room"]] = {}
		for phase in rec["boss_phase_seconds"]:
			if not by_room[rec["room"]].has(phase):
				by_room[rec["room"]][phase] = []
			by_room[rec["room"]][phase].append(rec["boss_phase_seconds"][phase])
	var ids: Array = by_room.keys()
	ids.sort()
	var lines: Array = ["Boss seconds per phase (rooms with a phased enemy; mini-bosses included):", "", "| room | phase | n | s (median / min / max) |", "|---|---|---|---|"]
	for id in ids:
		var phases: Array = by_room[id].keys()
		phases.sort()
		for phase in phases:
			lines.append("| %s | %s | %d | %s |" % [id, phase, by_room[id][phase].size(), _cell(by_room[id][phase])])
	lines.append("")
	return lines

func _diag_sanity(runs: Array) -> Array:
	var hit: Array = []
	var idle: Array = []
	var no_sight: Array = []
	var casts := 0
	var ticks := 0
	for r in runs:
		var fought: Array = _fought([r])
		var r_ticks := 0
		var r_idle := 0
		var r_sight := 0
		var r_hits := 0
		var r_casts := 0
		for rec in fought:
			r_ticks += rec["ticks"]
			r_idle += rec["idle_ticks"]
			r_sight += rec["no_sight_ticks"]
			r_hits += rec["hits"]
			for key in rec["casts"]:
				r_casts += int(rec["casts"][key])
		hit.append(float(r_hits) / maxf(1.0, float(r_casts)))
		idle.append(100.0 * r_idle / maxf(1.0, float(r_ticks)))
		no_sight.append(100.0 * r_sight / maxf(1.0, float(r_ticks)))
		casts += r_casts
		ticks += r_ticks
	var rate: float = 60.0
	if not runs.is_empty() and not runs[0]["rooms"].is_empty():
		rate = maxf(1.0, float(_tick_rate_of(runs[0])))
	return ["Scripted player sanity (hits = enemy-lost-HP events per tick, so a pierce/burst can exceed 1 per cast):", "",
		"| hit rate median | idle % median (foe alive, no cast, no dash, mana ok) | no-sight % median | casts per combat minute |", "|---|---|---|---|",
		"| %s | %s | %s | %s |" % [_stats(hit)["median"], _stats(idle)["median"], _stats(no_sight)["median"],
		_r(float(casts) / maxf(0.001, float(ticks) / rate / 60.0))], ""]

func _tick_rate_of(run: Dictionary) -> int:
	return int(run.get("tick_rate", 60))

func _diag_totals(runs: Array) -> Array:
	var rate: float = float(_tick_rate_of(runs[0])) if not runs.is_empty() else 60.0
	var total: Array = []
	var combat: Array = []
	var walk: Array = []
	var spent: Array = []
	var regen: Array = []
	var hp: Array = []
	var dps: Array = []
	for r in runs:
		var c := 0
		var w := 0
		var sp := 0.0
		var rg := 0.0
		var h := 0.0
		var dealt := 0.0
		for rec in r["rooms"]:
			c += rec["ticks"]
			w += rec["walk_ticks"]
			if rec["ticks"] > 0:
				sp += rec["mana_spent"]
				rg += rec["mana_regen"]
				h += rec["total_enemy_hp"]
				dealt += rec["damage_dealt"]
		total.append(r["total_seconds"] / 60.0)
		combat.append(c / rate / 60.0)
		walk.append(w / rate / 60.0)
		spent.append(sp)
		regen.append(rg)
		hp.append(h)
		dps.append(dealt / maxf(0.001, c / rate))
	return ["Run totals:", "", "| total min | combat min | walk min | mana spent | mana regen | enemy HP faced | overall DPS |", "|---|---|---|---|---|---|---|",
		"| %s | %s | %s | %s | %s | %s | %s |" % [_cell(total), _cell(combat), _cell(walk), _cell(spent), _cell(regen), _cell(hp), _cell(dps)], ""]
