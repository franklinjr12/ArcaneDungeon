extends SceneTree
## AD-156: deterministic full-run (2-stage) benchmark. Scripted player only; no gameplay change.
## Run: godot --headless --path . --script res://tests/bench/run_bench.gd [-- --seeds=N --builds=weak,typical,skilled]
const Flow = preload("res://world/run_flow.gd")
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

func _initialize() -> void:
	call_deferred("_run")

func _option(prefix: String, fallback: String) -> String:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with(prefix):
			return arg.substr(prefix.length())
	return fallback

func _run() -> void:
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
		"starved_percent": _r(100.0 * starved / maxf(1.0, combat)), "rooms_cleared": flow.rooms_cleared, "rooms": rooms}

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
	var cheapest: float = _cheapest(session, slots)
	var cap: int = ROOM_CAP_SECONDS * rate
	var ticks := 0
	var starved := 0
	var casts: Dictionary = _cast_slots(flow)
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
		var used_before: int = flow.spells_used
		flow.step({"move": movement, "aim": view["direction"].rotated(jitter), "dash": dodge["dash"], "cast": slot,
			"cursor": view["actor"] + (view["cursor"] - view["actor"]).rotated(jitter)})
		ticks += 1
		if slot >= 0 and flow.spells_used > used_before:
			casts[str(slot)] += flow.spells_used - used_before
	var label: String = flow.state if flow.state in ["cleared", "won", "dead"] else "timeout"
	return {"outcome": label, "ticks": ticks, "sim_seconds": _r(float(ticks) / rate),
		"hp_lost": _r(hp_start - session.sim.actor.health.current), "mana_starved_ticks": starved, "casts": casts}

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
