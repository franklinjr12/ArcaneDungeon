extends Control
## Render-only reference-guided sprites. M2 and M3 collision/state remain authoritative.
signal world_click(at: Vector2, button: int)
const Art = preload("res://ui/pixel_art_renderer.gd")
const ReduceMotion = preload("res://ui/reduce_motion.gd")
const DamageNumbers = preload("res://ui/damage_numbers.gd")
var _damage_numbers = DamageNumbers.new()
var _damage_session = null
var _fx_memo: Dictionary = {}
var _fx_session = null
var _anim_memo: Dictionary = {}
var _anim_session = null
const SlotHUD = preload("res://ui/pixel_hud.gd")
const Lighting = preload("res://ui/lighting.gd")
const VfxLayer = preload("res://ui/vfx/vfx_layer.gd")
const HitFlashOverlay = preload("res://ui/vfx/hit_flash_overlay.gd")
const VfxData = preload("res://ui/vfx/vfx_data.gd")
var session
var settings = null
var hover := Vector2(440,440)
var show_debug := false
## AD-065 debug hitbox overlay colour (sim radii, not art).
const HITBOX_COLOR := Color("#ff4fd8")
var view_rect := Rect2(0,0,916,650)
var environment_id := 0
var last_player_at := Vector2.ZERO
var last_enemy_at: Dictionary = {}
var slot_hud
## AD-148: render-only lighting inputs (the run screen sets these from the room); defaults suit the sandbox.
var lighting_stage := 0
var lighting_room_type := "combat"
var lighting_props: Array = []
var lighting
## AD-149: render-only additive particles/glow and the actor hit-flash overlay (children above the arena, below the slot HUD).
var vfx
var hit_flash
## AD-091: the run screen sets this node's `scale` to texel/(2*physical scale) so one art texel is a whole number of
## physical pixels, and `size` to the visible world size. Node scale (not draw_set_transform) because the renderer resets the draw transform.
const FRAME_COLOR := Color("#0b1320")

func _ready() -> void:
	slot_hud = SlotHUD.new()
	slot_hud.name = "SlotHUD"
	slot_hud.canvas = self
	add_child(slot_hud)
	lighting = Lighting.new()
	lighting.name = "Lighting"
	add_child(lighting)
	lighting.setup(self)
	vfx = VfxLayer.new()
	vfx.name = "Vfx"
	add_child(vfx)
	vfx.setup(self)
	hit_flash = HitFlashOverlay.new()
	hit_flash.name = "HitFlash"
	add_child(hit_flash)
	move_child(slot_hud,get_child_count()-1)
	mouse_filter = Control.MOUSE_FILTER_STOP
	clip_contents = true
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST

## World-space size of the visible view (this node is scaled, so its size is already in world units).
func view_size() -> Vector2:
	return size

func camera_offset() -> Vector2:
	if session == null:
		return Vector2.ZERO
	var arena: Rect2 = session.world.bounds
	var camera: Vector2 = session.sim.actor.position
	var view := view_size()
	var base := Vector2(
		arena.get_center().x-view.x/2.0 if view.x >= arena.size.x else clampf(camera.x-view.x/2.0,arena.position.x,arena.end.x-view.x),
		arena.get_center().y-view.y/2.0 if view.y >= arena.size.y else clampf(camera.y-view.y/2.0,arena.position.y,arena.end.y-view.y)
	)
	return base+ReduceMotion.shake_offset(settings,session.player.hit_flash,session.sim.clock.tick)

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

## AD-089: the mage aim line is a short tick; the countdown label is debug-only.
const AIM_TICK_LEN := 24.0

static func countdown_visible(debug: bool) -> bool:
	return debug

