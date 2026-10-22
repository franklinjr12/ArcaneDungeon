extends RefCounted
const Profiler = preload("res://debug/stress_profiler.gd")
const Runner = preload("res://magic/runtime/spell_runner.gd")
func run(t) -> void:
	var result: Dictionary = Profiler.benchmark(5151,105,36)
	t.equal(result["targets"],36,"TASK-051 at least 30 targets in stress workload")
	t.equal(result["ticks"],105,"TASK-051 fixed number of stress ticks completed")
	t.check(result["alive"],"TASK-051 synthetic workload does not kill runner")
	t.equal(result["cap_attempted"],10000,"TASK-051 cascade explicitly attempts 10000 effects")
	t.equal(result["cap_accepted"],result["cap_per_cast"],
		"TASK-051 over-limit cascade capped at configured effects per root")
	t.check(result["budget_drop_records"]>=1,"TASK-051 overflow visible in typed debug trace")
	t.check(result["peak_active_effects"]<=result["limits"]["max_active_effects"],
		"TASK-051 active effects never exceed global budget")
	t.check(result["hit_records"]>0,"TASK-051 mixed split/pierce/orb workload actually hits targets")
	t.check(result["trigger_records"]>0,"TASK-051 triggers actually execute in synthetic combat")
	t.equal(result["pending_end"],0,"TASK-051 queue drains without hanging")
	t.check(result["memory_static_peak_bytes"]>=result["memory_static_start_bytes"],
		"TASK-051 static memory high-water measured")
	t.check(result["mean_tick_ms"]>=0 and result["max_tick_ms"]>=result["p95_tick_ms"],
		"TASK-051 valid observed mean/p95/maximum fixed-step timings")
	var r = Runner.new(55)
	var data: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://magic/data/sandbox_samples_v1.json"))
	var sample = data["formulas"][0]
	r.equip(0,sample)
	var overload: Dictionary = r.stress()
	t.equal(overload["accepted"],r.limits.get_limit("max_effects_per_cast"),
		"TASK-051 immediate budget overflow enforces same per-cast cap")
	t.check(r.try_cast(0,r.actor.position,Vector2.RIGHT)["accepted"],
		"TASK-051 a later valid cast still works after cap overflow")
	for i in 25:
		r.step()
	t.equal(r.queue.pending_count(),0,"TASK-051 no stale queue after overflow")
