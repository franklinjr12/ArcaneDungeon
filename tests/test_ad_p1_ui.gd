extends RefCounted
## AD-040: P1 HUD parts / reward card are in the manifest and every rune id has an icon cell.
const MANIFEST := "res://art/export/manifest.json"
const MAP := "res://art/export/engine_map.json"
const INDEX := "res://art/export/ico/ad_ico_atlas_mvp_index.json"
const RUNES := "res://magic/data/runes_v1.json"
const Hud = preload("res://ui/pixel_hud.gd")
const ATLAS := "res://art/export/ico/ad_ico_atlas_mvp.png"

func _load_json(path: String):
	return JSON.parse_string(FileAccess.get_file_as_string(path))

func _tag_frames(entry: Dictionary, tag: String) -> int:
	var tags: Dictionary = entry["tags"]
	return int(tags[tag]["frames"]) if tags.has(tag) else -1

func run(t) -> void:
	var m = _load_json(MANIFEST)
	var map = _load_json(MAP)
	var index = _load_json(INDEX)
	var runes = _load_json(RUNES)
	t.check(m is Dictionary and map is Dictionary and index is Dictionary and runes is Dictionary, "AD-040 json files parse")
	if not (m is Dictionary and map is Dictionary and index is Dictionary and runes is Dictionary):
		return
	_check_hud_helpers(t, runes)
	var icons: Dictionary = index["icons"]
	var atlas: Texture2D = load(ATLAS)
	t.check(atlas != null, "AD-040 icon atlas png loads")
	if atlas == null:
		return
	var rune_icons: Dictionary = map["rune_icons"]
	for r in runes["runes"]:
		var id: String = r["id"]
		t.check(rune_icons.has(id), "AD-040 rune %s has an icon mapping" % id)
		if not rune_icons.has(id):
			continue
		var key: String = rune_icons[id]
		t.check(icons.has(key), "AD-040 rune %s icon %s in atlas index" % [id, key])
		if icons.has(key):
			_check_cell(t, icons[key], atlas, key)
	for k in map["ui_icons"]:
		var key2: String = map["ui_icons"][k]
		t.check(icons.has(key2), "AD-040 ui icon %s -> %s in atlas index" % [k, key2])
	var assets: Dictionary = m["assets"]
	var hud: Dictionary = map["hud"]
	var want := {
		"spell_slot": ["AD-037", {"states": 4, "cooldown": 8}, ["icon"]],
		"slot_bar": ["AD-037", {"frame": 1, "keycaps": 4, "dash_marker": 3},
			["slot_1", "slot_2", "slot_3", "slot_4", "keycap_1", "keycap_2", "keycap_3", "keycap_4", "lock_slot1", "dash"]],
		"bar_hp": ["AD-037", {"static": 1}, []],
		"bar_mana": ["AD-037", {"static": 1}, []],
		"reward_card": ["AD-038", {"states": 3}, ["rune_icon_slot"]],
	}
	for part in want:
		var stem: String = hud[part]
		t.check(assets.has(stem), "AD-040 hud %s in manifest: %s" % [part, stem])
		if not assets.has(stem):
			continue
		var e: Dictionary = assets[stem]
		t.equal(e["row"], want[part][0], "AD-040 %s row" % stem)
		t.check(load(e["png"]) is Texture2D, "AD-040 %s png loads" % stem)
		for tag in want[part][1]:
			t.equal(_tag_frames(e, tag), want[part][1][tag], "AD-040 %s tag %s frames" % [stem, tag])
		for s in want[part][2]:
			t.check(e["slices"].has(s), "AD-040 %s slice %s" % [stem, s])
	var nine = _load_json(hud["nine_slice"])
	t.check(nine is Dictionary, "AD-040 9slice margins parse")
	if nine is Dictionary:
		for b in ["ad_ui_bar_hp", "ad_ui_bar_mana"]:
			t.check(nine.has(b) and nine[b].has("margins") and nine[b].has("trough"), "AD-040 9slice %s margins+trough" % b)

func _check_hud_helpers(t, runes: Dictionary) -> void:
	t.equal(Hud.cooldown_frame(1.0), 4, "AD-040 cooldown_frame(1.0)")
	t.equal(Hud.cooldown_frame(0.5), 8, "AD-040 cooldown_frame(0.5)")
	t.equal(Hud.cooldown_frame(0.01), 11, "AD-040 cooldown_frame(0.01)")
	t.equal(Hud.cooldown_frame(0.0), 11, "AD-040 cooldown_frame(0.0)")
	t.equal(Hud.dash_frame({"ready": true}), 5, "AD-040 dash_frame ready")
	t.equal(Hud.dash_frame({"ready": false}), 6, "AD-040 dash_frame cooling")
	var ids: Array = ["essence.neutral"]
	for r in runes["runes"]:
		ids.append(r["id"])
	for id in ids:
		var tex: AtlasTexture = Hud.rune_icon_texture(id)
		t.check(tex != null and tex.atlas != null and tex.region.size == Vector2(16, 16), "AD-040 rune_icon_texture %s is a 16x16 cell" % id)

func _check_cell(t, c: Dictionary, atlas: Texture2D, key: String) -> void:
	t.check(int(c["w"]) == 16 and int(c["h"]) == 16, "AD-040 icon %s is 16x16" % key)
	t.check(int(c["x"]) >= 0 and int(c["y"]) >= 0 and int(c["x"]) + int(c["w"]) <= atlas.get_width() and int(c["y"]) + int(c["h"]) <= atlas.get_height(), "AD-040 icon %s inside atlas" % key)
