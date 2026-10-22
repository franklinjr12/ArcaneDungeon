extends Control
## M2 primitive placeholder renderer; no combat rules in draw().
signal world_click(at: Vector2, button: int)
var session
var hover := Vector2(440,440)
var show_debug := false
var view_rect := Rect2(0,0,916,650)

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP
	clip_contents = true

func camera_offset() -> Vector2:
	if session == null:
		return Vector2.ZERO
	var arena: Rect2 = session.world.bounds
	var camera: Vector2 = session.sim.actor.position
	return Vector2(
		clampf(camera.x-size.x/2.0,arena.position.x,arena.end.x-size.x),
		clampf(camera.y-size.y/2.0,arena.position.y,arena.end.y-size.y))

func world_from_local(point: Vector2) -> Vector2:
	return point+camera_offset()

func local_from_world(point: Vector2) -> Vector2:
	return point-camera_offset()

func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseMotion:
		hover = world_from_local(event.position)
	if event is InputEventMouseButton and event.pressed and event.button_index in [MOUSE_BUTTON_LEFT,MOUSE_BUTTON_RIGHT]:
		world_click.emit(world_from_local(event.position),event.button_index)
		accept_event()

func _draw() -> void:
	draw_rect(Rect2(Vector2.ZERO,size),Color("#0e1927"))
	if session == null:
		return
	var offset := camera_offset()
	var arena: Rect2 = session.world.bounds
	for x in range(0,int(arena.size.x),56):
		draw_line(Vector2(x,0)-offset,Vector2(x,arena.size.y)-offset,Color("#283649"),1)
	for y in range(0,int(arena.size.y),56):
		draw_line(Vector2(0,y)-offset,Vector2(arena.size.x,y)-offset,Color("#283649"),1)
	draw_rect(Rect2(arena.position-offset,arena.size),Color("#718299"),false,3.0)
	for wall in session.world.walls:
		draw_rect(Rect2(wall.position-offset,wall.size),Color("#465268"))
		draw_rect(Rect2(wall.position-offset,wall.size),Color("#8495ac"),false,2)
	var mage = session.sim.actor
	var m: Vector2 = mage.position-offset
	draw_line(m,hover-offset,Color("#b7dfe6",0.30),1.0)
	draw_circle(m,mage.radius+3,Color("#e4f6ff") if session.player.invulnerable() else Color("#1b657d"))
	draw_circle(m,mage.radius,Color("#74d1d8") if session.player.hit_flash <= 0 or session.reduce_flashes else Color("#fafffd"))
	_health_bar(m,mage.radius+10,mage.health.current/mage.health.maximum)
	draw_line(m,m+session.player.facing*27,Color("#ecf4ff"),3)
	_label(m+Vector2(-17,-28),"MAGE",Color("#d9f7fb"))
	for enemy in session.enemies:
		var t = enemy.target
		var at: Vector2 = t.position-offset
		draw_circle(at,t.radius+2,Color("#151720"))
		draw_circle(at,t.radius,Color(str(enemy.tuning["color"])) if t.alive() else Color("#4b515e"))
		draw_line(at,at+Vector2.RIGHT.rotated(float(t.id)*1.4)*11,Color("#202939"),2)
		if t.alive():
			_health_bar(at,t.radius+8,t.health.current/t.health.maximum)
			_label(at+Vector2(-25,-t.radius-17),enemy.kind.to_upper(),Color("#f2e9eb"))
			var statuses: Array = t.status.snapshot(session.sim.clock.tick).keys()
			statuses.sort()
			if not statuses.is_empty():
				_label(at+Vector2(-21,t.radius+28),",".join(statuses),Color("#c9eef8"))
		if enemy.state == "windup" and enemy.intent != null:
			var intent: Dictionary = enemy.intent.snapshot()
			var time_left: int = maxi(0,int(enemy.tuning["telegraph_ticks"])-enemy.state_tick)
			var fraction: float = 1.0-float(time_left)/maxf(1,float(enemy.tuning["telegraph_ticks"]))
			# Contrast and text preserve meaning without relying on red tint.
			draw_arc(at,float(intent["range"]) if enemy.kind == "pursuer" else 33.0,0,TAU,48,Color("#efc273"),2.0+fraction*2.0)
			draw_line(at,session.sim.actor.position-offset,Color("#ecc48a",0.5+fraction*0.5),2)
			_label(at+Vector2(-28,-44),"! %d" % time_left,Color.WHITE)
		if show_debug:
			_label(at+Vector2(-28,46),"#%d %s" % [t.id,enemy.state],Color("#a5d2ff"))
			draw_arc(at,float(enemy.tuning["attack_range"]),0,TAU,48,Color("#8b9bcd",0.22),1)
	for shot in session.enemy_shots:
		var at: Vector2 = shot["position"]-offset
		draw_circle(at,float(shot["radius"]),Color("#f3a5ba"))
		draw_circle(at,3,Color("#fffafa"))
	for entry in session.sim.active:
		var effect = entry["effect"]
		var at: Vector2 = effect.position-offset
		var element_id: String = str(effect.root["essence"]["id"])
		var c := Color("#e9ac76")
		if element_id == "essence.water":
			c = Color("#79bcf8")
		elif element_id == "essence.lightning":
			c = Color("#f6e193")
		var radius: float = effect.radius if entry["kind"] == "projectile" else float(effect.root["params"]["orb_radius"])
		draw_circle(at,radius,c)
		draw_circle(at,3,Color.WHITE)
	for event in session.sim.visuals:
		var remaining := maxf(0,float(int(event["until"])-session.sim.clock.tick))
		var strength := clampf(remaining/18.0,0,1)
		if event["kind"] == "arc":
			draw_line(event["from"]-offset,event["to"]-offset,Color(0.9,0.95,1,strength),4)
			_label((event["from"]+event["to"])/2.0-offset,"ARC!",Color("#fff5af"))
		else:
			draw_arc(event["position"]-offset,float(event["radius"]),0,TAU,42,Color(0.84,0.96,1,strength),2)
	for message in session.feedback:
		var age: float = float(session.sim.clock.tick-int(message["tick"]))
		_label(message["position"]-offset+Vector2(-20,-28-age*.38),str(message["label"]),Color("#ffe3ab"))
	if show_debug:
		_label(Vector2(15,22),"DEBUG: solid walls / attack geometry / range / state",Color.WHITE)

func _label(point: Vector2, label: String, shade: Color) -> void:
	draw_string(ThemeDB.fallback_font,point,label,HORIZONTAL_ALIGNMENT_LEFT,-1,12,shade)

func _health_bar(center: Vector2, below: float, percent: float) -> void:
	draw_rect(Rect2(center+Vector2(-23,below),Vector2(46,5)),Color("#101a25"))
	draw_rect(Rect2(center+Vector2(-23,below),Vector2(46*clampf(percent,0,1),5)),Color("#f4a7a7"))
