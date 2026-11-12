extends SceneTree
## AD-199 Undead Warden bot bench on LIVE balance data (INFO only: the human target is 60-120 s, the bot is not held to it).
## Run: godot --headless --path . --script res://tests/bench/warden_bench.gd
const Session = preload("res://combat/combat_session.gd")
const Driver = preload("res://tests/m3_run_driver.gd")
const BUILDS := [0,2]
const SEEDS := [1423,2718,3141,4242,5150,6174,7331,8086]
const MAX_TICKS := 12000

class Harness:
	var session
	var boss
	var state := "fighting"
	func step(command: Dictionary) -> void:
		session.issue(command)
		session.step()
		if session.state != "playing" or not boss.target.alive():
			state = "done"

func _initialize() -> void:
	call_deferred("_run")

static func _median(values: Array) -> float:
	if values.is_empty():
		return 0.0
	var sorted := values.duplicate()
	sorted.sort()
	var n := sorted.size()
	return float(sorted[n/2]) if n % 2 == 1 else (float(sorted[n/2-1])+float(sorted[n/2]))/2.0

func _fight(doc: Dictionary, run_seed: int, build: int) -> Dictionary:
	var s = Session.new(run_seed,"empty",build)
	s.defer_clear = true
	var boss = s.spawn_boss(doc["bosses"]["ruins_warden"],Vector2(doc["bosses"]["ruins_warden"]["position"][0],doc["bosses"]["ruins_warden"]["position"][1]))
	var h := Harness.new()
	h.session = s
	h.boss = boss
	var track := {"still":0,"max":0,"last":boss.target.position}
	var on_tick := func(_flow):
		if ["acquire","recover","moving"].has(boss.state):
			track["still"] = int(track["still"])+1 if boss.target.position == track["last"] else 0
			track["max"] = maxi(int(track["max"]),int(track["still"]))
		else:
			track["still"] = 0
		track["last"] = boss.target.position
	Driver.fight(h,MAX_TICKS,on_tick)
	var result := "win"
	if boss.target.alive():
		result = "loss" if s.sim.actor.health.current <= 0.0 or s.state != "playing" else "timeout"
	return {"result":result,"seconds":float(s.sim.clock.tick)/60.0,"dashes":s.player.dashes,
		"hp":s.sim.actor.health.current,"phase":boss.phase,"still":int(track["max"])}

func _run() -> void:
	var doc: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://world/data/run_v2.json"))
	for build in BUILDS:
		var seconds: Array = []
		var dashes: Array = []
		for run_seed in SEEDS:
			var r := _fight(doc,run_seed,build)
			seconds.append(r["seconds"])
			dashes.append(r["dashes"])
			print("WARDEN_BENCH seed=%d build=%d result=%s seconds=%.1f dashes=%d player_hp=%.0f phase=%d max_stationary_ticks=%d" % [run_seed,build,r["result"],r["seconds"],r["dashes"],r["hp"],r["phase"],r["still"]])
		print("WARDEN_BENCH_SUMMARY build=%d fights=%d median_seconds=%.1f median_dashes=%.1f target=60-120 INFO" % [build,SEEDS.size(),_median(seconds),_median(dashes)])
	quit(0)
