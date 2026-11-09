extends Node
## AD-187: non-rendering core of the reference-PC perf run (room setup, stats, JSON report schema).
const BuildInfo = preload("res://game/core/build_info.gd")
const Settings = preload("res://game/core/settings.gd")
const FILE := "res://game/data/perf_run_v1.json"
const REPORT_SCHEMA_VERSION := 1
const STATS_KEYS := ["p50", "p95", "max"]

static func config() -> Dictionary:
	var file := FileAccess.open(FILE, FileAccess.READ)
	var parsed = JSON.parse_string(file.get_as_text()) if file != null else null
	return parsed if parsed is Dictionary else {}

static func prepare_room(flow, room_id: String, cfg: Dictionary) -> Dictionary:
	var idx := -1
	for i in flow.rooms.size():
		if str(flow.rooms[i]["id"]) == room_id:
			idx = i
	var out := {"ok": false, "error": "", "room_id": room_id}
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
	var grid: Dictionary = cfg["spawn_grid"]
	var spawned := 0
	var tries := 0
	for gy in range(int(grid["y"][0]), int(grid["y"][1]), int(grid["y"][2])):
		for gx in range(int(grid["x"][0]), int(grid["x"][1]), int(grid["x"][2])):
			if spawned >= want:
				break
			if session.spawn_enemy(kinds[tries % kinds.size()], Vector2(gx, gy)) != null:
				spawned += 1
			tries += 1
	out["enemies_spawned"] = spawned
	var hp := float(cfg["enemy_health"])
	for e in session.enemies:
		e.target.health.maximum = hp
		e.target.health.current = hp
	var sim = session.sim
	sim.loadout.unlocked = sim.registry.get_ids()
	sim.loadout.allow_edit = true
	var eq: Dictionary = sim.equip(1, cfg["worst_formula"])
	out["equip_ok"] = bool(eq.get("ok", false))
	if not out["equip_ok"]:
		out["error"] = "equip failed " + str(eq.get("issues", []))
		return out
	out["complexity"] = sim.loadout.get_plan(1).complexity()
	out["ok"] = true
	return out

static func refill(session) -> void:
	session.sim.actor.health.current = session.sim.actor.health.maximum
	session.sim.mana = float(session.sim.settings["combat"]["player_max_mana"])
	for e in session.enemies:
		e.target.health.current = maxf(e.target.health.current, 1e5)

static func command(session) -> Dictionary:
	var aim := Vector2.RIGHT
	var cursor: Vector2 = session.sim.actor.position + aim * 100.0
	for e in session.enemies:
		if e.target.alive():
			cursor = e.target.position
			aim = (cursor - session.sim.actor.position).normalized()
			break
	return {"move": Vector2.ZERO, "aim": aim, "cursor": cursor, "cast": 1, "dash": false}

static func sample_stats(usec: Array) -> Dictionary:
	var n := usec.size()
	if n == 0:
		return {"p50": 0.0, "p95": 0.0, "max": 0.0}
	var s := usec.duplicate()
	s.sort()
	return {
		"p50": float(s[clampi(roundi(n * 0.5), 0, n - 1)]) / 1000.0,
		"p95": float(s[clampi(roundi(n * 0.95), 0, n - 1)]) / 1000.0,
		"max": float(s[n - 1]) / 1000.0}

static func build_report(cfg: Dictionary, rooms: Array, meta: Dictionary) -> Dictionary:
	var target := float(cfg.get("target_p95_frame_ms", 16.7))
	var out_rooms: Array = []
	for r in rooms:
		var room: Dictionary = r.duplicate(true)
		room["pass"] = float(room["frame_ms"]["p95"]) <= target
		out_rooms.append(room)
	return {
		"schema_version": REPORT_SCHEMA_VERSION,
		"build": BuildInfo.as_dict(),
		"timestamp": str(meta.get("timestamp", Time.get_datetime_string_from_system())),
		"seed": int(cfg.get("seed", 0)),
		"ticks_per_room": int(cfg.get("ticks_per_room", 0)),
		"warmup_frames": int(cfg.get("warmup_frames", 0)),
		"lighting": str(meta.get("lighting", "high")),
		"headless": bool(meta.get("headless", false)),
		"window_size": meta.get("window_size", [0, 0]),
		"renderer": str(meta.get("renderer", "")),
		"target_p95_frame_ms": target,
		"rooms": out_rooms}

static func _is_num(v) -> bool:
	return typeof(v) == TYPE_FLOAT or typeof(v) == TYPE_INT

## JSON parsing yields floats for integers, so an integral float counts as an int.
static func _type_ok(v, type: int) -> bool:
	if type == TYPE_INT and typeof(v) == TYPE_FLOAT:
		return v == floorf(v)
	return typeof(v) == type

