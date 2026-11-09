extends SceneTree
## AD-155 per-element capture (developer capture, not a test: needs a display). Run:
##   xvfb-run -a -s '-screen 0 1280x720x24' /usr/local/bin/godot --path . --script res://tests/capture_ad155.gd -- /tmp/ad155_shots [group]
## Writes <group>_<ruins|cistern>.png into the given directory (default /tmp/ad155_shots; keep it outside the repo).
## Groups: cold_force, beams, fields, status, reactions, mods_triggers, icons, artifacts, props, light_particles.
## Every sprite is drawn through ui/pixel_art_renderer.gd at in-game scale (art scale 2) over the stage's real floor; `light_particles`
## also renders a real lit run room (lighting high). Any legacy fallback ends the run with a non-zero exit.
const PixelArt = preload("res://ui/pixel_art_renderer.gd")
const Settings = preload("res://game/core/settings.gd")
const GROUPS := ["cold_force", "beams", "fields", "status", "reactions", "mods_triggers", "icons", "artifacts", "props", "light_particles"]
const FLOORS := {"ruins": 0, "cistern": 2}
const ELEMENTS := ["fire", "water", "lightning", "cold", "force"]
const VIEW := Vector2(1280, 720)
var out_dir := "/tmp/ad155_shots"
var board: Node2D
var gallery := Callable()
var failed := false
var keep: Array = []  # draw commands only hold RIDs: keep every loaded texture alive until the screenshot

class Board extends Node2D:
	var fn := Callable()
	var stage := 0
	func _draw() -> void:
		PixelArt.tile_floor(self, Rect2(Vector2.ZERO, VIEW), Vector2.ZERO, stage)
		fn.call(self)
		PixelArt.draw_actor_glows(self)

func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	if args.size() > 0:
		out_dir = args[0]
	DirAccess.make_dir_recursive_absolute(out_dir)
	root.size = Vector2i(1280, 720)
	call_deferred("_run")

func _keep(t: Texture2D) -> Texture2D:
	keep.append(t)
	return t

func _label(c: CanvasItem, text: String, at: Vector2) -> void:
	c.draw_string(ThemeDB.fallback_font, at, text, HORIZONTAL_ALIGNMENT_LEFT, -1, 12, Color(1, 1, 1, 0.9))

func _grid(i: int, cols: int, cell: Vector2, origin: Vector2 = Vector2(40, 50)) -> Vector2:
	return origin + Vector2(i % cols * cell.x, i / cols * cell.y)

func _g_cold_force(c: CanvasItem, tick: int) -> void:
	var evs := ["projectile", "impact", "burst", "orb"]
	for r in 2:
		for k in evs.size():
			var el: String = ["cold", "force"][r]
			var at := Vector2(160 + k * 280, 180 + r * 260)
			PixelArt.draw_fx(c, "%s.%s" % [evs[k], el], at, tick)
			_label(c, "%s.%s" % [evs[k], el], at + Vector2(-40, 100))

func _g_beams(c: CanvasItem, tick: int) -> void:
	var els := ["fire", "water", "lightning", "cold", "force", "neutral"]
	for i in els.size():
		var y := 90.0 + i * 100.0
		PixelArt.draw_form_visuals(c, [{"kind": "beam", "essence": "essence." + els[i], "from": Vector2(120, y), "to": Vector2(900, y), "age": tick}], Vector2.ZERO, tick)
		_label(c, "beam." + els[i], Vector2(940, y))

func _g_fields(c: CanvasItem, tick: int) -> void:
	for i in ELEMENTS.size():
		var at := Vector2(160 + i * 240, 300)
		PixelArt.draw_form_visuals(c, [{"kind": "field", "essence": "essence." + ELEMENTS[i], "position": at, "radius": 96.0, "age": tick}], Vector2.ZERO, tick)
		_label(c, "field." + ELEMENTS[i], at + Vector2(-30, 130))

func _g_status(c: CanvasItem, tick: int) -> void:
	var evs := ["status.chilled", "status.frozen", "status.brittle", "status.burning", "status.wet", "status.charged"]
	for i in evs.size():
		var at := Vector2(160 + i * 190, 320)
		PixelArt.entity(c, "bone_thrall", at, tick)
		PixelArt.draw_fx(c, evs[i], at, tick)
		_label(c, evs[i], at + Vector2(-40, 90))