static func aim_tick_segment(at: Vector2, hover: Vector2) -> Array:
	var dir := hover-at
	if dir.length() <= 0.001:
		return []
	var d := dir.normalized()
	return [at+d*14.0,at+d*(14.0+AIM_TICK_LEN)]

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
	Art.tile_floor(self,Rect2(Vector2.ZERO,view_size()),offset,environment_id)
	if session == null:
		lighting.hide_all()
		vfx.hide_all()
		hit_flash.set_entries([])
		return
	_draw_frame(Rect2(arena.position-offset,arena.size))
	Art.walls(self,session.world.walls,offset)
	Art.decorations(self,offset,environment_id)
	draw_rect(Rect2(arena.position-offset,arena.size),Color("#b48b52",0.55),false,2)
	if _anim_session != session:
		_anim_session = session
		_anim_memo = {"actors":{}}
	var mage = session.sim.actor
	var at: Vector2 = mage.position-offset
	var tick_seg := aim_tick_segment(at,hover-offset)
	if not tick_seg.is_empty():
		draw_line(tick_seg[0],tick_seg[1],Color("#6adbea",0.20),1)
	var actor_casting: bool = (session.sim.active.size()>0 or session.sim.is_channelling()) and tick%14<5
	var player_velocity: Vector2 = mage.position-last_player_at
	last_player_at = mage.position
	var mage_motion: Vector2 = session.player.dash_heading*16.0 if session.player.dash_left>0 else player_velocity
	var reduced := ReduceMotion.flashes_reduced(settings,session)
	var mage_hurt: bool = session.player.hit_flash>0 and not reduced
	var mage_tint := ReduceMotion.hurt_tint(reduced,session.player.hit_flash)
	var mage_anim := _mage_anim(mage,tick,player_velocity,mage_hurt)
	var flash_entries: Array = []
	var flash_total := int(VfxData.hit_flash_cfg().get("ticks",0))
	var mage_entry := mage_flash_entry(reduced,at,tick,mage_motion,mage_anim)
	if not mage_entry.is_empty():
		flash_entries.append(mage_entry)
	if session.player.invulnerable() and Art.iframe_outline_on(tick):
		for step in [Vector2.LEFT,Vector2.RIGHT,Vector2.UP,Vector2.DOWN]:
			Art.entity(self,"mage",at+step*2.0,tick,mage_motion,actor_casting,mage_hurt,not mage.alive(),Art.IFRAME_OUTLINE,mage_anim)
	Art.entity(self,"mage",at,tick,mage_motion,actor_casting,mage_hurt,not mage.alive(),mage_tint,mage_anim)
	_health_bar(at,25,mage.health.current/mage.health.maximum,Color("#da686e"))
	if show_debug:
		_label(at+Vector2(-17,-45),tr("combat.mage_label"),Color("#f8e7ba"))
		draw_arc(at,mage.radius,0.0,TAU,32,HITBOX_COLOR,1.0)
	Art.icon(self,"health",at+Vector2(-40,23),Vector2(15,15))
	Art.draw_water(self,session,offset)
	Art.draw_env_props(self,session,offset)
	Art.draw_hazards(self,session,offset)
	for enemy in session.enemies:
		var target = enemy.target
		var enemy_at: Vector2 = target.position-offset
		var enemy_mod: Color = Art.placeholder_modulate(enemy.kind,Color(str(enemy.tuning.get("color","#ffffff"))),enemy.get("intangible") == true,enemy.get("intangible_warning") == true and tick%6<3)
		var movement: Vector2 = target.position-last_enemy_at.get(target.id,target.position)
		last_enemy_at[target.id] = target.position
		if enemy.get("submerged") == true:
			# AD-198: a submerged boss is hidden; its emerge telegraph still comes from collect_fx.
			continue
		var dissolved: int = int(_fx_memo.get("dead",{}).get(target.id,tick+1))
		var enemy_anim := _enemy_anim(enemy,mage,tick,movement)
		if Art.actor_has_tag(enemy.kind,"death_side"):
			if not enemy_anim.is_empty():
				Art.entity(self,enemy.kind,enemy_at,tick,movement,false,false,not target.alive(),enemy_mod,enemy_anim)
		elif tick-dissolved < 20 or target.alive():
			Art.entity(self,enemy.kind,enemy_at,tick,movement,enemy.state=="windup",false,not target.alive(),enemy_mod)
		var hit_at = _anim_memo["actors"].get(target.id,{}).get("hit")
		if hit_at != null and target.alive() and not enemy_anim.is_empty():
			var enemy_flash := ReduceMotion.hit_flash_strength(reduced,flash_total-(tick-int(hit_at)),flash_total)
			if enemy_flash > 0.0:
				flash_entries.append({"kind":enemy.kind,"at":enemy_at,"tick":tick,"motion":movement,"anim":enemy_anim,"strength":enemy_flash})
		Art.draw_enemy_markers(self,enemy,enemy_at,tick,offset)
		if target.alive():
			_health_bar(enemy_at,target.radius+12,target.health.current/target.health.maximum,Color("#dc7060"))
			if enemy.kind == "undead_warden" or show_debug:
				_label(enemy_at+Vector2(-27,-(59 if enemy.kind=="undead_warden" else 45)),str(enemy.tuning.get("display_name",enemy.kind)),Color("#eec88b"))
		if enemy.state == "windup" and enemy.intent != null and target.alive():
			var intent: Dictionary = enemy.intent.snapshot()
			var time_left: int = maxi(0,int(enemy.tuning["telegraph_ticks"])-enemy.state_tick)
			if countdown_visible(show_debug):
				_label(enemy_at+Vector2(-26,-54),"! %d" % time_left,Color("#ffe4a0"))
		if show_debug and target.alive():
			draw_arc(enemy_at,target.radius,0.0,TAU,32,HITBOX_COLOR,1.0)
			_label(enemy_at+Vector2(-26,53),"#%d %s" % [target.id,enemy.state],Color("#b9e8fc"))
	if _fx_session != session:
		_fx_session = session
		_fx_memo = {}
	Art.draw_form_visuals(self,session.sim.visuals,offset,tick)
	var fx_list: Array = Art.collect_fx(session,tick,_fx_memo)
	for fx in fx_list:
		var fp := ReduceMotion.fx_draw_params(reduced,fx["event"],fx["age"])
		Art.draw_fx(self,fx["event"],fx["at"]-offset,fp["age"],fx["rotation"],fx["length"],fp["modulate"],fx["slot"],fx.get("uniform",0.0),int(fx.get("window",0)),float(fx.get("arc_degrees",0.0)))
	_draw_floating_text(offset,tick)
	_draw_death_banner()
	if show_debug:
		_label(Vector2(18,20),tr("combat.debug_geometry"),Color("#d6edf7"))
	lighting.sync(self,session,settings,lighting_stage,lighting_room_type,lighting_props)
	vfx.sync(self,session,settings,fx_list,tick)
	hit_flash.set_entries(flash_entries)

