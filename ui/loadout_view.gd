extends Control
## AD-147: read-only loadout view between rooms.
## Shows the 4 spell slots and held artifacts. No edit controls; purely visual (never touches the sim).
signal close_requested

var _box: VBoxContainer

func _init() -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP
	visible = false
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var dim := ColorRect.new()
	dim.color = Color(0, 0, 0, 0.6)
	dim.mouse_filter = Control.MOUSE_FILTER_IGNORE
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(dim)
	var center := CenterContainer.new()
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(center)
	var panel := PanelContainer.new()
	panel.name = "LoadoutViewPanel"
	center.add_child(panel)
	_box = VBoxContainer.new()
	_box.custom_minimum_size = Vector2(520, 0)
	_box.add_theme_constant_override("separation", 6)
	panel.add_child(_box)

func show_for(flow) -> void:
	for child in _box.get_children():
		_box.remove_child(child)
		child.queue_free()
	_label(tr("loadout_view.title"), 20)
	var loadout = flow.session.sim.loadout
	for i in 4:
		var row := VBoxContainer.new()
		row.name = "LoadoutSlot%d" % i
		_box.add_child(row)
		var preview: Dictionary = loadout.preview(i)
		var formula: Dictionary = loadout.slots[i]["formula"]
		var title := tr("loadout_view.slot") % [i + 1, tr("run.loadout.empty") if preview.is_empty() else str(formula.get("display_name", ""))]
		if loadout.is_locked(i):
			title += tr("loadout_view.locked")
		_label(title, 16, row)
		if preview.is_empty():
			continue
		_label(", ".join(_rune_ids(formula).map(_rune_label)), 14, row)
		var seconds: float = float(preview["cooldown"]) / float(Engine.physics_ticks_per_second)
		_label(tr("loadout_view.cost") % [int(preview["mana"]), seconds], 14, row)
	_label(tr("loadout_view.artifacts"), 16)
	if flow.run.artifacts.is_empty():
		_label(tr("loadout_view.no_artifacts"), 14)
	for id in flow.run.artifacts:
		_label(tr("artifact." + str(id) + ".name") + " — " + tr("artifact." + str(id) + ".desc"), 14)
	_label(tr("loadout_view.read_only"), 14)
	var close := Button.new()
	close.name = "LoadoutCloseButton"
	close.text = tr("loadout_view.close")
	close.focus_mode = Control.FOCUS_NONE # Space is dash
	close.pressed.connect(func(): close_requested.emit())
	_box.add_child(close)
	visible = true

func _label(text: String, font_size: int, parent: Node = null) -> Label:
	var l := Label.new()
	l.text = text
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.add_theme_font_size_override("font_size", font_size)
	(parent if parent != null else _box).add_child(l)
	return l

func _rune_ids(formula: Dictionary) -> Array:
	var root: Dictionary = formula.get("root", {})
	var ids: Array = [root.get("essence_id", ""), root.get("manifestation_id", "")]
	ids.append_array(root.get("modifier_ids", []))
	if formula.has("on_hit"):
		var on_hit: Dictionary = formula["on_hit"]
		var payload: Dictionary = on_hit.get("payload", {})
		ids.append_array([on_hit.get("trigger_id", ""), payload.get("essence_id", ""), payload.get("manifestation_id", "")])
	return ids.filter(func(id): return str(id) != "")

func _rune_label(id) -> String:
	var key := "rune." + str(id) + ".name"
	var text := tr(key)
	return str(id) if text == key else text
