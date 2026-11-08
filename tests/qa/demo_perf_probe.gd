extends SceneTree
## AD-158 demo perf probe (AD-087 method applied to run_v2). Measurement only; run:
##   godot --headless --path . --script res://tests/qa/demo_perf_probe.gd -- [--ticks=N] [--rooms=id1,id2]
## Targets: the final boss (boss room of the highest stage), the stage-1 boss, and the 2 "worst" combat rooms.
## Worst-room rule: per stage, the non-boss, non-optional combat room of this seed's sequence whose waves
## spawn the most enemies in total (ties: earliest in the sequence). `--rooms=` overrides with explicit ids.
## An exceeded 4 ms p95 budget is reported, not fatal (AD-087 already FAILS it on this host); exit 1 = setup failure only.
const Flow = preload("res://world/run_flow.gd")
const SEED := 20261022
const BUDGET_MS := 4.0
const PROXY_TARGET_MS := 8.0 ## game-design ruling 2026-11-08: VM proxy target until the reference PC is measured
## A legitimate data retune invalidates these digests; --verify-digests is only for no-behaviour-change perf work.
const BASELINE_DIGESTS := {
	"cistern_boss":"b5707c8b24f5a60ac5c166fa6b18288e44d4d30ad4b4ebb332e049734781f685",
	"ruins_boss":"eb50274ac60b600e19b8a2460d42d3f9a499f741b8415f0c02bb4f36c4ed63d2",
	"ruins_c07":"310039acdbc1a8a375f1c2caf3fa93802d8cca5ab2773595323e313de326b420",
	"cistern_p10":"37ad1915e27bb88a841c797d0cd06657558fad15d811d6deb66fb7f4fe64501c"}
var verify_digests := false
var ticks := 600
var room_override: Array = []

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	print("AD_DEMO_PERF_HOST:",_loadavg())
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--ticks="):
			ticks = maxi(1,int(a.substr(8)))
		elif a == "--verify-digests":
			verify_digests = true
		elif a.begins_with("--rooms="):
			room_override = a.substr(8).split(",",false)
	var flow = Flow.new(SEED,Flow.CONFIG_V2)
	var ids: Array = []
	for r in flow.rooms:
		ids.append(str(r["id"]))
	print("AD_DEMO_PERF_ROOMS:",JSON.stringify(ids))
	var targets: Array = _targets(flow.rooms)
	var results: Array = []
	var all_ok := true
	for id in targets:
		var res: Dictionary = _probe(str(id))
		results.append(res)
		print("AD_DEMO_PERF:",JSON.stringify(res))
		if not res.get("ok",false):
			all_ok = false
		elif not res["budget_pass"]:
			print("AD_DEMO_PERF: BUDGET EXCEEDED room=%s p95=%.3f ms > %.1f ms" % [id,res["sim_p95_ms"],BUDGET_MS])
	_print_table(results)
	var digest_ok := true
	if verify_digests:
		for res in results:
			var rid := str(res["room_id"])
			if int(res.get("ticks",0)) != 600 or str(res.get("digest","")) != str(BASELINE_DIGESTS.get(rid,"")):
				print("AD_DEMO_PERF_DIGEST_MISMATCH room=%s ticks=%s digest=%s" % [rid,res.get("ticks"),res.get("digest","")])
				digest_ok = false
	quit(0 if all_ok and results.size() >= 3 and digest_ok else 1)

func _enemy_count(room: Dictionary) -> int:
	var n := 0
	for w in room.get("waves",[]):
		n += w["enemies"].size()
	return n

