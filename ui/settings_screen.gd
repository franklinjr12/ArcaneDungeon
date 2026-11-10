extends Control
## AD-067 / AD-152: skin A settings screen (AD-095 kit, AD-096 layouts), 4 tabs. Reused by the title screen and the
## pause menu; the owner listens to back_requested and decides what to do (this screen never frees itself).
## Every control is backed by a Settings field (no disabled mock widgets). The mock resolution dropdown slot hosts the UI
## scale slider and the Access tab re-uses the removed mock toggle rects for telemetry/tips. The Music slider row is hidden
## if no Music audio bus exists; Pause stays fixed to Esc (AD-152).
const VisualTheme = preload("res://ui/pixel_theme.gd")
const ExperimentLog = preload("res://debug/experiment_log.gd")
const SkinA = preload("res://ui/skin_a.gd")
const Settings = preload("res://game/core/settings.gd")
const OsShell = preload("res://ui/os_shell.gd")
const InputActions = preload("res://ui/input_actions.gd")
const TITLE_ART := "res://assets/ui/title/ad_ui_title_illustration.png"
const TITLE_ART_LIGHT := "res://assets/ui/title/ad_ui_title_illustration_light.png"
const PREVIEW_CROP := Rect2(300, 170, 170, 84)
const CONTENT := Rect2(28, 50, 584, 252)
const TABS := ["audio", "video", "controls", "access"]
const TEST_CUE := "ui.confirm"
const MUSIC_BUS := "Music"
const FRAME_LIMIT_KEYS := {0: "settings.value.unlimited", 30: "settings.value.fps30", 60: "settings.value.fps60", 120: "settings.value.fps120"}
## bus -> [slider id, value label id] in the layout JSON (iteration order = row order).
const BUS_ROWS := {"Master": ["slider_master", "val_0"], "Music": ["slider_music", "val_1"], "SFX": ["slider_sound_effects", "val_2"],
	"UI": ["slider_interface", "val_3"], "Ambience": ["slider_ambience", "val_4"]}
## Help shown when a tab opens (id -> label key), before any row is focused.
const FIRST_HELP := {"audio": ["master", "settings.audio.master"], "video": ["lighting", "settings.lighting"], "access": ["reduce_flash", "settings.flashes"]}
const TEXT := {
	"tabs": {"audio": "settings.tab.audio", "video": "settings.tab.video", "controls": "settings.tab.controls", "access": "settings.tab.access"},
	"buses": {"Master": "settings.audio.master", "Music": "settings.audio.music", "SFX": "settings.audio.sfx", "UI": "settings.audio.ui", "Ambience": "settings.audio.ambience"},
	"modes": ["settings.mode.windowed", "settings.mode.fullscreen", "settings.mode.borderless"],
	"qualities": ["settings.lighting.high", "settings.lighting.low"],
}
const CONFLICT_COLOR := Color(1, 0.45, 0.4)
## action -> id stem used by the layout JSON rebind rows.
const RB_STEM := {"cast_slot_1": "cast_1", "cast_slot_2": "cast_2", "cast_slot_3": "cast_3", "cast_slot_4": "cast_4", "report": "screenshot"}
signal back_requested

## Kit painting (scaled 9-slice / tile), shared by the skin controls below.
class Paint extends RefCounted:
	static func sprite(name: String) -> Dictionary:
		return SkinA.kit().get("sprites", {}).get(SkinA.resolve(name), {})

	static func draw(ci: CanvasItem, name: String, rect: Rect2, sc: float, tiled: bool = false) -> void:
		var s := sprite(name)
		if s.is_empty() or rect.size.x <= 0.0 or rect.size.y <= 0.0:
			return
		var src := Rect2(s["x"], s["y"], s["w"], s["h"])
		if tiled:
			var cell := src.size * sc
			var y := rect.position.y
			while y < rect.end.y:
				var x := rect.position.x
				var h := minf(cell.y, rect.end.y - y)
				while x < rect.end.x:
					var w := minf(cell.x, rect.end.x - x)
					ci.draw_texture_rect_region(SkinA.ATLAS, Rect2(x, y, w, h), Rect2(src.position, Vector2(w, h) / sc))
					x += cell.x
				y += cell.y
			return
		var nine = s.get("nine")
		if nine == null:
			ci.draw_texture_rect_region(SkinA.ATLAS, rect, src)
			return
		var l: float = minf(nine["left"] * sc, rect.size.x * 0.5)
		var r: float = minf(nine["right"] * sc, rect.size.x * 0.5)
		var t: float = minf(nine["top"] * sc, rect.size.y * 0.5)
		var b: float = minf(nine["bottom"] * sc, rect.size.y * 0.5)
		var sx := [0.0, nine["left"], src.size.x - nine["right"], src.size.x]
		var sy := [0.0, nine["top"], src.size.y - nine["bottom"], src.size.y]
		var dx := [rect.position.x, rect.position.x + l, rect.end.x - r, rect.end.x]
		var dy := [rect.position.y, rect.position.y + t, rect.end.y - b, rect.end.y]
		for j in 3:
			for i in 3:
				var d := Rect2(dx[i], dy[j], dx[i + 1] - dx[i], dy[j + 1] - dy[j])
				var q := Rect2(src.position + Vector2(sx[i], sy[j]), Vector2(sx[i + 1] - sx[i], sy[j + 1] - sy[j]))
				if d.size.x > 0.0 and d.size.y > 0.0 and q.size.x > 0.0 and q.size.y > 0.0:
					ci.draw_texture_rect_region(SkinA.ATLAS, d, q)

	static func blank(w: int, h: int) -> ImageTexture:
		return ImageTexture.create_from_image(Image.create(maxi(w, 1), maxi(h, 1), false, Image.FORMAT_RGBA8))

class SkinBox extends Control:
	var sprite := ""
	var tiled := false
	var sc := 1.0

	func _init(sprite_name: String = "", is_tiled: bool = false) -> void:
		sprite = sprite_name
		tiled = is_tiled
		mouse_filter = Control.MOUSE_FILTER_IGNORE

	func set_skin_scale(s: float) -> void:
		sc = s
		queue_redraw()

	func _draw() -> void:
		Paint.draw(self, sprite, Rect2(Vector2.ZERO, size), sc, tiled)

