extends RefCounted
## AD-020: AudioDirector cue table, voice limits, missing-stream silence.
const Director = preload("res://game/audio/audio_director.gd")
const IDS := ["sfx.cast.neutral","sfx.cast.fire","sfx.cast.water","sfx.cast.lightning","sfx.hit.generic","sfx.react.arc","sfx.react.extinguish","sfx.dash","sfx.dash.iframe","sfx.cast.rejected","sfx.tele.bone_thrall","sfx.tele.fallen_adept","sfx.tele.grave_hound","sfx.boss.tele_a","sfx.boss.tele_b","sfx.boss.phase","sfx.boss.death","sfx.player.hurt","sfx.player.death","sfx.room.cleared","sfx.pickup.rune","sfx.pickup.currency","ui.hover","ui.confirm","ui.cancel","ui.editor_error","ui.purchase","ui.reward_pick","amb.ruins","amb.workshop"]

func run(t) -> void:
	var d = Director.new()
	var cues: Dictionary = d.table.get("cues", {})
	t.equal(cues.size(), IDS.size(), "AD-020 cue table has 30 cues")
	for id in IDS:
		t.check(cues.has(id), "AD-020 cue present: " + id)
	t.equal(cues["sfx.tele.grave_hound"]["priority"], 3, "AD-020 telegraph priority")
	t.equal(cues["sfx.player.hurt"]["priority"], 2, "AD-020 hurt priority")
	t.check(cues["amb.ruins"].get("loop", false), "AD-020 amb loops")
	# Missing stream: silent, never crashes, spy still fires.
	var spy := []
	d.cue_played.connect(func(c, p, ok): spy.append([c, ok]))
	t.check(not d.play("sfx.dash"), "AD-020 missing stream returns false")
	t.check(not d.play("sfx.dash"), "AD-020 missing stream repeat returns false")
	t.check(not d.play("no.such.cue"), "AD-020 unknown cue returns false")
	t.equal(spy.size(), 3, "AD-020 spy sees every play call")
	t.check(d._warned.has("sfx.dash") and d._warned.size() == 2, "AD-020 warn once per cue")
	t.equal(d.voices.size(), 0, "AD-020 no voices for missing streams")
	# Voice limits and telegraph survival.
	var s := AudioStreamWAV.new()
	for id in IDS:
		d.register_stream(id, s)
	t.check(d.play("sfx.tele.bone_thrall"), "AD-020 telegraph plays")
	for i in 32:
		d.play("sfx.hit.generic")
		d.play("sfx.cast.fire")
		d.play("ui.hover")
	t.check(d.voices.size() <= 24, "AD-020 total voice cap")
	var tele = d.voices.filter(func(v): return v["cue_id"] == "sfx.tele.bone_thrall")
	t.equal(tele.size(), 1, "AD-020 telegraph survives 32-voice flood")
	var hits = d.voices.filter(func(v): return v["cue_id"] == "sfx.hit.generic")
	t.equal(hits.size(), 6, "AD-020 per-cue max voices")
	# Telegraphs fill their cap; a further telegraph is dropped, not stealing.
	for i in 6:
		d.play("sfx.boss.tele_a")
	t.equal(d.voices.filter(func(v): return v["cue_id"] == "sfx.boss.tele_a").size(), 4, "AD-020 telegraph cap")
	t.check(not d.play("sfx.boss.tele_a"), "AD-020 telegraph never stolen")
	# Invalid table is a no-op.
	d.load_table({})
	t.check(not d.play("sfx.dash"), "AD-020 empty table no-op")
	d.free()
