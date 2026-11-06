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
		for s in j["meta"].get("slices", []):
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
	_actors(t)

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

const ACTORS_MANIFEST := "res://art/export/actors/actors_manifest.json"
const TUNING := "res://combat/combat_tuning_v1.json"
const ENEMY_TAGS := ["idle_side", "move_side", "telegraph_side", "attack_side", "hit_side", "death_side"]

## AD-154: actors_manifest.json matches each sheet json (tags, ms, pivot, hurtbox, glow rects); enemies carry the canvas tags.
func _actors(t) -> void:
	var m = JSON.parse_string(FileAccess.get_file_as_string(ACTORS_MANIFEST))
	t.check(m is Dictionary and m.has("actors"), "AD-154 actors manifest parses")
	if not m is Dictionary:
		return
	var actors: Dictionary = m["actors"]
	var jsons := {}
	for kind in actors:
		var ent: Dictionary = actors[kind]
		for key in ent["sheets"]:
			var sh: Dictionary = ent["sheets"][key]
			var j = JSON.parse_string(FileAccess.get_file_as_string(sh["json"]))
			t.check(j is Dictionary, "AD-154 json parses: %s/%s" % [kind, key])
			t.check(load(sh["png"]) is Texture2D, "AD-154 png loads: %s/%s" % [kind, key])
			if not j is Dictionary:
				continue
			jsons[kind + "/" + key] = j
			var slices := {}
			for s in j["meta"].get("slices", []):
				slices[s["name"]] = s["keys"][0]["bounds"]
			t.check(slices.has("pivot") and slices.has("hurtbox"), "AD-154 pivot/hurtbox slices: %s/%s" % [kind, key])
			if slices.has("pivot"):
				t.equal(sh["pivot"], [slices["pivot"]["x"], slices["pivot"]["y"]], "AD-154 pivot: %s/%s" % [kind, key])
			t.check(sh["hurtbox"] is Dictionary, "AD-154 hurtbox: %s/%s" % [kind, key])
			if sh.get("glow_png") != null:
				var gtex = load(sh["glow_png"])
				t.check(gtex is Texture2D, "AD-154 glow png loads: %s/%s" % [kind, key])
				if gtex is Texture2D:
					for fi in sh["glow"]:
						var r: Dictionary = sh["glow"][fi]
						t.check(int(fi) < j["frames"].size() and r["x"] >= 0 and r["y"] >= 0 and r["x"] + r["w"] <= gtex.get_width() and r["y"] + r["h"] <= gtex.get_height(), "AD-154 glow rect inside texture: %s/%s/%s" % [kind, key, fi])
		for n in ent["tags"]:
			var tg: Dictionary = ent["tags"][n]
			var j = jsons.get(kind + "/" + str(tg["sheet"]))
			if j == null:
				continue
			var src := str(tg.get("src", n))
			var jt = null
			for x in j["meta"]["frameTags"]:
				if x["name"] == src:
					jt = x
			t.check(jt != null, "AD-154 json tag exists: %s/%s" % [kind, n])
			if jt == null:
				continue
			var f: int = int(tg["from"])
			var to: int = int(tg["to"])
			t.check(f >= int(jt["from"]) and f <= to and to <= int(jt["to"]), "AD-154 tag range inside source: %s/%s" % [kind, n])
			if not tg.has("src"):
				t.check(f == int(jt["from"]) and to == int(jt["to"]), "AD-154 tag from/to equals json: %s/%s" % [kind, n])
			t.equal(int(tg["frames"]), to - f + 1, "AD-154 tag frames: %s/%s" % [kind, n])
			var ms := []
			for i in range(f, to + 1):
				ms.append(int(j["frames"][i]["duration"]))
			var got := []
			for v in tg["ms"]:
				got.append(int(v))
			t.equal(got, ms, "AD-154 tag ms equals json: %s/%s" % [kind, n])
	var tuning = JSON.parse_string(FileAccess.get_file_as_string(TUNING))
	var kinds: Array = tuning["enemies"].keys() if tuning is Dictionary else []
	kinds.append("drowned_archivist")
	for kind in kinds:
		t.check(actors.has(kind), "AD-154 actor exists: " + kind)
		for n in ENEMY_TAGS:
			t.check(actors.has(kind) and actors[kind]["tags"].has(n), "AD-154 required tag %s/%s" % [kind, n])
