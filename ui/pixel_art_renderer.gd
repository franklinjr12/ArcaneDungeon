extends RefCounted
## Presentation only: the reference-matched pixel assets never own collision, damage or spells.
const TILE = preload("res://assets/pixel/dungeon_tiles.png")
const PROPS = preload("res://assets/pixel/dungeon_props.png")
const ICON = preload("res://assets/pixel/rune_icons.png")
const FX = preload("res://assets/pixel/spell_effects.png")
const MAGE = preload("res://assets/pixel/mage_sheet.png")
const PURSUER = preload("res://assets/pixel/pursuer_sheet.png")
const RANGED = preload("res://assets/pixel/ranged_sheet.png")
const FLANKER = preload("res://assets/pixel/flanker_sheet.png")
const BOSS = preload("res://assets/pixel/boss_sheet.png")
const DUMMY = preload("res://assets/pixel/dummy_sheet.png")
const ICONS = ["fire","water","lightning","projectile","burst","orb","homing","split","pierce","on_hit",
	"health","mana","rune","coin","dodge","wet","burning","charged","damage","door","shop","book","staff","shield"]
const EFFECT_ROWS = ["fire","water","lightning","orb","enemy","arc","impact","dodge"]
const F = {"mage":MAGE,"bone_thrall":PURSUER,"fallen_adept":RANGED,"grave_hound":FLANKER,"undead_warden":BOSS,"dummy":DUMMY}

# AD-030: debug-only swap to art/export sprites (F6). Default stays assets/pixel.
const EXPORT_MANIFEST := "res://art/export/manifest.json"
const EXPORT_MAP := "res://art/export/engine_map.json"
static var use_art_export := false
static var _manifest: Dictionary = {}
static var _map: Dictionary = {}
static var _jsons: Dictionary = {}
static var _texs: Dictionary = {}

static func toggle_art_export() -> bool:
	use_art_export = not use_art_export
	return use_art_export

static func _export_data() -> void:
	if not _manifest.is_empty():
		return
	var m = JSON.parse_string(FileAccess.get_file_as_string(EXPORT_MANIFEST))
	var e = JSON.parse_string(FileAccess.get_file_as_string(EXPORT_MAP))
	_manifest = m["assets"] if m is Dictionary else {}
	_map = e if e is Dictionary else {}

static func export_map() -> Dictionary:
	_export_data()
	return _map

static func export_manifest() -> Dictionary:
	_export_data()
	return _manifest

static func _export_json(stem: String) -> Dictionary:
	if not _jsons.has(stem):
		_export_data()
		_jsons[stem] = JSON.parse_string(FileAccess.get_file_as_string(_manifest[stem]["json"]))
		_texs[stem] = load(_manifest[stem]["png"])
	return _jsons[stem]

static func build_sprite_frames(stem: String) -> SpriteFrames:
	var j: Dictionary = _export_json(stem)
	var tex: Texture2D = _texs[stem]
	var frames: Array = j["frames"]
	var sf := SpriteFrames.new()
	sf.remove_animation("default")
	for tg in j["meta"]["frameTags"]:
		var n := str(tg["name"])
		sf.add_animation(n)
		sf.set_animation_speed(n, 10.0)
		sf.set_animation_loop(n, true)
		for i in range(int(tg["from"]), int(tg["to"]) + 1):
			var r: Dictionary = frames[i]["frame"]
			var at := AtlasTexture.new()
			at.atlas = tex
			at.region = Rect2(r["x"], r["y"], r["w"], r["h"])
			sf.add_frame(n, at, float(frames[i]["duration"]) / 100.0)
	return sf

## Pure lookup: which export frame shows for entity kind/state at a fixed 60 Hz tick.
static func export_frame_for(kind: String, state: String, tick: int) -> Dictionary:
	_export_data()
	var stem: String = _map.get("entities", {}).get(kind, "")
	if stem == "":
		return {}
	var tag: String = _map["states"][stem][state]
	var entry: Dictionary = _manifest[stem]
	var ms: Array = entry["tags"][tag]["ms"]
	var total := 0
	for d in ms:
		total += int(d)
	var elapsed := tick * 1000 / 60
	var index := 0
	if state == "dead":
		index = ms.size() - 1
		if elapsed < total:
			var acc := 0
			for i in ms.size():
				acc += int(ms[i])
				if elapsed < acc:
					index = i
					break
	else:
		var t := elapsed % total
		var acc := 0
		for i in ms.size():
			acc += int(ms[i])
			if t < acc:
				index = i
				break
	var f: Dictionary = _export_json(stem)["frames"][int(entry["tags"][tag]["from"]) + index]["frame"]
	var piv: Array = entry["pivot"]
	return {"stem": stem, "tag": tag, "index": index, "total_ms": total,
		"region": Rect2(f["x"], f["y"], f["w"], f["h"]), "pivot": Vector2(piv[0], piv[1])}

