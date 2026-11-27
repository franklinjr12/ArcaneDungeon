extends SceneTree
## AD-257 combo DPS bench: best single-skill spam vs best combo rotation on the 4-dummy pack, same seeds and
## rotations as test_ad_257_d_combo_dps_bar (reuses its _pack_damage so the numbers match the test).
## /usr/local/bin/godot --headless --path . --script res://tests/bench/ad257_combo_bench.gd
const Suite = preload("res://tests/test_ad_257_combos.gd")

const SINGLES := ["essence.lightning","essence.cold","essence.fire","essence.water","essence.force"]
const ROTATIONS := [["essence.water","essence.lightning"],["essence.water","essence.cold","essence.force"]]

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	var suite = Suite.new()
	var seconds := float(Suite.WINDOW_TICKS)/60.0
	for seed_value in Suite.SEEDS:
		var single := 0.0
		for e in SINGLES:
			single = maxf(single,suite._pack_damage(seed_value,[e])/seconds)
		var combo := 0.0
		for rot in ROTATIONS:
			combo = maxf(combo,suite._pack_damage(seed_value,rot)/seconds)
		print("AD257_BENCH seed=%d single_dps=%.2f combo_dps=%.2f ratio=%.3f" % [seed_value,single,combo,combo/single if single > 0.0 else 0.0])
	quit(0)
