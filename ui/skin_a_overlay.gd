extends Control
## AD-153: layout-driven skin A modal for the in-run overlays (reward pick, merchant, run summary). The owner calls
## begin(screen), adds sprites/labels/buttons by layout widget id (or an explicit canvas rect), then finish(). Everything is
## placed on the centred 640x360 canvas at an integer scale. Render-only: it never touches the sim.
const SkinA = preload("res://ui/skin_a.gd")
const FONT_UNITS := 7 # m5x7 glyph height in canvas px; x2 = 14 px at 1280x720

var screen := ""
var widgets: Dictionary = {}
var backdrop: TextureRect
var content: Control
var buttons: Dictionary = {} # widget id -> Button, in creation order
var director = null
var _items: Array = [] # [Control, rect Dictionary in canvas px]
var _focus_id := ""
var _focus_order: Array = []

func _init(block_mouse: bool = false) -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	visible = false
	backdrop = TextureRect.new()
	backdrop.name = "Backdrop"
	backdrop.stretch_mode = TextureRect.STRETCH_TILE
	backdrop.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	backdrop.mouse_filter = Control.MOUSE_FILTER_STOP if block_mouse else Control.MOUSE_FILTER_IGNORE
	add_child(backdrop)
	content = Control.new()
	content.name = "Content"
	content.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(content)
	resized.connect(relayout)

## Starts a rebuild from a layout screen; remembers which button had focus so a rebuild keeps it.
func begin(screen_name: String) -> void:
	_focus_id = ""
	for id in buttons:
		if buttons[id].has_focus():
			_focus_id = id
	screen = screen_name
	widgets = SkinA.widgets_by_id(screen_name)
	backdrop.texture = SkinA.region(widgets.get("modal_backdrop", {}).get("sprite", "ad_ui_modal_backdrop_50"))
	for child in content.get_children():
		content.remove_child(child)
		child.queue_free()
	buttons.clear()
	_items.clear()

func has_widget(id: String) -> bool:
	return widgets.has(id)

## Layout widget (or explicit rect) shifted by dx/dy canvas px.
func rect_of(id: String, dx: float = 0.0, dy: float = 0.0) -> Dictionary:
	var w: Dictionary = widgets.get(id, {})
	return {"x": float(w.get("x", 0)) + dx, "y": float(w.get("y", 0)) + dy, "w": float(w.get("w", 0)), "h": float(w.get("h", 0))}

## Layout sub-region ("regions": header/art/icon/text) of a card widget, shifted by dx/dy.
func region_of(id: String, region: String, dx: float = 0.0, dy: float = 0.0) -> Dictionary:
	var r: Array = widgets.get(id, {}).get("regions", {}).get(region, [0, 0, 0, 0])
	return {"x": float(r[0]) + dx, "y": float(r[1]) + dy, "w": float(r[2]), "h": float(r[3])}

func _add(control: Control, node_name: String, rect: Dictionary) -> void:
	control.name = node_name
	content.add_child(control)
	_items.append([control, rect])

func frame(node_name: String, sprite: String, rect: Dictionary) -> Panel:
	var p := Panel.new()
	p.add_theme_stylebox_override("panel", SkinA.stylebox(sprite))
	p.mouse_filter = Control.MOUSE_FILTER_IGNORE
	p.set_meta("sprite", sprite)
	_add(p, node_name, rect)
	return p

func picture(node_name: String, tex: Texture2D, rect: Dictionary) -> TextureRect:
	var r := TextureRect.new()
	r.texture = tex
	r.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	r.stretch_mode = TextureRect.STRETCH_SCALE
	r.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	r.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_add(r, node_name, rect)
	return r

## Tiled flat strip (dividers): sprites without a 9-slice.
func rule(node_name: String, sprite: String, rect: Dictionary) -> TextureRect:
	var r := TextureRect.new()
	r.texture = SkinA.region(sprite)
	r.stretch_mode = TextureRect.STRETCH_TILE
	r.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	r.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_add(r, node_name, rect)
	return r