static func _entity_export(canvas: CanvasItem, kind: String, at: Vector2, tick: int, motion: Vector2,
		casting: bool, hurt: bool, dead: bool, modulate: Color = Color.WHITE) -> void:
	var state := "idle"
	if dead:
		state = "dead"
	elif hurt:
		state = "hit"
	elif casting:
		state = "cast"
	elif motion.length_squared() > 3.0:
		state = "move"
	var fr := export_frame_for(kind, state, tick)
	var sc: float = float(_map.get("scale", 1.5))
	var region: Rect2 = fr["region"]
	var pivot: Vector2 = fr["pivot"]
	var tex: Texture2D = _texs[fr["stem"]]
	var flip := motion.x < 0.0
	if flip:
		canvas.draw_set_transform(at, 0.0, Vector2(-1, 1))
		canvas.draw_texture_rect_region(tex, Rect2(-pivot * sc, region.size * sc), region, modulate)
		canvas.draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
	else:
		canvas.draw_texture_rect_region(tex, Rect2(at - pivot * sc, region.size * sc), region, modulate)

# AD-065 PROPOSED: actor animation sheets (art/export/actors) drive the default entity draw.
# Frames are chosen from sim state by the canvas; nothing here writes to or reads back into the sim.
const ACTOR_MANIFEST := "res://art/export/actors/actors_manifest.json"
static var _actors: Dictionary = {}
static var _actors_loaded := false
static var _actor_scale := 2.0
static var _actor_sheets: Dictionary = {}

static func actor_manifest() -> Dictionary:
	if not _actors_loaded:
		_actors_loaded = true
		var m = JSON.parse_string(FileAccess.get_file_as_string(ACTOR_MANIFEST))
		if m is Dictionary:
			_actors = m.get("actors", {})
			_actor_scale = float(m.get("scale", 2))
	return _actors

static func actor_tag(kind: String, tag: String) -> Dictionary:
	return actor_manifest().get(kind, {}).get("tags", {}).get(tag, {})

static func actor_has_tag(kind: String, tag: String) -> bool:
	return not actor_tag(kind, tag).is_empty()

static func actor_tag_frames(kind: String, tag: String) -> int:
	return int(actor_tag(kind, tag).get("frames", 0))

static func actor_tag_total_ms(kind: String, tag: String) -> int:
	var total := 0
	for d in actor_tag(kind, tag).get("ms", []):
		total += int(d)
	return total

## Whole ticks (60 Hz) a tag lasts at its authored ms.
static func actor_tag_ticks(kind: String, tag: String) -> int:
	return ceili(actor_tag_total_ms(kind, tag) * 60.0 / 1000.0)

static func _actor_sheet(json_path: String, png_path: String) -> Dictionary:
	if not _actor_sheets.has(json_path):
		_actor_sheets[json_path] = {"json": JSON.parse_string(FileAccess.get_file_as_string(json_path)), "tex": load(png_path)}
	return _actor_sheets[json_path]

static func _actor_frame(kind: String, tag: String, index: int, left: bool) -> Dictionary:
	var tg := actor_tag(kind, tag)
	if tg.is_empty():
		return {}
	var sh: Dictionary = actor_manifest()[kind]["sheets"][tg["sheet"]]
	var use_left: bool = left and sh.get("left_json") != null
	var data := _actor_sheet(sh["left_json"], sh["left_png"]) if use_left else _actor_sheet(sh["json"], sh["png"])
	index = clampi(index, 0, int(tg["frames"]) - 1)
	var fr: Dictionary = data["json"]["frames"][int(tg["from"]) + index]
	var r: Dictionary = fr["frame"]
	var o: Dictionary = fr.get("spriteSourceSize", {"x": 0, "y": 0})
	var piv: Array = sh["left_pivot"] if use_left and sh.get("left_pivot") != null else sh["pivot"]
	var hb: Dictionary = sh["left_hurtbox"] if use_left and sh.get("left_hurtbox") != null else sh["hurtbox"]
	return {"sheet": tg["sheet"], "tag": tag, "index": index, "tex": data["tex"], "left": use_left,
		"region": Rect2(r["x"], r["y"], r["w"], r["h"]), "offset": Vector2(o["x"], o["y"]),
		"pivot": Vector2(piv[0], piv[1]), "hurtbox": Rect2(hb["x"], hb["y"], hb["w"], hb["h"])}

## Pure: tag frame after elapsed_ticks (60 Hz -> ms). loop=false holds the last frame.
static func actor_tag_frame(kind: String, tag: String, elapsed_ticks: int, loop: bool, left: bool = false) -> Dictionary:
	var ms: Array = actor_tag(kind, tag).get("ms", [])
	if ms.is_empty():
		return {}
	var total := actor_tag_total_ms(kind, tag)
	var elapsed := maxi(0, elapsed_ticks) * 1000 / 60
	if loop and total > 0:
		elapsed %= total
	var index := ms.size() - 1
	var acc := 0
	for i in ms.size():
		acc += int(ms[i])
		if elapsed < acc:
			index = i
			break
	return _actor_frame(kind, tag, index, left)

