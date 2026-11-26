extends RefCounted
## AD-261 step 1: cistern water edge autotile mapping (neighbour bitmask -> frame) and once-per-room-load edge cache.
const WaterTiles = preload("res://world/water_tiles.gd")
var _wt: GDScript = WaterTiles
const CANON := [0,1,2,4,5,8,9,10,16,17,18,20,21,32,33,34,36,37,40,41,42,64,65,66,68,69,72,73,74,80,81,82,84,85,128,130,132,136,138,144,146,148,160,162,164,168,170]
const N := 1
const NE := 2
const E := 4
const SE := 8
const S := 16
const SW := 32
const W := 64
const NW := 128
const DIRS := {N:Vector2i(0,-1),NE:Vector2i(1,-1),E:Vector2i(1,0),SE:Vector2i(1,1),S:Vector2i(0,1),SW:Vector2i(-1,1),W:Vector2i(-1,0),NW:Vector2i(-1,-1)}

func run(t) -> void:
	test_ad_261_a_bitmask_frame_mapping(t)
	test_ad_261_a2_edges_computed_once_per_room_load(t)

## Reference: canonical mask by the README rule, then its position in the sorted list.
func _expect(mask: int) -> int:
	var m := mask
	if m & NE and not (m & N or m & E): pass
	else: m &= ~NE
	if m & SE and not (m & E or m & S): pass
	else: m &= ~SE
	if m & SW and not (m & S or m & W): pass
	else: m &= ~SW
	if m & NW and not (m & W or m & N): pass
	else: m &= ~NW
	return CANON.find(m)

func _has(name: String) -> bool:
	return _wt.get_script_method_list().any(func(m): return m["name"] == name)

func _block(x0: int, y0: int, w: int, h: int) -> Dictionary:
	var cells := {}
	for y in range(y0, y0 + h):
		for x in range(x0, x0 + w):
			cells[Vector2i(x, y)] = true
	return cells

func _mask_of(cells: Dictionary, cell: Vector2i) -> int:
	var mask := 0
	for bit in DIRS:
		if not cells.has(cell + DIRS[bit]):
			mask |= bit
	return mask

