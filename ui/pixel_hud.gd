extends Control
## Reference-inspired bottom-centre HUD (canvas set, AD-014): portrait, HP/mana bars, 4 loadout slots with keys, cost and a dash marker, render-only.
const Art = preload("res://ui/pixel_art_renderer.gd")
const MAGE = preload("res://assets/pixel/mage_sheet.png")
const KEY_LABELS := ["hud.key.lmb","hud.key.rmb","Q","E"] # mirrors the cast_slot_1..4 input map (ui/input_actions.gd)
const DASH_KEY := "hud.key.space" # mirrors the dash input action
const TICKS_PER_SECOND := 60.0
const SLOT_SIZE := 54.0
const SLOT_GAP := 10.0
const PANEL_PAD := 14.0
const DASH_GAP := 16.0
const PANEL_HEIGHT := 136.0
const MIN_FONT_SIZE := 14 # smallest legible text at 1280x720
const PORTRAIT_W := 58.0
const PORTRAIT_H := 66.0
const PORTRAIT_GAP := 14.0
const SAFE_MARGIN := 16.0 # logical px between the combat panel and the bottom edge of the canvas
var flow
var session
var canvas

func _ready() -> void:
	if canvas != null:
		custom_minimum_size = Vector2(panel_width(slot_count()),PANEL_HEIGHT)
		canvas.resized.connect(fit_to_canvas)
		fit_to_canvas()
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST

## Bottom-centre of the canvas with a safe margin. The canvas node is scaled by the arena zoom, so this counter-scales to stay logical-sized.
func fit_to_canvas() -> void:
	if canvas == null:
		return
	var k: float = 1.0/maxf(canvas.scale.x,0.01)
	var panel := Vector2(panel_width(slot_count()),PANEL_HEIGHT)
	scale = Vector2(k,k)
	size = panel
	position = Vector2(floorf((canvas.size.x-panel.x*k)/2.0),canvas.size.y-(panel.y+SAFE_MARGIN)*k)

static func panel_width(slots: int) -> float:
	var slots_width: float = slots*SLOT_SIZE+(slots-1)*SLOT_GAP
	return PANEL_PAD*2+PORTRAIT_W+PORTRAIT_GAP+maxf(slots_width+DASH_GAP+SLOT_SIZE,128.0*hud_scale())

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
	return {"key_label":tr(KEY_LABELS[i]) if i < KEY_LABELS.size() else "","locked":loadout.is_locked(i),"empty":empty,
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
	_draw_combat_panel()

func _text(where: Vector2,content: String,color: Color,font_size: int) -> void:
	draw_string(ThemeDB.fallback_font,where,content,HORIZONTAL_ALIGNMENT_LEFT,-1,font_size,color)

func _draw_combat_panel() -> void:
	var live = _session()
	if live == null:
		return
	_nine()
	var sc: float = hud_scale()
	var bar_px: Vector2 = Vector2(128.0,28.0)*sc
	var width: float = panel_width(slot_count())
	var origin := Vector2.ZERO # the control itself is anchored bottom-centre with SAFE_MARGIN
	draw_rect(Rect2(origin,Vector2(width,PANEL_HEIGHT)),Color("#0b131b",0.92))
	draw_rect(Rect2(origin,Vector2(width,PANEL_HEIGHT)),Color("#b08042"),false,2)
	draw_rect(Rect2(origin+Vector2(4,4),Vector2(width-8,PANEL_HEIGHT-8)),Color("#564226"),false,1)
	draw_texture_rect_region(MAGE,Rect2(PANEL_PAD,PANEL_PAD,PORTRAIT_W,PORTRAIT_H),Rect2(0,0,48,56))
	var hp: float = live.sim.actor.health.current
	var max_hp: float = live.sim.actor.health.maximum
	var mana: float = live.sim.mana
	var max_mana: float = float(live.sim.settings["combat"]["player_max_mana"])
	var content_x: float = PANEL_PAD+PORTRAIT_W+PORTRAIT_GAP
	var bar_width: float = (bar_px.x-10.0)/2.0
	var bar_at := origin+Vector2(content_x,8)
	_draw_bar9("ad_ui_bar_hp",bar_at,bar_width,hp/maxf(1,max_hp))
	_text(bar_at+Vector2(8,15),tr("hud.hp") % [ceili(hp),int(max_hp)],Color("#fff1d4"),MIN_FONT_SIZE)
	var mana_at := bar_at+Vector2(bar_width+10,0)
	_draw_bar9("ad_ui_bar_mana",mana_at,bar_width,mana/maxf(1,max_mana))
	_text(mana_at+Vector2(8,15),tr("hud.mp") % [int(mana),int(max_mana)],Color("#eff8ff"),MIN_FONT_SIZE)
	var bar_origin := Vector2(origin.x+content_x,origin.y+36.0)
	var bar_tex: Texture2D = Art._texs[HUD_BAR]
	draw_texture_rect_region(bar_tex,Rect2(bar_origin,bar_px),_frame(HUD_BAR,0))
	var slot_px: float = 28.0*sc
	var key_y: float = bar_origin.y+bar_px.y+MIN_FONT_SIZE
	var cost_y: float = key_y+MIN_FONT_SIZE+2.0
	for i in slot_count():
		var view := slot_view(i)
		var at := bar_origin+Vector2(i*slot_px,0)
		_draw_slot(at,view,sc)
		draw_texture_rect_region(bar_tex,Rect2(bar_origin,bar_px),_frame(HUD_BAR,1+i))
		_text(Vector2(at.x+2.0,key_y),"%d %s" % [i+1,view["key_label"]],Color("#e9d5a8"),MIN_FONT_SIZE)
		if not view["empty"]:
			var no_mana: bool = view["state"] == "no_mana"
			_text(Vector2(at.x+2.0,cost_y),tr("hud.mana_cost") % int(view["mana_cost"]),Color("#ff8f8f") if no_mana else Color("#83d8ff"),MIN_FONT_SIZE)
	var dash := dash_view()
	draw_texture_rect_region(bar_tex,Rect2(bar_origin,bar_px),_frame(HUD_BAR,dash_frame(dash)))
	var ready: bool = dash["ready"]
	var dash_x: float = bar_origin.x+114.0*sc-6.0
	_text(Vector2(dash_x,key_y),tr("hud.dash") if ready else "%.1f" % (float(dash["cooldown_left"])/TICKS_PER_SECOND),
		Color("#8fe3c1") if ready else Color("#fff1d4"),MIN_FONT_SIZE)
	_text(Vector2(dash_x,cost_y),tr(DASH_KEY),Color("#e9d5a8"),MIN_FONT_SIZE)

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
		_text(at+Vector2(14.0*sc-14.0,14.0*sc+4.0),"%.1f" % (float(view["cooldown_left"])/TICKS_PER_SECOND),Color("#fff1d4"),MIN_FONT_SIZE)

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
