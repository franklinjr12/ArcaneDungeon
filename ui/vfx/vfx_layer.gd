extends Node2D
## AD-149 render-only additive VFX: pooled particles plus *_glow sprites. Reads the session, never writes it.
## The pool only advances when the sim tick changes, so paused or redrawn frames never move particles.
const Data = preload("res://ui/vfx/vfx_data.gd")
const Pool = preload("res://ui/vfx/particle_pool.gd")
const Emitters = preload("res://ui/vfx/vfx_emitters.gd")
const ReduceMotion = preload("res://ui/reduce_motion.gd")
const Lighting = preload("res://ui/lighting.gd")
const Settings = preload("res://game/core/settings.gd")
const MODE_HIGH := "high"
## Upper bound on pool steps for one sync, so a large tick jump cannot stall a frame.
const MAX_CATCH_UP_STEPS := 8
var _pool: Pool
var _canvas = null
var _glows: Array = []
var _cap := 0
var _last_tick := -1
var _session_id := 0

func setup(canvas) -> void:
	_canvas = canvas
	var mat := CanvasItemMaterial.new()
	mat.blend_mode = CanvasItemMaterial.BLEND_MODE_ADD
	material = mat
	light_mask = Lighting.arena_mask()
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	_pool = Pool.new(Data.particle_cap(MODE_HIGH))

func active_count() -> int:
	return _pool.active_count()

func capacity() -> int:
	return _pool.capacity()

func glow_count() -> int:
	return _glows.size()

func hide_all() -> void:
	_pool.clear()
	_glows.clear()
	_last_tick = -1
	_session_id = 0
	visible = false

func sync(canvas, session, settings, fx_list: Array, tick: int) -> void:
	_canvas = canvas
	visible = true
	var mode := str(settings.lighting) if settings != null and str(settings.lighting) in Settings.LIGHTING_MODES else MODE_HIGH
	_cap = mini(Data.particle_cap(mode), _pool.capacity())
	var sid: int = session.get_instance_id()
	if sid != _session_id or tick < _last_tick:
		_pool.clear()
		_last_tick = -1
	_session_id = sid
	var reduced := ReduceMotion.flashes_reduced(settings, session)
	var params := ReduceMotion.vfx_params(reduced)
	if _cap <= 0:
		_pool.clear()
		_glows.clear()
		_last_tick = tick
		queue_redraw()
		return
	_glows = Emitters.glow_sources(session, params)
	if tick != _last_tick:
		var steps := 1 if _last_tick < 0 else clampi(tick - _last_tick, 1, MAX_CATCH_UP_STEPS)
		for i in steps:
			_pool.step()
		_last_tick = tick
		_emit(session, settings, fx_list, tick, params)
	queue_redraw()

func _emit(session, settings, fx_list: Array, tick: int, params: Dictionary) -> void:
	var requests: Array = Emitters.trail_requests(session, tick, params)
	requests.append_array(Emitters.impact_requests(fx_list, tick, params))
	if not ReduceMotion.particle_jitter_enabled(settings):
		for r in requests:
			r["vel"] = Vector2.ZERO
	requests.append_array(Emitters.status_requests(session, tick, params))
	var budget := mini(Data.spawn_cap(_mode_of(settings)), requests.size())
	for i in budget:
		if _pool.active_count() >= _cap:
			break
		var r: Dictionary = requests[i]
		_pool.emit(r["at"], r["vel"], r["life"], r["size"], r["color"], r["color_end"])

func _mode_of(settings) -> String:
	if settings != null and str(settings.lighting) in Settings.LIGHTING_MODES:
		return str(settings.lighting)
	return MODE_HIGH

func _draw() -> void:
	if _canvas == null or _canvas.session == null:
		return
	var offset: Vector2 = _canvas.camera_offset()
	for g in _glows:
		var tex := Data.texture(str(g["texture"]), "glow")
		var r := float(g["radius"])
		draw_texture_rect(tex, Rect2(g["at"] - offset - Vector2(r, r), Vector2(r, r) * 2.0), false, g["color"])
	var tex_p := Data.texture(str(Data.load_data().get("particle_texture", "")), "particle")
	for i in _pool.capacity():
		if not _pool.is_live(i):
			continue
		var s := _pool.size_of(i)
		draw_texture_rect(tex_p, Rect2(_pool.position_of(i) - offset - Vector2(s, s), Vector2(s, s) * 2.0), false, _pool.color_of(i))