## Each of frame_count frames holds window/frame_count ticks; the last ends exactly at window_ticks.
static func stretched_index(state_tick: int, window_ticks: int, frame_count: int) -> int:
	return clampi(state_tick * frame_count / maxi(1, window_ticks), 0, maxi(0, frame_count - 1))

## Ticks covered by the stretched telegraph (sum of per-frame hold ticks); equals window_ticks.
static func telegraph_anim_ticks(kind: String, window_ticks: int) -> int:
	var tag := "telegraph_side" if actor_has_tag(kind, "telegraph_side") else "telegraph_burst_side"
	var n := actor_tag_frames(kind, tag)
	var covered := 0
	for t in window_ticks:
		if stretched_index(t, window_ticks, n) < n:
			covered += 1
	return covered

## Mage facing from aim = hover - mage position: 3 directions, side is mirrored when aiming left.
static func mage_facing(aim: Vector2) -> Dictionary:
	if absf(aim.x) >= absf(aim.y):
		return {"dir": "side", "face_left": aim.x < 0.0}
	return {"dir": "down" if aim.y > 0.0 else "up", "face_left": false}

## anim = {tag, elapsed (+loop) or index, face_left}. PROPOSED: the centre of the art hurtbox slice
## lands on `at` (the sim position) so the drawn body lines up with the sim hurt circle.
static func draw_actor(canvas: CanvasItem, kind: String, at: Vector2, anim: Dictionary, modulate: Color = Color.WHITE) -> void:
	var tag := str(anim.get("tag", ""))
	var left := bool(anim.get("face_left", false))
	var fr: Dictionary
	if anim.has("index"):
		fr = _actor_frame(kind, tag, int(anim["index"]), left)
	else:
		fr = actor_tag_frame(kind, tag, int(anim.get("elapsed", 0)), bool(anim.get("loop", false)), left)
	if fr.is_empty():
		return
	var hb: Rect2 = fr["hurtbox"]
	var region: Rect2 = fr["region"]
	var rect := Rect2((fr["offset"] - (hb.position + hb.size / 2.0)) * _actor_scale, region.size * _actor_scale)
	if left and not fr["left"] and bool(actor_manifest()[kind].get("mirror", false)):
		canvas.draw_set_transform(at, 0.0, Vector2(-1, 1))
		canvas.draw_texture_rect_region(fr["tex"], rect, region, modulate)
		canvas.draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
	else:
		rect.position += at
		canvas.draw_texture_rect_region(fr["tex"], rect, region, modulate)

static func tile_floor(canvas: CanvasItem, view: Rect2, offset: Vector2, stage: int = 0) -> void:
	if use_art_export:
		_tile_floor_export(canvas, view, offset, stage)
		return
	canvas.draw_rect(Rect2(Vector2.ZERO,view.size),Color("#0f1924"))
	var max_x := int(ceil(view.size.x/32))+3
	var max_y := int(ceil(view.size.y/32))+3
	var first_x := int(floor(offset.x/32))
	var first_y := int(floor(offset.y/32))
	for ay in max_y:
		var gy := first_y+ay
		for ax in max_x:
			var gx := first_x+ax
			var h: int = (gx*73856093 ^ gy*19349663 ^ stage*83492791) & 0x7fffffff
			var variant: int = (16+h%8) if stage > 0 else h%8
			var pos := Vector2(float(gx*32),float(gy*32))-offset
			canvas.draw_texture_rect_region(TILE,Rect2(pos,Vector2(32,32)),
				Rect2(Vector2((variant%8)*32,(variant/8)*32),Vector2(32,32)))
	# Avoid bright grid: reference is continuous carved flagstones.

static func decorations(canvas: CanvasItem, offset: Vector2, stage: int = 0) -> void:
	# Decorative-only; never implicitly introduces a collectible or solid obstacle.
	var placements := [
		[Vector2(108,104),3],[Vector2(304,105),2],[Vector2(746,124),7],
		[Vector2(1030,115),4],[Vector2(1224,120),6],[Vector2(99,728),1],
		[Vector2(405,770),0],[Vector2(735,789),2],[Vector2(1110,750),6],
		[Vector2(1260,761),5],[Vector2(826,285),2],[Vector2(754,670),3]]
	for entry in placements:
		var at: Vector2 = entry[0]-offset
		if at.x < -60 or at.y < -60 or at.x > 1200 or at.y > 800:
			continue
		var n: int = int(entry[1])
		if stage > 0 and n in [2,3]:
			n = 6
		canvas.draw_texture_rect_region(PROPS,Rect2(at-Vector2(24,35),Vector2(48,48)),
			Rect2(Vector2(n*48,0),Vector2(48,48)))