## Paints a control's kit sprite from a child drawn *behind* it, so the Button's own text stays on top.
class SkinLayer extends Control:
	var skin: Control

	func _init(owner_control: Control) -> void:
		skin = owner_control
		show_behind_parent = true
		mouse_filter = Control.MOUSE_FILTER_IGNORE
		set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)

	func _draw() -> void:
		skin.call("paint", self)

## Button drawn from the kit: kind button | tab | toggle | rebind.
class SkinButton extends Button:
	var kind := "button"
	var sc := 1.0
	var active := false  # tab: selected
	var emphasis := false  # apply button uses the selected look
	var mark := ""  # rebind: listening | conflict
	var _layer: SkinLayer

	func _init() -> void:
		for st in ["normal", "hover", "pressed", "disabled", "focus", "hover_pressed"]:
			add_theme_stylebox_override(st, StyleBoxEmpty.new())
		clip_text = true
		_layer = SkinLayer.new(self)
		add_child(_layer)

	func set_skin_scale(s: float) -> void:
		sc = s
		queue_redraw()

	func _notification(what: int) -> void:
		if what == NOTIFICATION_DRAW and _layer != null:
			_layer.queue_redraw()

	func _lit() -> bool:
		return is_hovered() or has_focus()

	func paint(ci: Control) -> void:
		var rect := Rect2(Vector2.ZERO, size)
		match kind:
			"tab":
				Paint.draw(ci, "ad_ui_tab_active" if active else ("ad_ui_tab_hover" if _lit() else "ad_ui_tab_inactive"), rect, sc)
			"toggle":
				var look := "disabled" if disabled else ("hover" if _lit() else "normal")
				Paint.draw(ci, "ad_ui_toggle_%s_%s" % ["on" if button_pressed else "off", look], rect, sc)
			"rebind":
				var name := "ad_ui_rebind_idle"
				if disabled:
					name = "ad_ui_rebind_disabled"
				elif mark != "":
					name = "ad_ui_rebind_" + mark
				elif _lit():
					name = "ad_ui_rebind_hover"
				Paint.draw(ci, name, rect, sc)
			_:
				if disabled:
					Paint.draw(ci, "ad_ui_btn_disabled", rect, sc)
				elif has_focus():
					Paint.draw(ci, "ad_ui_btn_focus", rect.grow(4.0 * sc), sc)
				elif button_pressed or get_draw_mode() == DRAW_PRESSED:
					Paint.draw(ci, "ad_ui_btn_pressed", rect, sc)
				elif is_hovered():
					Paint.draw(ci, "ad_ui_btn_hover", rect, sc)
				else:
					Paint.draw(ci, "ad_ui_btn_selected" if emphasis else "ad_ui_btn_normal", rect, sc)

class SkinOption extends OptionButton:
	var sc := 1.0
	var _layer: SkinLayer

	func _init() -> void:
		for st in ["normal", "hover", "pressed", "disabled", "focus", "hover_pressed"]:
			add_theme_stylebox_override(st, StyleBoxEmpty.new())
		add_theme_icon_override("arrow", Paint.blank(1, 1))
		alignment = HORIZONTAL_ALIGNMENT_LEFT
		clip_text = true
		_layer = SkinLayer.new(self)
		add_child(_layer)

	func set_skin_scale(s: float) -> void:
		sc = s
		for st in ["normal", "hover", "pressed", "disabled", "focus", "hover_pressed"]:
			var box: StyleBox = get_theme_stylebox(st)
			box.content_margin_left = 6.0 * s
			box.content_margin_right = 15.0 * s
		queue_redraw()

	func _notification(what: int) -> void:
		if what == NOTIFICATION_DRAW and _layer != null:
			_layer.queue_redraw()

	func paint(ci: Control) -> void:
		var name := "ad_ui_dropdown_normal"
		if disabled:
			name = "ad_ui_dropdown_disabled"
		elif get_popup().visible:
			name = "ad_ui_dropdown_open"
		elif is_hovered() or has_focus():
			name = "ad_ui_dropdown_hover"
		Paint.draw(ci, name, Rect2(Vector2.ZERO, size), sc)

class SkinSlider extends HSlider:
	var sc := 1.0
	var _hover := false

	func _init() -> void:
		for st in ["slider", "grabber_area", "grabber_area_highlight", "focus"]:
			add_theme_stylebox_override(st, StyleBoxEmpty.new())

	func set_skin_scale(s: float) -> void:
		sc = s
		# Invisible native grabber with the sprite's size keeps mouse hit-testing aligned with what _draw paints.
		var blank := Paint.blank(int(10.0 * s), int(14.0 * s))
		for icon in ["grabber", "grabber_highlight", "grabber_disabled"]:
			add_theme_icon_override(icon, blank)
		queue_redraw()

	func _draw() -> void:
		var gw := 10.0 * sc
		var gh := 14.0 * sc
		var ratio := 0.0 if max_value <= min_value else clampf((value - min_value) / (max_value - min_value), 0.0, 1.0)
		var mid := size.y * 0.5
		var track := Rect2(0, mid - 4.0 * sc, size.x, 8.0 * sc)
		Paint.draw(self, "ad_ui_slider_track", track, sc)
		var cx := gw * 0.5 + ratio * (size.x - gw)
		if ratio > 0.0:
			Paint.draw(self, "ad_ui_slider_fill", Rect2(track.position, Vector2(maxf(cx, 8.0 * sc), track.size.y)), sc)
		var look := "disabled" if not editable else ("pressed" if has_focus() and Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT) else ("hover" if _hover or has_focus() else "normal"))
		Paint.draw(self, "ad_ui_slider_grab_" + look, Rect2(cx - gw * 0.5, mid - gh * 0.5, gw, gh), sc)

	func _gui_input(_event: InputEvent) -> void:
		queue_redraw()

	func _notification(what: int) -> void:
		if what == NOTIFICATION_MOUSE_ENTER or what == NOTIFICATION_MOUSE_EXIT:
			_hover = what == NOTIFICATION_MOUSE_ENTER
		if what in [NOTIFICATION_FOCUS_ENTER, NOTIFICATION_FOCUS_EXIT, NOTIFICATION_MOUSE_ENTER, NOTIFICATION_MOUSE_EXIT]:
			queue_redraw()

