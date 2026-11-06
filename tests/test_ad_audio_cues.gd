extends RefCounted
## AD-082: every GDD §12 cue maps to a file + bus; README records sources.
const Director = preload("res://game/audio/audio_director.gd")
const GDD_CUES := [
	{"gdd": "Cast neutral", "id": "sfx.cast.neutral", "bus": "SFX"},
	{"gdd": "Cast fire", "id": "sfx.cast.fire", "bus": "SFX"},
	{"gdd": "Cast water", "id": "sfx.cast.water", "bus": "SFX"},
	{"gdd": "Cast lightning", "id": "sfx.cast.lightning", "bus": "SFX"},
	{"gdd": "Hit generic", "id": "sfx.hit.generic", "bus": "SFX"},
	{"gdd": "Reaction sting arc", "id": "sfx.react.arc", "bus": "SFX"},
	{"gdd": "Reaction sting extinguish", "id": "sfx.react.extinguish", "bus": "SFX"},
	{"gdd": "Dash whoosh", "id": "sfx.dash", "bus": "SFX"},
	{"gdd": "i-frame cue", "id": "sfx.dash.iframe", "bus": "SFX"},
	{"gdd": "Cast rejected / out of mana", "id": "sfx.cast.rejected", "bus": "SFX"},
	{"gdd": "Enemy windup bone thrall", "id": "sfx.tele.bone_thrall", "bus": "SFX"},
	{"gdd": "Enemy windup fallen adept", "id": "sfx.tele.fallen_adept", "bus": "SFX"},
	{"gdd": "Enemy windup grave hound", "id": "sfx.tele.grave_hound", "bus": "SFX"},
	{"gdd": "Warden telegraph A", "id": "sfx.boss.tele_a", "bus": "SFX"},
	{"gdd": "Warden telegraph B", "id": "sfx.boss.tele_b", "bus": "SFX"},
	{"gdd": "Warden phase", "id": "sfx.boss.phase", "bus": "SFX"},
	{"gdd": "Warden death", "id": "sfx.boss.death", "bus": "SFX"},
	{"gdd": "UI hover", "id": "ui.hover", "bus": "UI"},
	{"gdd": "UI confirm", "id": "ui.confirm", "bus": "UI"},
	{"gdd": "UI cancel", "id": "ui.cancel", "bus": "UI"},
	{"gdd": "UI editor error", "id": "ui.editor_error", "bus": "UI"},
	{"gdd": "UI purchase", "id": "ui.purchase", "bus": "UI"},
	{"gdd": "Pickup rune", "id": "sfx.pickup.rune", "bus": "SFX"},
	{"gdd": "Pickup currency", "id": "sfx.pickup.currency", "bus": "SFX"},
	{"gdd": "Pickup reward card", "id": "ui.reward_pick", "bus": "UI"},
	{"gdd": "Player hurt", "id": "sfx.player.hurt", "bus": "SFX"},
	{"gdd": "Player death", "id": "sfx.player.death", "bus": "SFX"},
	{"gdd": "Room cleared / door unlock", "id": "sfx.room.cleared", "bus": "SFX"},
	{"gdd": "Ambience stage (Uncatalogued Ruins)", "id": "amb.ruins", "bus": "Ambience"},
	{"gdd": "Ambience workshop", "id": "amb.workshop", "bus": "Ambience"}
]

func run(t) -> void:
	var d = Director.new()
	var cues: Dictionary = d.table.get("cues", {})
	var floor_p: int = int(d.table.get("unstealable_priority", 3))
	var readme := FileAccess.get_file_as_string("res://assets/audio/README.md")
	t.check(FileAccess.file_exists("res://assets/audio/README.md"), "AD-082 audio README exists")
	var gdd_ids: Array = GDD_CUES.map(func(e): return e["id"])
	for id in cues:
		if not bool(cues[id].get("provided", false)):
			t.check(id in gdd_ids, "AD-082 non-provided cue is in GDD list: " + id)
	for e in GDD_CUES:
		var id: String = e["id"]
		t.check(cues.has(id), "AD-082 cue present: " + id)
		if not cues.has(id):
			continue
		var c: Dictionary = cues[id]
		var path: String = c["stream"]
		print("AD-082 cue %s | %s | %s | %s" % [e["gdd"], id, path, c["bus"]])
		t.equal(c["bus"], e["bus"], "AD-082 bus: " + id)
		t.check(AudioServer.get_bus_index(e["bus"]) >= 0, "AD-082 bus exists: " + e["bus"])
		t.check(path.ends_with(".wav") and ResourceLoader.exists(path) and load(path) is AudioStream, "AD-082 stream loads: " + id)
		t.check(int(c["max_voices"]) >= 1, "AD-082 max_voices >= 1: " + id)
		if id.begins_with("sfx.tele.") or id == "sfx.boss.tele_a" or id == "sfx.boss.tele_b":
			t.check(int(c["priority"]) >= floor_p, "AD-082 telegraph unstealable: " + id)
		if id.begins_with("amb."):
			t.check(c.get("loop", false), "AD-082 ambience loops: " + id)
		t.check(readme.contains(id), "AD-082 README lists: " + id)
	d.free()
	_ducking(t)

