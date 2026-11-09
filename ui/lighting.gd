extends Node2D
## AD-148 render-only 2D lighting for the combat arena. Reads session data, never writes it; flicker comes from sim.clock.tick.
## Design note: a real CanvasModulate would tint the whole root canvas (side panel, slot HUD, pause menu, loadout view).
## Instead the arena canvas sits on light mask ARENA_LIGHT_MASK and one SUB-blend DirectionalLight2D with colour (1-ambient)
## multiplies only that mask by the ambient colour, i.e. a CanvasModulate limited to the arena. Point lights are ADD-blend
## and culled to the same mask. The slot HUD uses mask 0 so it is never lit or darkened.
const Art = preload("res://ui/pixel_art_renderer.gd")
const DATA_PATH := "res://world/data/lighting_v1.json"
const POOL_MODE := "high"
static var _data: Dictionary = {}
var _ambient: DirectionalLight2D
var _player: PointLight2D
var _pool: Array = []
var _room_lights: Array = []
var _room_key := ""
var _cookie: Texture2D
var _active_spells := 0

static func load_data() -> Dictionary:
	if _data.is_empty():
		var parsed = JSON.parse_string(FileAccess.get_file_as_string(DATA_PATH))
		_data = parsed if parsed is Dictionary else {}
	return _data

static func biome_key(stage: int, room_type: String) -> String:
	if room_type == "workshop":
		return "workshop"
	return ("ruins" if stage < 1 else "cistern") + ("_boss" if room_type == "boss" else "")

static func stage_config(key: String) -> Dictionary:
	var stages: Dictionary = load_data().get("stages", {})
	return stages.get(key, stages.get("ruins", {}))

## Effective per-channel multiplier of the SUB ambient light: 1 - energy * (1 - colour).
static func ambient_factor(key: String) -> Color:
	var amb: Dictionary = stage_config(key).get("ambient", {})
	var c := Color(str(amb.get("color", "#ffffff")))
	var e := float(amb.get("energy", 0.0))
	return Color(1.0 - e * (1.0 - c.r), 1.0 - e * (1.0 - c.g), 1.0 - e * (1.0 - c.b))

## Static mirror of the lit arena brightness factor at a world point (ambient + radial point lights, clamped to 1).
static func light_factor_at(key: String, world_pos: Vector2, props: Array, bounds: Rect2, player_pos: Vector2) -> Color:
	var data := load_data()
	var cfg := stage_config(key)
	var half := float(data.get("fallback_cookie_px", 128)) * 0.5
	var out := ambient_factor(key)
	var lights: Array = []
	var torch: Dictionary = cfg.get("torch", {})
	for p in props:
		if p is Array and p.size() >= 3 and str(p[0]) == "brazier" and not torch.is_empty():
			lights.append([Vector2(float(p[1]), float(p[2])), torch])
	for d in cfg.get("fixed_lights", []):
		lights.append([bounds.position + Vector2(float(d["at"][0]), float(d["at"][1])) * bounds.size, d])
	if cfg.get("fill_light") is Dictionary:
		lights.append([bounds.get_center(), cfg["fill_light"]])
	if cfg.get("player_light") is Dictionary:
		lights.append([player_pos, cfg["player_light"]])
	for l in lights:
		var d: Dictionary = l[1]
		var falloff := maxf(0.0, 1.0 - world_pos.distance_to(l[0]) / (half * float(d["texture_scale"])))
		var c := Color(str(d["color"]))
		var k := float(d["energy"]) * falloff
		out = Color(out.r + c.r * k, out.g + c.g * k, out.b + c.b * k)
	return Color(minf(out.r, 1.0), minf(out.g, 1.0), minf(out.b, 1.0))

static func mode_config(mode: String) -> Dictionary:
	var modes: Dictionary = load_data().get("modes", {})
	return modes.get(mode, modes.get(POOL_MODE, {}))

static func arena_mask() -> int:
	return int(load_data().get("arena_light_mask", 2))

