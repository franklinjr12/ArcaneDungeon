extends SceneTree
## AD-158 demo perf probe (AD-087 method applied to run_v2). Measurement only; run:
##   godot --headless --path . --script res://tests/qa/demo_perf_probe.gd -- [--ticks=N] [--rooms=id1,id2]
## Targets: the final boss (boss room of the highest stage), the stage-1 boss, and the 2 "worst" combat rooms.
## Worst-room rule: per stage, the non-boss, non-optional combat room of this seed's sequence whose waves
## spawn the most enemies in total (ties: earliest in the sequence). `--rooms=` overrides with explicit ids.
## An exceeded 4 ms p95 budget is reported, not fatal (AD-087 already FAILS it on this host); exit 1 = setup failure only.
const Flow = preload("res://world/run_flow.gd")
const TargetStore = preload("res://combat/target_store.gd")
const MagicTarget = preload("res://combat/magic_target.gd")
const Projectile = preload("res://magic/runtime/projectile_effect.gd")
const PerfRun = preload("res://game/core/perf_run.gd")
const BaseGeometry = preload("res://world/arena_geometry.gd")
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
		elif a == "--check-equivalence":
			quit(0 if _check_equivalence() else 1)
			return
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

## AD-174: the optimised spatial helpers must equal the plain originals bit for bit. Own RNG, never the sim's.
const EQUIV_CASES := 5000

func _check_equivalence() -> bool:
	var rng := RandomNumberGenerator.new()
	rng.seed = 174174
	for n in EQUIV_CASES:
		var store := TargetStore.new()
		var count := rng.randi_range(0,8)
		for i in count:
			var t = MagicTarget.new(i+1,rng.randi_range(0,1),Vector2(snappedf(rng.randf_range(0.0,200.0),0.25 if i % 2 == 0 else 0.001),
				snappedf(rng.randf_range(0.0,200.0),0.25)),10.0,rng.randf_range(2.0,20.0))
			if rng.randi_range(0,5) == 0:
				t.position = Vector2(100.0,100.0) # exact distance ties exercise the id tie-break
			store.add(t)
		var center := Vector2(rng.randf_range(0.0,200.0),rng.randf_range(0.0,200.0))
		var radius := rng.randf_range(0.0,120.0)
		var team := rng.randi_range(0,1)
		var hits: Array = store.query(center,radius,team)
		var want = hits[0] if not hits.is_empty() else null
		var got = store.nearest(center,radius,team)
		if got != want:
			print("AD_EQUIV_FAIL nearest case=%d center=%s radius=%s team=%d want=%s got=%s" % [n,center,radius,team,
				want.id if want != null else -1,got.id if got != null else -1])
			return false
	for n in EQUIV_CASES:
		var walls: Array = []
		for i in rng.randi_range(0,6):
			var kind := rng.randi_range(0,3)
			var pos := Vector2(snappedf(rng.randf_range(0.0,200.0),0.5),snappedf(rng.randf_range(0.0,200.0),0.5))
			var size := Vector2(snappedf(rng.randf_range(1.0,60.0),0.5),snappedf(rng.randf_range(1.0,60.0),0.5))
			if kind == 1:
				size.x = 0.0 # degenerate wall
			walls.append(Rect2(pos,size))
		var padding: float = [0.0,0.5,4.0,rng.randf_range(0.0,12.0)][rng.randi_range(0,3)]
		var start := Vector2(rng.randf_range(-20.0,220.0),rng.randf_range(-20.0,220.0))
		var finish := start+Vector2(rng.randf_range(-40.0,40.0),rng.randf_range(-40.0,40.0))
		var shape := rng.randi_range(0,5)
		if shape == 0:
			finish = start
		elif shape == 1:
			finish.y = start.y
		elif shape == 2:
			finish.x = start.x
		elif not walls.is_empty() and shape == 3:
			var w: Rect2 = walls[rng.randi_range(0,walls.size()-1)]
			start = w.get_center() # start inside the rect
			finish = start+Vector2(rng.randf_range(-80.0,80.0),rng.randf_range(-80.0,80.0))
		elif not walls.is_empty() and shape == 4:
			var w: Rect2 = walls[rng.randi_range(0,walls.size()-1)]
			var gap: float = padding+[0.0,0.005,0.01,0.011,0.05][rng.randi_range(0,4)] # touching / near-touching the padded rect
			start = Vector2(w.position.x-gap,w.position.y+rng.randf()*w.size.y)
			finish = start+Vector2([0.0,1.0,-1.0,30.0][rng.randi_range(0,3)],rng.randf_range(-3.0,3.0))
		var initial: float = [1.0,rng.randf_range(0.0,1.0)][rng.randi_range(0,1)]
		var want := initial
		for wall in walls:
			want = minf(want,Projectile.segment_wall_time(start,finish,wall,padding))
		var got := Projectile.sweep_walls(start,finish,walls,padding,initial)
		if got != want:
			print("AD_EQUIV_FAIL sweep_walls case=%d start=%s finish=%s padding=%s walls=%s initial=%s want=%s got=%s" % [n,start,finish,padding,walls,initial,want,got])
			return false
	for room_id in ["cistern_boss","ruins_boss","ruins_c07","cistern_p10"]:
		if not _check_geometry(rng,room_id):
			return false
	print("AD_EQUIV_PASS")
	return true

