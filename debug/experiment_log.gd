extends RefCounted
## TASK-052: opt-in local-only experiment events; never persist device/user IDs or free text.
const SCHEMA := 1
const KINDS := ["formula_edit","rune_choice","test_cast","dungeon_cast","reaction",
	"death","room_clear","editor_open","editor_close","room_enter","purchase","run_restart"]
var enabled := false
var records: Array = []
var clock_ms: int = 0
var _start_ms: int = 0
var _last_edit_tick := -1
var _signatures: Dictionary = {}

func configure(opt_in: bool) -> void:
	enabled = opt_in
	if enabled:
		_start_ms = Time.get_ticks_msec()
		clock_ms = 0
	if not enabled:
		records.clear()
		_signatures.clear()
		_last_edit_tick = -1

static func signature(formula: Dictionary) -> String:
	# Only mechanics/rune IDs, never user-entered display names or free-form text.
	var root: Dictionary = formula.get("root",{})
	var mods: Array = root.get("modifier_ids",[]).duplicate()
	mods.sort()
	var parts := [str(root.get("essence_id","")),str(root.get("manifestation_id","")),",".join(mods)]
	if formula.has("on_hit"):
		var payload: Dictionary = formula["on_hit"].get("payload",{})
		parts.append(str(formula["on_hit"].get("trigger_id","")))
		parts.append(str(payload.get("essence_id","")))
		parts.append(str(payload.get("manifestation_id","")))
	return "|".join(parts).sha256_text().substr(0,16)

func mark_tick(_sim_tick: int) -> void:
	if enabled:
		clock_ms = maxi(0,Time.get_ticks_msec()-_start_ms)

func record(kind: String, properties: Dictionary = {}, formula: Dictionary = {}) -> void:
	if not enabled or kind not in KINDS:
		return
	mark_tick(0)
	var safe: Dictionary = {}
	# Deliberate allowlist: no player strings, coordinates, identity or raw formulas.
	for key in ["room_index","slot","count","duration_ms","cast_accepted","reaction_count","rune_index","price","is_workshop"]:
		if properties.has(key) and typeof(properties[key]) in [TYPE_INT,TYPE_FLOAT,TYPE_BOOL]:
			safe[key] = properties[key]
	if not formula.is_empty():
		var token := signature(formula)
		safe["formula_signature"] = token
		_signatures[token] = true
		if kind == "formula_edit":
			_last_edit_tick = clock_ms
	if kind == "test_cast" and _last_edit_tick >= 0:
		safe["edit_to_test_ms"] = maxi(0,clock_ms-_last_edit_tick)
		_last_edit_tick = -1
	records.append({"type":kind,"elapsed_ms":clock_ms,"fields":safe})
	if records.size() > 10000:
		records.remove_at(0)

func summary() -> Dictionary:
	var counts: Dictionary = {}
	var tests: Array = []
	for event in records:
		var kind: String = event["type"]
		counts[kind] = int(counts.get(kind,0))+1
		if event["fields"].has("edit_to_test_ms"):
			tests.append(event["fields"]["edit_to_test_ms"])
	return {"enabled":enabled,"events":records.size(),"counts":counts,
		"distinct_formulas":_signatures.size(),"edit_to_test_ms":tests.duplicate()}

func snapshot() -> Dictionary:
	return {"schema_version":SCHEMA,"anonymous":true,"external_upload":false,
		"events":records.duplicate(true),"summary":summary()}

func export_json(path: String = "user://arcane_m4_experiment.json") -> Error:
	if not enabled:
		return ERR_UNAVAILABLE
	var file := FileAccess.open(path,FileAccess.WRITE)
	if file == null:
		return FileAccess.get_open_error()
	file.store_string(JSON.stringify(snapshot(),"\t"))
	return OK

func export_csv(path: String = "user://arcane_m4_experiment.csv") -> Error:
	if not enabled:
		return ERR_UNAVAILABLE
	var file := FileAccess.open(path,FileAccess.WRITE)
	if file == null:
		return FileAccess.get_open_error()
	file.store_line("type,elapsed_ms,room_index,slot,formula_signature,edit_to_test_ms,cast_accepted,reaction_count")
	for event in records:
		var fields: Dictionary = event["fields"]
		var line: Array = [event["type"],event["elapsed_ms"]]
		for key in ["room_index","slot","formula_signature","edit_to_test_ms","cast_accepted","reaction_count"]:
			line.append(fields.get(key,""))
		# Numeric / hashed / fixed type values only; no CSV injection content accepted.
		file.store_line(",".join(line.map(func(v):return str(v))))
	return OK