static func spell_light_sources(session) -> Array:
	var out: Array = []
	for entry in session.sim.active:
		var kind := str(entry.get("kind", ""))
		if kind == "projectile" or kind == "orb":
			var fx = entry["effect"]
			out.append({"kind": kind, "at": fx.position, "essence": str(fx.root.get("essence", {}).get("id", ""))})
	for v in session.sim.visuals:
		var vk := str(v.get("kind", ""))
		if vk == "field" or vk == "burst":
			out.append({"kind": vk, "at": v["position"], "essence": str(v.get("essence", ""))})
	return out

func pool_size() -> int:
	return _pool.size()

func active_spell_lights() -> int:
	return _active_spells

func setup(canvas) -> void:
	var data := load_data()
	var mask := arena_mask()
	canvas.light_mask = mask
	if canvas.slot_hud != null:
		canvas.slot_hud.light_mask = 0
	_cookie = _make_cookie(data)
	_ambient = DirectionalLight2D.new()
	_ambient.name = "Ambient"
	_ambient.blend_mode = Light2D.BLEND_MODE_SUB
	_ambient.energy = 1.0
	_ambient.shadow_enabled = false
	_ambient.range_item_cull_mask = mask
	add_child(_ambient)
	_player = _new_point(mask)
	_player.name = "PlayerLight"
	var cap := int(mode_config(POOL_MODE).get("spell_light_cap", 0))
	for i in cap:
		var light := _new_point(mask)
		light.visible = false
		_pool.append(light)

func _make_cookie(data: Dictionary) -> Texture2D:
	var path := str(data.get("cookie_texture", ""))
	if path != "" and ResourceLoader.exists(path):
		var tex = load(path)
		if tex is Texture2D:
			return tex
	var grad := Gradient.new()
	grad.colors = PackedColorArray([Color(1, 1, 1, 1), Color(1, 1, 1, 0)])
	grad.offsets = PackedFloat32Array([0.0, 1.0])
	var tex := GradientTexture2D.new()
	tex.gradient = grad
	tex.fill = GradientTexture2D.FILL_RADIAL
	tex.fill_from = Vector2(0.5, 0.5)
	tex.fill_to = Vector2(1.0, 0.5)
	var px := int(data.get("fallback_cookie_px", 128))
	tex.width = px
	tex.height = px
	return tex

func _new_point(mask: int) -> PointLight2D:
	var light := PointLight2D.new()
	light.blend_mode = Light2D.BLEND_MODE_ADD
	light.shadow_enabled = false
	light.range_item_cull_mask = mask
	light.texture = _cookie
	add_child(light)
	return light

func _style(light: PointLight2D, color: Color, energy: float, texture_scale: float) -> void:
	light.color = color
	light.energy = energy
	light.texture_scale = texture_scale

## Rebuilds the small per-room pool (props, biome fixed lights, boss fill) when the room identity changes.
func _rebuild_room(session, key: String, room_type: String, props: Array, mode: Dictionary) -> void:
	for l in _room_lights:
		remove_child(l)
		l.queue_free()
	_room_lights.clear()
	var data := load_data()
	var bounds: Rect2 = session.world.bounds
	var mask := arena_mask()
	var cfg := stage_config(key)
	var torch: Dictionary = cfg.get("torch", {})
	for p in props:
		if p is Array and p.size() >= 3 and str(p[0]) == "brazier" and not torch.is_empty():
			var d: Dictionary = torch
			var l := _new_point(mask)
			_style(l, Color(str(d["color"])), float(d["energy"]), float(d["texture_scale"]))
			l.position = Vector2(float(p[1]), float(p[2]))
			l.set_meta("base", float(d["energy"]))
			l.set_meta("amp", float(d.get("flicker_amp", 0.0)))
			l.set_meta("period", maxf(1.0, float(d.get("flicker_period_ticks", 1))))
			l.set_meta("world", l.position)
			_room_lights.append(l)
	for d in cfg.get("fixed_lights", []):
		var l2 := _new_point(mask)
		_style(l2, Color(str(d["color"])), float(d["energy"]), float(d["texture_scale"]))
		l2.set_meta("base", float(d["energy"]))
		l2.set_meta("amp", 0.0)
		l2.set_meta("period", 1.0)
		l2.set_meta("world", bounds.position + Vector2(float(d["at"][0]), float(d["at"][1])) * bounds.size)
		_room_lights.append(l2)
	if cfg.get("fill_light") is Dictionary:
		var b: Dictionary = cfg["fill_light"]
		var l3 := _new_point(mask)
		_style(l3, Color(str(b.get("color", "#ffffff"))), float(b.get("energy", 0.0)), float(b.get("texture_scale", 1.0)))
		l3.set_meta("base", float(b.get("energy", 0.0)))
		l3.set_meta("amp", 0.0)
		l3.set_meta("period", 1.0)
		l3.set_meta("world", bounds.get_center())
		_room_lights.append(l3)

