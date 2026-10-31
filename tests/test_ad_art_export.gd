extends RefCounted
const ART = preload("res://ui/pixel_art_renderer.gd")
## AD-030: every art/export manifest entry loads as SpriteFrames and matches its Aseprite json.
const MANIFEST := "res://art/export/manifest.json"

func run(t) -> void:
	var m = JSON.parse_string(FileAccess.get_file_as_string(MANIFEST))
	t.check(m is Dictionary, "AD-030 manifest parses")
	if not m is Dictionary:
		return
	var assets: Dictionary = m["assets"]
	t.check(assets.size() >= 30, "AD-030 manifest has >= 30 assets")
	var sprites := 0
	for stem in assets:
		var e: Dictionary = assets[stem]
		var j = JSON.parse_string(FileAccess.get_file_as_string(e["json"]))
		t.check(j is Dictionary, "AD-030 json parses: " + stem)
		if e["png"] == null:
			t.equal(e.get("kind", ""), "swap_table", "AD-030 swap table: " + stem)
			continue
		sprites += 1
		var tex = load(e["png"])
		t.check(tex is Texture2D, "AD-030 png loads: " + stem)
		if not tex is Texture2D or not j is Dictionary:
			continue
		if e.get("kind", "") == "glyph_atlas":
			continue
		var tsize: Vector2i = Vector2i(tex.get_size())
		var frames: Array = j["frames"]
		var tags: Array = j["meta"]["frameTags"]
		var sf: SpriteFrames = ART.build_sprite_frames(stem)
		var names := []
		for tg in tags:
			names.append(str(tg["name"]))
		var got := Array(sf.get_animation_names())
		got.sort()
		names.sort()
		t.equal(got, names, "AD-030 animation names match json: " + stem)
		var mtags: Array = e["tags"].keys()
		mtags.sort()
		t.equal(mtags, names, "AD-030 manifest tags match json: " + stem)
		for tg in tags:
			var n := str(tg["name"])
			var cnt: int = int(tg["to"]) - int(tg["from"]) + 1
			t.equal(sf.get_frame_count(n), cnt, "AD-030 frame count %s/%s" % [stem, n])
			t.equal(int(e["tags"][n]["frames"]), cnt, "AD-030 manifest frames %s/%s" % [stem, n])
			for i in cnt:
				var ms: int = int(frames[int(tg["from"]) + i]["duration"])
				t.equal(int(e["tags"][n]["ms"][i]), ms, "AD-030 manifest ms %s/%s/%d" % [stem, n, i])
				var got_ms: float = sf.get_frame_duration(n, i) / sf.get_animation_speed(n) * 1000.0
				t.check(absf(got_ms - ms) < 0.01, "AD-030 SpriteFrames ms %s/%s/%d" % [stem, n, i])
		for f in frames:
			var r: Dictionary = f["frame"]
			t.check(r["x"] >= 0 and r["y"] >= 0 and r["x"] + r["w"] <= tsize.x and r["y"] + r["h"] <= tsize.y, "AD-030 region inside texture: %s/%s" % [stem, f["filename"]])
		var pivot = null
		for s in j["meta"]["slices"]:
			if s["name"] == "pivot":
				var b: Dictionary = s["keys"][0]["bounds"]
				pivot = [b["x"], b["y"]]
		if e["category"] in ["vfx", "ico"] and pivot == null:
			t.check(e["pivot"] is Array and e["pivot"].size() == 2, "AD-039 manifest pivot (canvas centre): " + stem)
			continue
		t.check(pivot != null, "AD-030 pivot slice in json: " + stem)
		t.check(e["slices"].has("pivot"), "AD-030 pivot slice in manifest: " + stem)
		if pivot != null:
			t.equal(e["pivot"], pivot, "AD-030 manifest pivot: " + stem)
	t.check(sprites >= 30, "AD-030 sprite entries >= 30")
	_engine_map(t, assets)

func _engine_map(t, assets: Dictionary) -> void:
	t.check(not ART.use_art_export, "AD-030 art export off by default")
	t.check(ART.toggle_art_export(), "AD-030 toggle on")
	t.check(not ART.toggle_art_export(), "AD-030 toggle off")
	var map: Dictionary = ART.export_map()
	for kind in map["entities"]:
		var stem: String = map["entities"][kind]
		t.check(assets.has(stem), "AD-030 map entity in manifest: " + kind)
		for st in ["idle", "move", "cast", "hit", "dead"]:
			t.check(assets[stem]["tags"].has(map["states"][stem][st]), "AD-030 map tag %s/%s" % [stem, st])
	t.check(assets[map["floor"]["asset"]]["tags"].has(map["floor"]["tag"]), "AD-030 floor tag exists")
	t.equal(ART.build_sprite_frames("ad_chr_mage").get_animation_names().size(), 18, "AD-030 mage has 18 animations")
	var f0: Dictionary = ART.export_frame_for("mage", "idle", 0)
	t.equal(f0["index"], 0, "AD-030 tick 0 -> frame 0")
	t.equal(ART.export_frame_for("mage", "idle", int(ceil(f0["total_ms"] * 60.0 / 1000.0)))["index"], 0, "AD-030 idle loops")
	var dead: Dictionary = ART.export_frame_for("bone_thrall", "dead", 100000)
	t.equal(dead["index"], 4, "AD-030 dead holds last frame")
	# Drawing is only legal inside _draw(); the headless runner has no render pass,
	# so the draw path is covered by frame/atlas lookups above instead.
	ART.use_art_export = true
	t.check(ART.export_frame_for("undead_warden", "cast", 5).has("region"), "AD-030 export frame has atlas region")
	ART.use_art_export = false