var save_service = null
var volume_sliders := {}
var music_slider: HSlider
var flash_toggle: Button
var shake_toggle: Button
var telemetry_toggle: Button
var tips_toggle: Button
var open_logs_button: Button
var lighting_toggle: Button
var fps_toggle: Button
var back_button: Button
var apply_button: Button
var window_mode_option: OptionButton
var lighting_option: OptionButton
var ui_scale_slider: HSlider
var ui_scale_label: Label
var binding_buttons := {}
var alt_buttons := {}
var conflict_labels := {}
var conflicts := {}
var reset_button: Button
var reset_keys_button: Button
var test_button: Button
var mute_toggle: Button
var vsync_toggle: Button
var frame_limit_option: OptionButton
var swap_button: Button
var cancel_button: Button
var listening_action := ""
var current_tab := ""
var tab_buttons := {}
var tab_pages := {}
var _listen_slot := 0
var _last_rebind := {}
var _settings
var _director = null
var _read_only := false
var _light_quality := "high"
var _items: Array = []  # {c, w, scroll}
var _by_id := {}  # tab -> {widget id -> widget}
var _help := {}  # tab -> {title, body}
var _scroll: ScrollContainer
var _holder: Control
var _backdrop: SkinBox
var _preview_rect := {}
var _preview_base: TextureRect
var _preview_light: TextureRect
var _conflict_group: Array = []
var _conflict_text: Label
var _listen_hint: Label
var _sync_hooks: Array = []  # Callables that refresh a control from _settings

func _ready() -> void:
	VisualTheme.apply(self)
	if save_service == null:
		save_service = get_node_or_null("/root/SaveService")
	_settings = save_service.settings if save_service != null else Settings.new()
	_read_only = save_service == null
	_director = get_node_or_null("/root/AudioDirector")
	_light_quality = _settings.lighting if _settings.lighting != "off" else "high"
	for tab in TABS:
		_by_id[tab] = {}
		for w in SkinA.layout("settings_" + tab).get("widgets", []):
			if not _by_id[tab].has(w.get("id", "")):
				_by_id[tab][w.get("id", "")] = w
	_backdrop = SkinBox.new("ad_ui_modal_backdrop_50", true)
	add_child(_backdrop)
	_build_chrome()
	for tab in TABS:
		var page := Control.new()
		page.name = "Page_" + tab
		page.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		page.mouse_filter = Control.MOUSE_FILTER_IGNORE
		add_child(page)
		tab_pages[tab] = page
		call("_build_" + tab, page)
		if _by_id[tab].has("help_panel"):
			_build_help(tab, page)
	refresh_bindings()
	get_viewport().size_changed.connect(_relayout)
	visibility_changed.connect(_on_visibility)
	select_tab("audio")
	_focus_first()

# ---------------------------------------------------------------- layout helpers

func _w(tab: String, id: String) -> Dictionary:
	return _by_id[tab].get(id, {"x": 0, "y": 0, "w": 0, "h": 0})

## Plain-label rects are positional in the layout JSON (label_NN), so rows find them by geometry, not by text.
func _labels(tab: String) -> Array:
	var out := []
	for w in SkinA.layout("settings_" + tab).get("widgets", []):
		if w.get("type", "") == "label":
			out.append(w)
	return out

func _same_row(label: Dictionary, ctrl: Dictionary) -> bool:
	return absf(label["y"] + label["h"] * 0.5 - (ctrl["y"] + ctrl["h"] * 0.5)) <= 8.0

## Leftmost label in the control's row that starts left of it.
func _label_left(tab: String, ctrl: Dictionary) -> Dictionary:
	var best := {"x": 44, "y": ctrl["y"], "w": 100, "h": 7}
	for l in _labels(tab):
		if l["x"] < ctrl["x"] and _same_row(l, ctrl) and l["x"] <= best["x"]:
			best = l
	return best

## First label right of min_x in the control's row (e.g. the lighting hint).
func _label_right(tab: String, ctrl: Dictionary, min_x: float) -> Dictionary:
	for l in _labels(tab):
		if l["x"] >= min_x and _same_row(l, ctrl):
			return l
	return {"x": min_x, "y": ctrl["y"], "w": 100, "h": 7}

## Labels printed inside a header rect, left to right.
func _labels_in(tab: String, hdr: Dictionary) -> Array:
	var out := []
	for l in _labels(tab):
		if l["x"] >= hdr["x"] and l["x"] < hdr["x"] + hdr["w"] and l["y"] >= hdr["y"] and l["y"] < hdr["y"] + hdr["h"]:
			out.append(l)
	out.sort_custom(func(a, b): return a["x"] < b["x"])
	return out

func _reg(c: Control, parent: Node, rect: Dictionary, scrolled: bool = false) -> Control:
	parent.add_child(c)
	_items.append({"c": c, "w": rect, "scroll": scrolled})
	return c

func _box(parent: Node, sprite: String, rect: Dictionary, tiled: bool = false, scrolled: bool = false) -> SkinBox:
	return _reg(SkinBox.new(sprite, tiled), parent, rect, scrolled) as SkinBox

func _text(parent: Node, text: String, rect: Dictionary, align: int = HORIZONTAL_ALIGNMENT_LEFT, scrolled: bool = false, wrap: bool = false) -> Label:
	var l := Label.new()
	l.text = text
	l.horizontal_alignment = align
	l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	if wrap:
		l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		l.vertical_alignment = VERTICAL_ALIGNMENT_TOP
	_reg(l, parent, rect, scrolled)
	return l

## Row label left of a control: starts at the layout label x, ends before the control.
func _row_label(tab: String, parent: Node, text: String, ctrl: Dictionary, dim: bool = false) -> Label:
	var x: float = _label_left(tab, ctrl)["x"]
	var l := _text(parent, text, {"x": x, "y": ctrl["y"], "w": maxf(ctrl["x"] - x - 4.0, 20.0), "h": ctrl["h"]})
	if dim:
		l.add_theme_color_override("font_color", SkinA.label_color("disabled"))
	return l

func _section(tab: String, parent: Node, hdr_id: String, text: String, scrolled: bool = false) -> void:
	var rect := _w(tab, hdr_id)
	_box(parent, "ad_ui_header_small", rect, false, scrolled)
	_text(parent, text, rect, HORIZONTAL_ALIGNMENT_CENTER, scrolled)

