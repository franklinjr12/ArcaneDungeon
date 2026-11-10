extends SceneTree
## Headless schematic screenshot sheet of a room-template JSON (Image API only, no display needed).
## Usage: godot --headless --path . --script res://tools/room_layout_sheet.gd -- <rooms_json_res_path> <out_png_path> [--stage=<id>]
## --stage=<id> (AD-202) reads a run_v2-style JSON: stages[id].pool + optional_room, templates merged with room_template_files.
## Exit codes: 0 ok, 1 load/usage/save error.
const SCALE := 5
const ARENA_W := 1320
const ARENA_H := 900
const TILE_W := ARENA_W / SCALE
const TILE_H := ARENA_H / SCALE
const COLUMNS := 4
const GAP := 4
const SPAWN_RING := 160

const C_BG := Color(0.02, 0.02, 0.03)
const C_FLOOR := Color(0.11, 0.1, 0.13)
const C_WALL := Color(0.5, 0.5, 0.55)
const C_SHALLOW := Color(0.45, 0.7, 0.95)
const C_DEEP := Color(0.08, 0.2, 0.55)
const C_ENTRANCE := Color(0.2, 0.45, 1.0)
const C_REWARD := Color(1.0, 0.9, 0.2)
const C_EXIT := Color(0.2, 0.85, 0.3)
const C_PROP := Color(0.7, 0.55, 0.35)
const C_ON_CLEAR := Color(0.95, 0.1, 0.1)
const C_PEDESTAL := Color(1.0, 0.45, 0.75)
const C_PIT := Color(0.005, 0.005, 0.01)
const C_COVER := Color(0.45, 0.4, 0.34)
const C_BURNABLE := Color(1.0, 0.5, 0.1)
const C_PUDDLE := Color(0.2, 0.9, 0.95)
const C_BRAZIER := Color(0.95, 0.15, 0.1)
const C_BREAKABLE := Color(1.0, 0.8, 0.2)
const C_MARK := Color(0.9, 0.9, 0.9)
const SHAPE_COLORS := {
	"open_hall": Color(0.9, 0.9, 0.9), "pillared_hall": Color(0.95, 0.6, 0.2), "corridor_chamber": Color(0.3, 0.8, 0.4),
	"ring_pit": Color(0.6, 0.3, 0.9), "split_bridges": Color(0.3, 0.6, 1.0), "cross_hall": Color(1.0, 0.3, 0.5),
	"l_bend": Color(0.9, 0.9, 0.2), "colonnade": Color(0.4, 0.9, 0.9), "dais_island": Color(0.7, 0.5, 0.3),
}
const BURNABLE_KINDS := ["crate", "cobweb"]
const BREAKABLE_KINDS := ["urn", "cracked_wall", "cracked_pillar", "broken_wall"]
const ENEMY_COLORS := {
	"bone_thrall": Color(1, 1, 1),
	"fallen_adept": Color(0.65, 0.3, 0.9),
	"grave_hound": Color(1.0, 0.55, 0.1),
}
const C_ENEMY_OTHER := Color(1.0, 0.0, 1.0)

var _img: Image
var _ox := 0
var _oy := 0

func _initialize() -> void:
	call_deferred("_run")

func _fail(msg: String) -> void:
	push_error("room_layout_sheet: " + msg)
	quit(1)

func _load_json(path: String):
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		return null
	return JSON.parse_string(f.get_as_text())

