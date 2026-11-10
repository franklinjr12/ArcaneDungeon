extends RefCounted
## AD-090: every visible Control stays inside the logical viewport and interactive Controls do not overlap,
## at each matrix window size and UI state. Enforced since AD-091 (REPORT_ONLY := false).
## AD-092: run states are checked release-like (show_dev_tools=false): no dev text, >=14 px text at 1280x720,
## no scroll container around the combat/reward/pause UI, and HUD slot numbering matches the loadout.
## Live resize 1280x720 -> 1920x1080 is covered by those two sizes; fullscreen on a 1920x1080 screen equals 1920x1080.
const REPORT_ONLY := false
const SIZES := [Vector2i(1280,720), Vector2i(1366,768), Vector2i(1600,900), Vector2i(1920,1080), Vector2i(2560,1440),
	Vector2i(3840,2160), Vector2i(1280,800), Vector2i(1920,1200), Vector2i(2560,1080), Vector2i(3440,1440), Vector2i(1024,768)]
const MENU_STATES := ["title","settings","settings_video","settings_controls","settings_access","compendium","compendium_reactions","compendium_enemies","compendium_artifacts","credits"]
const DEV_TEXTS := ["ARCANE DUNGEON / M4","Edit policy","Render FPS","Waves scheduled","telemetry","Toggle debug","Toggle edit policy"]
const RUN_STATES := ["combat","combat_resonance","reward","reward_resonant","loadout","workshop_editor","merchant","pause","summary","summary_win","sigil_desk"]

var issues := 0

## Godot stretch rules: logical viewport size the game sees for a given window size.
func logical_size(window: Vector2i) -> Vector2i:
	var base := Vector2(int(ProjectSettings.get_setting("display/window/size/viewport_width")),
		int(ProjectSettings.get_setting("display/window/size/viewport_height")))
	var mode := str(ProjectSettings.get_setting("display/window/stretch/mode", "disabled"))
	var aspect := str(ProjectSettings.get_setting("display/window/stretch/aspect", "keep"))
	if mode == "disabled":
		return window
	var win := Vector2(window)
	var result := base
	match aspect:
		"keep_width":
			result = Vector2(base.x, win.y / (win.x / base.x))
		"keep_height":
			result = Vector2(win.x / (win.y / base.y), base.y)
		"expand":
			var scale := minf(win.x / base.x, win.y / base.y)
			result = win / scale
	return Vector2i(roundi(result.x), roundi(result.y))

func run(t) -> void:
	var root := (Engine.get_main_loop() as SceneTree).root
	_display_settings(t)
	_arena_scale(t)
	_floating_text_overlap(t)
	for window in SIZES:
		var logical := logical_size(window)
		for state in MENU_STATES + RUN_STATES:
			_case(t, root, window, logical, state)
	print("AD-090 UI-BOUNDS REPORT total issues: %d (report_only=%s)" % [issues, REPORT_ONLY])
	if REPORT_ONLY:
		t.check(true, "AD-090 bounds report-only (%d issues)" % issues)

func _display_settings(t) -> void:
	const Settings = preload("res://game/core/settings.gd")
	var s := Settings.new()
	t.equal(s.window_mode, "windowed", "AD-091 default window_mode")
	t.equal(s.ui_scale, 1.0, "AD-091 default ui_scale")
	s.window_mode = "borderless"
	s.ui_scale = 1.3
	var cfg := ConfigFile.new()
	s.to_config(cfg)
	var back := Settings.new()
	back.from_config(cfg)
	t.equal(back.window_mode, "borderless", "AD-091 window_mode round trip")
	t.check(is_equal_approx(back.ui_scale, 1.3), "AD-091 ui_scale round trip")
	var bad := ConfigFile.new()
	bad.set_value("display", "window_mode", "bogus")
	bad.set_value("display", "ui_scale", 9.0)
	back.from_config(bad)
	t.equal(back.window_mode, "windowed", "AD-091 bogus mode falls back")
	t.check(is_equal_approx(back.ui_scale, 1.5), "AD-091 ui_scale clamps high")
	bad.set_value("display", "ui_scale", 0.1)
	back.from_config(bad)
	t.check(is_equal_approx(back.ui_scale, 0.9), "AD-091 ui_scale clamps low")
	bad.set_value("display", "ui_scale", "x")
	back.from_config(bad)
	t.equal(back.ui_scale, 1.0, "AD-091 non-number ui_scale falls back")

