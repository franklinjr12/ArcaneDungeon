extends RefCounted
## AD-200 steps 1-3: elite mini-boss kit (blink move, homing skull, decoy; storm crystal float path, beam sweep, electrify, Cold freeze, small crystals). All settings are synthetic.
const Session = preload("res://combat/combat_session.gd")
const BossCombat = preload("res://combat/boss_combat.gd")
const Minion = preload("res://combat/boss_moves/elite_minion.gd")
const Difficulty = preload("res://game/core/difficulty.gd")
const A := Vector2(400,200)
const B := Vector2(1000,200)
const C := Vector2(700,750)
const ANCHORS := [[400,200],[1000,200],[700,750]]
const PLAYER := Vector2(150,450)
const WaterTiles = preload("res://world/water_tiles.gd")
const Movement = preload("res://combat/boss_moves/boss_movement.gd")
const Enemy = preload("res://combat/enemy_combat.gd")
const POOL := [{"kind":"shallow","rect":[0,0,128,64]},{"kind":"shallow","rect":[500,0,64,64]},{"kind":"deep","rect":[128,0,64,64]}]
const BLINK := {"move":{"mode":"blink","blink_ticks":30,"radius":60}}

func run(t) -> void:
	_blink_telegraph(t)
	_blink_anchors(t)
	_blink_always_moves(t)
	_validate(t)
	_skull_spawn_and_homing(t)
	_skull_hits_once(t)
	_skull_dash(t)
	_skull_wall_and_lifetime(t)
	_skull_destroyed(t)
	_skull_cap(t)
	_decoy_spawned_once(t)
	_decoy_copies(t)
	_decoy_not_copied(t)
	_decoy_dies_to_one_hit(t)
	_minions_vanish_with_boss(t)
	_water_states(t)
	_water_shock(t)
	_float_path(t)
	_beam_telegraph(t)
	_beam_sweep(t)
	_beam_hits(t)
	_beam_speed_and_cancel(t)
	_electrify(t)
	_cold_freeze(t)
	_small_crystals(t)
	_crystal_validate(t)
	_crystal_rng(t)

func _cfg(phases: Array, extra: Dictionary = {}) -> Dictionary:
	var cfg := {"kind":"test_adept","hp":260,"radius":30,"recovery_ticks":10,"min_telegraph_ticks":36,"shot_speed":300,"shot_spread":0,
		"shot_damage":10,"radial_shots":4,"radial_damage":6,"fan_shots":3,"fan_arc_degrees":40,"telegraph_radius":190,"anchors":ANCHORS,
		"homing_skull":{"hp":6,"radius":20,"speed":120,"turn_deg_per_tick":3,"lifetime_ticks":300,"damage":9,"cap":2},
		"decoy":{"hp":1,"radius":26,"damage_multiplier":0.5,"copies":["fan","targeted"]},"phases":phases}
	return cfg.merged(extra,true)

func _patterns(names: Array, threshold: float = 1.0) -> Dictionary:
	return {"threshold":threshold,"windup_ticks":40,"patterns":names}

## Two phases: `first` patterns, then (at 50% hp, with a 20 tick roar and a decoy) `second`.
func _split(first: Array, second: Array, extra: Dictionary = {}) -> Dictionary:
	var phase_two := _patterns(second,0.5)
	phase_two["transition"] = {"roar_ticks":20,"arena_change":{}}
	phase_two["spawn_decoy"] = true
	return _cfg([_patterns(first),phase_two],extra)

func _fresh(cfg: Dictionary, at: Vector2 = A, player_at: Vector2 = PLAYER) -> Array:
	var s = Session.new(1981,"empty",0)
	s.defer_clear = true
	var boss = s.spawn_boss(cfg,at)
	s.sim.actor.position = player_at
	return [s,boss]

func _hp(s) -> float:
	return s.sim.actor.health.current

func _minions(s, minion_kind: String) -> Array:
	return s.enemies.filter(func(e): return e is Minion and e.kind == minion_kind)

func _step_until(s, limit: int, done: Callable) -> int:
	for i in limit:
		if done.call():
			return i
		s.step()
	return -1

## Advances the boss until the windup it just opened (state_tick 0).
func _open(s, boss) -> void:
	for i in 400:
		boss.advance(s)
		if boss.state == "windup" and boss.state_tick == 0:
			return

## Real player projectile of `essence` fired from the player along `dir`; only the sim steps (the AI stays frozen).
func _cast(s, essence: String, dir: Vector2, ticks: int) -> void:
	s.sim.loadout.allow_edit = true
	s.sim.equip(1,{"schema_version":1,"formula_id":"test.hit","display_name":"hit",
		"root":{"essence_id":essence,"manifestation_id":"form.projectile","modifier_ids":[],"params":{}}})
	s.sim.loadout.slots[1]["cooldown"] = 0
	s.sim.mana = 120.0
	s.sim.try_cast(1,s.sim.actor.position,dir)
	for i in ticks:
		s.sim.step()

func _queue_skull(s, boss, at: Vector2, heading: Vector2) -> Object:
	s.pending_spawns.append({"minion":"homing_skull","position":at,"summoner_id":boss.target.id,"heading":heading,"settings":boss.tuning["homing_skull"]})
	s._flush_pending_spawns()
	return _minions(s,"homing_skull").back()

# --- blink ---

## One entry per blink: telegraph in the intent, ticks the windup really took, positions before and after.
func _blinks(cfg: Dictionary, count: int, at: Vector2 = A) -> Array:
	var pair := _fresh(cfg,at)
	var out: Array = []
	for i in count:
		_open(pair[0],pair[1])
		var snap: Dictionary = pair[1].intent.snapshot()
		var from: Vector2 = pair[1].target.position
		var ticks := 0
		while pair[1].state == "windup":
			pair[1].advance(pair[0])
			ticks += 1
		out.append({"kind":snap["kind"],"telegraph":int(snap["telegraph_ticks"]),"ticks":ticks,"from":from,"to":pair[1].target.position,"landing":snap["landing"]})
	return out

func _blink_cfg(extra: Dictionary = {}) -> Dictionary:
	return _cfg([{"threshold":1.0,"windup_ticks":40,"pool":[BLINK]}],extra)

func _blink_telegraph(t) -> void:
	for scale in [1.0,2.0,0.5]:
		Difficulty.set_override({"telegraph_length":scale})
		var blinks := _blinks(_blink_cfg(),2)
		Difficulty.clear_override()
		for blink in blinks:
			t.check(blink["kind"] == "blink" and blink["telegraph"] == 30 and blink["ticks"] == 30,"AD-200 the blink telegraph is exactly 30 ticks at telegraph_length x%s (got %d/%d)" % [scale,blink["telegraph"],blink["ticks"]])
	var boss = _fresh(_blink_cfg())[1]
	t.equal(boss.tuning["phases"][0]["pool"][0]["move"]["blink_ticks"],30,"AD-200 blink_ticks is not floored to min_telegraph_ticks")

func _blink_anchors(t) -> void:
	var blinks := _blinks(_blink_cfg(),6)
	var previous: Vector2 = A
	var landed := {}
	var every_blink := true
	for blink in blinks:
		every_blink = every_blink and blink["to"] == blink["landing"] and blink["to"] != previous and blink["from"] == previous
		landed[blink["to"]] = true
		previous = blink["to"]
	t.check(every_blink,"AD-200 each blink lands on the announced anchor and never where the boss already stood: %s" % str(blinks.map(func(b): return b["to"])))
	t.check(landed.size() >= 2 and landed.keys().all(func(p): return [A,B,C].has(p)),"AD-200 the boss uses more than one of the 3 anchors")
	var nearest := _blinks(_blink_cfg({"phases":[{"threshold":1.0,"windup_ticks":40,"pool":[{"move":{"mode":"blink","blink_ticks":30,"radius":60,"anchor_pick":"nearest"}}]}]}),1)
	t.equal(nearest[0]["to"],C,"AD-200 anchor_pick nearest picks the nearest other anchor to the player")

