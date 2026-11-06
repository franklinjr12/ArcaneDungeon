extends RefCounted
## AD-153: skin A spell editor (ad_ui_screen_editor_layout.json). Builds the editor's controls into the docked panel owned by
## run_controller.gd; every action still goes through the SpellEditor (magic/editor/spell_editor.gd), this file only draws.
## Deviation from the mock (a 608x332 full-panel modal at x2 would hide the test range, and the bounds test forbids that):
## the mock's left column (spells, chain, stats) and right column (palette, rune tooltip) are stacked into one x2 column that
## scrolls, working parts first (chain, validation, palette, tooltip) and the spell-slot overview last; the Cancel/Undo/Reset/Apply
## row is fixed under the scroll area.
const SkinA = preload("res://ui/skin_a.gd")
const LAYOUT := "editor"
const SC := 2.0 # canvas px -> screen px (the in-run UI is authored for 640x360 shown at 1280x720)
const WIDTH := 296.0 # canvas px: the right column of the mock, which is the widest
const LEFT_DX := -18.0 # left column x (28 in the mock) -> centred in WIDTH
const RIGHT_DX := -316.0
const COLUMNS := 9
const CHAIN_COLUMNS := 6
const VALID_COLOR := Color8(150, 210, 90)
const INVALID_COLOR := Color8(235, 120, 95)
const ROLES := {"essence": "editor.role.essence", "form": "editor.role.form", "mod": "editor.role.mod", "trigger": "editor.role.trigger"}

var tab := "all"
var preview: Label
var apply_button: Button
var undo_button: Button
var reset_button: Button
var cancel_button: Button
var rune_buttons: Dictionary = {} # rune id -> Button
var tab_buttons: Dictionary = {} # tab id -> Button
var _widgets: Dictionary = {}
var _e
var _hooks: Dictionary = {}
var _director
var _tip_slot: TextureRect
var _tip_name: Label
var _tip_cat: Label
var _tip_desc: Label
var _tip_ids: Dictionary = {} # rune id -> {name, category, description, locked}
var _first_rune := ""

## content: the scrolling VBox; actions: the fixed button row. hooks: rebuild, apply, cancel (Callables), loadout (live loadout).
func build(content: VBoxContainer, actions: HBoxContainer, e, hooks: Dictionary, director) -> void:
	_e = e
	_hooks = hooks
	_director = director
	_widgets = SkinA.widgets_by_id(LAYOUT)
	rune_buttons.clear()
	tab_buttons.clear()
	_tip_ids.clear()
	_first_rune = ""
	var verdict: Dictionary = e.validate()
	_title(content)
	_chain(content)
	_stats(content, verdict)
	_palette(content)
	_tooltip(content)
	_spell_rows(content, verdict)
	_actions(actions, verdict)

# --- drawing primitives -------------------------------------------------------------------------------------------------

func _w(id: String) -> Dictionary:
	return _widgets.get(id, {})

func _section(parent: Control, height: float) -> Control:
	var c := Control.new()
	c.custom_minimum_size = Vector2(WIDTH * SC, height * SC)
	c.mouse_filter = Control.MOUSE_FILTER_IGNORE
	parent.add_child(c)
	return c

func _place(c: Control, x: float, y: float, w: float, h: float) -> void:
	c.position = Vector2(x, y) * SC
	c.size = Vector2(w, h) * SC

func _box(sec: Control, sprite: String, x: float, y: float, w: float, h: float) -> Panel:
	var p := Panel.new()
	p.add_theme_stylebox_override("panel", SkinA.stylebox(sprite))
	p.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_place(p, x, y, w, h)
	sec.add_child(p)
	return p

func _pic(sec: Control, tex: Texture2D, x: float, y: float, w: float, h: float) -> TextureRect:
	var r := TextureRect.new()
	r.texture = tex
	r.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	r.stretch_mode = TextureRect.STRETCH_SCALE
	r.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	r.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_place(r, x, y, w, h)
	sec.add_child(r)
	return r

