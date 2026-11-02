extends RefCounted
## AD-065: actor animation manifest matches its Aseprite jsons and the Art 02 card frame counts.
const MANIFEST := "res://art/export/actors/actors_manifest.json"
const ENEMY := {"idle_side": 4, "move_side": 4, "telegraph_side": 3, "attack_side": 4, "hit_side": 2, "death_side": 5, "spawn_side": 4}
const WARDEN := {"idle_side": 4, "move_side": 4, "telegraph_burst_side": 4, "burst_side": 6, "telegraph_dash_side": 3,
		"dash_side": 4, "phase_side": 6, "hit_side": 2, "death_side": 10}
const WARDEN_LATE := ["phase_side", "hit_side", "death_side"]

func _expected() -> Dictionary:
	var mage := {}
	var counts := {"idle": 4, "walk": 6, "cast": 5, "dash": 4, "hit": 2, "death": 6}
	for a in counts:
		for d in ["down", "side", "up"]:
			mage[a + "_" + d] = counts[a]
	return {"mage": mage, "bone_thrall": ENEMY, "fallen_adept": ENEMY, "grave_hound": ENEMY, "undead_warden": WARDEN}

func _check_json(t, path: String, tags: Dictionary, label: String) -> void:
	var j = JSON.parse_string(FileAccess.get_file_as_string(path))
	t.check(j is Dictionary, "AD-065 json parses: " + label)
	if not j is Dictionary:
		return
	var by_name := {}
	for tg in j["meta"]["frameTags"]:
		by_name[str(tg["name"])] = tg
	for n in tags:
		var e: Dictionary = tags[n]
		t.check(by_name.has(n), "AD-065 tag in json: %s/%s" % [label, n])
		if not by_name.has(n):
			continue
		var tg: Dictionary = by_name[n]
		t.equal(int(tg["from"]), int(e["from"]), "AD-065 from: %s/%s" % [label, n])
		t.equal(int(tg["to"]), int(e["to"]), "AD-065 to: %s/%s" % [label, n])
		t.equal(int(e["frames"]), int(e["to"]) - int(e["from"]) + 1, "AD-065 frame count: %s/%s" % [label, n])
		var ms := []
		for i in range(int(tg["from"]), int(tg["to"]) + 1):
			ms.append(int(j["frames"][i]["duration"]))
		var got := []
		for v in e["ms"]:
			got.append(int(v))
		t.equal(got, ms, "AD-065 ms: %s/%s" % [label, n])

func run(t) -> void:
	var m = JSON.parse_string(FileAccess.get_file_as_string(MANIFEST))
	t.check(m is Dictionary, "AD-065 actor manifest parses")
	if not m is Dictionary:
		return
	var actors: Dictionary = m["actors"]
	t.equal(actors.size(), 5, "AD-065 five actor kinds")
	var exp := _expected()
	for kind in exp:
		t.check(actors.has(kind), "AD-065 kind present: " + kind)
		if not actors.has(kind):
			continue
		var ent: Dictionary = actors[kind]
		var tags: Dictionary = ent["tags"]
		var names := tags.keys()
		var want: Array = exp[kind].keys()
		names.sort()
		want.sort()
		t.equal(names, want, "AD-065 tag set: " + kind)
		for n in exp[kind]:
			if tags.has(n):
				t.equal(int(tags[n]["frames"]), int(exp[kind][n]), "AD-065 card frames: %s/%s" % [kind, n])
		if kind == "undead_warden":
			for n in want:
				t.equal(str(tags[n]["sheet"]), "late" if n in WARDEN_LATE else "main", "AD-065 warden sheet: " + n)
		for key in ent["sheets"]:
			var sh: Dictionary = ent["sheets"][key]
			var sub := {}
			for n in tags:
				if tags[n]["sheet"] == key:
					sub[n] = tags[n]
			t.check(load(sh["png"]) is Texture2D, "AD-065 png loads: %s/%s" % [kind, key])
			_check_json(t, sh["json"], sub, "%s/%s" % [kind, key])
			if sh["left_json"] != null:
				t.check(load(sh["left_png"]) is Texture2D, "AD-065 left png loads: %s/%s" % [kind, key])
				_check_json(t, sh["left_json"], sub, "%s/%s left" % [kind, key])
			else:
				t.check(bool(ent["mirror"]), "AD-065 no left sheet means mirror: %s/%s" % [kind, key])
