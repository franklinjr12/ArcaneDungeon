extends Control
## AD-145 / AD-153: read-only skin A Compendium (AD-097 layouts ad_ui_screen_compendium_{runes,reactions,enemies,artifacts}).
## Tabs: Runes, Reactions, Enemies, Artifacts, switched by click, Q/E, shoulder buttons or PageUp/PageDown. The owner listens to
## back_requested; this screen never frees itself and never writes the profile.
## Deviations from the mocks (owner/art follow-ups): no enemy sprite lookup exists for UI, so enemy cells show the name only
## (undiscovered: "?" + undiscovered icon); enemy detail shows weak/resist icons (AD-194) but no other per-entry stats
## (found/used/encountered/drops) because no such data is tracked; artifacts use the generic upgrade glyph (as the HUD does) and no rarity card; milestones are not listed (only the
## layout's static note); enemy/reaction detail prose is limited to the name and recipe. Entries beyond a layout's cells are
## paged with the scroll arrows (the enemy layout has 14 cells for 15 enemies); cells beyond the catalog are hidden.
const VisualTheme = preload("res://ui/pixel_theme.gd")
const SkinA = preload("res://ui/skin_a.gd")
const SettingsScreen = preload("res://ui/settings_screen.gd")
const MetaProgress = preload("res://world/meta_progress.gd")
const Artifacts = preload("res://world/artifacts.gd")
const Art = preload("res://ui/pixel_art_renderer.gd")
const EnemyAffinity = preload("res://ui/enemy_affinity.gd")
const RUN_PATH := "res://world/data/run_v2.json"
const TABS := ["runes", "reactions", "enemies", "artifacts"]
const CHROME_LAYOUT := "compendium_runes"
## Operand icon names + result icon per reaction id (display only; the rules live in the simulation data).
const REACTION_ICONS := {
	"wet_lightning_arc": ["wet", "lightning", "charged"],
	"chill_freeze": ["chilled", "chilled", "frozen"],
	"wet_cold_freeze": ["wet", "cold", "frozen"],
	"frozen_force_shatter": ["frozen", "force", "brittle"],
	"fire_thaw_steam": ["fire", "chilled", "wet"],
}
const TEXT := {
	"title": "compendium.title",
	"back": "compendium.back",
	"unknown": "compendium.unknown",
	"progress": "compendium.discovered",
	"tabs": {"runes": "compendium.section.runes", "reactions": "compendium.section.reactions", "enemies": "compendium.section.enemies", "artifacts": "compendium.section.artifacts"},
	"tags": {"runes": "compendium.tag.rune", "reactions": "compendium.tag.reaction", "enemies": "compendium.tag.enemy", "artifacts": "compendium.tag.artifact"},
	"note1": "compendium.note1",
	"note2": "compendium.note2",
	"undiscovered": "compendium.undiscovered",
	"recipe": "compendium.recipe.%s",
}
signal back_requested

## Cell / row / arrow button painted from the kit; `sprites` = {normal, hover, selected, locked}.
class Cell extends SettingsScreen.SkinButton:
	var sprites := {}
	var chosen := false
	var locked := false
	var entry_id := ""

	func _init() -> void:
		super._init()
		kind = "cell"

	func paint(ci: Control) -> void:
		var name: String = sprites.get("locked" if locked else ("selected" if chosen else ("hover" if _lit() else "normal")), "")
		if name == "" or (locked and chosen and _lit()):
			name = sprites.get("normal", "")
		SettingsScreen.Paint.draw(ci, name, Rect2(Vector2.ZERO, size), sc)

var save_service = null
var back_button: Button
var tab_buttons := {}
var tab_pages := {}
var current_tab := ""
## tab -> Array of Cell (visible and hidden, in layout order).
var cells := {}
## tab -> progress Label ("DISCOVERED a / b").
var section_labels := {}
## tab -> layout widgets by id.
var layout_by_tab := {}
var selected := {}
var pages := {}
var _meta: Dictionary
var _catalogs: Dictionary
var _items: Array = []  # {c, w, fill}
var _backdrop: SettingsScreen.SkinBox
var _detail := {}  # tab -> {name, tag, desc, rec, slot}
var _arrows := {}  # tab -> {up, down}
var _cell_extras := {}  # Cell -> Array of overlay controls
var _bars := {}