func _txt(sec: Control, value: String, x: float, y: float, w: float, state: String = "normal", align: int = HORIZONTAL_ALIGNMENT_LEFT, lines: int = 1) -> Label:
	var l := Label.new()
	l.text = value
	l.horizontal_alignment = align
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART if lines > 1 else TextServer.AUTOWRAP_OFF
	l.max_lines_visible = lines
	l.clip_text = true
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	l.add_theme_font_size_override("font_size", int(7 * SC))
	l.add_theme_color_override("font_color", SkinA.label_color(state))
	_place(l, x, y, w, 8.0 * lines + (2.0 if lines > 1 else 0.0))
	sec.add_child(l)
	return l

func _header(sec: Control, x: float, y: float, w: float, value: String) -> void:
	_box(sec, "ad_ui_header_small", x, y, w, 12)
	_txt(sec, value.to_upper(), x, y + 3.0, w, "selected", HORIZONTAL_ALIGNMENT_CENTER)

func _skin_button(b: Button, normal: String, hover: String, pressed: String, disabled: String) -> void:
	b.add_theme_stylebox_override("normal", SkinA.stylebox(normal, 0))
	b.add_theme_stylebox_override("hover", SkinA.stylebox(hover, 0))
	b.add_theme_stylebox_override("pressed", SkinA.stylebox(pressed, 0))
	b.add_theme_stylebox_override("hover_pressed", SkinA.stylebox(pressed, 0))
	b.add_theme_stylebox_override("disabled", SkinA.stylebox(disabled, 0))
	b.add_theme_stylebox_override("focus", SkinA.stylebox(hover, 0))

# --- sections -----------------------------------------------------------------------------------------------------------

func _title(content: VBoxContainer) -> void:
	var sec := _section(content, 18)
	var head := _w("title_header")
	_box(sec, "ad_ui_header", (WIDTH - head["w"]) * 0.5, 0, head["w"], head["h"])
	_txt(sec, (tr("run.editor.title") % (_e.slot + 2)).to_upper(), 0, 5, WIDTH, "selected", HORIZONTAL_ALIGNMENT_CENTER)
	if not _e.guided_runes.is_empty():
		var hint := _section(content, 10)
		_txt(hint, (tr("run.desk.guided") % _rune_name(_e.guided_next())).to_upper(), 0, 0, WIDTH, "selected", HORIZONTAL_ALIGNMENT_CENTER)

