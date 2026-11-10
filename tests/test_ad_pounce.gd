extends RefCounted
## AD-197: pounce behaviour (Ghoul stalker swipe, Riptide leaper slam): data, telegraph/recovery timing, locked commit, hit regions, dodge-through.
const Session = preload("res://combat/combat_session.gd")
const Art = preload("res://ui/pixel_art_renderer.gd")
const Registry = preload("res://combat/enemy_behaviours/registry.gd")

const KINDS := {"ghoul_stalker":{"offset":Vector2(100,0),"telegraph":50,"recovery":45,"damage":14.0},
	"riptide_leaper":{"offset":Vector2(200,0),"telegraph":55,"recovery":50,"damage":16.0}}

func run(t) -> void:
	_data(t)
	for kind in KINDS:
		_timing(t,kind)
		_one_hit(t,kind)
		_dodge_through(t,kind)
	_ghoul_locked(t)
	_ghoul_region(t)
	_leaper_locked(t)
	_leaper_region(t)
	_leaper_resumes(t)
	_telegraph_items(t)

func _spawn(kind: String, offset: Vector2) -> Array:
	var s = Session.new(136,"empty",0)
	return [s,s.spawn_enemy(kind,s.sim.actor.position+offset)]

func _pounce(enemy) -> Dictionary:
	for b in enemy.tuning["behaviours"]:
		if b["id"] == "pounce":
			return b
	return {}

func _tick_of(enemy, from: String, to: String) -> int:
	for tr in enemy.transitions:
		if tr["from"] == from and tr["to"] == to:
			return int(tr["tick"])
	return -1

## Steps until the enemy is in `state` with state_tick == ticks.
func _until(s, enemy, state: String, ticks: int, limit := 400) -> bool:
	for i in limit:
		if enemy.state == state and enemy.state_tick == ticks:
			return true
		s.step()
	return false

func _data(t) -> void:
	var s = Session.new(136,"empty",0)
	for kind in KINDS:
		t.check(s.data["enemies"].has(kind) and Registry.validate_enemy(s.data["enemies"][kind]).is_empty(),"AD-197 %s config validates" % kind)
	var g: Dictionary = s.data["enemies"]["ghoul_stalker"]
	var l: Dictionary = s.data["enemies"]["riptide_leaper"]
	var gp: Dictionary = g["behaviours"][1]
	var lp: Dictionary = l["behaviours"][1]
	t.check(g["hp"] == 70 and g["move_speed"] == 300 and g["telegraph_ticks"] == 50 and g["recovery_ticks"] == 45 and g["damage"] == 14,"AD-197 ghoul stalker spec values")
	t.check(l["hp"] == 80 and l["move_speed"] == 280 and l["telegraph_ticks"] == 55 and l["recovery_ticks"] == 50 and l["damage"] == 16 and lp["slam_radius"] == 70,"AD-197 riptide leaper spec values")
	t.equal(g["channel_resistances"],{"fire":-0.5},"AD-197 ghoul weak to Fire")
	t.equal(l["channel_resistances"],{"cold":-0.5},"AD-197 leaper weak to Cold")
	t.check(gp["swipe_radius"] == 30*2 and gp["swipe_arc_degrees"] == 120,"AD-197 ghoul swipe matches the art (60 radius, 120 degrees)")
	t.check(float(g["attack_range"]) == float(gp["swipe_radius"])+float(gp["lunge_distance"]),"AD-197 ghoul attack_range is swipe_radius + lunge_distance")
	t.check(lp["slam_radius"] == 35*2,"AD-197 leaper slam radius matches the art (70)")
	t.check(not Registry.validate_enemy({"behaviours":[{"id":"pounce","style":"hop"}]}).is_empty(),"AD-197 pounce rejects an unknown style")

func _timing(t, kind: String) -> void:
	var spec: Dictionary = KINDS[kind]
	var pair := _spawn(kind,spec["offset"])
	var s = pair[0]
	var e = pair[1]
	for i in 300:
		s.step()
		if e.state == "chase" and _tick_of(e,"recover","chase") >= 0:
			break
	var windup := _tick_of(e,"chase","windup")
	t.check(windup >= 0 and _tick_of(e,"windup","attack")-windup == spec["telegraph"],"AD-197 %s telegraph is %d ticks" % [kind,spec["telegraph"]])
	var attack_end := _tick_of(e,"attack","recover")
	t.check(attack_end >= 0 and _tick_of(e,"recover","chase")-attack_end == spec["recovery"],"AD-197 %s recovery window is %d ticks" % [kind,spec["recovery"]])
	var late := 0
	for ev in s.damage_events:
		if int(ev["tick"]) > attack_end:
			late += 1
	t.check(late == 0,"AD-197 %s deals no damage during recovery" % kind)

