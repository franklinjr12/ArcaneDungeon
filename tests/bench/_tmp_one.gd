extends "res://tests/bench/slice_bench.gd"
func _run() -> void:
	var out: Array = []
	for s in [20261022, 20261024]:
		out.append(_play(s))
	print("ONE:" + JSON.stringify(out))
	quit(0)
func _reach_exit(flow, max_ticks: int = 1100) -> Dictionary:
	var r = super._reach_exit(flow, max_ticks)
	print("EXIT:", r, " pos ", flow.session.sim.actor.position, " state ", flow.state)
	return r
