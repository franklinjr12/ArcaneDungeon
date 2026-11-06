extends Node2D
## AD-149 actor hit flash: redraws flashing actors on top of the canvas through hit_flash.gdshader, which paints the
## sprite silhouette white; the entry strength is the modulate alpha. Render-only; entries come from combat_canvas.
const Art = preload("res://ui/pixel_art_renderer.gd")
const VfxData = preload("res://ui/vfx/vfx_data.gd")
const Lighting = preload("res://ui/lighting.gd")
const SHADER := preload("res://shaders/hit_flash.gdshader")
var _entries: Array = []

func _init() -> void:
	var mat := ShaderMaterial.new()
	mat.shader = SHADER
	mat.set_shader_parameter("flash_strength", 1.0)
	mat.set_shader_parameter("flash_color", Color(str(VfxData.hit_flash_cfg().get("color", "#ffffff"))))
	material = mat
	light_mask = Lighting.arena_mask()
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST

func entry_count() -> int:
	return _entries.size()

## Entries: {kind, at (canvas-local), tick, motion, anim, strength}. Zero-strength entries are dropped.
func set_entries(entries: Array) -> void:
	_entries.clear()
	for e in entries:
		if float(e.get("strength", 0.0)) > 0.0:
			_entries.append(e)
	visible = not _entries.is_empty()
	queue_redraw()

func _draw() -> void:
	for e in _entries:
		Art.entity(self, str(e["kind"]), e["at"], int(e["tick"]), e["motion"], false, false, false,
			Color(1, 1, 1, float(e["strength"])), e["anim"])
