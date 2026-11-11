extends "res://tests/bench/run_bench.gd"
## AD-158: full-run smoke + full-run determinism (extends AD-086). Reuses the AD-156 bot; no gameplay change.
## Run: godot --headless --path . --script res://tests/qa/demo_smoke.gd [-- --seeds=N --det-seeds=N --natural=1 --first=N --trace=0 --diag=1]
## --first=N starts the route and natural loops at SEEDS[N] (AD-176 chunking; determinism still uses SEEDS[0..det-seeds)).
## --trace=0 turns trace recording off (AD-173: same results); use it with --det-seeds=0 because determinism compares traces.
## --diag=1 (AD-229, report only): natural mode also prints AD_DIAG_RUN lines and a DIAG_MD block of difficulty tables; default output unchanged.
## Not named test_*.gd on purpose: a full run is far too slow for tests/run_tests.gd.
const GOD_HEALTH := 1000000.0
const SMOKE_BUILD := "typical"

## When true the player cannot die, so every seed walks the whole route.
var _god := false
## AD-229: difficulty report flag.
var _diag := false

func _run() -> void:
	if _option("--trace=", "1") == "0":
		_record_trace = false
	var first: int = clampi(int(_option("--first=", "0")), 0, SEEDS.size() - 1)
	var count: int = clampi(int(_option("--seeds=", str(SEEDS.size()))), 1, SEEDS.size())
	var chunk: Array = SEEDS.slice(first, first + count)
	var det_count: int = clampi(int(_option("--det-seeds=", "5")), 0, SEEDS.size())
	var natural: bool = _option("--natural=", "0") == "1"
	_diag = _option("--diag=", "0") == "1"
	var diag_runs: Array = []
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
				if _diag:
					var diag: Dictionary = _diag_run(rec)
					diag_runs.append(diag)
					print("AD_DIAG_RUN:" + JSON.stringify(diag))
				if not ok:
					failing.append("%d:natural:%s" % [run_seed, build])
	var green := 0
	for row in rows:
		green += 1 if row["ok"] else 0
	var summary := {"smoke_total": rows.size(), "smoke_green": green, "determinism_total": det_total,
		"determinism_green": det_ok, "failing": failing}
	if _diag:
		print("DIAG_MD_BEGIN")
		print(_diag_md(diag_runs))
		print("DIAG_MD_END")
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
	if not _diag or _god:
		return super._fight(flow, rate, bot)
	var session = flow.session
	var hp_start: float = session.sim.actor.health.current
	var dodges_start: int = session.player.perfect_dodges
	var events_start: int = session.damage_events.size()
	var res: Dictionary = super._fight(flow, rate, bot)
	## Enemies stay in session.enemies after death (alive_enemies() only filters), so source_id -> kind is looked up there, as run_flow._death_cause does.
	var by_source := {}
	var last_enemy = null
	var events: Array = session.damage_events.slice(events_start)
	for event in events:
		var enemy = _enemy_of(session, int(event.get("source_id", -1)))
		var key := "%s:%s" % [str(enemy.kind) if enemy != null else "unknown", str(event.get("channel", ""))]
		by_source[key] = _r(float(by_source.get(key, 0.0)) + float(event.get("dealt", 0.0)))
		last_enemy = enemy
	var phase := ""
	var phases: Array = res["boss_phase_seconds"].keys()
	phases.sort()
	if not phases.is_empty():
		phase = str(phases.back())
	res["diag_room_index"] = flow.run.sequence_index
	res["diag_hp_start"] = _r(hp_start)
	res["diag_hp_max"] = _r(session.sim.actor.health.maximum)
	res["diag_hp_end"] = _r(session.sim.actor.health.current)
	res["diag_perfect_dodges"] = session.player.perfect_dodges - dodges_start
	res["diag_damage_by_source"] = by_source
	res["diag_boss_phase"] = phase
	if res["outcome"] == "dead" and not events.is_empty():
		var last: Dictionary = events.back()
		## Attack name: the boss windup attack when exposed, else the enemy state, else the numeric attack_id.
		var attack := str(int(last.get("attack_id", -1)))
		if last_enemy != null:
			var windup = last_enemy.get("_windup_attack")
			attack = str(windup) if windup != null and str(windup) != "" else str(last_enemy.state)
		res["diag_killer"] = {"kind": str(last_enemy.kind) if last_enemy != null else "unknown",
			"channel": str(last.get("channel", "")), "attack": attack}
	return res

func _enemy_of(session, source_id: int):
	for enemy in session.enemies:
		if enemy.target.id == source_id:
			return enemy
	return null

## One AD_DIAG_RUN record from a natural run. The game has no flask/potion mechanic (grep found none), so flask is "n/a".
func _diag_run(rec: Dictionary) -> Dictionary:
	var rooms: Array = []
	var bosses: Array = []
	var death: Dictionary = {}
	for room in rec["rooms"]:
		if not room.has("diag_room_index"):
			continue
		rooms.append({"room": room["room"], "index": room["diag_room_index"], "type": room["type"], "outcome": room["outcome"],
			"sim_seconds": room["sim_seconds"], "damage_taken": room["damage_taken"], "damage_by_source": room["diag_damage_by_source"],
			"starved_ticks": room["mana_starved_ticks"], "fight_ticks": room["ticks"], "dodges": room["dodges"],
			"perfect_dodges": room["diag_perfect_dodges"], "reactions_total": room["reactions_total"], "reactions": room["reactions"]})
		if room["type"] == "boss":
			bosses.append({"room": room["room"], "stage": room["stage"], "hp_start": room["diag_hp_start"], "hp_max": room["diag_hp_max"],
				"hp_end": room["diag_hp_end"], "outcome": room["outcome"], "flask": "n/a"})
		if room["outcome"] == "dead":
			death = room
	return {"seed": rec["seed"], "build": rec["build"], "outcome": rec["outcome"], "rooms_cleared": rec["rooms_cleared"],
		"starved_percent": rec["starved_percent"], "death_room_id": rec["death_room"],
		"death_room_index": death.get("diag_room_index", -1), "death_type": death.get("type", ""),
		"boss_phase": death.get("diag_boss_phase", ""), "killer": death.get("diag_killer", {}), "bosses": bosses, "rooms": rooms}

