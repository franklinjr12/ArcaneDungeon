extends RefCounted
## AD-138: Stage 2 water tiles. Shallow water only Wets and conducts; deep water also blocks walking.
## Pure data + geometry, no rendering or RNG. Bodies are connected components of overlapping/touching rects.
const KINDS := ["shallow","deep"]
var _entries: Array = []
var _rects: Array = []
var _body_ids: Array = []
## AD-200: runtime per-cell states on top of the rects. Cells are keyed by Vector2i; values are the tick the state ends on (active while tick < until).
const CELL := 32
var _electrified := {}
var _frozen := {}
var _tick := 0

func _init(entries: Array = []) -> void:
	_append(entries)
	_build_bodies()

## AD-142: runtime toggle. Entries may carry an optional string `tag` so a whole group can be removed again.
func add_entries(entries: Array) -> void:
	_append(entries)
	_build_bodies()

## Removes every entry carrying `tag`; returns how many were removed.
func remove_tag(tag: String) -> int:
	var kept_entries: Array = []
	var kept_rects: Array = []
	for i in _entries.size():
		if _entries[i].has("tag") and _entries[i]["tag"] == tag:
			continue
		kept_entries.append(_entries[i])
		kept_rects.append(_rects[i])
	var removed := _entries.size()-kept_entries.size()
	_entries = kept_entries
	_rects = kept_rects
	_build_bodies()
	_drop_uncovered()
	return removed

func _append(entries: Array) -> void:
	for entry in entries:
		var dims: Array = entry["rect"]
		var parsed := {"kind":str(entry["kind"]),"rect":Rect2(float(dims[0]),float(dims[1]),float(dims[2]),float(dims[3]))}
		if entry.has("tag"):
			parsed["tag"] = str(entry["tag"])
		_entries.append(parsed)
		_rects.append(parsed["rect"])

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
		if entry.has("tag") and typeof(entry["tag"]) != TYPE_STRING:
			issues.append({"code":"WATER_TILE_INVALID","path":path+".tag","message":"tag must be a string"})
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
	if _frozen.has(_cell_of(pos)):
		return -1
	for i in _rects.size():
		if _rects[i].has_point(pos):
			return int(_body_ids[i])
	return -1

func view() -> Array:
	var result: Array = []
	for i in _entries.size():
		var item := {"kind":_entries[i]["kind"],"rect":_entries[i]["rect"],"body":int(_body_ids[i])}
		if _entries[i].has("tag"):
			item["tag"] = _entries[i]["tag"]
		result.append(item)
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

## AD-200: stores the current tick and purges expired cell states.
func advance(tick: int) -> void:
	_tick = tick
	_purge(_electrified)
	_purge(_frozen)

func _purge(states: Dictionary) -> void:
	for cell in states.keys():
		if int(states[cell]) <= _tick:
			states.erase(cell)

func electrify_body(body_id: int, until_tick: int) -> void:
	for i in _rects.size():
		if int(_body_ids[i]) == body_id:
			_electrify_rect(_rects[i],until_tick)

func electrify_all(until_tick: int) -> void:
	for rect in _rects:
		_electrify_rect(rect,until_tick)

func _electrify_rect(rect: Rect2, until_tick: int) -> void:
	for cell in _cells_in(rect):
		if not _frozen.has(cell) and _covered(cell):
			_electrified[cell] = maxi(int(_electrified.get(cell,0)),until_tick)

## Shallow cells only: deep water stays a ground blocker. A frozen cell loses any electrified state.
func freeze_circle(center: Vector2, radius: float, until_tick: int) -> void:
	var box := Rect2(center-Vector2(radius,radius),Vector2(radius,radius)*2.0)
	for cell in _cells_in(box):
		if _cell_center(cell).distance_to(center) <= radius:
			_freeze_cell(cell,until_tick)

func freeze_segment(from: Vector2, to: Vector2, radius: float, until_tick: int) -> void:
	var low := Vector2(minf(from.x,to.x),minf(from.y,to.y))-Vector2(radius,radius)
	var box := Rect2(low,Vector2(absf(to.x-from.x),absf(to.y-from.y))+Vector2(radius,radius)*2.0)
	for cell in _cells_in(box):
		var c := _cell_center(cell)
		if Geometry2D.get_closest_point_to_segment(c,from,to).distance_to(c) <= radius:
			_freeze_cell(cell,until_tick)

func _freeze_cell(cell: Vector2i, until_tick: int) -> void:
	if not _shallow_cell(cell):
		return
	_frozen[cell] = maxi(int(_frozen.get(cell,0)),until_tick)
	_electrified.erase(cell)

func is_electrified(pos: Vector2) -> bool:
	var cell := _cell_of(pos)
	return _electrified.has(cell) and not _frozen.has(cell) and in_water(pos)

func is_frozen(pos: Vector2) -> bool:
	return _frozen.has(_cell_of(pos))

## AD-201: true if any frozen cell centre lies within `radius` of `center`.
func frozen_near(center: Vector2, radius: float) -> bool:
	for cell in _frozen:
		if _cell_center(cell).distance_to(center) <= radius:
			return true
	return false

func clear_states() -> void:
	_electrified.clear()
	_frozen.clear()

## Read-only, sorted by cell (y then x) so the order is deterministic.
func state_view() -> Array:
	var view: Array = []
	for states in [[_frozen,"frozen"],[_electrified,"electrified"]]:
		for cell in states[0]:
			view.append({"cell":cell,"state":states[1]})
	view.sort_custom(func(a, b): return a["cell"].y < b["cell"].y or (a["cell"].y == b["cell"].y and (a["cell"].x < b["cell"].x or (a["cell"].x == b["cell"].x and a["state"] < b["state"]))))
	return view.map(func(item): return {"cell_rect":_cell_rect(item["cell"]),"state":item["state"]})

static func _cell_of(pos: Vector2) -> Vector2i:
	return Vector2i(floori(pos.x/CELL),floori(pos.y/CELL))

static func _cell_rect(cell: Vector2i) -> Rect2:
	return Rect2(Vector2(cell)*CELL,Vector2(CELL,CELL))

static func _cell_center(cell: Vector2i) -> Vector2:
	return (Vector2(cell)+Vector2(0.5,0.5))*CELL

func _cells_in(area: Rect2) -> Array:
	var first := _cell_of(area.position)
	var last := _cell_of(area.end)
	var cells: Array = []
	for y in range(first.y,last.y+1):
		for x in range(first.x,last.x+1):
			cells.append(Vector2i(x,y))
	return cells

## A cell holds states only if some water rect overlaps it.
func _covered(cell: Vector2i) -> bool:
	var box := _cell_rect(cell)
	for rect in _rects:
		if box.intersects(rect):
			return true
	return false

func _shallow_cell(cell: Vector2i) -> bool:
	var box := _cell_rect(cell)
	var shallow := false
	for entry in _entries:
		if box.intersects(entry["rect"]):
			if entry["kind"] == "deep":
				return false
			shallow = true
	return shallow

func _drop_uncovered() -> void:
	for states in [_electrified,_frozen]:
		for cell in states.keys():
			if not _covered(cell):
				states.erase(cell)
