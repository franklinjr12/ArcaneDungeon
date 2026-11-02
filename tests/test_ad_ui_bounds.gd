extends RefCounted
## AD-090: every visible Control stays inside the logical viewport and interactive Controls do not overlap,
## at each matrix window size and UI state. Report-only until AD U2 (flip REPORT_ONLY to false).
## Live resize 1280x720 -> 1920x1080 is covered by those two sizes; fullscreen on a 1920x1080 screen equals 1920x1080.
const REPORT_ONLY := true
const SIZES := [Vector2i(1280,720), Vector2i(1366,768), Vector2i(1600,900), Vector2i(1920,1080), Vector2i(2560,1440),
	Vector2i(3840,2160), Vector2i(1280,800), Vector2i(1920,1200), Vector2i(2560,1080), Vector2i(3440,1440), Vector2i(1024,768)]
const MENU_STATES := ["title","settings"]
const RUN_STATES := ["combat","reward","workshop_editor","merchant","pause","summary"]

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
	for window in SIZES:
		var logical := logical_size(window)
		for state in MENU_STATES + RUN_STATES:
			_case(t, root, window, logical, state)
	print("AD-090 UI-BOUNDS REPORT total issues: %d (report_only=%s)" % [issues, REPORT_ONLY])
	if REPORT_ONLY:
		t.check(true, "AD-090 bounds report-only (%d issues)" % issues)

func _case(t, root: Node, window: Vector2i, logical: Vector2i, state: String) -> void:
	var viewport := SubViewport.new()
	viewport.size = logical
	viewport.disable_3d = true
	root.add_child(viewport)
	var scene: Node = load("res://scenes/main.tscn" if state in MENU_STATES else "res://scenes/run.tscn").instantiate()
	viewport.add_child(scene)
	var ok: bool = scene.apply_debug_shot_state(state)
	t.check(ok, "AD-090 shot state %s applies at %dx%d" % [state, window.x, window.y])
	if ok:
		_layout(viewport)
		_layout(viewport)
		_check_controls(t, viewport, "%dx%d" % [window.x, window.y], state, Rect2(Vector2.ZERO, Vector2(logical)))
	viewport.queue_free()

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
		if not bounds.encloses(rect):
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
