extends SceneTree
## AD-088 telegraph screenshots per floor + greyscale (not a test: needs a display). Run:
##   xvfb-run -a godot --path . --script res://tests/capture_ad_telegraphs.gd -- docs/ui/telegraphs/after
const Art = preload("res://ui/pixel_art_renderer.gd")
const WORKSHOP_TILE := "res://art/export/til/ad_til_guild_workshop.png"
const WINDOW := 60
const CASES := [
	{"kind": "bone_thrall", "event": "telegraph.circle", "uniform": 120.0, "length": 0.0},
	{"kind": "fallen_adept", "event": "telegraph.line", "uniform": 0.0, "length": 220.0},
	{"kind": "undead_warden", "event": "telegraph.dash_lane", "uniform": 0.0, "length": 260.0},
]
var out_dir := "user://ad088"

class Board extends Node2D:
	var floor_name := "ruins"
	var tex: ImageTexture
	func _draw() -> void:
		var Art = load("res://ui/pixel_art_renderer.gd")
		var view := Rect2(0, 0, 1280, 720)
		if floor_name == "ruins":
			Art.use_art_export = true
			Art.tile_floor(self, view, Vector2.ZERO, 0)
		else:
			var img := Image.load_from_file(ProjectSettings.globalize_path("res://art/export/til/ad_til_guild_workshop.png"))
			tex = ImageTexture.create_from_image(img)  # keep a reference: a freed texture draws white
			for y in range(0, 720, 32):
				for x in range(0, 1280, 32):
					draw_texture_rect_region(tex, Rect2(x, y, 32, 32), Rect2(17, 0, 16, 16))
		var font := ThemeDB.fallback_font
		var has_window: bool = Art.has_method("telegraph_colors")
		var cases: Array = load("res://tests/capture_ad_telegraphs.gd").CASES
		for r in cases.size():
			var c: Dictionary = cases[r]
			for m in 2:
				var frac := 0.4 if m == 0 else 0.95
				var at := Vector2(240 + m * 640, 130 + r * 230)
				var age := int(WINDOW_F * frac)
				Art.entity(self, c["kind"], at, 0)
				if has_window:
					Art.draw_fx(self, c["event"], at, age, 0.0, c["length"], Color.WHITE, 0, c["uniform"], WINDOW_F)
				else:
					Art.draw_fx(self, c["event"], at, age, 0.0, c["length"], Color.WHITE, 0, c["uniform"])
				draw_string(font, at + Vector2(-100, 90), "%s %s windup %d%%" % [c["kind"], c["event"], int(frac * 100)],
					HORIZONTAL_ALIGNMENT_LEFT, -1, 14, Color.WHITE)
	const WINDOW_F := 60

func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	if args.size() > 0:
		out_dir = args[0]
	DirAccess.make_dir_recursive_absolute(out_dir)
	root.size = Vector2i(1280, 720)
	call_deferred("_run")

func _run() -> void:
	for floor_name in ["ruins", "workshop"]:
		var b := Board.new()
		b.floor_name = floor_name
		root.add_child(b)
		await process_frame
		await process_frame
		await RenderingServer.frame_post_draw
		var img: Image = root.get_texture().get_image()
		img.save_png("%s/%s.png" % [out_dir, floor_name])
		for y in img.get_height():
			for x in img.get_width():
				var c := img.get_pixel(x, y)
				var l := 0.299 * c.r + 0.587 * c.g + 0.114 * c.b
				img.set_pixel(x, y, Color(l, l, l, 1.0))
		img.save_png("%s/%s_grey.png" % [out_dir, floor_name])
		print("CAPTURE ", floor_name)
		root.remove_child(b)
		b.free()
		await process_frame
		await process_frame
	quit(0)