func _floating_text_overlap(t) -> void:
	const Art = preload("res://ui/pixel_art_renderer.gd")
	const Numbers = preload("res://ui/damage_numbers.gd")
	const Target = preload("res://combat/magic_target.gd")
	var target := Target.new(5,2,Vector2(400,300),100.0)
	var tracker := Numbers.new()
	tracker.update([target],0)
	for channel in ["essence.fire","essence.water","essence.lightning","essence.fire","essence.water","essence.lightning"]:
		target.receive_damage(3.0,channel,1,1.0)
	tracker.update([target],5)
	t.equal(tracker.popups.size(), 6, "AD-093 six simultaneous popups")
	var items: Array = []
	for popup in tracker.popups:
		var w := Art.damage_glyph_width(popup["symbol"],popup["text"])
		items.append({"anchor":Vector2(392,250)-Vector2(w/2.0,0),"size":Vector2(w,Numbers.LINE_HEIGHT),"group":popup["target_id"],"order":items.size()})
	items.append({"anchor":Vector2(376,250),"size":Vector2(56,12),"group":5,"order":items.size()})
	items.append({"anchor":Vector2(380,250),"size":Vector2(34,12),"group":"arc0","order":items.size()})
	var rects := Numbers.stack_layout(items)
	var clear := true
	for i in rects.size():
		for j in range(i+1,rects.size()):
			if rects[i].intersection(rects[j]).has_area():
				clear = false
	t.check(clear, "AD-093 floating text rects do not overlap (6 damage + status + ARC!)")

func _arena_scale(t) -> void:
	const Run = preload("res://ui/run_controller.gd")
	const Canvas = preload("res://ui/combat_canvas.gd")
	t.equal(Run.arena_texel(Vector2(950,690)), 2, "AD-091 texel 2 at 1280x720 arena area")
	t.equal(Run.arena_texel(Vector2(3500,2100)), 3, "AD-091 texel 3 at 3840x2160 arena area")
	for s: float in [1.0, 1.0672, 1.5, 2.0, 3.0]:
		var texel := Run.arena_texel(Vector2(900,600)*s*1.7)
		var zoom := float(texel)/(2.0*s)
		var phys := 2.0*s*zoom
		t.check(absf(phys-roundf(phys)) < 0.0001, "AD-091 art texel is whole physical pixels at scale %s" % s)
	var canvas := Canvas.new()
	canvas.scale = Vector2(1.5,1.5)
	canvas.size = Vector2(600,400)
	var p := Vector2(123.5,77.25)
	t.check(canvas.world_from_local(canvas.local_from_world(p)).is_equal_approx(p), "AD-091 world/local round trip on a scaled canvas")
	t.equal(canvas.view_size(), canvas.size, "AD-091 view_size is the world-space node size")
	canvas.free()

func _case(t, root: Node, window: Vector2i, logical: Vector2i, state: String) -> void:
	var viewport := SubViewport.new()
	viewport.size = logical
	viewport.disable_3d = true
	root.add_child(viewport)
	var scene: Node = load("res://scenes/main.tscn" if state in MENU_STATES else "res://scenes/run.tscn").instantiate()
	if state in RUN_STATES:
		scene.show_dev_tools = false # release-like run: no dev overlay
	viewport.add_child(scene)
	var ok: bool = scene.apply_debug_shot_state(state)
	t.check(ok, "AD-090 shot state %s applies at %dx%d" % [state, window.x, window.y])
	if ok:
		if state == "workshop_editor":
			_layout(viewport)
			scene._fit_test_canvas()
		_layout(viewport)
		_layout(viewport)
		if state == "workshop_editor":
			_check_editor_dummies(t, scene, "%dx%d" % [window.x, window.y], logical)
		_check_controls(t, viewport, "%dx%d" % [window.x, window.y], state, Rect2(Vector2.ZERO, Vector2(logical)))
		if state in RUN_STATES:
			_check_release_run(t, viewport, scene, window, state)
	viewport.queue_free()

## AD-093: the docked editor must not cover any live test-range dummy (labels included).
func _check_editor_dummies(t, scene: Node, size_label: String, logical: Vector2i) -> void:
	var range_sim = scene.flow.range_sim
	var panel: Rect2 = scene.editor_panel.get_global_rect()
	var view := Rect2(Vector2.ZERO, Vector2(logical))
	var checked := 0
	for target in range_sim.targets.all():
		if target.id == range_sim.actor.id:
			continue
		var r: float = target.radius + 8.0
		var rect: Rect2 = scene.test_canvas.get_global_transform() * Rect2(target.position - Vector2(r, r), Vector2(2.0*r, 2.0*r))
		if rect.size.y < 24.0:
			rect.size.y = 24.0
		checked += 1
		t.check(not rect.intersects(panel), "AD-093 editor covers dummy %s at %s: %s vs %s" % [target.id, size_label, rect, panel])
		t.check(view.encloses(rect), "AD-093 dummy %s outside viewport at %s: %s" % [target.id, size_label, rect])
	t.check(checked > 0, "AD-093 workshop has dummies to check at %s" % size_label)

func _layout(node: Node) -> void:
	if node is Container:
		node.notification(Container.NOTIFICATION_SORT_CHILDREN)
	for child in node.get_children():
		_layout(child)

func _controls(node: Node, out: Array) -> void:
	for child in node.get_children():
		if child is Control and child.is_visible_in_tree():
			out.append(child)
		_controls(child, out)