func _median(values: Array) -> float:
	if values.is_empty():
		return 0.0
	var sorted: Array = values.duplicate()
	sorted.sort()
	return _r(float(sorted[sorted.size() / 2]) if sorted.size() % 2 == 1 else (float(sorted[sorted.size() / 2 - 1]) + float(sorted[sorted.size() / 2])) / 2.0)

func _add(map: Dictionary, key: String, amount: float) -> void:
	map[key] = _r(float(map.get(key, 0.0)) + amount)

func _top(map: Dictionary, limit: int) -> String:
	var keys: Array = map.keys()
	keys.sort_custom(func(a, b): return map[a] > map[b] or (map[a] == map[b] and a < b))
	var parts: Array = []
	for key in keys.slice(0, limit):
		parts.append("%s %s" % [key, map[key]])
	return ", ".join(parts) if not parts.is_empty() else "-"

## Markdown tables (a)-(g) per build, aggregated from the AD_DIAG_RUN records.
func _diag_md(runs: Array) -> String:
	var out: Array = []
	for build in BUILDS.keys():
		var mine: Array = runs.filter(func(r): return r["build"] == build)
		var deaths := {}
		var killers := {}
		var src_total := {}
		var src_room := {}
		var starved: Array = []
		var dodge := {}
		var perfect := 0
		var fought := 0
		var reactions: Array = []
		var react_ids := {}
		var boss_hp := {}
		for r in mine:
			starved.append(float(r["starved_percent"]))
			if r["outcome"] == "dead":
				var key := "%s (idx %d, %s, phase %s)" % [r["death_room_id"], r["death_room_index"], r["death_type"], r["boss_phase"] if r["boss_phase"] != "" else "-"]
				deaths[key] = int(deaths.get(key, 0)) + 1
				var k: Dictionary = r["killer"]
				var kkey := "%s:%s" % [k.get("kind", "unknown"), k.get("attack", "")]
				killers[kkey] = int(killers.get(kkey, 0)) + 1
			for b in r["bosses"]:
				if not boss_hp.has(b["room"]):
					boss_hp[b["room"]] = []
				boss_hp[b["room"]].append(float(b["hp_start"]))
			for room in r["rooms"]:
				fought += 1
				perfect += int(room["perfect_dodges"])
				reactions.append(float(room["reactions_total"]))
				for id in room["reactions"]:
					react_ids[id] = int(react_ids.get(id, 0)) + int(room["reactions"][id])
				for id in room["damage_by_source"]:
					_add(src_total, id, float(room["damage_by_source"][id]))
					_add(src_room, "%s/%s" % [room["room"], id], float(room["damage_by_source"][id]))
				for type in room["dodges"]:
					if not dodge.has(type):
						dodge[type] = [0, 0]
					dodge[type][0] += int(room["dodges"][type]["attempted"])
					dodge[type][1] += int(room["dodges"][type]["succeeded"])
		out.append("### %s (%d runs)" % [build, mine.size()])
		out.append("**(a) Where runs end** (room id, index, boss phase x count): " + ", ".join(deaths.keys().map(func(k): return "%s x%d" % [k, deaths[k]])) if not deaths.is_empty() else "**(a) Where runs end**: no deaths")
		out.append("**(b) Killer kind:attack x count**: " + _top(killers, 8))
		out.append("**(c) Damage taken by source**: " + _top(src_total, 8) + " | per room: " + _top(src_room, 8))
		out.append("**(d) Mana-starved %% of combat ticks**: median %s, max %s" % [_median(starved), _r(starved.max()) if not starved.is_empty() else 0.0])
		var dl: Array = []
		for type in dodge:
			dl.append("%s %d/%d (%s%%)" % [type, dodge[type][1], dodge[type][0], _r(100.0 * dodge[type][1] / maxf(1.0, float(dodge[type][0])))])
		out.append("**(e) Dodges succeeded/attempted**: " + (", ".join(dl) if not dl.is_empty() else "none") + "; perfect dodges %d total, %s per fought room" % [perfect, _r(float(perfect) / maxf(1.0, float(fought)))])
		out.append("**(f) Reactions per fought room**: median %s, total by id: %s" % [_median(reactions), _top(react_ids, 12)])
		var hp: Array = []
		for room in boss_hp:
			var v: Array = boss_hp[room]
			hp.append("%s median %s min %s max %s (n=%d)" % [room, _median(v), _r(v.min()), _r(v.max()), v.size()])
		out.append("**(g) HP at boss entry**: " + (", ".join(hp) if not hp.is_empty() else "no boss reached") + "; flask n/a (no flask mechanic)")
		out.append("")
	return "\n".join(out)

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
