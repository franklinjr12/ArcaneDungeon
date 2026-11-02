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
		draw_texture_rect(rune_icon_texture(str(formula["root"]["essence_id"])),Rect2(px+2,83,31,31),false)
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
	_nine()
	var sc: float = hud_scale()
	var bar_px: Vector2 = Vector2(128.0,28.0)*sc
	var slots_width: float = slot_count()*SLOT_SIZE+(slot_count()-1)*SLOT_GAP
	var width: float = maxf(PANEL_PAD*2+slots_width+DASH_GAP+SLOT_SIZE,bar_px.x+PANEL_PAD*2)
	var origin := Vector2(floorf((size.x-width)/2.0),size.y-PANEL_HEIGHT-8.0)
	draw_rect(Rect2(origin,Vector2(width,PANEL_HEIGHT)),Color("#0b131b",0.92))
	draw_rect(Rect2(origin,Vector2(width,PANEL_HEIGHT)),Color("#b08042"),false,2)
	draw_rect(Rect2(origin+Vector2(4,4),Vector2(width-8,PANEL_HEIGHT-8)),Color("#564226"),false,1)
	var hp: float = live.sim.actor.health.current
	var max_hp: float = live.sim.actor.health.maximum
	var mana: float = live.sim.mana
	var max_mana: float = float(live.sim.settings["combat"]["player_max_mana"])
	var bar_width: float = (width-PANEL_PAD*2-10.0)/2.0
	var bar_at := origin+Vector2(PANEL_PAD,8)
	_draw_bar9("ad_ui_bar_hp",bar_at,bar_width,hp/maxf(1,max_hp))
	_text(bar_at+Vector2(8,15),"HP %d/%d" % [ceili(hp),int(max_hp)],Color("#fff1d4"),11)
	var mana_at := bar_at+Vector2(bar_width+10,0)
	_draw_bar9("ad_ui_bar_mana",mana_at,bar_width,mana/maxf(1,max_mana))
	_text(mana_at+Vector2(8,10),"MP %d/%d" % [int(mana),int(max_mana)],Color("#eff8ff"),10)
	var bar_origin := Vector2(origin.x+floorf((width-bar_px.x)/2.0),origin.y+36.0)
	var bar_tex: Texture2D = Art._texs[HUD_BAR]
	draw_texture_rect_region(bar_tex,Rect2(bar_origin,bar_px),_frame(HUD_BAR,0))
	var slot_px: float = 28.0*sc
	var text_y: float = bar_origin.y+bar_px.y+12.0
	for i in slot_count():
		var view := slot_view(i)
		var at := bar_origin+Vector2(i*slot_px,0)
		_draw_slot(at,view,sc)
		draw_texture_rect_region(bar_tex,Rect2(bar_origin,bar_px),_frame(HUD_BAR,1+i))
		if not view["empty"]:
			var no_mana: bool = view["state"] == "no_mana"
			_text(Vector2(at.x+slot_px/2.0-5.0,text_y),str(view["mana_cost"]),Color("#ff8f8f") if no_mana else Color("#83d8ff"),11)
	var dash := dash_view()
	draw_texture_rect_region(bar_tex,Rect2(bar_origin,bar_px),_frame(HUD_BAR,dash_frame(dash)))
	var ready: bool = dash["ready"]
	_text(bar_origin+Vector2(114.0*sc-6.0,bar_px.y+12.0),"DASH" if ready else "%.1f" % (float(dash["cooldown_left"])/TICKS_PER_SECOND),
		Color("#8fe3c1") if ready else Color("#fff1d4"),11)

func _draw_slot(at: Vector2, view: Dictionary, sc: float) -> void:
	var state: String = view["state"]
	var slot_tex: Texture2D = Art._texs[HUD_SLOT]
	var empty: bool = state == "empty"
	if not empty:
		var rune_id := "essence."+str(view["element"])
		var icon_rect := Rect2(4,4,16,16) # 'icon' slice of ad_ui_spell_slot
		draw_texture_rect(rune_icon_texture(rune_id),Rect2(at+icon_rect.position*sc,icon_rect.size*sc),false)
	var frame := 0
	if empty:
		frame = 2
	elif state == "no_mana":
		frame = 3
	elif state == "cooldown":
		frame = cooldown_frame(float(view["cooldown_fraction"]))
	draw_texture_rect_region(slot_tex,Rect2(at,Vector2(28,28)*sc),_frame(HUD_SLOT,frame))
	if state == "cooldown":
		_text(at+Vector2(14.0*sc-14.0,14.0*sc+4.0),"%.1f" % (float(view["cooldown_left"])/TICKS_PER_SECOND),Color("#fff1d4"),12)

func _draw_bar9(stem: String,at: Vector2,width: float,fraction: float) -> void:
	var sc: float = hud_scale()
	var info: Dictionary = _nine()[stem]
	var m: Dictionary = info["margins"]
	var tex: Texture2D = Art._texs[stem]
	var sb := StyleBoxTexture.new()
	sb.texture = tex
	sb.texture_margin_left = m["left"]
	sb.texture_margin_top = m["top"]
	sb.texture_margin_right = m["right"]
	sb.texture_margin_bottom = m["bottom"]
	var h: float = float(tex.get_height())
	var w: float = width/sc
	draw_set_transform(at,0.0,Vector2(sc,sc))
	draw_style_box(sb,Rect2(0,0,w,h))
	var fill: Dictionary = info["fill"]
	var fill_w: float = w-float(m["left"])-float(m["right"])
	var used: float = fill_w*clampf(fraction,0.0,1.0)
	draw_rect(Rect2(float(fill["x"])+used,float(fill["y"]),fill_w-used,float(fill["h"])),Color(str(info["trough"]["rgb"])))
	draw_set_transform(Vector2.ZERO,0.0,Vector2.ONE)

# --- AD-040 art lookups (P1 default visuals; independent of Art.use_art_export) ---
const HUD_SLOT := "ad_ui_spell_slot"
const HUD_BAR := "ad_ui_hud_slot_bar"
const NINE := "res://art/export/ui/ad_ui_9slice_margins.json"
const ATLAS := "res://art/export/ico/ad_ico_atlas_mvp.png"
const ATLAS_INDEX := "res://art/export/ico/ad_ico_atlas_mvp_index.json"
static var _atlas: Texture2D
static var _icons: Dictionary = {}
static var _nine_cache: Dictionary = {}

static func hud_scale() -> float:
	return float(Art.export_map().get("scale",2))

static func _nine() -> Dictionary:
	if _nine_cache.is_empty():
		_nine_cache = JSON.parse_string(FileAccess.get_file_as_string(NINE))
		for stem in ["ad_ui_bar_hp","ad_ui_bar_mana"]:
			Art._export_json(stem)
		Art._export_json(HUD_SLOT)
		Art._export_json(HUD_BAR)
	return _nine_cache

static func _frame(stem: String, index: int) -> Rect2:
	var f: Dictionary = Art._export_json(stem)["frames"][index]["frame"]
	return Rect2(f["x"],f["y"],f["w"],f["h"])

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
