extends RefCounted
## AD-086 determinism regression (backlog scenario 10, GDD pillar 4): same seed + scripted commands
## give identical event traces, RNG draws and reward schedule; a different seed differs.
const Flow = preload("res://world/run_flow.gd")
const Driver = preload("res://tests/m3_run_driver.gd")
const SEED := 20261022

## Scripted stage-one route from the flow's current state; returns normalized plain-data records.
func _play(flow, max_rooms: int = 4) -> Array:
	var rec: Array = []
	for index in max_rooms:
		var id: String = str(flow.room.values["id"])
		var result: Dictionary = Driver.fight(flow, 4600)
		rec.append({"kind":"fight","room":id,"state":result["state"],"casts":result["casts"],
			"tick":flow.session.sim.clock.tick})
		if index < 3:
			rec.append({"kind":"reward_options","room":id,"options":flow.reward_options.duplicate(true)})
			rec.append({"kind":"grant","room":id,"grant":flow.choose_reward(0)})
		var events = JSON.parse_string(flow.session.sim.trace_json())
		for e in (events if events is Array else []):
			rec.append({"kind":"trace","room":id,"event":e})
		rec.append({"kind":"rng","room":id,"state":flow.session.sim.clock._rng.state})
		rec.append({"kind":"exit","room":id,"ok":Driver.reach_exit(flow)["ok"]})
		if str(flow.room.values["id"]) == "workshop":
			break
	rec.append({"kind":"logs","logs":flow.logs.duplicate(true)})
	rec.append({"kind":"summary","summary":flow.summary()})
	rec.append({"kind":"run","snapshot":flow.run.snapshot()})
	return rec

func _first_divergence(a: Array, b: Array) -> String:
	for i in mini(a.size(), b.size()):
		if a[i] != b[i]:
			return "first diverging event #%d: A=%s B=%s" % [i, JSON.stringify(a[i]), JSON.stringify(b[i])]
	if a.size() != b.size():
		return "first diverging event #%d: length mismatch A=%d B=%d" % [mini(a.size(), b.size()), a.size(), b.size()]
	return ""

func _compare(t, a: Array, b: Array, message: String) -> void:
	var div := _first_divergence(a, b)
	if div != "":
		printerr(message + ": " + div)
	t.check(div == "", message + ": " + div)

func _kinds(rec: Array, kind: String) -> Array:
	return rec.filter(func(r): return r["kind"] == kind)

func run(t) -> void:
	var trace1: Array = _play(Flow.new(SEED))
	var trace2: Array = _play(Flow.new(SEED))
	_compare(t, trace1, trace2, "AD-086 same seed + scripted commands give identical traces/RNG/rewards")
	t.equal(_kinds(trace1, "reward_options").size(), 3, "AD-086 route records 3 reward_options")
	t.check(_kinds(trace1, "trace").size() > 0, "AD-086 route records trace events")
	t.check(_kinds(trace1, "rng").size() == 4, "AD-086 route records RNG fingerprints")
	t.check(trace1.any(func(r): return r["kind"] == "exit" and r["room"] == "boss" and r["ok"]) or
		_kinds(trace1, "summary").size() == 1, "AD-086 route completes")
	_retry_via_pause_menu(t, trace1)
	var other: Array = _play(Flow.new(SEED + 1), 1)
	t.check(_first_divergence(trace1, other) != "", "AD-086 different seed produces a different trace/reward schedule")
	var o_opts := _kinds(other, "reward_options")
	var o_rng := _kinds(other, "rng")
	t.check(o_opts[0] != _kinds(trace1, "reward_options")[0] or o_rng[0] != _kinds(trace1, "rng")[0],
		"AD-086 different seed changes first reward options or RNG state")

func _retry_via_pause_menu(t, trace1: Array) -> void:
	var viewport := SubViewport.new()
	viewport.size = Vector2i(1280, 720)
	viewport.disable_3d = true
	(Engine.get_main_loop() as SceneTree).root.add_child(viewport)
	var scene: Node = load("res://scenes/run.tscn").instantiate()
	scene.show_dev_tools = false
	scene.config_path = "res://world/data/vertical_slice_v1.json"
	viewport.add_child(scene)
	if scene.flow.run.seed != SEED:
		scene.flow.start_new(SEED)
	Driver.fight(scene.flow, 4600)
	scene.flow.choose_reward(0)
	scene.open_pause()
	t.check(scene.is_paused(), "AD-086 pause menu opens before retry")
	scene.pause_menu.request_retry()
	scene.pause_menu.confirm_pending()
	t.check(not scene.is_paused(), "AD-086 pause menu closes after retry")
	t.equal(scene.flow.run.sequence_index, 0, "AD-086 pause-menu retry resets to first room")
	t.equal(scene.flow.run.seed, SEED, "AD-086 pause-menu retry keeps the seed")
	# AD-145: the scene applies the profile's meta locks, so the baseline must run under the same locks.
	var locked_base = Flow.new(SEED)
	locked_base.set_meta_locks(scene.flow.meta_locked_runes, scene.flow.meta_locked_artifacts)
	locked_base.start_new(SEED)
	_compare(t, _play(locked_base), _play(scene.flow), "AD-086 pause-menu retry same seed reproduces the first playthrough")
	viewport.queue_free()
