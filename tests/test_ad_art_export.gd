extends RefCounted
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
		var tsize: Vector2i = Vector2i(tex.get_size())
		var frames: Array = j["frames"]
		var tags: Array = j["meta"]["frameTags"]
		var sf := _build(tex, frames, tags)
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
		t.check(pivot != null, "AD-030 pivot slice in json: " + stem)
		t.check(e["slices"].has("pivot"), "AD-030 pivot slice in manifest: " + stem)
		if pivot != null:
			t.equal(e["pivot"], pivot, "AD-030 manifest pivot: " + stem)
	t.check(sprites >= 30, "AD-030 sprite entries >= 30")

## One animation per frameTag; frame duration is relative to a 1000/ms-based speed.
static func _build(tex: Texture2D, frames: Array, tags: Array) -> SpriteFrames:
	var sf := SpriteFrames.new()
	sf.remove_animation("default")
	for tg in tags:
		var n := str(tg["name"])
		var from: int = int(tg["from"])
		var to: int = int(tg["to"])
		# base = 100 ms per 1.0 duration unit at speed 10 fps
		sf.add_animation(n)
		sf.set_animation_speed(n, 10.0)
		sf.set_animation_loop(n, true)
		for i in range(from, to + 1):
			var r: Dictionary = frames[i]["frame"]
			var at := AtlasTexture.new()
			at.atlas = tex
			at.region = Rect2(r["x"], r["y"], r["w"], r["h"])
			sf.add_frame(n, at, float(frames[i]["duration"]) / 100.0)
	return sf