## AD-149: hit-flash overlay entry for the mage, or {} when there is nothing to flash (dead, expired or reduce-flash).
func mage_flash_entry(reduced: bool, at: Vector2, tick: int, motion: Vector2, anim: Dictionary) -> Dictionary:
	var strength := ReduceMotion.hit_flash_strength(reduced,session.player.hit_flash,int(session.player.tuning.get("hit_flash_ticks",1)))
	strength = maxf(strength,ReduceMotion.hit_flash_strength(reduced,session.player.perfect_flash,int(session.player.tuning.get("perfect_dodge_flash_ticks",1))))
	if not session.sim.actor.alive() or strength <= 0.0:
		return {}
	return {"kind":"mage","at":at,"tick":tick,"motion":motion,"anim":anim,"strength":strength}

## Dark frame around the arena when the view is larger than the arena bounds (extreme aspects).
func _draw_frame(arena_view: Rect2) -> void:
	var view := view_size()
	var pad := 4.0
	var left := arena_view.position.x
	var right := arena_view.end.x
	var top := arena_view.position.y
	var bottom := arena_view.end.y
	if left > 0.0:
		draw_rect(Rect2(-pad,-pad,left+pad,view.y+2.0*pad),FRAME_COLOR)
	if right < view.x:
		draw_rect(Rect2(right,-pad,view.x-right+pad,view.y+2.0*pad),FRAME_COLOR)
	if top > 0.0:
		draw_rect(Rect2(-pad,-pad,view.x+2.0*pad,top+pad),FRAME_COLOR)
	if bottom < view.y:
		draw_rect(Rect2(-pad,bottom,view.x+2.0*pad,view.y-bottom+pad),FRAME_COLOR)

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

