extends RefCounted
## AD-199 step 1: Warden melee combo, spear line, Grave rise and pool range gates. All settings are synthetic.
const Session = preload("res://combat/combat_session.gd")
const Pool = preload("res://combat/boss_moves/boss_pattern_pool.gd")
const BossCombat = preload("res://combat/boss_combat.gd")
const Warden = preload("res://combat/boss_moves/warden_patterns.gd")
const Difficulty = preload("res://game/core/difficulty.gd")
const Art = preload("res://ui/pixel_art_renderer.gd")
const Flow = preload("res://world/run_flow.gd")
const Driver = preload("res://tests/m3_run_driver.gd")
const AT := Vector2(1030,450)
const COMBO := ["sweep_1","sweep_2","overhead_slam"]

func run(t) -> void:
	_combo_windups(t)
	_sweep_reach(t)
	_sweep_arc(t)
	_slam(t)
	_damage_scaling(t)
	_spear_line(t)
	_spear_line_cancel(t)
	_grave_rise(t)
	_thralls_die(t)
	_range_gates(t)
	_range_no_rng(t)
	_validate(t)
	_leap_stagger(t)
	_ring_hit(t)
	_ring_invulnerable(t)
	_ring_range_and_cover(t)
	_burst(t)
	_timed_summon(t)
	_aftermath_validate(t)
	_aftermath_trace(t)
	_pillars(t)
	_pillar_cover_and_break(t)
	_pillar_stun(t)
	_pillar_no_stun(t)
	_pillar_validate(t)
	_pillar_trace(t)
	_live_data(t)
	_live_room_fit(t)
	_live_leap_stagger(t)
	_live_movement_bench(t)

func _melee() -> Dictionary:
	return {"sweep_1":{"shape":"arc","windup_ticks":40,"reach":150,"arc_degrees":150,"damage":14},
		"sweep_2":{"shape":"arc","windup_ticks":32,"reach":150,"arc_degrees":150,"damage":14},
		"overhead_slam":{"shape":"slam","windup_ticks":48,"reach":150,"damage":24}}

func _spear() -> Dictionary:
	return {"windup_ticks":50,"count":3,"start":150,"spacing":150,"radius":40,"damage":12}

func _grave() -> Dictionary:
	return {"windup_ticks":50,"kind":"bone_thrall","offsets":[[90,0],[0,90]],"cap":3,"radius":80}

func _cfg(pool: Array, extra: Dictionary = {}) -> Dictionary:
	var cfg := {"kind":"test_warden","hp":1800,"radius":49,"recovery_ticks":10,"min_telegraph_ticks":30,"shot_speed":280,"shot_spread":0,
		"shot_damage":0,"radial_shots":4,"radial_damage":0,"fan_shots":3,"fan_arc_degrees":40,"telegraph_radius":190,"pulse_radius":150,"pulse_damage":0,
		"melee":_melee(),"spear_line":_spear(),"grave_rise":_grave(),
		"phases":[{"threshold":1.0,"windup_ticks":40,"pool":pool}]}
	return cfg.merged(extra,true)

func _fresh(cfg: Dictionary, player_offset: Vector2 = Vector2(-300,0)) -> Array:
	var s = Session.new(1981,"empty",0)
	s.defer_clear = true
	var boss = s.spawn_boss(cfg,AT)
	s.sim.actor.position = AT+player_offset
	return [s,boss]

func _hp(s) -> float:
	return s.sim.actor.health.current

## Advances until the boss is in the windup it just opened (state_tick 0).
func _open(s, boss) -> void:
	for i in 400:
		boss.advance(s)
		if boss.state == "windup" and boss.state_tick == 0:
			return

## Advances to the end of the open windup; returns the hp lost on the firing tick and the windup ticks spent.
func _resolve(s, boss) -> Dictionary:
	var before := _hp(s)
	var ticks := 0
	while boss.state == "windup" and ticks < 400:
		boss.advance(s)
		ticks += 1
	return {"lost":before-_hp(s),"ticks":ticks}

func _windups(cfg: Dictionary, attacks: int) -> Array:
	var pair := _fresh(cfg,Vector2(-500,0))
	var out: Array = []
	for i in attacks:
		_open(pair[0],pair[1])
		var snap: Dictionary = pair[1].intent.snapshot()
		out.append(int(snap["telegraph_ticks"]))
		_resolve(pair[0],pair[1])
	return out

func _combo_windups(t) -> void:
	var pool := [{"combo":COMBO,"gap_ticks":6}]
	t.equal(_windups(_cfg(pool),3),[40,32,48],"AD-199 the sweep combo windups are 40/32/48")
	var enraged := _cfg(pool,{"phases":[{"threshold":1.0,"windup_ticks":40,"windup_scale":0.85,"pool":pool}]})
	t.equal(_windups(enraged,3),[34,30,41],"AD-199 windup_scale 0.85 gives 34/30/41 with a 30-tick floor")
	var pair := _fresh(_cfg(pool),Vector2(-500,0))
	_open(pair[0],pair[1])
	var ticks := 0
	var start: Vector2 = pair[1].target.position
	while pair[1].state == "windup":
		pair[1].advance(pair[0])
		ticks += 1
	t.check(ticks == 40 and pair[1].target.position == start,"AD-199 the boss stands still for the whole windup")

## Hit test: windup starts aimed at the player east of the boss, then the player moves to `at` (relative to the boss) before the swing lands.
func _swing(attack: String, at: Vector2, invulnerable: int = 0) -> float:
	var pair := _fresh(_cfg([{"pattern":attack}]),Vector2(200,0))
	_open(pair[0],pair[1])
	pair[0].sim.actor.position = AT+at
	pair[0].player.invulnerable_left = invulnerable
	return float(_resolve(pair[0],pair[1])["lost"])

func _sweep_reach(t) -> void:
	var radius: float = Session.new(1981,"empty",0).sim.actor.radius
	var reach := 150.0+radius
	for attack in ["sweep_1","sweep_2"]:
		t.check(_swing(attack,Vector2(reach,0)) > 0.0,"AD-199 %s hits at reach + player radius" % attack)
		t.equal(_swing(attack,Vector2(reach+1.0,0)),0.0,"AD-199 %s misses beyond reach" % attack)

