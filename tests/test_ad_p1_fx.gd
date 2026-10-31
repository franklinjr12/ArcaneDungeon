extends RefCounted
## AD-039: P1 FX/glyph/icon exports are in the manifest and every gameplay FX event key maps to them.
const MANIFEST := "res://art/export/manifest.json"
const MAP := "res://art/export/engine_map.json"

func _load_json(path: String):
	return JSON.parse_string(FileAccess.get_file_as_string(path))

func run(t) -> void:
	var m = _load_json(MANIFEST)
	var map = _load_json(MAP)
	t.check(m is Dictionary and map is Dictionary, "AD-039 manifest and engine_map parse")
	if not (m is Dictionary and map is Dictionary):
		return
	var assets: Dictionary = m["assets"]
	t.check(map["scale"] is float and map["scale"] == 2.0 and int(map["scale"]) == 2, "AD-039 engine_map scale == 2")
	t.check(not str(map["note"]).contains("PROPOSED (scale") and not str(map["note"]).to_lower().contains("scale and"), "AD-039 note no longer calls scale PROPOSED")
	var fx: Dictionary = map["fx"]
	t.check(fx.size() == 37, "AD-039 fx map has all event keys")
	for key in fx:
		var stem: String = fx[key]["asset"]
		var tag: String = fx[key]["tag"]
		t.check(assets.has(stem), "AD-039 fx %s stem in manifest: %s" % [key, stem])
		if not assets.has(stem):
			continue
		t.check(load(assets[stem]["png"]) is Texture2D, "AD-039 fx %s png loads" % key)
		t.check(assets[stem]["tags"].has(tag), "AD-039 fx %s tag exists: %s" % [key, tag])
	for k in ["status.wet", "status.burning", "status.charged"]:
		t.check(assets[fx[k]["asset"]]["slices"].has("symbol"), "AD-039 %s has symbol slice" % k)
	t.equal(map["damage_glyphs"], "ad_vfx_damage_numbers", "AD-039 damage glyph stem")
	var gj = _load_json(assets[map["damage_glyphs"]]["json"])
	t.check(gj is Dictionary and gj.has("glyphs"), "AD-039 glyph json parses")
	if gj is Dictionary:
		for g in ["0", "1", "2", "3", "4", "5", "6", "7", "8", "9", "flame", "droplet", "bolt"]:
			t.check(gj["glyphs"].has(g), "AD-039 glyph " + g)
	t.equal(map["icons"], "ad_ico_atlas_mvp", "AD-039 icon atlas stem")
	var idx = _load_json("res://art/export/ico/ad_ico_atlas_mvp_index.json")
	t.check(idx is Dictionary, "AD-039 icon index parses")
	if idx is Dictionary:
		for n in ["ad_ico_wet", "ad_ico_burning", "ad_ico_charged"]:
			t.check(idx["icons"].has(n), "AD-039 icon " + n)
