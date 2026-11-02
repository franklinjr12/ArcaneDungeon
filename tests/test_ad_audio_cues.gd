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
	t.equal(cues.size(), GDD_CUES.size(), "AD-082 table has no cues outside GDD list")
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