func _sweep_arc(t) -> void:
	var inside := Vector2(100,0).rotated(deg_to_rad(70))
	var outside := Vector2(100,0).rotated(deg_to_rad(80))
	t.check(_swing("sweep_1",inside) > 0.0,"AD-199 a sweep hits inside its 150 degree arc")
	t.equal(_swing("sweep_1",outside),0.0,"AD-199 a sweep misses outside its arc")
	t.equal(_swing("sweep_2",Vector2(-100,0)),0.0,"AD-199 a sweep misses a player behind the boss")

func _slam(t) -> void:
	t.check(_swing("overhead_slam",Vector2(-100,0)) > 0.0,"AD-199 the overhead slam is a circle that hits behind the boss too")
	t.equal(_swing("overhead_slam",Vector2(-100,0),30),0.0,"AD-199 dash i-frames absorb the overhead slam")
	t.equal(_swing("sweep_1",Vector2(100,0),30),0.0,"AD-199 dash i-frames absorb a sweep")
	var pair := _fresh(_cfg([{"pattern":"overhead_slam"}]),Vector2(100,0))
	_open(pair[0],pair[1])
	var snap: Dictionary = pair[1].intent.snapshot()
	t.check(snap["telegraph_shape"] == "slam" and snap["landing"] == AT and snap["range"] == 150.0,"AD-199 the slam telegraph is a circle on the boss")
	var pair2 := _fresh(_cfg([{"pattern":"sweep_1"}]),Vector2(100,0))
	_open(pair2[0],pair2[1])
	var arc: Dictionary = pair2[1].intent.snapshot()
	t.check(arc["telegraph_shape"] == "arc" and arc["arc_center"] == AT and arc["arc_radius"] == 150.0 and arc["arc_degrees"] == 150.0 \
		and arc["direction"] == Vector2.RIGHT,"AD-199 the sweep telegraph is an arc locked on the player")

func _damage_scaling(t) -> void:
	var boss = _fresh(_cfg([{"pattern":"sweep_1"}],{"elite_damage_multiplier":2.0}))[1]
	t.equal(boss.tuning["melee"]["overhead_slam"]["damage"],Difficulty.scale_f(48.0,"enemy_damage"),"AD-199 melee damage is scaled like other boss damage")
	t.equal(boss.tuning["spear_line"]["damage"],Difficulty.scale_f(24.0,"enemy_damage"),"AD-199 spear damage is scaled like other boss damage")

func _warnings(s) -> Array:
	return s.hazards.filter(func(h): return h["kind"] == "boss_warning")

func _spear_line(t) -> void:
	var cfg := _cfg([{"pattern":"spear_line"}])
	var pair := _fresh(cfg)
	var s = pair[0]
	var boss = pair[1]
	_open(s,boss)
	var snap: Dictionary = boss.intent.snapshot()
	t.equal(_warnings(s).size(),3,"AD-199 the spear line publishes 3 ground warnings")
	t.equal(_warnings(s).map(func(h): return h["position"]),[AT+Vector2(-150,0),AT+Vector2(-300,0),AT+Vector2(-450,0)],"AD-199 the warnings sit along the locked aim")
	t.check(snap["telegraph_shape"] == "none" and snap["range"] == 40.0 and snap["points"].size() == 3,"AD-199 the spear intent has no own telegraph shape")
	var hp := _hp(s)
	var ticks := 0
	var early := false
	while boss.state == "windup":
		boss.advance(s)
		ticks += 1
		early = early or (boss.state == "windup" and _hp(s) < hp)
	t.check(ticks == 50 and not early and hp-_hp(s) == 12.0,"AD-199 nothing hits before the spear windup ends, then one hit")
	t.check(_warnings(s).is_empty(),"AD-199 the warnings are gone once the spears land")
	var overlap := _cfg([{"pattern":"spear_line"}],{"spear_line":_spear().merged({"spacing":10,"start":290})})
	var tight := _fresh(overlap)
	_open(tight[0],tight[1])
	var lost: float = _resolve(tight[0],tight[1])["lost"]
	t.equal(lost,12.0,"AD-199 overlapping spears hit the player at most once")
	var edge := _fresh(_cfg([{"pattern":"spear_line"}],{"spear_line":_spear().merged({"start":400,"spacing":200})}),Vector2(300,0))
	_open(edge[0],edge[1])
	var bounds: Rect2 = edge[0].world.bounds
	t.check(_warnings(edge[0]).all(func(h): return bounds.grow(0.01).has_point(h["position"])),"AD-199 spear points are clamped into the arena")

func _two_phase(pool: Array) -> Dictionary:
	return _cfg(pool,{"phases":[{"threshold":1.0,"windup_ticks":40,"pool":pool},
		{"threshold":0.5,"windup_ticks":40,"transition":{"roar_ticks":30},"pool":pool}]})

func _spear_line_cancel(t) -> void:
	var pair := _fresh(_two_phase([{"pattern":"spear_line"}]))
	_open(pair[0],pair[1])
	t.equal(_warnings(pair[0]).size(),3,"AD-199 warnings are up before the roar")
	pair[1].target.health.current = pair[1].target.health.maximum*0.4
	pair[1].advance(pair[0])
	t.check(pair[1].state == "roar" and _warnings(pair[0]).is_empty(),"AD-199 a roar removes the spear warnings")
	var dead := _fresh(_cfg([{"pattern":"spear_line"}]))
	_open(dead[0],dead[1])
	dead[1].target.receive_damage(99999.0,"neutral",dead[0].sim.actor.team,1.0)
	dead[1].advance(dead[0])
	t.check(dead[1].state == "dead" and _warnings(dead[0]).is_empty(),"AD-199 boss death removes the spear warnings")

## Fires Grave rise `times` times, flushing queued spawns like the session does.
func _rise(cfg: Dictionary, times: int) -> Array:
	var pair := _fresh(cfg)
	for i in times:
		_open(pair[0],pair[1])
		if i == 0:
			var snap: Dictionary = pair[1].intent.snapshot()
			pair.append(snap)
		_resolve(pair[0],pair[1])
		pair[0]._flush_pending_spawns()
	return pair

