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
## AD-137 placeholder art: new Stage 1 kinds borrow an existing sprite until the art import row (tinted by tuning color).
const PLACEHOLDER_KIND := {"ghoul_stalker":"bone_thrall","riptide_leaper":"cistern_slime"}
const F = {"mage":MAGE,"bone_thrall":PURSUER,"fallen_adept":RANGED,"grave_hound":FLANKER,"undead_warden":BOSS,"dummy":DUMMY}

# AD-030: debug-only swap to art/export sprites (F6). Default stays assets/pixel.
const EXPORT_MANIFEST := "res://art/export/manifest.json"
const EXPORT_MAP := "res://art/export/engine_map.json"
const PRESENTATION := "res://world/data/presentation_v1.json"
static var use_art_export := false
static var _telegraph_styles: Dictionary = {}
static var last_telegraph_draw: Dictionary = {}
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

const ARTIFACT_INDEX := "res://art/export/ico/ad_ico_artifacts_index.json"
const ARTIFACT_ATLAS := {16: "res://art/export/ico/ad_ico_artifacts_atlas_16.png", 32: "res://art/export/ico/ad_ico_artifacts_atlas_32_icon.png"}
static var _artifact_index: Dictionary = {}

## AD-115 per-artifact icon (16 px or 32 px icon atlas, never the placeholder card frames); unknown id -> generic upgrade icon.
static func artifact_icon(id: String, px: int = 16) -> AtlasTexture:
	if _artifact_index.is_empty():
		var parsed = JSON.parse_string(FileAccess.get_file_as_string(ARTIFACT_INDEX))
		_artifact_index = parsed.get("artifacts", {}) if parsed is Dictionary else {}
	if not _artifact_index.has(id):
		return load("res://ui/skin_a.gd").icon_or_mvp("upgrade")
	px = 32 if px >= 32 else 16
	var e: Dictionary = _artifact_index[id]
	var t := AtlasTexture.new()
	t.atlas = load(ARTIFACT_ATLAS[px])
	t.region = Rect2(float(e["x%d" % px]), float(e["y%d" % px]), px, px)
	return t

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
	kind = resolve_kind(kind)
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
static var _extra_sheets: Dictionary = {}

static func actor_manifest() -> Dictionary:
	if not _actors_loaded:
		_actors_loaded = true
		var m = JSON.parse_string(FileAccess.get_file_as_string(ACTOR_MANIFEST))
		if m is Dictionary:
			_actors = m.get("actors", {})
			_extra_sheets = m.get("sheets", {})
			_actor_scale = float(m.get("scale", 2))
	return _actors

static func resolve_kind(kind: String) -> String:
	if actor_manifest().has(kind):
		return kind
	return PLACEHOLDER_KIND.get(kind,kind)

static func actor_tag(kind: String, tag: String) -> Dictionary:
	kind = resolve_kind(kind)
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
	kind = resolve_kind(kind)
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
	var mirror: bool = left and not fr["left"] and bool(actor_manifest()[resolve_kind(kind)].get("mirror", false))
	if mirror:
		canvas.draw_set_transform(at, 0.0, Vector2(-1, 1))
		canvas.draw_texture_rect_region(fr["tex"], rect, region, modulate)
		canvas.draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
	else:
		rect.position += at
		canvas.draw_texture_rect_region(fr["tex"], rect, region, modulate)
	var gl := actor_glow_frame(kind, tag, int(fr["index"]), left)
	if not gl.is_empty():
		var grect := Rect2((gl["offset"] - (hb.position + hb.size / 2.0)) * _actor_scale, gl["region"].size * _actor_scale)
		_queue_glow({"tex": gl["tex"], "rect": grect, "region": gl["region"], "mirror": mirror, "at": at})

## AD-154 glow layer: *_glow frames queued while the base is drawn, drawn later on the additive V2 layer.
## Pure lookup: {tex, region, offset} of the glow slice for a tag frame, or {} when the frame has none.
static func actor_glow_frame(kind: String, tag: String, index: int, left: bool = false) -> Dictionary:
	var tg := actor_tag(kind, tag)
	if tg.is_empty():
		return {}
	var sh: Dictionary = actor_manifest()[resolve_kind(kind)]["sheets"][tg["sheet"]]
	if sh.get("glow_png") == null or (left and sh.get("left_json") != null):
		return {}
	index = clampi(index, 0, int(tg["frames"]) - 1)
	var g = sh.get("glow", {}).get(str(int(tg["from"]) + index))
	if g == null:
		return {}
	if not _glow_tex.has(sh["glow_png"]):
		_glow_tex[sh["glow_png"]] = load(sh["glow_png"])
	return {"tex": _glow_tex[sh["glow_png"]], "region": Rect2(g["x"], g["y"], g["w"], g["h"]), "offset": Vector2(g["ox"], g["oy"])}

static var _glow_tex: Dictionary = {}
static var _glow_queue: Array = []
static var _glow_frame := -1

static func _queue_glow(item: Dictionary) -> void:
	var f := Engine.get_frames_drawn()
	if f != _glow_frame:
		_glow_frame = f
		_glow_queue.clear()
	_glow_queue.append(item)

## Draws this frame's queued glows (additive canvas item). Rendering only; never touches the sim.
static func draw_actor_glows(ci: CanvasItem, alpha_mult: float = 1.0) -> void:
	if _glow_frame != Engine.get_frames_drawn():
		return
	var col := Color(1, 1, 1, alpha_mult)
	for it in _glow_queue:
		if it.has("rot"):  # AD-155 fx glow: same dest rect and rotation as the base sprite
			ci.draw_set_transform(it["at"], float(it["rot"]), Vector2.ONE)
			ci.draw_texture_rect_region(it["tex"], it["rect"], it["region"], col)
			ci.draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
		elif it["mirror"]:
			ci.draw_set_transform(it["at"], 0.0, Vector2(-1, 1))
			ci.draw_texture_rect_region(it["tex"], it["rect"], it["region"], col)
		else:
			var r: Rect2 = it["rect"]
			r.position += it["at"]
			ci.draw_texture_rect_region(it["tex"], r, it["region"], col)
	ci.draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)

## AD-200: non-actor sheets listed under actors_manifest "sheets" (storm beam, water states). Pure lookups; {} when absent.
static func extra_sheet(name: String) -> Dictionary:
	actor_manifest()
	return _extra_sheets.get(name, {})

## Sheet frame region for tag frame `index` (clamped) of an extra sheet, or {} when the sheet/png/json/tag is missing.
static func extra_sheet_frame(name: String, tag: String, index: int) -> Dictionary:
	var sh := extra_sheet(name)
	var tg: Dictionary = sh.get("tags", {}).get(tag, {})
	if tg.is_empty() or not FileAccess.file_exists(str(sh["json"])) or not ResourceLoader.exists(str(sh["png"])):
		return {}
	var data := _actor_sheet(str(sh["json"]), str(sh["png"]))
	var fr: Dictionary = data["json"]["frames"][int(tg["from"]) + clampi(index, 0, int(tg["frames"]) - 1)]
	var r: Dictionary = fr["frame"]
	var o: Dictionary = fr.get("spriteSourceSize", {"x": 0, "y": 0})
	var out := {"tex": data["tex"], "region": Rect2(r["x"], r["y"], r["w"], r["h"]), "offset": Vector2(o["x"], o["y"]), "glow": null}
	if sh.get("glow_png") != null and ResourceLoader.exists(str(sh["glow_png"])):
		if not _glow_tex.has(sh["glow_png"]):
			_glow_tex[sh["glow_png"]] = load(sh["glow_png"])
		out["glow"] = _glow_tex[sh["glow_png"]]
	return out