func _g_reactions(c: CanvasItem, tick: int) -> void:
	var evs := ["reaction.shatter", "reaction.steam", "reaction.flash_freeze"]
	for i in evs.size():
		for k in 3:
			var at := Vector2(200 + i * 400, 130 + k * 190)
			PixelArt.draw_fx(c, evs[i], at, tick + k * 6)
		_label(c, evs[i], Vector2(160 + i * 400, 690))

func _g_mods_triggers(c: CanvasItem, tick: int) -> void:
	var evs := ["mod.chain", "mod.rapid", "trigger.on_hit", "trigger.on_kill", "trigger.on_expire", "trigger.timer"]
	for i in evs.size():
		var at := Vector2(160 + i * 190, 320)
		PixelArt.draw_fx(c, evs[i], at, tick)
		_label(c, evs[i], at + Vector2(-40, 90))

func _g_icons(c: CanvasItem, _tick: int) -> void:
	var skin = load("res://ui/skin_a.gd")
	var ids: Array = PixelArt.export_map()["rune_icons"].keys()
	for i in ids.size():
		var at := _grid(i, 11, Vector2(110, 130))
		var tex: Texture2D = skin.rune_icon(ids[i])
		c.draw_texture_rect(tex, Rect2(at, Vector2(64, 64)), false)
		c.draw_texture_rect(tex, Rect2(at + Vector2(0, 70), Vector2(16, 16)), false)
		_label(c, ids[i].get_slice(".", 1), at + Vector2(0, 100))
	var ui: Array = PixelArt.export_map()["ui_icons"].keys()
	for i in ui.size():
		var at := Vector2(40 + i * 110, 380)
		var tex2: Texture2D = skin.icon_or_mvp(ui[i])
		c.draw_texture_rect(tex2, Rect2(at, Vector2(64, 64)), false)
		_label(c, ui[i], at + Vector2(0, 80))
	var j: Dictionary = PixelArt.export_manifest()["ad_ico_merchant8"]
	var sheet := PixelArt.build_sprite_frames("ad_ico_merchant8")
	var n := 0
	for an in sheet.get_animation_names():
		for f in sheet.get_frame_count(an):
			var t := sheet.get_frame_texture(an, f)
			var at2 := Vector2(40 + n * 90, 520)
			c.draw_texture_rect(t, Rect2(at2, t.get_size() * 6), false)
			_label(c, "%s/%d" % [an, f], at2 + Vector2(0, 100))
			n += 1
	_label(c, "merchant8 frames: %d (tags %s)" % [n, str(j.get("tags", {}).keys())], Vector2(40, 680))

func _g_artifacts(c: CanvasItem, _tick: int) -> void:
	var ids: Array = JSON.parse_string(FileAccess.get_file_as_string(PixelArt.ARTIFACT_INDEX))["artifacts"].keys()
	for i in ids.size():
		var at := _grid(i, 6, Vector2(200, 300), Vector2(40, 40))
		c.draw_texture_rect(_keep(PixelArt.artifact_icon(ids[i], 16)), Rect2(at, Vector2(16, 16)), false)
		c.draw_texture_rect(_keep(PixelArt.artifact_icon(ids[i], 32)), Rect2(at + Vector2(40, 0), Vector2(32, 32)), false)
		c.draw_texture_rect(_keep(PixelArt.artifact_icon(ids[i], 32)), Rect2(at + Vector2(0, 50), Vector2(128, 128)), false)
		_label(c, ids[i], at + Vector2(0, 200))

func _g_props(c: CanvasItem, tick: int) -> void:
	var m := PixelArt.export_manifest()
	var stems: Array = []
	for s in m:
		if s.begins_with("ad_prp_"):
			stems.append(s)
	for i in stems.size():
		var stem: String = stems[i]
		var tags: Dictionary = m[stem]["tags"]
		var tag: String = "idle" if tags.has("idle") else tags.keys()[0]
		var fr := {"stem": stem, "tag": tag, "index": PixelArt.loop_index(tags[tag]["ms"], tick)}
		var at := _grid(i, 8, Vector2(155, 165), Vector2(60, 40))
		if not PixelArt._draw_env_prop_art(c, fr, Rect2(at, Vector2(64, 64))):
			print("PROP NOT DRAWN ", stem)
			failed = true
		_label(c, stem.trim_prefix("ad_prp_"), at + Vector2(-20, 80))