## AD-174: CachedGeometry (session.world) against a plain base Geometry holding copies of the same rects, exact ==.
const GEOMETRY_CASES := 2500

func _check_geometry(rng: RandomNumberGenerator, room_id: String) -> bool:
	var flow = Flow.new(SEED,Flow.CONFIG_V2)
	var idx := -1
	for i in flow.rooms.size():
		if str(flow.rooms[i]["id"]) == room_id:
			idx = i
	if idx < 0:
		print("AD_EQUIV_FAIL geometry room missing ",room_id)
		return false
	flow.run.sequence_index = idx
	flow._enter_current()
	if flow.state != "fighting":
		print("AD_EQUIV_FAIL geometry room state ",flow.state)
		return false
	var session = flow.session
	var radii: Array = [session.sim.actor.radius]
	for kind in session.data["enemies"].keys():
		var radius := float(session.data["enemies"][kind]["radius"])
		if not radii.has(radius):
			radii.append(radius)
	var fast = session.world
	var plain := BaseGeometry.new({"width":fast.bounds.size.x,"height":fast.bounds.size.y,"walls":[]})
	plain.bounds = fast.bounds
	plain.walls = fast.walls.duplicate()
	plain.ground_blockers = fast.ground_blockers.duplicate()
	var cases := 0
	var added := Rect2(Vector2(rng.randf_range(200.0,800.0),rng.randf_range(100.0,500.0)),Vector2(60.0,90.0))
	for phase in ["base","append","erase"]:
		if phase == "append":
			fast.walls.append(added)
			plain.walls.append(added)
		elif phase == "erase":
			fast.walls.erase(added)
			plain.walls.erase(added)
		for n in GEOMETRY_CASES:
			var start := Vector2(rng.randf_range(-10.0,fast.bounds.end.x+10.0),rng.randf_range(-10.0,fast.bounds.end.y+10.0))
			var finish := Vector2(rng.randf_range(0.0,fast.bounds.end.x),rng.randf_range(0.0,fast.bounds.end.y))
			if n % 5 == 0:
				finish = start+Vector2(rng.randf_range(-60.0,60.0),rng.randf_range(-60.0,60.0))
			var radius: float = radii[rng.randi_range(0,radii.size()-1)]
			var padding: float = [0.0,radius,rng.randf_range(0.0,12.0)][rng.randi_range(0,2)]
			var what := ""
			if fast.navigate_direction(start,finish,radius) != plain.navigate_direction(start,finish,radius):
				what = "navigate_direction"
			elif fast.clear_sight(start,finish,padding) != plain.clear_sight(start,finish,padding):
				what = "clear_sight"
			elif fast.walk_clear(start,finish,padding) != plain.walk_clear(start,finish,padding):
				what = "walk_clear"
			elif fast.valid_position(start,radius) != plain.valid_position(start,radius):
				what = "valid_position"
			if what != "":
				print("AD_EQUIV_FAIL %s room=%s phase=%s case=%d start=%s finish=%s radius=%s padding=%s" % [what,room_id,phase,n,start,finish,radius,padding])
				return false
			cases += 1
	print("AD_EQUIV_GEOMETRY room=%s cases=%d radii=%s" % [room_id,cases,radii])
	return true

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

func _worst_formula() -> Dictionary:
	return PerfRun.config()["worst_formula"]

func _refill(session) -> void:
	PerfRun.refill(session)

func _command(session) -> Dictionary:
	return PerfRun.command(session)

func _probe(room_id: String) -> Dictionary:
	var flow = Flow.new(SEED,Flow.CONFIG_V2)
	var out := {"seed":SEED,"ticks":ticks,"room_id":room_id,"ok":false}
	var prep: Dictionary = PerfRun.prepare_room(flow,room_id,PerfRun.config())
	for k in ["stage","type","boss_present","enemies_spawned","equip_ok","complexity"]:
		if prep.has(k):
			out[k] = prep[k]
	if not prep["ok"]:
		out["error"] = prep["error"]
		return out
	var session = flow.session
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
	out["ok"] = int(prep["enemies_spawned"]) > 0 and flow.session != null
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
