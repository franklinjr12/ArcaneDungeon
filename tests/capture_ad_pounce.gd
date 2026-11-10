extends SceneTree
## AD-197 Ghoul stalker / Riptide leaper telegraph + Compendium screenshots (not a test: needs a display). Run:
##   xvfb-run -a /usr/local/bin/godot --path . --resolution 1280x720 --script res://tests/capture_ad_pounce.gd -- docs/ui/pounce
const Session = preload("res://combat/combat_session.gd")
const Canvas = preload("res://ui/combat_canvas.gd")
const Screen = preload("res://ui/compendium_screen.gd")
var out_dir := "user://ad197"

func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	if args.size() > 0:
		out_dir = args[0]
	if out_dir.begins_with("res://"):
		out_dir = ProjectSettings.globalize_path(out_dir)
	DirAccess.make_dir_recursive_absolute(out_dir)
	root.size = Vector2i(1280, 720)
	call_deferred("_run")

func _snap(name: String) -> void:
	await process_frame
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png("%s/%s.png" % [out_dir, name])
	print("CAPTURE ", name)

func _until(s, enemy, state: String, ticks: int) -> bool:
	for i in 600:
		if enemy.state == state and enemy.state_tick >= ticks:
			return true
		s.step()
	return false

func _combat(kind: String, offset: Vector2, prefix: String, later: String) -> void:
	var s = Session.new(197, "empty", 0)
	var enemy = s.spawn_enemy(kind, s.sim.actor.position + offset)
	var canvas := Canvas.new()
	canvas.size = Vector2(1280, 720)
	canvas.environment_id = 0
	canvas.show_debug = false
	root.add_child(canvas)
	await process_frame
	var ok: bool = _until(s, enemy, "windup", 30)
	canvas.session = s
	canvas.queue_redraw()
	await _snap("%s_windup" % prefix)
	ok = ok and _until(s, enemy, "recover", 1)
	canvas.session = s
	canvas.queue_redraw()
	await _snap(later)
	if not ok:
		push_error("%s never reached windup/recover" % kind)
	canvas.queue_free()

func _compendium(id: String, name: String) -> void:
	var screen = Screen.new()
	root.add_child(screen)
	screen.select_tab("enemies")
	screen._meta = screen._meta.duplicate(true)
	screen._meta["discovered"]["enemies"] = screen._catalogs["enemies"].duplicate()
	screen._fill_page("enemies")
	var idx: int = screen.entries("enemies").find(id)
	if idx < 0:
		push_error("%s not on first Compendium page" % id)
		idx = 0
	screen._select("enemies", idx)
	await _snap(name)
	screen.queue_free()
	await process_frame

func _run() -> void:
	await _combat("ghoul_stalker", Vector2(110, 0), "ghoul", "ghoul_recovery")
	await _combat("riptide_leaper", Vector2(220, 0), "leaper", "leaper_landed")
	await _compendium("ghoul_stalker", "compendium_ghoul")
	await _compendium("riptide_leaper", "compendium_leaper")
	quit(0)
