extends Control
## AD-153: skin A in-run HUD (ad_ui_screen_hud_layout.json): HP/MP + statuses top-left, boss bar top-centre, stage/coins/artifacts
## top-right, spell slots + dash bottom-centre. Render-only (reads the session, never writes it), so visuals cannot change sim timing.
const Art = preload("res://ui/pixel_art_renderer.gd")
const SkinA = preload("res://ui/skin_a.gd")
const KEY_LABELS := ["hud.key.lmb","hud.key.rmb","Q","E"] # mirrors the cast_slot_1..4 input map (ui/input_actions.gd)
const DASH_KEY := "hud.key.space" # mirrors the dash input action
const TICKS_PER_SECOND := 60.0
const MIN_FONT_SIZE := 14 # smallest legible text at 1280x720
const STATUS_SLOTS := 3
const ARTIFACT_SLOTS := 4
const SLOT_SPRITES := {"selected":"ad_ui_slot24_selected","ready":"ad_ui_slot24_ready","cooldown":"ad_ui_slot24_cooldown",
	"no_mana":"ad_ui_slot24_no_mana","empty":"ad_ui_slot24_empty"}
const ANCHOR_LEFT := ["ico_hp","bar_hp","txt_hp","ico_mana","bar_mp","txt_mp","status_"]
const ANCHOR_TOP := ["boss_","bar_boss"]
const ANCHOR_RIGHT := ["plate_stage","txt_stage","ico_coin","txt_coins","artifact_"]
const SHADOW := Color("#0b1320")
var flow
var session
var canvas
## Fallback stage text for rooms without stage/room numbers; set by the run screen.
var room_title := ""
var _widgets: Dictionary = {}

func _ready() -> void:
	if canvas != null:
		canvas.resized.connect(fit_to_canvas)
		fit_to_canvas()
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST

## Covers the whole canvas in physical pixels. The canvas node is scaled by the arena zoom, so this counter-scales.
func fit_to_canvas() -> void:
	if canvas == null:
		return
	var k: float = 1.0/maxf(canvas.scale.x,0.01)
	scale = Vector2(k,k)
	size = canvas.size/k
	position = Vector2.ZERO
	queue_redraw()

## Integer HUD scale from the window size (the arena area is a few px smaller than the window).
func hud_scale() -> float:
	var view: Vector2 = get_viewport_rect().size if is_inside_tree() else Vector2(1280,720)
	return floorf(SkinA.canvas_scale(view))

func _session():
	if canvas != null:
		return canvas.session
	if session != null:
		return session
	if flow != null:
		return flow.session
	return null

func _run_flow():
	if flow != null:
		return flow
	return canvas.get("run_flow") if canvas != null else null

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
	return {"key_label":tr(KEY_LABELS[i]) if i < KEY_LABELS.size() else "","locked":loadout.is_locked(i),"empty":empty,
		"name":"" if empty else str(formula.get("display_name","")),
		"element":"" if empty else str(formula.get("root",{}).get("essence_id","")).trim_prefix("essence."),
		"mana_cost":cost,"cooldown_left":cooldown_left,
		"cooldown_fraction":clampf(float(cooldown_left)/float(cooldown_max),0.0,1.0) if cooldown_max > 0 else 0.0,
		"affordable":affordable,"state":state}

func dash_view() -> Dictionary:
	var live = _session()
	if live == null:
		return {"ready":true,"cooldown_left":0,"cooldown_fraction":0.0,"charges":1}
	var left: int = int(live.player.dash_cooldown)
	var maximum: int = int(live.player.tuning["dash_cooldown_ticks"])
	return {"ready":left == 0,"cooldown_left":left,
		"cooldown_fraction":clampf(float(left)/float(maximum),0.0,1.0) if maximum > 0 else 0.0,
		"charges":(1 if left == 0 else 0)+int(live.player.bonus_dashes_left)}

