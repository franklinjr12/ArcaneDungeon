extends RefCounted
## AD-191: enemy/cast cue rate limits, voice caps, telegraph priority, EnemySFX bus.
const Director = preload("res://game/audio/audio_director.gd")

func _cues_matching(d, pred: Callable) -> Array:
	var out: Array = []
	for id in d.table["cues"]:
		if pred.call(id):
			out.append(id)
	return out

func _is_tele(id: String) -> bool:
	return id.begins_with("sfx.tele.") or ".tele_" in id

func run(t) -> void:
	if AudioServer.get_bus_index("EnemySFX") < 0:
		AudioServer.set_bus_layout(load("res://default_bus_layout.tres"))
	var d = Director.new()
	var cues: Dictionary = d.table["cues"]
	var teles := _cues_matching(d, _is_tele)
	var casts := _cues_matching(d, func(id): return id.begins_with("sfx.cast."))
	for id in cues:
		d.register_stream(id, AudioStreamWAV.new())
	# (a) 9 enemies, same tick
	var n := 0
	for i in 9:
		if d.play("sfx.tele.bone_thrall"):
			n += 1
	t.equal(n, 1, "AD-191 same-tick 9-enemy room admits 1 voice")
	# (b) spaced
	d.voices.clear()
	d._process(1.0)
	n = 0
	for i in 9:
		d._process(0.13)
		if d.play("sfx.tele.bone_thrall"):
			n += 1
	t.equal(n, 2, "AD-191 spaced 9-enemy room admits 2 plays")
	t.equal(d.voices.filter(func(v): return v["cue_id"] == "sfx.tele.bone_thrall").size(), 2, "AD-191 max 2 voices")
	# (c) cast spam
	d.voices.clear()
	d._process(1.0)
	t.check(d.play("sfx.cast.fire"), "AD-191 first cast plays")
	d._process(0.05)
	t.check(not d.play("sfx.cast.fire"), "AD-191 cast at 50 ms rejected")
	d._process(0.05)
	t.check(d.play("sfx.cast.fire"), "AD-191 cast at 100 ms accepted")
	# (d) telegraph priority
	t.equal(teles.size(), 17, "AD-191 17 telegraph cues")
	for id in teles:
		t.equal(int(cues[id]["priority"]), int(d.table["unstealable_priority"]), "AD-191 tele priority: " + id)
		t.check(d.is_telegraph(cues[id]), "AD-191 is_telegraph: " + id)
	d.voices.clear()
	d._process(1.0)
	t.check(d.play("sfx.boss.tele_a"), "AD-191 telegraph plays")
	for i in 60:
		d._process(0.2)
		d.play("sfx.hit.generic")
		d.play("sfx.cast.fire")
		d.play("ui.hover")
	t.check(d.voices.size() <= 24, "AD-191 total cap")
	t.check(d.voices.any(func(v): return v["cue_id"] == "sfx.boss.tele_a"), "AD-191 telegraph survives flood")
	# (e) data
	for id in teles + ["sfx.hit.generic"]:
		var c: Dictionary = cues[id]
		var db := float(c.get("volume_db", 0.0))
		t.check(db >= -14.0 and db <= -10.0, "AD-191 volume_db range: " + id)
		t.equal(float(c.get("pitch_jitter", 0.0)), 0.06, "AD-191 jitter: " + id)
		t.equal(float(c.get("rate_limit_ms", 0.0)), 120.0, "AD-191 rate limit: " + id)
		t.equal(int(c.get("max_voices", 0)), 2, "AD-191 max_voices: " + id)
	for id in casts:
		t.equal(float(cues[id].get("rate_limit_ms", 0.0)), 90.0, "AD-191 cast rate limit: " + id)
	# (f) voice values
	d.voices.clear()
	d._process(1.0)
	for id in ["sfx.tele.grave_hound", "sfx.hit.generic", "sfx.cast.water"]:
		t.check(d.play(id), "AD-191 plays " + id)
		var v = d.voices.back()
		t.check(v["pitch_scale"] >= 0.94 and v["pitch_scale"] <= 1.06, "AD-191 pitch range: " + id)
		t.equal(v["volume_db"], float(cues[id]["volume_db"]), "AD-191 voice volume: " + id)
	# (g) routing
	t.equal(d.route_bus(cues["sfx.tele.bone_thrall"]), "EnemySFX", "AD-191 tele routed to EnemySFX")
	t.check(d.route_bus(cues["sfx.hit.generic"]) != "EnemySFX", "AD-191 hit not on EnemySFX")
	var idx := AudioServer.get_bus_index("EnemySFX")
	t.check(idx >= 0, "AD-191 EnemySFX bus exists")
	t.equal(str(AudioServer.get_bus_send(idx)), "SFX", "AD-191 EnemySFX sends to SFX")
	t.check(AudioServer.get_bus_effect(idx, 0) is AudioEffectLowPassFilter, "AD-191 EnemySFX low-pass")
	# (h) no attack/fired cues
	for id in cues:
		t.check(not ("attack" in id or "fired" in id), "AD-191 no attack cue: " + id)
	for k in d.event_keys():
		t.check(not ("attack" in k or "fired" in k), "AD-191 no attack event: " + k)
	d.free()
