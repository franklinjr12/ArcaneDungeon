extends RefCounted
## AD-039: P1 FX/glyph/icon exports are in the manifest and every gameplay FX event key maps to them.
const MANIFEST := "res://art/export/manifest.json"
const MAP := "res://art/export/engine_map.json"
const Art = preload("res://ui/pixel_art_renderer.gd")
const Flow = preload("res://world/run_flow.gd")
const Driver = preload("res://tests/m3_run_driver.gd")
const SEED := 20261022

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
	_lookup(t)
	_slice_route(t)

func _lookup(t) -> void:
	for ev in Art.FX_EVENTS:
		var fr: Dictionary = Art.fx_frame(ev, 0)
		t.check(not fr.is_empty(), "AD-039 fx_frame maps " + ev)
		if fr.is_empty():
			continue
		var tex: Texture2D = load(Art.export_manifest()[fr["stem"]]["png"])
		var r: Rect2 = fr["region"]
		t.check(Rect2(Vector2.ZERO, tex.get_size()).encloses(r) and r.size.x > 0 and r.size.y > 0,
			"AD-039 %s region inside texture" % ev)
	t.equal(Art.fx_frame("no.such_event", 0), {}, "AD-039 unmapped event returns {}")
	# loop tag: 4 x 120 ms (status.wet) wraps; 120 ms = 7.2 ticks.
	t.equal(Art.fx_frame("status.wet", 0)["index"], 0, "AD-039 loop tick 0 -> frame 0")
	t.equal(Art.fx_frame("status.wet", 8)["index"], 1, "AD-039 loop tick 8 (133 ms) -> frame 1")
	t.equal(Art.fx_frame("status.wet", 28)["index"], 3, "AD-039 loop tick 28 (466 ms) -> frame 3")
	t.equal(Art.fx_frame("status.wet", 29)["index"], 0, "AD-039 loop wraps at 480 ms (tick 29) -> frame 0")
	t.check(not Art.fx_frame("status.wet", 5000)["done"], "AD-039 loop never done")
	# play tag: split pop 3 x 60 ms = 180 ms; holds last frame, done after 11 ticks (183 ms).
	t.equal(Art.fx_frame("mod.split", 0)["index"], 0, "AD-039 play tick 0 -> frame 0")
	t.equal(Art.fx_frame("mod.split", 4)["index"], 1, "AD-039 play tick 4 (66 ms) -> frame 1")
	t.check(not Art.fx_frame("mod.split", 10)["done"], "AD-039 play not done at 166 ms")
	var last: Dictionary = Art.fx_frame("mod.split", 11)
	t.check(last["done"] and last["index"] == 2, "AD-039 play done at 183 ms holding last frame")
	t.equal(Art.fx_frame("mod.split", 500)["index"], 2, "AD-039 play holds last frame")

func _slice_route(t) -> void:
	Art.fx_fallbacks.clear()
	var flow = Flow.new(SEED)
	var memo: Dictionary = {}
	var seen: Dictionary = {}
	var missing: Array = []
	var probe := func(f):
		var tick: int = f.session.sim.clock.tick
		for item in Art.collect_fx(f.session, tick, memo):
			seen[item["event"]] = true
			if Art.fx_frame(item["event"], item["age"]).is_empty() and not missing.has(item["event"]):
				missing.append(item["event"])
	for index in 4:
		var result: Dictionary = Driver.fight(flow, 4600, probe)
		t.equal(result["state"], "cleared", "AD-039 slice room %d cleared with FX probe" % index)
		if index < 3:
			flow.choose_reward(0)
		Driver.reach_exit(flow)
		memo = {}
	t.equal(missing, [], "AD-039 slice route: every FX event maps to a manifest entry")
	t.equal(Art.fx_fallbacks, [], "AD-039 slice route: no legacy fallback")
	var kinds: Dictionary = {}
	for ev in seen:
		kinds[str(ev).split(".")[0]] = true
	for k in ["projectile", "impact", "status"]:
		t.check(kinds.has(k), "AD-039 slice route emitted %s events (saw %s)" % [k, seen.keys()])
