extends Control
## M1 spell sandbox with reference-guided pixel sprites; gameplay is untouched.
signal world_click(point: Vector2, button: int)
const Art = preload("res://ui/pixel_art_renderer.gd")
var runner
var hover := Vector2(420,340)
var selected_id := -1

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP
	clip_contents = true
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST

func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseMotion:
		hover = event.position
	elif event is InputEventMouseButton and event.pressed and event.button_index in [MOUSE_BUTTON_LEFT,MOUSE_BUTTON_RIGHT,MOUSE_BUTTON_MIDDLE]:
		world_click.emit(event.position,event.button_index)
		accept_event()

func _draw() -> void:
	Art.tile_floor(self,Rect2(Vector2.ZERO,size),Vector2.ZERO,0)
	draw_rect(Rect2(Vector2.ZERO,size),Color("#c39950"),false,2)
	if runner == null or not runner.initialized:
		return
	var tick: int = runner.clock.tick
	draw_line(runner.actor.position,hover,Color("#6fe1fa",0.18),1)
	Art.entity(self,"mage",runner.actor.position,tick,Vector2.ZERO,runner.active.size()>0 and tick%14<5)
	_label(runner.actor.position+Vector2(-19,-46),"MAGE",Color("#fbe1a9"),11)
	for t in runner.targets.all():
		if t.id == runner.actor.id:
			continue
		Art.entity(self,"dummy",t.position,tick,t.motion, false,false,not t.alive())
		if t.id == selected_id:
			draw_arc(t.position,t.radius+10,0,TAU,36,Color("#fbd287"),2)
		if t.alive() and not t.motion.is_zero_approx():
			draw_line(t.position,t.position+t.motion.normalized()*21,Color("#f9c579"),2)
		_label(t.position+Vector2(-15,-41),"#"+str(t.id),Color("#ffecbb"),12)
		draw_rect(Rect2(t.position+Vector2(-23,t.radius+7),Vector2(46,6)),Color("#13232a"))
		draw_rect(Rect2(t.position+Vector2(-22,t.radius+8),Vector2(44*maxf(0,t.health.current/t.health.maximum),4)),Color("#bf5448"))
		Art.status_icons(self,t,tick,t.position+Vector2(-15,t.radius+21))
	for entry in runner.active:
		var effect = entry["effect"]
		var kind := "fire"
		match str(effect.root["essence"]["id"]):
			"essence.water": kind = "water"
			"essence.lightning": kind = "lightning"
		if entry["kind"] == "orb":
			kind = "orb"
		Art.effect(self,kind,effect.position,tick,Vector2(40,40) if kind=="orb" else Vector2(33,33))
	for v in runner.visuals:
		var fade := clampf(float(int(v["until"])-tick)/20.0,0,1)
		if v["kind"] == "arc":
			draw_line(v["from"],v["to"],Color("#d4fdff",fade),3)
			Art.effect(self,"arc",(v["from"]+v["to"])/2.0,tick,Vector2(35,35),fade)
		else:
			Art.effect(self,"impact",v["position"],tick,
				Vector2(clampf(float(v["radius"])*2,32,105),clampf(float(v["radius"])*2,32,105)),fade)

func _label(at: Vector2, content: String, color: Color, font_size: int) -> void:
	draw_string(ThemeDB.fallback_font,at,content,HORIZONTAL_ALIGNMENT_LEFT,-1,font_size,color)