func _bind(b: BaseButton) -> void:
	if _director != null:
		_director.bind_button(b)

func _help_hook(c: Control, tab: String, id: String, label_key: String) -> void:
	var show := func():
		_show_help(tab, id, label_key)
	c.focus_entered.connect(show)
	c.mouse_entered.connect(show)

func _show_help(tab: String, id: String, label_key: String) -> void:
	if not _help.has(tab):
		return
	var h: Dictionary = _help[tab]
	h["title"].text = tr(label_key)
	h["body"].text = tr("settings.help." + id)

func _build_help(tab: String, page: Node) -> void:
	var r := _w(tab, "help_panel")
	_box(page, "ad_ui_panel_tooltip", r)
	_box(page, "ad_ui_divider_plain", {"x": r["x"] + 8, "y": r["y"] + 19, "w": r["w"] - 16, "h": 3}, true)
	var title := _text(page, "", {"x": r["x"] + 8, "y": r["y"] + 6, "w": r["w"] - 16, "h": 12})
	title.add_theme_color_override("font_color", SkinA.label_color("selected"))
	var body := _text(page, "", {"x": r["x"] + 8, "y": r["y"] + 24, "w": r["w"] - 16, "h": r["h"] - 28}, HORIZONTAL_ALIGNMENT_LEFT, false, true)
	_help[tab] = {"title": title, "body": body}

# ---------------------------------------------------------------- widget builders

func _slider(tab: String, page: Node, sid: String, label_key: String, val_id: String, value: float, enabled: bool, on_change: Callable) -> SkinSlider:
	var w := _w(tab, sid)
	var s := SkinSlider.new()
	s.min_value = 0.0
	s.max_value = 1.0
	s.step = 0.05
	s.value = value
	s.focus_mode = Control.FOCUS_ALL
	_reg(s, page, w)
	var vl := _text(page, "%d%%" % roundi(value * 100.0), {"x": w["x"] + w["w"] + 10, "y": w["y"], "w": 40, "h": w["h"]})
	_row_label(tab, page, tr(label_key), w, not enabled)
	s.value_changed.connect(func(v: float):
		vl.text = "%d%%" % roundi(v * 100.0)
		on_change.call(v))
	if not enabled:
		s.editable = false
	s.set_meta("value_label", vl)
	return s

func _toggle(tab: String, page: Node, tid: String, label_key: String, help_id: String, value: bool, on_change: Callable, rect_override: Dictionary = {}, scrolled: bool = false) -> SkinButton:
	var w: Dictionary = rect_override if not rect_override.is_empty() else _w(tab, tid)
	var b := SkinButton.new()
	b.kind = "toggle"
	b.toggle_mode = true
	b.button_pressed = value
	b.focus_mode = Control.FOCUS_ALL
	_reg(b, page, w, scrolled)
	var vrect := {"x": w["x"] + 34, "y": w["y"], "w": 40, "h": w["h"]}
	var vl := _text(page, "", vrect)
	b.set_meta("value_label", vl)
	var refresh := func(on: bool):
		vl.text = tr("settings.value.on" if on else "settings.value.off")
	refresh.call(value)
	b.toggled.connect(refresh)
	b.toggled.connect(on_change)
	var row_ctrl := {"x": w["x"], "y": w["y"], "w": w["w"], "h": w["h"]}
	_row_label(tab, page, tr(label_key), row_ctrl)
	_bind(b)
	_help_hook(b, tab, help_id, label_key)
	return b

func _dropdown(tab: String, page: Node, did: String, label_key: String, help_id: String, items: Array, selected: int, on_select: Callable, rect_override: Dictionary = {}) -> SkinOption:
	var w: Dictionary = rect_override if not rect_override.is_empty() else _w(tab, did)
	var o := SkinOption.new()
	for i in items:
		o.add_item(i)
	o.selected = selected
	o.focus_mode = Control.FOCUS_ALL
	_reg(o, page, w)
	o.item_selected.connect(on_select)
	_row_label(tab, page, tr(label_key), w)
	_bind(o)
	_help_hook(o, tab, help_id, label_key)
	return o

func _button(parent: Node, bid: String, text: String, tab: String, scrolled: bool = false) -> SkinButton:
	var b := SkinButton.new()
	b.text = text
	b.focus_mode = Control.FOCUS_ALL
	_reg(b, parent, _w(tab, bid), scrolled)
	_bind(b)
	return b

# ---------------------------------------------------------------- shared chrome

func _build_chrome() -> void:
	var tab := "audio"
	_box(self, "ad_ui_panel_large", _w(tab, "panel"))
	_box(self, "ad_ui_header", _w(tab, "title_header"))
	_text(self, tr("settings.title"), _w(tab, "title_header"), HORIZONTAL_ALIGNMENT_CENTER)
	for t in TABS:
		var b := SkinButton.new()
		b.kind = "tab"
		b.text = tr(TEXT["tabs"][t])
		b.focus_mode = Control.FOCUS_ALL
		_reg(b, self, _w(tab, "tab_" + t))
		_bind(b)
		b.pressed.connect(select_tab.bind(t))
		tab_buttons[t] = b
	_box(self, "ad_ui_panel_inset", _w(tab, "content"))
	back_button = _button(self, "btn_back", tr("settings.back"), tab)
	back_button.pressed.connect(func(): back_requested.emit())
	reset_button = _button(self, "btn_defaults", tr("settings.defaults"), tab)
	reset_button.disabled = _read_only
	reset_button.pressed.connect(reset_all)
	apply_button = _button(self, "btn_apply", tr("settings.apply"), tab)
	apply_button.emphasis = true
	apply_button.disabled = _read_only
	apply_button.pressed.connect(apply_settings)
	var hint := _text(self, tr("settings.hint"), _w(tab, "hint"), HORIZONTAL_ALIGNMENT_CENTER)
	hint.add_theme_color_override("font_color", SkinA.label_color("disabled"))
	# Tabs sit above the first slider in the focus order; down from a tab goes into the page.
	for t in TABS:
		tab_buttons[t].focus_neighbor_left = tab_buttons[t].get_path_to(tab_buttons[TABS[(TABS.find(t) + TABS.size() - 1) % TABS.size()]])
		tab_buttons[t].focus_neighbor_right = tab_buttons[t].get_path_to(tab_buttons[TABS[(TABS.find(t) + 1) % TABS.size()]])

