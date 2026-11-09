extends "res://tests/bench/run_bench.gd"
## AD-158: full-run smoke + full-run determinism (extends AD-086). Reuses the AD-156 bot; no gameplay change.
## Run: godot --headless --path . --script res://tests/qa/demo_smoke.gd [-- --seeds=N --det-seeds=N --natural=1 --first=N --trace=0]
## --first=N starts the route and natural loops at SEEDS[N] (AD-176 chunking; determinism still uses SEEDS[0..det-seeds)).
## --trace=0 turns trace recording off (AD-173: same results); use it with --det-seeds=0 because determinism compares traces.
## Not named test_*.gd on purpose: a full run is far too slow for tests/run_tests.gd.
const GOD_HEALTH := 1000000.0
const SMOKE_BUILD := "typical"

## When true the player cannot die, so every seed walks the whole route.
var _god := false

func _run() -> void:
	if _option("--trace=", "1") == "0":
		_record_trace = false
	var first: int = clampi(int(_option("--first=", "0")), 0, SEEDS.size() - 1)
	var count: int = clampi(int(_option("--seeds=", str(SEEDS.size()))), 1, SEEDS.size())
	var chunk: Array = SEEDS.slice(first, first + count)
	var det_count: int = clampi(int(_option("--det-seeds=", "5")), 0, SEEDS.size())
	var natural: bool = _option("--natural=", "0") == "1"
	var rows: Array = []
	var failing: Array = []
	_god = true
	for run_seed in chunk:
		var rec: Dictionary = _play(int(run_seed), SMOKE_BUILD)
		var ok: bool = _route_ok(rec)
		rows.append(_row(rec, "route", ok))
		if not ok:
			failing.append("%d:route" % run_seed)
	var det_ok := 0
	var det_total := 0
	for run_seed in SEEDS.slice(0, det_count):
		var good: bool = _determinism(int(run_seed))
		det_total += 1
		det_ok += 1 if good else 0
		print("AD_DEMO_DETERMINISM seed=%d ok=%s" % [run_seed, good])
		if not good:
			failing.append("%d:determinism" % run_seed)
	if det_count >= 2:
		var a: Dictionary = _play(SEEDS[0], SMOKE_BUILD)
		var b: Dictionary = _play(SEEDS[1], SMOKE_BUILD)
		var differs: bool = JSON.stringify(a, "", true) != JSON.stringify(b, "", true)
		det_total += 1
		det_ok += 1 if differs else 0
		print("AD_DEMO_DETERMINISM seed=%d/%d distinct ok=%s" % [SEEDS[0], SEEDS[1], differs])
		if not differs:
			failing.append("%d/%d:distinct" % [SEEDS[0], SEEDS[1]])
	_god = false
	if natural:
		for run_seed in chunk:
			for build in BUILDS.keys():
				var rec: Dictionary = _play(int(run_seed), build)
				var ok: bool = rec["outcome"] in ["won", "dead"]
				rows.append(_row(rec, "natural", ok))
				if not ok:
					failing.append("%d:natural:%s" % [run_seed, build])
	var green := 0
	for row in rows:
		green += 1 if row["ok"] else 0
	var summary := {"smoke_total": rows.size(), "smoke_green": green, "determinism_total": det_total,
		"determinism_green": det_ok, "failing": failing}
	print("AD_DEMO_QA_SUMMARY:" + JSON.stringify(summary, "", true))
	print("QA_MD_BEGIN")
	print(_table(rows))
	print("QA_MD_END")
	quit(0 if failing.is_empty() else 1)

## Invulnerable player in route mode; HP is reset every room because _fight runs once per room.
func _fight(flow, rate: int, bot: Dictionary) -> Dictionary:
	if _god:
		flow.session.sim.actor.health.maximum = GOD_HEALTH
		flow.session.sim.actor.health.current = GOD_HEALTH
	return super._fight(flow, rate, bot)

func _enter(flow, plan: Dictionary, earned: Array, rate: int, bot: Dictionary) -> Dictionary:
	var rec: Dictionary = super._enter(flow, plan, earned, rate, bot)
	rec["rng_state"] = str(flow.session.sim.clock._rng.state)
	if flow.session != null:
		rec["trace_hash"] = flow.session.sim.trace_json().hash()
	return rec

func _route_ok(rec: Dictionary) -> bool:
	var boss := [false, false]
	var workshop := false
	for room in rec["rooms"]:
		if room["outcome"] in ["timeout", "error"]:
			return false
		if room["outcome"] == "workshop":
			workshop = true
		if room["type"] == "boss" and int(room["stage"]) in [0, 1]:
			boss[int(room["stage"])] = true
	return rec["outcome"] == "won" and boss[0] and boss[1] and workshop

func _row(rec: Dictionary, mode: String, ok: bool) -> Dictionary:
	var row := {"seed": rec["seed"], "mode": mode, "build": rec["build"], "outcome": rec["outcome"],
		"rooms": rec["rooms"].size(), "total_min": _r(float(rec["total_seconds"]) / 60.0),
		"max_room_s": rec["max_room_seconds"], "ok": ok}
	print("AD_DEMO_SMOKE seed=%d mode=%s build=%s outcome=%s rooms=%d total_min=%s ok=%s" % [row["seed"], mode,
		row["build"], row["outcome"], row["rooms"], row["total_min"], ok])
	return row

## Plays the god-mode run twice; prints the first differing room and key on mismatch.
func _determinism(run_seed: int) -> bool:
	var first: Dictionary = _play(run_seed, SMOKE_BUILD)
	var second: Dictionary = _play(run_seed, SMOKE_BUILD)
	if JSON.stringify(first, "", true) == JSON.stringify(second, "", true):
		return true
	var rooms_a: Array = first["rooms"]
	var rooms_b: Array = second["rooms"]
	for i in mini(rooms_a.size(), rooms_b.size()):
		for key in rooms_a[i].keys():
			if JSON.stringify(rooms_a[i][key], "", true) != JSON.stringify(rooms_b[i].get(key), "", true):
				printerr("AD_DEMO_DETERMINISM seed=%d first diff room=%d key=%s" % [run_seed, i, key])
				return false
	printerr("AD_DEMO_DETERMINISM seed=%d diff outside rooms (count %d vs %d)" % [run_seed, rooms_a.size(), rooms_b.size()])
	return false

func _table(rows: Array) -> String:
	var lines: Array = ["| seed | mode | build | outcome | rooms | total min | max room s | ok |",
		"|---|---|---|---|---|---|---|---|"]
	for r in rows:
		lines.append("| %d | %s | %s | %s | %d | %s | %s | %s |" % [r["seed"], r["mode"], r["build"], r["outcome"],
			r["rooms"], r["total_min"], r["max_room_s"], "yes" if r["ok"] else "NO"])
	return "\n".join(lines)