func text(node_name: String, value: String, rect: Dictionary, state: String = "normal", align: int = HORIZONTAL_ALIGNMENT_LEFT, max_lines: int = 1, units: int = FONT_UNITS) -> Label:
	var l := Label.new()
	l.text = value
	l.horizontal_alignment = align
	l.vertical_alignment = VERTICAL_ALIGNMENT_TOP
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART if max_lines > 1 else TextServer.AUTOWRAP_OFF
	l.max_lines_visible = max_lines
	l.clip_text = true
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	l.set_meta("units", units)
	l.add_theme_color_override("font_color", SkinA.label_color(state))
	_add(l, node_name, rect)
	return l

func button(id: String, value: String, action: Callable, rect: Dictionary = {}, cue: String = "ui.confirm") -> Button:
	var b := Button.new()
	b.text = value
	b.focus_mode = Control.FOCUS_ALL
	b.clip_text = true
	if director != null:
		director.bind_button(b, cue)
	b.pressed.connect(action)
	_add(b, id, rect if not rect.is_empty() else rect_of(id))
	buttons[id] = b
	return b

## A transparent click target over a sprite (cards): mouse only, never takes focus.
func hotspot(node_name: String, action: Callable, rect: Dictionary) -> Button:
	var b := Button.new()
	b.flat = true
	b.focus_mode = Control.FOCUS_NONE
	for state in ["normal", "hover", "pressed", "focus", "disabled"]:
		b.add_theme_stylebox_override(state, StyleBoxEmpty.new())
	b.pressed.connect(action)
	_add(b, node_name, rect)
	return b

func relayout() -> void:
	if not is_inside_tree():
		return
	var vp := get_viewport_rect().size
	var sc := maxf(1.0, floorf(SkinA.canvas_scale(vp)))
	var origin := SkinA.canvas_origin(vp, sc)
	backdrop.position = Vector2.ZERO
	backdrop.size = vp
	for item in _items:
		var c: Control = item[0]
		SkinA.place(c, item[1], sc, origin)
		if c is Label or c is Button:
			c.add_theme_font_size_override("font_size", int(int(c.get_meta("units", FONT_UNITS)) * sc))

## Chains the buttons of `order` (button ids; default the layout's focus_order) with wrap-around navigation.
func link_focus(order: Array = []) -> void:
	var chain: Array = []
	for id in (order if not order.is_empty() else SkinA.layout(screen).get("focus_order", [])):
		if buttons.has(id) and not buttons[id].disabled:
			chain.append(buttons[id])
	_focus_order = order
	for i in chain.size():
		var b: Button = chain[i]
		var prev: NodePath = b.get_path_to(chain[(i - 1 + chain.size()) % chain.size()])
		var next: NodePath = b.get_path_to(chain[(i + 1) % chain.size()])
		b.focus_neighbor_left = prev
		b.focus_neighbor_top = prev
		b.focus_neighbor_right = next
		b.focus_neighbor_bottom = next
		b.focus_previous = prev
		b.focus_next = next

func finish(order: Array = []) -> void:
	relayout()
	link_focus(order)
	focus_default()

## Restores the focus remembered by begin(), else the first enabled button of the layout's focus_order.
func focus_default() -> void:
	if not is_visible_in_tree():
		return
	var owner = get_viewport().gui_get_focus_owner()
	if owner != null and is_ancestor_of(owner):
		return
	var pick: Button = buttons.get(_focus_id)
	if pick == null or pick.disabled:
		pick = null
		for id in (_focus_order if not _focus_order.is_empty() else SkinA.layout(screen).get("focus_order", [])):
			if buttons.has(id) and not buttons[id].disabled:
				pick = buttons[id]
				break
	if pick != null:
		pick.grab_focus()

func has_button_focus() -> bool:
	var owner = get_viewport().gui_get_focus_owner() if is_inside_tree() else null
	return visible and owner != null and is_ancestor_of(owner)