func _spell_rows(content: VBoxContainer, verdict: Dictionary) -> void:
	var top: float = _w("hdr_spells")["y"]
	var sec := _section(content, 149)
	var dx := LEFT_DX
	var dy := -top
	_header(sec, _w("hdr_spells")["x"] + dx, 0, _w("hdr_spells")["w"], tr("editor.spell_slots"))
	var loadout = _hooks.get("loadout")
	for i in 4:
		var n := i + 1
		var row: Dictionary = _w("spell_row_%d" % n)
		var ox: float = float(row["x"]) + dx
		var oy: float = float(row["y"]) + dy
		var editing: bool = i == _e.slot + 1
		_box(sec, "ad_ui_panel_inset", ox, oy, row["w"], row["h"])
		var formula: Dictionary = {}
		var preview_data: Dictionary = {}
		if editing:
			formula = _e.draft
		elif loadout != null:
			formula = loadout.slots[i]["formula"]
			preview_data = loadout.preview(i)
		var empty: bool = formula.is_empty()
		var slot_w: Dictionary = _w("spell_slot_%d" % n)
		var sprite := "ad_ui_slot24_empty" if empty else ("ad_ui_slot24_selected" if editing else "ad_ui_slot24_ready")
		_pic(sec, SkinA.region(sprite), float(slot_w["x"]) + dx, float(slot_w["y"]) + dy, 24, 24)
		var key := _w("spell_key_%d" % n)
		_txt(sec, SkinA.slot_key(i), float(key["x"]) + dx, float(key["y"]) + dy, 28, "hover")
		var name_x: float = float(_w("spell_name_%d" % n)["x"]) + dx
		if empty:
			_txt(sec, tr("run.loadout.empty").to_upper(), name_x, float(key["y"]) + dy, 120, "disabled")
			continue
		var ids := SkinA.formula_rune_ids(formula)
		var ir: Array = slot_w["icon_rect"]
		_pic(sec, SkinA.rune_icon(str(ids[0])), float(ir[0]) + dx, float(ir[1]) + dy, 16, 16)
		var title := str(formula.get("display_name", "")).to_upper()
		_txt(sec, title, name_x, float(key["y"]) + dy, 140, "normal")
		var mana := int(verdict["mana"]) if editing and verdict["ok"] else int(preview_data.get("mana", 0))
		if editing or not preview_data.is_empty():
			var mp := _txt(sec, (tr("loadout_view.mp") % mana).to_upper(), ox + float(row["w"]) - 48.0, float(key["y"]) + dy, 40, "normal", HORIZONTAL_ALIGNMENT_RIGHT)
			mp.add_theme_color_override("font_color", SkinA.mana_color())
		var runes_w := _w("spell_%d_runes" % n)
		var rx: float = float(runes_w["x"]) + dx
		var ry: float = float(runes_w["y"]) + dy
		for k in ids.size():
			_pic(sec, SkinA.rune_icon(str(ids[k])), rx + 20.0 * k, ry, 16, 16)
			if k < ids.size() - 1:
				_txt(sec, ">", rx + 20.0 * k + 15.0, ry + 5.0, 6, "disabled", HORIZONTAL_ALIGNMENT_CENTER)

func _chain(content: VBoxContainer) -> void:
	var ids := SkinA.formula_rune_ids(_e.draft)
	var rows := maxi(1, ceili(float(maxi(ids.size() + 1, CHAIN_COLUMNS)) / CHAIN_COLUMNS))
	var sec := _section(content, 22.0 + 36.0 * rows)
	var ox: float = LEFT_DX
	var key := SkinA.slot_key(_e.slot + 1)
	_header(sec, 28.0 + ox, 0, 276, (tr("editor.chain_title") % [_e.slot + 2, key]))
	var after_trigger := false
	for k in rows * CHAIN_COLUMNS:
		var cx: float = 32.0 + ox + 44.0 * (k % CHAIN_COLUMNS)
		var cy: float = 18.0 + 36.0 * (k / CHAIN_COLUMNS)
		var filled: bool = k < ids.size()
		_pic(sec, SkinA.region("ad_ui_slot24_ready" if filled else "ad_ui_slot24_empty"), cx, cy, 24, 24)
		if not filled:
			continue
		var id := str(ids[k])
		_pic(sec, SkinA.rune_icon(id), cx + 4.0, cy + 4.0, 16, 16)
		var kind := id.get_slice(".", 0)
		if kind == "trigger":
			after_trigger = true
		var role := tr("editor.role.payload") if after_trigger and kind != "trigger" else tr(ROLES.get(kind, "editor.role.essence"))
		_txt(sec, role.to_upper(), cx - 6.0, cy + 27.0, 36, "disabled", HORIZONTAL_ALIGNMENT_CENTER)
		if kind in ["mod", "trigger"]:
			var remove := Button.new() # click or right click removes a modifier / the trigger, like clicking it again in the palette
			remove.flat = true
			remove.focus_mode = Control.FOCUS_NONE
			remove.button_mask = MOUSE_BUTTON_MASK_LEFT | MOUSE_BUTTON_MASK_RIGHT
			remove.tooltip_text = tr("editor.remove_tip")
			for state in ["normal", "hover", "pressed", "focus", "disabled"]:
				remove.add_theme_stylebox_override(state, StyleBoxEmpty.new())
			remove.pressed.connect(_remove_rune.bind(id))
			_place(remove, cx, cy, 24, 24)
			sec.add_child(remove)
		if k < ids.size() - 1 and k % CHAIN_COLUMNS < CHAIN_COLUMNS - 1:
			_txt(sec, ">", cx + 27.0, cy + 8.0, 6, "disabled", HORIZONTAL_ALIGNMENT_CENTER)
	if _e.draft.has("on_hit"):
		var line := _section(content, 24)
		_txt(line, tr("run.editor.child_essence").to_upper(), 28.0 + LEFT_DX + 4.0, 7, 130, "normal")
		var option := _option()
		_place(option, 28.0 + LEFT_DX + 140.0, 0, 130, 24)
		line.add_child(option)