func _blink_always_moves(t) -> void:
	var near_a := A+Vector2(5,0)
	var cfg := _blink_cfg({"anchors":[[400,200],[1000,200]]})
	t.equal(_blinks(cfg,1,near_a)[0]["to"],B,"AD-200 an anchor within 8 px of the boss is never the blink target")
	var lone := _blinks(_blink_cfg({"anchors":[[400,200]]}),1,A)
	t.equal(lone[0]["to"],A,"AD-200 with no other anchor the blink stays put without errors")

func _validate(t) -> void:
	var good := _split(["fan"],["fan"])
	t.equal(BossCombat.validate(good),[],"AD-200 a synthetic elite config is valid")
	t.equal(BossCombat.validate(_cfg([{"threshold":1.0,"windup_ticks":40,"pool":[{"pattern":"fan"},{"pattern":"targeted"},{"pattern":"radial"},BLINK]}])),[],"AD-200 a blink pool config is valid")
	var missing := _cfg([{"threshold":1.0,"windup_ticks":40,"pool":[{"move":{"mode":"blink"}}]}])
	var paths: Array = BossCombat.validate(missing).map(func(i): return i["path"])
	t.check(paths.has("phases[0].pool[0].move.blink_ticks") and paths.has("phases[0].pool[0].move.radius"),"AD-200 blink without blink_ticks/radius is reported: %s" % str(paths))
	t.contains_issue(BossCombat.validate(_blink_cfg({"anchors":[]})),"BOSS_MOVE_ANCHORS","AD-200 blink needs anchors")
	var no_cap := good.duplicate(true)
	no_cap["homing_skull"].erase("cap")
	t.contains_issue(BossCombat.validate(no_cap),"BOSS_ELITE_PARAM","AD-200 homing_skull without cap is invalid")
	var zero := good.duplicate(true)
	zero["homing_skull"]["speed"] = 0
	t.contains_issue(BossCombat.validate(zero),"BOSS_ELITE_PARAM","AD-200 homing_skull speed must be > 0")
	var no_mult := good.duplicate(true)
	no_mult["decoy"].erase("damage_multiplier")
	t.contains_issue(BossCombat.validate(no_mult),"BOSS_ELITE_PARAM","AD-200 decoy without damage_multiplier is invalid")
	var bad_copies := good.duplicate(true)
	bad_copies["decoy"]["copies"] = "fan"
	t.contains_issue(BossCombat.validate(bad_copies),"BOSS_ELITE_PARAM","AD-200 decoy.copies must be an array")
	var no_decoy := good.duplicate(true)
	no_decoy.erase("decoy")
	t.contains_issue(BossCombat.validate(no_decoy),"BOSS_ELITE_PARAM","AD-200 spawn_decoy needs a decoy block")
	var no_skull := _cfg([_patterns(["homing_skull","fan"])])
	no_skull.erase("homing_skull")
	t.contains_issue(BossCombat.validate(no_skull),"BOSS_ELITE_PARAM","AD-200 the homing_skull pattern needs its block")
	t.equal(BossCombat.validate({}),[],"AD-200 settings without the new keys add no issues")

# --- homing skull ---

func _skull_spawn_and_homing(t) -> void:
	var pair := _fresh(_cfg([_patterns(["homing_skull"])]),A,Vector2(400,600))
	var s = pair[0]
	var boss = pair[1]
	var windup := 0
	_open(s,boss)
	var snap: Dictionary = boss.intent.snapshot()
	t.check(snap["kind"] == "homing_skull" and snap["telegraph_shape"] == "slam" and snap["landing"] == A and int(snap["telegraph_ticks"]) == 40,"AD-200 the skull cast opens a slam windup at the boss with the phase windup ticks")
	while boss.state == "windup":
		boss.advance(s)
	t.equal(_minions(s,"homing_skull").size(),0,"AD-200 the skull is only queued until the AI loop ends")
	s._flush_pending_spawns()
	var skull = _minions(s,"homing_skull")[0]
	t.check(skull.summoner_id == boss.target.id and skull.target.tags == ["enemy","homing_skull"] and is_equal_approx(skull.target.health.current,6.0),"AD-200 the skull is a tagged target owned by the boss with settings hp")
	t.check(skull.tuning.has("color") and skull.tuning.has("telegraph_ticks") and skull.tuning.has("attack_range") and skull.tuning.has("display_name"),"AD-200 the minion carries the tuning fields other code reads")
	t.check(skull.target.position.distance_to(A) > 40.0 and skull.state == "fly","AD-200 the skull starts outside the boss, flying")
	# The player moves sideways: the skull turns by at most 3 degrees per tick and the angle to the player shrinks.
	s.sim.actor.position = Vector2(900,300)
	var start_error := absf(skull.heading.angle_to(s.sim.actor.position-skull.target.position))
	var largest := 0.0
	for i in 40:
		var before: Vector2 = skull.heading
		skull.advance(s)
		largest = maxf(largest,absf(before.angle_to(skull.heading)))
	var end_error := absf(skull.heading.angle_to(s.sim.actor.position-skull.target.position))
	t.check(largest <= deg_to_rad(3.0)+0.0001 and largest > 0.0,"AD-200 the skull turns by at most turn_deg_per_tick per tick")
	t.check(end_error < start_error,"AD-200 the skull homes toward the player")

func _skull_hits_once(t) -> void:
	var pair := _fresh(_cfg([_patterns(["homing_skull"])],{"recovery_ticks":400}),A,Vector2(400,500))
	var s = pair[0]
	var skull = null
	var found := _step_until(s,200,func(): return not _minions(s,"homing_skull").is_empty())
	skull = _minions(s,"homing_skull")[0]
	var hp := _hp(s)
	var dead := _step_until(s,400,func(): return not skull.target.alive())
	t.check(found >= 0 and dead >= 0,"AD-200 setup: the skull flew into the player")
	t.check(hp-_hp(s) > 0.0 and s.damage_events.size() == 1,"AD-200 the skull damages the player exactly once")
	var after := _hp(s)
	for i in 20:
		s.step()
	t.check(_hp(s) == after and skull.state == "dead","AD-200 the skull is gone after the hit and deals no more damage")

func _skull_dash(t) -> void:
	var pair := _fresh(_cfg([_patterns(["homing_skull"])],{"recovery_ticks":400}),A,Vector2(400,500))
	var s = pair[0]
	_step_until(s,200,func(): return not _minions(s,"homing_skull").is_empty())
	var skull = _minions(s,"homing_skull")[0]
	var hp := _hp(s)
	s.player.invulnerable_left = 1000
	_step_until(s,400,func(): return skull.target.position.distance_to(s.sim.actor.position) <= skull.target.radius+s.sim.actor.radius)
	s.step()
	t.check(skull.target.alive() and _hp(s) == hp,"AD-200 dash i-frames absorb the skull and it keeps flying")
	s.player.invulnerable_left = 0
	_step_until(s,10,func(): return not skull.target.alive())
	t.check(not skull.target.alive() and _hp(s) < hp,"AD-200 without i-frames the same skull hits and dies")

