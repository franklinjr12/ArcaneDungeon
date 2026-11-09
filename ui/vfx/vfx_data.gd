extends RefCounted
## AD-149 render-only VFX data access. Tunables live in world/data/vfx_v1.json; textures are optional (AD-117 hook).
const DATA_PATH := "res://world/data/vfx_v1.json"
const ELEMENTS := ["fire", "water", "lightning", "cold", "force", "neutral"]
const STATUSES := ["burning", "wet", "charged", "chilled", "frozen", "brittle", "blinded"]
static var _data: Dictionary = {}
static var _textures: Dictionary = {}

static func load_data() -> Dictionary:
	if _data.is_empty():
		var parsed = JSON.parse_string(FileAccess.get_file_as_string(DATA_PATH))
		_data = parsed if parsed is Dictionary else {}
	return _data

static func element_key(essence_id: String) -> String:
	var el := essence_id.trim_prefix("essence.")
	return el if el in ELEMENTS else "neutral"

static func element_cfg(essence_id: String) -> Dictionary:
	var els: Dictionary = load_data().get("elements", {})
	return els.get(element_key(essence_id), els.get("neutral", {}))

static func status_cfg(status_id: String) -> Dictionary:
	return load_data().get("status", {}).get(status_id, {})

static func reduced_cfg() -> Dictionary:
	return load_data().get("reduced", {})

static func hit_flash_cfg() -> Dictionary:
	return load_data().get("hit_flash", {})

## High/low/off, matching Settings.lighting; unknown falls back to high.
static func particle_cap(mode: String) -> int:
	var caps: Dictionary = load_data().get("particle_cap", {})
	return int(caps.get(mode, caps.get("high", 0)))

static func spawn_cap(mode: String) -> int:
	var caps: Dictionary = load_data().get("spawn_per_tick_cap", {})
	return int(caps.get(mode, caps.get("high", 0)))

## Loaded texture when the path exists, else a cached procedural one ("glow" soft radial, "particle" soft dot).
static func texture(path: String, fallback_kind: String) -> Texture2D:
	var key := path + "|" + fallback_kind
	if _textures.has(key):
		return _textures[key]
	var tex: Texture2D = null
	if path != "" and ResourceLoader.exists(path):
		var loaded = load(path)
		if loaded is Texture2D:
			tex = _first_frame(path, loaded)
	if tex == null:
		tex = _procedural(fallback_kind)
	_textures[key] = tex
	return tex

## Multi-frame strips (sibling .json with a frames list) show frame 0 only; visuals never change sim timing.
static func _first_frame(path: String, full: Texture2D) -> Texture2D:
	var jp := path.get_basename() + ".json"
	if not FileAccess.file_exists(jp):
		return full
	var parsed = JSON.parse_string(FileAccess.get_file_as_string(jp))
	if not (parsed is Dictionary) or not (parsed.get("frames") is Array) or parsed["frames"].is_empty():
		return full
	var f: Dictionary = parsed["frames"][0].get("frame", {})
	var r := Rect2(float(f.get("x", 0)), float(f.get("y", 0)), float(f.get("w", 0)), float(f.get("h", 0)))
	if r.size.x <= 0.0 or r.size.y <= 0.0 or not Rect2(Vector2.ZERO, full.get_size()).encloses(r) or r.size == full.get_size():
		return full
	var at := AtlasTexture.new()
	at.atlas = full
	at.region = r
	return at

static func _procedural(kind: String) -> Texture2D:
	var grad := Gradient.new()
	if kind == "glow":
		grad.colors = PackedColorArray([Color(1, 1, 1, 1), Color(1, 1, 1, 0)])
		grad.offsets = PackedFloat32Array([0.0, 1.0])
	else:
		grad.colors = PackedColorArray([Color(1, 1, 1, 1), Color(1, 1, 1, 1), Color(1, 1, 1, 0)])
		grad.offsets = PackedFloat32Array([0.0, 0.55, 1.0])
	var tex := GradientTexture2D.new()
	tex.gradient = grad
	tex.fill = GradientTexture2D.FILL_RADIAL
	tex.fill_from = Vector2(0.5, 0.5)
	tex.fill_to = Vector2(1.0, 0.5)
	var px := int(load_data().get("fallback_texture_px", 32))
	tex.width = px
	tex.height = px
	return tex
