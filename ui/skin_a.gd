extends RefCounted
## AD-152: skin A (AD-095 kit) loader. Visual only; never touches the sim.
const KIT_PATH := "res://assets/ui/ad_ui_kit.json"
const ATLAS := preload("res://assets/ui/ad_ui_kit_atlas.png")
const ATLAS_GLOW := preload("res://assets/ui/ad_ui_kit_atlas_glow.png")
const LAYOUT_DIR := "res://assets/ui/layouts/"
const ICON_ATLAS := preload("res://assets/ui/icons/ad_ico_atlas_demo.png")
const ICON_INDEX_PATH := "res://assets/ui/icons/ad_ico_atlas_demo_index.json"
const PIXEL_HUD_PATH := "res://ui/pixel_hud.gd" # loaded lazily: pixel_hud.gd preloads this file
const CANVAS := Vector2(640, 360)
## Game-art note: the pause layout names the busy 25% dither; code uses the 50% dim.
const SPRITE_REMAP := {"ad_ui_modal_backdrop_25": "ad_ui_modal_backdrop_50"}

static var _kit: Dictionary = {}
static var _layouts: Dictionary = {}
static var _icons: Dictionary = {}

static func _read_json(path: String) -> Dictionary:
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		return {}
	var parsed = JSON.parse_string(f.get_as_text())
	return parsed if parsed is Dictionary else {}

static func kit() -> Dictionary:
	if _kit.is_empty():
		_kit = _read_json(KIT_PATH)
	return _kit

static func resolve(sprite: String) -> String:
	return SPRITE_REMAP.get(sprite, sprite)

static func has_sprite(name: String) -> bool:
	return kit().get("sprites", {}).has(resolve(name))

static func _region(atlas: Texture2D, name: String) -> AtlasTexture:
	var s: Dictionary = kit().get("sprites", {}).get(resolve(name), {})
	var t := AtlasTexture.new()
	t.atlas = atlas
	t.region = Rect2(s.get("x", 0), s.get("y", 0), s.get("w", 0), s.get("h", 0))
	return t

static func region(name: String) -> AtlasTexture:
	return _region(ATLAS, name)

static func glow_region(name: String) -> AtlasTexture:
	return _region(ATLAS_GLOW, name)

static func stylebox(name: String, content_margin: float = 4) -> StyleBoxTexture:
	var s := StyleBoxTexture.new()
	s.texture = region(name)
	var nine: Dictionary = kit().get("sprites", {}).get(resolve(name), {}).get("nine", {})
	s.texture_margin_left = nine.get("left", 0)
	s.texture_margin_top = nine.get("top", 0)
	s.texture_margin_right = nine.get("right", 0)
	s.texture_margin_bottom = nine.get("bottom", 0)
	s.set_content_margin_all(content_margin)
	return s

static func layout(screen: String) -> Dictionary:
	if not _layouts.has(screen):
		_layouts[screen] = _read_json("%sad_ui_screen_%s_layout.json" % [LAYOUT_DIR, screen])
	return _layouts[screen]

static func canvas_scale(viewport_size: Vector2) -> float:
	return maxf(1.0, minf(viewport_size.x / CANVAS.x, viewport_size.y / CANVAS.y))

## Top-left of the centred canvas inside the viewport.
static func canvas_origin(viewport_size: Vector2, scale: float) -> Vector2:
	return ((viewport_size - CANVAS * scale) * 0.5).floor()

static func place(control: Control, widget: Dictionary, scale: float, origin: Vector2) -> void:
	control.position = origin + Vector2(widget.get("x", 0), widget.get("y", 0)) * scale
	control.size = Vector2(widget.get("w", 0), widget.get("h", 0)) * scale

static func label_color(state: String) -> Color:
	var c: Array = kit().get("label_colors", {}).get(state, kit().get("label_colors", {}).get("normal", [255, 255, 255]))
	return Color8(int(c[0]), int(c[1]), int(c[2]))

static func _icon_key(name: String) -> String:
	var icons: Dictionary = icon_index()
	if icons.has(name):
		return name
	return "ad_ico_" + name if icons.has("ad_ico_" + name) else ""

static func icon_index() -> Dictionary:
	if _icons.is_empty():
		_icons = _read_json(ICON_INDEX_PATH).get("icons", {})
	return _icons

static func has_icon(name: String) -> bool:
	return _icon_key(name) != ""

## Demo atlas icon by name (with or without `ad_ico_`); empty region when missing.
## Callers may fall back to PixelHud.ui_icon_texture when has_icon is false.
static func icon(name: String) -> AtlasTexture:
	var t := AtlasTexture.new()
	t.atlas = ICON_ATLAS
	var k := _icon_key(name)
	if k != "":
		var s: Dictionary = icon_index()[k]
		t.region = Rect2(s.x, s.y, s.w, s.h)
	return t

## Demo atlas first, then the MVP atlas lookup.
static func icon_or_mvp(name: String) -> AtlasTexture:
	if has_icon(name):
		return icon(name)
	return load(PIXEL_HUD_PATH).ui_icon_texture(name)

static func widgets_by_id(screen: String) -> Dictionary:
	var out := {}
	for w in layout(screen).get("widgets", []):
		out[str(w.get("id", ""))] = w
	return out