func _skull_wall_and_lifetime(t) -> void:
	# Wall (570..634 x 165..375) between the boss at A and a player to the east.
	var pair := _fresh(_cfg([_patterns(["fan"])]),A,Vector2(1100,270))
	var skull = _queue_skull(pair[0],pair[1],Vector2(520,270),Vector2.RIGHT)
	for i in 40:
		skull.advance(pair[0])
	t.check(not skull.target.alive() and _hp(pair[0]) == pair[0].sim.actor.health.maximum,"AD-200 a skull dies on a wall")
	var timed := _fresh(_cfg([_patterns(["fan"])],{"homing_skull":{"hp":6,"radius":20,"speed":10,"turn_deg_per_tick":3,"lifetime_ticks":50,"damage":9,"cap":2}}),A,Vector2(1100,800))
	var late = _queue_skull(timed[0],timed[1],Vector2(400,700),Vector2.RIGHT)
	for i in 49:
		late.advance(timed[0])
	t.check(late.target.alive(),"AD-200 the skull is alive just before lifetime_ticks")
	late.advance(timed[0])
	t.check(not late.target.alive(),"AD-200 the skull expires at lifetime_ticks")

func _skull_destroyed(t) -> void:
	for essence in ["essence.force","essence.fire"]:
		var pair := _fresh(_cfg([_patterns(["fan"])]),A,Vector2(400,700))
		var skull = _queue_skull(pair[0],pair[1],Vector2(400,550),Vector2.RIGHT)
		_cast(pair[0],essence,Vector2.UP,40)
		t.check(not skull.target.alive(),"AD-200 a %s projectile destroys the skull" % essence)
		skull.advance(pair[0])
		t.check(skull.state == "dead" and pair[0]._death_ids.has(skull.target.id),"AD-200 a destroyed skull reports its death")
	var direct := _fresh(_cfg([_patterns(["fan"])]),A,Vector2(400,700))
	var plain = _queue_skull(direct[0],direct[1],Vector2(400,550),Vector2.RIGHT)
	plain.target.receive_damage(6.0,"neutral",direct[0].sim.actor.team,1.0)
	t.check(not plain.target.alive(),"AD-200 settings hp 6 is destroyed by a 6 damage hit")

func _skull_cap(t) -> void:
	var pair := _fresh(_cfg([_patterns(["homing_skull"])]),A,Vector2(150,800))
	var s = pair[0]
	var peak := 0
	var casts := 0
	for i in 170:
		var before: int = pair[1].cycle
		s.step()
		casts += 1 if pair[1].cycle > before else 0
		peak = maxi(peak,_minions(s,"homing_skull").filter(func(m): return m.target.alive()).size())
	t.check(casts >= 3 and peak == 2,"AD-200 the boss casts a third skull but at most cap (2) exist (casts %d, peak %d)" % [casts,peak])
	t.check(s.enemies.filter(func(e): return e is Minion).size() == 2,"AD-200 the capped cast creates no third skull")

# --- decoy ---

## Hp to 50% so the next advance enters phase 2.
func _threshold(boss) -> void:
	boss.target.health.current = boss.target.health.maximum*0.5

func _decoy_spawned_once(t) -> void:
	var pair := _fresh(_split(["fan"],["fan"]))
	var s = pair[0]
	t.equal(_minions(s,"decoy").size(),0,"AD-200 no decoy before the threshold")
	for i in 5:
		s.step()
	t.equal(_minions(s,"decoy").size(),0,"AD-200 no decoy in phase 1")
	_threshold(pair[1])
	s.step()
	t.check(pair[1].state == "roar" and _minions(s,"decoy").size() == 1,"AD-200 one decoy appears when the phase 2 roar begins")
	var decoy = _minions(s,"decoy")[0]
	var farthest := A
	for anchor in [A,B,C]:
		if anchor.distance_to(A) > farthest.distance_to(A):
			farthest = anchor
	t.check(decoy.target.position == farthest and decoy.summoner_id == pair[1].target.id and decoy.target.tags == ["enemy","decoy"],"AD-200 the decoy stands at the anchor farthest from the boss")
	for i in 300:
		s.step()
	t.equal(_minions(s,"decoy").size(),1,"AD-200 the decoy is spawned once, not again later")
	decoy.kill(s)
	for i in 200:
		s.step()
	t.equal(_minions(s,"decoy").size(),1,"AD-200 a killed decoy is not replaced")
	t.check(decoy.target.position == farthest and decoy.state == "dead","AD-200 the decoy stood still")

func _first_shots(s, boss, ticks: int) -> Array:
	for i in ticks:
		s.step()
		if not s.enemy_shots.is_empty():
			return s.enemy_shots.duplicate()
	return []

func _decoy_copies(t) -> void:
	Difficulty.set_override({"enemy_damage":2.0})
	var pair := _fresh(_split(["fan"],["fan","targeted"]))
	var s = pair[0]
	var boss = pair[1]
	_threshold(boss)
	_step_until(s,60,func(): return boss.state == "windup")
	var decoy = _minions(s,"decoy")[0]
	t.check(decoy.state == "windup" and decoy.intent != null and decoy.intent.snapshot()["kind"] == "fan","AD-200 the decoy shows the fan telegraph while the boss winds up")
	t.check(decoy.intent.snapshot()["origin"] == decoy.target.position and boss.intent.snapshot()["origin"] == A and decoy.intent.snapshot()["telegraph_ticks"] == boss.intent.snapshot()["telegraph_ticks"],"AD-200 the decoy telegraph sits on the decoy with the boss's ticks")
	t.check(decoy.tuning["telegraph_ticks"] == 40 and decoy.tuning["attack_range"] == 190.0,"AD-200 the decoy tuning follows the shown telegraph")
	var shots := _first_shots(s,boss,80)
	var own: Array = shots.filter(func(x): return x["source_id"] == boss.target.id)
	var copy: Array = shots.filter(func(x): return x["source_id"] == decoy.target.id)
	t.equal([own.size(),copy.size()],[3,3],"AD-200 the boss and the decoy each fire the 3 shot fan")
	var full := Difficulty.scale_f(10.0,"enemy_damage")
	t.check(own.all(func(x): return is_equal_approx(float(x["damage"]),full)) and copy.all(func(x): return is_equal_approx(float(x["damage"]),full*0.5)),"AD-200 the decoy fan deals damage_multiplier x the boss damage")
	t.check(copy.all(func(x): return x["position"].distance_to(decoy.target.position) < 120.0) and decoy.state == "idle","AD-200 the decoy fan starts at the decoy, which then ends its telegraph")
	for i in 30:
		s.step()
	s.enemy_shots.clear()
	var second := _first_shots(s,boss,200)
	var targeted: Array = second.filter(func(x): return x["source_id"] == decoy.target.id)
	t.check(targeted.size() == 1 and is_equal_approx(float(targeted[0]["damage"]),full*0.5) and second.size() == 2,"AD-200 the decoy also copies the targeted shot")
	# Killing the decoy removes the shots it owns.
	decoy.kill(s)
	s.advance_enemy_projectiles()
	t.check(s.enemy_shots.all(func(x): return x["source_id"] != decoy.target.id),"AD-200 a dead decoy's shots vanish")
	Difficulty.clear_override()