func _one_hit(t, kind: String) -> void:
	var pair := _spawn(kind,KINDS[kind]["offset"])
	var s = pair[0]
	var e = pair[1]
	for i in 300:
		s.step()
		if _tick_of(e,"recover","chase") >= 0:
			break
	t.check(s.damage_events.size() == 1 and is_equal_approx(float(s.damage_events[0]["amount"]),KINDS[kind]["damage"]),"AD-197 %s hits a stationary player once for %s (%d events)" % [kind,KINDS[kind]["damage"],s.damage_events.size()])

func _ghoul_locked(t) -> void:
	var pair := _spawn("ghoul_stalker",Vector2(100,0))
	var s = pair[0]
	var e = pair[1]
	t.check(_until(s,e,"windup",1),"AD-197 ghoul starts its windup")
	var start: Vector2 = e.target.position
	for i in 20:
		s.step()
	t.check(e.target.position.is_equal_approx(start),"AD-197 ghoul stands still during the windup")
	s.sim.actor.position = start+Vector2(-60,90)
	t.check(_until(s,e,"recover",0),"AD-197 ghoul reaches recovery")
	t.check(absf(e.target.position.y-start.y) < 0.01 and absf(e.target.position.x-(start.x-64.0)) < 0.01 and s.damage_events.is_empty(),"AD-197 ghoul lunge line is locked at windup start (%s)" % str(e.target.position))

func _last_tick_ghoul() -> Array:
	var pair := _spawn("ghoul_stalker",Vector2(100,0))
	var lunge := int(_pounce(pair[1])["lunge_ticks"])
	_until(pair[0],pair[1],"attack",lunge-1)
	return pair

## Places the player r from the end-of-lunge centre at `degrees` off the lunge direction (-x), then runs the final lunge tick.
func _swipe_hits(r: float, degrees: float) -> bool:
	var pair := _last_tick_ghoul()
	var s = pair[0]
	var e = pair[1]
	var direction := Vector2.LEFT
	var centre: Vector2 = e.target.position+direction*8.0
	s.sim.actor.position = centre+direction.rotated(deg_to_rad(degrees))*r
	s.step()
	return s.damage_events.size() == 1

func _ghoul_region(t) -> void:
	var reach := 60.0+float(Session.new(136,"empty",0).sim.actor.radius)
	t.check(_swipe_hits(reach,0.0),"AD-197 swipe hits at the arc radius (%s)" % reach)
	t.check(not _swipe_hits(reach+1.0,0.0),"AD-197 swipe misses just beyond the arc radius")
	for sign in [1.0,-1.0]:
		t.check(_swipe_hits(70.0,59.0*sign),"AD-197 swipe hits inside the 120 degree arc (%s)" % sign)
		t.check(not _swipe_hits(70.0,61.0*sign),"AD-197 swipe misses outside the 120 degree arc (%s)" % sign)

func _leaper_locked(t) -> void:
	var pair := _spawn("riptide_leaper",Vector2(200,0))
	var s = pair[0]
	var e = pair[1]
	var landing: Vector2 = s.sim.actor.position
	t.check(_until(s,e,"windup",1),"AD-197 leaper starts its windup")
	t.check(e.intent.snapshot().get("landing",Vector2.ZERO) == landing,"AD-197 leaper telegraphs the player's position")
	s.sim.actor.position = Vector2(185,120)
	t.check(_until(s,e,"recover",0),"AD-197 leaper reaches recovery")
	t.check(e.target.position.distance_to(landing) < 0.5 and s.damage_events.is_empty(),"AD-197 leaper lands on the locked point and misses a player who left (%s)" % str(e.target.position))