static func walls(canvas: CanvasItem, wall_rects: Array, offset: Vector2) -> void:
	for wall in wall_rects:
		canvas.draw_rect(Rect2(wall.position-offset-Vector2(4,7),wall.size+Vector2(8,14)),Color("#0b1218",0.84))
		for y in range(0,int(wall.size.y),32):
			for x in range(0,int(wall.size.x),32):
				var p: Vector2 = wall.position+Vector2(x,y)-offset
				var dim := Vector2(minf(32,wall.size.x-x),minf(32,wall.size.y-y))
				var tile: int = 8+((x/32+y/32)%8)
				canvas.draw_texture_rect_region(TILE,Rect2(p,dim),
					Rect2(Vector2((tile%8)*32,32),dim))
		canvas.draw_rect(Rect2(wall.position-offset,wall.size),Color("#bf8a47"),false,2)
		canvas.draw_line(wall.position-offset+Vector2(3,4),wall.position-offset+Vector2(wall.size.x-3,4),Color("#dcb773",0.7),1)

static func _tile_floor_export(canvas: CanvasItem, view: Rect2, offset: Vector2, stage: int) -> void:
	_export_data()
	var fl: Dictionary = _map["floor"]
	var entry: Dictionary = _manifest[fl["asset"]]
	var tag: Dictionary = entry["tags"][fl["tag"]]
	var j: Dictionary = _export_json(fl["asset"])
	var tex: Texture2D = _texs[fl["asset"]]
	var count: int = int(tag["frames"])
	canvas.draw_rect(Rect2(Vector2.ZERO, view.size), Color("#0f1924"))
	var first_x := int(floor(offset.x / 32))
	var first_y := int(floor(offset.y / 32))
	for ay in int(ceil(view.size.y / 32)) + 3:
		for ax in int(ceil(view.size.x / 32)) + 3:
			var gx := first_x + ax
			var gy := first_y + ay
			var h: int = (gx * 73856093 ^ gy * 19349663 ^ stage * 83492791) & 0x7fffffff
			var f: Dictionary = j["frames"][int(tag["from"]) + h % count]["frame"]
			canvas.draw_texture_rect_region(tex, Rect2(Vector2(gx * 32, gy * 32) - offset, Vector2(32, 32)),
				Rect2(f["x"], f["y"], f["w"], f["h"]))

static func entity(canvas: CanvasItem, kind: String, at: Vector2, tick: int, motion: Vector2 = Vector2.ZERO,
		casting: bool = false, hurt: bool = false, dead: bool = false, modulate: Color = Color.WHITE,
		anim: Dictionary = {}) -> void:
	if not anim.is_empty() and actor_has_tag(kind, str(anim.get("tag", ""))):
		draw_actor(canvas, kind, at, anim, modulate)
		return
	if use_art_export and export_map().get("entities", {}).has(kind):
		_entity_export(canvas, kind, at, tick, motion, casting, hurt, dead, modulate)
		return
	if not F.has(kind):
		kind = "dummy"
	var size: Vector2 = Vector2(104,112) if kind == "undead_warden" else Vector2(48,56)
	var frame := 0
	if dead:
		frame = 9
	elif hurt:
		frame = 8
	elif casting:
		frame = 6+((tick/5)%2)
	elif motion.length_squared() > 3.0:
		frame = 2+((tick/6)%4)
	else:
		frame = (tick/18)%2
	var where := Rect2(at+Vector2(-size.x/2,-size.y+7),size)
	canvas.draw_texture_rect_region(F[kind],where,Rect2(Vector2(frame*size.x,0),size))

static func icon(canvas: CanvasItem, name: String, at: Vector2, dimensions: Vector2 = Vector2(32,32)) -> void:
	var index: int = ICONS.find(name)
	if index == -1:
		index = 12
	canvas.draw_texture_rect_region(ICON,Rect2(at,dimensions),
		Rect2(Vector2(index%8*32,(index/8)*32),Vector2(32,32)))

static func effect(canvas: CanvasItem, kind: String, center: Vector2, tick: int,
		dimensions: Vector2 = Vector2(32,32), alpha: float = 1.0) -> void:
	var row: int = EFFECT_ROWS.find(kind)
	if row == -1:
		row = 6
	var frame: int = (tick/4)%8
	canvas.draw_texture_rect_region(FX,Rect2(center-dimensions/2.0,dimensions),
		Rect2(Vector2(frame*32,row*32),Vector2(32,32)),Color(1,1,1,clampf(alpha,0,1)))

