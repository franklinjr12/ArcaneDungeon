extends SceneTree
const Profiler = preload("res://debug/stress_profiler.gd")
const Flow = preload("res://world/run_flow.gd")
const SEED := 20261022
const BOSS_INDEX := 3
const SIM_TICKS := 600
const RENDER_TICKS := 300
const BUDGET_MS := 4.0
const COMPLEXITY_CAP := 12

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	var stats: Dictionary = Profiler.benchmark(5151,300,40)
	print("M4_STRESS:",JSON.stringify(stats))
	var valid: bool = stats["targets"]>=30 and stats["ticks"]==300 and stats["cap_accepted"]<=stats["cap_per_cast"] and stats["pending_end"]==0
	var probe_ok: bool = await _boss_probe()
	quit(0 if valid and probe_ok else 1)

## Highest-complexity legal Split+Pierce(+Homing) projectile with On Hit burst payload.
func _worst_formula() -> Dictionary:
	return {"schema_version":1,"formula_id":"ad087.worst_case","display_name":"AD-087 worst case",
		"root":{"essence_id":"essence.fire","manifestation_id":"form.projectile",
			"modifier_ids":["mod.split","mod.pierce","mod.homing"],"params":{}},
		"on_hit":{"trigger_id":"trigger.on_hit","payload":{"essence_id":"essence.lightning",
			"manifestation_id":"form.burst","modifier_ids":[],"params":{}}}}

func _boss_flow() -> Dictionary:
	var flow = Flow.new(SEED)
	return _setup(flow)

## Puts flow into the boss room with max enemies and the worst spell. Returns diagnostics (ok=false on failure).
func _setup(flow) -> Dictionary:
	flow.run.sequence_index = BOSS_INDEX
	flow._enter_current()
	var out := {"ok":false,"flow":flow}
	if flow.state != "fighting":
		return out
	var session = flow.session
	var boss = null
	for e in session.enemies:
		if "undead_warden" in e.target.tags:
			boss = e
	out["boss_present"] = boss != null
	if boss == null:
		return out
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
	var res: Dictionary = sim.equip(1,formula)
	out["equip_ok"] = bool(res.get("ok",false))
	if not out["equip_ok"]:
		out["equip_issues"] = res.get("issues",[])
		return out
	out["formula"] = formula
	out["complexity"] = sim.loadout.get_plan(1).complexity()
	out["boss"] = boss
	out["ok"] = spawned > 0
	return out

func _command(session, boss) -> Dictionary:
	var to_boss: Vector2 = boss.target.position-session.sim.actor.position
	return {"move":Vector2.ZERO,"aim":to_boss.normalized(),"cursor":boss.target.position,"cast":1,"dash":false}

func _refill(session) -> void:
	session.sim.actor.health.current = session.sim.actor.health.maximum
	session.sim.mana = float(session.sim.settings["combat"]["player_max_mana"])
	for e in session.enemies:
		e.target.health.current = maxf(e.target.health.current,1e5)

