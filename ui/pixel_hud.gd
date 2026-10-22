extends Control
## Reference-inspired HUD portrait, HP/mana bars and 2 legal spell slots.
const Art = preload("res://ui/pixel_art_renderer.gd")
const MAGE = preload("res://assets/pixel/mage_sheet.png")
var flow

func _ready() -> void:
	custom_minimum_size = Vector2(277,124)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST

func _draw() -> void:
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
		var plan = flow.session.sim.loadout.get_plan(i)
		var cost: int = int(plan.snapshot()["mana_cost"]) if plan!=null else 0
		_text(Vector2(px+34,109),"MP %d · SLOT %d" % [cost,i+1],Color("#91c2ce"),10)

func _bar(point: Vector2,width: float,height: float,percent: float,low: Color,high: Color) -> void:
	draw_rect(Rect2(point,Vector2(width,height)),Color("#080c12"))
	draw_rect(Rect2(point+Vector2(2,2),Vector2((width-4)*clampf(percent,0,1),height-4)),low)
	draw_line(point+Vector2(2,2),point+Vector2(maxf(2,2+(width-4)*clampf(percent,0,1)),2),high,2)
	draw_rect(Rect2(point,Vector2(width,height)),Color("#a47a43"),false,1)

func _text(where: Vector2,content: String,color: Color,font_size: int) -> void:
	draw_string(ThemeDB.fallback_font,where,content,HORIZONTAL_ALIGNMENT_LEFT,-1,font_size,color)