## Legacy entry point (sandbox): the AD-045 overlay is centred above the old icon-row anchor.
static func status_icons(canvas: CanvasItem, target, tick: int, at: Vector2) -> void:
	var current: Dictionary = target.status.snapshot(tick)
	var slot := 0
	for status_id in ["burning","wet","charged"]:
		if current.has(status_id):
			draw_fx(canvas,"status."+status_id,at+Vector2(15,-(target.radius+21)),tick,0.0,0.0,Color.WHITE,slot)
			slot += 1

# AD-039: P1 spell FX are the default visuals (not behind F6). Resolved through engine_map.fx + manifest.
const FX_ELEMENTS := ["fire","water","lightning"]
const FX_EVENTS := [
	"projectile.fire","projectile.water","projectile.lightning","projectile.neutral",
	"orb.fire","orb.water","orb.lightning","mod.homing",
	"impact.fire","impact.water","impact.lightning","impact.neutral",
	"burst.fire","burst.water","burst.lightning",
	"reaction.arc","reaction.extinguish","mod.split","mod.pierce","trigger.on_hit",
	"status.wet","status.burning","status.charged",
	"cast.charge","cast.muzzle","dash.trail","hit.spark","enemy.spawn","enemy.dissolve","enemy.bolt","enemy.bolt_impact",
	"boss.bullet","boss.phase","room.clear","telegraph.circle","telegraph.line","telegraph.dash_lane"]
const IFRAME_OUTLINE := Color("#e9f2e5")
## Events that had no P1 mapping when drawn (legacy sprite used instead); must stay empty in the slice.
static var fx_fallbacks: Array = []
static var _icon_index: Dictionary = {}

## Pure lookup: P1 FX frame for an event at age_ticks (60 Hz). {} when the event is unmapped.
static func fx_frame(event: String, age_ticks: int) -> Dictionary:
	_export_data()
	var ref: Dictionary = _map.get("fx", {}).get(event, {})
	if ref.is_empty() or not _manifest.has(ref.get("asset", "")):
		return {}
	var stem: String = ref["asset"]
	var tag: String = ref["tag"]
	var entry: Dictionary = _manifest[stem]
	if not entry["tags"].has(tag):
		return {}
	var ms: Array = entry["tags"][tag]["ms"]
	var total := 0
	for d in ms:
		total += int(d)
	var elapsed := maxi(0, age_ticks) * 1000 / 60
	var looping := tag == "loop"
	var done := not looping and elapsed >= total
	var t := elapsed % total if looping else mini(elapsed, total - 1)
	var index := ms.size() - 1 if done else 0
	if not done:
		var acc := 0
		for i in ms.size():
			acc += int(ms[i])
			if t < acc:
				index = i
				break
	var f: Dictionary = _export_json(stem)["frames"][int(entry["tags"][tag]["from"]) + index]["frame"]
	var piv: Array = entry["pivot"]
	return {"stem": stem, "tag": tag, "index": index, "total_ms": total, "done": done,
		"region": Rect2(f["x"], f["y"], f["w"], f["h"]), "pivot": Vector2(piv[0], piv[1])}

static func _legacy_kind(event: String) -> String:
	var parts := event.split(".")
	if parts[0] == "orb":
		return "orb"
	if parts[0] == "reaction":
		return "arc"
	if parts[0] in ["projectile", "impact", "burst"] and parts.size() > 1 and parts[1] in FX_ELEMENTS:
		return parts[1] if parts[0] == "projectile" else "impact"
	return "impact"

## AD-VFX-035 i-frame flicker: outline toggles every 60 ms (3.6 ticks, floored), on first.
static func iframe_outline_on(tick: int) -> bool:
	return (tick * 1000 / 60) / 60 % 2 == 0

## Draws region*scale around the pivot. uniform > 0 scales both axes to that world diameter (telegraph circle). length > 0 stretches only along x (lanes, lines, arcs).
## Status events also draw the AD-033 icon at the overlay's symbol slice (slot offsets stacked icons).
static func draw_fx(canvas: CanvasItem, event: String, center: Vector2, age_ticks: int, rotation: float = 0.0,
		length: float = 0.0, modulate: Color = Color.WHITE, slot: int = 0, uniform: float = 0.0) -> void:
	var fr := fx_frame(event, age_ticks)
	if fr.is_empty():
		if not fx_fallbacks.has(event):
			fx_fallbacks.append(event)
		effect(canvas, _legacy_kind(event), center, age_ticks, Vector2(34, 34), modulate.a)
		return
	var sc: float = float(_map.get("scale", 2))
	var region: Rect2 = fr["region"]
	var pivot: Vector2 = fr["pivot"]
	var sx := length / region.size.x if length > 0.0 else sc
	if uniform > 0.0:
		sc = uniform / region.size.x
		sx = sc
	canvas.draw_set_transform(center, rotation, Vector2.ONE)
	canvas.draw_texture_rect_region(_texs[fr["stem"]],
		Rect2(Vector2(-pivot.x * sx, -pivot.y * sc), Vector2(region.size.x * sx, region.size.y * sc)), region, modulate)
	if event.begins_with("status."):
		_status_icon(canvas, event, fr, slot, modulate)
	canvas.draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)