func test_ad_261_a_bitmask_frame_mapping(t) -> void:
	var ok := _has("edge_indices")
	t.check(ok, "AD-261 test_ad_261_a_bitmask_frame_mapping: WaterTiles.edge_indices exists")
	ok = ok and _has("edge_index") and _has("canon_mask")
	t.check(ok, "AD-261 test_ad_261_a_bitmask_frame_mapping: edge_index and canon_mask exist")
	if not ok:
		return
	# (1) 3x3 block: centre interior, corners and edges follow the table
	var block := _block(0, 0, 3, 3)
	var idx: Dictionary = _wt.call("edge_indices", block)
	t.check(not idx.has(Vector2i(1, 1)), "AD-261 a: 3x3 centre has no edge entry")
	var expect := {Vector2i(0,0):N|W,Vector2i(2,0):N|E,Vector2i(0,2):S|W,Vector2i(2,2):S|E,Vector2i(1,0):N,Vector2i(1,2):S,Vector2i(0,1):W,Vector2i(2,1):E}
	for cell in expect:
		t.check(idx.get(cell, -1) == _expect(_mask_of(block, cell)), "AD-261 a: 3x3 cell %s index %d (got %d)" % [cell, _expect(_mask_of(block, cell)), idx.get(cell, -1)])
		t.check(CANON[_expect(expect[cell])] == expect[cell], "AD-261 a: 3x3 cell %s canonical mask is %d" % [cell, expect[cell]])
	# (2) channels
	var h := _block(0, 0, 5, 1)
	var hi: Dictionary = _wt.call("edge_indices", h)
	t.check(hi.get(Vector2i(2, 0), -1) == 9, "AD-261 a: horizontal 1-tile channel middle = index 9 (got %d)" % hi.get(Vector2i(2, 0), -1))
	var v := _block(0, 0, 1, 5)
	var vi: Dictionary = _wt.call("edge_indices", v)
	t.check(vi.get(Vector2i(0, 2), -1) == 24, "AD-261 a: vertical 1-tile channel middle = index 24 (got %d)" % vi.get(Vector2i(0, 2), -1))
	# (3) island
	var island: Dictionary = _wt.call("edge_indices", {Vector2i(7, 7):true})
	t.check(island.get(Vector2i(7, 7), -1) == 33, "AD-261 a: island index 33 (got %d)" % island.get(Vector2i(7, 7), -1))
	t.check(_wt.call("canon_mask", 255) == 85, "AD-261 a: canon_mask(255) == 85")
	# (4) diagonal-only
	t.check(_wt.call("edge_index", NE) == 2, "AD-261 a: only NE missing -> index 2")
	t.check(_wt.call("edge_index", N | NE) == 1, "AD-261 a: N+NE missing canonicalises to 1 -> index 1")
	var only_ne: Dictionary = _wt.call("edge_indices", _ring_without(Vector2i(1, -1)))
	t.check(only_ne.get(Vector2i(0, 0), -1) == 2, "AD-261 a: cell with only NE neighbour missing gets index 2 (got %d)" % only_ne.get(Vector2i(0, 0), -1))
	# (5) exhaustive
	var seen := {}
	var all_ok := true
	for m in 256:
		var e: int = _wt.call("edge_index", m)
		var c: int = _wt.call("canon_mask", m)
		if e < 0 or e > 46 or e != _wt.call("edge_index", c) or e != _expect(m):
			all_ok = false
		seen[e] = true
	t.check(all_ok, "AD-261 a: edge_index(m) == edge_index(canon_mask(m)) == reference, within 0..46")
	t.check(seen.size() == 47, "AD-261 a: all 47 frames reachable (got %d)" % seen.size())
	# (6) shallow rim -> deep: only the deep region's own rim gets entries
	var deep := _block(2, 2, 3, 3)
	var di: Dictionary = _wt.call("edge_indices", deep)
	var rim_ok := di.size() == 8 and not di.has(Vector2i(3, 3))
	for cell in di:
		rim_ok = rim_ok and deep.has(cell)
	t.check(rim_ok, "AD-261 a: deep region 3x3 inside shallow pool: 8 rim entries, none outside, none at centre (got %d)" % di.size())

## 3x3 block centred on (0,0) minus the NE cell.
func _ring_without(missing: Vector2i) -> Dictionary:
	var cells := _block(-1, -1, 3, 3)
	cells.erase(missing)
	return cells

func test_ad_261_a2_edges_computed_once_per_room_load(t) -> void:
	var entries := [{"kind":"shallow","rect":[0,0,192,192]},{"kind":"deep","rect":[64,64,64,64],"tag":"extra"}]
	var w = WaterTiles.new(entries)
	var ok: bool = w.has_method("edge_cache") and "edge_builds" in w
	t.check(ok, "AD-261 test_ad_261_a2_edges_computed_once_per_room_load: WaterTiles has edge_cache() and edge_builds")
	if not ok:
		return
	var cache: Dictionary = w.call("edge_cache")
	t.check(cache.has("shore") and cache.has("deep_step"), "AD-261 a2: edge_cache returns shore and deep_step")
	for i in 9:
		w.call("edge_cache")
	t.check(w.get("edge_builds") == 1, "AD-261 a2: ten edge_cache calls build once (got %d)" % w.get("edge_builds"))
	w.advance(5)
	w.electrify_all(100)
	w.freeze_circle(Vector2(96, 96), 40.0, 100)
	w.call("edge_cache")
	t.check(w.get("edge_builds") == 1, "AD-261 a2: advance/electrify/freeze do not rebuild (got %d)" % w.get("edge_builds"))
	w.add_entries([{"kind":"shallow","rect":[256,0,64,64],"tag":"more"}])
	w.call("edge_cache")
	w.call("edge_cache")
	t.check(w.get("edge_builds") == 2, "AD-261 a2: add_entries rebuilds once on next call (got %d)" % w.get("edge_builds"))
	w.remove_tag("more")
	w.call("edge_cache")
	w.call("edge_cache")
	t.check(w.get("edge_builds") == 3, "AD-261 a2: remove_tag rebuilds once on next call (got %d)" % w.get("edge_builds"))
