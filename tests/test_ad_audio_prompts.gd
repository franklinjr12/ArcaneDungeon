extends RefCounted
## AD-226: the musicgen prompt pack (docs/demo/AUDIO_PROMPTS.md) matches the cue table.
const Director = preload("res://game/audio/audio_director.gd")

func run(t) -> void:
	var d = Director.new()
	var text: String = FileAccess.get_file_as_string("res://docs/demo/AUDIO_PROMPTS.md")
	var re := RegEx.create_from_string("(?m)^### \\d+\\. `([^`]+)`[^\\n]*\\n- File: `([^`]+)`")
	var pack := {}
	for m in re.search_all(text):
		pack[m.get_string(1)] = m.get_string(2)
	t.equal(pack.size(), 79, "AD-226 prompt pack has 79 cue blocks")
	# Expected file per id: cue streams plus music contexts (music.<ctx>), res:// stripped.
	var expected := {}
	for id in d.table["cues"]:
		expected[id] = str(d.table["cues"][id]["stream"]).trim_prefix("res://")
	var contexts: Dictionary = d.table["music"]["contexts"]
	for ctx in contexts:
		expected["music." + ctx] = str(contexts[ctx]["stream"]).trim_prefix("res://")
	t.equal(expected.size(), 79, "AD-226 cue table has 79 ids")
	for id in expected:
		t.check(pack.has(id), "AD-226 prompt pack covers: " + id)
		t.equal(pack.get(id, ""), expected[id], "AD-226 prompt file matches stream: " + id)
		t.check(expected[id].ends_with(".wav"), "AD-226 stream is wav: " + id)
	for id in pack:
		t.check(expected.has(id), "AD-226 prompt pack id is in table: " + id)
	var events: Dictionary = d.table["events"]
	t.equal(events["telegraph:ghoul_stalker"], "sfx.tele.ghoul_stalker", "AD-226 ghoul_stalker telegraph event")
	t.equal(events["telegraph:riptide_leaper"], "sfx.tele.riptide_leaper", "AD-226 riptide_leaper telegraph event")
	for id in ["sfx.tele.ghoul_stalker", "sfx.tele.riptide_leaper"]:
		var cue: Dictionary = d.table["cues"][id]
		t.equal(int(cue["priority"]), 3, "AD-226 telegraph priority: " + id)
		t.equal(float(cue["volume_db"]), -10.0, "AD-226 telegraph volume: " + id)
		var path: String = d.resolve_path(id, cue)
		t.check(path != "" and load(path) is AudioStream, "AD-226 placeholder loads while .wav is absent: " + id)
	d.free()