## AD-093: damage numbers, status labels and 'ARC!' share one stacked layout so they never overlap.
func _draw_floating_text(offset: Vector2, tick: int) -> void:
	if session == null:
		return
	if _damage_session != session:
		_damage_session = session
		_damage_numbers.reset()
	_damage_numbers.update(session.sim.targets.all(),tick)
	var font := ThemeDB.fallback_font
	var items: Array = []
	var order := 0
	for popup in _damage_numbers.popups:
		var age: float = float(tick-int(popup["spawn_tick"]))
		var at: Vector2 = popup["position"]-offset+Vector2(-8,-34-age*DamageNumbers.RISE_PER_TICK-float(popup["index"])*12)
		var text: String = popup["text"]
		var width: float = Art.damage_glyph_width(popup["symbol"],text)
		items.append({"kind":"damage","popup":popup,"anchor":at+Vector2(-width/2.0,-7),"size":Vector2(width,DamageNumbers.LINE_HEIGHT),"group":popup["target_id"],"order":order})
		order += 1
	var arc_index := 0
	for visual in session.sim.visuals:
		if visual["kind"] == "arc":
			var text := tr("combat.arc")
			var size := font.get_string_size(text,HORIZONTAL_ALIGNMENT_LEFT,-1,12)
			var at: Vector2 = (visual["from"]+visual["to"])/2.0-offset+Vector2(-12,-15)
			items.append({"kind":"label","text":text,"color":Color("#ffeda4"),"anchor":at-Vector2(0,font.get_ascent(12)),"size":size,"group":"arc%d" % arc_index,"order":order})
			arc_index += 1
			order += 1
	for item in session.feedback:
		var text := str(item["label"])
		if text.begins_with("DEFEAT"):
			continue
		var age: float = float(tick-int(item["tick"]))
		var size := font.get_string_size(text,HORIZONTAL_ALIGNMENT_LEFT,-1,12)
		var at: Vector2 = item["position"]-offset+Vector2(-24,-30-age*.38)
		items.append({"kind":"label","text":text,"color":Color("#ffdf95"),"anchor":at-Vector2(0,font.get_ascent(12)),"size":size,"group":_group_near(item["position"]),"order":order})
		order += 1
	var rects := DamageNumbers.stack_layout(items)
	for i in items.size():
		var item: Dictionary = items[i]
		if item["kind"] == "damage":
			Art.draw_damage_number(self,item["popup"]["symbol"],item["popup"]["text"],rects[i].position,item["popup"]["color"])
		else:
			_label(rects[i].position+Vector2(0,font.get_ascent(12)),item["text"],item["color"])

## Group key for a world position: nearest live enemy id, the mage within 40 units, else the position itself.
func _group_near(world: Vector2) -> Variant:
	var best: Variant = null
	var best_d := 40.0
	for enemy in session.enemies:
		var d: float = enemy.target.position.distance_to(world)
		if enemy.target.alive() and d <= best_d:
			best_d = d
			best = enemy.target.id
	if best == null and session.sim.actor.position.distance_to(world) <= 40.0:
		return "mage"
	return best if best != null else "pos%d,%d" % [roundi(world.x),roundi(world.y)]

## AD-093: death text is a screen-centre banner, never anchored to the mage.
func _draw_death_banner() -> void:
	if session == null or session.sim.actor.alive():
		return
	var font := ThemeDB.fallback_font
	var text := tr("combat.defeated")
	var size := font.get_string_size(text,HORIZONTAL_ALIGNMENT_LEFT,-1,28)
	var view := view_size()
	var box := Rect2(Vector2((view.x-size.x)/2.0-16,view.y*0.22-size.y/2.0-8),size+Vector2(32,16))
	draw_rect(box,Color(0.04,0.06,0.09,0.85))
	draw_rect(box,Color("#a17b41"),false,1)
	draw_string(font,Vector2(box.position.x+16,box.position.y+8+font.get_ascent(28)),text,HORIZONTAL_ALIGNMENT_LEFT,-1,28,Color("#f08a8a"))

func _label(point: Vector2, label: String, shade: Color) -> void:
	draw_string(ThemeDB.fallback_font,point,label,HORIZONTAL_ALIGNMENT_LEFT,-1,12,shade)

func _health_bar(center: Vector2, below: float, percent: float, tint: Color) -> void:
	draw_rect(Rect2(center+Vector2(-26,below),Vector2(52,7)),Color("#0b1219"))
	draw_rect(Rect2(center+Vector2(-25,below+1),Vector2(50*clampf(percent,0,1),5)),tint)
	draw_rect(Rect2(center+Vector2(-26,below),Vector2(52,7)),Color("#a17b41"),false,1)
