extends Control
## Reference-inspired HUD. Sidebar mode (canvas == null): portrait, HP/mana bars and 2 slots from the run formulas.
## In-canvas mode (canvas set, AD-014): HP/mana bars, 4 loadout slots with keycaps and a dash marker, render-only.
const Art = preload("res://ui/pixel_art_renderer.gd")
const MAGE = preload("res://assets/pixel/mage_sheet.png")
const KEY_LABELS := ["LMB","RMB","Q","E"] # mirrors the cast_slot_1..4 input map (ui/input_actions.gd)
const DASH_KEY := "SPACE" # mirrors the dash input action
const TICKS_PER_SECOND := 60.0
const SLOT_SIZE := 54.0
const SLOT_GAP := 10.0
const PANEL_PAD := 14.0
const DASH_GAP := 16.0
const PANEL_HEIGHT := 112.0
var flow
var session
var canvas

func _ready() -> void:
	if canvas != null:
		set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	else:
		custom_minimum_size = Vector2(277,124)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST

func _session():
	if canvas != null:
		return canvas.session
	if session != null:
		return session
	if flow != null:
		return flow.session
	return null

func slot_count() -> int:
	var live = _session()
	return live.sim.loadout.SLOT_COUNT if live != null else 4

func slot_view(i: int) -> Dictionary:
	var live = _session()
	if live == null or i < 0 or i >= slot_count():
		return {}
	var loadout = live.sim.loadout
	var preview: Dictionary = loadout.preview(i)
	var empty: bool = preview.is_empty()
	var formula: Dictionary = loadout.slots[i]["formula"]
	var cost: int = 0 if empty else int(preview["mana"])
	var cooldown_left: int = 0 if empty else int(loadout.slots[i]["cooldown"])
	var cooldown_max: int = 0 if empty else int(preview["cooldown"])
	var affordable: bool = empty or live.sim.mana >= float(cost)
	var state := "ready"
	if empty:
		state = "empty"
	elif cooldown_left > 0:
		state = "cooldown"
	elif not affordable:
		state = "no_mana"
	return {"key_label":KEY_LABELS[i] if i < KEY_LABELS.size() else "","locked":loadout.is_locked(i),"empty":empty,
		"name":"" if empty else str(formula.get("display_name","")),
		"element":"" if empty else str(formula.get("root",{}).get("essence_id","")).trim_prefix("essence."),
		"mana_cost":cost,"cooldown_left":cooldown_left,
		"cooldown_fraction":clampf(float(cooldown_left)/float(cooldown_max),0.0,1.0) if cooldown_max > 0 else 0.0,
		"affordable":affordable,"state":state}

func dash_view() -> Dictionary:
	var live = _session()
	if live == null:
		return {"ready":true,"cooldown_left":0,"cooldown_fraction":0.0}
	var left: int = int(live.player.dash_cooldown)
	var maximum: int = int(live.player.tuning["dash_cooldown_ticks"])
	return {"ready":left == 0,"cooldown_left":left,
		"cooldown_fraction":clampf(float(left)/float(maximum),0.0,1.0) if maximum > 0 else 0.0}