func _grave_rise(t) -> void:
	var cfg := _cfg([{"pattern":"grave_rise"}])
	var one := _rise(cfg,1)
	t.equal(one[0].summons_owned_by(one[1].target.id),2,"AD-199 Grave rise raises 2 bone thralls")
	var snap: Dictionary = one[2]
	t.check(snap["telegraph_shape"] == "slam" and snap["landing"] == AT and snap["range"] == 80.0 and snap["telegraph_ticks"] == 50,"AD-199 Grave rise telegraphs a circle on the boss")
	t.check(one[0].enemies.filter(func(e): return e.get("summoner_id") == one[1].target.id).all(func(e): return e.kind == "bone_thrall"),"AD-199 the summons are bone thralls")
	var three := _rise(cfg,3)
	t.equal(three[0].summons_owned_by(three[1].target.id),3,"AD-199 Grave rise stops at the cap of 3 alive")
	var queued := _fresh(cfg)
	_open(queued[0],queued[1])
	queued[1].fire_summon(queued[0],"bone_thrall",[[90,0],[0,90],[0,-90]],3)
	queued[1].fire_summon(queued[0],"bone_thrall",[[-60,0]],3)
	t.equal(queued[0].summons_owned_by(queued[1].target.id),3,"AD-199 the cap counts queued summons")

func _thralls_die(t) -> void:
	var pair := _rise(_cfg([{"pattern":"grave_rise"}]),1)
	var s = pair[0]
	var boss = pair[1]
	boss.fire_summon(s,"bone_thrall",[[0,-90]],3)
	s._flush_pending_spawns()
	var thralls: Array = s.enemies.filter(func(e): return e.get("summoner_id") == boss.target.id)
	t.equal(thralls.size(),3,"AD-199 three thralls are alive before the boss dies")
	boss.target.receive_damage(99999.0,"neutral",s.sim.actor.team,1.0)
	boss.advance(s)
	t.check(thralls.all(func(e): return not e.target.alive()),"AD-199 the thralls die with the boss")
	t.check(s.pending_spawns.is_empty() and s.summons_owned_by(boss.target.id) == 0,"AD-199 queued thralls are dropped when the boss dies")

## Attack picked at every windup start while the player stands `distance` px from the boss.
func _picks(pool: Array, distance: float, count: int, seed: int = 1981) -> Array:
	var s = Session.new(seed,"empty",0)
	s.defer_clear = true
	var boss = s.spawn_boss(_cfg(pool),AT)
	s.sim.actor.position = AT+Vector2(-distance,0)
	var out: Array = []
	while out.size() < count:
		_open(s,boss)
		out.append(boss._windup_attack)
		_resolve(s,boss)
	return out

func _range_gates(t) -> void:
	var pool := [{"pattern":"radial","max_range":100},{"pattern":"fan","min_range":300},{"pattern":"targeted"}]
	t.check(_picks(pool,200,8).all(func(a): return a == "targeted"),"AD-199 at mid range only the unrestricted attack is picked")
	var close := _picks(pool,50,12)
	t.check(not close.has("fan") and close.has("radial"),"AD-199 min_range blocks a close pick and max_range allows it")
	var far := _picks(pool,400,12)
	t.check(not far.has("radial") and far.has("fan"),"AD-199 max_range blocks a far pick and min_range allows it")
	var edge := _picks([{"pattern":"radial","max_range":200},{"pattern":"fan"},{"pattern":"targeted"}],200,10)
	t.check(edge.has("radial"),"AD-199 the range gate is inclusive at the limit")

func _range_no_rng(t) -> void:
	var plain := [{"pattern":"radial","weight":2},{"pattern":"fan"},{"pattern":"targeted"}]
	var gated := [{"pattern":"radial","weight":2,"max_range":5000},{"pattern":"fan","min_range":0},{"pattern":"targeted"}]
	t.equal(_picks(gated,300,12),_picks(plain,300,12),"AD-199 unblocked range entries pick exactly like a legacy pool")
	var legacy = _fresh(_cfg(plain))[1]
	t.check(not Warden.handles(legacy.tuning,"radial") and Warden.handles(legacy.tuning,"sweep_2") and not Warden.handles({},"spear_line"),"AD-199 Warden.handles only claims configured attacks")
	var s = _fresh(_cfg([{"pattern":"radial"},{"pattern":"fan"},{"pattern":"targeted"}]))[0]
	var fresh = Session.new(1981,"empty",0)
	t.equal(s.sim.clock.next_id("probe_rng"),fresh.sim.clock.next_id("probe_rng"),"AD-199 a Warden boss does not touch the shared sim clock on spawn")
	var art := _fresh(_cfg([{"pattern":"spear_line"}]))
	_open(art[0],art[1])
	var fx: Array = Art.collect_fx(art[0],art[0].sim.clock.tick,{})
	t.check(fx.all(func(e): return e["event"] != "telegraph.dash_lane"),"AD-199 the spear windup draws no dash lane")

func _validate(t) -> void:
	var pool := [{"pattern":"radial"},{"pattern":"fan"},{"pattern":"targeted","min_range":10,"max_range":500.5}]
	t.equal(BossCombat.validate(_cfg(pool)),[],"AD-199 a complete Warden config is valid")
	var missing := _cfg(pool)
	missing["melee"]["sweep_1"].erase("reach")
	t.contains_issue(BossCombat.validate(missing),"BOSS_WARDEN_PARAM","AD-199 a melee entry without reach is invalid")
	var text := _cfg(pool)
	text["spear_line"]["count"] = "3"
	t.contains_issue(BossCombat.validate(text),"BOSS_WARDEN_PARAM","AD-199 a non-numeric spear key is invalid")
	var shape := _cfg(pool)
	shape["melee"]["sweep_2"]["shape"] = "cone"
	t.contains_issue(BossCombat.validate(shape),"BOSS_WARDEN_PARAM","AD-199 an unknown melee shape is invalid")
	var grave := _cfg(pool)
	grave["grave_rise"]["offsets"] = [[1,"x"]]
	t.contains_issue(BossCombat.validate(grave),"BOSS_WARDEN_PARAM","AD-199 grave_rise offsets must be [x,y] numbers")
	var no_cap := _cfg(pool)
	no_cap["grave_rise"].erase("cap")
	var issues := BossCombat.validate(no_cap)
	t.check(issues.any(func(i): return i["path"] == "grave_rise.cap"),"AD-199 the issue path names the missing key")
	var negative := _cfg([{"pattern":"radial","max_range":-1},{"pattern":"fan","min_range":"far"},{"pattern":"targeted"}])
	var range_issues := BossCombat.validate(negative).filter(func(i): return i["code"] == "BOSS_POOL_RANGE")
	t.equal(range_issues.map(func(i): return i["path"]),["phases[0].pool[0].max_range","phases[0].pool[1].min_range"],"AD-199 BOSS_POOL_RANGE flags negative and non-numeric ranges")
	t.equal(Pool.validate(_cfg(pool)),[],"AD-199 valid ranges raise no pool issue")


