extends Control
## Render-only reference-guided sprites. M2 and M3 collision/state remain authoritative.
signal world_click(at: Vector2, button: int)
const Art = preload("res://ui/pixel_art_renderer.gd")
const DamageNumbers = preload("res://ui/damage_numbers.gd")
var _damage_numbers = DamageNumbers.new()
var _damage_session = null
var _fx_memo: Dictionary = {}
var _fx_session = null
var _anim_memo: Dictionary = {}
var _anim_session = null
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
	if _anim_session != session:
		_anim_session = session
		_anim_memo = {"actors":{}}
	var mage = session.sim.actor
	var at: Vector2 = mage.position-offset
	draw_line(at,hover-offset,Color("#6adbea",0.20),1)
	var actor_casting: bool = session.sim.active.size()>0 and tick%14<5
	var player_velocity: Vector2 = mage.position-last_player_at
	last_player_at = mage.position
	var mage_motion: Vector2 = session.player.dash_heading*16.0 if session.player.dash_left>0 else player_velocity
	var mage_hurt: bool = session.player.hit_flash>0 and not session.reduce_flashes
	var mage_anim := _mage_anim(mage,tick,player_velocity,mage_hurt)
	if session.player.invulnerable() and Art.iframe_outline_on(tick):
		for step in [Vector2.LEFT,Vector2.RIGHT,Vector2.UP,Vector2.DOWN]:
			Art.entity(self,"mage",at+step*2.0,tick,mage_motion,actor_casting,mage_hurt,not mage.alive(),Art.IFRAME_OUTLINE,mage_anim)
	Art.entity(self,"mage",at,tick,mage_motion,actor_casting,mage_hurt,not mage.alive(),Color.WHITE,mage_anim)
	_health_bar(at,25,mage.health.current/mage.health.maximum,Color("#da686e"))
	if show_debug:
		_label(at+Vector2(-17,-45),"MAGE",Color("#f8e7ba"))
	Art.icon(self,"health",at+Vector2(-40,23),Vector2(15,15))
	for enemy in session.enemies:
		var target = enemy.target
		var enemy_at: Vector2 = target.position-offset
		var movement: Vector2 = target.position-last_enemy_at.get(target.id,target.position)
		last_enemy_at[target.id] = target.position
		var dissolved: int = int(_fx_memo.get("dead",{}).get(target.id,tick+1))
		var enemy_anim := _enemy_anim(enemy,mage,tick,movement)
		if Art.actor_has_tag(enemy.kind,"death_side"):
			if not enemy_anim.is_empty():
				Art.entity(self,enemy.kind,enemy_at,tick,movement,false,false,not target.alive(),Color.WHITE,enemy_anim)
		elif tick-dissolved < 20 or target.alive():
			Art.entity(self,enemy.kind,enemy_at,tick,movement,enemy.state=="windup",false,not target.alive())
		if target.alive():
			_health_bar(enemy_at,target.radius+12,target.health.current/target.health.maximum,Color("#dc7060"))
			if enemy.kind == "undead_warden" or show_debug:
				_label(enemy_at+Vector2(-27,-(59 if enemy.kind=="undead_warden" else 45)),str(enemy.tuning.get("display_name",enemy.kind)),Color("#eec88b"))
		if enemy.state == "windup" and enemy.intent != null and target.alive():
			var intent: Dictionary = enemy.intent.snapshot()
			var time_left: int = maxi(0,int(enemy.tuning["telegraph_ticks"])-enemy.state_tick)
			var f: float = 1.0-float(time_left)/maxf(1.0,float(enemy.tuning["telegraph_ticks"]))
			_label(enemy_at+Vector2(-26,-54),"! %d" % time_left,Color("#ffe4a0"))
		if show_debug and target.alive():
			_label(enemy_at+Vector2(-26,53),"#%d %s" % [target.id,enemy.state],Color("#b9e8fc"))
	if _fx_session != session:
		_fx_session = session
		_fx_memo = {}
	for fx in Art.collect_fx(session,tick,_fx_memo):
		Art.draw_fx(self,fx["event"],fx["at"]-offset,fx["age"],fx["rotation"],fx["length"],Color.WHITE,fx["slot"],fx.get("uniform",0.0))
	for visual in session.sim.visuals:
		if visual["kind"] == "arc":
			_label((visual["from"]+visual["to"])/2.0-offset+Vector2(-12,-15),"ARC!",Color("#ffeda4"))
	for item in session.feedback:
		var age: float = float(tick-int(item["tick"]))
		_label(item["position"]-offset+Vector2(-24,-30-age*.38),str(item["label"]),Color("#ffdf95"))
	_draw_damage_numbers(offset,tick)
	if show_debug:
		_label(Vector2(18,20),"DEBUG: wall/attack geometry and live target state",Color("#d6edf7"))