func _ready() -> void:
	VisualTheme.apply(self)
	if save_service == null:
		save_service = get_node_or_null("/root/SaveService")
	_meta = save_service.meta() if save_service != null else MetaProgress.empty_meta()
	_catalogs = catalogs_by_category()
	for tab in TABS:
		layout_by_tab[tab] = SkinA.widgets_by_id("compendium_" + tab)
		selected[tab] = 0
		pages[tab] = 0
	_backdrop = SettingsScreen.SkinBox.new("ad_ui_modal_backdrop_75", true)
	add_child(_backdrop)
	_build_chrome()
	for tab in TABS:
		var page := Control.new()
		page.name = "Page_" + tab
		page.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		page.mouse_filter = Control.MOUSE_FILTER_IGNORE
		add_child(page)
		tab_pages[tab] = page
		_build_page(tab, page)
	get_viewport().size_changed.connect(_relayout)
	visibility_changed.connect(_focus_first)
	select_tab("runes")
	_focus_first()

# ---------------------------------------------------------------- building

func _w(tab: String, id: String) -> Dictionary:
	return layout_by_tab[tab].get(id, {"x": 0, "y": 0, "w": 0, "h": 0})

func _reg(c: Control, parent: Node, rect: Dictionary) -> Control:
	parent.add_child(c)
	_items.append({"c": c, "w": rect})
	return c

func _box(parent: Node, sprite: String, rect: Dictionary, tiled: bool = false) -> SettingsScreen.SkinBox:
	return _reg(SettingsScreen.SkinBox.new(sprite, tiled), parent, rect) as SettingsScreen.SkinBox

func _text(parent: Node, text: String, rect: Dictionary, align: int = HORIZONTAL_ALIGNMENT_LEFT, wrap: bool = false) -> Label:
	var l := Label.new()
	l.text = text
	l.horizontal_alignment = align
	l.vertical_alignment = VERTICAL_ALIGNMENT_TOP if wrap else VERTICAL_ALIGNMENT_CENTER
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	if wrap:
		l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		l.clip_text = true # keep the wrapped height from growing the label past its layout rect
	return _reg(l, parent, rect) as Label

func _pic(parent: Node, tex: Texture2D, rect: Dictionary) -> TextureRect:
	var r := TextureRect.new()
	r.texture = tex
	r.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	r.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	r.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	r.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return _reg(r, parent, rect) as TextureRect

func _bind(b: BaseButton) -> void:
	var director = get_node_or_null("/root/AudioDirector")
	if director != null:
		director.bind_button(b)

func _build_chrome() -> void:
	var tab := CHROME_LAYOUT.trim_prefix("compendium_")
	_box(self, "ad_ui_panel_large", _w(tab, "panel"))
	_box(self, "ad_ui_header", _w(tab, "title_header"))
	_text(self, tr(TEXT["title"]), _w(tab, "title_header"), HORIZONTAL_ALIGNMENT_CENTER)
	for t in TABS:
		var b := SettingsScreen.SkinButton.new()
		b.kind = "tab"
		b.text = tr(TEXT["tabs"][t])
		b.focus_mode = Control.FOCUS_ALL
		_reg(b, self, _w(tab, "tab_" + t))
		_bind(b)
		b.pressed.connect(select_tab.bind(t))
		tab_buttons[t] = b
	_box(self, "ad_ui_panel_inset", _w(tab, "content"))
	back_button = SettingsScreen.SkinButton.new()
	back_button.text = tr(TEXT["back"])
	back_button.focus_mode = Control.FOCUS_ALL
	_reg(back_button, self, _w(tab, "btn_back"))
	_bind(back_button)
	back_button.pressed.connect(func(): back_requested.emit())
	_text(self, tr(TEXT["note1"]), _w(tab, "note1"))
	_text(self, tr(TEXT["note2"]), _w(tab, "note2"))
	for t in TABS:
		var i := TABS.find(t)
		tab_buttons[t].focus_neighbor_left = tab_buttons[t].get_path_to(tab_buttons[TABS[(i + TABS.size() - 1) % TABS.size()]])
		tab_buttons[t].focus_neighbor_right = tab_buttons[t].get_path_to(tab_buttons[TABS[(i + 1) % TABS.size()]])
		tab_buttons[t].focus_neighbor_bottom = tab_buttons[t].get_path_to(back_button)
	back_button.focus_neighbor_top = back_button.get_path_to(tab_buttons["runes"])