## AD-045: the icon's bottom-centre sits on the 1x1 'symbol' slice (overlay-local art px).
static func _status_icon(canvas: CanvasItem, event: String, fr: Dictionary, slot: int, modulate: Color) -> void:
	var sym: Dictionary = _manifest[fr["stem"]]["slices"].get("symbol", {})
	if sym.is_empty():
		return
	var atlas: String = _map["icons"]
	if _icon_index.is_empty():
		_icon_index = JSON.parse_string(FileAccess.get_file_as_string("res://art/export/ico/ad_ico_atlas_mvp_index.json"))["icons"]
	var cell: Dictionary = _icon_index["ad_ico_" + event.trim_prefix("status.")]
	_export_json(atlas)
	var sc: float = float(_map.get("scale", 2))
	var anchor: Vector2 = (Vector2(float(sym["x"]), float(sym["y"])) - fr["pivot"]) * sc
	var size := Vector2(float(cell["w"]), float(cell["h"])) * sc
	canvas.draw_texture_rect_region(_texs[atlas],
		Rect2(anchor + Vector2(-size.x / 2.0 + slot * size.x, -size.y), size),
		Rect2(float(cell["x"]), float(cell["y"]), float(cell["w"]), float(cell["h"])), modulate)

static func _element(essence_id: String) -> String:
	var el := essence_id.trim_prefix("essence.")
	return el if el in FX_ELEMENTS else "neutral"

static func _pos(p: Variant) -> Vector2:
	return Vector2(float(p["x"]), float(p["y"])) if p is Dictionary else Vector2(p)

## Pure: FX list [{event, at (world), age, rotation, length, slot}] from session state; no drawing.
## memo is per-canvas render memory (spawn ticks, trace cursors, last statuses, pending one-shots).
static func collect_fx(session, tick: int, memo: Dictionary) -> Array:
	var sim = session.sim
	var out: Array = []
	for key in ["born", "cursor", "prev", "since", "seen", "known", "dead", "phase", "eshots"]:
		if not memo.has(key):
			memo[key] = {}
	if not memo.has("shots"):
		memo["shots"] = []
	var shots: Array = memo["shots"]
	var live: Dictionary = {}
	var pierce_ids: Dictionary = {}
	for entry in sim.active:
		var effect = entry["effect"]
		var mods: Array = []
		for m in effect.root.get("modifiers", []):
			mods.append(m["id"])
		var el := _element(str(effect.root["essence"]["id"]))
		var key := "%s:%d" % [entry["kind"], effect.id]
		live[key] = true
		var born: int = memo["born"].get(key, tick)
		memo["born"][key] = born
		var heading := 0.0
		if entry["kind"] == "projectile":
			heading = effect.direction.angle()
			if "mod.pierce" in mods:
				pierce_ids[effect.id] = true
		var ev := ("orb." if entry["kind"] == "orb" else "projectile.") + el
		out.append({"event": ev, "at": effect.position, "age": tick - born, "rotation": heading, "length": 0.0, "slot": 0})
		if entry["kind"] == "projectile" and "mod.homing" in mods:
			out.append({"event": "mod.homing", "at": effect.position, "age": tick - born, "rotation": heading, "length": 0.0, "slot": 0})
	for key in memo["born"].keys():
		if not live.has(key):
			memo["born"].erase(key)
	# New sim.visuals become one-shots that run their full animation (visuals expire sooner).
	var tally: Dictionary = {}
	var seen_now: Dictionary = {}
	for v in sim.visuals:
		var base := "%s:%d:%s" % [v["kind"], int(v["until"]), str(v.get("position", v.get("from")))]
		var n: int = tally.get(base, 0)
		tally[base] = n + 1
		var key := "%s#%d" % [base, n]
		seen_now[key] = true
		if memo["seen"].has(key):
			continue
		match v["kind"]:
			"hit":
				_shot(shots, "impact." + _element(str(v.get("essence", ""))), v["position"], tick)
			"burst":
				var el := _element(str(v.get("essence", "")))
				_shot(shots, ("burst." + el) if el != "neutral" else "impact.neutral", v["position"], tick)
			"arc":
				var d: Vector2 = v["to"] - v["from"]
				_shot(shots, "reaction.arc", (v["from"] + v["to"]) / 2.0, tick, d.angle(), d.length())
	memo["seen"] = seen_now
	# Trace-derived modifier / trigger FX, consumed through per-type cursors.
	var batch: Dictionary = {}
	for kind in ["spawn", "hit", "trigger"]:
		var recs: Array = sim.trace.filter_records(-1, "", kind)
		var from: int = int(memo["cursor"].get(kind, 0))
		if recs.size() < from:
			from = 0
		memo["cursor"][kind] = recs.size()
		batch[kind] = recs.slice(from).filter(func(r): return tick - int(r["tick"]) < 30)
	var hit_at: Dictionary = {}
	for r in batch["hit"]:
		var target = sim.targets.get_target(int(r["target_id"]))
		if target == null:
			continue
		hit_at[int(r["effect_id"])] = target.position
		if pierce_ids.has(int(r["effect_id"])):
			_shot(shots, "mod.pierce", target.position, tick)
	for r in batch["trigger"]:
		if hit_at.has(int(r["parent_effect_id"])):
			_shot(shots, "trigger.on_hit", hit_at[int(r["parent_effect_id"])], tick)
	var groups: Dictionary = {}
	for r in batch["spawn"]:
		if int(r["parent_effect_id"]) != 0:
			continue
		var gk := "%d:%d" % [int(r["cast_id"]), int(r["tick"])]
		groups[gk] = groups.get(gk, []) + [r]
	for gk in groups:
		if groups[gk].size() > 1:
			_shot(shots, "mod.split", _pos(groups[gk][0]["position"]), tick)
	# Live target statuses; extinguish = burning lost while wet.
	var next_shots: Array = []
	for target in sim.targets.all():
		var snap: Dictionary = target.status.snapshot(tick) if target.alive() else {}
		var before: Dictionary = memo["prev"].get(target.id, {})
		if before.has("burning") and snap.has("wet") and not snap.has("burning"):
			_shot(shots, "reaction.extinguish", target.position, tick)
		memo["prev"][target.id] = snap
		var slot := 0
		for sid in ["burning", "wet", "charged"]:
			var skey := "%d:%s" % [target.id, sid]
			if not snap.has(sid):
				memo["since"].erase(skey)
				continue
			var since: int = memo["since"].get(skey, tick)
			memo["since"][skey] = since
			out.append({"event": "status." + sid, "at": target.position, "age": tick - since,
				"rotation": 0.0, "length": 0.0, "slot": slot})
			slot += 1
	for shot in shots:
		var age: int = tick - int(shot["tick"])
		if fx_frame(shot["event"], age).get("done", true) and age > 0:
			continue
		next_shots.append(shot)
		out.append({"event": shot["event"], "at": shot["at"], "age": age,
			"rotation": shot["rotation"], "length": shot["length"], "slot": 0})
	memo["shots"] = next_shots
	_collect_feedback(session, tick, memo, out)
	return out

