extends SceneTree
## Headless run-length / difficulty report driven by the baseline bot (tests/m3_run_driver.gd).
## Usage: godot --headless --path . --script res://tools/run_length_report.gd -- [--seeds a,b,c] [--out path] [--check-determinism]
## Default seeds (20): 20261022, then 20261023..20261041.
## Exit codes: 0 ok, 1 nondeterminism, 2 flow init/transition failure.
## Note: walk_ticks (exit navigation) is not reported; Driver.reach_exit does not expose per-tick hooks.
const Flow = preload("res://world/run_flow.gd")
const Driver = preload("res://tests/m3_run_driver.gd")
const FIGHT_CAP := 20000

var _failed := false
var _hp_prev := 0.0
var _damage := 0.0

func _initialize() -> void:
	call_deferred("_run")

func _on_tick(flow) -> void:
	var hp: float = flow.session.sim.actor.health.current
	if hp < _hp_prev:
		_damage += _hp_prev - hp
	_hp_prev = hp

func _r(value: float) -> float:
	return snappedf(value, 0.001)

func _run_seed(seed_value: int) -> Dictionary:
	var started := Time.get_ticks_msec()
	var flow = Flow.new(seed_value)
	var rooms: Array = []
	var picks: Array = []
	var total_damage := 0.0
	var deaths := 0
	var status := "completed"
	var boss_id := ""
	var boss_seconds := 0.0
	var buy_result = null
	var count: int = flow.config["rooms"].size()
	for i in count:
		if flow.mode != "workshop":
			var rid := str(flow.room.values["id"])
			var rtype := str(flow.room.values["type"])
			var tick_rate: float = float(flow.session.sim.clock.tick_rate)
			var start_tick: int = flow.session.sim.clock.tick
			_hp_prev = flow.session.sim.actor.health.current
			_damage = 0.0
			Driver.fight(flow, FIGHT_CAP, Callable(self, "_on_tick"))
			var ticks: int = flow.session.sim.clock.tick - start_tick
			var secs := _r(float(ticks) / tick_rate)
			total_damage += _damage
			rooms.append({"id": rid, "type": rtype, "stage": int(flow.room.values.get("stage", 0)),
				"ticks": ticks, "seconds": secs, "damage": _r(_damage),
				"end_hp": _r(flow.session.sim.actor.health.current), "end_state": flow.state})
			if rtype == "boss":
				boss_id = rid
				boss_seconds = secs
			if flow.state == "dead":
				deaths += 1
				status = "dead"
				break
			if flow.state == "fighting":
				status = "stalled"
				break
			if rtype == "combat" and not flow.reward_options.is_empty():
				var reward = flow.choose_reward(0)
				picks.append("%s:%s" % [reward.get("kind", "?"), reward.get("rune", reward.get("id", reward.get("currency", "?")))])
		else:
			buy_result = flow.buy(0)
			rooms.append({"id": str(flow.room.values["id"]), "type": "workshop", "stage": int(flow.room.values.get("stage", 0)),
				"ticks": 0, "seconds": 0.0, "damage": 0.0, "end_hp": 0.0, "end_state": "workshop"})
		if flow.state == "won":
			break
		if i < count - 1:
			var next: Dictionary = Driver.reach_exit(flow)
			if not next["ok"]:
				_failed = true
				status = "transition_failed"
				break
	var summary: Dictionary = flow.summary()
	return {"seed": seed_value, "status": status, "outcome": flow.outcome, "rooms": rooms,
		"rooms_cleared": summary["rooms_cleared"], "kills": summary["kills"], "ticks": summary["ticks"],
		"seconds": _r(float(summary["seconds"])), "spells_used": summary["spells_used"],
		"damage": _r(total_damage), "deaths": deaths, "boss_room": boss_id, "boss_seconds": boss_seconds,
		"rewards": picks, "workshop_buy": buy_result, "wall_ms": Time.get_ticks_msec() - started}

func _strip(run: Dictionary) -> String:
	var copy := run.duplicate(true)
	copy.erase("wall_ms")
	return JSON.stringify(copy)

func _stats(values: Array) -> Dictionary:
	if values.is_empty():
		return {"min": 0, "median": 0, "max": 0}
	var sorted := values.duplicate()
	sorted.sort()
	var n := sorted.size()
	var median: float = float(sorted[n / 2]) if n % 2 == 1 else (float(sorted[n / 2 - 1]) + float(sorted[n / 2])) / 2.0
	return {"min": _r(float(sorted[0])), "median": _r(median), "max": _r(float(sorted[n - 1]))}