const SHOCK := {"speed":340,"width":36,"max_radius":420,"damage":14}
## Player offsets from the landing point (the empty arena has walls east of x=890, so these lines are clear).
const NEAR := Vector2(0,-200)
const FAR := Vector2(-500,0)

func _leap(extra: Dictionary = {}) -> Dictionary:
	var move := {"mode":"leap","telegraph_ticks":30,"flight_ticks":10,"radius":60,"damage":0,"shockwave":SHOCK.duplicate(),"burst_delay_ticks":18}
	var pool := [{"move":move.merged(extra,true),"big":true}]
	return _cfg(pool,{"stagger":{"ticks":90,"damage_taken_multiplier":1.5},"phases":[{"threshold":1.0,"windup_ticks":40,"pool":pool}]})

## Leap windup opens aimed at the player; the player then stands `offset` from the landing point. Returns [session, boss, landing].
func _landed(cfg: Dictionary, offset: Vector2) -> Array:
	var pair := _fresh(cfg)
	_open(pair[0],pair[1])
	var landing: Vector2 = pair[1].intent.snapshot()["landing"]
	pair[0].sim.actor.position = landing+offset
	for i in 100:
		pair[1].advance(pair[0])
		if pair[1].state == "stagger":
			break
	pair.append(landing)
	return pair

## First tick after landing at which a ring of `speed` px/s touches a player `distance` px away (mirrors the contact rule).
func _contact_tick(session, distance: float) -> int:
	var per_tick := float(SHOCK["speed"])/float(session.sim.clock.tick_rate)
	for age in range(1,200):
		if per_tick*age > float(SHOCK["max_radius"]):
			return -1
		if absf(distance-per_tick*age) <= float(SHOCK["width"])*0.5+session.sim.actor.radius:
			return age
	return -1

func _leap_stagger(t) -> void:
	var pair := _landed(_leap(),NEAR)
	var boss = pair[1]
	t.check(boss.state == "stagger" and boss.staggered and boss.target.damage_scale == 1.5,"AD-199 a leap with a shockwave still staggers the boss on landing")
	t.equal(boss.target.position,pair[2],"AD-199 the boss lands on the telegraphed point")
	t.equal(pair[0].hazards.filter(func(h): return h["kind"] == "boss_ring").size(),1,"AD-199 landing publishes one ring hazard")
	var plain := _landed(_leap().merged({"phases":[{"threshold":1.0,"windup_ticks":40,"pool":[{"move":{"mode":"leap","telegraph_ticks":30,"flight_ticks":10,"radius":60,"damage":0},"big":true}]}]},true),NEAR)
	t.check(plain[1]._aftermath.is_empty() and plain[0].hazards.filter(func(h): return h["kind"] == "boss_ring").is_empty(),"AD-199 a leap without shockwave starts no aftermath")

func _ring_hit(t) -> void:
	var pair := _landed(_leap(),NEAR)
	var s = pair[0]
	var expected := _contact_tick(s,NEAR.length())
	var hits: Array = []
	for age in range(1,81):
		var before := _hp(s)
		pair[1].advance(s)
		s._step_hazards()
		if _hp(s) < before:
			hits.append([age,before-_hp(s)])
	t.equal(hits,[[expected,Difficulty.scale_f(14.0,"enemy_damage")]],"AD-199 the ring hits a standing player once at the expected tick")
	t.check(expected > 0 and pair[1].state == "stagger" or pair[1].state == "windup","AD-199 the ring contact happens during the stagger window")
	t.check(pair[1]._aftermath.is_empty() and s.hazards.filter(func(h): return h["kind"] == "boss_ring").is_empty(),"AD-199 the ring and its hazard end at max radius")
	var scaled = _fresh(_leap().merged({"elite_damage_multiplier":2.0},true))[1]
	t.equal(scaled.tuning["phases"][0]["pool"][0]["move"]["shockwave"]["damage"],Difficulty.scale_f(28.0,"enemy_damage"),"AD-199 shockwave damage is scaled like move damage")

func _ring_invulnerable(t) -> void:
	var pair := _landed(_leap(),NEAR)
	var s = pair[0]
	var expected := _contact_tick(s,NEAR.length())
	s.player.invulnerable_left = 30
	var lost := 0.0
	for age in range(1,81):
		if age == expected+1:
			s.player.invulnerable_left = 0
		var before := _hp(s)
		pair[1].advance(s)
		lost += before-_hp(s)
	t.equal(lost,0.0,"AD-199 dash i-frames at contact absorb the ring and it does not hit afterwards")

func _ring_range_and_cover(t) -> void:
	var far := _landed(_leap(),FAR)
	var hp := _hp(far[0])
	for i in 100:
		far[1].advance(far[0])
	t.equal(_hp(far[0]),hp,"AD-199 a player beyond max radius is untouched")
	var cover := _landed(_leap(),NEAR)
	var s = cover[0]
	s.world.walls.append(Rect2(cover[2]+Vector2(-50,-100),Vector2(100,20)))
	var hp_cover := _hp(s)
	for i in 100:
		cover[1].advance(s)
	t.equal(_hp(s),hp_cover,"AD-199 a wall between the landing and the player blocks the ring")

func _burst(t) -> void:
	var pair := _landed(_leap(),FAR)
	var s = pair[0]
	var boss = pair[1]
	var shots: Array = []
	for age in range(1,40):
		var before: int = s.enemy_shots.size()
		boss.advance(s)
		if s.enemy_shots.size() != before:
			shots.append([age,s.enemy_shots.size()-before,boss.state])
	t.equal(shots,[[18,4,"stagger"]],"AD-199 the burst spawns radial_shots shots burst_delay_ticks after landing, during stagger")
	var headings: Array = s.enemy_shots.map(func(p): return p["direction"].snapped(Vector2(0.001,0.001)))
	t.equal(headings,[Vector2(1,0),Vector2(0,1),Vector2(-1,0),Vector2(0,-1)],"AD-199 the burst is a radial ring from the boss")
	var roar := _landed(_two_leap(),FAR)
	roar[1].target.health.current = roar[1].target.health.maximum*0.4
	var count := 0
	for i in 40:
		var before: int = roar[0].enemy_shots.size()
		roar[1].advance(roar[0])
		count += roar[0].enemy_shots.size()-before
	t.check(roar[1].state == "roar" or roar[1].phase == 2,"AD-199 the second phase roar starts during the aftermath")
	t.equal(count,4,"AD-199 a roar does not cancel the burst")

