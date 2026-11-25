extends RefCounted
## AD-237: new Ruins enemies. Step 1: Rune Sentry (rotating telegraphed beam).
const Session = preload("res://combat/combat_session.gd")
const Registry = preload("res://combat/enemy_behaviours/registry.gd")

func run(t) -> void:
	_sentry_config(t)
	_sentry_validate(t)
	_sentry_telegraph(t)
	_sentry_rotates(t)
	_sentry_off_beam(t)
	_sentry_static(t)
	_sentry_scenario(t)
	_sentry_deterministic(t)

func _sentry_session() -> Array:
	var s = Session.new(237,"empty",0)
	var player = s.sim.actor
	var sentry = s.spawn_enemy("rune_sentry",player.position+Vector2(250,0))
	return [s,sentry]

## Steps until the sentry enters `wanted` (guarded); returns true when reached.
func _until(s, sentry, wanted: String) -> bool:
	var guard := 0
	while sentry.state != wanted and guard < 400:
		s.step()
		guard += 1
	return sentry.state == wanted

func _sentry_config(t) -> void:
	var s = Session.new(237,"empty",0)
	var cfg: Dictionary = s.data["enemies"].get("rune_sentry",{})
	t.check(not cfg.is_empty() and Registry.validate_enemy(cfg).is_empty(),"AD-237 rune_sentry config validates")
	t.check(int(cfg["telegraph_ticks"]) >= 50,"AD-237 rune_sentry telegraph >= 50 ticks (%d)" % int(cfg["telegraph_ticks"]))
	t.check(float(cfg["move_speed"]) == 0.0,"AD-237 rune_sentry has move_speed 0")
	var negatives: Array = []
	for channel in cfg["channel_resistances"]:
		if float(cfg["channel_resistances"][channel]) < 0.0:
			negatives.append(channel)
	t.check(negatives == ["lightning"],"AD-237 rune_sentry has exactly one weakness: lightning (%s)" % str(negatives))
	var beam: Dictionary = {}
	for entry in cfg["behaviours"]:
		if entry["id"] == "rune_sentry":
			beam = entry
	var tangential: float = float(beam["beam_length"])*deg_to_rad(float(beam["beam_sweep_degrees_per_tick"]))*60.0
	t.check(tangential < float(s.data["player"]["move_speed"])*0.75,"AD-237 beam tip speed %.0f u/s is well below player speed" % tangential)

func _sentry_validate(t) -> void:
	var script = Registry.SCRIPTS["rune_sentry"]
	var good := {"id":"rune_sentry","beam_length":300,"beam_half_width":14,"beam_sweep_degrees_per_tick":0.5,"beam_active_ticks":180,"hit_interval_ticks":30}
	t.check(script.validate(good).is_empty(),"AD-237 valid rune_sentry accepted")
	for key in ["beam_length","beam_half_width","beam_sweep_degrees_per_tick","beam_active_ticks","hit_interval_ticks"]:
		var missing: Dictionary = good.duplicate()
		missing.erase(key)
		t.check(not script.validate(missing).is_empty(),"AD-237 rune_sentry missing %s rejected" % key)
		var zero: Dictionary = good.duplicate()
		zero[key] = 0
		t.check(not script.validate(zero).is_empty(),"AD-237 rune_sentry %s = 0 rejected" % key)
		var text: Dictionary = good.duplicate()
		text[key] = "x"
		t.check(not script.validate(text).is_empty(),"AD-237 rune_sentry non-numeric %s rejected" % key)

func _sentry_telegraph(t) -> void:
	var r := _sentry_session()
	var s = r[0]
	var sentry = r[1]
	var player = s.sim.actor
	var telegraph := int(sentry.tuning["telegraph_ticks"])
	t.check(_until(s,sentry,"windup"),"AD-237 sentry starts a windup when the player is in reach")
	var hp0: float = player.health.current
	var windup_ticks := 0
	var damaged_in_windup := false
	var guard := 0
	while sentry.state == "windup" and guard < 400:
		windup_ticks += 1
		if player.health.current < hp0:
			damaged_in_windup = true
		s.step()
		guard += 1
	t.check(not damaged_in_windup,"AD-237 no damage during the telegraph")
	t.check(windup_ticks == telegraph,"AD-237 windup lasts telegraph_ticks (%d vs %d)" % [windup_ticks,telegraph])
	t.check(sentry.state == "attack","AD-237 windup is followed by the attack state (%s)" % sentry.state)
	t.check(player.health.current == hp0,"AD-237 still undamaged at the first attack tick")
	guard = 0
	while sentry.state == "attack" and player.health.current == hp0 and guard < 400:
		s.step()
		guard += 1
	t.check(player.health.current < hp0 and sentry.state == "attack","AD-237 damage arrives only after the state changed to attack")