## Boss shown in the top-centre block: the first living boss of the session, or {}.
func boss_view() -> Dictionary:
	var live = _session()
	if live == null:
		return {}
	for enemy in live.enemies:
		if "boss" in enemy.target.tags and enemy.target.health.alive():
			var health = enemy.target.health
			return {"name":tr("compendium.enemy."+str(enemy.kind)),"fraction":clampf(health.current/maxf(1.0,health.maximum),0.0,1.0),
				"statuses":status_views(enemy.target)}
	return {}

## Active statuses of a target as [{id, seconds}] in stable id order, capped to the layout's status slots.
func status_views(target) -> Array:
	var live = _session()
	var out: Array = []
	if live == null or target == null:
		return out
	var now: int = live.sim.clock.tick
	var states: Dictionary = target.status.snapshot(now)
	var ids := states.keys()
	ids.sort()
	for id in ids:
		out.append({"id":str(id),"seconds":ceili(float(int(states[id]["expires_tick"])-now)/TICKS_PER_SECOND)})
	return out.slice(0,STATUS_SLOTS)

func artifact_ids() -> Array:
	var running = _run_flow()
	if running == null or running.run == null:
		return []
	return running.run.artifacts.slice(0,ARTIFACT_SLOTS)

func stage_text() -> String:
	var running = _run_flow()
	if running == null or running.room == null:
		return ""
	var values: Dictionary = running.room.values
	if values.has("stage") and values.has("room"):
		return tr("hud.stage") % [int(values["stage"])+1,int(values["room"])+1]
	return room_title

func _draw() -> void:
	var live = _session()
	if live == null:
		return
	if _widgets.is_empty():
		_widgets = SkinA.widgets_by_id("hud")
	var sc: float = hud_scale()
	_draw_vitals(live,sc)
	_draw_statuses("status_",status_views(live.sim.actor),sc)
	var boss := boss_view()
	if not boss.is_empty():
		_draw_boss(boss,sc)
	var running = _run_flow()
	if running != null and running.run != null:
		_draw_run_info(running,sc)
	_draw_slots(live,sc)

# --- layout helpers: each group anchors to its own screen edge/corner ---
func _widget(id: String) -> Dictionary:
	return _widgets.get(id,{})

func _anchor_of(id: String) -> String:
	for stem in ANCHOR_LEFT:
		if id.begins_with(stem):
			return "left"
	for stem in ANCHOR_TOP:
		if id.begins_with(stem):
			return "top"
	for stem in ANCHOR_RIGHT:
		if id.begins_with(stem):
			return "right"
	return "bottom"

## Top-left of a layout point (x,y in 640x360 canvas px) in HUD pixels.
func _origin(id: String, x: float, y: float, sc: float) -> Vector2:
	match _anchor_of(id):
		"left":
			return Vector2(x,y)*sc
		"top":
			return Vector2(size.x*0.5+(x-SkinA.CANVAS.x*0.5)*sc,y*sc)
		"right":
			return Vector2(size.x+(x-SkinA.CANVAS.x)*sc,y*sc)
	return Vector2(size.x*0.5+(x-SkinA.CANVAS.x*0.5)*sc,size.y+(y-SkinA.CANVAS.y)*sc)

func _rect(id: String, sc: float) -> Rect2:
	var w := _widget(id)
	if w.is_empty():
		return Rect2()
	return Rect2(_origin(id,float(w["x"]),float(w["y"]),sc),Vector2(float(w["w"]),float(w["h"]))*sc)

## Sub-rectangle given in canvas px (icon_rect / fill_rect), moved with its widget.
func _sub(id: String, key: String, sc: float) -> Rect2:
	var w := _widget(id)
	var r: Array = w.get(key,[0,0,0,0])
	return Rect2(_origin(id,float(r[0]),float(r[1]),sc),Vector2(float(r[2]),float(r[3]))*sc)

func _font_size(sc: float) -> int:
	return maxi(MIN_FONT_SIZE,int(7.0*sc))