func _two_leap() -> Dictionary:
	var cfg := _leap()
	var pool: Array = cfg["phases"][0]["pool"]
	cfg["phases"] = [{"threshold":1.0,"windup_ticks":40,"pool":pool},{"threshold":0.5,"windup_ticks":40,"transition":{"roar_ticks":30},"pool":pool}]
	return cfg

func _summon_cfg(timed: Dictionary, second: bool = false) -> Dictionary:
	var pool := [{"pattern":"radial"},{"pattern":"fan"},{"pattern":"targeted"}]
	var phases := [{"threshold":1.0,"windup_ticks":40,"pool":pool}]
	if second:
		phases.append({"threshold":0.5,"windup_ticks":40,"transition":{"roar_ticks":30},"pool":pool,"timed_summon":timed})
	else:
		phases[0]["timed_summon"] = timed
	return _cfg(pool,{"phases":phases,"recovery_ticks":10})

func _timed_summon(t) -> void:
	var pair := _fresh(_summon_cfg({"first_ticks":20,"every_ticks":50}),Vector2(-500,0))
	var s = pair[0]
	var boss = pair[1]
	var owned := 0
	var fired: Array = []
	for n in range(1,300):
		boss.advance(s)
		var now: int = s.summons_owned_by(boss.target.id)
		if now != owned:
			fired.append([n,now])
			owned = now
	t.equal(fired,[[21,2],[71,3]],"AD-199 timed_summon fires at first_ticks and every_ticks later and respects the cap")
	var plain := _fresh(_summon_cfg({"first_ticks":20,"every_ticks":50}).merged({"phases":[{"threshold":1.0,"windup_ticks":40,"pool":[{"pattern":"radial"},{"pattern":"fan"},{"pattern":"targeted"}]}]},true),Vector2(-500,0))
	var with_timed := _fresh(_summon_cfg({"first_ticks":20,"every_ticks":50}),Vector2(-500,0))
	var picks_a: Array = []
	var picks_b: Array = []
	for n in 400:
		plain[1].advance(plain[0])
		with_timed[1].advance(with_timed[0])
		picks_a.append(plain[1]._windup_attack)
		picks_b.append(with_timed[1]._windup_attack)
	t.equal(picks_b,picks_a,"AD-199 timed_summon does not change the pattern picks")
	t.equal(with_timed[1].rng(with_timed[0]).state,plain[1].rng(plain[0]).state,"AD-199 timed_summon leaves the boss rng state unchanged")
	var late := _fresh(_summon_cfg({"first_ticks":0,"every_ticks":1000},true),Vector2(-500,0))
	var during_roar := 0
	var roar_seen := false
	late[1].target.health.current = late[1].target.health.maximum*0.4
	for n in 100:
		late[1].advance(late[0])
		if late[1].state == "roar":
			roar_seen = true
			during_roar += late[0].summons_owned_by(late[1].target.id)
	t.check(roar_seen and during_roar == 0 and late[0].summons_owned_by(late[1].target.id) == 2,"AD-199 the summon timer does not count during the roar and restarts with the phase")

## Validation wants 3 distinct patterns per pool; runtime tests keep the leap alone in the pool.
func _padded(cfg: Dictionary) -> Dictionary:
	cfg["phases"][0]["pool"] = cfg["phases"][0]["pool"]+[{"pattern":"radial"},{"pattern":"fan"},{"pattern":"targeted"}]
	return cfg

func _aftermath_validate(t) -> void:
	t.equal(BossCombat.validate(_padded(_leap())),[],"AD-199 a leap with shockwave and burst is valid")
	var no_speed := _padded(_leap())
	no_speed["phases"][0]["pool"][0]["move"]["shockwave"].erase("speed")
	var issues := BossCombat.validate(no_speed)
	t.check(issues.any(func(i): return i["code"] == "BOSS_WARDEN_PARAM" and i["path"].ends_with("shockwave.speed")),"AD-199 a shockwave without speed is invalid")
	var zero := _padded(_leap())
	zero["phases"][0]["pool"][0]["move"]["shockwave"]["width"] = 0
	t.contains_issue(BossCombat.validate(zero),"BOSS_WARDEN_PARAM","AD-199 a zero-width shockwave is invalid")
	t.contains_issue(BossCombat.validate(_padded(_leap({"burst_delay_ticks":0}))),"BOSS_WARDEN_PARAM","AD-199 burst_delay_ticks must be >= 1")
	var no_radial := _padded(_leap())
	no_radial.erase("radial_shots")
	t.contains_issue(BossCombat.validate(no_radial),"BOSS_WARDEN_PARAM","AD-199 the burst needs the radial settings")
	t.equal(BossCombat.validate(_summon_cfg({"first_ticks":0,"every_ticks":1200})),[],"AD-199 a valid timed_summon passes")
	t.contains_issue(BossCombat.validate(_summon_cfg({"first_ticks":0,"every_ticks":0})),"BOSS_WARDEN_PARAM","AD-199 timed_summon every_ticks must be >= 1")
	t.contains_issue(BossCombat.validate(_summon_cfg({"first_ticks":-1,"every_ticks":10})),"BOSS_WARDEN_PARAM","AD-199 timed_summon first_ticks must be >= 0")
	var no_grave := _summon_cfg({"first_ticks":0,"every_ticks":10})
	no_grave.erase("grave_rise")
	t.contains_issue(BossCombat.validate(no_grave),"BOSS_WARDEN_PARAM","AD-199 timed_summon needs a grave_rise block")

func _trace(seed: int) -> Array:
	var s = Session.new(seed,"empty",0)
	s.defer_clear = true
	var boss = s.spawn_boss(_leap(),AT)
	s.sim.actor.position = AT+Vector2(-300,0)
	var out: Array = []
	for i in 400:
		boss.advance(s)
		out.append([boss.state,boss.target.position,_hp(s),s.enemy_shots.size(),s.hazards.size()])
	return out

func _aftermath_trace(t) -> void:
	t.equal(_trace(1981),_trace(1981),"AD-199 identical seeds give an identical leap aftermath trace")

## Step 3: cracked boss pillars at the phase 2 roar, Force break, debris stun. The boss stands at AT, the player 300 px north (the room's own walls fill the west side); pillar_0 sits between them, 150 px from the boss.
const PILLARS := [[1030,300],[1250,150],[1030,780],[1250,750]]
const FORCE := "essence.force"

