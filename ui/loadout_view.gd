extends "res://ui/skin_a_overlay.gd"
## AD-147: read-only loadout view (pause menu, between rooms). AD-153: skin A layout (ad_ui_screen_loadout_layout.json).
## Shows the 4 spell slots with their rune chains, held artifacts, run upgrades and vitals. No edit controls; purely visual
## (never touches the sim). Back and Continue both close the view: the exit door is still walked to.
const Artifacts = preload("res://world/artifacts.gd")
const Difficulty = preload("res://game/core/difficulty.gd")
const ARTIFACT_ICON := "upgrade" # no per-artifact icons yet; same generic glyph as the HUD
const BASE_HP := 150.0 # mirrors RunState.initialize; only used to read the merchant's HP bonus
signal close_requested

var _tooltip_name: Label
var _tooltip_rarity: Label
var _tooltip_desc: Label
var _artifact_ids: Array = []

func _init() -> void:
	super(true)

func show_for(flow) -> void:
	begin("loadout")
	var live = flow.session
	var loadout = live.sim.loadout
	frame("panel", "ad_ui_panel_large", rect_of("panel"))
	picture("title_header", SkinA.region("ad_ui_header"), rect_of("title_header"))
	text("title", tr("loadout_view.title").to_upper(), _span("title_header", "title"), "selected", HORIZONTAL_ALIGNMENT_CENTER)
	text("readonly_note", tr("loadout_view.read_only").to_upper(), _span("panel", "readonly_note"), "normal", HORIZONTAL_ALIGNMENT_CENTER)
	_header("hdr_spells", "label_7", tr("loadout_view.spells"))
	for i in 4:
		_spell_row(i, loadout)
	_header("hdr_status", "label_41", tr("loadout_view.status"))
	_status(flow, live)
	_artifacts(flow)
	_upgrades(flow)
	if flow.room != null and flow.room.values.has("room"):
		text("room_cleared", (tr("loadout_view.room_cleared") % (int(flow.room.values["room"]) + 1)).to_upper(), rect_of("room_cleared"), "selected")
	var back := button("btn_back", tr("loadout_view.back").to_upper(), func(): close_requested.emit(), {}, "ui.cancel")
	back.name = "LoadoutCloseButton"
	var next := button("btn_continue", tr("loadout_view.continue").to_upper(), func(): close_requested.emit())
	next.name = "LoadoutContinueButton"
	visible = true
	finish(["btn_continue", "btn_back"])

## Layout label row centred across a band (header/panel) rect.
func _span(band_id: String, label_id: String) -> Dictionary:
	var band: Dictionary = rect_of(band_id)
	var row: Dictionary = rect_of(label_id)
	return {"x": band["x"], "y": row["y"], "w": band["w"], "h": row["h"]}

func _header(band_id: String, label_id: String, value: String) -> void:
	frame(band_id, "ad_ui_header_small", rect_of(band_id))
	text(label_id, value.to_upper(), _span(band_id, label_id), "selected", HORIZONTAL_ALIGNMENT_CENTER)