# ---------------------------------------------------------------- audio

func _build_audio(page: Control) -> void:
	var tab := "audio"
	_section(tab, page, "hdr_volume", tr("settings.section.volume"))
	for bus in BUS_ROWS:
		var row: Array = BUS_ROWS[bus]
		var enabled := not _read_only
		if bus == MUSIC_BUS:
			enabled = enabled and AudioServer.get_bus_index(MUSIC_BUS) >= 0
		var s := _slider(tab, page, row[0], TEXT["buses"][bus], row[1], float(_settings.volumes.get(bus, 1.0)), enabled, func(v: float):
			_settings.volumes[bus] = v
			_settings.apply_audio()
			_save())
		_help_hook(s, tab, bus.to_lower(), TEXT["buses"][bus])
		if bus == MUSIC_BUS:
			music_slider = s
			if AudioServer.get_bus_index(MUSIC_BUS) < 0:
				s.visible = false
				s.get_meta("value_label").visible = false
		volume_sliders[bus] = s
		_sync_hooks.append(func():
			s.set_value_no_signal(float(_settings.volumes.get(bus, 1.0)))
			s.get_meta("value_label").text = "%d%%" % roundi(s.value * 100.0))
	_box(page, "ad_ui_divider_h", _w(tab, "div_1"))
	_section(tab, page, "hdr_options", tr("settings.section.options"))
	mute_toggle = _toggle(tab, page, "toggle_mute_unfocused", "settings.audio.mute_unfocused", "mute_unfocused", _settings.mute_unfocused, func(on: bool):
		_settings.mute_unfocused = on
		_save())
	mute_toggle.disabled = _read_only
	_sync_hooks.append(func():
		mute_toggle.set_pressed_no_signal(_settings.mute_unfocused)
		mute_toggle.get_meta("value_label").text = tr("settings.value.on" if _settings.mute_unfocused else "settings.value.off"))
	test_button = _button(page, "btn_test_sfx", tr("settings.test"), tab)
	if _director != null and _director.has_method("play"):
		test_button.pressed.connect(func(): _director.play(TEST_CUE))
	else:
		test_button.visible = false
	test_button.disabled = _read_only

# ---------------------------------------------------------------- video

func _build_video(page: Control) -> void:
	var tab := "video"
	_section(tab, page, "hdr_display", tr("settings.section.display"))
	var modes := []
	for m in TEXT["modes"]:
		modes.append(tr(m))
	window_mode_option = _dropdown(tab, page, "dd_window_mode", "settings.window_mode", "window_mode", modes,
		maxi(Settings.WINDOW_MODES.find(_settings.window_mode), 0), func(i: int):
			_settings.window_mode = Settings.WINDOW_MODES[i]
			_settings.apply_display(get_window())
			_save())
	window_mode_option.disabled = _read_only
	_sync_hooks.append(func(): window_mode_option.select(maxi(Settings.WINDOW_MODES.find(_settings.window_mode), 0)))
	# UI scale: the mock has no free row under the Display header, so it takes the mock resolution dropdown's rect.
	var rr := _w(tab, "dd_resolution")
	ui_scale_slider = SkinSlider.new()
	ui_scale_slider.min_value = 90
	ui_scale_slider.max_value = 150
	ui_scale_slider.step = 10
	ui_scale_slider.value = roundf(_settings.ui_scale * 100.0)
	ui_scale_slider.focus_mode = Control.FOCUS_ALL
	ui_scale_slider.editable = not _read_only
	_reg(ui_scale_slider, page, {"x": rr["x"], "y": rr["y"], "w": 104, "h": rr["h"]})
	ui_scale_label = _text(page, "%d%%" % int(ui_scale_slider.value), {"x": rr["x"] + 112, "y": rr["y"], "w": 40, "h": rr["h"]})
	_row_label(tab, page, tr("settings.ui_scale"), rr)
	ui_scale_slider.value_changed.connect(func(v: float):
		ui_scale_label.text = "%d%%" % int(v)
		_settings.ui_scale = Settings.snap_ui_scale(v / 100.0)
		_settings.apply_display(get_window())
		_save())
	_help_hook(ui_scale_slider, tab, "ui_scale", "settings.ui_scale")
	_sync_hooks.append(func():
		ui_scale_slider.set_value_no_signal(roundf(_settings.ui_scale * 100.0))
		ui_scale_label.text = "%d%%" % int(ui_scale_slider.value))
	var limits := []
	for l in Settings.FRAME_LIMITS:
		limits.append(tr(FRAME_LIMIT_KEYS[l]))
	frame_limit_option = _dropdown(tab, page, "dd_frame_limit", "settings.video.frame_limit", "frame_limit", limits,
		maxi(Settings.FRAME_LIMITS.find(_settings.frame_limit), 0), func(i: int):
			_settings.frame_limit = Settings.FRAME_LIMITS[i]
			_settings.apply_display(get_window())
			_save())
	frame_limit_option.disabled = _read_only
	_sync_hooks.append(func(): frame_limit_option.select(maxi(Settings.FRAME_LIMITS.find(_settings.frame_limit), 0)))
	vsync_toggle = _toggle(tab, page, "toggle_vsync", "settings.video.vsync", "vsync", _settings.vsync, func(on: bool):
		_settings.vsync = on
		_settings.apply_display(get_window())
		_save())
	vsync_toggle.disabled = _read_only
	_sync_hooks.append(func():
		vsync_toggle.set_pressed_no_signal(_settings.vsync)
		vsync_toggle.get_meta("value_label").text = tr("settings.value.on" if _settings.vsync else "settings.value.off"))
	_box(page, "ad_ui_divider_h", _w(tab, "div_1"))
	_section(tab, page, "hdr_light", tr("settings.section.light"))
	lighting_toggle = _toggle(tab, page, "toggle_lighting", "settings.lighting", "lighting", _settings.lighting != "off", func(on: bool):
		_settings.lighting = _light_quality if on else "off"
		_light_state()
		_save())
	lighting_toggle.disabled = _read_only
	var hint := _label_right(tab, _w(tab, "toggle_lighting"), 260.0)
	_text(page, tr("settings.lighting.hint"), {"x": hint["x"], "y": hint["y"] - 3, "w": 140, "h": 14}).add_theme_color_override("font_color", SkinA.label_color("disabled"))
	var qualities := []
	for q in TEXT["qualities"]:
		qualities.append(tr(q))
	lighting_option = _dropdown(tab, page, "dd_light_quality", "settings.video.light_quality", "light_quality", qualities,
		maxi(Settings.LIGHTING_MODES.find(_light_quality), 0), func(i: int):
			_light_quality = Settings.LIGHTING_MODES[i]
			if lighting_toggle.button_pressed:
				_settings.lighting = _light_quality
			_save())
	_sync_hooks.append(func():
		_light_quality = _settings.lighting if _settings.lighting != "off" else _light_quality
		lighting_option.select(maxi(Settings.LIGHTING_MODES.find(_light_quality), 0))
		lighting_toggle.set_pressed_no_signal(_settings.lighting != "off")
		lighting_toggle.get_meta("value_label").text = tr("settings.value.on" if _settings.lighting != "off" else "settings.value.off")
		_light_state())
	fps_toggle = _toggle(tab, page, "toggle_fps", "settings.video.fps", "fps", _settings.show_fps, func(on: bool):
		_settings.show_fps = on
		_save(), {"x": 196, "y": 229, "w": 28, "h": 14})
	fps_toggle.disabled = _read_only
	_sync_hooks.append(func():
		fps_toggle.set_pressed_no_signal(_settings.show_fps)
		fps_toggle.get_meta("value_label").text = tr("settings.value.on" if _settings.show_fps else "settings.value.off"))
	_preview_rect = _w(tab, "preview")
	_box(page, "ad_ui_panel_inset", _preview_rect)
	_text(page, tr("settings.lighting.preview"), {"x": _preview_rect["x"], "y": _preview_rect["y"] + 2, "w": _preview_rect["w"], "h": 12}, HORIZONTAL_ALIGNMENT_CENTER)
	var area := {"x": _preview_rect["x"] + 4, "y": _preview_rect["y"] + 16, "w": PREVIEW_CROP.size.x, "h": PREVIEW_CROP.size.y}
	_preview_base = _preview_layer(page, TITLE_ART, area, false)
	_preview_light = _preview_layer(page, TITLE_ART_LIGHT, area, true)
	_light_state()

