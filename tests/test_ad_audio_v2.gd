extends RefCounted
## AD-151: music bus, per-context crossfade, placeholder fallback.
const Director = preload("res://game/audio/audio_director.gd")

func run(t) -> void:
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
