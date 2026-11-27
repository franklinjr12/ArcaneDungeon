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
## AD-256: caches. Rebuilt lazily after `_electrified`/`_frozen` change; `_cover` and `_all_cells` follow the rect set.
var _states_dirty := true
var _rects_cache: Array = []
var _view_cache: Array = []
var _cover := {}
var _all_cells: Array = []
var _all_cells_ready := false
## AD-261: edge frame indices per room load. Rebuilt lazily only when the rect set changes, never on state changes.
var _edge_cache := {}
var _edge_dirty := true
var edge_builds := 0

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
	_edge_dirty = true
	_build_bodies()
	_drop_uncovered()
	return removed

func _append(entries: Array) -> void:
	_edge_dirty = true
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
	_cover.clear()
	_all_cells = []
	_all_cells_ready = false
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
			_states_dirty = true

func electrify_body(body_id: int, until_tick: int) -> void:
	for i in _rects.size():
		if int(_body_ids[i]) == body_id:
			_electrify_rect(_rects[i],until_tick)

## AD-256: walks the cached covered-cell list (one dictionary op per cell), so calling it every tick stays cheap.
func electrify_all(until_tick: int) -> void:
	if not _all_cells_ready:
		var seen := {}
		for rect in _rects:
			for cell in _cells_in(rect):
				if not seen.has(cell) and _covered(cell):
					seen[cell] = true
					_all_cells.append(cell)
		_all_cells_ready = true
	for cell in _all_cells:
		_electrify_cell(cell,until_tick)

func _electrify_rect(rect: Rect2, until_tick: int) -> void:
	for cell in _cells_in(rect):
		if _covered(cell):
			_electrify_cell(cell,until_tick)

func _electrify_cell(cell: Vector2i, until_tick: int) -> void:
	if _frozen.has(cell):
		return
	var current := int(_electrified.get(cell,0))
	if current < until_tick:
		if current == 0:
			_states_dirty = true
		_electrified[cell] = until_tick

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
	_states_dirty = true

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
	_states_dirty = true

## Read-only, sorted by cell (y then x, then "electrified" before "frozen") so the order is deterministic. Cached between state changes.
func state_view() -> Array:
	_refresh_caches()
	return _view_cache

## AD-256: merged Rect2 spans covering exactly the electrified, non-frozen cells (horizontal runs per row, identical x-spans stacked vertically). Cached between state changes.
func electrified_rects() -> Array:
	_refresh_caches()
	return _rects_cache

const _SORT_BIAS := 32768

## Sort key (y, x, state) packed into one int so the sort needs no lambda: state 0 = electrified, 1 = frozen.
static func _pack(cell: Vector2i, state: int) -> int:
	return (((cell.y+_SORT_BIAS)<<16)|(cell.x+_SORT_BIAS))*2+state

static func _unpack(key: int) -> Array:
	var state := key&1
	var rest := key>>1
	return [Vector2i((rest&0xFFFF)-_SORT_BIAS,(rest>>16)-_SORT_BIAS),state]

func _refresh_caches() -> void:
	if not _states_dirty:
		return
	_states_dirty = false
	var keys: Array = []
	for cell in _frozen:
		keys.append(_pack(cell,1))
	for cell in _electrified:
		keys.append(_pack(cell,0))
	keys.sort()
	_view_cache = []
	var rows := {}
	for key in keys:
		var parts := _unpack(key)
		var cell: Vector2i = parts[0]
		_view_cache.append({"cell_rect":_cell_rect(cell),"state":"frozen" if int(parts[1]) == 1 else "electrified"})
		if int(parts[1]) == 0 and not _frozen.has(cell):
			if not rows.has(cell.y):
				rows[cell.y] = []
			rows[cell.y].append(cell.x)
	_rects_cache = _merge_rows(rows)