func _spell_row(i: int, loadout) -> void:
	var n := i + 1
	var preview: Dictionary = loadout.preview(i)
	var empty := preview.is_empty()
	var formula: Dictionary = loadout.slots[i]["formula"]
	var row_panel := frame("spell_row_%d" % n, "ad_ui_panel_inset", rect_of("spell_row_%d" % n))
	row_panel.name = "LoadoutSlot" + str(i) # the smoke test looks rows up by this name
	var slot_sprite := "ad_ui_slot24_empty" if empty else ("ad_ui_slot24_selected" if loadout.is_locked(i) else "ad_ui_slot24_ready")
	picture("spell_slot_%d" % n, SkinA.region(slot_sprite), rect_of("spell_slot_%d" % n))
	text("spell_key_%d" % n, SkinA.slot_key(i), rect_of("spell_key_%d" % n), "hover")
	var row := rect_of("spell_row_%d" % n)
	var cost_rect := {"x": row["x"] + row["w"] - 48.0, "y": rect_of("spell_cost_%d" % n)["y"], "w": 40.0, "h": 7.0} # right-aligned MP / cooldown column
	var name_rect := rect_of("spell_name_%d" % n)
	name_rect["w"] = cost_rect["x"] - name_rect["x"] - 4.0
	if empty:
		text("spell_name_%d" % n, tr("run.loadout.empty").to_upper(), name_rect, "disabled")
		return
	var ir: Array = widgets["spell_slot_%d" % n]["icon_rect"]
	var ids := SkinA.formula_rune_ids(formula)
	picture("spell_slot_%d_icon" % n, SkinA.rune_icon(str(ids[0])), {"x": ir[0], "y": ir[1], "w": ir[2], "h": ir[3]})
	var title := str(formula.get("display_name", "")).to_upper()
	if loadout.is_locked(i):
		title += tr("loadout_view.locked").to_upper()
	text("spell_name_%d" % n, title, name_rect, "normal")
	var mp := text("spell_cost_%d" % n, (tr("loadout_view.mp") % int(preview["mana"])).to_upper(), cost_rect, "normal", HORIZONTAL_ALIGNMENT_RIGHT)
	mp.add_theme_color_override("font_color", SkinA.mana_color())
	var seconds := float(preview["cooldown"]) / float(Engine.physics_ticks_per_second)
	var cd_rect := {"x": cost_rect["x"], "y": cost_rect["y"] + 18.0, "w": cost_rect["w"], "h": 7.0}
	text("spell_cd_%d" % n, (tr("loadout_view.cooldown") % seconds).to_upper(), cd_rect, "disabled", HORIZONTAL_ALIGNMENT_RIGHT)
	var chain := rect_of("spell_%d_runes" % n)
	for k in ids.size():
		var x: float = chain["x"] + 22.0 * k
		picture("spell_%d_rune_%d" % [n, k + 1], SkinA.rune_icon(str(ids[k])), {"x": x, "y": chain["y"], "w": 16, "h": 16})
		if k < ids.size() - 1:
			text("spell_%d_arrow_%d" % [n, k + 1], ">", {"x": x + 16.0, "y": chain["y"] + 5.0, "w": 6, "h": 7}, "disabled", HORIZONTAL_ALIGNMENT_CENTER)

func _status(flow, live) -> void:
	var hp: float = live.sim.actor.health.current
	var max_hp: float = live.sim.actor.health.maximum
	var mana: float = live.sim.mana
	var max_mana: float = float(live.sim.settings["combat"]["player_max_mana"])
	var ico_x := 34.0
	_icon_at(ico_x, 260.0, "hp")
	_bar("bar_hp", hp / maxf(1.0, max_hp), "ad_ui_bar_fill_hp")
	text("txt_hp", tr("hud.value") % [ceili(hp), int(max_hp)], rect_of("txt_hp"))
	_icon_at(ico_x, 278.0, "mana")
	_bar("bar_mp", mana / maxf(1.0, max_mana), "ad_ui_bar_fill_mana")
	text("txt_mp", tr("hud.value") % [int(mana), int(max_mana)], rect_of("txt_mp"))
	_icon_at(240.0, 262.0, "coin")
	text("txt_coins", "%d" % flow.run.currency, rect_of("txt_coins"), "selected")
	var charges: int = (1 if live.player.dash_cooldown == 0 else 0) + int(live.player.bonus_dashes_left)
	_icon_at(240.0, 280.0, "dash")
	text("txt_dash", (tr("loadout_view.charges") % charges).to_upper(), rect_of("txt_dash"))

func _icon_at(x: float, y: float, name: String) -> void:
	picture("ico_" + name, SkinA.icon_or_mvp(name), {"x": x, "y": y, "w": 16, "h": 16})