## AD-200 art_kind for a summoned helper (decoy, homing skull, small crystal): the owner's tuning names it under the
## same key as the summon spec ('kind' of the spec, or the key itself). Drawing only; the sim kind never changes.
static func summon_art_kind(owner_tuning: Dictionary, kind: String) -> String:
	for key in ["homing_skull", "decoy", "small_crystals"]:
		var spec = owner_tuning.get(key)
		if spec is Dictionary and spec.has("art_kind") and kind == str(spec.get("kind", key)):
			return str(spec["art_kind"])
	return kind

## AD-200: blink landing marker (ground sigil) over the blink telegraph; its 4 frames stretch over the windup.
static func draw_blink_sigil(canvas: CanvasItem, at: Vector2, state_tick: int, window_ticks: int) -> void:
	if actor_has_tag("blink_anchor_sigil", "telegraph"):
		var n := actor_tag_frames("blink_anchor_sigil", "telegraph")
		draw_actor(canvas, "blink_anchor_sigil", at, {"tag": "telegraph", "index": stretched_index(state_tick, window_ticks, n)})

const BEAM_ANGLES := 16
const BEAM_SHEET := "storm_beam"
static var _beam_layout: Array = []

## Pure: index 0..15 (22.5 degree steps, a00 east, clockwise on screen = Godot y-down angles) nearest to `angle` radians.
static func beam_angle_index(angle: float) -> int:
	return posmod(floori(rad_to_deg(angle) / 22.5 + 0.5), BEAM_ANGLES)

## Pure: segment count for a beam of `length` world units (1 art px = 2 world units): ceil(length / |step|).
static func beam_tile_count(length: float, step: Vector2) -> int:
	return ceili(length / _actor_scale / maxf(step.length(), 0.001))

static func beam_step(index: int) -> Vector2:
	if _beam_layout.is_empty():
		var path := str(extra_sheet(BEAM_SHEET).get("layout", ""))
		if path != "" and FileAccess.file_exists(path):
			var lay = JSON.parse_string(FileAccess.get_file_as_string(path))
			if lay is Dictionary:
				_beam_layout = lay.get("angles", [])
	if index < 0 or index >= _beam_layout.size():
		return Vector2.ZERO
	var st: Array = _beam_layout[index]["step"]
	return Vector2(float(st[0]), float(st[1]))

## Placement list [{tag, index, k}] of one beam in draw order (segs, end cap, start cap); k = step multiple of the tile anchor.
## Telegraph: segs then the end marker. Never rotates a texture (the sheet has a pre-rendered tile set per angle).
static func beam_parts(angle_index: int, n: int, telegraph: bool) -> Array:
	var tag := "a%02d" % angle_index
	var parts: Array = []
	for k in n:
		parts.append({"tag": ("tele_%s_seg" if telegraph else "beam_%s_seg") % tag, "k": k})
	parts.append({"tag": ("tele_%s_end" if telegraph else "beam_%s_end") % tag, "k": n})
	if not telegraph:
		parts.append({"tag": "beam_%s_start" % tag, "k": 0})
	return parts

## boss_beam hazard drawn from the storm beam sheet; a plain coloured band when the sheet is missing. `reduced` holds frame 0.
static func draw_beam(canvas: CanvasItem, hazard: Dictionary, at: Vector2, tick: int, reduced: bool) -> void:
	var angle := float(hazard["beam_angle"])
	var length := float(hazard["radius"])
	var tele := bool(hazard.get("telegraph", false))
	var idx := beam_angle_index(angle)
	var step := beam_step(idx)
	var sc := _actor_scale
	if step == Vector2.ZERO or extra_sheet_frame(BEAM_SHEET, "beam_a00_seg", 0).is_empty():
		var col := Color(1.0, 0.45, 0.45, 0.35) if tele else Color(0.85, 0.95, 1.0, 0.85)
		canvas.draw_line(at, at + Vector2.RIGHT.rotated(angle) * length, col, float(hazard.get("beam_width", 20.0)))
		return
	var n := beam_tile_count(length, step)
	var anchor := Vector2(16, 16)
	var anc = extra_sheet(BEAM_SHEET).get("anchor")
	if anc is Array:
		anchor = Vector2(float(anc[0]), float(anc[1]))
	for part in beam_parts(idx, n, tele):
		var tg: Dictionary = extra_sheet(BEAM_SHEET)["tags"].get(part["tag"], {})
		if tg.is_empty():
			continue
		var fi := 0 if reduced else loop_index(tg["ms"], tick)
		var fr := extra_sheet_frame(BEAM_SHEET, part["tag"], fi)
		if fr.is_empty():
			continue
		var cell: Vector2 = at + (step * float(part["k"]) - anchor + fr["offset"]) * sc
		canvas.draw_texture_rect_region(fr["tex"], Rect2(cell, fr["region"].size * sc), fr["region"])

const WATER_STATES := "water_states"

## Pure: electrified-cell look from the cell index only (no RNG): variant 1..4 (20/40/20/20 percent) and frame offset 0..3.
static func elec_choice(cell: Vector2i) -> Dictionary:
	var h: int = (cell.x * 73856093 ^ cell.y * 19349663) & 0x7fffffff
	var r := h % 100
	return {"variant": 1 if r < 20 else (2 if r < 60 else (3 if r < 80 else 4)), "offset": (h / 100) % 4}

## Tag + frame for a state_view cell ({} for none). Frozen cells are shallow only; electrified use the v1..v4 tags (never the legacy ones).
static func water_state_tag(state: String, deep: bool, cell: Vector2i, tick: int, reduced: bool) -> Dictionary:
	var sh := extra_sheet(WATER_STATES)
	if state == "frozen":
		var ftag := "frozen_deep" if deep else "frozen_shallow"
		var fms: Array = sh.get("tags", {}).get(ftag, {}).get("ms", [])
		return {"tag": ftag, "index": 0 if fms.is_empty() else loop_index(fms, tick)}
	var ch := elec_choice(cell)
	var tag := "elec_%s_v%d" % ["deep" if deep else "shallow", ch["variant"]]
	var ms: Array = sh.get("tags", {}).get(tag, {}).get("ms", [])
	if ms.is_empty():
		return {}
	return {"tag": tag, "index": 0 if reduced else (loop_index(ms, tick) + int(ch["offset"])) % ms.size()}

## AD-200: session.water.state_view() cells (electrified / frozen) over the base water. Skipped quietly without the sheet.
static func _draw_water_states(canvas: CanvasItem, session, offset: Vector2, tick: int, reduced: bool) -> void:
	if extra_sheet(WATER_STATES).is_empty():
		return
	var deeps: Array[Rect2] = session.water.deep_rects()
	for item in session.water.state_view():
		var rect: Rect2 = item["cell_rect"]
		var cell := Vector2i(floori(rect.position.x / 32.0), floori(rect.position.y / 32.0))
		var deep := false
		for d in deeps:
			deep = deep or d.has_point(rect.get_center())
		var pick := water_state_tag(str(item["state"]), deep, cell, tick, reduced)
		if pick.is_empty():
			continue
		var fr := extra_sheet_frame(WATER_STATES, pick["tag"], int(pick["index"]))
		if fr.is_empty():
			continue
		var dest := Rect2(rect.position - offset, fr["region"].size * _actor_scale)
		canvas.draw_texture_rect_region(fr["tex"], dest, fr["region"])
		if fr["glow"] != null:
			_queue_glow({"tex": fr["glow"], "rect": dest, "region": fr["region"], "mirror": false, "at": Vector2.ZERO})