func _ducking(t) -> void:
	if AudioServer.get_bus_index("SFXBed") < 0:
		AudioServer.set_bus_layout(load("res://default_bus_layout.tres"))
	var bed := AudioServer.get_bus_index("SFXBed")
	t.check(bed >= 0, "AD-082 SFXBed bus exists")
	if bed < 0:
		return
	t.equal(str(AudioServer.get_bus_send(bed)), "SFX", "AD-082 SFXBed sends to SFX")
	var sfx := AudioServer.get_bus_index("SFX")
	t.equal(AudioServer.get_bus_effect_count(sfx), 0, "AD-082 SFX bus has no ducking effect")
	var d = Director.new()
	var cues: Dictionary = d.table["cues"]
	var teles: Array = []
	var gdd_ids: Array = GDD_CUES.map(func(e): return e["id"])
	d._apply_duck(0.0) # earlier suites may have left the shared bus ducked
	t.equal(d.duck_db("Ambience"), 0.0, "AD-082 Ambience unducked at start")
	t.equal(d.duck_db("SFXBed"), 0.0, "AD-082 SFXBed unducked at start")
	for id in cues:
		var c: Dictionary = cues[id]
		var want: String = c["bus"]
		if want == "SFX":
			if d.is_telegraph(c):
				if id in gdd_ids:
					teles.append(id)
			else:
				want = "SFXBed"
		t.equal(d.route_bus(c), want, "AD-082 route_bus: " + id)
	t.equal(teles.size(), 5, "AD-082 five telegraph cues")
	d.play("sfx.hit.generic")
	t.equal(d.duck_db("Ambience"), 0.0, "AD-082 non-telegraph does not duck")
	t.check(not d.is_ducking(), "AD-082 not ducking after non-telegraph")
	var sfx_db := AudioServer.get_bus_volume_db(sfx)
	for id in teles:
		d.voices.clear()
		d._process(10.0)
		t.check(d.play(id), "AD-082 telegraph plays: " + id)
		t.check(absf(d.duck_db("Ambience") - -6.0) < 0.01, "AD-082 Ambience ducked: " + id)
		t.check(absf(d.duck_db("SFXBed") - -6.0) < 0.01, "AD-082 SFXBed ducked: " + id)
		t.equal(AudioServer.get_bus_volume_db(sfx), sfx_db, "AD-082 SFX bus volume untouched: " + id)
		t.equal(AudioServer.get_bus_effect_count(sfx), 0, "AD-082 telegraph path unducked: " + id)
		var length := maxf((load(cues[id]["stream"]) as AudioStream).get_length(), d.DUCK_MIN_SEC)
		d._process(length * 0.5)
		t.check(d.is_ducking() and d.duck_db("Ambience") < -5.9, "AD-082 still ducked mid-cue: " + id)
		d._process(length)
		t.equal(d.duck_db("Ambience"), 0.0, "AD-082 Ambience restored: " + id)
		t.equal(d.duck_db("SFXBed"), 0.0, "AD-082 SFXBed restored: " + id)
		t.check(not d.is_ducking(), "AD-082 not ducking after cue: " + id)
	# overlap: ducking lasts until the longer remaining cue ends
	d.voices.clear()
	d._process(10.0)
	d.play("sfx.boss.tele_a")
	d._process(0.1)
	d.play("sfx.boss.tele_b")
	var la := maxf((load(cues["sfx.boss.tele_a"]["stream"]) as AudioStream).get_length(), d.DUCK_MIN_SEC)
	var lb := maxf((load(cues["sfx.boss.tele_b"]["stream"]) as AudioStream).get_length(), d.DUCK_MIN_SEC)
	var rest := maxf(la - 0.1, lb)
	d._process(rest - 0.01)
	t.check(d.is_ducking(), "AD-082 overlap still ducked before longest ends")
	d._process(0.02)
	t.check(not d.is_ducking(), "AD-082 overlap released after longest ends")
	# voice caps
	for id in teles:
		d.voices.clear()
		for i in 10:
			d.play(id)
		var n: int = d.voices.filter(func(v): return v["cue_id"] == id).size()
		t.equal(n, int(cues[id]["max_voices"]), "AD-082 voice cap: " + id)
	d.voices.clear()
	d._process(10.0)
	d._apply_duck(0.0)
	d.free()