func _decoy_not_copied(t) -> void:
	var pair := _fresh(_split(["fan"],["radial"]))
	var s = pair[0]
	_threshold(pair[1])
	_step_until(s,60,func(): return pair[1].state == "windup")
	var decoy = _minions(s,"decoy")[0]
	t.check(decoy.state == "idle" and decoy.intent == null,"AD-200 a pattern outside decoy.copies shows no decoy telegraph")
	var shots := _first_shots(s,pair[1],80)
	t.check(not shots.is_empty() and shots.all(func(x): return x["source_id"] == pair[1].target.id),"AD-200 a pattern outside decoy.copies is cast by the boss only")
	var skulls := _fresh(_split(["fan"],["homing_skull"],{"decoy":{"hp":1,"radius":26,"damage_multiplier":0.5,"copies":["homing_skull"]},"homing_skull":{"hp":6,"radius":20,"speed":120,"turn_deg_per_tick":3,"lifetime_ticks":300,"damage":9,"cap":3}}))
	_threshold(skulls[1])
	_step_until(skulls[0],200,func(): return _minions(skulls[0],"homing_skull").size() >= 2)
	var damages: Array = _minions(skulls[0],"homing_skull").map(func(m): return m._spec["damage"])
	var base: float = skulls[1].tuning["homing_skull"]["damage"]
	t.check(damages.size() == 2 and damages.has(base) and damages.has(base*0.5),"AD-200 a decoy copy of the skull cast adds one skull at the decoy's damage multiplier (%s)" % str(damages))

func _decoy_dies_to_one_hit(t) -> void:
	Difficulty.set_override({"enemy_hp":3.0})
	var pair := _fresh(_split(["fan"],["fan"]),A,Vector2(700,600))
	_threshold(pair[1])
	pair[0].step()
	var decoy = _minions(pair[0],"decoy")[0]
	Difficulty.clear_override()
	t.check(decoy.target.health.maximum == 1.0 and is_equal_approx(pair[1].target.health.maximum,780.0),"AD-200 the decoy hp is not difficulty scaled (the boss's is)")
	decoy.target.receive_damage(1.0,"neutral",pair[0].sim.actor.team,1.0)
	t.check(not decoy.target.alive(),"AD-200 the decoy dies to 1 damage")
	var real := _fresh(_split(["fan"],["fan"]),A,Vector2(700,600))
	_threshold(real[1])
	real[0].step()
	var live = _minions(real[0],"decoy")[0]
	var before: float = live.target.health.current
	_cast(real[0],"essence.force",Vector2.DOWN,40)
	t.check(before == 1.0 and not live.target.alive(),"AD-200 a real projectile kills the decoy")

func _minions_vanish_with_boss(t) -> void:
	var pair := _fresh(_split(["homing_skull"],["homing_skull","fan"]),A,Vector2(150,820))
	var s = pair[0]
	var boss = pair[1]
	_step_until(s,300,func(): return _minions(s,"homing_skull").size() >= 2)
	_threshold(boss)
	_step_until(s,60,func(): return not _minions(s,"decoy").is_empty())
	t.check(s.alive_enemies() >= 3,"AD-200 setup: the boss, its skulls and the decoy are alive")
	s.pending_spawns.append({"minion":"homing_skull","position":Vector2(300,300),"summoner_id":boss.target.id,"heading":Vector2.DOWN,"settings":boss.tuning["homing_skull"]})
	boss.target.health.current = 0.0 # the roar made it invulnerable to damage
	s.step()
	s.step()
	t.equal(s.alive_enemies(),0,"AD-200 alive_enemies reaches 0 when the boss dies")
	t.check(s.pending_spawns.is_empty() and _minions(s,"homing_skull").size() >= 2 and s.enemies.filter(func(e): return e is Minion).all(func(m): return m.state == "dead"),"AD-200 minions are dead and queued ones dropped when the boss dies")
	t.check(s.enemies.filter(func(e): return e is Minion).all(func(m): return s._death_ids.has(m.target.id)),"AD-200 every minion death is reported once")

func _water_states(t) -> void:
	var w = WaterTiles.new(POOL)
	var left := Vector2(16,16)
	var far := Vector2(520,16)
	t.check(not w.is_electrified(left) and w.state_view().is_empty(),"AD-200 a fresh water set has no cell states")
	w.electrify_body(w.body_of(far),10)
	t.check(w.is_electrified(far) and not w.is_electrified(left),"AD-200 electrify_body only touches that body")
	w.advance(9)
	t.check(w.is_electrified(far),"AD-200 an electrified cell is still live the tick before it expires")
	w.advance(10)
	t.check(not w.is_electrified(far) and w.state_view().is_empty(),"AD-200 an electrified cell expires on its exact tick")
	w.electrify_all(50)
	t.check(w.is_electrified(left) and w.is_electrified(far) and not w.is_electrified(Vector2(300,16)),"AD-200 electrify_all covers every water rect only")
	var body: int = w.body_of(left)
	w.freeze_circle(left,10,50)
	t.check(w.is_frozen(left) and not w.in_water(left) and w.body_of(left) == -1,"AD-200 a frozen cell is not water and has no body")
	t.check(w.in_water(Vector2(80,16)) and w.body_of(Vector2(80,16)) == body,"AD-200 the rest of the rect is still water")
	t.check(not w.is_electrified(left),"AD-200 a frozen cell is not electrified")
	w.electrify_all(60)
	t.check(not w.is_electrified(left) and w.is_electrified(Vector2(80,16)),"AD-200 a frozen cell cannot be electrified")
	w.freeze_circle(Vector2(160,16),80,50)
	t.check(w.in_water(Vector2(160,16)) and not w.is_frozen(Vector2(160,16)),"AD-200 deep cells are not frozen")
	var line = WaterTiles.new(POOL)
	line.freeze_segment(Vector2(40,48),Vector2(120,48),5,50)
	t.check(line.is_frozen(Vector2(72,48)) and not line.is_frozen(Vector2(72,8)),"AD-200 freeze_segment freezes cells along the line")
	var view: Array = w.state_view()
	var keys: Array = view.map(func(v): return Vector2i(v["cell_rect"].position)/32)
	var sorted := true
	for i in range(1,keys.size()):
		if keys[i].y < keys[i-1].y or (keys[i].y == keys[i-1].y and keys[i].x < keys[i-1].x):
			sorted = false
	t.check(sorted and view == w.state_view() and view[0].has("state"),"AD-200 state_view is stable and sorted")
	w.advance(50)
	t.check(not w.is_frozen(left) and w.in_water(left),"AD-200 a frozen cell thaws on its exact tick")
	w.electrify_all(99)
	w.remove_tag("none")
	w.clear_states()
	t.check(w.state_view().is_empty(),"AD-200 clear_states drops everything")
	var tagged = WaterTiles.new([{"kind":"shallow","rect":[0,0,64,64],"tag":"x"},{"kind":"shallow","rect":[500,0,64,64]}])
	tagged.electrify_all(99)
	tagged.remove_tag("x")
	t.check(not tagged.is_electrified(Vector2(16,16)) and tagged.is_electrified(Vector2(520,16)),"AD-200 a state on a removed rect is dropped")

func _shock_session(player_at: Vector2) -> Array:
	var pair := _fresh(_cfg([_patterns(["fan"])],{"recovery_ticks":4000}),Vector2(1000,700),player_at)
	pair[0].set_water(POOL)
	pair[0].water_shock = {"source_id":pair[1].target.id,"damage":5,"interval_ticks":10,"channel":"hazard"}
	return pair