func _draw() -> void:
	if canvas != null:
		_draw_combat_panel()
		return
	draw_rect(Rect2(0,0,275,123),Color("#0b131b"))
	draw_rect(Rect2(0,0,275,123),Color("#b08042"),false,2)
	draw_rect(Rect2(5,5,265,113),Color("#564226"),false,1)
	draw_texture_rect_region(MAGE,Rect2(8,7,58,66),Rect2(0,0,48,56))
	if flow==null or flow.session==null:
		return
	var hp: float = flow.session.sim.actor.health.current
	var max_hp: float = flow.session.sim.actor.health.maximum
	var mana: float = flow.session.sim.mana
	var max_mana: float = float(flow.session.sim.settings["combat"]["player_max_mana"])
	_bar(Vector2(82,18),180,14,hp/maxf(1,max_hp),Color("#cb5552"),Color("#ee9862"))
	_bar(Vector2(82,42),180,13,mana/maxf(1,max_mana),Color("#2b8cbf"),Color("#83d8ff"))
	_text(Vector2(88,30),"HP  %d / %d" % [ceili(hp),int(max_hp)],Color("#fff1d4"),12)
	_text(Vector2(88,53),"MP  %d / %d" % [int(mana),int(max_mana)],Color("#eff8ff"),12)
	draw_line(Vector2(8,78),Vector2(266,78),Color("#826436"),1)
	for i in 2:
		var px := 14+i*131
		draw_rect(Rect2(px,82,119,35),Color("#132333"),true)
		draw_rect(Rect2(px,82,119,35),Color("#97703b"),false,1)
		var formula: Dictionary = flow.run.formulas[i]
		var element: String = str(formula["root"]["essence_id"]).trim_prefix("essence.")
		Art.icon(self,element,Vector2(px+2,83),Vector2(31,31))
		var label := str(formula["display_name"])
		if label.length()>11:
			label = label.substr(0,11)
		_text(Vector2(px+34,94),label,Color("#e9d5a8"),10)
		var plan = flow.session.sim.loadout.get_plan(i+1)
		var cost: int = int(plan.snapshot()["mana_cost"]) if plan!=null else 0
		_text(Vector2(px+34,109),"MP %d · SLOT %d" % [cost,i+1],Color("#91c2ce"),10)

func _bar(point: Vector2,width: float,height: float,percent: float,low: Color,high: Color) -> void:
	draw_rect(Rect2(point,Vector2(width,height)),Color("#080c12"))
	draw_rect(Rect2(point+Vector2(2,2),Vector2((width-4)*clampf(percent,0,1),height-4)),low)
	draw_line(point+Vector2(2,2),point+Vector2(maxf(2,2+(width-4)*clampf(percent,0,1)),2),high,2)
	draw_rect(Rect2(point,Vector2(width,height)),Color("#a47a43"),false,1)

func _text(where: Vector2,content: String,color: Color,font_size: int) -> void:
	draw_string(ThemeDB.fallback_font,where,content,HORIZONTAL_ALIGNMENT_LEFT,-1,font_size,color)

func _draw_combat_panel() -> void:
	var live = _session()
	if live == null:
		return
	var slots_width: float = slot_count()*SLOT_SIZE+(slot_count()-1)*SLOT_GAP
	var width: float = PANEL_PAD*2+slots_width+DASH_GAP+SLOT_SIZE
	var origin := Vector2(floorf((size.x-width)/2.0),size.y-PANEL_HEIGHT-8.0)
	draw_rect(Rect2(origin,Vector2(width,PANEL_HEIGHT)),Color("#0b131b",0.92))
	draw_rect(Rect2(origin,Vector2(width,PANEL_HEIGHT)),Color("#b08042"),false,2)
	draw_rect(Rect2(origin+Vector2(4,4),Vector2(width-8,PANEL_HEIGHT-8)),Color("#564226"),false,1)
	var hp: float = live.sim.actor.health.current
	var max_hp: float = live.sim.actor.health.maximum
	var mana: float = live.sim.mana
	var max_mana: float = float(live.sim.settings["combat"]["player_max_mana"])
	var bar_width: float = (width-PANEL_PAD*2-10.0)/2.0
	var bar_at := origin+Vector2(PANEL_PAD,10)
	_bar(bar_at,bar_width,16,hp/maxf(1,max_hp),Color("#cb5552"),Color("#ee9862"))
	_text(bar_at+Vector2(6,13),"HP %d/%d" % [ceili(hp),int(max_hp)],Color("#fff1d4"),11)
	_bar(bar_at+Vector2(bar_width+10,0),bar_width,16,mana/maxf(1,max_mana),Color("#2b8cbf"),Color("#83d8ff"))
	_text(bar_at+Vector2(bar_width+16,13),"MP %d/%d" % [int(mana),int(max_mana)],Color("#eff8ff"),11)
	var row_y: float = origin.y+36.0
	for i in slot_count():
		_draw_slot(Vector2(origin.x+PANEL_PAD+i*(SLOT_SIZE+SLOT_GAP),row_y),slot_view(i))
	_draw_dash(Vector2(origin.x+PANEL_PAD+slots_width+DASH_GAP,row_y),dash_view())