func _targets(rooms: Array) -> Array:
	var out: Array = []
	var top_stage := 0
	var final_boss := ""
	var first_boss := ""
	for r in rooms:
		if r["type"] == "boss":
			if first_boss == "":
				first_boss = str(r["id"])
			if int(r["stage"]) >= top_stage:
				top_stage = int(r["stage"])
				final_boss = str(r["id"])
	out.append(final_boss)
	if first_boss != final_boss:
		out.append(first_boss)
	if room_override.size() > 0:
		return out + room_override
	var best := {}
	for r in rooms:
		if r["type"] != "combat" or bool(r.get("optional",false)):
			continue
		var st := int(r["stage"])
		if not best.has(st) or _enemy_count(r) > _enemy_count(best[st]):
			best[st] = r
	var stages: Array = best.keys()
	stages.sort()
	for st in stages:
		out.append(str(best[st]["id"]))
	return out

## Highest-complexity legal Split+Pierce(+Homing) projectile with On Hit burst payload (same as m4_stress_probe).
func _worst_formula() -> Dictionary:
	return {"schema_version":1,"formula_id":"ad087.worst_case","display_name":"AD-087 worst case",
		"root":{"essence_id":"essence.fire","manifestation_id":"form.projectile",
			"modifier_ids":["mod.split","mod.pierce","mod.homing"],"params":{}},
		"on_hit":{"trigger_id":"trigger.on_hit","payload":{"essence_id":"essence.lightning",
			"manifestation_id":"form.burst","modifier_ids":[],"params":{}}}}

func _refill(session) -> void:
	session.sim.actor.health.current = session.sim.actor.health.maximum
	session.sim.mana = float(session.sim.settings["combat"]["player_max_mana"])
	for e in session.enemies:
		e.target.health.current = maxf(e.target.health.current,1e5)

func _command(session) -> Dictionary:
	var aim := Vector2.RIGHT
	var cursor: Vector2 = session.sim.actor.position+aim*100.0
	for e in session.enemies:
		if e.target.alive():
			cursor = e.target.position
			aim = (cursor-session.sim.actor.position).normalized()
			break
	return {"move":Vector2.ZERO,"aim":aim,"cursor":cursor,"cast":1,"dash":false}

func _probe(room_id: String) -> Dictionary:
	var flow = Flow.new(SEED,Flow.CONFIG_V2)
	var idx := -1
	for i in flow.rooms.size():
		if str(flow.rooms[i]["id"]) == room_id:
			idx = i
	var out := {"seed":SEED,"ticks":ticks,"room_id":room_id,"ok":false}
	if idx < 0:
		out["error"] = "room not in sequence"
		return out
	out["stage"] = int(flow.rooms[idx]["stage"])
	out["type"] = str(flow.rooms[idx]["type"])
	flow.run.sequence_index = idx
	flow._enter_current()
	if flow.state != "fighting":
		out["error"] = "state " + flow.state
		return out
	var session = flow.session
	out["boss_present"] = out["type"] == "boss" and session.enemies.size() == 1
	var kinds: Array = session.data["enemies"].keys()
	kinds.sort()
	var want: int = int(flow.config["max_active_enemies"])
	var spawned := 0
	var tries := 0
	for gy in range(120,800,90):
		for gx in range(260,1200,110):
			if spawned >= want:
				break
			if session.spawn_enemy(kinds[tries%kinds.size()],Vector2(gx,gy)) != null:
				spawned += 1
			tries += 1
	out["enemies_spawned"] = spawned
	for e in session.enemies:
		e.target.health.maximum = 1e6
		e.target.health.current = 1e6
	var sim = session.sim
	sim.loadout.unlocked = sim.registry.get_ids()
	sim.loadout.allow_edit = true
	var formula := _worst_formula()
	var eq: Dictionary = sim.equip(1,formula)
	out["equip_ok"] = bool(eq.get("ok",false))
	if not out["equip_ok"]:
		out["error"] = "equip failed " + str(eq.get("issues",[]))
		return out
	out["complexity"] = sim.loadout.get_plan(1).complexity()
	var samples: Array = []
	var peak_active := 0
	var peak_pending := 0
	var peak_alive := 0
	for i in ticks:
		_refill(session)
		var cmd := _command(session)
		var t0: int = Time.get_ticks_usec()
		flow.step(cmd)
		samples.append(Time.get_ticks_usec()-t0)
		session = flow.session
		peak_active = maxi(peak_active,session.sim.queue.active_effect_count())
		peak_pending = maxi(peak_pending,session.sim.queue.pending_count())
		var alive := 0
		for e in session.enemies:
			if e.target.alive():
				alive += 1
		peak_alive = maxi(peak_alive,alive)
	var drops := 0
	var casts := 0
	for entry in session.sim.trace.snapshot():
		var kind := str(entry["type"])
		if kind == "budget_exceeded":
			drops += 1
		elif kind == "cost_paid":
			casts += 1
	var win: int = maxi(1,mini(100,samples.size()/2))
	var p50_first := _median_ms(samples.slice(0,win))
	var p50_last := _median_ms(samples.slice(samples.size()-win))
	var trace_records: int = session.sim.trace.snapshot().size()
	out["digest"] = _digest(session)
	samples.sort()
	var total := 0
	for x in samples:
		total += int(x)
	var n: int = samples.size()
	var p95: float = float(samples[clampi(roundi(n*.95),0,n-1)])/1000.0
	out.merge({"sim_p50_ms":float(samples[clampi(roundi(n*.5),0,n-1)])/1000.0,"sim_p95_ms":p95,
		"sim_max_ms":float(samples[-1])/1000.0,"sim_mean_ms":snappedf(float(total)/n/1000.0,0.001),
		"budget_ms":BUDGET_MS,"budget_pass":p95 <= BUDGET_MS,"proxy_pass":p95 <= PROXY_TARGET_MS,"peak_active_effects":peak_active,
		"peak_queued_events":peak_pending,"peak_enemies_alive":peak_alive,"budget_drop_records":drops,
		"casts":casts,"sim_p50_first100_ms":p50_first,"sim_p50_last100_ms":p50_last,
		"trace_records":trace_records,"godot":Engine.get_version_info()["string"]})
	out["ok"] = spawned > 0 and flow.session != null
	return out