func _water_shock(t) -> void:
	var pair := _shock_session(Vector2(16,16))
	var s = pair[0]
	s.water.electrify_all(1000)
	var hp := _hp(s)
	for i in 9:
		s.step()
	t.check(_hp(s) == hp,"AD-200 no shock damage before the interval")
	_step_until(s,2,func(): return _hp(s) < hp)
	t.check(is_equal_approx(_hp(s),hp-5.0),"AD-200 electrified water damages on the interval tick")
	var after := _hp(s)
	for i in 5:
		s.step()
	t.check(_hp(s) == after,"AD-200 no shock damage between intervals")
	var dry := _shock_session(Vector2(300,300))
	dry[0].water.electrify_all(1000)
	var dry_hp := _hp(dry[0])
	for i in 25:
		dry[0].step()
	t.check(_hp(dry[0]) == dry_hp,"AD-200 standing outside water takes no shock")
	var dash := _shock_session(Vector2(16,16))
	dash[0].water.electrify_all(1000)
	dash[0].player.invulnerable_left = 1000
	var dash_hp := _hp(dash[0])
	for i in 25:
		dash[0].step()
	t.check(_hp(dash[0]) == dash_hp,"AD-200 a dashing player takes no shock")
	var cold := _shock_session(Vector2(16,16))
	cold[0].water.electrify_all(1000)
	cold[0].water.freeze_circle(Vector2(16,16),20,1000)
	var cold_hp := _hp(cold[0])
	for i in 25:
		cold[0].step()
	t.check(_hp(cold[0]) == cold_hp,"AD-200 freezing a cell removes its shock")
	var clear := _shock_session(Vector2(16,16))
	clear[0].water.electrify_all(1000)
	clear[0].clear_water_shock()
	t.check(clear[0].water_shock.is_empty() and clear[0].water.state_view().is_empty(),"AD-200 clear_water_shock empties the shock and the states")
	var plain := _fresh(_cfg([_patterns(["fan"])],{"recovery_ticks":4000}),Vector2(1000,700),Vector2(16,16))
	plain[0].set_water(POOL)
	var twin := _fresh(_cfg([_patterns(["fan"])],{"recovery_ticks":4000}),Vector2(1000,700),Vector2(16,16))
	twin[0].set_water(POOL)
	twin[0].water_shock = {}
	for i in 60:
		plain[0].step()
		twin[0].step()
	t.check(_hp(plain[0]) == _hp(twin[0]) and plain[0].water.state_view().is_empty(),"AD-200 water without states behaves exactly as before")

# --- storm crystal: float path ---

const LANE := [[200,800],[600,800],[1100,800]]

func _float_spec(prefer: String, points: Array = LANE) -> Dictionary:
	return {"mode":"float_path","speed":150,"waypoints":points,"prefer":prefer}

## A boss placed at `at`, stepped `count` times by the float_path movement alone; returns the visited positions and waypoint indices.
func _float(spec: Dictionary, at: Vector2, count: int, water: Array = []) -> Dictionary:
	var pair := _fresh(_cfg([_patterns(["fan"])]),at,PLAYER)
	if not water.is_empty():
		pair[0].set_water(water)
	var out := {"positions":[],"waypoints":[]}
	for i in count:
		Movement.continuous_step(pair[1],pair[0],spec)
		out["positions"].append(pair[1].target.position)
		out["waypoints"].append(pair[1]._waypoint)
	return out

func _float_path(t) -> void:
	var run := _float(_float_spec("away"),Vector2(200,800),700)
	var positions: Array = run["positions"]
	var moving := true
	for i in range(1,positions.size()):
		moving = moving and positions[i] != positions[i-1]
	t.check(moving,"AD-200 float_path moves on every tick (it never stops at a waypoint)")
	var visited: Array = []
	for index in run["waypoints"]:
		if visited.is_empty() or visited[-1] != index:
			visited.append(index)
	t.check(positions.has(Vector2(600,800)) and positions.has(Vector2(1100,800)),"AD-200 float_path reaches each waypoint exactly")
	t.check(positions.all(func(p): return is_equal_approx(p.y,800.0)),"AD-200 float_path stays on the lane between waypoints")
	t.equal(visited.slice(0,4),[1,2,1,2],"AD-200 float_path walks adjacent waypoints (away from the player), starting by leaving the nearest one")
	var nearest := _float(_float_spec("away"),Vector2(1000,790),1)
	t.equal(nearest["waypoints"][0],2,"AD-200 the first waypoint is the nearest one")
	var away := _float(_float_spec("away"),Vector2(600,800),30)
	var toward := _float(_float_spec("toward"),Vector2(600,800),30)
	t.check(away["waypoints"][0] == 2 and away["positions"][-1].x > 600.0,"AD-200 prefer away heads for the waypoint farther from the player")
	t.check(toward["waypoints"][0] == 0 and toward["positions"][-1].x < 600.0,"AD-200 prefer toward flips it to the nearer waypoint")
	var tied := _fresh(_cfg([_patterns(["fan"])]),Vector2(600,800),Vector2(600,300))
	Movement.continuous_step(tied[1],tied[0],_float_spec("away",[[300,800],[600,800],[900,800]]))
	t.equal(tied[1]._waypoint,0,"AD-200 equal distances pick the lower index (no RNG)")
	var deep := _float(_float_spec("away",[[200,800],[600,800]]),Vector2(200,800),120,[{"kind":"deep","rect":[330,760,120,80]}])
	t.check(deep["positions"].any(func(p): return p.x > 470.0),"AD-200 float_path crosses deep water that blocks normal movers")
	var wall := _float(_float_spec("away",[[200,450],[1100,450]]),Vector2(200,450),900)
	var max_x := 0.0
	for p in wall["positions"]:
		max_x = maxf(max_x,p.x)
	t.check(max_x > 800.0 and max_x <= 860.0,"AD-200 float_path stops only at a wall (reached x=%.1f, wall edge 860)" % max_x)
	var late: Array = wall["positions"].slice(-300)
	t.check(late.any(func(p): return p.x < 700.0) and late.any(func(p): return p.x > 800.0),"AD-200 float_path turns around after a wall instead of freezing")

# --- storm crystal: beam sweep ---

func _crystal_cfg(extra: Dictionary = {}, phases: Array = []) -> Dictionary:
	var first := {"threshold":1.0,"windup_ticks":40,"patterns":["beam_sweep"]}
	var cfg := {"kind":"test_crystal","hp":450,"radius":30,"recovery_ticks":4000,"min_telegraph_ticks":36,"shot_speed":300,"shot_spread":0,
		"shot_damage":10,"radial_shots":4,"radial_damage":6,"telegraph_radius":150,"anchors":ANCHORS,
		"beam_sweep":{"windup_ticks":45,"sweep_degrees":90,"deg_per_tick":3,"length":500,"width":40,"damage":8,"hit_interval_ticks":20},
		"electrify":{"duration_ticks":120,"damage":5,"interval_ticks":10},"water_freeze":{"radius":40,"ice_ticks":600},
		"small_crystals":{"kind":"storm_crystal","offsets":[[80,0],[-80,0]],"cap":2,"hp":20,"radius":16},
		"phases":phases if not phases.is_empty() else [first]}
	return cfg.merged(extra,true)

const BEAM_BOSS := Vector2(300,450)
const BEAM_PLAYER := Vector2(500,450)

func _beam_session(extra: Dictionary = {}, phases: Array = [], player_at: Vector2 = BEAM_PLAYER) -> Array:
	return _fresh(_crystal_cfg(extra,phases),BEAM_BOSS,player_at)

func _beams(s) -> Array:
	return s.hazards.filter(func(h): return h["kind"] == "boss_beam")