func _pillar_props(positions: Array = PILLARS) -> Array:
	var props: Array = []
	for index in positions.size():
		props.append({"id":"pillar_%d" % index,"kind":"boss_pillar","position":positions[index]})
	return props

func _pillar_cfg(props: Array = _pillar_props(), phase_two_pool: Array = [{"pattern":"sweep_1"}], extra: Dictionary = {}) -> Dictionary:
	var phase_one := [{"pattern":"sweep_1"}]
	var phases := [{"threshold":1.0,"windup_ticks":40,"pool":phase_one},
		{"threshold":0.5,"windup_ticks":40,"transition":{"roar_ticks":30,"arena_change":{"props":props}},"pool":phase_two_pool}]
	return _cfg(phase_one,{"phases":phases,"stagger":{"ticks":90,"damage_taken_multiplier":1.5},"pillar_debris":{"radius":190,"stun_ticks":120},
		"anchors":[[600,820],[1200,820]],"recovery_ticks":10}.merged(extra,true))

## Drops the boss under 50% hp and advances until the roar has just begun.
func _roared(cfg: Dictionary, player_offset: Vector2 = Vector2(0,-300)) -> Array:
	var pair := _fresh(cfg,player_offset)
	pair[1].target.health.current = pair[1].target.health.maximum*0.4
	for i in 10:
		pair[1].advance(pair[0])
		if pair[1].state == "roar":
			break
	return pair

## Advances through the roar until the boss is free again.
func _after_roar(pair: Array) -> void:
	for i in 60:
		pair[1].advance(pair[0])
		if pair[1].state != "roar":
			return

func _break(pair: Array, id: String, essence: String = FORCE) -> void:
	for prop in pair[0].env_props.props:
		if prop["id"] == id:
			pair[0].env_props._apply(prop,essence,pair[0].sim.clock.tick)

func _alive_pillars(s) -> int:
	return s.env_props.props.filter(func(p): return p["state"] != "destroyed").size() if s.env_props != null else 0

func _pillars(t) -> void:
	var pair := _fresh(_pillar_cfg())
	var walls: int = pair[0].world.walls.size()
	for i in 20:
		pair[1].advance(pair[0])
	t.check(pair[0].env_props == null and pair[0].world.walls.size() == walls,"AD-199 no pillars exist before the phase 2 roar")
	var s: Array = _roared(_pillar_cfg())
	t.equal(s[1].state,"roar","AD-199 the phase 2 transition starts the roar")
	t.equal(s[0].env_props.props.size(),4,"AD-199 the roar installs the 4 pillars")
	t.equal(s[0].world.walls.size(),walls+4,"AD-199 each pillar adds a wall")
	t.check(s[0].env_props.props.all(func(p): return p["kind"] == "boss_pillar" and (p["rect"] as Rect2).size == Vector2(64,64)),"AD-199 pillars are 64x64 boss_pillar props")
	var on_player := _roared(_pillar_cfg(_pillar_props([[1030,150]])))
	var player = on_player[0].sim.actor
	t.check(on_player[0].world.valid_position(player.position,player.radius) and player.position != Vector2(1030,150),"AD-199 a pillar placed on the player displaces the player to a valid position")
	var on_boss := _roared(_pillar_cfg(_pillar_props([[1030,450]])))
	t.check(on_boss[0].world.valid_position(on_boss[1].target.position,on_boss[1].target.radius) and on_boss[1].target.position != AT,"AD-199 a pillar placed on the boss displaces the boss to a valid position")

func _pillar_cover_and_break(t) -> void:
	var bare := _fresh(_pillar_cfg(),Vector2(0,-300))
	bare[0].spawn_enemy_projectile(bare[1].target.id,AT,Vector2.UP,10.0,400.0)
	var hp := _hp(bare[0])
	for i in 80:
		bare[0].advance_enemy_projectiles()
	t.check(_hp(bare[0]) < hp,"AD-199 control: a hostile shot reaches the player without cover")
	var pair := _roared(_pillar_cfg())
	var s = pair[0]
	hp = _hp(s)
	s.spawn_enemy_projectile(pair[1].target.id,AT,Vector2.UP,10.0,400.0)
	for i in 80:
		s.advance_enemy_projectiles()
	t.check(_hp(s) == hp and s.enemy_shots.is_empty(),"AD-199 a hostile shot stops at a pillar")
	var walls: int = s.world.walls.size()
	_break(pair,"pillar_0","essence.fire")
	t.check(_alive_pillars(s) == 4 and s.world.walls.size() == walls,"AD-199 a non-Force essence does not break a pillar")
	var rect: Rect2 = s.env_props.props[0]["rect"]
	_break(pair,"pillar_0")
	t.check(_alive_pillars(s) == 3 and s.world.walls.size() == walls-1 and not s.world.walls.has(rect),"AD-199 Force breaks a pillar and frees its wall")
	t.check(not s.sim.collision_walls.has(rect),"AD-199 a broken pillar no longer blocks spells")
	# A real Force projectile from the player at (1030,150) shoots south into the pillar at (1030,300).
	var shot := _roared(_pillar_cfg())
	var env = shot[0].env_props
	shot[0].sim.loadout.allow_edit = true
	shot[0].sim.equip(1,{"schema_version":1,"formula_id":"test.force","display_name":"force",
		"root":{"essence_id":FORCE,"manifestation_id":"form.projectile","modifier_ids":[],"params":{}}})
	shot[0].sim.loadout.slots[1]["cooldown"] = 0
	shot[0].sim.mana = 120.0
	shot[0].sim.try_cast(1,shot[0].sim.actor.position,Vector2.DOWN)
	for i in 60:
		env.pre_step(shot[0].sim)
		shot[0].sim.step()
	t.equal(env.props[0]["state"],"destroyed","AD-199 a Force projectile breaks a pillar")