func _bar(id: String, fraction: float, fill_sprite: String) -> void:
	picture(id, SkinA.region("ad_ui_bar_frame"), rect_of(id))
	var f: Array = widgets[id]["fill_rect"]
	var width := floorf(float(f[2]) * clampf(fraction, 0.0, 1.0))
	if width > 0.0:
		picture(id + "_fill", SkinA.region(fill_sprite), {"x": f[0], "y": f[1], "w": width, "h": f[3]})

func _artifacts(flow) -> void:
	_artifact_ids = flow.run.artifacts
	var maximum := Artifacts.max_held()
	_header("hdr_artifacts", "label_49", tr("loadout_view.artifacts_count") % [_artifact_ids.size(), maximum])
	for i in mini(maximum, 12):
		var id := "artifact_slot_%d" % (i + 1)
		var held: bool = i < _artifact_ids.size()
		var slot := picture(id, SkinA.region("ad_ui_slot40_normal" if held else "ad_ui_slot40_empty"), rect_of(id))
		if not held:
			continue
		var r := rect_of(id)
		picture(id + "_icon", SkinA.icon_or_mvp(ARTIFACT_ICON), {"x": r["x"] + 4.0, "y": r["y"] + 4.0, "w": 32, "h": 32})
		slot.mouse_filter = Control.MOUSE_FILTER_STOP
		slot.mouse_entered.connect(_show_artifact.bind(i))
	frame("artifact_tooltip", "ad_ui_panel_tooltip", rect_of("artifact_tooltip"))
	_tooltip_name = text("tt_name", "", rect_of("tt_name"), "selected")
	var tip := rect_of("artifact_tooltip")
	_tooltip_rarity = text("tt_rarity", "", {"x": tip["x"] + 8.0, "y": rect_of("tt_rarity")["y"], "w": tip["w"] - 16.0, "h": 7.0}, "disabled", HORIZONTAL_ALIGNMENT_RIGHT)
	var desc_rect := rect_of("tt_l1")
	desc_rect["w"] = tip["w"] - 16.0
	desc_rect["h"] = 28.0
	_tooltip_desc = text("tt_desc", "", desc_rect, "normal", HORIZONTAL_ALIGNMENT_LEFT, 3)
	if _artifact_ids.is_empty():
		_tooltip_name.text = tr("loadout_view.no_artifacts").to_upper()
	else:
		_show_artifact(0)

func _show_artifact(index: int) -> void:
	var id := str(_artifact_ids[index])
	_tooltip_name.text = tr("artifact." + id + ".name").to_upper()
	_tooltip_rarity.text = tr("run.rarity." + Artifacts.rarity_of(id)).to_upper()
	_tooltip_desc.text = tr("artifact." + id + ".desc").to_upper()

func _upgrades(flow) -> void:
	_header("hdr_upgrades", "label_68", tr("loadout_view.upgrades"))
	var hp_bonus := int(round(flow.run.max_hp - Difficulty.scale_f(BASE_HP, "player_hp")))
	var rows := [["hp_up", "loadout_view.hp_up", hp_bonus], ["mana_up", "loadout_view.mana_up", int(flow.run.max_mana_bonus)],
		["dash_up", "loadout_view.dash_up", int(flow.run.dash_charges_bonus)]]
	for i in rows.size():
		var n := i + 1
		var slot := rect_of("upgrade_slot_%d" % n)
		picture("upgrade_slot_%d" % n, SkinA.region("ad_ui_slot24_ready" if rows[i][2] > 0 else "ad_ui_slot24_empty"), slot)
		picture("upgrade_slot_%d_icon" % n, SkinA.icon_or_mvp(rows[i][0]), {"x": slot["x"] + 4.0, "y": slot["y"] + 4.0, "w": 16, "h": 16})
		text("upgrade_%d" % n, (tr(rows[i][1]) % rows[i][2]).to_upper(), rect_of("upgrade_%d" % n), "normal" if rows[i][2] > 0 else "disabled")