func _remove_rune(id: String) -> void:
	if id.begins_with("mod."):
		_e.toggle_modifier(id)
	else:
		_e.set_trigger(false)
	_hooks["rebuild"].call()

func _option() -> OptionButton:
	var option := OptionButton.new()
	option.add_theme_font_size_override("font_size", int(7 * SC))
	var list: Array = _e.available("essence")
	var selection := str(_e.draft["on_hit"]["payload"]["essence_id"])
	var current := -1
	for i in list.size():
		var item: Dictionary = list[i]
		option.add_item(_rune_name(str(item["id"])) + (tr("run.suffix.locked_lower") if item["locked"] else ""))
		option.set_item_metadata(i, str(item["id"]))
		option.set_item_icon(i, SkinA.rune_icon(str(item["id"])))
		option.set_item_disabled(i, bool(item["locked"]))
		if str(item["id"]) == selection:
			current = i
	if current >= 0:
		option.select(current)
	option.item_selected.connect(func(idx):
		_e.change_payload_essence(str(option.get_item_metadata(idx)))
		_hooks["rebuild"].call())
	return option

func _stats(content: VBoxContainer, verdict: Dictionary) -> void:
	var panel := PanelContainer.new()
	panel.name = "EditorStats"
	panel.add_theme_stylebox_override("panel", SkinA.stylebox("ad_ui_panel_inset", 8))
	panel.custom_minimum_size = Vector2(276.0 * SC, 40.0 * SC)
	panel.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	content.add_child(panel)
	preview = Label.new()
	preview.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	preview.add_theme_font_size_override("font_size", int(7 * SC))
	preview.mouse_filter = Control.MOUSE_FILTER_IGNORE
	panel.add_child(preview)
	if verdict["ok"]:
		preview.text = tr("run.editor.valid") % [verdict["mana"], verdict["cooldown"], verdict["complexity"], verdict["complexity_cap"]] + "\n" + str(verdict["summary"])
		preview.add_theme_color_override("font_color", VALID_COLOR)
		return
	preview.text = tr("run.editor.invalid") + "\n"
	preview.add_theme_color_override("font_color", INVALID_COLOR)
	for issue in verdict["issues"]:
		var reason := tr(str(issue["reason_key"]))
		var args: Array = issue["reason_args"]
		preview.text += (reason % args if not args.is_empty() else reason) + "\n"