func _pillar_stun(t) -> void:
	var pair := _roared(_pillar_cfg())
	_after_roar(pair)
	var boss = pair[1]
	for i in 100:
		boss.advance(pair[0])
		if boss.state == "windup":
			break
	t.check(boss.state == "windup" and boss.intent != null,"AD-199 setup: the boss is winding up a sweep")
	_break(pair,"pillar_0")
	boss.advance(pair[0])
	t.check(boss.state == "stagger" and boss.staggered and boss.intent == null and boss._windup_attack == "","AD-199 debris within radius stuns the boss and cancels the windup")
	t.equal(boss.target.damage_scale,1.5,"AD-199 the debris stun opens the damage window")
	var ticks := 0
	while boss.state == "stagger" and ticks < 300:
		boss.advance(pair[0])
		ticks += 1
	t.equal(ticks,120,"AD-199 the debris stun lasts exactly stun_ticks")
	t.check(not boss.staggered and boss.target.damage_scale == 1.0,"AD-199 the debris stun ends with the damage window")
	var again := _roared(_pillar_cfg())
	_after_roar(again)
	_break(again,"pillar_1")
	again[1].advance(again[0])
	t.check(not again[1].staggered,"AD-199 a pillar broken out of radius does not stun")
	var leap := _landed(_leap(),FAR)
	leap[1].tuning["pillar_debris"] = {"radius":190,"stun_ticks":120}
	for i in 10:
		leap[1].advance(leap[0])
	var mid_stagger: int = leap[1].state_tick
	leap[1].stun(leap[0],120)
	t.check(leap[1].state == "stagger" and leap[1].state_tick == 0 and mid_stagger > 0,"AD-199 a stun during a leap stagger restarts the window")

func _pillar_no_stun(t) -> void:
	var roar := _roared(_pillar_cfg())
	_break(roar,"pillar_0")
	roar[1].advance(roar[0])
	t.check(roar[1].state == "roar" and not roar[1].staggered,"AD-199 a pillar broken during the roar does not stun")
	var move := {"mode":"reposition","speed":100,"max_ticks":200}
	var moving := _roared(_pillar_cfg(_pillar_props(),[{"move":move}]))
	_after_roar(moving)
	for i in 20:
		moving[1].advance(moving[0])
		if moving[1].state == "moving":
			break
	t.equal(moving[1].state,"moving","AD-199 setup: the boss is repositioning")
	_break(moving,"pillar_0")
	moving[1].advance(moving[0])
	t.check(moving[1].state == "moving" and not moving[1].staggered,"AD-199 a pillar broken while the boss moves does not stun")
	for i in 5:
		moving[1].advance(moving[0])
	t.check(not moving[1].staggered,"AD-199 the ignored break does not stun later")

func _pillar_validate(t) -> void:
	var good := _padded(_pillar_cfg())
	good["phases"][1]["pool"] = good["phases"][1]["pool"]+[{"pattern":"radial"},{"pattern":"fan"},{"pattern":"targeted"}]
	t.equal(BossCombat.validate(good),[],"AD-199 a boss with pillars and debris settings is valid")
	var bad_kind := good.duplicate(true)
	bad_kind["phases"][1]["transition"]["arena_change"]["props"][0]["kind"] = "nonsense"
	var issues := BossCombat.validate(bad_kind)
	t.check(issues.any(func(i): return i["code"] == "BOSS_TRANSITION_PARAM" and i["path"].ends_with("arena_change.props")),"AD-199 an invalid pillar entry is a BOSS_TRANSITION_PARAM on arena_change.props")
	var bad_debris := good.duplicate(true)
	bad_debris["pillar_debris"].erase("stun_ticks")
	t.contains_issue(BossCombat.validate(bad_debris),"BOSS_WARDEN_PARAM","AD-199 pillar_debris needs stun_ticks")
	var zero := good.duplicate(true)
	zero["pillar_debris"]["radius"] = 0
	t.contains_issue(BossCombat.validate(zero),"BOSS_WARDEN_PARAM","AD-199 pillar_debris radius must be >= 1")

func _pillar_trace(t) -> void:
	var run := func(seed: int) -> Array:
		var s = Session.new(seed,"empty",0)
		s.defer_clear = true
		var boss = s.spawn_boss(_pillar_cfg(),AT)
		s.sim.actor.position = AT+Vector2(0,-300)
		boss.target.health.current = boss.target.health.maximum*0.4
		var out: Array = []
		for i in 300:
			boss.advance(s)
			if i == 120:
				for prop in s.env_props.props:
					if prop["id"] == "pillar_0":
						s.env_props._apply(prop,FORCE,s.sim.clock.tick)
			out.append([boss.state,boss.target.position,_hp(s),s.world.walls.size(),boss.target.damage_scale])
		return out
	t.equal(run.call(1981),run.call(1981),"AD-199 identical seeds give an identical pillar and stun trace")

## AD-199 step 4: live world/data/run_v2.json bosses.ruins_warden.
const LIVE_FILE := "res://world/data/run_v2.json"
const LIVE_BENCH_SEEDS := [1423,2718]
const LIVE_BENCH_BUILDS := [0,2]
const LIVE_BENCH_TICKS := 12000
const LIVE_STILL_LIMIT := 120

func _live_doc() -> Dictionary:
	return JSON.parse_string(FileAccess.get_file_as_string(LIVE_FILE))

func _live() -> Dictionary:
	return _live_doc()["bosses"]["ruins_warden"]

## Live data with one phase's pool replaced (and the timed summon removed) so a test can pick the move.
func _live_with_pool(phase_index: int, pool: Array) -> Dictionary:
	var cfg := _live()
	cfg["phases"][phase_index]["pool"] = pool
	cfg["phases"][phase_index].erase("timed_summon")
	return cfg

func _live_data(t) -> void:
	var cfg := _live()
	t.equal(BossCombat.validate(cfg),[],"AD-199 live ruins_warden validates")
	t.equal(int(cfg["hp"]),1800,"AD-199 live ruins_warden keeps 1800 hp")
	t.equal(cfg["phases"].map(func(p): return float(p["threshold"])),[1.0,0.6,0.25],"AD-199 live phase thresholds are 100/60/25 percent")
	var melee: Dictionary = cfg["melee"]
	t.equal(COMBO.map(func(k): return int(melee[k]["windup_ticks"])),[40,32,48],"AD-199 live melee windups are 40/32/48")
	t.check(COMBO.all(func(k): return int(melee[k]["reach"]) == 150),"AD-199 live melee reach is 150 px")
	var combo := [{"combo":COMBO,"gap_ticks":12}]
	var enraged := _live_with_pool(2,combo)
	var pair := _fresh(enraged,Vector2(-200,0))
	pair[1].target.health.current = pair[1].target.health.maximum*0.2
	var seen: Array = []
	for i in 600:
		pair[0].player.invulnerable_left = 10
		pair[1].advance(pair[0])
		if pair[1].state == "windup" and pair[1].state_tick == 0:
			seen.append(int(pair[1].intent.snapshot()["telegraph_ticks"]))
			if seen.size() == 3:
				break
	t.equal(seen,[34,30,41],"AD-199 live phase 3 combo windups are 34/30/41")
	t.equal(pair[1].phase,3,"AD-199 the live boss reaches phase 3 below 25 percent")
	var speeds: Array = cfg["phases"].map(func(p): return float(p["movement"]["speed"]))
	var walk := float(cfg["walk_speed"])
	t.equal(speeds,[walk,walk,walk*float(cfg["enrage_speed_multiplier"])],"AD-199 live walk speeds are walk_speed, walk_speed, walk_speed x enrage")
	t.equal(speeds[2],144.0,"AD-199 enraged walk speed is 144")
	t.equal(int(cfg["grave_rise"]["cap"]),3,"AD-199 live Grave rise cap is 3")
	t.equal(int(cfg["phases"][2]["timed_summon"]["every_ticks"]),1200,"AD-199 live phase 3 summons every 1200 ticks")
	var roar := _roared(_live(),Vector2(-300,0))
	t.equal(roar[0].env_props.props.size() if roar[0].env_props != null else 0,4,"AD-199 the live phase 2 roar creates 4 pillars")