func _beam_telegraph(t) -> void:
	for case in [[1.0,45],[2.0,90],[0.5,36]]:
		var scale: float = case[0]
		Difficulty.set_override({"telegraph_length":scale})
		var pair := _beam_session()
		_step_until(pair[0],10,func(): return pair[1].state == "windup")
		var telegraph := int(pair[1].intent.snapshot()["telegraph_ticks"])
		var warning: Array = _beams(pair[0])
		var ticks := 0
		while pair[1].state == "windup" and ticks < 200:
			pair[0].step()
			ticks += 1
		Difficulty.clear_override()
		t.check(telegraph == case[1] and ticks == case[1] and pair[1].state == "casting","AD-200 the beam telegraph is exactly %d ticks at telegraph_length x%s (Warden-style scale and floor; got %d/%d)" % [case[1],scale,telegraph,ticks])
		t.check(warning.size() == 1 and warning[0]["telegraph"] == true and warning[0]["status"] == "" and warning[0]["radius"] == 500.0 and warning[0]["beam_width"] == 40.0 and warning[0]["position"] == BEAM_BOSS,"AD-200 the beam warning hazard is published during the windup")
		t.equal(pair[1].intent.snapshot()["telegraph_shape"],"none","AD-200 the beam windup draws no shape (the hazard is the telegraph)")

func _beam_sweep(t) -> void:
	var pair := _beam_session()
	var s = pair[0]
	var boss = pair[1]
	_step_until(s,10,func(): return boss.state == "windup")
	var start: float = _beams(s)[0]["beam_angle"]
	t.check(is_equal_approx(start,-PI*0.25),"AD-200 the beam starts half a sweep before the locked player angle (%.3f)" % start)
	_step_until(s,100,func(): return boss.state == "casting")
	s.step()
	var first: Dictionary = _beams(s)[0]
	t.check(first["telegraph"] == false and is_equal_approx(first["beam_angle"],start+deg_to_rad(3.0)),"AD-200 the first casting tick rotates the beam and drops the telegraph flag")
	var last_angle := 0.0
	var ticks := 1
	while boss.state == "casting" and ticks < 200:
		last_angle = float(boss._beam.get("angle",last_angle))
		s.step()
		ticks += 1
	t.check(absf(rad_to_deg(last_angle-start)-90.0) < 3.01 and ticks == 30,"AD-200 the beam sweeps the configured 90 degrees in 30 ticks (got %d ticks, %.1f deg)" % [ticks,rad_to_deg(last_angle-start)])
	t.check(_beams(s).is_empty() and boss._beam.is_empty() and boss.state == "recover","AD-200 the beam hazard is removed and the boss recovers when the sweep ends")
	var second := _beam_session()
	_step_until(second[0],10,func(): return second[1].state == "windup")
	var again := float(_beams(second[0])[0]["beam_angle"])
	_step_until(second[0],100,func(): return second[1].state == "recover")
	second[1]._start_windup(second[0])
	var flipped := float(_beams(second[0])[0]["beam_angle"])
	t.check(again < 0.0 and flipped > 0.0,"AD-200 the sweep direction alternates each cast (%.2f then %.2f)" % [again,flipped])
	var floating := _beam_session({},[{"threshold":1.0,"windup_ticks":40,"patterns":["beam_sweep"],"movement":_float_spec("away",[[300,450],[300,800]])}])
	_step_until(floating[0],100,func(): return floating[1].state == "casting")
	var before: Vector2 = floating[1].target.position
	for i in 10:
		floating[0].step()
	t.check(floating[1].target.position != before and _beams(floating[0])[0]["position"] == floating[1].target.position,"AD-200 the crystal keeps floating while it casts and the beam follows it")

func _hit_ticks(s) -> Array:
	return s.damage_events.map(func(e): return int(e["tick"]))

func _run_cast(s, boss) -> void:
	_step_until(s,10,func(): return boss.state == "windup")
	_step_until(s,300,func(): return boss.state == "casting")
	_step_until(s,400,func(): return boss.state != "casting")

func _beam_hits(t) -> void:
	var slow := {"beam_sweep":{"windup_ticks":45,"sweep_degrees":60,"deg_per_tick":0.5,"length":500,"width":40,"damage":8,"hit_interval_ticks":20}}
	var pair := _beam_session(slow)
	var start_hp := _hp(pair[0])
	_run_cast(pair[0],pair[1])
	var ticks := _hit_ticks(pair[0])
	var gaps: Array = []
	for i in range(1,ticks.size()):
		gaps.append(ticks[i]-ticks[i-1])
	t.check(ticks.size() >= 2 and gaps.all(func(g): return g == 20),"AD-200 a player standing on the beam is hit once per hit_interval_ticks (gaps %s)" % str(gaps))
	t.check(is_equal_approx(start_hp-_hp(pair[0]),8.0*ticks.size()),"AD-200 every beam hit deals the configured damage (%.1f lost for %d hits)" % [start_hp-_hp(pair[0]),ticks.size()])
	var quick := _beam_session()
	_run_cast(quick[0],quick[1])
	t.equal(_hit_ticks(quick[0]).size(),1,"AD-200 a fast sweep passes a player once and hits once")
	var dash := _beam_session(slow)
	dash[0].player.invulnerable_left = 1000
	var dash_hp := _hp(dash[0])
	_run_cast(dash[0],dash[1])
	t.check(_hp(dash[0]) == dash_hp,"AD-200 a dashing player takes no beam damage")
	var shadow := _beam_session(slow)
	shadow[0].world.walls.append(Rect2(380,420,30,60))
	var shadow_hp := _hp(shadow[0])
	_run_cast(shadow[0],shadow[1])
	t.check(_hp(shadow[0]) == shadow_hp,"AD-200 a wall between the crystal and the player shadows the beam")
	var off := _beam_session(slow)
	var off_hp := _hp(off[0])
	_step_until(off[0],10,func(): return off[1].state == "windup")
	off[0].sim.actor.position = Vector2(100,450)
	_run_cast(off[0],off[1])
	t.check(_hp(off[0]) == off_hp,"AD-200 a player outside the sweep is never hit")

func _beam_speed_and_cancel(t) -> void:
	for scale in [2.0,0.5]:
		var pair := _beam_session({},[{"threshold":1.0,"windup_ticks":40,"patterns":["beam_sweep"],"beam_speed_scale":scale}])
		_step_until(pair[0],10,func(): return pair[1].state == "windup")
		_step_until(pair[0],100,func(): return pair[1].state == "casting")
		var ticks := 0
		var present := true
		while pair[1].state == "casting" and ticks < 200:
			pair[0].step()
			ticks += 1
			present = present and (pair[1].state != "casting" or not _beams(pair[0]).is_empty())
		t.check(ticks == roundi(30.0/scale) and present,"AD-200 beam_speed_scale x%s sweeps in %d ticks and the hazard lives the whole cast (got %d)" % [scale,roundi(30.0/scale),ticks])
	var roar := _crystal_cfg({},[{"threshold":1.0,"windup_ticks":40,"patterns":["beam_sweep"]},
		{"threshold":0.5,"windup_ticks":40,"patterns":["beam_sweep"],"transition":{"roar_ticks":20,"arena_change":{}}}])
	var pair := _fresh(roar,BEAM_BOSS,BEAM_PLAYER)
	_step_until(pair[0],10,func(): return pair[1].state == "windup")
	t.check(not _beams(pair[0]).is_empty(),"AD-200 setup: the beam warning exists before the roar")
	_threshold(pair[1])
	pair[0].step()
	t.check(pair[1].state == "roar" and _beams(pair[0]).is_empty() and pair[1]._beam.is_empty(),"AD-200 a roar during the windup cancels the beam hazard")
	var cast := _fresh(roar,BEAM_BOSS,BEAM_PLAYER)
	_step_until(cast[0],10,func(): return cast[1].state == "windup")
	_step_until(cast[0],100,func(): return cast[1].state == "casting")
	for i in 5:
		cast[0].step()
	t.check(not _beams(cast[0]).is_empty(),"AD-200 setup: the beam is live mid cast")
	_threshold(cast[1])
	cast[0].step()
	t.check(cast[1].state == "roar" and _beams(cast[0]).is_empty(),"AD-200 a roar during the sweep cancels the beam hazard")
	var dead := _beam_session()
	_step_until(dead[0],10,func(): return dead[1].state == "windup")
	_step_until(dead[0],100,func(): return dead[1].state == "casting")
	dead[1].target.health.current = 0.0
	dead[0].step()
	t.check(_beams(dead[0]).is_empty() and dead[1].state == "dead","AD-200 death cancels the beam hazard")