## AD-201 Drowned Archivist FX (AD-213 r2 + AD-227 tide wave), all under actors_manifest "sheets". Drawing only; each drawer
## returns false when its sheet is missing so the caller keeps the plain shape. Looping FX hold frame 0 when `reduced`.
const POOL_RIPPLE := "pool_ripple"
const SPLASH_RING := "splash_ring"
const BOOK_PAGE := "book_page"
const WISP_SHIELD := "wisp_shield"
const TIDE_WAVE := "tide_wave"
## The shield art is authored on the body canvas (96 px, hurtbox centre at 48,48) so it wraps the boss drawn at `at`.
const BOSS_BODY_CENTER := Vector2(48, 48)
const TIDE_NOMINAL_WARN := 60.0

## Pure: frame of a one-shot after age_ticks (60 Hz); -1 once it has finished.
static func shot_index(ms: Array, age_ticks: int) -> int:
	var t := maxi(0, age_ticks) * 1000 / 60
	var acc := 0
	for i in ms.size():
		acc += int(ms[i])
		if t < acc:
			return i
	return -1

static func _sheet_ms(name: String, tag: String) -> Array:
	return extra_sheet(name).get("tags", {}).get(tag, {}).get("ms", [])

## Draws frame `index` of an extra sheet tag with art-px `anchor` (default: the sheet's pivot slice) on `at`.
## clip_x = (min, max) canvas x trims the frame horizontally (tide tiles at the arena edge); x == y means no clip.
static func _draw_extra(canvas: CanvasItem, name: String, tag: String, index: int, at: Vector2, anchor: Vector2 = Vector2(-1, -1),
		tint: Color = Color.WHITE, clip_x: Vector2 = Vector2.ZERO) -> bool:
	var fr := extra_sheet_frame(name, tag, index)
	if fr.is_empty():
		return false
	if anchor.x < 0.0:
		var anc = extra_sheet(name).get("anchor")
		anchor = Vector2(float(anc[0]), float(anc[1])) if anc is Array else Vector2.ZERO
	var region: Rect2 = fr["region"]
	var dest := Rect2(at + (fr["offset"] - anchor) * _actor_scale, region.size * _actor_scale)
	if clip_x.x != clip_x.y:
		var left := maxf(dest.position.x, clip_x.x)
		var right := minf(dest.end.x, clip_x.y)
		if right <= left:
			return true
		region = Rect2(region.position + Vector2((left - dest.position.x) / _actor_scale, 0.0), Vector2((right - left) / _actor_scale, region.size.y))
		dest = Rect2(Vector2(left, dest.position.y), Vector2(right - left, dest.size.y))
	canvas.draw_texture_rect_region(fr["tex"], dest, region, tint)
	if fr["glow"] != null:
		_queue_glow({"tex": fr["glow"], "rect": dest, "region": region, "mirror": false, "at": Vector2.ZERO})
	return true

## Emerge landing ripple (4 frames stretched over the emerge telegraph window), under the usual danger circle.
static func draw_pool_ripple(canvas: CanvasItem, at: Vector2, state_tick: int, window_ticks: int) -> bool:
	var n := int(extra_sheet(POOL_RIPPLE).get("tags", {}).get("telegraph", {}).get("frames", 0))
	return n > 0 and _draw_extra(canvas, POOL_RIPPLE, "telegraph", stretched_index(state_tick, window_ticks, n), at)

## Splash ring on an Archivist emerge boss_ring hazard (one shot from its first tick; the damage ring is drawn regardless).
static func draw_splash_ring(canvas: CanvasItem, at: Vector2, age_ticks: int) -> bool:
	var i := shot_index(_sheet_ms(SPLASH_RING, "splash"), age_ticks)
	return i >= 0 and _draw_extra(canvas, SPLASH_RING, "splash", i, at)

## Pure: {tag, index} of a book page: torn one-shot once dead (index -1 = finished, skip), burn while Burning, else flutter.
static func page_pick(tick: int, burning: bool, dead_age: int, reduced: bool) -> Dictionary:
	if dead_age >= 0:
		return {"tag": "torn", "index": shot_index(_sheet_ms(BOOK_PAGE, "torn"), dead_age)}
	var tag := "burn" if burning else "flutter"
	var ms := _sheet_ms(BOOK_PAGE, tag)
	return {"tag": tag, "index": 0 if reduced or ms.is_empty() else loop_index(ms, tick)}

static func draw_page(canvas: CanvasItem, at: Vector2, tick: int, burning: bool, dead_age: int, reduced: bool) -> bool:
	var pick := page_pick(tick, burning, dead_age, reduced)
	return int(pick["index"]) >= 0 and _draw_extra(canvas, BOOK_PAGE, str(pick["tag"]), int(pick["index"]), at)

## Wisp shield bubble around the boss at `at` (loop), or its break one-shot when `break_age` >= 0.
static func draw_wisp_shield(canvas: CanvasItem, at: Vector2, tick: int, break_age: int, reduced: bool) -> bool:
	if break_age >= 0:
		var i := shot_index(_sheet_ms(WISP_SHIELD, "break"), break_age)
		return i >= 0 and _draw_extra(canvas, WISP_SHIELD, "break", i, at, BOSS_BODY_CENTER)
	var ms := _sheet_ms(WISP_SHIELD, "loop")
	return not ms.is_empty() and _draw_extra(canvas, WISP_SHIELD, "loop", 0 if reduced else loop_index(ms, tick), at, BOSS_BODY_CENTER)

## Pure: x of each tide tile's art origin (tiles are `tile_w` wide); one tile is centred on gap_x (it takes the gap frame),
## the rest tile left and right until bounds are covered. Returns [{x, gap}] sorted by x.
static func tide_tiles(gap_x: float, tile_w: float, left: float, right: float) -> Array:
	var tiles: Array = []
	var x0 := gap_x - tile_w * 0.5
	var k := -ceili((x0 - left) / tile_w)
	while x0 + k * tile_w < right:
		tiles.append({"x": x0 + k * tile_w, "gap": k == 0})
		k += 1
	return tiles

## boss_tide_wave from the AD-227 sheet: wave frames tiled across the arena, a gap frame centred on gap_x. The hit band is the
## sheet's 'hit' slice (top of the band at the hazard y). While warning (hazard.telegraph) it is frame 0 tinted with the
## danger ramp (telegraph.circle colours); false when the sheet is missing (caller falls back to a plain band).
static func draw_tide_wave(canvas: CanvasItem, hazard: Dictionary, offset: Vector2, reduced: bool) -> bool:
	var sh := extra_sheet(TIDE_WAVE)
	if sh.is_empty() or extra_sheet_frame(TIDE_WAVE, "wave", 0).is_empty() or extra_sheet_frame(TIDE_WAVE, "gap", 0).is_empty():
		return false
	var tele := bool(hazard.get("telegraph", false))
	var tint := Color.WHITE
	if tele:
		tint = telegraph_colors("telegraph.circle", float(hazard.get("age", 0)) / TIDE_NOMINAL_WARN)["outline"]
	var bounds: Rect2 = hazard["bounds"]
	var gap_x := float(hazard["gap_x"]) - offset.x
	var tick := int(hazard.get("age", 0))
	var wi := 0 if tele or reduced else loop_index(_sheet_ms(TIDE_WAVE, "wave"), tick)
	var gi := 0 if tele or reduced else loop_index(_sheet_ms(TIDE_WAVE, "gap"), tick)
	var top := float(hazard["y"]) - offset.y
	var tile_w := float(sh["canvas"][0]) * _actor_scale
	var clip := Vector2(bounds.position.x - offset.x, bounds.end.x - offset.x)
	for tile in tide_tiles(gap_x, tile_w, clip.x, clip.y):
		# the 'hit' slice starts 13 art px below the frame top; the anchor puts it on the hazard y
		var at := Vector2(float(tile["x"]) + tile_w * 0.5, top)
		_draw_extra(canvas, TIDE_WAVE, "gap" if tile["gap"] else "wave", gi if tile["gap"] else wi, at, Vector2(32, 13), tint, clip)
	return true