## Global rect clipped by every ScrollContainer ancestor; empty Rect2() when fully scrolled out of view.
func _visible_rect(c: Control) -> Rect2:
	var rect := c.get_global_rect()
	var p := c.get_parent()
	while p != null:
		if p is ScrollContainer:
			rect = rect.intersection(p.get_global_rect())
			if not rect.has_area():
				return Rect2()
		p = p.get_parent()
	return rect

func _interactive(c: Control) -> bool:
	if not (c is BaseButton or c is Range or c is LineEdit or c is TextEdit or c is ItemList):
		return false
	return c.focus_mode != Control.FOCUS_NONE or c.mouse_filter != Control.MOUSE_FILTER_IGNORE

func _report(t, size_label: String, state: String, kind: String, c: Control, rect: Rect2) -> void:
	issues += 1
	var message := "AD-090 UI-BOUNDS REPORT %s %s %s %s %s" % [size_label, state, kind, c.get_path(), rect]
	if REPORT_ONLY:
		print(message)
	else:
		t.check(false, message)

func _check_controls(t, root: Node, size_label: String, state: String, bounds: Rect2) -> void:
	var controls: Array = []
	_controls(root, controls)
	var interactive: Array = []
	for c in controls:
		var full: Rect2 = c.get_global_rect()
		if full.size.x <= 0.0 or full.size.y <= 0.0:
			continue
		var rect := _visible_rect(c)
		if rect.size == Vector2.ZERO:
			continue
		# Title parallax layers (par_*) overscan the viewport by design (AD-152); they are decorative and not interactive.
		if not bounds.encloses(rect) and not String(c.name).begins_with("par_"):
			_report(t, size_label, state, "outside", c, rect)
		if _interactive(c):
			interactive.append([c, rect])
	for i in interactive.size():
		for j in range(i + 1, interactive.size()):
			var a: Control = interactive[i][0]
			var b: Control = interactive[j][0]
			if a.is_ancestor_of(b) or b.is_ancestor_of(a):
				continue
			if (interactive[i][1] as Rect2).intersection(interactive[j][1]).has_area():
				_report(t, size_label, state, "overlap", a, interactive[i][1])

func _text_of(c: Control) -> String:
	if c is Label or c is Button:
		return c.text
	if c is RichTextLabel:
		return c.get_parsed_text()
	return ""

func _has_scroll_ancestor(c: Node) -> bool:
	var p := c.get_parent()
	while p != null:
		if p is ScrollContainer and p.is_visible_in_tree():
			return true
		p = p.get_parent()
	return false

## AD-092: release-like run UI checks (enforced).
func _check_release_run(t, viewport: Node, scene: Node, window: Vector2i, state: String) -> void:
	var tag := "%dx%d %s" % [window.x, window.y, state]
	var controls: Array = []
	_controls(viewport, controls)
	var dev_hits := 0
	var small_hits := 0
	for c in controls:
		var text := _text_of(c)
		if text == "":
			continue
		for needle in DEV_TEXTS:
			if text.findn(needle) >= 0:
				dev_hits += 1
				t.check(false, "AD-092 dev text '%s' visible at %s: %s" % [needle, tag, c.get_path()])
		if window == Vector2i(1280,720) and (c is Label or c is Button) and c.get_theme_font_size("font_size") < 14:
			small_hits += 1
			t.check(false, "AD-092 font size %d < 14 at %s: %s" % [c.get_theme_font_size("font_size"), tag, c.get_path()])
	t.check(dev_hits == 0, "AD-092 no dev text at %s" % tag)
	if window == Vector2i(1280,720):
		t.check(small_hits == 0, "AD-092 all visible text >= 14 px at %s" % tag)
	if state in ["combat","reward","merchant","pause"]:
		var guarded: Array = [scene.arena_canvas.slot_hud, scene.objective, scene.coins_label, scene.pause_button]
		if state == "reward":
			guarded.append(scene.reward_overlay)
		elif state == "merchant":
			guarded.append(scene.shop_overlay)
		for c in guarded:
			t.check(not _has_scroll_ancestor(c), "AD-092 %s not inside a ScrollContainer at %s" % [c.name, tag])
	if state == "combat":
		var hud = scene.arena_canvas.slot_hud
		var keys := ["LMB","RMB","Q","E"]
		for i in keys.size():
			var v: Dictionary = hud.slot_view(i)
			t.equal(v.get("key_label"), keys[i], "AD-092 HUD slot %d key at %s" % [i + 1, tag])
		var first: Dictionary = hud.slot_view(0)
		t.check(first.get("locked", false) and not first.get("empty", true), "AD-092 HUD slot 1 is locked Basic Bolt at %s" % tag)
		var buttons: Array = scene.loadout_slot_buttons
		for i in buttons.size():
			var want := "Slot 1: Basic Bolt" if i == 0 else "Slot %d" % (i + 1)
			t.check(buttons[i].text.begins_with(want), "AD-092 loadout button %d reads '%s' at %s" % [i + 1, buttons[i].text, tag])
