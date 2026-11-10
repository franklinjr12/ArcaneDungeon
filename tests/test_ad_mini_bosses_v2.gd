extends RefCounted
## AD-200 step 1: elite mini-boss kit (blink move, homing skull, decoy). All settings are synthetic.
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