# --- storm crystal: electrify, Cold freeze, small crystals ---

func _electric_session(player_at: Vector2, water: Array = POOL) -> Array:
	var pair := _fresh(_crystal_cfg({},[{"threshold":1.0,"windup_ticks":40,"patterns":["electrify"]}]),Vector2(1000,700),player_at)
	if not water.is_empty():
		pair[0].set_water(water)
	return pair

func _warnings(s) -> Array:
	return s.hazards.filter(func(h): return h["kind"] == "boss_water_warning")

func _electrify(t) -> void:
	var pair := _electric_session(Vector2(16,16))
	var s = pair[0]
	var boss = pair[1]
	var hp := _hp(s)
	_step_until(s,10,func(): return boss.state == "windup")
	t.equal(_warnings(s).size(),POOL.size(),"AD-200 the electrify windup warns on every water rect")
	t.equal(boss.intent.snapshot()["telegraph_shape"],"none","AD-200 the electrify windup draws no shape")
	for i in 3:
		s.step()
	t.check(boss.state == "windup" and not s.water.is_electrified(Vector2(16,16)),"AD-200 nothing is electrified while the windup runs")
	_step_until(s,100,func(): return boss.state != "windup")
	t.check(_hp(s) == hp and s.water.is_electrified(Vector2(16,16)) and _warnings(s).is_empty(),"AD-200 the windup is harmless, then the water is electrified and the warnings are gone")
	t.check(not s.water_shock.is_empty() and int(s.water_shock["interval_ticks"]) == 10,"AD-200 firing sets session.water_shock")
	_step_until(s,12,func(): return _hp(s) < hp)
	t.check(_hp(s) < hp,"AD-200 an electrified water stander takes lightning damage")
	var dry := _electric_session(Vector2(300,300))
	var dry_hp := _hp(dry[0])
	_step_until(dry[0],100,func(): return dry[1].state == "recover")
	for i in 30:
		dry[0].step()
	t.check(_hp(dry[0]) == dry_hp and dry[0].water.is_electrified(Vector2(16,16)),"AD-200 standing outside the water is safe while the water is electrified")
	for i in 130:
		s.step()
	t.check(not s.water.is_electrified(Vector2(16,16)),"AD-200 the electrified water goes quiet after duration_ticks")
	var bare := _electric_session(Vector2(16,16),[])
	_step_until(bare[0],200,func(): return bare[1].state == "recover")
	t.check(bare[1].state == "recover" and bare[0].water == null and bare[0].water_shock.is_empty() and bare[0].hazards.is_empty(),"AD-200 electrify is a no-op without water")
	var ending := _electric_session(Vector2(300,300))
	_step_until(ending[0],100,func(): return ending[1].state == "recover")
	ending[1].target.health.current = 0.0
	ending[0].step()
	t.check(ending[0].water_shock.is_empty() and ending[0].water.state_view().is_empty(),"AD-200 the boss's death clears the shock and the water states")

func _cold_session(player_at: Vector2) -> Array:
	var pair := _fresh(_crystal_cfg({},[{"threshold":1.0,"windup_ticks":40,"patterns":["electrify"]}]),Vector2(1000,700),player_at)
	pair[0].set_water(POOL)
	return pair

func _shoot(s, essence: String, dir: Vector2, ticks: int) -> void:
	s.sim.loadout.allow_edit = true
	s.sim.equip(1,{"schema_version":1,"formula_id":"test.hit","display_name":"hit",
		"root":{"essence_id":essence,"manifestation_id":"form.projectile","modifier_ids":[],"params":{}}})
	s.sim.loadout.slots[1]["cooldown"] = 0
	s.sim.mana = 120.0
	s.sim.try_cast(1,s.sim.actor.position,dir)
	for i in ticks:
		s.step()

func _cold_freeze(t) -> void:
	for case in [["essence.cold",true],["essence.fire",false],["essence.water",false]]:
		var pair := _cold_session(Vector2(300,32))
		_shoot(pair[0],case[0],Vector2.LEFT,40)
		var frozen: bool = pair[0].water.is_frozen(Vector2(16,16)) or pair[0].water.is_frozen(Vector2(80,16))
		t.equal(frozen,case[1],"AD-200 a %s projectile %s water cells" % [case[0],"freezes" if case[1] else "does not freeze"])
	for case in [["essence.cold",true],["essence.fire",false]]:
		var burst := _cold_session(Vector2(300,300))
		burst[0].sim.visuals.append({"kind":"burst","position":Vector2(520,16),"radius":40.0,"essence":case[0],"until":burst[0].sim.clock.tick+5})
		burst[0].step()
		t.equal(burst[0].water.is_frozen(Vector2(520,16)),case[1],"AD-200 a %s burst %s water cells" % [case[0],"freezes" if case[1] else "does not freeze"])
	var beam := _cold_session(Vector2(300,300))
	beam[0].sim.visuals.append({"kind":"beam","from":Vector2(0,32),"to":Vector2(128,32),"essence":"essence.cold","until":beam[0].sim.clock.tick+5})
	beam[0].step()
	t.check(beam[0].water.is_frozen(Vector2(80,16)),"AD-200 a Cold beam freezes the water cells along it")
	var fresh := _cold_session(Vector2(16,16))
	fresh[0].sim.visuals.append({"kind":"burst","position":Vector2(16,16),"radius":40.0,"essence":"essence.cold","until":5})
	_step_until(fresh[0],10,func(): return fresh[0].water.is_frozen(Vector2(16,16)))
	for i in 600:
		fresh[0].step()
	t.check(not fresh[0].water.is_frozen(Vector2(16,16)) and fresh[0].water.in_water(Vector2(16,16)),"AD-200 ice melts after ice_ticks")
	var safe := _cold_session(Vector2(16,16))
	_step_until(safe[0],100,func(): return safe[1].state == "recover")
	var hp := _hp(safe[0])
	safe[0].sim.visuals.append({"kind":"burst","position":Vector2(16,16),"radius":40.0,"essence":"essence.cold","until":safe[0].sim.clock.tick+5})
	for i in 40:
		safe[0].step()
	t.check(_hp(safe[0]) == hp and safe[0].water.is_frozen(Vector2(16,16)),"AD-200 frozen cells are safe ground: the shock does not hurt there")
	var plain := _fresh(_cfg([_patterns(["fan"])]),Vector2(1000,700),Vector2(16,16))
	plain[0].set_water(POOL)
	plain[0].sim.visuals.append({"kind":"burst","position":Vector2(16,16),"radius":40.0,"essence":"essence.cold","until":9})
	plain[0].step()
	t.check(not plain[0].water.is_frozen(Vector2(16,16)),"AD-200 a boss without water_freeze never freezes water")

