extends Control
## AD-234: Scriptorium, the between-runs Arcane Ink upgrade screen (max HP, max mana, mana regen).
## Reads/writes the profile only through the SaveService autoload (buy/respec are saved immediately). The owner listens to
## back_requested; this screen never frees itself (standalone scenes/meta_shop.tscn returns to the main menu).
const VisualTheme = preload("res://ui/pixel_theme.gd")
const SettingsScreen = preload("res://ui/settings_screen.gd")
const MetaProgress = preload("res://world/meta_progress.gd")
const MAIN_SCENE := "res://scenes/main.tscn"
## Display multiplier per id: mana_regen is stored as a fraction per tier, shown as percent.
const DISPLAY_SCALE := {"max_hp": 1.0, "max_mana": 1.0, "mana_regen": 100.0}
signal back_requested

var save_service = null
var buy_buttons := {}
var respec_button: Button
var back_button: Button
var ink_label: Label
var tier_labels := {}
var cost_labels := {}
var next_labels := {}

func _ready() -> void:
	VisualTheme.apply(self)
	if save_service == null:
		save_service = get_node_or_null("/root/SaveService")
	add_child(SettingsScreen.SkinBox.new("ad_ui_modal_backdrop_75", true))
	var panel := SettingsScreen.SkinBox.new("ad_ui_panel_large")
	panel.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	panel.custom_minimum_size = Vector2(760, 520)
	panel.offset_left = -380
	panel.offset_right = 380
	panel.offset_top = -260
	panel.offset_bottom = 260
	add_child(panel)
	var col := VBoxContainer.new()
	col.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT, Control.PRESET_MODE_MINSIZE, 24)
	col.add_theme_constant_override("separation", 10)
	panel.add_child(col)
	var header := SettingsScreen.SkinBox.new("ad_ui_header")
	header.custom_minimum_size = Vector2(0, 48)
	col.add_child(header)
	var title := _label(tr("meta_shop.title"), HORIZONTAL_ALIGNMENT_CENTER)
	title.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	header.add_child(title)
	ink_label = _label("", HORIZONTAL_ALIGNMENT_CENTER)
	col.add_child(ink_label)
	for id in MetaProgress.upgrade_ids():
		col.add_child(_build_row(id))
	respec_button = _button(tr("meta_shop.respec"))
	respec_button.pressed.connect(_on_respec)
	col.add_child(respec_button)
	back_button = _button(tr("meta_shop.back"))
	back_button.pressed.connect(func(): back_requested.emit())
	col.add_child(back_button)
	_wire_focus()
	back_requested.connect(_on_back_standalone)
	visibility_changed.connect(_focus_first)
	refresh()

func _label(text: String, align: int = HORIZONTAL_ALIGNMENT_LEFT) -> Label:
	var l := Label.new()
	l.text = text
	l.horizontal_alignment = align as HorizontalAlignment
	l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return l

func _button(text: String) -> Button:
	var b := SettingsScreen.SkinButton.new()
	b.text = text
	b.focus_mode = Control.FOCUS_ALL
	b.custom_minimum_size = Vector2(0, 40)
	var director = get_node_or_null("/root/AudioDirector")
	if director != null:
		director.bind_button(b)
	return b

func _build_row(id: String) -> Control:
	var inset := SettingsScreen.SkinBox.new("ad_ui_panel_inset")
	inset.custom_minimum_size = Vector2(0, 84)
	var row := HBoxContainer.new()
	row.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT, Control.PRESET_MODE_MINSIZE, 10)
	row.add_theme_constant_override("separation", 12)
	inset.add_child(row)
	var info := VBoxContainer.new()
	info.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(info)
	var head := HBoxContainer.new()
	info.add_child(head)
	var name_label := _label(tr("meta_shop.name." + id))
	name_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(name_label)
	tier_labels[id] = _label("", HORIZONTAL_ALIGNMENT_RIGHT)
	head.add_child(tier_labels[id])
	next_labels[id] = _label("")
	info.add_child(next_labels[id])
	var buy := VBoxContainer.new()
	buy.custom_minimum_size = Vector2(190, 0)
	row.add_child(buy)
	cost_labels[id] = _label("", HORIZONTAL_ALIGNMENT_CENTER)
	buy.add_child(cost_labels[id])
	var b := _button(tr("meta_shop.buy"))
	b.pressed.connect(_on_buy.bind(id))
	buy.add_child(b)
	buy_buttons[id] = b
	return inset

func _wire_focus() -> void:
	var order := _focus_order()
	for i in order.size():
		var b: Control = order[i]
		b.focus_neighbor_top = b.get_path_to(order[(i + order.size() - 1) % order.size()])
		b.focus_neighbor_bottom = b.get_path_to(order[(i + 1) % order.size()])

func _meta() -> Dictionary:
	return save_service.meta() if save_service != null else MetaProgress.empty_meta()

func _fmt(id: String, per_tier_units: float) -> int:
	return int(round(per_tier_units * float(DISPLAY_SCALE[id])))

## Re-reads the profile and updates every label/button state.
func refresh() -> void:
	var meta := _meta()
	var ink := int(meta.get("ink", 0))
	ink_label.text = tr("meta_shop.ink") % ink
	for id in MetaProgress.upgrade_ids():
		var tier := MetaProgress.tier(meta, id)
		var cost := MetaProgress.next_cost(meta, id)
		var per := float(MetaProgress.upgrade_def(id).get("per_tier", 0))
		tier_labels[id].text = tr("meta_shop.tier") % [tier, MetaProgress.max_tier(id)]
		var b: Button = buy_buttons[id]
		if cost < 0:
			cost_labels[id].text = tr("meta_shop.max")
			next_labels[id].text = tr("meta_shop.next.done") % ("%d%s" % [_fmt(id, per * tier), "%" if id == "mana_regen" else ""])
			b.disabled = true
			b.text = tr("meta_shop.max")
		else:
			cost_labels[id].text = tr("meta_shop.cost") % cost
			next_labels[id].text = tr("meta_shop.next." + id) % [_fmt(id, per), _fmt(id, per * (tier + 1))]
			b.disabled = ink < cost
			b.text = tr("meta_shop.buy") if ink >= cost else tr("meta_shop.need_ink") % (cost - ink)
	respec_button.disabled = MetaProgress.spent_ink(meta) <= 0
	var owner := get_viewport().gui_get_focus_owner() if is_inside_tree() else null
	if owner == null or (owner is BaseButton and owner.disabled):
		_focus_first()

func _on_buy(id: String) -> void:
	if save_service != null and save_service.buy_upgrade(id):
		refresh()

func _on_respec() -> void:
	if save_service != null:
		save_service.respec_upgrades()
	refresh()

func _focus_first() -> void:
	if not is_visible_in_tree():
		return
	for b in _focus_order():
		if not b.disabled:
			b.grab_focus()
			return

func _focus_order() -> Array:
	var order: Array = []
	for id in MetaProgress.upgrade_ids():
		order.append(buy_buttons[id])
	order.append(respec_button)
	order.append(back_button)
	return order

func _on_back_standalone() -> void:
	if is_inside_tree() and get_tree().current_scene == self:
		get_tree().change_scene_to_file(MAIN_SCENE)

func _unhandled_input(event: InputEvent) -> void:
	if visible and event.is_action_pressed("ui_cancel"):
		back_requested.emit()
		get_viewport().set_input_as_handled()
