extends SceneTree
## AD-043: deterministic 10-seed headless slice benchmark with a scripted player (no gameplay change).
const Flow = preload("res://world/run_flow.gd")
const SEEDS := [20261022, 20261023, 20261024, 20261025, 20261026, 20261027, 20261028, 20261029, 20261030, 20261031]
const ROOM_TICK_CAP := 6000

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	var first: Dictionary = _bench()
	var second: Dictionary = _bench()
	var text_a: String = JSON.stringify(first, "", true)
	var text_b: String = JSON.stringify(second, "", true)
	print("AD_SLICE_BENCH:" + text_a)
	print("BENCH_MD_BEGIN")
	print(_markdown(first))
	print("BENCH_MD_END")
	if text_a != text_b:
		printerr("AD_SLICE_BENCH: two in-process runs differ")
		quit(1)
		return
	if first["per_seed"].size() != SEEDS.size():
		printerr("AD_SLICE_BENCH: missing seed results")
		quit(1)
		return
	quit(0)

func _bench() -> Dictionary:
	var per_seed: Array = []
	for run_seed in SEEDS:
		per_seed.append(_play(int(run_seed)))
	return {"per_seed": per_seed, "aggregate": _aggregate(per_seed)}

func _r3(value: float) -> float:
	return snappedf(value, 0.001)

func _play(run_seed: int) -> Dictionary:
	var flow = Flow.new(run_seed)
	var rate: float = float(flow.session.sim.clock.tick_rate)
	var rooms: Array = []
	var casts: Dictionary = {}
	var picks: Array = []
	var workshop_spell: Dictionary = {}
	var outcome := "won"
	var total_ticks := 0
	var total_hp := 0.0
	var total_starved := 0
	var warden_ticks := 0
	var room_count: int = flow.config["rooms"].size()
	for index in room_count:
		var room_id: String = str(flow.room.values["id"])
		if flow.mode == "workshop":
			workshop_spell = _workshop(flow, picks)
			var leave: Dictionary = _reach_exit(flow)
			if not leave["ok"]:
				outcome = "error"
				break
			continue
		var stats: Dictionary = _fight(flow, casts)
		var ticks: int = stats["ticks"]
		total_ticks += ticks
		total_hp += stats["hp_lost"]
		total_starved += stats["starved"]
		if room_id == "s1_boss":
			warden_ticks = ticks
		var room_result := {"room": room_id, "ticks": ticks, "seconds": _r3(float(ticks) / rate),
			"hp_lost": _r3(stats["hp_lost"]), "mana_starved_ticks": stats["starved"], "outcome": stats["outcome"]}
		rooms.append(room_result)
		if stats["outcome"] == "won":
			break
		if stats["outcome"] != "cleared":
			outcome = stats["outcome"]
			break
		if str(flow.room.values["type"]) == "combat":
			var pick: int = 0
			for i in flow.reward_options.size():
				var option: Dictionary = flow.reward_options[i]
				if option["kind"] == "rune" and str(option["id"]) not in flow.run.unlocked:
					pick = i
					break
			var option: Dictionary = flow.reward_options[pick]
			flow.choose_reward(pick)
			var entry := {"room": room_id, "index": pick, "kind": str(option["kind"])}
			if option["kind"] == "rune":
				entry["id"] = str(option["id"])
			else:
				entry["amount"] = int(option["amount"])
			picks.append(entry)
		if not _reach_exit(flow)["ok"]:
			outcome = "error"
			break
	var casts_out: Dictionary = {}
	for key in casts.keys():
		casts_out[str(key)] = casts[key]
	return {"seed": run_seed, "outcome": outcome, "deaths": 1 if outcome == "dead" else 0,
		"total_ticks": total_ticks, "total_seconds": _r3(float(total_ticks) / rate),
		"total_hp_lost": _r3(total_hp), "total_mana_starved_ticks": total_starved,
		"casts_per_slot": casts_out, "warden_ticks": warden_ticks, "warden_seconds": _r3(float(warden_ticks) / rate),
		"reward_picks": picks, "workshop_spell": workshop_spell, "rooms": rooms}

func _workshop(flow, picks: Array) -> Dictionary:
	if not flow.open_editor(0)["ok"]:
		return {"error": "OPEN_FAILED"}
	var editor = flow.editor
	var essence := "essence.water"
	for entry in editor.available("essence"):
		if not entry["locked"]:
			essence = str(entry["id"])
			if essence == "essence.water":
				break
	editor.set_root(essence, "form.projectile")
	for pick in picks:
		if pick.has("id") and str(pick["id"]).begins_with("mod."):
			editor.toggle_modifier(str(pick["id"]))
			break
	var ok: bool = editor.validate()["ok"]
	flow.close_editor(ok, 0.0)
	var formula: Dictionary = flow.run.formulas[0]
	return {"applied": ok, "formula_id": str(formula["formula_id"]), "essence": str(formula["root"]["essence_id"]),
		"form": str(formula["root"]["manifestation_id"]), "modifiers": formula["root"]["modifier_ids"].duplicate()}