func _sentry_rotates(t) -> void:
	var r := _sentry_session()
	var s = r[0]
	var sentry = r[1]
	t.check(_until(s,sentry,"windup"),"AD-237 sentry windup reached for rotation test")
	var locked: Vector2 = sentry.intent.snapshot()["direction"]
	t.check(str(sentry.intent.snapshot()["geometry"]) == "line" and is_equal_approx(float(sentry.intent.snapshot()["range"]),300.0),"AD-237 intent is a line of beam_length")
	for i in int(sentry.tuning["telegraph_ticks"])-2:
		s.step()
	t.check(sentry.state == "windup" and sentry.intent.snapshot()["direction"].is_equal_approx(locked),"AD-237 beam direction stays locked during the telegraph")
	t.check(_until(s,sentry,"attack"),"AD-237 sentry reaches attack")
	var first: Vector2 = sentry.intent.snapshot()["direction"]
	s.step()
	var second: Vector2 = sentry.intent.snapshot()["direction"]
	var step_degrees := rad_to_deg(absf(first.angle_to(second)))
	t.check(not first.is_equal_approx(second),"AD-237 beam direction changes between active ticks")
	t.check(is_equal_approx(step_degrees,0.5),"AD-237 beam turns beam_sweep_degrees_per_tick (%f)" % step_degrees)
	t.check(first.angle_to(second) > 0.0,"AD-237 beam always sweeps the same (clockwise) way")

func _sentry_off_beam(t) -> void:
	var r := _sentry_session()
	var s = r[0]
	var sentry = r[1]
	var player = s.sim.actor
	t.check(_until(s,sentry,"windup"),"AD-237 windup reached for off-beam test")
	# The beam starts toward the player's old spot and sweeps away from the point directly below the sentry.
	player.position = sentry.target.position+Vector2(0,150)
	var hp0: float = player.health.current
	var guard := 0
	while sentry.state != "recover" and guard < 600:
		s.step()
		guard += 1
	t.check(sentry.state == "recover","AD-237 sentry finishes its sweep")
	t.check(player.health.current == hp0,"AD-237 a player off the beam line takes no damage")

func _sentry_static(t) -> void:
	var r := _sentry_session()
	var s = r[0]
	var sentry = r[1]
	var at: Vector2 = sentry.target.position
	var moved := false
	for i in 500:
		s.step()
		if sentry.target.position != at:
			moved = true
	t.check(not moved,"AD-237 rune_sentry never moves through a full attack cycle")

func _sentry_scenario(t) -> void:
	var s = Session.new(237,"rune_sentry",0)
	var kinds: Array = s.enemies.map(func(e): return e.kind)
	t.check(s.scenario == "rune_sentry" and kinds == ["rune_sentry"],"AD-237 scenario rune_sentry has exactly one rune_sentry (%s)" % str(kinds))
	t.check(str(s.data["scenarios"]["rune_sentry"]["name"]) == "Rune Sentry","AD-237 scenario is named Rune Sentry")

func _sentry_run() -> Array:
	var r := _sentry_session()
	var s = r[0]
	var sentry = r[1]
	for i in 170:
		s.step()
	return [s.sim.actor.health.current,sentry.intent.snapshot()["direction"] if sentry.intent != null else Vector2.ZERO,sentry.state]

func _sentry_deterministic(t) -> void:
	var a := _sentry_run()
	var b := _sentry_run()
	t.check(a == b and a[2] == "attack","AD-237 sentry run deterministic (hp, beam direction, state)")
