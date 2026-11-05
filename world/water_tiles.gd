extends RefCounted
## AD-138: Stage 2 water tiles. Shallow water only Wets and conducts; deep water also blocks walking.
## Pure data + geometry, no rendering or RNG. Bodies are connected components of overlapping/touching rects.
const KINDS := ["shallow","deep"]
var _entries: Array = []
var _rects: Array = []
var _body_ids: Array = []

func _init(entries: Array = []) -> void:
	for entry in entries:
		var dims: Array = entry["rect"]
		_entries.append({"kind":str(entry["kind"]),"rect":Rect2(float(dims[0]),float(dims[1]),float(dims[2]),float(dims[3]))})
		_rects.append(_entries.back()["rect"])
	_build_bodies()

static func validate(entries) -> Array:
	var issues: Array = []
	if typeof(entries) != TYPE_ARRAY:
		issues.append({"code":"WATER_TILE_INVALID","path":"water","message":"water must be an array"})
		return issues
	for i in entries.size():
		var path := "water[%d]" % i
		var entry = entries[i]
		if typeof(entry) != TYPE_DICTIONARY:
			issues.append({"code":"WATER_TILE_INVALID","path":path,"message":"entry must be an object"})
			continue
		if not KINDS.has(str(entry.get("kind",""))):
			issues.append({"code":"WATER_TILE_INVALID","path":path+".kind","message":"kind must be shallow or deep"})
		var dims = entry.get("rect")
		var good: bool = typeof(dims) == TYPE_ARRAY and dims.size() == 4
		if good:
			for v in dims:
				if typeof(v) != TYPE_INT and typeof(v) != TYPE_FLOAT:
					good = false
			good = good and float(dims[2]) > 0.0 and float(dims[3]) > 0.0
		if not good:
			issues.append({"code":"WATER_TILE_INVALID","path":path+".rect","message":"rect must be [x,y,w,h] numbers with w,h > 0"})
	return issues

func deep_rects() -> Array[Rect2]:
	var result: Array[Rect2] = []
	for entry in _entries:
		if entry["kind"] == "deep":
			result.append(entry["rect"])
	return result

## The body centre decides; radius is accepted for API symmetry with other ground rules.
func in_water(pos: Vector2, _radius: float = 0.0) -> bool:
	return body_of(pos) >= 0

func body_of(pos: Vector2) -> int:
	for i in _rects.size():
		if _rects[i].has_point(pos):
			return int(_body_ids[i])
	return -1

func view() -> Array:
	var result: Array = []
	for i in _entries.size():
		result.append({"kind":_entries[i]["kind"],"rect":_entries[i]["rect"],"body":int(_body_ids[i])})
	return result

func _build_bodies() -> void:
	_body_ids.resize(_rects.size())
	_body_ids.fill(-1)
	var next_body := 0
	for i in _rects.size():
		if int(_body_ids[i]) >= 0:
			continue
		_body_ids[i] = next_body
		var queue: Array = [i]
		while not queue.is_empty():
			var current: int = queue.pop_front()
			for j in _rects.size():
				if int(_body_ids[j]) < 0 and _touches(_rects[current],_rects[j]):
					_body_ids[j] = next_body
					queue.append(j)
		next_body += 1

static func _touches(a: Rect2, b: Rect2) -> bool:
	return a.position.x <= b.end.x and b.position.x <= a.end.x and a.position.y <= b.end.y and b.position.y <= a.end.y