static func _check_stats(v, label: String, issues: Array) -> void:
	if not v is Dictionary:
		issues.append(label + " must be a dictionary")
		return
	for k in STATS_KEYS:
		if not v.has(k):
			issues.append("%s missing %s" % [label, k])
		elif not _is_num(v[k]):
			issues.append("%s.%s must be a number" % [label, k])

static func validate_report(report) -> Array:
	var issues: Array = []
	if not report is Dictionary:
		return ["report must be a dictionary"]
	var types := {"schema_version": TYPE_INT, "build": TYPE_DICTIONARY, "timestamp": TYPE_STRING,
		"seed": TYPE_INT, "ticks_per_room": TYPE_INT, "warmup_frames": TYPE_INT, "lighting": TYPE_STRING,
		"headless": TYPE_BOOL, "window_size": TYPE_ARRAY, "renderer": TYPE_STRING, "rooms": TYPE_ARRAY}
	for k in types:
		if not report.has(k):
			issues.append("missing " + k)
		elif not _type_ok(report[k], types[k]):
			issues.append("wrong type for " + k)
	if not report.has("target_p95_frame_ms"):
		issues.append("missing target_p95_frame_ms")
	elif not _is_num(report["target_p95_frame_ms"]):
		issues.append("wrong type for target_p95_frame_ms")
	if report.get("schema_version") is float or report.get("schema_version") is int:
		if int(report["schema_version"]) != REPORT_SCHEMA_VERSION:
			issues.append("unsupported schema_version")
	if report.get("lighting") is String and not report["lighting"] in Settings.LIGHTING_MODES:
		issues.append("unknown lighting " + str(report["lighting"]))
	if report.get("window_size") is Array:
		var ws: Array = report["window_size"]
		if ws.size() != 2 or not _is_num(ws[0]) or not _is_num(ws[1]):
			issues.append("window_size must be [w,h]")
	if not report.get("rooms") is Array:
		return issues
	var want: Array = config().get("rooms", [])
	var got: Array = []
	var target := float(report.get("target_p95_frame_ms", 0.0)) if _is_num(report.get("target_p95_frame_ms")) else 0.0
	for i in report["rooms"].size():
		var r = report["rooms"][i]
		var label := "rooms[%d]" % i
		if not r is Dictionary:
			issues.append(label + " must be a dictionary")
			continue
		got.append(str(r.get("room_id", "")))
		for k in ["room_id", "stage", "type"]:
			if not r.has(k):
				issues.append("%s missing %s" % [label, k])
		if r.has("room_id") and not r["room_id"] is String:
			issues.append(label + ".room_id must be a string")
		if r.has("type") and not r["type"] is String:
			issues.append(label + ".type must be a string")
		for k in ["stage", "frames", "enemies_spawned", "peak_enemies_alive", "peak_effects"]:
			if not r.has(k):
				issues.append("%s missing %s" % [label, k])
			elif not _is_num(r[k]):
				issues.append("%s.%s must be an int" % [label, k])
		_check_stats(r.get("frame_ms"), label + ".frame_ms", issues)
		_check_stats(r.get("sim_ms"), label + ".sim_ms", issues)
		if not r.get("pass") is bool:
			issues.append(label + ".pass must be a bool")
		elif r.get("frame_ms") is Dictionary and _is_num(r["frame_ms"].get("p95")) \
				and bool(r["pass"]) != (float(r["frame_ms"]["p95"]) <= target):
			issues.append(label + ".pass disagrees with frame_ms.p95")
	if got != want:
		issues.append("rooms must be exactly %s, got %s" % [str(want), str(got)])
	return issues

static func write_report(report: Dictionary, dir: String = "user://perf") -> String:
	if DirAccess.make_dir_recursive_absolute(dir) != OK:
		return ""
	var stamp := Time.get_datetime_string_from_system().replace(":", "-")
	var path := "%s/%s.json" % [dir, stamp]
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		return ""
	file.store_string(JSON.stringify(report, "\t"))
	file.close()
	return path


# ---- live driver (AD-187): plays the fixed script through the real run scene ----
const RUN_SCENE := "res://scenes/run.tscn"

var cfg: Dictionary = {}
var _rooms_left: Array = []
var _room_id := ""
var _info: Dictionary = {}
var _ctrl = null
var _frame_usec: Array = []
var _sim_usec: Array = []
var _seen := 0
var _last_usec := 0
var _peak_enemies := 0
var _peak_effects := 0
var _ticks := 0
var _results: Array = []
var _active := false
var _done := false

static func _args() -> Array:
	return Array(OS.get_cmdline_user_args()) + Array(OS.get_cmdline_args())

static func requested() -> bool:
	return "--perf-run" in _args()