func _boss_probe() -> bool:
	var s: Dictionary = _boss_flow()
	var out := {"seed":SEED,"ticks":SIM_TICKS,"room_id":"s1_boss","complexity_cap":COMPLEXITY_CAP,
		"boss_present":s.get("boss_present",false),"enemies_spawned":s.get("enemies_spawned",0)}
	if not s["ok"]:
		print("AD_PERF_PROBE:",JSON.stringify({"error":"boss-room setup failed","detail":str(s.get("equip_issues",[])),"partial":out}))
		return false
	var flow = s["flow"]
	var session = flow.session
	var boss = s["boss"]
	var samples: Array = []
	var peak_active := 0
	var peak_pending := 0
	var peak_alive := 0
	var casts := 0
	for i in SIM_TICKS:
		_refill(session)
		var cmd := _command(session,boss)
		var t0: int = Time.get_ticks_usec()
		flow.step(cmd)
		samples.append(Time.get_ticks_usec()-t0)
		peak_active = maxi(peak_active,session.sim.queue.active_effect_count())
		peak_pending = maxi(peak_pending,session.sim.queue.pending_count())
		var alive := 0
		for e in session.enemies:
			if e.target.alive():
				alive += 1
		peak_alive = maxi(peak_alive,alive)
	var drops := 0
	for entry in session.sim.trace.snapshot():
		var kind := str(entry["type"])
		if kind == "budget_exceeded":
			drops += 1
		elif kind == "cost_paid":
			casts += 1
	samples.sort()
	var total := 0
	for x in samples:
		total += int(x)
	var n: int = samples.size()
	var p95: float = float(samples[clampi(roundi(n*.95),0,n-1)])/1000.0
	out.merge({"formula":s["formula"],"complexity":s["complexity"],
		"sim_p50_ms":float(samples[clampi(roundi(n*.5),0,n-1)])/1000.0,"sim_p95_ms":p95,
		"sim_max_ms":float(samples[-1])/1000.0,"sim_mean_ms":snappedf(float(total)/n/1000.0,0.001),
		"budget_ms":BUDGET_MS,"budget_pass":p95 <= BUDGET_MS,
		"peak_active_effects":peak_active,"peak_queued_events":peak_pending,"peak_enemies_alive":peak_alive,
		"budget_drop_records":drops,"casts":casts})
	if p95 > BUDGET_MS:
		print("AD_PERF_PROBE: BUDGET EXCEEDED p95=%.3f ms > %.1f ms" % [p95,BUDGET_MS])
	out["render"] = await _render_probe()
	out["godot"] = Engine.get_version_info()["string"]
	print("AD_PERF_PROBE:",JSON.stringify(out))
	return true

func _count(node: Node, acc: Dictionary) -> void:
	acc["nodes"] += 1
	if node is CPUParticles2D or node is GPUParticles2D:
		acc["particle_nodes"] += 1
		if node.emitting:
			acc["particles_emitting"] += 1
			acc["particles_amount"] += int(node.amount)
	for c in node.get_children():
		_count(c,acc)

func _render_probe() -> Dictionary:
	var viewport := SubViewport.new()
	viewport.size = Vector2i(1280,720)
	viewport.disable_3d = true
	root.add_child(viewport)
	var scene: Node = load("res://scenes/run.tscn").instantiate()
	scene.show_dev_tools = false
	viewport.add_child(scene)
	scene.set_physics_process(false) # this probe drives flow.step itself
	var render := {"render_note":"draw-call/primitive monitors unavailable headless (dummy renderer); node counts and particle nodes are proxies. Arena is custom _draw on one canvas node, so effect_visuals are counted from sim effects/enemy shots, not scene nodes."}
	var s: Dictionary = _setup(scene.flow)
	if not s["ok"]:
		render["error"] = "render-side setup failed"
		viewport.queue_free()
		return render
	scene._redraw_panel()
	var flow = scene.flow
	var session = flow.session
	var frames := 0
	var mon_peak := 0
	var mon_sum := 0
	var scene_peak := 0
	var part_nodes_peak := 0
	var part_amount_peak := 0
	var fx_peak := 0
	for i in RENDER_TICKS:
		_refill(session)
		flow.step(_command(session,s["boss"]))
		scene.arena_canvas.queue_redraw()
		await process_frame
		frames += 1
		var m := int(Performance.get_monitor(Performance.OBJECT_NODE_COUNT))
		mon_peak = maxi(mon_peak,m)
		mon_sum += m
		var acc := {"nodes":0,"particle_nodes":0,"particles_emitting":0,"particles_amount":0}
		_count(scene,acc)
		scene_peak = maxi(scene_peak,acc["nodes"])
		part_nodes_peak = maxi(part_nodes_peak,acc["particles_emitting"])
		part_amount_peak = maxi(part_amount_peak,acc["particles_amount"])
		fx_peak = maxi(fx_peak,session.sim.queue.active_effect_count()+session.enemy_shots.size())
	render.merge({"frames":frames,"node_count_peak":mon_peak,"node_count_mean":snappedf(float(mon_sum)/maxi(1,frames),0.1),
		"scene_nodes_peak":scene_peak,"particles_nodes_peak":part_nodes_peak,"particles_amount_peak":part_amount_peak,
		"effect_visuals_peak":fx_peak})
	viewport.queue_free()
	await process_frame
	return render