func hide_all() -> void:
	_active_spells = 0
	if _ambient != null:
		_ambient.visible = false
		_ambient.enabled = false
	for l in _pool:
		l.visible = false
		l.enabled = false
	for l in _room_lights:
		l.visible = false
		l.enabled = false
	if _player != null:
		_player.visible = false
		_player.enabled = false

func sync(canvas, session, settings, stage: int, room_type: String, props: Array) -> void:
	var mode_name: String = str(settings.lighting) if settings != null else "high"
	var mode := mode_config(mode_name)
	var tick: int = session.sim.clock.tick
	var key := biome_key(stage, room_type)
	var ambient_on := bool(mode.get("ambient", false))
	var cfg := stage_config(key)
	var amb: Color = Color(str(cfg.get("ambient", {}).get("color", "#ffffff")))
	_ambient.color = Color(1.0 - amb.r, 1.0 - amb.g, 1.0 - amb.b)
	_ambient.energy = float(cfg.get("ambient", {}).get("energy", 0.0))
	_ambient.visible = ambient_on
	_ambient.enabled = ambient_on
	var room_id := "%s|%s|%d|%s" % [key, room_type, session.get_instance_id(), JSON.stringify(props)]
	if room_id != _room_key:
		_room_key = room_id
		_rebuild_room(session, key, room_type, props, mode)
	var props_on := bool(mode.get("prop_lights", false))
	for i in _room_lights.size():
		var l: PointLight2D = _room_lights[i]
		l.visible = props_on
		l.enabled = props_on
		if props_on:
			var amp: float = l.get_meta("amp")
			var phase := TAU * float(tick) / float(l.get_meta("period")) + float(i)
			l.energy = float(l.get_meta("base")) * (1.0 + amp * sin(phase))
			l.position = canvas.local_from_world(l.get_meta("world"))
	var pl: Dictionary = cfg.get("player_light", {})
	var player_on := bool(mode.get("player_light", false)) and not pl.is_empty()
	_player.visible = player_on
	_player.enabled = player_on
	if player_on:
		_style(_player, Color(str(pl["color"])), float(pl["energy"]), float(pl["texture_scale"]))
		_player.position = canvas.local_from_world(session.sim.actor.position)
	var cap := mini(int(mode.get("spell_light_cap", 0)), _pool.size())
	var sources := spell_light_sources(session)
	var defs: Dictionary = cfg.get("spell_lights", {})
	var used := 0
	for s in sources:
		if used >= cap:
			break
		var d: Dictionary = defs.get(s["kind"], {})
		if d.is_empty():
			continue
		var light: PointLight2D = _pool[used]
		_style(light, Art.essence_color(s["essence"]), float(d["energy"]), float(d["texture_scale"]))
		light.position = canvas.local_from_world(s["at"])
		light.visible = true
		light.enabled = true
		used += 1
	for j in range(used, _pool.size()):
		_pool[j].visible = false
		_pool[j].enabled = false
	_active_spells = used