func _palette(content: VBoxContainer) -> void:
	var entries: Array = _e.palette()
	var holder := VBoxContainer.new()
	holder.name = "RunePalette"
	holder.add_theme_constant_override("separation", 0)
	holder.mouse_filter = Control.MOUSE_FILTER_IGNORE
	content.add_child(holder)
	var tabs := _section(holder, 16)
	var tab_ids: Array = ["all"]
	for entry in entries:
		tab_ids.append(str(entry["id"]))
	if tab not in tab_ids:
		tab = "all"
	for k in tab_ids.size():
		var id: String = tab_ids[k]
		var title := tr("editor.tab." + id)
		if title == "editor.tab." + id:
			title = id
		var b := Button.new()
		b.name = "PaletteTab_" + id
		b.text = title.to_upper()
		b.clip_text = true
		b.add_theme_font_size_override("font_size", int(7 * SC))
		_skin_button(b, "ad_ui_tab_active" if id == tab else "ad_ui_tab_inactive", "ad_ui_tab_hover", "ad_ui_tab_active", "ad_ui_tab_disabled")
		if _director != null:
			_director.bind_button(b, "ui.confirm")
		b.pressed.connect(_select_tab.bind(id))
		_place(b, 59.0 * k, 0, 58, 16)
		tabs.add_child(b)
		tab_buttons[id] = b
	var shown: Array = []
	for entry in entries:
		if tab == "all" or tab == str(entry["id"]):
			for rune in entry["runes"]:
				shown.append({"rune": rune, "kind": str(entry["id"]), "category": str(entry["label"])})
	var rows := maxi(1, ceili(float(shown.size()) / COLUMNS))
	var grid := _section(holder, 8.0 + 28.0 * rows)
	_box(grid, "ad_ui_panel_inset", 0, 0, WIDTH, 8.0 + 28.0 * rows)
	var root: Dictionary = _e.draft["root"]
	for k in shown.size():
		_rune_cell(grid, shown[k], 8.0 + 28.0 * (k % COLUMNS), 6.0 + 28.0 * (k / COLUMNS), root)

func _select_tab(id: String) -> void:
	tab = id
	_hooks["rebuild"].call()

func _rune_cell(grid: Control, item: Dictionary, x: float, y: float, root: Dictionary) -> void:
	var rune: Dictionary = item["rune"]
	var kind: String = item["kind"]
	var id := str(rune["id"])
	var locked: bool = bool(rune["locked"])
	var attach: Dictionary = _e.can_attach(id) if kind in ["modifier", "trigger"] else {"ok": true, "reason_key": ""}
	var active := false
	match kind:
		"essence": active = str(root["essence_id"]) == id
		"form": active = str(root["manifestation_id"]) == id
		"modifier": active = id in root["modifier_ids"]
		"trigger": active = _e.draft.has("on_hit") and str(_e.draft["on_hit"]["trigger_id"]) == id
	var b := Button.new()
	b.name = "Rune_" + id.replace(".", "_")
	b.toggle_mode = true
	b.button_pressed = active
	b.focus_mode = Control.FOCUS_ALL
	b.set_meta("rune_id", id)
	b.disabled = locked or not bool(attach["ok"])
	_skin_button(b, "ad_ui_slot24_selected" if active else "ad_ui_slot24_ready", "ad_ui_slot24_hover", "ad_ui_slot24_selected", "ad_ui_slot24_disabled")
	var description := tr("rune." + id + ".desc")
	if description == "rune." + id + ".desc":
		description = str(rune["description"])
	if locked:
		b.tooltip_text = tr("editor.locked_tip")
	elif not bool(attach["ok"]):
		b.tooltip_text = tr(str(attach["reason_key"]))
	else:
		b.tooltip_text = description
	if _director != null:
		_director.bind_button(b, "ui.confirm")
	_place(b, x, y, 24, 24)
	grid.add_child(b)
	_pic(b, SkinA.icon("undiscovered") if locked else SkinA.rune_icon(id), 4, 4, 16, 16)
	if not _e.guided_runes.is_empty() and id == _e.guided_next():
		b.modulate = Color("#efbc65")
	if _first_rune == "":
		_first_rune = id
	_tip_ids[id] = {"name": _rune_name(id), "category": item["category"], "description": description if not locked else tr("editor.locked_tip"), "locked": locked}
	rune_buttons[id] = b
	b.mouse_entered.connect(_show_tip.bind(id))
	b.focus_entered.connect(_show_tip.bind(id))
	b.pressed.connect(_press_rune.bind(id, kind))

