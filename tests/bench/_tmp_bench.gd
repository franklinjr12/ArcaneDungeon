extends SceneTree
## AD-043: deterministic 10-seed headless slice benchmark. Scripted player only; no gameplay change.
## Run: godot --headless --path . --script res://tests/bench/slice_bench.gd
const Flow = preload("res://world/run_flow.gd")
const SEEDS := [20261022]
const ROOM_TICK_CAP := 6000

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	var first: Dictionary = _bench()
	var a: String = JSON.stringify(first,"",true)
	var b: String = a
	var second: Dictionary = first
	if a != b:
		printerr("AD_SLICE_BENCH nondeterministic: two runs differ")
		quit(1)
		return
	if first["per_seed"].size() != SEEDS.size():
		printerr("AD_SLICE_BENCH missing seed results")
		quit(1)
		return
	print("AD_SLICE_BENCH:" + a)
	print("BENCH_MD_BEGIN")
	print(_markdown(first))
	print("BENCH_MD_END")
	quit(0)

func _bench() -> Dictionary:
	var per_seed: Array = []
	for run_seed in SEEDS:
		per_seed.append(_play(int(run_seed)))
	return {"seeds": SEEDS.duplicate(), "per_seed": per_seed, "aggregate": _aggregate(per_seed)}

func _r(value: float) -> float:
	return snappedf(value, 0.001)

func _play(run_seed: int) -> Dictionary:
	var flow = Flow.new(run_seed)
	var rooms: Array = []
	var picks: Array = []
	var casts: Dictionary = {}
	var outcome := "won"
	var workshop_spell: Dictionary = {}
	var earned: Array = []
	var rate: int = flow.session.sim.clock.tick_rate
	for slot in flow.session.sim.loadout.slots.size():
		casts[str(slot)] = 0
	while true:
		var room_id: String = str(flow.room.values["id"])
		if flow.state == "workshop":
			workshop_spell = _workshop(flow, earned)
		else:
			var rec: Dictionary = _fight(flow, rate)
			rec["room"] = room_id
			print("PROG ", run_seed, " ", room_id, " ", rec["outcome"], " ticks=", rec["ticks"], " hp=", rec["hp_lost"], " start=", rec.get("x", 0), " starved=", rec["mana_starved_ticks"])
			rooms.append(rec)
			for key in rec["casts"]:
				casts[key] += rec["casts"][key]
			if flow.state == "dead":
				outcome = "dead"
				break
			if flow.state == "fighting":
				outcome = "timeout"
				break
			if flow.state == "won":
				break
			if flow.room.values["type"] == "combat":
				picks.append(_pick(flow, room_id, earned))
		var exit_result: Dictionary = _reach_exit(flow)
		if not exit_result.get("ok", false):
			outcome = "error"
			break
	var ticks := 0
	var hp := 0.0
	var starved := 0
	var warden_ticks := 0
	for rec in rooms:
		ticks += rec["ticks"]
		hp += rec["hp_lost"]
		starved += rec["mana_starved_ticks"]
		if rec["room"] == "s1_boss":
			warden_ticks = rec["ticks"]
	return {"seed": run_seed, "outcome": outcome, "deaths": 1 if outcome == "dead" else 0,
		"total_ticks": ticks, "total_seconds": _r(float(ticks) / rate), "total_hp_lost": _r(hp),
		"total_mana_starved_ticks": starved, "casts_per_slot": casts, "warden_ticks": warden_ticks,
		"warden_seconds": _r(float(warden_ticks) / rate), "reward_picks": picks,
		"workshop_spell": workshop_spell, "rooms": rooms}

func _pick(flow, room_id: String, earned: Array) -> Dictionary:
	var index := 0
	for i in flow.reward_options.size():
		var option: Dictionary = flow.reward_options[i]
		if option["kind"] == "rune" and not (str(option["id"]) in flow.run.unlocked):
			index = i
			break
	var option: Dictionary = flow.reward_options[index]
	var result: Dictionary = flow.choose_reward(index)
	var record := {"room": room_id, "index": index, "kind": str(option["kind"])}
	if option["kind"] == "rune":
		record["id"] = str(option["id"])
		if result.get("ok", false):
			earned.append(str(option["id"]))
	else:
		record["amount"] = int(option.get("amount", 0))
	return record

