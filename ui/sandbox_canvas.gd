extends Control
## M1 debug primitives only; simulation rules live in SpellRunner.
signal world_click(point: Vector2, button: int)
var runner
var hover := Vector2(420,340)
var selected_id := -1

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP
	clip_contents = true

func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseMotion:
		hover = event.position
	elif event is InputEventMouseButton and event.pressed and event.button_index in [MOUSE_BUTTON_LEFT,MOUSE_BUTTON_RIGHT,MOUSE_BUTTON_MIDDLE]:
		world_click.emit(event.position,event.button_index)
		accept_event()

func _draw() -> void:
	draw_rect(Rect2(Vector2.ZERO,size),Color("#111c2b"))
	for x in range(0,int(size.x),40):
		draw_line(Vector2(x,0),Vector2(x,size.y),Color("#233248"),1)
	for y in range(0,int(size.y),40):
		draw_line(Vector2(0,y),Vector2(size.x,y),Color("#233248"),1)
	draw_rect(Rect2(Vector2.ZERO,size-Vector2.ONE),Color("#5c748e"),false,2)
	if runner == null or not runner.initialized:
		return
	draw_line(runner.actor.position,hover,Color(0.65,0.75,0.9,0.25),1)
	draw_circle(runner.actor.position,18,Color("#6ccddd"))
	draw_circle(runner.actor.position,8,Color.WHITE)
	_label(runner.actor.position+Vector2(-18,-26),"MAGE",Color("#b6edf1"),11)
	for t in runner.targets.all():
		if t.id == runner.actor.id:
			continue
		draw_circle(t.position,t.radius,Color("#a76376") if t.alive() else Color("#425269"))
		draw_circle(t.position,maxf(1,t.radius-5),Color("#3c4056"))
		if t.id == selected_id:
			draw_arc(t.position,t.radius+7,0,TAU,36,Color("#fbd287"),2)
		if t.alive() and not t.motion.is_zero_approx():
			draw_line(t.position,t.position+t.motion.normalized()*21,Color("#ffe5a5"),2)
		_label(t.position+Vector2(-15,-27),"#"+str(t.id),Color("#e1edfa"),12)
		draw_rect(Rect2(t.position+Vector2(-23,t.radius+7),Vector2(46,5)),Color("#36465a"))
		draw_rect(Rect2(t.position+Vector2(-23,t.radius+7),Vector2(46*maxf(0,t.health.current/t.health.maximum),5)),Color("#e07788"))
		var states: Array = t.status.snapshot(runner.clock.tick).keys()
		states.sort()
		if not states.is_empty():
			_label(t.position+Vector2(-24,t.radius+27),",".join(states),Color("#9ed7ff"),11)
	for entry in runner.active:
		var effect = entry["effect"]
		var tint := Color("#f7a16d")
		match effect.root["essence"]["id"]:
			"essence.water": tint = Color("#6eacff")
			"essence.lightning": tint = Color("#efdc80")
		var radius: float = effect.radius if entry["kind"] == "projectile" else float(effect.root["params"]["orb_radius"])
		draw_circle(effect.position,radius,tint)
		draw_circle(effect.position,maxf(2,radius*0.42),Color.WHITE)
	for v in runner.visuals:
		var fade := clampf(float(int(v["until"])-runner.clock.tick)/20.0,0,1)
		if v["kind"] == "arc":
			draw_line(v["from"],v["to"],Color(0.83,0.95,1,fade),4)
		else:
			draw_arc(v["position"],float(v["radius"]),0,TAU,48,Color(0.84,0.96,1,fade),2)

func _label(at: Vector2, content: String, color: Color, font_size: int) -> void:
	draw_string(ThemeDB.fallback_font,at,content,HORIZONTAL_ALIGNMENT_LEFT,-1,font_size,color)