## Text centred in (or left-aligned to) the widget's box, with a dark drop shadow for contrast over the arena.
func _label(id: String, content: String, color: Color, sc: float, centred: bool = true) -> void:
	var box := _rect(id,sc)
	if box.size == Vector2.ZERO or content == "":
		return
	var fs := _font_size(sc)
	var font := ThemeDB.fallback_font
	var width := font.get_string_size(content,HORIZONTAL_ALIGNMENT_LEFT,-1,fs).x
	var x := box.position.x+(box.size.x-width)*0.5 if centred else box.position.x
	var base := Vector2(x,box.position.y+(box.size.y-font.get_height(fs))*0.5+font.get_ascent(fs))
	draw_string(font,base+Vector2(1,1),content,HORIZONTAL_ALIGNMENT_LEFT,-1,fs,SHADOW)
	draw_string(font,base,content,HORIZONTAL_ALIGNMENT_LEFT,-1,fs,color)

func _icon(id: String, tex: Texture2D, sc: float, key: String = "") -> void:
	var box := _sub(id,key,sc) if key != "" else _rect(id,sc)
	if box.size != Vector2.ZERO:
		draw_texture_rect(tex,box,false)

func _frame(id: String, sprite: String, sc: float) -> void:
	var box := _rect(id,sc)
	if box.size == Vector2.ZERO:
		return
	var nine: Dictionary = SkinA.kit()["sprites"][SkinA.resolve(sprite)].get("nine",{})
	if nine.is_empty():
		draw_texture_rect(SkinA.region(sprite),box,false)
	else:
		draw_style_box(SkinA.stylebox(sprite,0),box)

func _bar(frame_id: String, fraction: float, fill_sprite: String, sc: float) -> void:
	_frame(frame_id,"ad_ui_bar_frame",sc)
	var fill := _sub(frame_id,"fill_rect",sc)
	fill.size.x = floorf(fill.size.x*clampf(fraction,0.0,1.0))
	if fill.size.x > 0.0:
		draw_texture_rect(SkinA.region(fill_sprite),fill,false)

func _slot(id: String, state: String, icon_tex: Texture2D, sc: float) -> void:
	draw_texture_rect(SkinA.region(SLOT_SPRITES.get(state,SLOT_SPRITES["ready"])),_rect(id,sc),false)
	if icon_tex != null:
		_icon(id,icon_tex,sc,"icon_rect")

func _draw_vitals(live, sc: float) -> void:
	var hp: float = live.sim.actor.health.current
	var max_hp: float = live.sim.actor.health.maximum
	var mana: float = live.sim.mana
	var max_mana: float = float(live.sim.settings["combat"]["player_max_mana"])
	_icon("ico_hp",SkinA.icon_or_mvp("hp"),sc)
	_bar("bar_hp",hp/maxf(1.0,max_hp),"ad_ui_bar_fill_hp",sc)
	_label("txt_hp",tr("hud.value") % [ceili(hp),int(max_hp)],SkinA.label_color("normal"),sc,false)
	_icon("ico_mana",SkinA.icon_or_mvp("mana"),sc)
	_bar("bar_mp",mana/maxf(1.0,max_mana),"ad_ui_bar_fill_mana",sc)
	_label("txt_mp",tr("hud.value") % [int(mana),int(max_mana)],SkinA.label_color("normal"),sc,false)

## Status icons with remaining seconds; empty entries are not drawn. `stem` is "status_" or "boss_status_".
func _draw_statuses(stem: String, views: Array, sc: float) -> void:
	for i in views.size():
		var id := "%s%d" % [stem,i]
		_slot(id,"ready",SkinA.icon_or_mvp(views[i]["id"]),sc)
		_label(id+"_time",str(views[i]["seconds"]),SkinA.label_color("normal"),sc)

func _draw_boss(boss: Dictionary, sc: float) -> void:
	_frame("boss_name_header","ad_ui_header",sc)
	_label("boss_name",str(boss["name"]).to_upper(),SkinA.label_color("selected"),sc)
	_bar("bar_boss",float(boss["fraction"]),"ad_ui_bar_fill_hp",sc)
	for id in ["boss_phase_33","boss_phase_66"]:
		draw_rect(_rect(id,sc),SkinA.label_color("normal"))
	var first: Array = boss["statuses"].slice(0,1)
	_draw_statuses("boss_status_",first,sc)

