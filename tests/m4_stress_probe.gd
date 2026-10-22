extends SceneTree
const Profiler = preload("res://debug/stress_profiler.gd")
func _initialize() -> void:
	call_deferred("_run")
func _run() -> void:
	var stats: Dictionary = Profiler.benchmark(5151,300,40)
	print("M4_STRESS:",JSON.stringify(stats))
	var valid: bool = stats["targets"]>=30 and stats["ticks"]==300 and stats["cap_accepted"]<=stats["cap_per_cast"] and stats["pending_end"]==0
	quit(0 if valid else 1)