func _cell_ids(tab: String) -> Array:
	var out := []
	var prefix: String = {"runes": "rune_", "reactions": "reaction_", "enemies": "enemy_", "artifacts": "artifact_"}[tab]
	var n := 1
	while layout_by_tab[tab].has(prefix + str(n)):
		out.append(prefix + str(n))
		n += 1
	return out

func _found(tab: String) -> Array:
	return _meta["discovered"][tab]

func _build_page(tab: String, page: Control) -> void:
	var ids: Array = _catalogs.get(tab, [])
	var found := _found(tab)
	var seen := 0
	for id in ids:
		if id in found:
			seen += 1
	var tl := _text(page, tr(TEXT["progress"]) % [seen, ids.size()], _w(tab, "progress_txt"))
	section_labels[tab] = tl
	_box(page, "ad_ui_bar_frame_thin", _w(tab, "progress_bar"))
	var bar := _w(tab, "progress_bar").duplicate()
	bar["fraction"] = float(seen) / maxf(1.0, float(ids.size()))
	_bars[tab] = _box(page, "ad_ui_bar_fill_xp", bar)
	var d := {}
	_box(page, "ad_ui_panel_tooltip", _w(tab, "detail"))
	d["name"] = _text(page, "", _w(tab, "d_name"))
	d["tag"] = _text(page, "", _w(tab, "d_tag"), HORIZONTAL_ALIGNMENT_RIGHT)
	_box(page, "ad_ui_divider_plain", _w(tab, "divider_" + _divider_suffix(tab)), true)
	var desc_rect: Dictionary = _w(tab, "d_desc_0").duplicate()
	desc_rect["h"] = 56
	desc_rect["w"] = _w(tab, "detail")["x"] + _w(tab, "detail")["w"] - desc_rect["x"] - 8
	if tab == "reactions":
		desc_rect["y"] = _w(tab, "d_desc_0")["y"]
		d["rec"] = _text(page, "", _w(tab, "d_rec"))
	d["desc"] = _text(page, "", desc_rect, HORIZONTAL_ALIGNMENT_LEFT, true)
	var slot := _w(tab, "d_slot") if layout_by_tab[tab].has("d_slot") else _w(tab, "d_portrait")
	_box(page, "ad_ui_slot40_selected" if tab != "enemies" else "ad_ui_panel_inset", slot)
	var pic_rect := {"x": slot["x"] + (slot["w"] - 16) / 2, "y": slot["y"] + (slot["h"] - 16) / 2, "w": 16, "h": 16}
	d["slot"] = _pic(page, null, pic_rect)
	d["slot"].visible = slot.get("w", 0) > 0 # artifacts layout has no detail slot
	if tab == "enemies":
		d["weak_label"] = _text(page, tr("compendium.weak"), {"x": 340, "y": 212, "w": 52, "h": 7})
		d["resist_label"] = _text(page, tr("compendium.resist"), {"x": 340, "y": 236, "w": 52, "h": 7})
		d["weak_icons"] = []
		d["resist_icons"] = []
		for i in 6:
			d["weak_icons"].append(_pic(page, null, {"x": 398 + 20 * i, "y": 206, "w": 16, "h": 16}))
			d["resist_icons"].append(_pic(page, null, {"x": 398 + 20 * i, "y": 230, "w": 16, "h": 16}))
	_detail[tab] = d
	if layout_by_tab[tab].has("scroll_track"):
		_box(page, "ad_ui_scroll_track_v", _w(tab, "scroll_track"))
	var cell_ids := _cell_ids(tab)
	cells[tab] = []
	for cid in cell_ids:
		var w := _w(tab, cid)
		var c := Cell.new()
		c.focus_mode = Control.FOCUS_ALL
		c.sprites = _cell_sprites(tab, w)
		_reg(c, page, w)
		_bind(c)
		cells[tab].append(c)
		var idx: int = cells[tab].size() - 1
		c.pressed.connect(func(): _select(tab, idx))
		c.focus_entered.connect(func(): _select(tab, idx))
		c.mouse_entered.connect(func(): _select(tab, idx))
		_cell_extras[c] = _cell_extra(tab, page, w, cid)
	if layout_by_tab[tab].has("scroll_up"):
		var up := _arrow(page, tab, "up")
		var down := _arrow(page, tab, "down")
		_arrows[tab] = {"up": up, "down": down}
		up.pressed.connect(_page_step.bind(tab, -1))
		down.pressed.connect(_page_step.bind(tab, 1))
	_fill_page(tab)