func _press_rune(id: String, kind: String) -> void:
	match kind:
		"essence": _e.set_root(id, str(_e.draft["root"]["manifestation_id"]))
		"form": _e.set_root(str(_e.draft["root"]["essence_id"]), id)
		"modifier": _e.toggle_modifier(id)
		"trigger":
			var active: bool = _e.draft.has("on_hit") and str(_e.draft["on_hit"]["trigger_id"]) == id
			var payload := str(_e.draft["on_hit"]["payload"]["essence_id"]) if _e.draft.has("on_hit") else "essence.lightning"
			_e.set_trigger(not active, payload, id)
	_hooks["rebuild"].call()

func _tooltip(content: VBoxContainer) -> void:
	var sec := _section(content, 60)
	_box(sec, "ad_ui_panel_tooltip", 0, 0, WIDTH, 60)
	_pic(sec, SkinA.region("ad_ui_slot24_ready"), 6, 6, 24, 24)
	_tip_slot = _pic(sec, SkinA.icon("undiscovered"), 10, 10, 16, 16)
	_tip_name = _txt(sec, "", 36, 8, 150, "selected")
	_tip_cat = _txt(sec, "", WIDTH - 158.0, 8, 150, "disabled", HORIZONTAL_ALIGNMENT_RIGHT)
	var rule := TextureRect.new()
	rule.texture = SkinA.region("ad_ui_divider_plain")
	rule.stretch_mode = TextureRect.STRETCH_TILE
	rule.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	rule.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_place(rule, 36, 20, 252, 3)
	sec.add_child(rule)
	_tip_desc = _txt(sec, "", 36, 26, 252, "normal", HORIZONTAL_ALIGNMENT_LEFT, 3)
	var hint := _section(content, 22)
	_txt(hint, tr("editor.hint1").to_upper(), 6, 0, 288, "disabled", HORIZONTAL_ALIGNMENT_LEFT)
	_txt(hint, tr("editor.hint2").to_upper(), 6, 10, 288, "disabled", HORIZONTAL_ALIGNMENT_LEFT)
	var essence := str(_e.draft["root"]["essence_id"])
	_show_tip(essence if _tip_ids.has(essence) else _first_rune)

func _show_tip(id: String) -> void:
	var info: Dictionary = _tip_ids.get(id, {})
	if info.is_empty() or _tip_name == null or not is_instance_valid(_tip_name):
		return
	_tip_slot.texture = SkinA.icon("undiscovered") if info["locked"] else SkinA.rune_icon(id)
	_tip_name.text = str(info["name"]).to_upper()
	_tip_cat.text = str(info["category"]).to_upper()
	_tip_desc.text = str(info["description"]).to_upper()

func _actions(row: HBoxContainer, verdict: Dictionary) -> void:
	cancel_button = _action(row, "EditorCancelButton", tr("editor.btn.cancel"), 78, func(): _hooks["cancel"].call(), "ui.cancel")
	undo_button = _action(row, "EditorUndoButton", tr("editor.btn.undo"), 62, func():
		_e.undo()
		_hooks["rebuild"].call())
	reset_button = _action(row, "EditorResetButton", tr("editor.btn.reset"), 66, func():
		_e.reset_draft()
		_hooks["rebuild"].call())
	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	spacer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(spacer)
	apply_button = _action(row, "EditorApplyButton", tr("editor.btn.apply"), 70, func(): _hooks["apply"].call())
	apply_button.disabled = not verdict["ok"]

func _action(row: HBoxContainer, node_name: String, label: String, width: float, action: Callable, cue: String = "ui.confirm") -> Button:
	var b := Button.new()
	b.name = node_name
	b.text = label.to_upper()
	b.clip_text = true
	b.custom_minimum_size = Vector2(width * SC, 24.0 * SC)
	b.add_theme_font_size_override("font_size", int(7 * SC))
	if _director != null:
		_director.bind_button(b, cue)
	b.pressed.connect(action)
	row.add_child(b)
	return b

func _rune_name(id: String) -> String:
	var key := "rune." + id + ".name"
	var text := tr(key)
	return id if text == key else text