func _run() -> void:
	var args := OS.get_cmdline_user_args()
	var stage := ""
	var positional: Array = []
	for arg in args:
		if arg.begins_with("--stage="):
			stage = arg.substr(8)
		else:
			positional.append(arg)
	if positional.size() < 2:
		_fail("usage: -- <rooms_json_res_path> <out_png_path> [--stage=<id>]")
		return
	args = PackedStringArray(positional)
	var data = _load_json(args[0])
	var tuning = _load_json("res://combat/combat_tuning_v1.json")
	if not (data is Dictionary) or not (tuning is Dictionary):
		_fail("cannot load " + args[0] + " or combat tuning")
		return
	var templates: Dictionary = data.get("room_templates", {}).duplicate()
	var ids: Array = []
	if stage.is_empty():
		ids.append_array(data.get("pool", []))
		for key in ["treasure_room", "challenge_room"]:
			if data.has(key):
				ids.append(data[key])
	else:
		for path in data.get("room_template_files", []):
			var doc = _load_json(path)
			if doc is Dictionary:
				templates.merge(doc.get("room_templates", {}))
		var found := false
		for entry in data.get("stages", []):
			if entry.get("id", "") == stage:
				found = true
				ids.append_array(entry.get("pool", []))
				if entry.has("optional_room"):
					ids.append(entry["optional_room"])
		if not found:
			_fail("no stage " + stage + " in " + args[0])
			return
	var shared_walls: Array = tuning.get("arena", {}).get("walls", [])
	var rows := int(ceil(float(ids.size()) / COLUMNS))
	_img = Image.create(COLUMNS * TILE_W + (COLUMNS + 1) * GAP, maxi(rows, 1) * TILE_H + (rows + 1) * GAP, false, Image.FORMAT_RGBA8)
	_img.fill(C_BG)
	for i in ids.size():
		if not templates.has(ids[i]):
			_fail("missing template " + str(ids[i]))
			return
		_ox = GAP + (i % COLUMNS) * (TILE_W + GAP)
		_oy = GAP + (i / COLUMNS) * (TILE_H + GAP)
		var template: Dictionary = templates[ids[i]].duplicate()
		template["_sheet_index"] = i
		_draw_template(template, shared_walls)
	var out: String = args[1]
	if _img.save_png(out) != OK:
		_fail("cannot save " + out)
		return
	quit(0)

func _rect(r: Array, c: Color) -> void:
	var x0 := clampi(int(r[0]) / SCALE, 0, TILE_W)
	var y0 := clampi(int(r[1]) / SCALE, 0, TILE_H)
	var x1 := clampi(int(ceil(float(int(r[0]) + int(r[2])) / SCALE)), 0, TILE_W)
	var y1 := clampi(int(ceil(float(int(r[1]) + int(r[3])) / SCALE)), 0, TILE_H)
	if x1 > x0 and y1 > y0:
		_img.fill_rect(Rect2i(_ox + x0, _oy + y0, x1 - x0, y1 - y0), c)

func _px(x: int, y: int, c: Color) -> void:
	if x >= 0 and y >= 0 and x < TILE_W and y < TILE_H:
		_img.set_pixel(_ox + x, _oy + y, c)

func _disc(p: Array, r: int, c: Color) -> void:
	var cx := int(p[0]) / SCALE
	var cy := int(p[1]) / SCALE
	for dy in range(-r, r + 1):
		for dx in range(-r, r + 1):
			if dx * dx + dy * dy <= r * r:
				_px(cx + dx, cy + dy, c)

func _ring(p: Array, r: int, c: Color) -> void:
	var cx := int(p[0]) / SCALE
	var cy := int(p[1]) / SCALE
	for dy in range(-r - 1, r + 2):
		for dx in range(-r - 1, r + 2):
			var d2 := dx * dx + dy * dy
			if d2 <= r * r + r and d2 >= (r - 1) * (r - 1):
				_px(cx + dx, cy + dy, c)

func _diamond(p: Array, r: int, c: Color) -> void:
	var cx := int(p[0]) / SCALE
	var cy := int(p[1]) / SCALE
	for dy in range(-r, r + 1):
		for dx in range(-r, r + 1):
			if absi(dx) + absi(dy) <= r:
				_px(cx + dx, cy + dy, c)

func _frame(rect: Rect2i, c: Color) -> void:
	for x in range(rect.position.x, rect.end.x):
		_px(x, rect.position.y, c)
		_px(x, rect.end.y - 1, c)
	for y in range(rect.position.y, rect.end.y):
		_px(rect.position.x, y, c)
		_px(rect.end.x - 1, y, c)