func _divider_suffix(tab: String) -> String:
	for id in layout_by_tab[tab]:
		if str(id).begins_with("divider_"):
			return str(id).trim_prefix("divider_")
	return ""

func _cell_sprites(tab: String, w: Dictionary) -> Dictionary:
	if tab == "reactions" or tab == "enemies":
		return {"normal": "ad_ui_panel_inset", "hover": "ad_ui_panel_inset", "selected": "ad_ui_panel_inset", "locked": "ad_ui_panel_inset"}
	return {"normal": "ad_ui_slot40_normal", "hover": "ad_ui_slot40_hover", "selected": "ad_ui_slot40_selected", "locked": "ad_ui_slot40_disabled"}

func _arrow(page: Control, tab: String, dir: String) -> Cell:
	var c := Cell.new()
	c.focus_mode = Control.FOCUS_ALL
	c.sprites = {"normal": "ad_ui_scroll_arrow_%s_normal" % dir, "hover": "ad_ui_scroll_arrow_%s_hover" % dir, "selected": "ad_ui_scroll_arrow_%s_pressed" % dir, "locked": "ad_ui_scroll_arrow_%s_disabled" % dir}
	_reg(c, page, _w(tab, "scroll_" + dir))
	_bind(c)
	return c

## Labels / icons drawn over a cell (siblings, so the button keeps the click).
func _cell_extra(tab: String, page: Control, w: Dictionary, cid: String) -> Array:
	var out := []
	match tab:
		"runes", "artifacts":
			out.append(_pic(page, null, {"x": w["x"] + (w["w"] - 16) / 2, "y": w["y"] + (w["h"] - 16) / 2, "w": 16, "h": 16}))
		"enemies":
			out.append(_pic(page, null, {"x": w["x"] + (w["w"] - 16) / 2, "y": w["y"] + 8, "w": 16, "h": 16}))
			out.append(_text(page, "", {"x": w["x"] + 2, "y": w["y"] + 26, "w": w["w"] - 4, "h": 26}, HORIZONTAL_ALIGNMENT_CENTER, true))
		"reactions":
			for i in 3:
				out.append(_pic(page, null, {"x": w["x"] + 6 + i * 30 + (8 if i == 2 else 0), "y": w["y"] + 10, "w": 16, "h": 16}))
			out.append(_text(page, "", {"x": w["x"] + 106, "y": w["y"] + 6, "w": w["w"] - 110, "h": 12}))
			out.append(_text(page, "", {"x": w["x"] + 106, "y": w["y"] + 19, "w": w["w"] - 110, "h": 12}))
	return out

# ---------------------------------------------------------------- entries

func entries(tab: String) -> Array:
	var ids: Array = _catalogs.get(tab, [])
	var per: int = cells[tab].size()
	var start: int = pages[tab] * per
	return ids.slice(start, start + per)

func page_count(tab: String) -> int:
	var per: int = maxi(1, cells[tab].size())
	return maxi(1, ceili(float(_catalogs.get(tab, []).size()) / per))