## AD-035 feedback, telegraphs and hostile shots (presentation only).
static func _collect_feedback(session, tick: int, memo: Dictionary, out: Array) -> void:
	var sim = session.sim
	var mage: Vector2 = sim.actor.position
	var shots: Array = memo["shots"]
	var pending: Array = []
	# Hostile shots; a vanished id leaves an impact at its last position.
	var current: Dictionary = {}
	for s in session.enemy_shots:
		var sid := int(s["id"])
		var boss := _is_boss_id(session, int(s["source_id"]))
		current[sid] = true
		memo["eshots"][sid] = {"at": s["position"], "boss": boss}
		out.append({"event": "boss.bullet" if boss else "enemy.bolt", "at": s["position"], "age": tick,
			"rotation": Vector2(s["direction"]).angle(), "length": 0.0, "slot": 0})
	for sid in memo["eshots"].keys():
		if not current.has(sid):
			pending.append(["enemy.bolt_impact", memo["eshots"][sid]["at"]])
			memo["eshots"].erase(sid)
	# Casts: a new cost_paid record this tick.
	var paid: Array = sim.trace.filter_records(-1, "", "cost_paid")
	var from: int = int(memo["cursor"].get("cost_paid", 0))
	if paid.size() < from:
		from = 0
	memo["cursor"]["cost_paid"] = paid.size()
	if paid.size() > from:
		var aim := Vector2.RIGHT
		for entry in sim.active:
			if entry["kind"] == "projectile":
				aim = entry["effect"].direction
		pending.append(["cast.charge", mage])
		_shot(shots, "cast.muzzle", mage + aim * 18.0, tick, aim.angle())
		out.append({"event": "cast.muzzle", "at": mage + aim * 18.0, "age": 0, "rotation": aim.angle(), "length": 0.0, "slot": 0})
	if session.player.dash_left > 0:
		out.append({"event": "dash.trail", "at": mage, "age": tick, "rotation": 0.0, "length": 0.0, "slot": 0})
	var flash: int = session.player.hit_flash
	if flash > 0 and int(memo["cursor"].get("flash", 0)) == 0:
		pending.append(["hit.spark", mage])
	memo["cursor"]["flash"] = flash
	for enemy in session.enemies:
		var target = enemy.target
		var id: int = target.id
		if not memo["known"].has(id):
			memo["known"][id] = true
			pending.append(["enemy.spawn", target.position])
		if not target.alive() and not memo["dead"].has(id):
			memo["dead"][id] = tick
			pending.append(["enemy.dissolve", target.position])
		if enemy.kind == "undead_warden":
			if enemy.phase == 2 and int(memo["phase"].get(id, 1)) != 2:
				pending.append(["boss.phase", target.position])
			memo["phase"][id] = enemy.phase
		if enemy.state != "windup" or enemy.intent == null or not target.alive():
			continue
		var intent: Dictionary = enemy.intent.snapshot()
		var to_mage: Vector2 = mage - target.position
		var item := {"at": target.position, "age": int(enemy.state_tick), "rotation": to_mage.angle(), "length": 0.0, "slot": 0}
		if enemy.kind == "undead_warden":
			if intent["kind"] == "radial":
				item["event"] = "telegraph.circle"
				item["uniform"] = 2.0 * float(intent["range"])
			else:
				item["event"] = "telegraph.dash_lane"
				item["length"] = to_mage.length()
		elif enemy.kind == "bone_thrall":
			item["event"] = "telegraph.circle"
			item["uniform"] = 2.0 * float(intent["range"])
		else:
			item["event"] = "telegraph.line"
			item["length"] = to_mage.length()
		out.append(item)
	for p in pending:
		_shot(shots, p[0], p[1], tick)
		var shot: Dictionary = shots[shots.size() - 1]
		out.append({"event": shot["event"], "at": shot["at"], "age": 0, "rotation": 0.0, "length": 0.0, "slot": 0})