func _draw_template(t: Dictionary, shared_walls: Array) -> void:
	_img.fill_rect(Rect2i(_ox, _oy, TILE_W, TILE_H), C_FLOOR)
	var layout: Dictionary = t.get("layout", {})
	for w in layout.get("water", []):
		_rect(w["rect"], C_DEEP if w.get("kind", "shallow") == "deep" else C_SHALLOW)
	if layout.get("arena_walls", true) != false:
		for w in shared_walls:
			_rect(w, C_WALL)
	for w in layout.get("walls", []):
		_rect(w, C_WALL)
	for pit in layout.get("pits", []):
		_rect(pit, C_PIT)
	for prop in layout.get("env_props", []):
		_draw_env_prop(prop)
	_ring(t["entrance"], SPAWN_RING / SCALE, C_ENTRANCE)
	for pr in layout.get("props", []):
		_disc([pr[1], pr[2]], 3, C_PROP)
	for p in t.get("pedestals", []):
		_diamond(p["position"], 4, C_PEDESTAL)
	_disc(t["reward"], 4, C_REWARD)
	_disc(t["exit"], 4, C_EXIT)
	_disc(t["entrance"], 4, C_ENTRANCE)
	for wave in t.get("waves", []):
		var on_clear: bool = wave.get("trigger", "") == "on_clear"
		for e in wave.get("enemies", []):
			var pos := [e[1], e[2]]
			if on_clear:
				_disc(pos, 5, C_ON_CLEAR)
			_disc(pos, 3, ENEMY_COLORS.get(e[0], C_ENEMY_OTHER))
	_frame(Rect2i(_ox, _oy, TILE_W, TILE_H), Color(0.3, 0.3, 0.35))
	_draw_marker(t)

## AD-202: solid cover = grey-brown, interactive kinds = small coloured rects/discs (circles for position-only entries).
func _draw_env_prop(prop: Dictionary) -> void:
	var kind := str(prop.get("kind", ""))
	var colour := C_COVER
	if kind in BURNABLE_KINDS:
		colour = C_BURNABLE
	elif kind == "puddle":
		colour = C_PUDDLE
	elif kind == "brazier":
		colour = C_BRAZIER
	elif kind in BREAKABLE_KINDS:
		colour = C_BREAKABLE
	var interactive := colour != C_COVER
	if prop.has("rect"):
		_rect(prop["rect"], colour)
		if kind in ["cracked_pillar", "broken_wall"]:
			_frame_world(prop["rect"], C_COVER) # solid cover that Force can break: gold fill, cover-coloured outline
	elif prop.has("position"):
		_disc(prop["position"], 2 if interactive else 4, colour)

func _frame_world(r: Array, c: Color) -> void:
	var x0 := int(r[0]) / SCALE
	var y0 := int(r[1]) / SCALE
	var x1 := int(ceil(float(int(r[0]) + int(r[2])) / SCALE))
	var y1 := int(ceil(float(int(r[1]) + int(r[3])) / SCALE))
	for x in range(x0, x1):
		_px(x, y0, c)
		_px(x, y1 - 1, c)
	for y in range(y0, y1):
		_px(x0, y, c)
		_px(x1 - 1, y, c)

## Shape marker without fonts: a coloured square (colour = shape id) top-left, plus one white tick per room index.
func _draw_marker(t: Dictionary) -> void:
	var shape := str(t.get("shape", ""))
	var colour: Color = SHAPE_COLORS.get(shape, Color(0.3, 0.3, 0.3)) if not shape.is_empty() else Color(0.0, 0.0, 0.0)
	_img.fill_rect(Rect2i(_ox + 2, _oy + 2, 8, 8), C_BG)
	_img.fill_rect(Rect2i(_ox + 3, _oy + 3, 6, 6), colour)
	if shape.is_empty():
		_frame(Rect2i(_ox + 2, _oy + 2, 8, 8), Color(0.6, 0.1, 0.1))
	var index := int(t.get("_sheet_index", 0))
	for i in index + 1:
		_img.fill_rect(Rect2i(_ox + 12 + i * 3, _oy + 3, 2, 6), C_MARK)