func _workshop(flow, earned: Array) -> Dictionary:
	if not flow.open_editor(0).get("ok", false):
		return {"applied": false, "reason": "OPEN_FAILED"}
	var editor = flow.editor
	var essence := "essence.water"
	var form := "form.projectile"
	var essences: Array = editor.available("essence")
	var ok_root := false
	for entry in essences:
		if entry["id"] == essence and not entry["locked"]:
			ok_root = true
	if not ok_root:
		for entry in essences:
			if not entry["locked"]:
				essence = entry["id"]
				break
	editor.set_root(essence, form)
	for id in earned:
		if id.begins_with("mod."):
			editor.toggle_modifier(id)
			break
	var valid: bool = editor.validate()["ok"]
	var result: Dictionary = flow.close_editor(valid, 0.0)
	if not valid or not result.get("ok", false):
		if flow.editor.allowed:
			flow.close_editor(false, 0.0)
		return {"applied": false, "reason": "INVALID"}
	var formula: Dictionary = flow.run.formulas[0]
	return {"applied": true, "formula_id": str(formula["formula_id"]),
		"runes": _runes(formula)}

func _runes(formula: Dictionary) -> Array:
	var root: Dictionary = formula.get("root", {})
	var list: Array = [str(root.get("essence_id", "")), str(root.get("manifestation_id", ""))]
	for modifier in root.get("modifier_ids", []):
		list.append(str(modifier))
	return list

func _fight(flow, rate: int) -> Dictionary:
	var session = flow.session
	var slots: int = session.sim.loadout.slots.size()
	var hp_start: float = session.sim.actor.health.current
	var ticks := 0
	var starved := 0
	var casts: Dictionary = {}
	for slot in slots:
		casts[str(slot)] = 0
	for iteration in ROOM_TICK_CAP:
		if flow.state != "fighting":
			break
		var actor: Vector2 = session.sim.actor.position
		var foe = _nearest(session)
		var movement := Vector2.ZERO
		var direction := Vector2.RIGHT
		var cursor: Vector2 = actor + Vector2.RIGHT * 130
		var distance := INF
		var sight := false
		if foe != null:
			cursor = foe.target.position
			var displacement: Vector2 = cursor - actor
			distance = displacement.length()
			direction = displacement.normalized()
			if direction.is_zero_approx():
				direction = Vector2.RIGHT
			sight = session.world.clear_sight(actor, cursor, 8)
			if distance > 220 or not sight:
				movement = session.world.navigate_direction(actor, cursor, session.sim.actor.radius)
			elif distance < 120:
				movement = -direction
			else:
				movement = direction.rotated(PI / 2.0) * 0.4
		var dash := false
		if session.player.dash_cooldown == 0:
			for enemy in session.enemies:
				if enemy.target.alive() and enemy.state == "windup":
					var deadline: int = int(enemy.tuning["telegraph_ticks"]) - enemy.state_tick
					if deadline <= 7 and actor.distance_to(enemy.target.position) < float(enemy.tuning["attack_range"]) + 65:
						dash = true
						movement = direction.rotated(PI / 2.0)
						break
			for shot in session.enemy_shots:
				if actor.distance_to(shot["position"]) < 110:
					dash = true
					movement = shot["direction"].rotated(PI / 2.0)
					break
		var cheapest := INF
		for idx in slots:
			var plan = session.sim.loadout.get_plan(idx)
			if plan != null:
				cheapest = minf(cheapest, float(plan.snapshot()["mana_cost"]))
		if session.sim.mana < cheapest:
			starved += 1
		var slot := -1
		if foe != null and session.player.dash_left == 0 and session.player.recovery_left == 0:
			for k in slots - 1:
				var idx: int = 1 + (iteration + k) % (slots - 1)
				if session.sim.loadout.slots[idx]["cooldown"] > 0:
					continue
				var spell = session.sim.loadout.get_plan(idx)
				if spell == null or session.sim.mana < float(spell.snapshot()["mana_cost"]):
					continue
				var form: String = str(spell.snapshot()["root"]["manifestation"]["id"])
				if form == "form.projectile" and sight:
					slot = idx
					break
				if form == "form.burst" and sight and distance <= float(session.data["player"]["max_burst_distance"]) - 10:
					slot = idx
					break
				if form == "form.orb" and distance < 160:
					slot = idx
					break
			if slot == -1 and sight:
				var bolt = session.sim.loadout.get_plan(0)
				if bolt != null and session.sim.loadout.slots[0]["cooldown"] == 0 and session.sim.mana >= float(bolt.snapshot()["mana_cost"]):
					slot = 0
		if iteration % 500 == 0 and str(flow.room.values["id"]) == "s1_boss":
			print("DBG it=", iteration, " bosshp=", foe.target.health.current if foe != null else -1, " mana=", session.sim.mana, " dist=", distance, " sight=", sight, " slot=", slot, " pos=", actor)
		var used_before: int = flow.spells_used
		var hp_dbg: float = session.sim.actor.health.current
		flow.step({"move": movement, "aim": direction, "cursor": cursor, "cast": slot, "dash": dash})
		ticks += 1
		if session.sim.actor.health.current < hp_dbg:
			print("HIT ", flow.room.values["id"], " t=", ticks, " lost=", hp_dbg - session.sim.actor.health.current)
		if slot >= 0 and flow.spells_used > used_before:
			casts[str(slot)] += flow.spells_used - used_before
	var state: String = flow.state
	var label := "timeout"
	if state == "cleared":
		label = "cleared"
	elif state == "won" or state == "dead":
		label = state
	return {"outcome": label, "ticks": ticks, "sim_seconds": _r(float(ticks) / rate),
		"hp_lost": _r(hp_start - session.sim.actor.health.current),
		"mana_starved_ticks": starved, "casts": casts}