const CISTERN_TILES := "ad_til_flooded_cistern"

static func _cistern_ready() -> bool:
	_export_data()
	return _manifest.has(CISTERN_TILES)

## Region of a cistern tileset frame for a tag; index loops over the tag frames.
static func _cistern_region(tag: String, index: int) -> Rect2:
	var j: Dictionary = _export_json(CISTERN_TILES)
	var tg: Dictionary = _manifest[CISTERN_TILES]["tags"][tag]
	var f: Dictionary = j["frames"][int(tg["from"]) + posmod(index, int(tg["frames"]))]["frame"]
	return Rect2(f["x"], f["y"], f["w"], f["h"])

## Pure: index inside a tag's ms list at a 60 Hz tick, looped.
static func loop_index(ms: Array, tick: int) -> int:
	var total := 0
	for d in ms:
		total += int(d)
	var t := (tick * 1000 / 60) % maxi(total, 1)
	var acc := 0
	for i in ms.size():
		acc += int(ms[i])
		if t < acc:
			return i
	return ms.size() - 1

static func _tile_floor_cistern(canvas: CanvasItem, view: Rect2, offset: Vector2, stage: int) -> void:
	_export_json(CISTERN_TILES)
	var tex: Texture2D = _texs[CISTERN_TILES]
	var count: int = int(_manifest[CISTERN_TILES]["tags"]["floor"]["frames"])
	canvas.draw_rect(Rect2(Vector2.ZERO, view.size), Color("#0f1924"))
	var first_x := int(floor(offset.x / 32))
	var first_y := int(floor(offset.y / 32))
	for ay in int(ceil(view.size.y / 32)) + 3:
		for ax in int(ceil(view.size.x / 32)) + 3:
			var gx := first_x + ax
			var gy := first_y + ay
			var h: int = (gx * 73856093 ^ gy * 19349663 ^ stage * 83492791) & 0x7fffffff
			canvas.draw_texture_rect_region(tex, Rect2(Vector2(gx * 32, gy * 32) - offset, Vector2(32, 32)),
				_cistern_region("floor", h % count))

static func tile_floor(canvas: CanvasItem, view: Rect2, offset: Vector2, stage: int = 0) -> void:
	if stage == 2 and _cistern_ready():
		_tile_floor_cistern(canvas, view, offset, stage)
		return
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

## AD-202: pits block walking only; very dark placeholder fill until pit art exists. Drawn after the floor, before walls.
static func pits(canvas: CanvasItem, rects: Array, offset: Vector2) -> void:
	for rect in rects:
		canvas.draw_rect(Rect2(rect.position-offset,rect.size),Color("#05070b"))
		canvas.draw_rect(Rect2(rect.position-offset,rect.size),Color("#161d28"),false,2)

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
	kind = resolve_kind(kind)
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
	for status_id in ["burning","wet","charged","chilled","frozen","brittle"]:
		if current.has(status_id):
			draw_fx(canvas,"status."+status_id,at+Vector2(15,-(target.radius+21)),tick,0.0,0.0,Color.WHITE,slot)
			slot += 1

# AD-039: P1 spell FX are the default visuals (not behind F6). Resolved through engine_map.fx + manifest.
const FX_ELEMENTS := ["fire","water","lightning","cold","force"]
const FX_EVENTS := [
	"projectile.fire","projectile.water","projectile.lightning","projectile.neutral",
	"orb.fire","orb.water","orb.lightning","mod.homing",
	"impact.fire","impact.water","impact.lightning","impact.neutral",
	"burst.fire","burst.water","burst.lightning",
	"projectile.cold","impact.cold","burst.cold","orb.cold","projectile.force","impact.force","burst.force","orb.force",
	"status.chilled","status.frozen","status.brittle",
	"reaction.shatter","reaction.steam","reaction.flash_freeze","mod.chain","mod.rapid",
	"trigger.on_kill","trigger.on_expire","trigger.timer",
	"reaction.arc","reaction.extinguish","mod.split","mod.pierce","trigger.on_hit",
	"status.wet","status.burning","status.charged",
	"cast.charge","cast.muzzle","dash.trail","hit.spark","enemy.spawn","enemy.dissolve","enemy.bolt","enemy.bolt_impact",
	"boss.bullet","boss.phase","room.clear","telegraph.circle","telegraph.line","telegraph.dash_lane"]
## AD-155: mapped events the sim emits no trace / visual for (mod.rapid only changes cooldown and damage scale;
## on_expire and timer fire without a hit position, so they are drawn only when a payload spawn carries one).
const FX_UNEMITTED := ["mod.rapid"]
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

## AD-155: glow slice of an fx_frame result. Glow sheets are packed separately, so their own json is authoritative
## (same frame size as the base; only the sheet position may differ). {} when the stem has no glow.
static func fx_glow_frame(fr: Dictionary) -> Dictionary:
	if fr.is_empty():
		return {}
	var png: String = str(_manifest[fr["stem"]].get("glow", ""))
	if png == "":
		return {}
	if not _glow_tex.has(png):
		_glow_tex[png] = load(png)
		_glow_json[png] = JSON.parse_string(FileAccess.get_file_as_string(png.get_basename() + ".json"))
	var i: int = int(_manifest[fr["stem"]]["tags"][fr["tag"]]["from"]) + int(fr["index"])
	var f: Dictionary = _glow_json[png]["frames"][i]["frame"]
	return {"tex": _glow_tex[png], "region": Rect2(f["x"], f["y"], f["w"], f["h"])}

static var _glow_json: Dictionary = {}

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

## AD-088: telegraph style block for an event from presentation_v1.json ({} if unknown).
static func telegraph_style(event: String) -> Dictionary:
	if _telegraph_styles.is_empty():
		var data = JSON.parse_string(FileAccess.get_file_as_string(PRESENTATION))
		_telegraph_styles = data["telegraph_style"] if data is Dictionary and data.has("telegraph_style") else {"_": {}}
	return _telegraph_styles.get(event, {})

## AD-088: pure {fill, outline} colours; alpha swells linearly from pulse.start to 1.0 (monotonic, no oscillation).
static func telegraph_colors(event: String, progress: float) -> Dictionary:
	var st := telegraph_style(event)
	var tint := Color(String(st.get("tint", "#f0a060")))
	var pulse: Dictionary = st.get("pulse", {})
	var fa := float(st.get("fill_alpha", 0.3))
	var oa := float(st.get("outline_alpha", 0.75))
	var start := float(pulse.get("start", 0.75))
	var p := clampf(progress, 0.0, 1.0)
	if p > start and start < 1.0:
		var k := (p - start) / (1.0 - start)
		fa = lerpf(fa, float(pulse.get("fill_alpha_peak", fa)), k)
		oa = lerpf(oa, float(pulse.get("outline_alpha_peak", oa)), k)
	return {"fill": Color(tint.r, tint.g, tint.b, fa), "outline": Color(tint.r, tint.g, tint.b, oa)}