func _draw_run_info(running, sc: float) -> void:
	_frame("plate_stage","ad_ui_panel_tooltip",sc)
	_label("txt_stage",stage_text(),SkinA.label_color("normal"),sc)
	_icon("ico_coin",SkinA.icon_or_mvp("coin"),sc)
	_label("txt_coins","%d" % running.run.currency,SkinA.label_color("selected"),sc,false)
	var held := artifact_ids()
	for i in held.size():
		_slot("artifact_%d" % i,"ready",Art.artifact_icon(str(held[i])),sc)

func _draw_slots(live, sc: float) -> void:
	var white := SkinA.label_color("normal")
	for i in slot_count():
		var view := slot_view(i)
		var id := "slot_%d" % (i+1)
		var state: String = view["state"]
		if i == 0 and state == "ready":
			state = "selected" # slot 1 (LMB, the locked Basic Bolt) is the primary attack
		_slot(id,state,null if view["empty"] else rune_icon_texture("essence."+str(view["element"])),sc)
		if state == "cooldown":
			var sweep := "ad_ui_slot24_cooldown_sweep_%d" % (cooldown_frame(float(view["cooldown_fraction"]))-4)
			draw_texture_rect(SkinA.region(sweep),_sub(id,"icon_rect",sc),false)
			_label(id,"%.1f" % (float(view["cooldown_left"])/TICKS_PER_SECOND),white,sc)
		_label(id+"_key",str(view["key_label"]),white,sc)
	var dash := dash_view()
	_slot("slot_dash","ready" if dash["ready"] else "cooldown",SkinA.icon_or_mvp("dash"),sc)
	if not dash["ready"]:
		_label("slot_dash",("%.1f" % (float(dash["cooldown_left"])/TICKS_PER_SECOND)),white,sc)
	_label("slot_dash_key",tr(DASH_KEY),white,sc)
	if int(dash["charges"]) > 1:
		_label("dash_charges",tr("hud.dash_charges") % int(dash["charges"]),SkinA.label_color("selected"),sc)

# --- AD-040 art lookups (rune/UI icon atlas; independent of Art.use_art_export) ---
const ATLAS := "res://art/export/ico/ad_ico_atlas_demo.png"
const ATLAS_INDEX := "res://art/export/ico/ad_ico_atlas_demo_index.json"
static var _atlas: Texture2D
static var _icons: Dictionary = {}

static func cooldown_frame(fraction: float) -> int:
	return 4+clampi(floori((1.0-fraction)*8.0),0,7)

static func dash_frame(view: Dictionary) -> int:
	return 5 if view["ready"] else 6

static func _load_atlas() -> void:
	if _atlas == null:
		_atlas = load(ATLAS)
		_icons = JSON.parse_string(FileAccess.get_file_as_string(ATLAS_INDEX))["icons"]

static func _icon_cell(key: String) -> Rect2:
	_load_atlas()
	if not _icons.has(key):
		return Rect2()
	var c: Dictionary = _icons[key]
	return Rect2(c["x"],c["y"],c["w"],c["h"])

static func rune_icon_rect(rune_id: String) -> Rect2:
	var map: Dictionary = Art.export_map()["rune_icons"]
	if not map.has(rune_id):
		rune_id = "essence.neutral"
	return _icon_cell(str(map[rune_id]))

static func rune_icon_texture(rune_id: String) -> AtlasTexture:
	var t := AtlasTexture.new()
	t.region = rune_icon_rect(rune_id)
	t.atlas = _atlas
	return t

static func ui_icon_texture(key: String) -> AtlasTexture:
	var t := AtlasTexture.new()
	_load_atlas()
	t.atlas = _atlas
	var map: Dictionary = Art.export_map()["ui_icons"]
	t.region = _icon_cell(str(map[key])) if map.has(key) else Rect2()
	return t
