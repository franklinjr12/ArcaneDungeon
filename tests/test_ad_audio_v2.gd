extends RefCounted
## AD-151: music bus, per-context crossfade, placeholder fallback.
const Director = preload("res://game/audio/audio_director.gd")
const Session = preload("res://combat/combat_session.gd")
const M1_RUNES := ["form.projectile", "form.burst", "form.orb", "mod.homing", "mod.split", "mod.pierce"]

func _json(path: String) -> Dictionary:
	return JSON.parse_string(FileAccess.get_file_as_string(path))

## Event keys derived from the data files, never a hardcoded list.
func _expected_keys() -> Array:
	var keys: Array = []
	for r in _json("res://magic/data/runes_v2.json")["runes"]:
		var id := str(r["id"])
		match str(r["category"]):
			"essence": keys.append("cast:" + id.trim_prefix("essence."))
			"form": if id not in M1_RUNES: keys.append("form:" + id)
			"modifier": if id not in M1_RUNES: keys.append("mod:" + id)
			"trigger": keys.append("trigger:" + id)
	for rule in _json("res://magic/data/magic_balance_v1.json")["reactions"]["rules"]:
		keys.append("reaction:" + str(rule["id"]))
	keys.append("reaction:wet_lightning_arc")
	keys.append("status:burning:removed")
	var tuning := _json("res://combat/combat_tuning_v1.json")
	for kind in tuning["enemies"]:
		keys.append("telegraph:" + kind)
	for id in tuning["mini_bosses"]:
		var kind := str(tuning["mini_bosses"][id]["kind"])
		keys.append("telegraph:%s:a" % kind)
		keys.append("telegraph:%s:b" % kind)
	for id in _json("res://world/data/run_v2.json")["bosses"]:
		var kind := str(_json("res://world/data/run_v2.json")["bosses"][id]["kind"])
		keys.append("telegraph:%s:a" % kind)
		keys.append("telegraph:%s:b" % kind)
		keys.append("phase:" + kind)
	for id in _json("res://world/data/artifacts_v1.json")["artifacts"]:
		keys.append("artifact:" + id)
	var kinds: Dictionary = _json("res://world/data/env_props_v1.json")["kinds"]
	for kind in kinds:
		var rule: Dictionary = kinds[kind]
		if rule.has("ignite_by"):
			keys.append_array(["env:%s:ignite" % kind, "env:%s:burn_out" % kind])
		if rule.has("freeze_by"):
			keys.append_array(["env:%s:freeze" % kind, "env:%s:thaw" % kind])
		if rule.has("break_by"):
			keys.append("env:%s:break" % kind)
	return keys

func _coverage(t) -> void:
	if AudioServer.get_bus_index("SFX") < 0:
		AudioServer.set_bus_layout(load("res://default_bus_layout.tres"))
	var d = Director.new()
	var cues: Dictionary = d.table["cues"]
	var floor_p := int(d.table["unstealable_priority"])
	for key in _expected_keys():
		var id: String = d.cue_for_event(key)
		t.check(id != "" and cues.has(id), "AD-151 event has a cue: " + key)
		if id == "" or not cues.has(id):
			continue
		var cue: Dictionary = cues[id]
		t.check(AudioServer.get_bus_index(str(cue["bus"])) >= 0, "AD-151 cue bus exists: " + id)
		var path: String = d.resolve_path(id, cue)
		t.check(path != "" and load(path) is AudioStream, "AD-151 cue stream or placeholder loads: " + id)
		if key.begins_with("telegraph:"):
			t.check(int(cue["priority"]) >= floor_p, "AD-151 telegraph keeps priority: " + id)
	for id in cues:
		if id.begins_with("sfx.tele.") or (id.begins_with("sfx.boss.") and ".tele_" in id):
			t.check(int(cues[id]["priority"]) >= floor_p, "AD-151 telegraph cue priority: " + id)
	t.check(d.event_keys().size() > 0, "AD-151 event_keys lists the map")
	t.equal(d.cue_for_event("nope:nothing"), "", "AD-151 unmapped event gives empty cue")
	# A provided cue whose .wav is missing plays through its placeholder.
	d.voices.clear()
	t.check(not ResourceLoader.exists(cues["sfx.cast.cold"]["stream"]), "AD-151 cold .wav not yet provided")
	t.check(d.play("sfx.cast.cold"), "AD-151 missing provided file plays placeholder")
	d.voices.clear()
	# Dynamic: every cue a real session emits exists in the table.
	var seen: Array = []
	var arena = Session.new(7, "cluster", 2)
	arena.audio_sink = func(id, _pos): seen.append(id)
	var foe = arena.enemies[0]
	for i in 6:
		arena.issue({"cast": 1, "cursor": foe.target.position, "aim": Vector2.RIGHT})
		arena.step()
		arena.issue({"cast": 2, "aim": (foe.target.position - arena.sim.actor.position).normalized()})
		for k in 40:
			arena.step()
	t.check(seen.size() > 0, "AD-151 session emitted cues")
	for id in seen:
		t.check(id.begins_with("music.") or cues.has(id), "AD-151 emitted cue exists: " + id)
	d.free()