static func _is_boss_id(session, source_id: int) -> bool:
	for enemy in session.enemies:
		if enemy.target.id == source_id:
			return enemy.kind == "undead_warden"
	return false

static func _shot(shots: Array, event: String, at: Vector2, tick: int, rotation: float = 0.0, length: float = 0.0) -> void:
	shots.append({"event": event, "at": at, "tick": tick, "rotation": rotation, "length": length})


static func portal(canvas: CanvasItem, at: Vector2, open: bool, tick: int) -> void:
	var shade := Color("#5edfc3") if open else Color("#bd5366")
	canvas.draw_arc(at,27,PI,TAU,16,Color("#0d1823"),9)
	canvas.draw_arc(at,26,PI,TAU,16,Color("#a77c43"),6)
	canvas.draw_arc(at,21,PI,TAU,16,shade,2)
	canvas.draw_line(at+Vector2(-22,0),at+Vector2(-22,24),Color("#846037"),6)
	canvas.draw_line(at+Vector2(22,0),at+Vector2(22,24),Color("#846037"),6)
	icon(canvas,"door",at+Vector2(-11,-12),Vector2(22,22))
	if open:
		effect(canvas,"arc",at+Vector2(0,2),tick,Vector2(38,38),0.8)

## AD-036 damage numbers: pure layout. Symbol first (advance 7), then each char of text (advance 4); '+' is the plus glyph.
static func damage_glyph_layout(symbol: String, text: String) -> Array:
	var glyphs: Dictionary = _export_json(export_map()["damage_glyphs"])["glyphs"]
	var names: Array = []
	if symbol != "":
		names.append(symbol)
	for ch in text:
		names.append("plus" if ch == "+" else ch)
	var out: Array = []
	var x := 0
	for n in names:
		if not glyphs.has(n):
			continue
		var g: Dictionary = glyphs[n]
		out.append({"glyph": n, "region": Rect2(g["x"], g["y"], g["w"], g["h"]), "x": x})
		x += int(g["advance"])
	return out

static func damage_glyph_width(symbol: String, text: String) -> float:
	var layout := damage_glyph_layout(symbol, text)
	if layout.is_empty():
		return 0.0
	var last: Dictionary = layout[-1]
	return (float(last["x"]) + (last["region"] as Rect2).size.x) * float(_map.get("scale", 2))

## Draws the layout left to right, top-aligned at `at`, white constant, nearest. Returns the width in world units.
static func draw_damage_number(canvas: CanvasItem, symbol: String, text: String, at: Vector2) -> float:
	var layout := damage_glyph_layout(symbol, text)
	if layout.is_empty():
		return 0.0
	var sc: float = float(_map.get("scale", 2))
	var tex: Texture2D = _texs[export_map()["damage_glyphs"]]
	var right := 0.0
	for item in layout:
		var r: Rect2 = item["region"]
		canvas.draw_texture_rect_region(tex, Rect2(at + Vector2(float(item["x"]) * sc, 0.0), r.size * sc), r, Color.WHITE)
		right = maxf(right, (float(item["x"]) + r.size.x) * sc)
	return right
