extends RefCounted
## AD-020: AudioDirector cue table, voice limits, missing-stream silence.
const Director = preload("res://game/audio/audio_director.gd")
const Flow = preload("res://world/run_flow.gd")
const Driver = preload("res://tests/m3_run_driver.gd")
const Session = preload("res://combat/combat_session.gd")
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
	# Generated placeholder streams exist and load.
	for id in IDS:
		var path: String = cues[id]["stream"]
		t.check(path.ends_with(".wav") and ResourceLoader.exists(path), "AD-021 stream exists: " + id)
	t.check(d._resolve_stream("amb.ruins", cues["amb.ruins"]["stream"]).loop_mode != AudioStreamWAV.LOOP_DISABLED, "AD-021 amb.ruins imports looping")
	t.check(d._resolve_stream("sfx.dash", cues["sfx.dash"]["stream"]).loop_mode == AudioStreamWAV.LOOP_DISABLED, "AD-021 sfx do not loop")
	# Missing stream: silent (point one cue at a bogus path)
	d.table["cues"]["sfx.dash"]["stream"] = "res://assets/audio/sfx/missing.wav"
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
	_route(t)

## M3 scripted route recorded by a spy; hooks are read-only so state must match a sink-less run.
func _route(t) -> void:
	var director = Director.new()
	var seen := {}
	director.cue_played.connect(func(c, _p, _ok): seen[c] = int(seen.get(c, 0)) + 1)
	var flow = Flow.new(20261022)
	var plain = Flow.new(20261022)
	flow.audio_sink = director.play
	for index in 4:
		var room_name: String = str(flow.room.values["id"])
		Driver.fight(flow, 4600)
		Driver.fight(plain, 4600)
		t.equal(flow.session.sim.trace.to_json(), plain.session.sim.trace.to_json(), "AD-020 hooks leave trace identical " + room_name)
		var a: Dictionary = flow.session.snapshot()
		var b: Dictionary = plain.session.snapshot()
		a.erase("frame_ms")
		b.erase("frame_ms")
		t.equal(a, b, "AD-020 hooks leave snapshot identical " + room_name)
		if index < 3:
			flow.choose_reward(0)
			plain.choose_reward(0)
		Driver.reach_exit(flow)
		Driver.reach_exit(plain)
	# Workshop: shop, editor error, test cast.
	flow.run.currency = 500
	flow.buy(0)
	flow.open_editor(0)
	flow.editor.draft["root"]["manifestation_id"] = "form.none"
	flow.close_editor(true)
	flow.close_editor(false)
	flow.test_cast(1, Vector2.RIGHT)
	# Scripted extras for cues the autoplay policy does not reach (same spy, same sink path).
	var arena = Session.new(7, "cluster", 2)
	arena.audio_sink = director.play
	var foe = arena.enemies[0]
	for i in 6:
		arena.issue({"cast": 1, "cursor": foe.target.position, "aim": Vector2.RIGHT})
		arena.step()
		arena.issue({"cast": 2, "aim": (foe.target.position - arena.sim.actor.position).normalized()})
		for k in 12:
			arena.step()
	arena.issue({"cast": 3})
	var killer = arena.spawn_enemy("bone_thrall", Vector2(600, 450))
	if killer == null:
		killer = arena.enemies[arena.enemies.size() - 1]
	# Dash i-frames: the autoplay route no longer evades by chance after the AD-065 radii.
	for k in 120:
		arena.step()
	arena.issue({"dash": true, "move": Vector2.RIGHT})
	arena.step()
	arena.damage_player(killer.target.id, 5.0, "physical")
	for k in 60:
		arena.step()
	for i in 40:
		arena.damage_player(killer.target.id, 500.0, "physical")
	arena.step()
	var ui := Button.new()
	director.bind_button(ui)
	var back := Button.new()
	director.bind_button(back, "ui.cancel")
	ui.mouse_entered.emit()
	ui.pressed.emit()
	back.pressed.emit()
	ui.free()
	back.free()
	var missing := []
	for id in IDS:
		if not seen.has(id):
			missing.append(id)
	t.equal(missing, [], "AD-020 every cue fires in the scripted M3 route")
	for id in seen:
		t.check(id in IDS, "AD-020 only listed cues emitted: " + id)
	director.free()
