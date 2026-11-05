extends RefCounted
## AD-137 step 1: generic hooks for the Stage 1 enemies (turn rate, shield break, channel weakness, intangible_cycle).
const Session = preload("res://combat/combat_session.gd")
const Registry = preload("res://combat/enemy_behaviours/registry.gd")

func run(t) -> void:
	_turn_rate(t)
	_flank(t)
	_force_break(t)
	_weakness(t)
	_intangible(t)
	_registry(t)

func _spawn(offset: Vector2, overrides: Dictionary) -> Array:
	var s = Session.new(137,"empty",0)
	var config: Dictionary = s.data["enemies"]["bone_thrall"].duplicate(true)
	config.merge(overrides,true)
	s.data["enemies"]["probe"] = config
	var enemy = s.spawn_enemy("probe",s.sim.actor.position+offset)
	return [s,enemy]

func _steps(s, n: int) -> void:
	for i in n:
		s.step()

func _armor(s) -> float:
	return float(s.sim.settings["combat"]["armor_scale"])

func _turret_with(extra: Array, turn: float = 0.0) -> Dictionary:
	return {"turn_rate_degrees_per_tick":turn,"behaviours":[{"id":"turret"}]+extra}

func _turn_rate(t) -> void:
	var pair := _spawn(Vector2(250,0),_turret_with([],5.0))
	var s = pair[0]
	var enemy = pair[1]
	s.step()
	t.check(enemy.heading.is_equal_approx(Vector2.LEFT),"AD-137 turn rate: facing the player initially")
	s.sim.actor.position = enemy.target.position+Vector2(250,0)
	s.step()
	t.check(absf(rad_to_deg(enemy.heading.angle_to(Vector2.RIGHT))) > 170.0,"AD-137 turn rate: heading does not snap (%s)" % str(enemy.heading))
	_steps(s,60)
	t.check(enemy.heading.is_equal_approx(Vector2.RIGHT),"AD-137 turn rate: heading converges (%s)" % str(enemy.heading))

func _flank(t) -> void:
	var shield := {"id":"shield_front","front_damage_scale":0.5,"front_arc_degrees":60}
	var pair := _spawn(Vector2(250,0),_turret_with([shield],5.0))
	var s = pair[0]
	var enemy = pair[1]
	s.step()
	var plain: float = _spawn(Vector2(250,0),_turret_with([]))[1].target.receive_damage(20.0,"physical",s.sim.actor.team,_armor(s))
	var front: float = enemy.target.receive_damage(20.0,"physical",s.sim.actor.team,_armor(s))
	t.check(plain > 0.0 and is_equal_approx(front,plain*0.5),"AD-137 flank: frontal hit is reduced (%f vs %f)" % [front,plain])
	s.sim.actor.position = enemy.target.position+Vector2(250,0)
	s.step()
	var back: float = enemy.target.receive_damage(20.0,"physical",s.sim.actor.team,_armor(s))
	t.check(is_equal_approx(back,plain),"AD-137 flank: hit from behind inside the turn window is full (%f vs %f)" % [back,plain])

func _force_break(t) -> void:
	var shield := {"id":"shield_front","front_damage_scale":0.5,"front_arc_degrees":60,"break_impulse_speed":100}
	var pair := _spawn(Vector2(250,0),_turret_with([shield]))
	var s = pair[0]
	var enemy = pair[1]
	s.step()
	t.check(not enemy.shield_broken and is_equal_approx(enemy.target.damage_scale,0.5),"AD-137 shield intact without knockback")
	enemy.target.impulse = Vector2(300,0)
	s.step()
	t.check(enemy.shield_broken and enemy.target.damage_scale == 1.0,"AD-137 Force knockback breaks the shield (%s, %f)" % [str(enemy.shield_broken),enemy.target.damage_scale])
	var none := _spawn(Vector2(250,0),_turret_with([{"id":"shield_front","front_damage_scale":0.5,"front_arc_degrees":60}]))
	none[1].target.impulse = Vector2(900,0)
	none[0].step()
	t.check(not none[1].shield_broken and is_equal_approx(none[1].target.damage_scale,0.5),"AD-137 shield without break_impulse_speed never breaks")

func _weakness(t) -> void:
	var weak := _spawn(Vector2(250,0),_turret_with([]))
	weak[1].target.health.resistances = {}
	var s = weak[0]
	var base: float = weak[1].target.receive_damage(20.0,"fire",s.sim.actor.team,_armor(s))
	var phys_base: float = _spawn(Vector2(250,0),_turret_with([]))[1].target.receive_damage(20.0,"physical",s.sim.actor.team,_armor(s))
	var pair := _spawn(Vector2(250,0),{"channel_resistances":{"fire":-0.5},"behaviours":[{"id":"turret"}]})
	var fire: float = pair[1].target.receive_damage(20.0,"fire",s.sim.actor.team,_armor(s))
	var phys: float = pair[1].target.receive_damage(20.0,"physical",s.sim.actor.team,_armor(s))
	t.check(base > 0.0 and is_equal_approx(fire,base*1.5),"AD-137 fire weakness deals 1.5x (%f vs %f)" % [fire,base])
	t.check(is_equal_approx(phys,phys_base),"AD-137 fire weakness leaves physical damage unchanged")

func _intangible(t) -> void:
	var cycle := {"id":"intangible_cycle","period_ticks":10,"warn_ticks":2,"intangible_ticks":3,"intangible_damage_scale":0.0}
	var pair := _spawn(Vector2(250,0),_turret_with([cycle]))
	var s = pair[0]
	var enemy = pair[1]
	var armor := _armor(s)
	for i in 20:
		s.step()
		var phase := i%10
		var warn := phase < 2
		var ghost := phase >= 2 and phase < 5
		t.check(enemy.intangible_warning == warn and enemy.intangible == ghost,"AD-137 intangible_cycle flags at tick %d" % i)
		var dealt: float = enemy.target.receive_damage(1.0,"physical",s.sim.actor.team,armor)
		t.check((dealt == 0.0) == ghost,"AD-137 intangible_cycle damage at tick %d (%f)" % [i,dealt])

func _registry(t) -> void:
	var good := {"id":"intangible_cycle","period_ticks":10,"warn_ticks":2,"intangible_ticks":3}
	t.check(Registry.SCRIPTS["intangible_cycle"].validate(good).is_empty(),"AD-137 valid intangible_cycle accepted")
	var bad: Array = [{"period_ticks":10,"warn_ticks":2},
		{"period_ticks":10,"warn_ticks":5,"intangible_ticks":5},
		{"period_ticks":10,"warn_ticks":0,"intangible_ticks":3},
		{"period_ticks":10,"warn_ticks":2,"intangible_ticks":3,"intangible_damage_scale":2.0},
		{"period_ticks":"x","warn_ticks":2,"intangible_ticks":3}]
	for entry in bad:
		t.check(not Registry.SCRIPTS["intangible_cycle"].validate(entry).is_empty(),"AD-137 bad intangible_cycle rejected %s" % str(entry))
	t.check(not Registry.SCRIPTS["shield_front"].validate({"front_damage_scale":0.5,"front_arc_degrees":60,"break_impulse_speed":-1}).is_empty(),"AD-137 negative break_impulse_speed rejected")