func _cheapest(session) -> float:
	var best := INF
	for slot in session.sim.loadout.slots.size():
		var plan = session.sim.loadout.get_plan(slot)
		if plan != null:
			best = minf(best, float(plan.snapshot()["mana_cost"]))
	return best

func _fight(flow, casts: Dictionary) -> Dictionary:
	var hp_start: float = flow.session.sim.actor.health.current
	var ticks := 0
	var starved := 0
	for iteration in ROOM_TICK_CAP:
		if flow.state != "fighting":
			break
		var session = flow.session
		if session.sim.mana < _cheapest(session):
			starved += 1
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
		var slot := -1
		if foe != null and session.player.dash_left == 0 and session.player.recovery_left == 0:
			var count: int = session.sim.loadout.slots.size() - 1
			for k in count:
				var idx: int = 1 + (iteration + k) % count
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
		var used_before: int = flow.spells_used
		flow.step({"move": movement, "aim": direction, "cursor": cursor, "cast": slot, "dash": dash})
		ticks += 1
		if slot >= 0 and flow.spells_used > used_before:
			casts[slot] = int(casts.get(slot, 0)) + (flow.spells_used - used_before)
	var outcome: String = flow.state
	if flow.state == "fighting":
		outcome = "timeout"
	var hp_end: float = flow.session.sim.actor.health.current
	return {"ticks": ticks, "hp_lost": hp_start - hp_end, "starved": starved, "outcome": outcome}

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
		return {"median": 0.0, "min": 0.0, "max": 0.0}
	var sorted := values.duplicate()
	sorted.sort()
	var n: int = sorted.size()
	var median: float = float(sorted[n / 2]) if n % 2 == 1 else (float(sorted[n / 2 - 1]) + float(sorted[n / 2])) / 2.0
	return {"median": _r3(median), "min": _r3(float(sorted[0])), "max": _r3(float(sorted[n - 1]))}

func _aggregate(per_seed: Array) -> Dictionary:
	var out: Dictionary = {}
	for key in ["total_seconds", "total_hp_lost", "total_mana_starved_ticks", "warden_seconds", "deaths"]:
		var values: Array = []
		for r in per_seed:
			values.append(r[key])
		out[key] = _stats(values)
	var slot_keys: Dictionary = {}
	var room_ids: Dictionary = {}
	for r in per_seed:
		for k in r["casts_per_slot"].keys():
			slot_keys[k] = true
		for room in r["rooms"]:
			room_ids[room["room"]] = true
	var slot_out: Dictionary = {}
	for k in slot_keys.keys():
		var values: Array = []
		for r in per_seed:
			values.append(int(r["casts_per_slot"].get(k, 0)))
		slot_out[k] = _stats(values)
	out["casts_per_slot"] = slot_out
	var sec_out: Dictionary = {}
	var hp_out: Dictionary = {}
	for id in room_ids.keys():
		var secs: Array = []
		var hps: Array = []
		for r in per_seed:
			for room in r["rooms"]:
				if room["room"] == id:
					secs.append(room["seconds"])
					hps.append(room["hp_lost"])
		sec_out[id] = _stats(secs)
		hp_out[id] = _stats(hps)
	out["room_seconds"] = sec_out
	out["room_hp_lost"] = hp_out
	return out

func _markdown(result: Dictionary) -> String:
	var lines: Array = ["| seed | outcome | total s | HP lost | mana-starved ticks | warden s | casts per slot | rewards |",
		"|---|---|---|---|---|---|---|---|"]
	for r in result["per_seed"]:
		var rewards: Array = []
		for p in r["reward_picks"]:
			rewards.append(str(p.get("id", "currency+" + str(p.get("amount", 0)))))
		lines.append("| %d | %s | %s | %s | %d | %s | %s | %s |" % [r["seed"], r["outcome"], r["total_seconds"],
			r["total_hp_lost"], r["total_mana_starved_ticks"], r["warden_seconds"],
			JSON.stringify(r["casts_per_slot"], "", true), ", ".join(rewards)])
	lines.append("")
	lines.append("| metric | median | min | max |")
	lines.append("|---|---|---|---|")
	var agg: Dictionary = result["aggregate"]
	for key in ["total_seconds", "total_hp_lost", "total_mana_starved_ticks", "warden_seconds", "deaths"]:
		lines.append("| %s | %s | %s | %s |" % [key, agg[key]["median"], agg[key]["min"], agg[key]["max"]])
	for slot in agg["casts_per_slot"].keys():
		var s: Dictionary = agg["casts_per_slot"][slot]
		lines.append("| casts slot %s | %s | %s | %s |" % [slot, s["median"], s["min"], s["max"]])
	lines.append("")
	lines.append("| room | seconds median | min | max | HP lost median | min | max |")
	lines.append("|---|---|---|---|---|---|---|")
	for id in agg["room_seconds"].keys():
		var a: Dictionary = agg["room_seconds"][id]
		var h: Dictionary = agg["room_hp_lost"][id]
		lines.append("| %s | %s | %s | %s | %s | %s | %s |" % [id, a["median"], a["min"], a["max"], h["median"], h["min"], h["max"]])
	return "\n".join(lines)
