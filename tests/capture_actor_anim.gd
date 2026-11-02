extends SceneTree
## AD-065 developer capture (not a test: needs a display). Run:
##   xvfb-run -a /usr/local/bin/godot --path . --script res://tests/capture_actor_anim.gd -- /tmp/ad065_captures
## Writes one frame strip per actor per tag (scale 2) and one in-play shot per actor with the hitbox overlay.
const Art = preload("res://ui/pixel_art_renderer.gd")
var out_dir := "user://ad065_captures"

func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	if args.size() > 0:
		out_dir = args[0]
	DirAccess.make_dir_recursive_absolute(out_dir)
	root.size = Vector2i(1280, 720)
	call_deferred("_run")

func _save(img: Image, name: String) -> void:
	var err := img.save_png("%s/%s.png" % [out_dir, name])
	print("CAPTURE ", name, " ", "ok" if err == OK else "ERR %d" % err)

func _strips() -> void:
	var manifest: Dictionary = Art.actor_manifest()
	for kind in manifest:
		var tags: Dictionary = manifest[kind]["tags"]
		for tag in tags:
			var n := int(tags[tag]["frames"])
			var cells: Array = []
			var size := Vector2i(1, 1)
			for i in n:
				var fr: Dictionary = Art._actor_frame(kind, tag, i, false)
				if fr.is_empty():
					continue
				var src: Image = fr["tex"].get_image().get_region(Rect2i(fr["region"]))
				src.resize(src.get_width() * 2, src.get_height() * 2, Image.INTERPOLATE_NEAREST)
				cells.append(src)
				size = Vector2i(maxi(size.x, src.get_width()), maxi(size.y, src.get_height()))
			if cells.is_empty():
				continue
			var strip := Image.create(size.x * cells.size(), size.y, false, Image.FORMAT_RGBA8)
			for i in cells.size():
				strip.blit_rect(cells[i], Rect2i(Vector2i.ZERO, cells[i].get_size()), Vector2i(i * size.x, size.y - cells[i].get_height()))
			_save(strip, "strip_%s_%s" % [kind, tag])

func _shot(name: String) -> void:
	for i in 3:
		await process_frame
	await RenderingServer.frame_post_draw
	_save(root.get_texture().get_image(), name)

func _run() -> void:
	_strips()
	var control = load("res://scenes/run.tscn").instantiate()
	root.add_child(control)
	current_scene = control
	await process_frame
	var session = control.flow.session
	var canvas = control.get("canvas")
	if canvas == null:
		canvas = _find_canvas(control)
	canvas.show_debug = true
	var shown := {}
	var at := Vector2(900, 450)
	for kind in ["fallen_adept", "grave_hound", "undead_warden"]:
		var present := false
		for e in session.enemies:
			present = present or e.kind == kind
		if not present:
			if kind == "undead_warden":
				var boss_settings: Dictionary = session.data.get("boss", {}) if session.data.has("boss") else {}
				if boss_settings.is_empty():
					boss_settings = load_json("res://world/data/vertical_slice_v1.json")["boss"]
				for try in 12:
					if session.spawn_boss(boss_settings, Vector2(300 + 80 * try, 450)) != null:
						break
				continue
			for try in 12:
				at = Vector2(400 + 90 * (try % 6), 250 + 200 * (try / 6)) + Vector2(0, 40 * shown.size())
				if session.spawn_enemy(kind, at) != null:
					break
	for enemy in session.enemies.duplicate():
		if shown.has(enemy.kind):
			continue
		shown[enemy.kind] = true
		session.sim.actor.position = enemy.target.position + Vector2(-140, 0)
		for i in 20:
			await physics_frame
		await _shot("play_%s" % enemy.kind)
	quit(0)

func _find_canvas(node: Node):
	if node.get("show_debug") != null:
		return node
	for c in node.get_children():
		var f = _find_canvas(c)
		if f != null:
			return f
	return null

func load_json(path: String) -> Dictionary:
	return JSON.parse_string(FileAccess.get_file_as_string(path))
