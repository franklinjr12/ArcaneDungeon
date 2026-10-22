extends RefCounted
## TASK-009: immutable-to-consumers typed event record.
const EVENT_TYPES := [
	"cast_requested","cost_paid","spawn","hit","status",
	"trigger","reaction","cleanup","rejected","budget_exceeded"
]
const DEFAULT_KEYS := ["event_id","sequence","cast_id","root_cast_id","formula_id","parent_effect_id","source_id","target_id","type","depth","position"]
var _value: Dictionary = {}

func from_dict(fields: Dictionary) -> Dictionary:
	if not fields.has("type") or typeof(fields["type"]) != TYPE_STRING or fields["type"] not in EVENT_TYPES:
		return {"ok":false,"issues":[{"code":"EVENT_TYPE_INVALID","path":"type","message":"Event must use an approved event type"}]}
	var normalized: Dictionary = {
		"event_id":int(fields.get("event_id",0)),
		"sequence":int(fields.get("sequence",0)),
		"cast_id":int(fields.get("cast_id",0)),
		"root_cast_id":int(fields.get("root_cast_id",fields.get("cast_id",0))),
		"formula_id":str(fields.get("formula_id","")),
		"parent_effect_id":int(fields.get("parent_effect_id",0)),
		"source_id":int(fields.get("source_id",0)),
		"target_id":int(fields.get("target_id",0)),
		"type":fields["type"],
		"depth":int(fields.get("depth",0)),
		"position":_normalize_position(fields.get("position",{"x":0,"y":0}))
	}
	if normalized["depth"] < 0:
		return {"ok":false,"issues":[{"code":"EVENT_DEPTH_INVALID","path":"depth","message":"Event depth cannot be negative"}]}
	_value = normalized
	return {"ok":true,"issues":[]}

func snapshot() -> Dictionary:
	return _value.duplicate(true)

static func _normalize_position(value: Variant) -> Dictionary:
	if typeof(value) == TYPE_VECTOR2:
		return {"x":value.x,"y":value.y}
	if typeof(value) == TYPE_DICTIONARY:
		return {"x":float(value.get("x",0)),"y":float(value.get("y",0))}
	return {"x":0.0,"y":0.0}