## AD-065 mage animation, read-only on the sim; one-shot starts live in _anim_memo.
func _mage_anim(mage, tick: int, velocity: Vector2, hurt: bool) -> Dictionary:
	var m: Dictionary = _anim_memo
	var facing := Art.mage_facing(hover-mage.position)
	var dir: String = facing["dir"]
	var face: bool = facing["face_left"]
	var player = session.player
	var paid: int = session.sim.trace.filter_records(-1,"","cost_paid").size()
	var seen_paid: int = int(m.get("paid",paid))
	if paid > seen_paid:
		m["cast_start"] = tick
	m["paid"] = paid
	var flash: int = player.hit_flash
	if flash > int(m.get("flash",0)):
		m["hit_start"] = tick
	m["flash"] = flash
	if not mage.alive():
		if not m.has("dead"):
			m["dead"] = tick
		return {"tag":"death_"+dir,"elapsed":tick-int(m["dead"]),"face_left":face}
	m.erase("dead")
	if hurt:
		return {"tag":"hit_"+dir,"elapsed":tick-int(m.get("hit_start",tick)),"face_left":face}
	if player.dash_left > 0:
		var duration := int(player.tuning["dash_duration_ticks"])
		var frames := Art.actor_tag_frames("mage","dash_"+dir)
		return {"tag":"dash_"+dir,"index":Art.stretched_index(duration-player.dash_left,duration,frames),"face_left":face}
	if m.has("cast_start") and tick-int(m["cast_start"]) < Art.actor_tag_ticks("mage","cast_"+dir):
		return {"tag":"cast_"+dir,"elapsed":tick-int(m["cast_start"]),"face_left":face}
	return {"tag":("walk_" if velocity.length() > 0.5 else "idle_")+dir,"elapsed":tick,"loop":true,"face_left":face}

## AD-065 enemy/warden animation from AI state. Telegraph is stretched over the sim windup
## (tuning["telegraph_ticks"]) so the read and the hit line up. Returns {} when nothing is drawn.
func _enemy_anim(enemy, mage, tick: int, movement: Vector2) -> Dictionary:
	var kind: String = enemy.kind
	if not Art.actor_has_tag(kind,"idle_side"):
		return {}
	var target = enemy.target
	var warden: bool = kind == "undead_warden"
	var memos: Dictionary = _anim_memo["actors"]
	if not memos.has(target.id):
		memos[target.id] = {"seen":tick,"hp":target.health.current,"phase":enemy.phase if warden else 1}
	var e: Dictionary = memos[target.id]
	if target.health.current < float(e["hp"]):
		e["hit"] = tick
	e["hp"] = target.health.current
	if warden:
		if enemy.phase == 2 and int(e["phase"]) != 2:
			e["phase_start"] = tick
		e["phase"] = enemy.phase
	var face: bool = mage.position.x < target.position.x
	if not target.alive():
		if not e.has("dead"):
			e["dead"] = tick
		var elapsed: int = tick-int(e["dead"])
		if elapsed >= Art.actor_tag_ticks(kind,"death_side"):
			return {}
		return {"tag":"death_side","elapsed":elapsed,"face_left":face}
	if Art.actor_has_tag(kind,"spawn_side") and tick-int(e["seen"]) < Art.actor_tag_ticks(kind,"spawn_side"):
		return {"tag":"spawn_side","elapsed":tick-int(e["seen"]),"face_left":face}
	if e.has("hit") and tick-int(e["hit"]) < Art.actor_tag_ticks(kind,"hit_side"):
		return {"tag":"hit_side","elapsed":tick-int(e["hit"]),"face_left":face}
	var radial: bool = warden and enemy.intent != null and enemy.intent.snapshot()["kind"] == "radial"
	if enemy.state == "windup":
		var tag := "telegraph_side"
		if warden:
			tag = "telegraph_burst_side" if radial else "telegraph_dash_side"
		var window := int(enemy.tuning["telegraph_ticks"])
		return {"tag":tag,"index":Art.stretched_index(enemy.state_tick,window,Art.actor_tag_frames(kind,tag)),"face_left":face}
	if warden and e.has("phase_start") and tick-int(e["phase_start"]) < Art.actor_tag_ticks(kind,"phase_side"):
		return {"tag":"phase_side","elapsed":tick-int(e["phase_start"]),"face_left":face}
	if enemy.state == "recover":
		var attack := "attack_side"
		if warden:
			attack = "burst_side" if radial else "dash_side"
		return {"tag":attack,"elapsed":int(enemy.state_tick),"face_left":face}
	return {"tag":"move_side" if movement.length() > 0.5 else "idle_side","elapsed":tick,"loop":true,"face_left":face}

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
		var width: float = Art.damage_glyph_width(popup["symbol"],text)
		Art.draw_damage_number(self,popup["symbol"],text,at+Vector2(-width/2.0,-7))

func _label(point: Vector2, label: String, shade: Color) -> void:
	draw_string(ThemeDB.fallback_font,point,label,HORIZONTAL_ALIGNMENT_LEFT,-1,12,shade)

func _health_bar(center: Vector2, below: float, percent: float, tint: Color) -> void:
	draw_rect(Rect2(center+Vector2(-26,below),Vector2(52,7)),Color("#0b1219"))
	draw_rect(Rect2(center+Vector2(-25,below+1),Vector2(50*clampf(percent,0,1),5)),tint)
	draw_rect(Rect2(center+Vector2(-26,below),Vector2(52,7)),Color("#a17b41"),false,1)