func _preview_layer(page: Node, path: String, area: Dictionary, additive: bool) -> TextureRect:
	var r := TextureRect.new()
	var tex := AtlasTexture.new()
	tex.atlas = load(path)
	tex.region = PREVIEW_CROP
	r.texture = tex
	r.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	r.stretch_mode = TextureRect.STRETCH_SCALE
	r.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	r.mouse_filter = Control.MOUSE_FILTER_IGNORE
	if additive:
		var mat := CanvasItemMaterial.new()
		mat.blend_mode = CanvasItemMaterial.BLEND_MODE_ADD
		r.material = mat
	_reg(r, page, area)
	return r

## Lit preview and quality dropdown follow the lighting toggle.
func _light_state() -> void:
	var on: bool = _settings.lighting != "off"
	if _preview_light != null:
		_preview_light.visible = on
	if lighting_option != null:
		lighting_option.disabled = _read_only or not on

# ---------------------------------------------------------------- controls

func _build_controls(page: Control) -> void:
	var tab := "controls"
	_scroll = ScrollContainer.new()
	_scroll.name = "RebindScroll"
	_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_scroll.follow_focus = true
	_reg(_scroll, page, {"x": CONTENT.position.x, "y": CONTENT.position.y, "w": CONTENT.size.x, "h": CONTENT.size.y})
	_holder = Control.new()
	_holder.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_scroll.add_child(_holder)
	# Column headers: section name, PRIMARY and ALT sit left-aligned at the layout label positions inside the header.
	for hdr in [["hdr_combat", "settings.section.combat"], ["hdr_system", "settings.section.system"]]:
		_box(_holder, "ad_ui_header_small", _w(tab, hdr[0]), false, true)
		var cols := _labels_in(tab, _w(tab, hdr[0]))
		var keys := [hdr[1], "settings.controls.primary", "settings.controls.alt"]
		for i in mini(cols.size(), 3):
			var l := _text(_holder, tr(keys[i]), {"x": cols[i]["x"], "y": cols[i]["y"] - 3, "w": 96, "h": 14}, HORIZONTAL_ALIGNMENT_LEFT, true)
			if i > 0:
				l.add_theme_color_override("font_color", SkinA.label_color("selected"))
	for action in InputActions.REBINDABLE:
		var stem: String = RB_STEM.get(action, action)
		if not _by_id[tab].has("rb_%s_1" % stem):
			continue  # only actions that exist in the layout and in InputActions get a row
		var name_rect := _w(tab, "lbl_" + stem)
		var p_rect := _w(tab, "rb_%s_1" % stem)
		_text(_holder, tr("settings.action." + action), {"x": name_rect["x"], "y": p_rect["y"], "w": p_rect["x"] - name_rect["x"] - 4, "h": p_rect["h"]}, HORIZONTAL_ALIGNMENT_LEFT, true)
		var is_pause: bool = action == "pause"
		for slot in 2:
			var b := SkinButton.new()
			b.kind = "rebind"
			b.focus_mode = Control.FOCUS_ALL
			_reg(b, _holder, _w(tab, "rb_%s_%d" % [stem, slot + 1]), true)
			if _read_only or is_pause:
				b.disabled = true
			else:
				b.pressed.connect(func():
					listening_action = action
					_listen_slot = slot
					refresh_bindings())
				_bind(b)
			(binding_buttons if slot == 0 else alt_buttons)[action] = b
		var clabel := _text(_holder, "", {"x": name_rect["x"], "y": p_rect["y"] + p_rect["h"] - 7, "w": p_rect["x"] - name_rect["x"] - 4, "h": 10}, HORIZONTAL_ALIGNMENT_LEFT, true)
		clabel.add_theme_color_override("font_color", CONFLICT_COLOR)
		clabel.visible = false
		clabel.clip_text = true
		conflict_labels[action] = clabel
	var cp := _w(tab, "conflict_panel")
	_conflict_group.append(_box(_holder, "ad_ui_panel_tooltip", cp, false, true))
	_conflict_text = _text(_holder, "", {"x": cp["x"] + 8, "y": cp["y"] + 4, "w": cp["w"] - 16, "h": 22}, HORIZONTAL_ALIGNMENT_LEFT, true, true)
	_conflict_group.append(_conflict_text)
	swap_button = _button(_holder, "btn_swap", tr("settings.swap"), tab, true)
	cancel_button = _button(_holder, "btn_cancel", tr("settings.cancel"), tab, true)
	swap_button.pressed.connect(swap_binding)
	cancel_button.pressed.connect(cancel_rebind)
	_conflict_group.append(swap_button)
	_conflict_group.append(cancel_button)
	reset_keys_button = _button(_holder, "btn_reset_keys", tr("settings.controls.reset_keys"), tab, true)
	reset_keys_button.disabled = _read_only
	reset_keys_button.pressed.connect(reset_bindings)
	var lh := _w(tab, "listen_hint")
	_listen_hint = _text(_holder, tr("settings.controls.listen_hint"), {"x": lh["x"], "y": lh["y"] - 3, "w": 250, "h": 14}, HORIZONTAL_ALIGNMENT_LEFT, true)
	_listen_hint.visible = false
	for c in _conflict_group:
		c.visible = false