## Draws region*scale around the pivot. uniform > 0 scales both axes to that world diameter (telegraph circle). length > 0 stretches only along x (lanes, lines, arcs).
## Status events also draw the AD-033 icon at the overlay's symbol slice (slot offsets stacked icons).
static func draw_fx(canvas: CanvasItem, event: String, center: Vector2, age_ticks: int, rotation: float = 0.0,
		length: float = 0.0, modulate: Color = Color.WHITE, slot: int = 0, uniform: float = 0.0, window: int = 0, arc_degrees: float = 0.0) -> void:
	if event == "telegraph.arc":
		_draw_telegraph_arc(canvas, center, rotation, uniform / 2.0, arc_degrees, age_ticks, modulate, window)
		return
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
	var dest := Rect2(Vector2(-pivot.x * sx, -pivot.y * sc), Vector2(region.size.x * sx, region.size.y * sc))
	if event.begins_with("telegraph."):
		var progress := float(age_ticks) / float(maxi(1, window)) if window > 0 else 0.0
		var cols := telegraph_colors(event, progress)
		var fill: Color = cols["fill"] * modulate
		var line: Color = cols["outline"] * modulate
		last_telegraph_draw = {"event": event, "fill": fill, "outline": line, "progress": progress}
		canvas.draw_texture_rect_region(_texs[fr["stem"]], dest, region, fill)
		if event == "telegraph.circle":
			canvas.draw_arc(Vector2.ZERO, region.size.x * sc / 2.0, 0.0, TAU, 48, line, 2.0)
		else:
			canvas.draw_rect(dest, line, false, 2.0)
		canvas.draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
		return
	canvas.draw_texture_rect_region(_texs[fr["stem"]], dest, region, modulate)
	var gl := fx_glow_frame(fr)
	if not gl.is_empty():
		_queue_glow({"tex": gl["tex"], "rect": dest, "region": gl["region"], "mirror": false, "at": center, "rot": rotation})
	if event.begins_with("status."):
		_status_icon(canvas, event, fr, slot, modulate)
	canvas.draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)

## AD-197: wedge telegraph (no art yet), same danger tint as telegraph.circle. center is the arc centre, radius the swipe radius.
static func _draw_telegraph_arc(canvas: CanvasItem, center: Vector2, rotation: float, radius: float, arc_degrees: float,
		age_ticks: int, modulate: Color, window: int) -> void:
	var progress := float(age_ticks) / float(maxi(1, window)) if window > 0 else 0.0
	var cols := telegraph_colors("telegraph.circle", progress)
	var fill: Color = cols["fill"] * modulate
	var line: Color = cols["outline"] * modulate
	last_telegraph_draw = {"event": "telegraph.arc", "fill": fill, "outline": line, "progress": progress}
	var half := deg_to_rad(arc_degrees) * 0.5
	var pts := PackedVector2Array([center])
	for i in 25:
		pts.append(center + Vector2.from_angle(rotation - half + 2.0 * half * float(i) / 24.0) * radius)
	canvas.draw_colored_polygon(pts, fill)
	canvas.draw_arc(center, radius, rotation - half, rotation + half, 24, line, 2.0)
	canvas.draw_line(center, center + Vector2.from_angle(rotation - half) * radius, line, 2.0)
	canvas.draw_line(center, center + Vector2.from_angle(rotation + half) * radius, line, 2.0)

## AD-045: the icon's bottom-centre sits on the 1x1 'symbol' slice (overlay-local art px).
static func _status_icon(canvas: CanvasItem, event: String, fr: Dictionary, slot: int, modulate: Color) -> void:
	var sym: Dictionary = _manifest[fr["stem"]]["slices"].get("symbol", {})
	if sym.is_empty():
		return
	var atlas: String = _map["icons"]
	if _icon_index.is_empty():
		_icon_index = JSON.parse_string(FileAccess.get_file_as_string("res://art/export/ico/%s_index.json" % atlas))["icons"]
	var cell: Dictionary = _icon_index["ad_ico_" + event.trim_prefix("status.")]
	_export_json(atlas)
	var sc: float = float(_map.get("scale", 2))
	var anchor: Vector2 = (Vector2(float(sym["x"]), float(sym["y"])) - fr["pivot"]) * sc
	var size := Vector2(float(cell["w"]), float(cell["h"])) * sc
	canvas.draw_texture_rect_region(_texs[atlas],
		Rect2(anchor + Vector2(-size.x / 2.0 + slot * size.x, -size.y), size),
		Rect2(float(cell["x"]), float(cell["y"]), float(cell["w"]), float(cell["h"])), modulate)

## AD-155: sim.visuals "reaction" ids -> one-shot FX events.
const REACTION_FX := {"wet_cold_freeze": "reaction.flash_freeze", "frozen_force_shatter": "reaction.shatter",
	"fire_thaw_steam": "reaction.steam"}

static func _element(essence_id: String) -> String:
	var el := essence_id.trim_prefix("essence.")
	return el if el in FX_ELEMENTS else "neutral"

## AD-132: beam/field colour by essence (visual only).
static func essence_color(essence_id: String) -> Color:
	match _element(essence_id):
		"fire": return Color("#f08a3c")
		"water": return Color("#4aa8e8")
		"lightning": return Color("#f5e65a")
		"cold": return Color("#9fe6f4")
		"force": return Color("#c9a6f0")
	return Color("#e8e0cc")

## AD-155: beam piece list [{stem, part, region, pos (world), rot, scale, pivot}] for from->to at the map's 1x scale.
## Segment pieces tile [0,|to-from|] exactly (last tile cropped); start/end caps overlay the ends. Pure; [] when unmapped.
static func beam_segments(from: Vector2, to: Vector2, element: String, tick: int = 0, width_scale: float = 1.0) -> Array:
	var el := "neutral" if element == "" else element
	var fs := fx_frame("beam.%s.start" % el, tick)
	var fm := fx_frame("beam.%s.segment" % el, tick)
	var fe := fx_frame("beam.%s.end" % el, tick)
	if fs.is_empty() or fm.is_empty() or fe.is_empty():
		return []
	_export_data()
	var k := float(_map.get("beam", {}).get("scale", 1)) * 1.0
	var ws := k * width_scale
	var dir := to - from
	var length := dir.length()
	var rot := dir.angle()
	var u := dir / length if length > 0.0 else Vector2.RIGHT
	var out: Array = []
	var tile: float = fm["region"].size.x * k
	var along := 0.0
	while along < length - 0.001:
		var w := minf(tile, length - along)
		var reg: Rect2 = fm["region"]
		reg.size.x = w / k
		out.append({"stem": fm["stem"], "part": "segment", "region": reg, "pos": from + u * along, "rot": rot,
			"scale": Vector2(k, ws), "pivot": Vector2(0.0, fm["pivot"].y), "tag": fm})
		along += w
	out.append({"stem": fs["stem"], "part": "start", "region": fs["region"], "pos": from, "rot": rot,
		"scale": Vector2(k, ws), "pivot": fs["pivot"], "tag": fs})
	out.append({"stem": fe["stem"], "part": "end", "region": fe["region"], "pos": to, "rot": rot,
		"scale": Vector2(k, ws), "pivot": fe["pivot"], "tag": fe})
	return out