func _digest(session) -> String:
	var enemies: Array = []
	for e in session.enemies:
		enemies.append([e.target.id,e.state,e.target.position.x,e.target.position.y,e.target.health.current])
	var end_state := [session.sim.clock.tick,session.sim.actor.position.x,session.sim.actor.position.y,session.sim.mana,enemies]
	return (session.sim.trace.to_json()+JSON.stringify(end_state)).sha256_text()

func _loadavg() -> String:
	var f := FileAccess.open("/proc/loadavg",FileAccess.READ)
	return f.get_line().strip_edges() if f != null else "unavailable"

func _median_ms(part: Array) -> float:
	var a: Array = part.duplicate()
	a.sort()
	return float(a[clampi(roundi(a.size()*.5),0,a.size()-1)])/1000.0

func _print_table(results: Array) -> void:
	print("PERF_MD_BEGIN")
	print("| room | stage | enemies alive peak | p50 ms | p95 ms | max ms | peak effects | drops | verdict | proxy verdict |")
	print("|---|---|---|---|---|---|---|---|---|---|")
	for r in results:
		if not r.get("ok",false):
			print("| %s | %s | - | - | - | - | - | - | SETUP FAILED: %s | - |" % [r["room_id"],r.get("stage","-"),r.get("error","")])
			continue
		print("| %s | %d | %d | %.3f | %.3f | %.3f | %d | %d | %s | %s |" % [r["room_id"],r["stage"]+1,r["peak_enemies_alive"],
			r["sim_p50_ms"],r["sim_p95_ms"],r["sim_max_ms"],r["peak_active_effects"],r["budget_drop_records"],
			"PASS" if r["budget_pass"] else "FAIL (>%.1f ms)" % BUDGET_MS,
			"PASS" if r["proxy_pass"] else "FAIL (>%.1f ms)" % PROXY_TARGET_MS])
	print("PERF_MD_END")