# ---------------------------------------------------------------- accessibility

func _build_access(page: Control) -> void:
	var tab := "access"
	_section(tab, page, "hdr_vision", tr("settings.section.vision"))
	flash_toggle = _toggle(tab, page, "toggle_reduce_flash", "settings.flashes", "reduce_flash", _settings.reduce_flashes, func(on: bool):
		_settings.reduce_flashes = on
		_save())
	shake_toggle = _toggle(tab, page, "toggle_reduce_shake", "settings.shake", "reduce_shake", not _settings.screen_shake, func(on: bool):
		_settings.screen_shake = not on
		_save())
	_box(page, "ad_ui_divider_h", _w(tab, "div_1"))
	_section(tab, page, "hdr_input", tr("settings.section.general"))
	# Rows re-use the rects of the removed mock toggles.
	telemetry_toggle = _toggle(tab, page, "", "settings.telemetry", "telemetry", _settings.telemetry_opt_in, func(on: bool):
		_settings.telemetry_opt_in = on
		_save(), _w(tab, "toggle_hold_cast"))
	tips_toggle = _toggle(tab, page, "", "settings.tips", "tips", _settings.tips_enabled, func(on: bool):
		_settings.tips_enabled = on
		_save(), _w(tab, "toggle_aim_assist"))
	var logs_rect := {"x": 410, "y": 226, "w": 178, "h": 18}
	open_logs_button = _button(page, "btn_open_logs", tr("settings.open_logs"), tab)
	_items[_items.size() - 1]["w"] = logs_rect
	open_logs_button.disabled = _read_only
	open_logs_button.pressed.connect(func():
		DirAccess.make_dir_recursive_absolute(ExperimentLog.LOG_DIR)
		OsShell.open_folder(ExperimentLog.log_dir_path()))
	_help_hook(open_logs_button, tab, "open_logs", "settings.open_logs")
	for c in [flash_toggle, shake_toggle, telemetry_toggle, tips_toggle]:
		c.disabled = _read_only
	for pair in [[flash_toggle, func(): return _settings.reduce_flashes], [shake_toggle, func(): return not _settings.screen_shake], [telemetry_toggle, func(): return _settings.telemetry_opt_in], [tips_toggle, func(): return _settings.tips_enabled]]:
		var t: Button = pair[0]
		var getter: Callable = pair[1]
		_sync_hooks.append(func():
			t.set_pressed_no_signal(getter.call())
			t.get_meta("value_label").text = tr("settings.value.on" if t.button_pressed else "settings.value.off"))
	# Status-icon samples are decorative.
	var cb := _w(tab, "cb_preview")
	_box(page, "ad_ui_panel_inset", cb)
	_text(page, tr("settings.access.status_icons"), {"x": cb["x"], "y": cb["y"] + 2, "w": cb["w"], "h": 12}, HORIZONTAL_ALIGNMENT_CENTER)
	for i in 3:
		var slot := _w(tab, "prev_status_%d" % i)
		if not slot.get("id", "") == "" and Paint.sprite(slot.get("sprite", "")).size() > 0:
			_box(page, slot["sprite"], slot)

# ---------------------------------------------------------------- scaling

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
	var bottom := 0.0
	for it in _items:
		var c: Control = it["c"]
		var w: Dictionary = it["w"]
		if it["scroll"]:
			SkinA.place(c, w, sc, -CONTENT.position * sc)
			bottom = maxf(bottom, w["y"] + w["h"])
		else:
			SkinA.place(c, w, sc, origin)
		if c.has_method("set_skin_scale"):
			c.set_skin_scale(sc)
		if c is Label or c is Button:
			c.add_theme_font_size_override("font_size", fs)
		if c is OptionButton:
			c.get_popup().add_theme_font_size_override("font_size", fs)
	if _holder != null:
		_holder.custom_minimum_size = Vector2(552.0, maxf(bottom - CONTENT.position.y + 6.0, 0.0)) * sc

# ---------------------------------------------------------------- tabs

func select_tab(id: String) -> void:
	if not id in TABS:
		return
	if listening_action != "":
		listening_action = ""
		refresh_bindings()
	current_tab = id
	for t in TABS:
		tab_pages[t].visible = t == id
		tab_buttons[t].active = t == id
		tab_buttons[t].queue_redraw()
	_relayout()
	if FIRST_HELP.has(id):
		_show_help(id, FIRST_HELP[id][0], FIRST_HELP[id][1])
	var owner := get_viewport().gui_get_focus_owner() if is_inside_tree() else null
	if owner == null or not owner.is_visible_in_tree():
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

func _on_visibility() -> void:
	if not visible and listening_action != "":
		listening_action = ""
		refresh_bindings()
	_focus_first()

func _save() -> void:
	if save_service != null:
		save_service.save_settings()

func _focus_first() -> void:
	if is_visible_in_tree() and current_tab == "audio" and volume_sliders.has(Settings.BUSES[0]):
		volume_sliders[Settings.BUSES[0]].grab_focus()
	elif is_visible_in_tree() and tab_buttons.has(current_tab):
		tab_buttons[current_tab].grab_focus()