func _live_room_fit(t) -> void:
	var cfg := _live()
	var flow = Flow.new(20261022,Flow.CONFIG_V2)
	var index := -1
	for i in flow.rooms.size():
		if str(flow.rooms[i]["id"]) == "ruins_boss":
			index = i
	t.check(index >= 0,"AD-199 the v2 run has a ruins_boss room")
	if index < 0:
		return
	flow.run.sequence_index = index
	t.check(bool(flow._enter_current()["ok"]),"AD-199 the ruins_boss room opens with the live Warden")
	var world = flow.session.world
	var radius := float(cfg["radius"])
	var anchors_fit: bool = cfg["anchors"].all(func(a): return world.valid_position(Vector2(float(a[0]),float(a[1])),radius))
	t.check(anchors_fit,"AD-199 every live Warden anchor fits the ruins_boss room")
	var pillars: Array = cfg["phases"][1]["transition"]["arena_change"]["props"]
	var half := 32.0+float(flow.session.sim.actor.radius)
	var points: Array = ["entrance","exit","reward"].map(func(k): return Vector2(float(flow.room.values[k][0]),float(flow.room.values[k][1])))
	var fits := true
	var clear := true
	for prop in pillars:
		var centre := Vector2(float(prop["position"][0]),float(prop["position"][1]))
		fits = fits and world.valid_position(centre+Vector2(32,32),0.0) and world.valid_position(centre-Vector2(32,32),0.0)
		for point in points:
			clear = clear and absf(point.x-centre.x) > half and absf(point.y-centre.y) > half
	t.check(fits,"AD-199 every live pillar fits the ruins_boss room")
	t.check(clear,"AD-199 live pillars do not cover the entrance, exit or reward")

func _live_leap_stagger(t) -> void:
	var leap: Dictionary = _live()["phases"][1]["pool"][0].duplicate(true)
	leap.erase("weight")
	var pair := _landed(_live_with_pool(0,[leap]),Vector2(0,-300))
	t.check(pair[1].state == "stagger" and pair[1].staggered,"AD-199 a live leap slam ends in stagger")
	t.equal(pair[1].target.damage_scale,1.5,"AD-199 the live stagger takes 1.5x damage")

class BenchHarness:
	var session
	var boss
	var state := "fighting"
	func step(command: Dictionary) -> void:
		session.issue(command)
		session.step()
		if session.state != "playing" or not boss.target.alive():
			state = "done"

## Longest run of ticks where the boss stood still while acquiring, recovering or moving (windup, stagger, roar and submerged reset it).
func _live_bench(run_seed: int, build: int) -> Dictionary:
	var doc := _live_doc()
	var s = Session.new(run_seed,"empty",build)
	s.defer_clear = true
	var boss = s.spawn_boss(doc["bosses"]["ruins_warden"],AT)
	var h := BenchHarness.new()
	h.session = s
	h.boss = boss
	var track := {"still":0,"max":0,"last":boss.target.position,"phases":[1],"dashes":0,"dash_left":0,"phase_tick":0}
	var next_hp := [0.59,0.24]
	var on_tick := func(_flow):
		var state: String = boss.state
		var position: Vector2 = boss.target.position
		if ["acquire","recover","moving"].has(state):
			track["still"] = int(track["still"])+1 if position == track["last"] else 0
			track["max"] = maxi(int(track["max"]),int(track["still"]))
		else:
			track["still"] = 0
		track["last"] = position
		if not (track["phases"] as Array).has(boss.phase):
			(track["phases"] as Array).append(boss.phase)
			track["phase_tick"] = 0
		track["phase_tick"] = int(track["phase_tick"])+1
		var dash_left: int = s.player.dash_left
		if dash_left > 0 and int(track["dash_left"]) == 0:
			track["dashes"] = int(track["dashes"])+1
		track["dash_left"] = dash_left
		# A bot that stalls in a phase is pushed to the next one so every phase is exercised.
		if boss.target.alive() and boss.phase <= next_hp.size() and int(track["phase_tick"]) > 1800:
			boss.target.health.current = minf(boss.target.health.current,boss.target.health.maximum*float(next_hp[boss.phase-1]))
	Driver.fight(h,LIVE_BENCH_TICKS,on_tick)
	return {"max_still":int(track["max"]),"phases":track["phases"],"dead":not boss.target.alive(),
		"seconds":float(s.sim.clock.tick)/60.0,"dashes":int(track["dashes"]),"player_alive":s.sim.actor.health.current > 0.0}

func _live_movement_bench(t) -> void:
	for run_seed in LIVE_BENCH_SEEDS:
		for build in LIVE_BENCH_BUILDS:
			var r := _live_bench(run_seed,build)
			var label := "seed %d build %d" % [run_seed,build]
			print("INFO WARDEN_BENCH %s fight_seconds=%.1f dash_uses=%d max_still_ticks=%d phases=%s dead=%s" % [label,r["seconds"],r["dashes"],r["max_still"],str(r["phases"]),str(r["dead"])])
			t.check(int(r["max_still"]) <= LIVE_STILL_LIMIT,"AD-199 the live Warden never stands still more than 2 s while acquiring, recovering or moving (%s, %d ticks)" % [label,r["max_still"]])
			if bool(r["dead"]):
				t.equal(r["phases"],[1,2,3],"AD-199 the live Warden fight visits all 3 phases (%s)" % label)
