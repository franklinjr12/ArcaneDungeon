extends RefCounted
## TASK-010. No engine object identifiers, wall clock timestamps or rendering state.
const ALLOWED_FIELDS := [
	"type","cast_id","root_cast_id","formula_id","parent_effect_id","effect_id",
	"event_id","sequence","source_id","target_id","position","depth",
	"amount","reason","limit","tick"
]
var enabled := true
var _records: Array = []

func _init(collect: bool = true) -> void:
	enabled = collect

func record(kind: String, fields: Dictionary = {}) -> void:
	if not enabled:
		return
	var normalized: Dictionary = {"type":kind}
	for key in ALLOWED_FIELDS:
		if key != "type" and fields.has(key):
			if key == "position":
				normalized[key] = _position(fields[key])
			elif key in ["cast_id","root_cast_id","parent_effect_id","effect_id","event_id","sequence","source_id","target_id","depth","amount","limit","tick"]:
				normalized[key] = int(fields[key])
			else:
				normalized[key] = fields[key]
	_records.append(normalized)

func filter_records(cast_id: int = -1, formula_id: String = "", kind: String = "") -> Array:
	var output: Array = []
	for entry in _records:
		if cast_id >= 0 and int(entry.get("cast_id",-1)) != cast_id:
			continue
		if not formula_id.is_empty() and str(entry.get("formula_id","")) != formula_id:
			continue
		if not kind.is_empty() and str(entry.get("type","")) != kind:
			continue
		output.append(entry.duplicate(true))
	return output

func snapshot() -> Array:
	return _records.duplicate(true)

func to_json() -> String:
	return JSON.stringify(snapshot())

func export_json(path: String) -> Error:
	var f := FileAccess.open(path,FileAccess.WRITE)
	if f == null:
		return FileAccess.get_open_error()
	f.store_string(to_json()+"\n")
	f.close()
	return OK

func clear() -> void:
	_records.clear()

static func _position(p: Variant) -> Dictionary:
	if typeof(p) == TYPE_VECTOR2:
		return {"x":float(p.x),"y":float(p.y)}
	if typeof(p) == TYPE_DICTIONARY:
		return {"x":float(p.get("x",0)),"y":float(p.get("y",0))}
	return {"x":0.0,"y":0.0}