## rows: y -> ascending x list. Returns Rect2 spans sorted by (y, x).
func _merge_rows(rows: Dictionary) -> Array:
	var stacks := {}
	var ys: Array = rows.keys()
	ys.sort()
	for y in ys:
		var xs: Array = rows[y]
		var start: int = xs[0]
		var prev: int = start
		for i in range(1,xs.size()+1):
			if i < xs.size() and int(xs[i]) == prev+1:
				prev = xs[i]
				continue
			var span := Vector2i(start,prev)
			var open: Array = stacks.get(span,[])
			if not open.is_empty() and int(open[-1][1]) == y-1:
				open[-1][1] = y
			else:
				open.append([y,y])
			stacks[span] = open
			if i < xs.size():
				start = xs[i]
				prev = start
	var spans: Array = []
	for span in stacks:
		for ys_run in stacks[span]:
			spans.append([int(ys_run[0]),int(span.x),int(ys_run[1]),int(span.y)])
	spans.sort()
	return spans.map(func(s): return Rect2(float(s[1]*CELL),float(s[0]*CELL),float((s[3]-s[1]+1)*CELL),float((s[2]-s[0]+1)*CELL)))

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
	if _cover.has(cell):
		return _cover[cell]
	var box := _cell_rect(cell)
	var hit := false
	for rect in _rects:
		if box.intersects(rect):
			hit = true
			break
	_cover[cell] = hit
	return hit

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
				_states_dirty = true

## AD-261: neighbour bits (set = that neighbour is NOT water) in AD-260's order; CANON_MASKS is the sorted 47-frame table.
const BIT_N := 1
const BIT_NE := 2
const BIT_E := 4
const BIT_SE := 8
const BIT_S := 16
const BIT_SW := 32
const BIT_W := 64
const BIT_NW := 128
const CANON_MASKS := [0,1,2,4,5,8,9,10,16,17,18,20,21,32,33,34,36,37,40,41,42,64,65,66,68,69,72,73,74,80,81,82,84,85,128,130,132,136,138,144,146,148,160,162,164,168,170]
const _NEIGHBOURS := {BIT_N:Vector2i(0,-1),BIT_NE:Vector2i(1,-1),BIT_E:Vector2i(1,0),BIT_SE:Vector2i(1,1),BIT_S:Vector2i(0,1),BIT_SW:Vector2i(-1,1),BIT_W:Vector2i(-1,0),BIT_NW:Vector2i(-1,-1)}

## A corner bit only matters when both orthogonal neighbours around it are present; otherwise it is dropped.
static func canon_mask(mask: int) -> int:
	var m := mask&255
	for corner in [[BIT_NE,BIT_N|BIT_E],[BIT_SE,BIT_E|BIT_S],[BIT_SW,BIT_S|BIT_W],[BIT_NW,BIT_W|BIT_N]]:
		if m&int(corner[1]) != 0:
			m &= ~int(corner[0])
	return m

## Frame index 0..46 inside the shore / deep_step tag.
static func edge_index(mask: int) -> int:
	return CANON_MASKS.find(canon_mask(mask))

## cells: Vector2i-keyed Dictionary or Array of cells. Returns {cell: frame index} for cells with at least one missing neighbour.
static func edge_indices(cells) -> Dictionary:
	var set := {}
	for cell in cells:
		set[cell] = true
	var result := {}
	for cell in set:
		var mask := 0
		for bit in _NEIGHBOURS:
			if not set.has(cell+_NEIGHBOURS[bit]):
				mask |= int(bit)
		if mask != 0:
			result[cell] = edge_index(mask)
	return result

## AD-261: {"shore": edges of all water cells, "deep_step": edges of deep cells}. Built once per rect set.
func edge_cache() -> Dictionary:
	if _edge_dirty:
		var water := {}
		var deep := {}
		for entry in _entries:
			var rect: Rect2 = entry["rect"]
			var first := _cell_of(rect.position)
			var last := _cell_of(rect.end-Vector2(0.001,0.001))
			for y in range(first.y,last.y+1):
				for x in range(first.x,last.x+1):
					water[Vector2i(x,y)] = true
					if entry["kind"] == "deep":
						deep[Vector2i(x,y)] = true
		_edge_cache = {"shore":edge_indices(water),"deep_step":edge_indices(deep)}
		_edge_dirty = false
		edge_builds += 1
	return _edge_cache