func _draw_slot(at: Vector2, view: Dictionary) -> void:
	var box := Rect2(at,Vector2(SLOT_SIZE,SLOT_SIZE))
	var state: String = view["state"]
	var border := Color("#97703b")
	if state == "no_mana":
		border = Color("#cb5552")
	elif state == "empty":
		border = Color("#564226")
	draw_rect(box,Color("#0b131b") if state == "empty" else Color("#132333"),true)
	if state == "empty":
		_text(at+Vector2(8,34),"EMPTY",Color("#6b6250"),11)
	else:
		var element: String = view["element"]
		var icon_at := at+Vector2(13,11)
		if not Art.ICONS.has(element):
			element = "rune"
		Art.icon(self,element,icon_at,Vector2(28,28))
		if state == "no_mana":
			draw_rect(Rect2(icon_at,Vector2(28,28)),Color("#2a0d10",0.45),true)
		if state == "cooldown":
			_sweep(box.get_center(),SLOT_SIZE/2.0-1.0,float(view["cooldown_fraction"]))
			_text(at+Vector2(11,32),"%.1f" % (float(view["cooldown_left"])/TICKS_PER_SECOND),Color("#fff1d4"),12)
		_text(at+Vector2(SLOT_SIZE/2.0-5.0,SLOT_SIZE-4),str(view["mana_cost"]),
			Color("#ff8f8f") if state == "no_mana" else Color("#83d8ff"),11)
	draw_rect(box,border,false,2 if state == "no_mana" else 1)
	_keycap(at+Vector2(2,2),str(view["key_label"]))
	if view["locked"]:
		_lock_mark(at+Vector2(SLOT_SIZE-14,3))

func _draw_dash(at: Vector2, view: Dictionary) -> void:
	var box := Rect2(at,Vector2(SLOT_SIZE,SLOT_SIZE))
	var ready: bool = view["ready"]
	draw_rect(box,Color("#132333"),true)
	Art.icon(self,"dodge",at+Vector2(13,11),Vector2(28,28))
	if not ready:
		_sweep(box.get_center(),SLOT_SIZE/2.0-1.0,float(view["cooldown_fraction"]))
	_text(at+Vector2(SLOT_SIZE/2.0-15.0,SLOT_SIZE-4),"DASH" if ready else "%.1f" % (float(view["cooldown_left"])/TICKS_PER_SECOND),
		Color("#8fe3c1") if ready else Color("#fff1d4"),11)
	draw_rect(box,Color("#5edfc3") if ready else Color("#97703b"),false,1)
	_keycap(at+Vector2(2,2),DASH_KEY)

func _sweep(center: Vector2, radius: float, fraction: float) -> void:
	# Dark wedge covering the remaining fraction, starting at 12 o'clock and shrinking clockwise as the cooldown ends.
	var steps: int = maxi(2,ceili(48.0*fraction))
	var points := PackedVector2Array([center])
	for k in steps+1:
		var angle: float = -PI/2.0+TAU*(1.0-fraction)+TAU*fraction*float(k)/float(steps)
		points.append(center+Vector2(cos(angle),sin(angle))*radius*1.45)
	var clipped := Geometry2D.intersect_polygons(points,PackedVector2Array([
		center+Vector2(-radius,-radius),center+Vector2(radius,-radius),center+Vector2(radius,radius),center+Vector2(-radius,radius)]))
	for poly in clipped:
		draw_colored_polygon(poly,Color("#05080c",0.68))

func _keycap(at: Vector2, label: String) -> void:
	var text_width: float = ThemeDB.fallback_font.get_string_size(label,HORIZONTAL_ALIGNMENT_LEFT,-1,10).x
	var cap := Rect2(at,Vector2(text_width+6,13))
	draw_rect(cap,Color("#05080c",0.9),true)
	draw_rect(cap,Color("#826436"),false,1)
	_text(at+Vector2(3,10.5),label,Color("#fff1d4"),10)

func _lock_mark(at: Vector2) -> void:
	draw_arc(at+Vector2(5,4),3.0,PI,TAU,10,Color("#e9d5a8"),1.5)
	draw_rect(Rect2(at+Vector2(0,4),Vector2(10,7)),Color("#b08042"),true)
	draw_rect(Rect2(at+Vector2(4,6),Vector2(2,3)),Color("#0b131b"),true)
