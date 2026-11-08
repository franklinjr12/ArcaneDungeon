extends SceneTree
## Boss fight-length check (90-180 s) for the Drowned Archivist on LIVE balance data.
## Moved from tests/test_ad_final_boss.gd for AD-167 so unit tests stay on the frozen balance fixture.
## Run: godot --headless --path . --script res://tests/bench/boss_pacing_bench.gd
const Session = preload("res://combat/combat_session.gd")
const Driver = preload("res://tests/m3_run_driver.gd")
const AT := Vector2(1030,450)
const BUILDS := [0,2]
const MAX_TICKS := 12000
const MIN_SECONDS := 90.0
const MAX_SECONDS := 180.0

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

func _run() -> void:
	var doc: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://world/data/run_v2.json"))
	var failed := false
	for build in BUILDS:
		var s = Session.new(1423,"empty",build)
		s.defer_clear = true
		s.set_water(doc["room_templates"]["cistern_boss"]["layout"]["water"])
		var boss = s.spawn_boss(doc["bosses"]["cistern_boss"],AT)
		var h := Harness.new()
		h.session = s
		h.boss = boss
		Driver.fight(h,MAX_TICKS)
		var tick: int = s.sim.clock.tick
		var seconds := float(tick) / 60.0
		var ok: bool = not boss.target.alive() and seconds >= MIN_SECONDS and seconds <= MAX_SECONDS
		failed = failed or not ok
		print("BOSS_PACING build=%d tick=%d seconds=%.1f target=90-180 %s" % [build,tick,seconds,"PASS" if ok else "FAIL"])
	quit(1 if failed else 0)