func _page_step(tab: String, delta: int) -> void:
	pages[tab] = clampi(pages[tab] + delta, 0, page_count(tab) - 1)
	selected[tab] = 0
	_fill_page(tab)
	_relayout()

func _fill_page(tab: String) -> void:
	var list := entries(tab)
	var found := _found(tab)
	var per: int = cells[tab].size()
	for i in per:
		var c: Cell = cells[tab][i]
		var extras: Array = _cell_extras[c]
		var has := i < list.size()
		c.visible = has
		for e in extras:
			e.visible = has
		c.entry_id = str(list[i]) if has else ""
		c.locked = has and not (c.entry_id in found)
		c.disabled = false
		if has:
			_style_cell(tab, c, extras)
	if _arrows.has(tab):
		_arrows[tab]["up"].locked = pages[tab] <= 0
		_arrows[tab]["down"].locked = pages[tab] >= page_count(tab) - 1
		for a in _arrows[tab].values():
			a.visible = page_count(tab) > 1
			a.queue_redraw()
	selected[tab] = clampi(selected[tab], 0, maxi(0, list.size() - 1))
	_select(tab, selected[tab])

func _style_cell(tab: String, c: Cell, extras: Array) -> void:
	var id := c.entry_id
	var known := not c.locked
	match tab:
		"runes":
			extras[0].texture = SkinA.rune_icon(id) if known else SkinA.icon("undiscovered")
		"artifacts":
			extras[0].texture = Art.artifact_icon(id) if known else SkinA.icon("undiscovered")
		"enemies":
			extras[0].texture = SkinA.icon("undiscovered") if not known else null
			extras[1].text = entry_name(tab, id) if known else "?"
		"reactions":
			var icons: Array = REACTION_ICONS.get(id, ["undiscovered", "undiscovered", "undiscovered"])
			for i in 3:
				extras[i].texture = SkinA.icon_or_mvp(icons[i]) if known else SkinA.icon("undiscovered")
			extras[3].text = entry_name(tab, id) if known else tr(TEXT["unknown"])
			extras[4].text = tr(TEXT["recipe"] % id) if known else tr(TEXT["undiscovered"])
	c.text = ""

func entry_name(tab: String, id: String) -> String:
	match tab:
		"runes": return tr("rune." + id + ".name")
		"artifacts": return tr("artifact." + id + ".name")
		"reactions": return tr("compendium.reaction." + id)
		_: return tr("compendium.enemy." + id)

func _select(tab: String, idx: int) -> void:
	var list := entries(tab)
	selected[tab] = idx
	for i in cells[tab].size():
		cells[tab][i].chosen = i == idx and i < list.size()
		cells[tab][i].queue_redraw()
	var d: Dictionary = _detail[tab]
	if idx >= list.size():
		return
	var id: String = list[idx]
	var known: bool = id in _found(tab)
	d["name"].text = entry_name(tab, id) if known else tr(TEXT["unknown"])
	d["tag"].text = tr(TEXT["tags"][tab])
	var desc := ""
	if not known:
		desc = tr(TEXT["undiscovered"])
	elif tab == "runes":
		desc = tr("rune." + id + ".desc")
	elif tab == "artifacts":
		desc = tr("artifact." + id + ".desc")
	elif tab == "reactions":
		d["rec"].text = tr(TEXT["recipe"] % id)
	d["desc"].text = desc
	if tab == "reactions" and not known:
		d["rec"].text = ""
	var tex: Texture2D = SkinA.icon("undiscovered")
	if known:
		match tab:
			"runes": tex = SkinA.rune_icon(id)
			"artifacts": tex = Art.artifact_icon(id, 32)
			"reactions": tex = SkinA.icon_or_mvp(REACTION_ICONS.get(id, ["undiscovered", "", "undiscovered"])[2])
			_: tex = null
	d["slot"].texture = tex
	if tab == "enemies":
		var aff: Dictionary = EnemyAffinity.of(id) if known else {"weak": [], "resist": []}
		for row in ["weak", "resist"]:
			var channels: Array = aff[row]
			d[row + "_label"].visible = not channels.is_empty()
			for i in d[row + "_icons"].size():
				var pic: TextureRect = d[row + "_icons"][i]
				pic.visible = i < channels.size()
				pic.texture = EnemyAffinity.icon(channels[i]) if i < channels.size() else null

