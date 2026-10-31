extends Control
## Render-only reference-guided sprites. M2 and M3 collision/state remain authoritative.
signal world_click(at: Vector2, button: int)
const Art = preload("res://ui/pixel_art_renderer.gd")
const DamageNumbers = preload("res://ui/damage_numbers.gd")
var _damage_numbers = DamageNumbers.new()
var _damage_session = null
var _fx_memo: Dictionary = {}
var _fx_session = null
const SlotHUD = preload("res://ui/pixel_hud.gd")
var session
var hover := Vector2(440,440)
var show_debug := false
var view_rect := Rect2(0,0,916,650)
var environment_id := 0
var last_player_at := Vector2.ZERO
var last_enemy_at: Dictionary = {}
var slot_hud

func _ready() -> void:
	slot_hud = SlotHUD.new()
	slot_hud.name = "SlotHUD"
	slot_hud.canvas = self
	add_child(slot_hud)
	mouse_filter = Control.MOUSE_FILTER_STOP
	clip_contents = true
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST

func camera_offset() -> Vector2:
	if session == null:
		return Vector2.ZERO
	var arena: Rect2 = session.world.bounds
	var camera: Vector2 = session.sim.actor.position
	return Vector2(
		clampf(camera.x-size.x/2.0,arena.position.x,maxf(arena.position.x,arena.end.x-size.x)),
		clampf(camera.y-size.y/2.0,arena.position.y,maxf(arena.position.y,arena.end.y-size.y)))

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
	if slot_hud != null:
		slot_hud.queue_redraw()
	var arena := Rect2(Vector2.ZERO,Vector2(1320,900))
	var offset := Vector2.ZERO
	var tick := 0
	if session != null:
		arena = session.world.bounds
		offset = camera_offset()
		tick = session.sim.clock.tick
	Art.tile_floor(self,Rect2(Vector2.ZERO,size),offset,environment_id)
	if session == null:
		return
	Art.walls(self,session.world.walls,offset)
	Art.decorations(self,offset,environment_id)
	draw_rect(Rect2(arena.position-offset,arena.size),Color("#b48b52",0.55),false,2)
	var mage = session.sim.actor
	var at: Vector2 = mage.position-offset
	draw_line(at,hover-offset,Color("#6adbea",0.20),1)
	var actor_casting: bool = session.sim.active.size()>0 and tick%14<5
	var player_velocity: Vector2 = mage.position-last_player_at
	last_player_at = mage.position
	Art.entity(self,"mage",at,tick,session.player.dash_heading*16.0 if session.player.dash_left>0 else player_velocity,
		actor_casting,session.player.hit_flash>0 and not session.reduce_flashes,not mage.alive())
	if session.player.invulnerable():
		Art.effect(self,"dodge",at,tick,Vector2(65,65),0.85)
	_health_bar(at,25,mage.health.current/mage.health.maximum,Color("#da686e"))
	if show_debug:
		_label(at+Vector2(-17,-45),"MAGE",Color("#f8e7ba"))
	Art.icon(self,"health",at+Vector2(-40,23),Vector2(15,15))
	for enemy in session.enemies:
		var target = enemy.target
		var enemy_at: Vector2 = target.position-offset
		var movement: Vector2 = target.position-last_enemy_at.get(target.id,target.position)
		last_enemy_at[target.id] = target.position
		Art.entity(self,enemy.kind,enemy_at,tick,movement,enemy.state=="windup",false,not target.alive())
		if target.alive():
			_health_bar(enemy_at,target.radius+12,target.health.current/target.health.maximum,Color("#dc7060"))
			if enemy.kind == "undead_warden" or show_debug:
				_label(enemy_at+Vector2(-27,-(59 if enemy.kind=="undead_warden" else 45)),str(enemy.tuning.get("display_name",enemy.kind)),Color("#eec88b"))
		if enemy.state == "windup" and enemy.intent != null and target.alive():
			var intent: Dictionary = enemy.intent.snapshot()
			var time_left: int = maxi(0,int(enemy.tuning["telegraph_ticks"])-enemy.state_tick)
			var f: float = 1.0-float(time_left)/maxf(1.0,float(enemy.tuning["telegraph_ticks"]))
			var radius: float = float(intent["range"]) if enemy.kind in ["bone_thrall","undead_warden"] else 33.0
			draw_arc(enemy_at,radius,0,TAU,56,Color("#e9ad56",0.55+0.4*f),2.0+f*2.5)
			draw_line(enemy_at,mage.position-offset,Color("#f7b765",0.35+0.3*f),1.7)
			_label(enemy_at+Vector2(-26,-54),"! %d" % time_left,Color("#ffe4a0"))
		if show_debug and target.alive():
			_label(enemy_at+Vector2(-26,53),"#%d %s" % [target.id,enemy.state],Color("#b9e8fc"))
	for shot in session.enemy_shots:
		Art.effect(self,"enemy",shot["position"]-offset,tick,Vector2(28,28))
	if _fx_session != session:
		_fx_session = session
		_fx_memo = {}
	for fx in Art.collect_fx(session,tick,_fx_memo):
		Art.draw_fx(self,fx["event"],fx["at"]-offset,fx["age"],fx["rotation"],fx["length"],Color.WHITE,fx["slot"])
	for visual in session.sim.visuals:
		if visual["kind"] == "arc":
			_label((visual["from"]+visual["to"])/2.0-offset+Vector2(-12,-15),"ARC!",Color("#ffeda4"))
	for item in session.feedback:
		var age: float = float(tick-int(item["tick"]))
		_label(item["position"]-offset+Vector2(-24,-30-age*.38),str(item["label"]),Color("#ffdf95"))
	_draw_damage_numbers(offset,tick)
	if show_debug:
		_label(Vector2(18,20),"DEBUG: wall/attack geometry and live target state",Color("#d6edf7"))

func _draw_damage_numbers(offset: Vector2, tick: int) -> void:
	if session == null:
		return
	if _damage_session != session:
		_damage_session = session
		_damage_numbers.reset()
	_damage_numbers.update(session.sim.targets.all(),tick)
	for popup in _damage_numbers.popups:
		var age: float = float(tick-int(popup["spawn_tick"]))
		var at: Vector2 = popup["position"]-offset+Vector2(-8,-34-age*DamageNumbers.RISE_PER_TICK-float(popup["index"])*12)
		var text: String = popup["text"]
		var width := ThemeDB.fallback_font.get_string_size(text,HORIZONTAL_ALIGNMENT_LEFT,-1,14).x
		var start := at-Vector2(width/2.0,0)
		if popup["symbol"] != "":
			Art.damage_symbol(self,popup["symbol"],start+Vector2(-7,-5),10.0,popup["color"])
		draw_string(ThemeDB.fallback_font,start,text,HORIZONTAL_ALIGNMENT_LEFT,-1,14,popup["color"])

func _label(point: Vector2, label: String, shade: Color) -> void:
	draw_string(ThemeDB.fallback_font,point,label,HORIZONTAL_ALIGNMENT_LEFT,-1,12,shade)

func _health_bar(center: Vector2, below: float, percent: float, tint: Color) -> void:
	draw_rect(Rect2(center+Vector2(-26,below),Vector2(52,7)),Color("#0b1219"))
	draw_rect(Rect2(center+Vector2(-25,below+1),Vector2(50*clampf(percent,0,1),5)),tint)
	draw_rect(Rect2(center+Vector2(-26,below),Vector2(52,7)),Color("#a17b41"),false,1)