func _leaper_region(t) -> void:
	var radius := float(Session.new(136,"empty",0).sim.actor.radius)
	for extra in [0.0,1.0]:
		var pair := _spawn("riptide_leaper",Vector2(200,0))
		var s = pair[0]
		var e = pair[1]
		var landing: Vector2 = s.sim.actor.position
		_until(s,e,"attack",int(_pounce(e)["leap_ticks"])-1)
		s.sim.actor.position = landing+Vector2(0,70.0+radius+extra)
		s.step()
		t.check((s.damage_events.size() == 1) == (extra == 0.0),"AD-197 slam %s at radius 70 + player radius + %s" % ["hits" if extra == 0.0 else "misses",extra])

func _leaper_resumes(t) -> void:
	var pair := _spawn("riptide_leaper",Vector2(200,0))
	var s = pair[0]
	var e = pair[1]
	for i in 300:
		s.step()
		if _tick_of(e,"recover","chase") >= 0:
			break
	s.sim.actor.position = Vector2(700,450)
	var before: Vector2 = e.target.position
	for i in 5:
		s.step()
	t.check(e.state == "chase" and e.target.position.distance_to(before) > 20.0,"AD-197 leaper resumes chasing after recovery (%s)" % str(e.target.position.distance_to(before)))

func _dodge_through(t, kind: String) -> void:
	var pair := _spawn(kind,KINDS[kind]["offset"])
	var s = pair[0]
	var e = pair[1]
	var active := int(_pounce(e)["lunge_ticks" if kind == "ghoul_stalker" else "leap_ticks"])
	t.check(_until(s,e,"attack",active-4),"AD-197 %s reaches its last active ticks" % kind)
	s.player.process_command({"dash":true,"move":Vector2.RIGHT})
	for i in 10:
		if e.state == "recover":
			break
		s.step()
	t.check(e.state == "recover" and s.damage_events.is_empty() and s.player.perfect_dodges == 1,"AD-197 %s: dashing through the strike is a perfect dodge (%d events, %d dodges)" % [kind,s.damage_events.size(),s.player.perfect_dodges])

func _windup_items(kind: String, offset: Vector2) -> Array:
	var pair := _spawn(kind,offset)
	var s = pair[0]
	var e = pair[1]
	_until(s,e,"windup",1)
	return [s,e,Art.collect_fx(s,s.sim.clock.tick,{}).filter(func(i): return str(i["event"]).begins_with("telegraph."))]

## AD-197: ghoul wedge and leaper landing circle share the one danger tint and are drawn from the locked intent.
func _telegraph_items(t) -> void:
	var g := _windup_items("ghoul_stalker",Vector2(100,0))
	var gi: Array = g[2]
	var gs: Dictionary = _pounce(g[1])
	var origin: Vector2 = g[1].target.position
	t.check(gi.size() == 1 and gi[0]["event"] == "telegraph.arc","AD-197 ghoul windup yields one telegraph.arc item")
	if gi.size() == 1:
		t.check(gi[0]["at"].is_equal_approx(origin+Vector2.LEFT*float(gs["lunge_distance"])) or gi[0]["at"].is_equal_approx(origin+Vector2.RIGHT*float(gs["lunge_distance"])),"AD-197 ghoul arc is centred at the lunge end (%s)" % str(gi[0]["at"]))
		t.check(is_equal_approx(float(gi[0]["uniform"]),120.0) and is_equal_approx(float(gi[0]["arc_degrees"]),120.0),"AD-197 ghoul arc is 120 wide and 120 degrees")
	t.check(not Art.fx_fallbacks.has("telegraph.arc"),"AD-197 telegraph.arc is not an fx fallback")
	var l := _windup_items("riptide_leaper",Vector2(200,0))
	var li: Array = l[2]
	var landing: Vector2 = l[0].sim.actor.position
	t.check(li.size() == 1 and li[0]["event"] == "telegraph.circle" and li[0]["at"] == landing and is_equal_approx(float(li[0]["uniform"]),140.0),"AD-197 leaper windup yields a 140 circle on the player")
	l[0].sim.actor.position = landing+Vector2(0,90)
	var again: Array = Art.collect_fx(l[0],l[0].sim.clock.tick,{}).filter(func(i): return i["event"] == "telegraph.circle")
	t.check(again.size() == 1 and again[0]["at"] == landing,"AD-197 leaper circle stays on the locked point after the player moves")
	t.check(Art.telegraph_colors("telegraph.circle",0.5) == Art.telegraph_colors("telegraph.circle",0.5),"AD-197 both telegraphs use the telegraph.circle tint")