## Applies the live settings and writes them (every control already applies on change; this is the explicit save).
func apply_settings() -> void:
	_settings.apply_audio()
	_settings.apply_bindings()
	_settings.apply_display(get_window())
	_save()

## Defaults button: Settings reset, reapply and save, then refresh every control.
func reset_all() -> void:
	_settings.reset()
	_light_quality = "high"
	apply_settings()
	listening_action = ""
	_last_rebind = {}
	for hook in _sync_hooks:
		hook.call()
	refresh_bindings()

# ---------------------------------------------------------------- rebinding

func effective_bindings() -> Dictionary:
	var current := InputActions.current_bindings()
	var out := {}
	for action in InputActions.REBINDABLE:
		var own = _settings.bindings.get(action, [])
		out[action] = own if typeof(own) == TYPE_ARRAY and not own.is_empty() else current.get(action, [])
	return out

func refresh_bindings() -> void:
	var eff := effective_bindings()
	conflicts = InputActions.find_conflicts(eff)
	for action in InputActions.REBINDABLE:
		var btn: SkinButton = binding_buttons.get(action)
		if btn == null:
			continue
		var list: Array = eff[action]
		for slot in 2:
			var b: SkinButton = (binding_buttons if slot == 0 else alt_buttons)[action]
			var ev = InputActions.dict_to_event(list[slot]) if list.size() > slot else null
			var listening: bool = listening_action == action and _listen_slot == slot
			b.text = tr("settings.controls.press_key") if listening else _event_text(ev)
			var clash := false
			if conflicts.has(action) and list.size() > slot:
				for other in conflicts[action]:
					clash = clash or list[slot] in eff[other]
			b.mark = "listening" if listening else ("conflict" if clash else "")
			b.queue_redraw()
		var label: Label = conflict_labels[action]
		if conflicts.has(action):
			var names := []
			for other in conflicts[action]:
				names.append(tr("settings.action." + other))
			var msg: String = tr("settings.controls.conflict") % ", ".join(names)
			btn.tooltip_text = msg
			label.text = msg
			label.visible = true
		else:
			btn.tooltip_text = ""
			label.text = ""
			label.visible = false
	_refresh_conflict_panel(eff)
	if _listen_hint != null:
		_listen_hint.visible = listening_action != ""

func _conflict_subject() -> String:
	if _last_rebind.has("action") and conflicts.has(_last_rebind["action"]):
		return _last_rebind["action"]
	for action in InputActions.REBINDABLE:
		if conflicts.has(action):
			return action
	return ""

func _refresh_conflict_panel(eff: Dictionary) -> void:
	var subject := _conflict_subject()
	for c in _conflict_group:
		c.visible = subject != ""
	if subject == "":
		return
	var names := []
	for other in conflicts[subject]:
		names.append(tr("settings.action." + other))
	var slot: int = _last_rebind.get("slot", 0) if _last_rebind.get("action", "") == subject else 0
	var list: Array = eff[subject]
	var ev = InputActions.dict_to_event(list[mini(slot, list.size() - 1)]) if not list.is_empty() else null
	_conflict_text.text = tr("settings.controls.conflict_panel") % [_event_text(ev), ", ".join(names)]
	var actionable: bool = _last_rebind.get("action", "") == subject and not _read_only
	swap_button.disabled = not actionable
	cancel_button.disabled = not actionable

func _event_text(ev) -> String:
	return InputActions.event_text(ev)

func _commit(bindings: Dictionary) -> void:
	_settings.bindings = bindings
	_settings.apply_bindings()
	_save()
	listening_action = ""
	refresh_bindings()

func rebind_action(action: String, ev: InputEvent, slot: int = 0) -> void:
	var eff := effective_bindings()
	var old: Dictionary = eff[action][slot] if eff[action].size() > slot else {}
	_last_rebind = {"action": action, "slot": slot, "old": old}
	if slot == 0:
		_commit(InputActions.rebind_primary(eff, action, ev))
		return
	var out := eff.duplicate(true)
	var list: Array = out[action]
	if list.size() > 1:
		list[1] = InputActions.event_to_dict(ev)
	else:
		list.append(InputActions.event_to_dict(ev))
	_commit(out)

## Conflict panel SWAP: the other action takes the key the rebound action just gave up.
func swap_binding() -> void:
	var subject := _conflict_subject()
	if subject == "" or _last_rebind.get("action", "") != subject or _last_rebind["old"].is_empty():
		return
	var out := effective_bindings().duplicate(true)
	var taken = out[subject][_last_rebind["slot"]]
	var other: String = conflicts[subject][0]
	var idx: int = out[other].find(taken)
	if idx >= 0:
		out[other][idx] = _last_rebind["old"]
	_last_rebind = {}
	_commit(out)

## Conflict panel CANCEL: restore what the rebound slot held before.
func cancel_rebind() -> void:
	if _last_rebind.is_empty():
		return
	var out := effective_bindings().duplicate(true)
	var list: Array = out[_last_rebind["action"]]
	var slot: int = _last_rebind["slot"]
	if _last_rebind["old"].is_empty():
		if list.size() > slot:
			list.remove_at(slot)
	else:
		list[slot] = _last_rebind["old"]
	_last_rebind = {}
	_commit(out)

## Reset keys button: bindings only.
func reset_bindings() -> void:
	_settings.bindings = {}
	InputActions.reset_to_defaults()
	_save()
	listening_action = ""
	_last_rebind = {}
	refresh_bindings()

func _input(event: InputEvent) -> void:
	if listening_action == "":
		return
	if event is InputEventKey and event.pressed and not event.echo and event.physical_keycode == KEY_ESCAPE:
		get_viewport().set_input_as_handled()
		listening_action = ""
		refresh_bindings()
		return
	var ev: InputEvent = null
	if event is InputEventKey and event.pressed and not event.echo:
		ev = event
	elif event is InputEventMouseButton and event.pressed:
		ev = event
	elif event is InputEventJoypadButton and event.pressed:
		ev = event
	elif event is InputEventJoypadMotion and absf(event.axis_value) >= 0.5:
		ev = event
	if ev == null:
		return
	get_viewport().set_input_as_handled()
	rebind_action(listening_action, ev, _listen_slot)

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