func _g_light_particles(c: CanvasItem, _tick: int) -> void:
	var dir := "res://art/export/vfx/"
	var cookies: Array = []
	var parts: Array = []
	for f in DirAccess.get_files_at(dir):
		if f.ends_with(".png") and f.begins_with("ad_fx_cookie_"):
			cookies.append(f)
		elif f.ends_with(".png") and f.begins_with("ad_fx_ptc_") and not f.contains("_mask") and not f.contains("_glow"):
			parts.append(f)
	cookies.sort()
	parts.sort()
	var mat := CanvasItemMaterial.new()
	mat.blend_mode = CanvasItemMaterial.BLEND_MODE_ADD
	for i in cookies.size():
		var at := _grid(i, 7, Vector2(175, 160), Vector2(40, 30))
		var t: Texture2D = _keep(load(dir + cookies[i]))
		c.material = mat
		c.draw_texture_rect(t, Rect2(at, Vector2(128, 128)), false)
		c.material = null
		_label(c, cookies[i].trim_prefix("ad_fx_cookie_").get_basename(), at + Vector2(0, 142))
	for i in parts.size():
		var at2 := _grid(i, 13, Vector2(95, 70), Vector2(40, 400))
		var t2: Texture2D = _keep(load(dir + parts[i]))
		c.draw_texture_rect(t2, Rect2(at2, t2.get_size() * 2.0), false)
		_label(c, parts[i].trim_prefix("ad_fx_ptc_").get_basename(), at2 + Vector2(0, 62))

func _shoot(path: String) -> void:
	for i in 3:
		if board != null and is_instance_valid(board):
			board.queue_redraw()  # textures first loaded inside _draw show blank until the next draw
		await process_frame
	await RenderingServer.frame_post_draw
	var err := root.get_texture().get_image().save_png(path)
	print("CAPTURE ", path, " ", "ok" if err == OK else "ERR %d" % err)
	if err != OK:
		failed = true

func _run() -> void:
	var args := OS.get_cmdline_user_args()
	var which: Array = GROUPS if args.size() < 2 else [args[1]]
	PixelArt.export_map()
	for g in which:
		for fname in FLOORS:
			PixelArt.fx_fallbacks.clear()
			board = Board.new()
			board.stage = FLOORS[fname]
			var cb := Callable(self, "_g_" + g)
			board.fn = func(c): cb.call(c, 12)
			root.add_child(board)
			board.queue_redraw()
			await _shoot("%s/%s_%s.png" % [out_dir, g, fname])
			if not PixelArt.fx_fallbacks.is_empty():
				print("LEGACY FALLBACK ", g, " ", PixelArt.fx_fallbacks)
				failed = true
			board.queue_free()
			await process_frame
	if which.has("light_particles"):
		for fname in FLOORS:
			await _lit_room(fname)
	quit(1 if failed else 0)

## A real run room (lighting high, the cookie from lighting_v1.json) with the particle layer running.
func _lit_room(fname: String) -> void:
	var control = load("res://scenes/run.tscn").instantiate()
	root.add_child(control)
	current_scene = control
	control.set_physics_process(false)
	control._stats_recorded = true
	await process_frame
	var flow = control.flow
	var found := -1
	for i in flow.rooms.size():
		if int(flow.rooms[i].get("stage", 0)) == (0 if fname == "ruins" else 1) and str(flow.rooms[i].get("type", "")) == "combat":
			found = i
			break
	if found < 0:
		print("MISSING ROOM ", fname)
		failed = true
		control.queue_free()
		return
	flow.run.sequence_index = found
	flow._enter_current()
	control._redraw_panel()
	control.arena_canvas.settings = Settings.new()
	for i in 90:
		flow.step({})
		control.arena_canvas.queue_redraw()
		await process_frame
	var shown := board
	board = null
	await _shoot("%s/light_particles_room_%s.png" % [out_dir, fname])
	board = shown
	control.queue_free()
	await process_frame
