extends RefCounted
## AD-183: local per-run JSON log under user://runs/ for friend-demo validation. No network, read-only w.r.t. the simulation.
const BuildInfo = preload("res://game/core/build_info.gd")
const FILE := "res://game/data/demo_v1.json"
const RUNS_DIR := "user://runs/"
const SCHEMA_VERSION := 1
## Test-only path override; changing it drops the cached value.
static var file_override := "":
	set(value):
		file_override = value
		_loaded = false
## Test-only target directory (must be under user://).
static var dir_override := ""
static var _enabled := false
static var _loaded := false

var build_version := ""
var build: Dictionary = {}
var seed_value := 0
var resumed := false
var started_at := ""
var ended_at := ""
var result := ""
var death = null
var rooms: Array = []
var total_seconds := 0.0
var spells_crafted: Array = []
var artifacts: Array = []
var enemy_deaths: Dictionary = {}
var written_path := ""
var _finished := false
var _room_wall_start := 0
var _room_start_tick := 0

static func enabled() -> bool:
	if not _loaded:
		_loaded = true
		var file := FileAccess.open(file_override if not file_override.is_empty() else FILE,FileAccess.READ)
		var parsed = JSON.parse_string(file.get_as_text()) if file != null else null
		_enabled = parsed is Dictionary and parsed.get("run_log_enabled",false) == true
	return _enabled

func begin(run_seed: int) -> void:
	build_version = BuildInfo.version()
	build = BuildInfo.as_dict()
	seed_value = run_seed
	started_at = Time.get_datetime_string_from_system(true)
	ended_at = ""
	result = ""
	death = null
	resumed = false
	rooms = []
	total_seconds = 0.0
	spells_crafted = []
	artifacts = []
	enemy_deaths = {}
	written_path = ""
	_finished = false
	_room_start_tick = 0
	_room_wall_start = Time.get_ticks_msec()

func _close_room() -> void:
	if not rooms.is_empty():
		rooms.back()["wall_seconds"] = float(Time.get_ticks_msec()-_room_wall_start)/1000.0

func enter_room(index: int, id: String, type: String, total_ticks: int) -> void:
	_close_room()
	rooms.append({"index":index,"id":id,"type":type,"seconds":0.0,"wall_seconds":0.0,"damage_taken":0.0})
	_room_start_tick = total_ticks
	_room_wall_start = Time.get_ticks_msec()

func sample(total_ticks: int, damage_taken: float, tick_rate: int) -> void:
	if rooms.is_empty() or tick_rate <= 0:
		return
	rooms.back()["seconds"] = float(total_ticks-_room_start_tick)/float(tick_rate)
	rooms.back()["damage_taken"] = damage_taken
	total_seconds = float(total_ticks)/float(tick_rate)

func add_enemy_death(kind: String) -> void:
	enemy_deaths[kind] = int(enemy_deaths.get(kind,0))+1

func add_spell(formula_id: String, slot: int, room_index: int, formula: Dictionary) -> void:
	spells_crafted.append({"formula_id":formula_id,"slot":slot,"room_index":room_index,"formula":formula.duplicate(true)})

func to_dict() -> Dictionary:
	return {"schema_version":SCHEMA_VERSION,"build_version":build_version,"build":build,"seed":seed_value,
		"resumed":resumed,"started_at":started_at,"ended_at":ended_at,"result":result,"death":death,
		"rooms":rooms,"total_seconds":total_seconds,"spells_crafted":spells_crafted,
		"artifacts":artifacts,"enemy_deaths":enemy_deaths}

func snapshot() -> Dictionary:
	var parsed = JSON.parse_string(JSON.stringify(to_dict()))
	return parsed if parsed is Dictionary else {}

func restore(data: Variant, run_seed: int) -> void:
	if data is Dictionary and data.get("rooms") is Array:
		build_version = str(data.get("build_version",BuildInfo.version()))
		build = data["build"] if data.get("build") is Dictionary else BuildInfo.as_dict()
		seed_value = int(data.get("seed",run_seed))
		started_at = str(data.get("started_at",""))
		ended_at = ""
		result = ""
		death = null
		rooms = data["rooms"]
		total_seconds = float(data.get("total_seconds",0.0))
		spells_crafted = data["spells_crafted"] if data.get("spells_crafted") is Array else []
		artifacts = []
		enemy_deaths = data["enemy_deaths"] if data.get("enemy_deaths") is Dictionary else {}
		written_path = ""
		_finished = false
		_room_start_tick = 0
		_room_wall_start = Time.get_ticks_msec()
	else:
		begin(run_seed)
	resumed = true

func finish(final_result: String, final_artifacts: Array, final_death: Variant) -> Error:
	if _finished:
		return ERR_ALREADY_EXISTS
	_finished = true
	ended_at = Time.get_datetime_string_from_system(true)
	result = final_result
	artifacts = final_artifacts.duplicate()
	artifacts.sort()
	death = final_death
	_close_room()
	if not enabled():
		return ERR_UNAVAILABLE
	if dir_override.is_empty() and DisplayServer.get_name() == "headless":
		return ERR_UNAVAILABLE
	var dir := dir_override if not dir_override.is_empty() else RUNS_DIR
	if not dir.begins_with("user://"):
		return ERR_INVALID_PARAMETER
	if not dir.ends_with("/"):
		dir += "/"
	var made := DirAccess.make_dir_recursive_absolute(dir)
	if made != OK:
		return made
	var stamp := ""
	for c in ended_at:
		if c >= "0" and c <= "9":
			stamp += c
	var base := "run_%s_%d" % [stamp,seed_value]
	var path := dir + base + ".json"
	var n := 0
	while FileAccess.file_exists(path):
		n += 1
		path = dir + base + "_%d.json" % n
	var tmp := path + ".tmp"
	var file := FileAccess.open(tmp,FileAccess.WRITE)
	if file == null:
		return FileAccess.get_open_error()
	file.store_string(JSON.stringify(to_dict(),"\t"))
	file.close()
	var renamed := DirAccess.rename_absolute(tmp,path)
	if renamed != OK:
		return renamed
	written_path = path
	return OK