func _crystals(s, boss) -> Array:
	return s.enemies.filter(func(e): return e is Enemy and e.kind == "storm_crystal" and e.summoner_id == boss.target.id)

func _crystal_phases() -> Array:
	return [{"threshold":1.0,"windup_ticks":40,"patterns":["beam_sweep"]},
		{"threshold":0.5,"windup_ticks":40,"patterns":["beam_sweep"],"beam_speed_scale":1.5,"small_crystals":true,"transition":{"roar_ticks":20,"arena_change":{}}}]

func _small_crystals(t) -> void:
	var pair := _fresh(_crystal_cfg({},_crystal_phases()),Vector2(1000,700),PLAYER)
	var s = pair[0]
	var boss = pair[1]
	s.step()
	t.equal(_crystals(s,boss).size(),0,"AD-200 no small crystals before phase 2")
	_threshold(boss)
	s.step()
	var crystals := _crystals(s,boss)
	t.equal(crystals.size(),2,"AD-200 phase 2 spawns the 2 small crystals")
	var wanted := Difficulty.scale_f(20.0,"enemy_hp")
	t.check(crystals.all(func(c): return c.target.health.maximum == wanted and c.target.health.current == wanted and c.target.radius == 16.0),"AD-200 the spawn overrides set hp and radius")
	t.check(crystals.map(func(c): return c.target.position).has(Vector2(1080,700)) and crystals.map(func(c): return c.target.position).has(Vector2(920,700)),"AD-200 the crystals appear at the configured offsets")
	for i in 120:
		s.step()
	t.equal(_crystals(s,boss).size(),2,"AD-200 the small crystals spawn once")
	var force: float = crystals[0].target.receive_damage(10.0,"force",s.sim.actor.team,1.0)
	var plain: float = crystals[1].target.receive_damage(10.0,"neutral",s.sim.actor.team,1.0)
	t.check(is_equal_approx(force,15.0) and is_equal_approx(plain,10.0),"AD-200 small crystals take bonus Force (%.1f vs %.1f)" % [force,plain])
	var big: Object = s.spawn_enemy("storm_crystal",Vector2(1000,300))
	t.check(big.target.health.maximum != wanted,"AD-200 the override does not leak onto a normal storm crystal")
	boss.target.health.current = 0.0
	s.step()
	s.step()
	t.check(crystals.all(func(c): return not c.target.alive()),"AD-200 the small crystals die with the boss")
	var wall := _fresh(_crystal_cfg({"small_crystals":{"kind":"storm_crystal","offsets":[[100,0]],"cap":1,"hp":20,"radius":16}},_crystal_phases()),Vector2(500,300),PLAYER)
	s = wall[0]
	_threshold(wall[1])
	s.step()
	var fallback := _crystals(s,wall[1])
	t.check(fallback.size() == 1 and s.world.valid_position(fallback[0].target.position,16.0),"AD-200 an invalid offset falls back to an open point")
	var legacy := _fresh(_cfg([_patterns(["fan"])]),A,PLAYER)
	legacy[1].fire_summon(legacy[0],"storm_crystal",[[80,0]],1)
	t.check(not legacy[0].pending_spawns[0].has("overrides"),"AD-200 a summon without overrides is queued exactly as before")

func _crystal_validate(t) -> void:
	var good := _crystal_cfg({},_crystal_phases())
	t.equal(BossCombat.validate(good),[],"AD-200 a synthetic storm crystal config is valid")
	var cases := {"beam_sweep":["hit_interval_ticks","width","deg_per_tick"],"electrify":["interval_ticks","duration_ticks"],"water_freeze":["ice_ticks","radius"],"small_crystals":["hp","cap","radius"]}
	for block in cases:
		for key in cases[block]:
			var broken := good.duplicate(true)
			broken[block].erase(key)
			t.check(BossCombat.validate(broken).any(func(i): return i["code"] == "BOSS_ELITE_PARAM" and i["path"] == "%s.%s" % [block,key]),"AD-200 %s without %s is reported" % [block,key])
	var bad_kind := good.duplicate(true)
	bad_kind["small_crystals"]["offsets"] = [[1]]
	t.contains_issue(BossCombat.validate(bad_kind),"BOSS_ELITE_PARAM","AD-200 small_crystals offsets must be [x,y] pairs")
	var no_block := good.duplicate(true)
	no_block.erase("small_crystals")
	t.contains_issue(BossCombat.validate(no_block),"BOSS_ELITE_PARAM","AD-200 a small_crystals phase needs its block")
	var no_beam := good.duplicate(true)
	no_beam.erase("beam_sweep")
	t.contains_issue(BossCombat.validate(no_beam),"BOSS_ELITE_PARAM","AD-200 the beam_sweep pattern needs its block")
	var no_electric := _crystal_cfg({},[{"threshold":1.0,"windup_ticks":40,"patterns":["electrify"]}])
	no_electric.erase("electrify")
	t.contains_issue(BossCombat.validate(no_electric),"BOSS_ELITE_PARAM","AD-200 the electrify pattern needs its block")
	var bad_scale := _crystal_cfg({},[{"threshold":1.0,"windup_ticks":40,"patterns":["beam_sweep"],"beam_speed_scale":0}])
	t.contains_issue(BossCombat.validate(bad_scale),"BOSS_ELITE_PARAM","AD-200 beam_speed_scale must be > 0")
	for bad in [[],[[1]],[["a","b"]],"x"]:
		var moved := _crystal_cfg({},[{"threshold":1.0,"windup_ticks":40,"patterns":["fan"],"movement":{"mode":"float_path","speed":50,"waypoints":bad,"prefer":"away"}}])
		t.contains_issue(BossCombat.validate(moved),"BOSS_MOVE_PARAM","AD-200 float_path waypoints %s are rejected" % str(bad))
	var bad_prefer := _crystal_cfg({},[{"threshold":1.0,"windup_ticks":40,"patterns":["fan"],"movement":{"mode":"float_path","speed":50,"waypoints":LANE,"prefer":"up"}}])
	t.contains_issue(BossCombat.validate(bad_prefer),"BOSS_MOVE_PARAM","AD-200 float_path prefer must be away or toward")
	var missing := _crystal_cfg({},[{"threshold":1.0,"windup_ticks":40,"patterns":["fan"],"movement":{"mode":"float_path","waypoints":LANE}}])
	var paths: Array = BossCombat.validate(missing).map(func(i): return i["path"])
	t.check(paths.has("phases[0].movement.speed") and paths.has("phases[0].movement.prefer"),"AD-200 float_path without speed/prefer is reported: %s" % str(paths))
	var fine := _crystal_cfg({},[{"threshold":1.0,"windup_ticks":40,"patterns":["fan"],"movement":_float_spec("toward")}])
	t.equal(BossCombat.validate(fine),[],"AD-200 a float_path movement is valid")

func _crystal_rng(t) -> void:
	var pair := _fresh(_crystal_cfg({},_crystal_phases()),Vector2(1000,700),PLAYER)
	pair[0].set_water(POOL)
	var fresh = Session.new(1981,"empty",0)
	for i in 400:
		if i == 100:
			_threshold(pair[1])
		pair[0].step()
	t.equal(pair[1]._rng,null,"AD-200 the crystal kit never creates the boss RNG")
	t.equal(pair[0].sim.clock._rng.state,fresh.sim.clock._rng.state,"AD-200 the crystal kit leaves the shared sim RNG unchanged")