# ---------------------------------------------------------------- layout

func _relayout() -> void:
	if _items.is_empty() or not is_inside_tree():
		return
	var vp := get_viewport_rect().size
	var sc := SkinA.canvas_scale(vp)
	var origin := SkinA.canvas_origin(vp, sc)
	var fs := maxi(14, int(7.0 * sc))
	_backdrop.position = Vector2.ZERO
	_backdrop.size = vp
	_backdrop.set_skin_scale(sc)
	for it in _items:
		var c: Control = it["c"]
		var w: Dictionary = it["w"]
		if w.has("fraction"):
			var inner := w.duplicate()
			inner["x"] += 1
			inner["y"] += 1
			inner["w"] = maxf(0.0, (w["w"] - 2) * float(w["fraction"]))
			inner["h"] = w["h"] - 2
			SkinA.place(c, inner, sc, origin)
		else:
			SkinA.place(c, w, sc, origin)
		if c.has_method("set_skin_scale"):
			c.set_skin_scale(sc)
		if c is Label or c is Button:
			c.add_theme_font_size_override("font_size", fs)

func select_tab(id: String) -> void:
	if not id in TABS:
		return
	current_tab = id
	for t in TABS:
		tab_pages[t].visible = t == id
		tab_buttons[t].active = t == id
		tab_buttons[t].queue_redraw()
	_relayout()
	var owner := get_viewport().gui_get_focus_owner() if is_inside_tree() else null
	if owner == null or not owner.is_visible_in_tree() or owner in tab_buttons.values():
		tab_buttons[id].grab_focus()

func _step_tab(delta: int) -> void:
	select_tab(TABS[(TABS.find(current_tab) + delta + TABS.size()) % TABS.size()])
	tab_buttons[current_tab].grab_focus()

func _tab_delta(event: InputEvent) -> int:
	if event.is_action_pressed("ui_page_up"):
		return -1
	if event.is_action_pressed("ui_page_down"):
		return 1
	if event is InputEventJoypadButton and event.pressed:
		if event.button_index == JOY_BUTTON_LEFT_SHOULDER:
			return -1
		if event.button_index == JOY_BUTTON_RIGHT_SHOULDER:
			return 1
	if event is InputEventKey and event.pressed and not event.echo:
		if event.physical_keycode == KEY_Q:
			return -1
		if event.physical_keycode == KEY_E:
			return 1
	return 0

func _focus_first() -> void:
	if is_visible_in_tree() and tab_buttons.has(current_tab):
		tab_buttons[current_tab].grab_focus()

func _unhandled_input(event: InputEvent) -> void:
	if not visible:
		return
	if event.is_action_pressed("ui_cancel"):
		back_requested.emit()
		get_viewport().set_input_as_handled()
		return
	var delta := _tab_delta(event)
	if delta != 0:
		_step_tab(delta)
		get_viewport().set_input_as_handled()

## Sorted id catalog per category.
static func catalogs_by_category() -> Dictionary:
	var compendium: Dictionary = MetaProgress.load_config().get("compendium", {})
	var runes := {}
	var file := FileAccess.open(RUN_PATH, FileAccess.READ)
	var run_cfg = JSON.parse_string(file.get_as_text()) if file != null else {}
	if run_cfg is Dictionary:
		for key in ["initial_unlocked", "reward_pool"]:
			for id in run_cfg.get(key, []):
				runes[id] = true
	for ms in MetaProgress.milestones():
		for id in ms.get("unlocks", {}).get("runes", []):
			runes[id] = true
	var rune_ids := runes.keys()
	rune_ids.sort()
	var artifact_ids := Artifacts.definitions().keys()
	artifact_ids.sort()
	return {
		"runes": rune_ids,
		"reactions": compendium.get("reactions", []),
		"enemies": compendium.get("enemies", []),
		"artifacts": artifact_ids,
	}