static func _draw_beam_sprites(canvas: CanvasItem, from: Vector2, to: Vector2, element: String, tick: int, width_scale: float) -> bool:
	var pieces := beam_segments(from, to, element, tick, width_scale)
	if pieces.is_empty():
		return false
	for pc in pieces:
		var reg: Rect2 = pc["region"]
		var sc: Vector2 = pc["scale"]
		var dest := Rect2(-pc["pivot"] * sc, reg.size * sc)
		canvas.draw_set_transform(pc["pos"], pc["rot"], Vector2.ONE)
		canvas.draw_texture_rect_region(_texs[pc["stem"]], dest, reg)
		var gl := fx_glow_frame(pc["tag"])
		if not gl.is_empty():
			var greg: Rect2 = gl["region"]
			greg.size.x = reg.size.x
			_queue_glow({"tex": gl["tex"], "rect": dest, "region": greg, "mirror": false, "at": pc["pos"], "rot": pc["rot"]})
	canvas.draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
	return true

## AD-132/AD-155: draws beam and field sprites from sim.visuals (primitive lines/circles when an asset is missing);
## `offset` is the camera offset, `tick` animates the sprites. Visual only.
static func draw_form_visuals(canvas: CanvasItem, visuals: Array, offset: Vector2 = Vector2.ZERO, tick: int = 0) -> void:
	for v in visuals:
		var essence := str(v.get("essence", ""))
		var el := _element(essence)
		var color := essence_color(essence)
		var age := int(v.get("age", tick))
		if v["kind"] == "beam":
			var wscale := float(v.get("width_scale", 1.0))
			if v.get("expand", false):
				wscale *= float(_map.get("beam", {}).get("expand_width", 1.0))
			if _draw_beam_sprites(canvas, v["from"] - offset, v["to"] - offset, el, age, wscale):
				continue
			canvas.draw_line(v["from"] - offset, v["to"] - offset, Color(color, 0.35), 9.0)
			canvas.draw_line(v["from"] - offset, v["to"] - offset, color, 3.0)
		elif v["kind"] == "field":
			var ev := "field." + el
			if not fx_frame(ev, age).is_empty():
				draw_fx(canvas, ev, v["position"] - offset, age, 0.0, 0.0, Color.WHITE, 0, float(v["radius"]) * 2.0)
				continue
			canvas.draw_circle(v["position"] - offset, float(v["radius"]), Color(color, 0.22))
			canvas.draw_arc(v["position"] - offset, float(v["radius"]), 0.0, TAU, 48, Color(color, 0.8), 2.0)

static func _pos(p: Variant) -> Vector2:
	return Vector2(float(p["x"]), float(p["y"])) if p is Dictionary else Vector2(p)

## Pure: FX list [{event, at (world), age, rotation, length, slot}] from session state; no drawing.
## memo is per-canvas render memory (spawn ticks, trace cursors, last statuses, pending one-shots).
static func collect_fx(session, tick: int, memo: Dictionary) -> Array:
	var sim = session.sim
	var out: Array = []
	for key in ["born", "cursor", "prev", "since", "seen", "known", "dead", "phase", "roar", "eshots"]:
		if not memo.has(key):
			memo[key] = {}
	if not memo.has("shots"):
		memo["shots"] = []
	var shots: Array = memo["shots"]
	var live: Dictionary = {}
	var pierce_ids: Dictionary = {}
	for entry in sim.active:
		if entry["kind"] in ["beam", "field"]:
			continue  # AD-132: drawn from sim.visuals as line / circle, not as a projectile sprite
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
			"reaction":
				var rev: String = REACTION_FX.get(str(v.get("reaction", "")), "")
				if rev != "":
					_shot(shots, rev, v["position"], tick)
			"arc":
				var d: Vector2 = v["to"] - v["from"]
				_shot(shots, "reaction.arc", (v["from"] + v["to"]) / 2.0, tick, d.angle(), d.length())
	memo["seen"] = seen_now
	# Trace-derived modifier / trigger FX, consumed through per-type cursors.
	var batch: Dictionary = {}
	for kind in ["spawn", "hit", "trigger", "chain"]:
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
	var spawn_at: Dictionary = {}
	for r in batch["spawn"]:
		spawn_at[int(r["parent_effect_id"])] = _pos(r["position"])
	for r in batch["trigger"]:
		var pid := int(r["parent_effect_id"])
		var tev: String = str(r.get("reason", "trigger.on_hit"))
		if not tev.begins_with("trigger."):
			tev = "trigger.on_hit"
		if tev == "trigger.on_hit":
			if hit_at.has(pid):
				_shot(shots, tev, hit_at[pid], tick)
		elif spawn_at.has(pid):
			_shot(shots, tev, spawn_at[pid], tick)
		elif hit_at.has(pid):
			_shot(shots, tev, hit_at[pid], tick)
	for r in batch["chain"]:
		var ct = sim.targets.get_target(int(r["target_id"]))
		if ct != null:
			_shot(shots, "mod.chain", ct.position, tick)
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
		for sid in ["burning", "wet", "charged", "chilled", "frozen", "brittle"]:
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

## AD-089: ranged telegraphs are a short aim line, never longer than this (px).
const RANGED_TELEGRAPH_MAX := 96.0

static func ranged_telegraph_length(intent_range: float) -> float:
	if intent_range <= 0.0:
		return RANGED_TELEGRAPH_MAX
	return minf(intent_range, RANGED_TELEGRAPH_MAX)

