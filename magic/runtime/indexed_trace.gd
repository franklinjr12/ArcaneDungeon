extends "res://debug/debug_trace.gd"
## AD-170: DebugTrace with a by-type index so per-tick consumers avoid scanning the whole trace.
var _by_type: Dictionary = {}

func _init(collect: bool = true) -> void:
	super(collect)

func record(kind: String, fields: Dictionary = {}) -> void:
	super(kind, fields)
	if not enabled:
		return
	if not _by_type.has(kind):
		_by_type[kind] = []
	_by_type[kind].append(_records[-1])

func clear() -> void:
	super()
	_by_type.clear()

func filter_records(cast_id: int = -1, formula_id: String = "", kind: String = "") -> Array:
	if kind.is_empty() or cast_id >= 0 or not formula_id.is_empty():
		return super(cast_id, formula_id, kind)
	return (_by_type.get(kind, []) as Array).duplicate(true)

func count_of(kind: String) -> int:
	return (_by_type.get(kind, []) as Array).size()

## Read-only view: callers must not mutate the returned records.
func records_since(kind: String, start: int) -> Array:
	return (_by_type.get(kind, []) as Array).slice(maxi(start, 0))
