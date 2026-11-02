extends RefCounted
## AD-083: reduce flash / reduce shake are honoured by every shake and flash source.
const RM = preload("res://ui/reduce_motion.gd")
const SettingsData = preload("res://game/core/settings.gd")
const Canvas = preload("res://ui/combat_canvas.gd")
const Flow = preload("res://world/run_flow.gd")

class SessionStub:
	var reduce_flashes := false

func _count_changes(values: Array) -> int:
	var n := 0
	for i in range(1, values.size()):
		if values[i] != values[i - 1]:
			n += 1
	return n

func run(t) -> void:
	var s = SettingsData.new()
	s.screen_shake = true
	s.reduce_flashes = false
	var any_shake := false
	for hf in range(1, 31):
		if RM.shake_offset(s, hf, 0) != Vector2.ZERO:
			any_shake = true
	t.check(any_shake, "AD-083 shake non-zero when screen_shake on")
	s.screen_shake = false
	var all_zero := true
	for hf in range(0, 31):
		for tick in range(4):
			if RM.shake_offset(s, hf, tick) != Vector2.ZERO:
				all_zero = false
	t.check(all_zero, "AD-083 shake exactly zero when screen_shake off")
	t.equal(RM.shake_offset(null, 0, 0), Vector2.ZERO, "AD-083 no shake without hit")

	s.reduce_flashes = true
	var tints := []
	for hf in range(10, 0, -1):
		tints.append(RM.hurt_tint(true, hf))
	t.equal(_count_changes(tints), 0, "AD-083 hurt tint constant across hit window")
	t.check(tints[0] != Color.WHITE, "AD-083 hurt tint visible when reduced")
	t.equal(RM.hurt_tint(true, 0), Color.WHITE, "AD-083 no tint without hit")

	var always_zero := true
	var any_alpha := false
	for hf in range(0, 31):
		if RM.overlay_alpha(true, hf) != 0.0:
			always_zero = false
		if RM.overlay_alpha(false, hf) > 0.0:
			any_alpha = true
	t.check(always_zero, "AD-083 overlay alpha 0 when reduced")
	t.check(any_alpha, "AD-083 overlay flashes when not reduced")

	for ev in RM.FLASH_EVENTS:
		var mods := []
		var ages_ok := true
		for age in range(61):
			var p: Dictionary = RM.fx_draw_params(true, ev, age)
			mods.append(p["modulate"])
			if p["age"] != 0:
				ages_ok = false
		t.check(ages_ok, "AD-083 %s frozen when reduced" % ev)
		t.check(_count_changes(mods) <= int(RM.MAX_TINT_HZ), "AD-083 %s tint <= 3 Hz" % ev)
		t.check(mods[0] != Color.WHITE, "AD-083 %s still tinted" % ev)
		t.equal(RM.fx_draw_params(false, ev, 7)["age"], 7, "AD-083 %s unchanged when not reduced" % ev)
	for ev in ["telegraph.circle", "telegraph.line", "telegraph.dash_lane"]:
		var p: Dictionary = RM.fx_draw_params(true, ev, 12)
		t.check(p["age"] == 12 and p["modulate"] == Color.WHITE, "AD-083 %s unchanged when reduced" % ev)

	var stub := SessionStub.new()
	var off = SettingsData.new()
	off.reduce_flashes = false
	var on = SettingsData.new()
	on.reduce_flashes = true
	t.check(not RM.flashes_reduced(off, stub), "AD-083 neither flag -> not reduced")
	t.check(RM.flashes_reduced(on, stub), "AD-083 settings flag reduces")
	stub.reduce_flashes = true
	t.check(RM.flashes_reduced(off, stub), "AD-083 session flag reduces")
	t.check(RM.flashes_reduced(null, stub), "AD-083 session flag reduces without settings")

	var flow = Flow.new(1)
	var canvas = Canvas.new()
	canvas.size = Vector2(916, 650)
	canvas.session = flow.session
	var cs = SettingsData.new()
	cs.screen_shake = false
	canvas.settings = cs
	flow.session.player.hit_flash = 0
	var base: Vector2 = canvas.camera_offset()
	flow.session.player.hit_flash = 10
	t.equal(canvas.camera_offset(), base, "AD-083 canvas camera steady with screen_shake off")
	cs.screen_shake = true
	t.check(canvas.camera_offset() != base, "AD-083 canvas camera shakes with screen_shake on")
	canvas.free()