func _reach_exit(flow, max_ticks: int = 1100) -> Dictionary:
	for i in max_ticks:
		if flow.session.sim.actor.position.distance_to(flow.room.marker("exit")) <= 65:
			return flow.try_exit(flow.session.sim.actor.position)
		var point: Vector2 = flow.session.sim.actor.position
		var direction: Vector2 = flow.session.world.navigate_direction(point, flow.room.marker("exit"), flow.session.sim.actor.radius)
		flow.move_after_clear({"move": direction, "aim": direction})
	return {"ok": false, "reason": "EXIT_NAV_TIMEOUT"}

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

func _aggregate(per_seed: Array) -> Dictionary:
	var agg: Dictionary = {}
	for key in ["total_seconds", "total_hp_lost", "total_mana_starved_ticks", "warden_seconds", "deaths"]:
		agg[key] = _stats(per_seed.map(func(s): return s[key]))
	var casts: Dictionary = {}
	for key in per_seed[0]["casts_per_slot"]:
		casts[key] = _stats(per_seed.map(func(s): return s["casts_per_slot"][key]))
	agg["casts_per_slot"] = casts
	var seconds: Dictionary = {}
	var hp: Dictionary = {}
	var by_room: Dictionary = {}
	for s in per_seed:
		for rec in s["rooms"]:
			if not by_room.has(rec["room"]):
				by_room[rec["room"]] = {"s": [], "h": []}
			by_room[rec["room"]]["s"].append(rec["sim_seconds"])
			by_room[rec["room"]]["h"].append(rec["hp_lost"])
	for id in by_room:
		seconds[id] = _stats(by_room[id]["s"])
		hp[id] = _stats(by_room[id]["h"])
	agg["room_seconds"] = seconds
	agg["room_hp_lost"] = hp
	return agg

func _markdown(result: Dictionary) -> String:
	var lines: Array = []
	lines.append("| seed | outcome | total s | HP lost | starved ticks | warden s | casts (slot0/1/2/3) | rewards |")
	lines.append("|---|---|---|---|---|---|---|---|")
	for s in result["per_seed"]:
		var c: Array = []
		for key in s["casts_per_slot"]:
			c.append(str(s["casts_per_slot"][key]))
		var r: Array = []
		for p in s["reward_picks"]:
			r.append(str(p.get("id", "currency:%d" % int(p.get("amount", 0)))))
		lines.append("| %d | %s | %s | %s | %d | %s | %s | %s |" % [s["seed"], s["outcome"], s["total_seconds"],
			s["total_hp_lost"], s["total_mana_starved_ticks"], s["warden_seconds"], "/".join(c), ", ".join(r)])
	lines.append("")
	lines.append("| metric | median | min | max |")
	lines.append("|---|---|---|---|")
	var agg: Dictionary = result["aggregate"]
	for key in ["total_seconds", "total_hp_lost", "total_mana_starved_ticks", "warden_seconds", "deaths"]:
		lines.append("| %s | %s | %s | %s |" % [key, agg[key]["median"], agg[key]["min"], agg[key]["max"]])
	for key in agg["casts_per_slot"]:
		var st: Dictionary = agg["casts_per_slot"][key]
		lines.append("| casts slot %s | %s | %s | %s |" % [key, st["median"], st["min"], st["max"]])
	lines.append("")
	lines.append("| room | n | median s | min s | max s | median HP lost | min HP lost | max HP lost |")
	lines.append("|---|---|---|---|---|---|---|---|")
	for id in agg["room_seconds"]:
		var a: Dictionary = agg["room_seconds"][id]
		var h: Dictionary = agg["room_hp_lost"][id]
		lines.append("| %s | %d | %s | %s | %s | %s | %s | %s |" % [id, a["n"], a["median"], a["min"], a["max"], h["median"], h["min"], h["max"]])
	return "\n".join(lines)