static func _arg_value(name: String) -> String:
	var prefix := name + "="
	for a in _args():
		if str(a).begins_with(prefix):
			return str(a).substr(prefix.length())
	return ""

static func launch(tree: SceneTree) -> void:
	tree.root.add_child.call_deferred(load("res://game/core/perf_run.gd").new())

func _fail(reason: String) -> void:
	if _done:
		return
	_done = true
	_active = false
	print("PERF_RUN_FAIL ", reason)
	get_tree().quit(1)

func _ready() -> void:
	name = "PerfRun"
	Engine.max_fps = 0
	if DisplayServer.get_name() != "headless":
		DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	cfg = config()
	if cfg.is_empty():
		_fail("config missing")
		return
	var ticks := _arg_value("--perf-ticks")
	if ticks != "":
		if not ticks.is_valid_int() or int(ticks) < 1:
			_fail("invalid --perf-ticks " + ticks)
			return
		cfg["ticks_per_room"] = int(ticks)
	var light := _arg_value("--perf-lighting")
	if light != "":
		if not light in Settings.LIGHTING_MODES:
			_fail("invalid --perf-lighting " + light)
			return
		var save = get_node_or_null("/root/SaveService")
		if save != null:
			save.settings.lighting = light # in memory only, never saved
	_rooms_left = cfg["rooms"].duplicate()
	for n in get_tree().root.get_children():
		if n is Control and n.get_script() != null and str(n.get_script().resource_path) == "res://ui/main_menu.gd":
			n.queue_free()
	_next_room()

func _next_room() -> void:
	_active = false
	if _rooms_left.is_empty():
		_finish()
		return
	_room_id = str(_rooms_left.pop_front())
	var ctrl = load(RUN_SCENE).instantiate()
	ctrl.perf_seed = int(cfg["seed"])
	ctrl.show_dev_tools = false
	get_tree().root.add_child(ctrl)
	_ctrl = ctrl
	_info = prepare_room(ctrl.flow, _room_id, cfg)
	if not _info["ok"]:
		_fail("%s: %s" % [_room_id, _info["error"]])
		return
	ctrl._redraw_panel()
	_frame_usec = []
	_sim_usec = []
	_seen = 0
	_ticks = 0
	_peak_enemies = 0
	_peak_effects = 0
	_last_usec = 0
	_active = true

func _process(_delta: float) -> void:
	if not _active:
		return
	var now := Time.get_ticks_usec()
	var frame_usec := now - _last_usec
	var had_prev := _last_usec != 0
	_last_usec = now
	var flow = _ctrl.flow
	if flow.state != "fighting":
		_fail("%s: left fighting state (%s)" % [_room_id, flow.state])
		return
	refill(flow.session)
	_ctrl.perf_step(command(flow.session))
	if not had_prev:
		return
	_seen += 1
	if _seen <= int(cfg["warmup_frames"]):
		return
	_frame_usec.append(frame_usec)
	_sim_usec.append(_ctrl.last_sim_usec)
	var alive := 0
	for e in flow.session.enemies:
		if e.target.alive():
			alive += 1
	_peak_enemies = maxi(_peak_enemies, alive)
	_peak_effects = maxi(_peak_effects, flow.session.sim.queue.active_effect_count())
	if _frame_usec.size() >= int(cfg["ticks_per_room"]):
		_finish_room()

func _finish_room() -> void:
	_active = false
	var room: Dictionary = _info.duplicate()
	for k in ["ok", "error", "boss_present", "equip_ok", "complexity"]:
		room.erase(k)
	room["frames"] = _frame_usec.size()
	room["frame_ms"] = sample_stats(_frame_usec)
	room["sim_ms"] = sample_stats(_sim_usec)
	room["peak_enemies_alive"] = _peak_enemies
	room["peak_effects"] = _peak_effects
	_results.append(room)
	_ctrl.queue_free()
	_ctrl = null
	await get_tree().process_frame
	_next_room()

func _finish() -> void:
	var save = get_node_or_null("/root/SaveService")
	var meta := {
		"lighting": save.settings.lighting if save != null else "high",
		"headless": DisplayServer.get_name() == "headless",
		"window_size": [get_window().size.x, get_window().size.y],
		"renderer": RenderingServer.get_current_rendering_method()}
	var report := build_report(cfg, _results, meta)
	var issues := validate_report(report)
	if not issues.is_empty():
		_fail("invalid report " + str(issues))
		return
	var path := write_report(report)
	if path == "":
		_fail("write failed")
		return
	_done = true
	print("PERF_RUN_OK path=", ProjectSettings.globalize_path(path))
	for r in _results:
		print("  %s frame_p95=%.2f ms sim_p95=%.2f ms" % [r["room_id"], r["frame_ms"]["p95"], r["sim_ms"]["p95"]])
	get_tree().quit(0)