func run(t) -> void:
	_coverage(t)
	var d = Director.new()
	var secs := float(d.table.get("music", {}).get("crossfade_sec", 0.0))
	t.check(secs > 0.0, "AD-151 crossfade_sec in table")
	for ctx in ["ruins", "cistern", "workshop", "boss"]:
		var path: String = d.music_stream_path(ctx)
		t.check(path != "" and load(path) is AudioStream, "AD-151 music stream resolves: " + ctx)
	d.set_music_context("ruins")
	d.music_step(100.0)
	t.equal(d.music_fade_in, 1.0, "AD-151 first context fully faded in")
	t.check(d.set_music_context("workshop"), "AD-151 switch to workshop")
	d.music_step(secs * 0.5)
	t.check(absf(d.music_fade_in - 0.5) < 0.01 and absf(d.music_fade_out - 0.5) < 0.01, "AD-151 half-way gains 0.5/0.5")
	t.check(absf(d.music_fade_in + d.music_fade_out - 1.0) < 0.01, "AD-151 gains sum to 1")
	t.check(d.set_music_context("workshop"), "AD-151 same context is a no-op")
	t.check(absf(d.music_fade_in - 0.5) < 0.01, "AD-151 same context does not restart fade")
	d.music_step(secs)
	t.equal(d.music_fade_in, 1.0, "AD-151 fade_in done")
	t.equal(d.music_fade_out, 0.0, "AD-151 fade_out done")
	t.equal(d.music_context, "workshop", "AD-151 context workshop")
	t.check(not d.set_music_context("nope"), "AD-151 unknown context rejected")
	t.equal(d.music_context, "workshop", "AD-151 unknown context leaves state")
	t.check(d.play("music.boss"), "AD-151 play(music.boss)")
	t.equal(d.music_context, "boss", "AD-151 play music.* switches context")
	d.music_step(secs * 0.25)
	var before: float = d.music_fade_in
	d.set_music_context("cistern") # mid-fade: continues from current gains
	t.check(absf(d.music_fade_out - before) < 0.01, "AD-151 mid-fade switch has no pop")
	d.music_step(100.0)

	if AudioServer.get_bus_index("Music") < 0:
		AudioServer.set_bus_layout(load("res://default_bus_layout.tres"))
	var m := AudioServer.get_bus_index("Music")
	t.check(m >= 0, "AD-151 Music bus exists")
	if m >= 0:
		t.check(AudioServer.get_bus_effect(m, 0) is AudioEffectAmplify, "AD-151 Music slot 0 is Amplify")
		d._apply_duck(0.0)
		d.voices.clear()
		t.check(d.play("sfx.boss.tele_a"), "AD-151 telegraph plays")
		t.check(absf(d.duck_db("Music") - -6.0) < 0.01, "AD-151 telegraph ducks Music")
		d._process(10.0)
		t.equal(d.duck_db("Music"), 0.0, "AD-151 Music duck restored")
	d._apply_duck(0.0)
	d.free()