## AD-035 feedback, telegraphs and hostile shots (presentation only).
static func _collect_feedback(session, tick: int, memo: Dictionary, out: Array) -> void:
	var sim = session.sim
	var mage: Vector2 = sim.actor.position
	var shots: Array = memo["shots"]
	var pending: Array = []
	var hostile: Array = []
	# Hostile shots; a vanished id leaves an impact at its last position.
	var current: Dictionary = {}
	for s in session.enemy_shots:
		var sid := int(s["id"])
		var boss := _is_boss_id(session, int(s["source_id"]))
		current[sid] = true
		memo["eshots"][sid] = {"at": s["position"], "boss": boss}
		hostile.append({"event": "boss.bullet" if boss else "enemy.bolt", "at": s["position"], "age": tick,
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
		if enemy.get("state") == "roar" and int(memo["roar"].get(id, 0)) != int(enemy.phase):
			memo["roar"][id] = int(enemy.phase)
			pending.append(["boss.phase", target.position])
		if enemy.state != "windup" or enemy.intent == null or not target.alive():
			continue
		var intent: Dictionary = enemy.intent.snapshot()
		var to_mage: Vector2 = mage - target.position
		var item := {"at": target.position, "age": int(enemy.state_tick), "rotation": to_mage.angle(), "length": 0.0, "slot": 0,
			"window": int(enemy.tuning["telegraph_ticks"])}
		var shape := str(intent.get("telegraph_shape", ""))
		if shape == "none":
			continue
		if shape == "arc":
			item["event"] = "telegraph.arc"
			item["at"] = intent["arc_center"]
			item["rotation"] = Vector2(intent["direction"]).angle()
			item["uniform"] = 2.0 * float(intent["arc_radius"])
			item["arc_degrees"] = float(intent["arc_degrees"])
		elif shape == "slam":
			item["event"] = "telegraph.circle"
			item["at"] = intent["landing"]
			item["uniform"] = 2.0 * float(intent["range"])
		elif enemy.kind == "undead_warden":
			if intent["kind"] == "radial":
				item["event"] = "telegraph.circle"
				item["uniform"] = 2.0 * float(intent["range"])
			else:
				item["event"] = "telegraph.dash_lane"
				item["length"] = to_mage.length()
		elif enemy.tuning.get("attack_kind","") == "melee":
			item["event"] = "telegraph.circle"
			item["uniform"] = 2.0 * float(intent["range"])
		else:
			item["event"] = "telegraph.line"
			item["length"] = ranged_telegraph_length(float(intent.get("range", 0.0)))
			var dir = intent.get("direction", Vector2.ZERO)
			if dir is Vector2 and dir.length() > 0.001:
				item["rotation"] = dir.angle()
		out.append(item)
	out.append_array(hostile)
	for hazard in session.hazards:
		if hazard["kind"] == "boss_warning":
			out.append({"event": "telegraph.circle", "at": hazard["position"], "age": int(hazard["age"]), "rotation": 0.0, "length": 0.0, "slot": 0,
				"uniform": 2.0 * float(hazard["radius"]), "window": int(hazard["duration_ticks"])})
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

## Draws the layout left to right, top-aligned at `at`, tinted by `color` (default white), nearest. Returns the width in world units.
static func draw_damage_number(canvas: CanvasItem, symbol: String, text: String, at: Vector2, color: Color = Color.WHITE) -> float:
	var layout := damage_glyph_layout(symbol, text)
	if layout.is_empty():
		return 0.0
	var sc: float = float(_map.get("scale", 2))
	var tex: Texture2D = _texs[export_map()["damage_glyphs"]]
	var right := 0.0
	for item in layout:
		var r: Rect2 = item["region"]
		canvas.draw_texture_rect_region(tex, Rect2(at + Vector2(float(item["x"]) * sc, 0.0), r.size * sc), r, color)
		right = maxf(right, (float(item["x"]) + r.size.x) * sc)
	return right

## AD-137 placeholder tint for a borrowed sprite: the enemy 'color' lerped over white; alpha < 1 while intangible.
static func placeholder_modulate(kind: String, color: Color, intangible: bool, warning_flicker: bool) -> Color:
	if actor_manifest().has(kind):
		return Color(1.0,1.0,1.0,0.4 if intangible else (0.7 if warning_flicker else 1.0))
	if not PLACEHOLDER_KIND.has(kind):
		return Color.WHITE
	var out := Color.WHITE.lerp(color,0.6)
	out.a = 0.4 if intangible else (0.7 if warning_flicker else 1.0)
	return out

## AD-137 telegraph markers (presentation only; read flags/session state, never write them).
static func draw_enemy_markers(canvas: CanvasItem, enemy, at: Vector2, tick: int, offset: Vector2) -> void:
	var target = enemy.target
	if target.alive():
		for behaviour in enemy.tuning.get("behaviours",[]):
			if behaviour["id"] == "shield_front" and not enemy.shield_broken:
				var half := deg_to_rad(float(behaviour["front_arc_degrees"]))
				canvas.draw_arc(at,target.radius+6.0,enemy.heading.angle()-half,enemy.heading.angle()+half,16,Color("#cfe3ee"),4.0)
			elif behaviour["id"] == "explode_on_death":
				var low: bool = target.health.current <= target.health.maximum*0.3
				if enemy.state == "windup" or low:
					canvas.draw_arc(at,float(behaviour["explode_radius"]),0.0,TAU,40,Color(0.8,0.9,0.3,0.45+0.25*float((tick/6)%2)),2.0)
		if enemy.get("staggered") == true:
			canvas.draw_arc(at,target.radius+10.0,0.0,TAU,32,Color(1.0,0.85,0.3,0.9),3.0)

## AD-138 placeholder water: translucent shallow, darker opaque deep. Visual only.
static func draw_water(canvas: CanvasItem, session, offset: Vector2, reduced: bool = false) -> void:
	if session.water == null:
		return
	var cistern := _cistern_ready()
	if cistern:
		_export_json(CISTERN_TILES)
	var tick: int = session.sim.clock.tick
	for tile in session.water.view():
		var rect: Rect2 = tile["rect"]
		rect.position -= offset
		var deep: bool = str(tile["kind"]) == "deep"
		if cistern:
			_draw_water_cells(canvas, rect, "deep_loop" if deep else "water_loop", tick, Color(1, 1, 1, 1.0 if deep else 0.85))
			continue
		canvas.draw_rect(rect,Color(0.08,0.2,0.45,1.0) if deep else Color(0.55,0.78,0.95,0.4))
	_draw_water_states(canvas, session, offset, tick, reduced)

## Fills rect with 32-unit cells of a looped cistern tag; partial edge cells are clipped by region size.
## Shore/deep 47-blob edge autotiling is out of scope here.
static func _draw_water_cells(canvas: CanvasItem, rect: Rect2, tag: String, tick: int, col: Color) -> void:
	var tg: Dictionary = _manifest[CISTERN_TILES]["tags"][tag]
	var region := _cistern_region(tag, loop_index(tg["ms"], tick))
	var tex: Texture2D = _texs[CISTERN_TILES]
	var y := 0.0
	while y < rect.size.y:
		var x := 0.0
		var ch := minf(32.0, rect.size.y - y)
		while x < rect.size.x:
			var cw := minf(32.0, rect.size.x - x)
			canvas.draw_texture_rect_region(tex, Rect2(rect.position + Vector2(x, y), Vector2(cw, ch)),
				Rect2(region.position, Vector2(cw / 2.0, ch / 2.0)), col)
			x += 32.0
		y += 32.0

## AD-150 env props: primitive placeholder draws. Reads session.env_props.view() only; never mutates the sim.
## Pure: {stem, tag, index} of the imported AD-120 prop frame for a view entry, or {} (unmapped / skipped).
static func env_prop_frame(kind: String, state: String, lit: bool, stage: int, tick: int) -> Dictionary:
	_export_data()
	var base := {"crate": "burnable_crate", "urn": "breakable_urn", "puddle": "puddle", "cobweb": "cobweb",
		"brazier": "brazier", "cracked_wall": "cracked_wall", "boss_pillar": "cracked_wall",
		"pillar": "cracked_wall", "cracked_pillar": "cracked_wall", "broken_wall": "cracked_wall", "column": "cracked_wall",
		"rubble": "rubble_set", "sarcophagus": "rubble_set"}.get(kind, "") as String
	if base == "" or state == "destroyed":
		return {}
	# AD-202 placeholders: the rubble set has one stage-less stem with a single "static" tag.
	if base == "rubble_set":
		return {"stem": "ad_prp_rubble_set", "tag": "static", "index": loop_index(_manifest["ad_prp_rubble_set"]["tags"]["static"]["ms"], tick)} if _manifest.has("ad_prp_rubble_set") else {}
	var stem := "ad_prp_" + base + ("_cistern" if stage == 2 else ("" if kind == "urn" else "_ruins"))
	var tag := "idle"
	if kind == "puddle" and state == "frozen":
		stem = "ad_prp_ice_patch"
	elif kind == "brazier":
		tag = "lit" if lit else "unlit"
	elif state == "burning":
		tag = "burning"
	if not _manifest.has(stem) or not _manifest[stem]["tags"].has(tag):
		return {}
	return {"stem": stem, "tag": tag, "index": loop_index(_manifest[stem]["tags"][tag]["ms"], tick)}

## Draws an env prop frame (scale 2, pivot at the rect's bottom-centre) and queues its glow. False if unavailable.
static func _draw_env_prop_art(canvas: CanvasItem, fr: Dictionary, rect: Rect2) -> bool:
	if fr.is_empty():
		return false
	var stem: String = fr["stem"]
	var j: Dictionary = _export_json(stem)
	var tg: Dictionary = _manifest[stem]["tags"][fr["tag"]]
	var f: Dictionary = j["frames"][int(tg["from"]) + int(fr["index"])]["frame"]
	var region := Rect2(f["x"], f["y"], f["w"], f["h"])
	var pv: Array = _manifest[stem]["pivot"]
	var dst := Rect2(Vector2(rect.get_center().x, rect.end.y) - Vector2(float(pv[0]), float(pv[1])) * 2.0, region.size * 2.0)
	canvas.draw_texture_rect_region(_texs[stem], dst, region)
	var gp = _manifest[stem].get("glow")
	if gp != null:
		if not _glow_tex.has(gp):
			_glow_tex[gp] = load(gp)
		_queue_glow({"tex": _glow_tex[gp], "rect": dst, "region": region, "mirror": false, "at": Vector2.ZERO})
	return true

static func draw_env_props(canvas: CanvasItem, session, offset: Vector2, stage: int = 0) -> void:
	if session.env_props == null:
		return
	var tick: int = session.sim.clock.tick
	for prop in session.env_props.view():
		var state := str(prop["state"])
		if state == "destroyed":
			continue
		var rect: Rect2 = prop["rect"]
		rect.position -= offset
		var mid := rect.get_center()
		var burning := state == "burning"
		if _draw_env_prop_art(canvas, env_prop_frame(str(prop["kind"]), state, bool(prop.get("lit", false)), stage, tick), rect):
			continue
		match str(prop["kind"]):
			"crate":
				var body := Color("#8a5a32")
				var edge := Color("#4a2e18")
				if burning:
					body = body.lerp(Color("#ff8a2a"),0.5+0.25*float((tick/3)%2))
				canvas.draw_rect(rect,body)
				canvas.draw_rect(rect,edge,false,2.0)
				canvas.draw_line(rect.position,rect.end,edge,1.5)
				canvas.draw_line(Vector2(rect.end.x,rect.position.y),Vector2(rect.position.x,rect.end.y),edge,1.5)
			"cobweb":
				var web := Color(0.9,0.92,0.95,0.8 if not burning else 0.5+0.3*float((tick/3)%2))
				for corner in [rect.position,rect.end,Vector2(rect.end.x,rect.position.y),Vector2(rect.position.x,rect.end.y)]:
					canvas.draw_line(mid,corner,web,1.0)
				canvas.draw_line(Vector2(rect.position.x,mid.y),Vector2(rect.end.x,mid.y),web,1.0)
				canvas.draw_line(Vector2(mid.x,rect.position.y),Vector2(mid.x,rect.end.y),web,1.0)
			"puddle":
				var r: float = minf(rect.size.x,rect.size.y)*0.5
				canvas.draw_circle(mid,r,Color(0.75,0.9,1.0,0.7) if state == "frozen" else Color(0.45,0.7,0.9,0.4))
				canvas.draw_arc(mid,r,0.0,TAU,32,Color(0.9,0.97,1.0,0.8) if state == "frozen" else Color(0.6,0.82,0.95,0.6),1.5)
			"brazier":
				var fire: Color = essence_color("essence.fire")
				var w := rect.size.x*0.5
				canvas.draw_rect(Rect2(mid.x-w*0.6,mid.y,w*1.2,w*0.8),Color("#3d3d46"))
				canvas.draw_rect(Rect2(mid.x-w,mid.y-w*0.2,w*2.0,w*0.4),Color("#5a5a66"))
				if bool(prop.get("lit",false)):
					var flick := 0.8+0.2*float((tick/4)%2)
					canvas.draw_circle(mid+Vector2(0,-w*0.5),w*0.7*flick,fire)
					canvas.draw_circle(mid+Vector2(0,-w*0.4),w*0.35*flick,Color("#ffe9a0"))
			"urn":
				var r2: float = minf(rect.size.x,rect.size.y)*0.5
				canvas.draw_circle(mid,r2,Color("#9a5a3a"))
				canvas.draw_rect(Rect2(mid.x-r2*0.5,mid.y-r2*1.1,r2,r2*0.4),Color("#7a4228"))
				canvas.draw_arc(mid,r2,0.0,TAU,24,Color("#4a2a1a"),1.5)
			"cracked_wall":
				canvas.draw_rect(rect,Color("#4a4a58"))
				var crack := Color("#1c1c24")
				canvas.draw_polyline(PackedVector2Array([Vector2(mid.x,rect.position.y),Vector2(mid.x-4,mid.y-6),
					Vector2(mid.x+3,mid.y+2),Vector2(mid.x-2,rect.end.y)]),crack,1.5)
				canvas.draw_line(Vector2(mid.x+3,mid.y+2),Vector2(rect.end.x,mid.y+8),crack,1.0)

## AD-201: true when the hazard's source boss has the tuning key (the Archivist's pools mark its emerge ring; the warden's leap ring has none).
static func _hazard_source_has(session, hazard: Dictionary, key: String) -> bool:
	for enemy in session.enemies:
		if enemy.target.id == int(hazard.get("source_id", -1)):
			return enemy.tuning.has(key)
	return false

static func draw_hazards(canvas: CanvasItem, session, offset: Vector2, reduced: bool = false) -> void:
	for hazard in session.hazards:
		var kind := str(hazard["kind"])
		if kind == "boss_warning":
			continue
		if kind == "boss_beam":
			draw_beam(canvas,hazard,hazard["position"]-offset,session.sim.clock.tick,reduced)
			continue
		if kind == "boss_tide_wave":
			if not draw_tide_wave(canvas,hazard,offset,reduced):
				var bounds: Rect2 = hazard["bounds"]
				var band := Color(1.0,0.45,0.45,0.35) if bool(hazard.get("telegraph",false)) else Color(0.45,0.7,1.0,0.6)
				var gap_x := float(hazard["gap_x"])
				var half := float(hazard["gap_width"])*0.5
				var top := float(hazard["y"])-offset.y
				var thick := float(hazard["thickness"])
				canvas.draw_rect(Rect2(bounds.position.x-offset.x,top,gap_x-half-bounds.position.x,thick),band)
				canvas.draw_rect(Rect2(gap_x+half-offset.x,top,bounds.end.x-gap_x-half,thick),band)
			continue
		if kind == "boss_water_warning":
			var rect: Rect2 = hazard["rect"]
			canvas.draw_rect(Rect2(rect.position-offset,rect.size),Color(0.45,0.7,1.0,0.7),false,2.0)
			continue
		var at: Vector2 = hazard["position"]-offset
		if kind == "boss_ring":
			if _hazard_source_has(session,hazard,"pools"):
				draw_splash_ring(canvas,at,int(hazard["age"]))
			# AD-199: expanding danger ring at a constant colour (no per-tick alpha change, reduce-flash safe).
			var ring_radius := float(hazard["ring_per_tick"])*float(hazard["age"])
			if ring_radius > 0.0:
				canvas.draw_arc(at,ring_radius,0.0,TAU,64,telegraph_colors("telegraph.circle",1.0)["outline"],float(hazard["ring_width"]))
			continue
		if kind == "boss_zone":
			# AD-198: solid warm tint, no per-tick alpha change (reduce-flash safe).
			canvas.draw_circle(at,float(hazard["radius"]),Color(0.9,0.3,0.15,0.4))
			canvas.draw_arc(at,float(hazard["radius"]),0.0,TAU,40,Color(1.0,0.55,0.25,0.85),2.0)
			continue
		canvas.draw_circle(at,float(hazard["radius"]),Color(0.25,0.5,0.9,0.28))
		canvas.draw_arc(at,float(hazard["radius"]),0.0,TAU,40,Color(0.45,0.7,1.0,0.6),1.5)