func _aggregate(runs: Array) -> Dictionary:
	var secs := []; var cleared := []; var dmg := []; var boss := []
	var deaths := 0
	var per_room := {}
	var pick_counts := {}
	for r in runs:
		secs.append(r["seconds"]); cleared.append(r["rooms_cleared"]); dmg.append(r["damage"])
		deaths += int(r["deaths"])
		if r["boss_room"] != "":
			boss.append(r["boss_seconds"])
		for room in r["rooms"]:
			if room["type"] == "workshop":
				continue
			if not per_room.has(room["id"]):
				per_room[room["id"]] = {"seconds": [], "damage": []}
			per_room[room["id"]]["seconds"].append(room["seconds"])
			per_room[room["id"]]["damage"].append(room["damage"])
		for p in r["rewards"]:
			pick_counts[p] = int(pick_counts.get(p, 0)) + 1
	var rooms_out := {}
	var keys := per_room.keys()
	keys.sort()
	for k in keys:
		rooms_out[k] = {"seconds": _stats(per_room[k]["seconds"]), "damage": _stats(per_room[k]["damage"])}
	var pk := pick_counts.keys()
	pk.sort()
	var picks_out := {}
	for k in pk:
		picks_out[k] = pick_counts[k]
	return {"runs": runs.size(), "combat_seconds": _stats(secs), "rooms_cleared": _stats(cleared),
		"damage": _stats(dmg), "boss_seconds": _stats(boss), "deaths_total": deaths,
		"per_room": rooms_out, "reward_picks": picks_out}

func _st(s: Dictionary) -> String:
	return "%s | %s | %s" % [s["min"], s["median"], s["max"]]

func _markdown(seeds: Array, runs: Array, agg: Dictionary) -> String:
	var md := PackedStringArray()
	md.append("### Seeds\n")
	md.append(", ".join(PackedStringArray(seeds.map(func(s): return str(s)))) + "\n")
	md.append("### Per-run results\n")
	md.append("| seed | outcome | rooms cleared | per-room seconds | per-room damage | deaths | boss s | reward picks | total combat s |")
	md.append("|---|---|---|---|---|---|---|---|---|")
	for r in runs:
		var rs := []; var rd := []
		for room in r["rooms"]:
			if room["type"] == "workshop":
				continue
			rs.append("%s=%s" % [room["id"], room["seconds"]])
			rd.append("%s=%s" % [room["id"], room["damage"]])
		md.append("| %s | %s/%s | %s | %s | %s | %s | %s | %s | %s |" % [r["seed"], r["outcome"], r["status"],
			r["rooms_cleared"], ", ".join(rs), ", ".join(rd), r["deaths"], r["boss_seconds"],
			", ".join(PackedStringArray(r["rewards"])).replace("|", "/"), r["seconds"]])
	md.append("\n### Per-room aggregate\n")
	md.append("| room | sec min | sec median | sec max | dmg min | dmg median | dmg max |")
	md.append("|---|---|---|---|---|---|---|")
	for k in agg["per_room"]:
		var e: Dictionary = agg["per_room"][k]
		md.append("| %s | %s | %s |" % [k, _st(e["seconds"]), _st(e["damage"])])
	md.append("\n### Overall aggregate\n")
	md.append("| metric | min | median | max |")
	md.append("|---|---|---|---|")
	for m in ["combat_seconds", "rooms_cleared", "damage", "boss_seconds"]:
		md.append("| %s | %s |" % [m, _st(agg[m])])
	md.append("\nDeaths (sum): %s over %s runs.\n" % [agg["deaths_total"], agg["runs"]])
	md.append("Reward picks: `%s`\n" % JSON.stringify(agg["reward_picks"]))
	return "\n".join(md)

func _run() -> void:
	var seeds: Array = [20261022]
	for s in range(20261023, 20261042):
		seeds.append(s)
	var out_path := ""
	var check := false
	var args := OS.get_cmdline_user_args()
	var i := 0
	while i < args.size():
		match args[i]:
			"--seeds":
				i += 1
				seeds = []
				for part in args[i].split(",", false):
					seeds.append(int(part))
			"--out":
				i += 1
				out_path = args[i]
			"--check-determinism":
				check = true
		i += 1
	var runs: Array = []
	for s in seeds:
		var run := _run_seed(s)
		print("RUN_LENGTH_RUN:", JSON.stringify(run))
		if check:
			var again := _run_seed(s)
			if _strip(run) != _strip(again):
				print("RUN_LENGTH_NONDETERMINISTIC:", s)
				quit(1)
				return
		runs.append(run)
		if _failed:
			quit(2)
			return
	var agg := _aggregate(runs)
	print("RUN_LENGTH_AGGREGATE:", JSON.stringify(agg))
	if out_path != "":
		var f := FileAccess.open(out_path, FileAccess.WRITE)
		if f == null:
			quit(2)
			return
		f.store_string(_markdown(seeds, runs, agg))
		f.close()
	print("RUN_LENGTH_DONE")
	quit(0)
