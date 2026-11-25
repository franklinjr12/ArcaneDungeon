extends "res://combat/enemy_behaviours/behaviour.gd"
## Tick component (AD-238): lamprey_pair. Two lampreys share one tether (a shared `link` dictionary).
## Pairing (deterministic): when a lamprey is spawned, CombatSession calls link_on_spawn, which links it to the
## nearest already-spawned living lamprey that has no link yet (ties: lower target id). pair_id = the lower target id.
## While both are alive and the tether is intact, the tether runs eel A -> eel B; a player whose circle is within
## tether_half_width of that segment takes tether_damage at most once per hit_interval_ticks (one shared timer per
## pair, processed once per tick by whichever eel ticks first). If the eels drift farther than tether_max_length
## apart, each pulls itself half the excess toward the other.
## Cut rules (once, permanent, idempotent via link["cut"]):
## - One eel dies (on_death): the tether is gone and the survivor is stunned stun_ticks.
## - A player beam, or a projectile with mod.pierce, crosses the segment (CombatSession calls check_spell_cuts after
##   the player's spells advance): the tether is cut and BOTH eels are stunned stun_ticks (neither has died).
## - A plain (non-piercing) projectile never cuts it. Both eels dying on the same tick: the first death cuts and
##   tries to stun a dead partner (skipped); the second finds the tether already cut and does nothing.
## A cut tether stays listed in tether_view() with cut = true.
const ROLE := "tick"
const SCRIPT_PATH := "res://combat/enemy_behaviours/lamprey_pair.gd"

## Shared with the partner (same Dictionary object): {"a_id","b_id" (a = lower target id),"cut","hit_wait","last_tick"};
## empty until linked. Holds target ids, not EnemyCombat refs, so no reference cycle keeps the eels alive.
var link: Dictionary = {}

func tick(enemy, session, ctx: Dictionary) -> void:
	if link.is_empty() or bool(link["cut"]):
		return
	var pair := _pair(session,link)
	if pair.is_empty() or not (pair[0].target.alive() and pair[1].target.alive()):
		return
	var partner = pair[1] if enemy == pair[0] else pair[0]
	var gap: Vector2 = partner.target.position-enemy.target.position
	var excess: float = gap.length()-float(params["tether_max_length"])
	if excess > 0.0:
		enemy.target.position = enemy.step_body(session,enemy.target.position,gap.normalized()*excess*0.5)
	var now: int = session.sim.clock.tick
	if int(link["last_tick"]) == now:
		return
	link["last_tick"] = now
	link["hit_wait"] = maxi(0,int(link["hit_wait"])-1)
	var player = ctx["player"]
	if int(link["hit_wait"]) > 0 or not player.alive():
		return
	var closest: Vector2 = Geometry2D.get_closest_point_to_segment(player.position,pair[0].target.position,pair[1].target.position)
	if closest.distance_to(player.position) > float(params["tether_half_width"])+player.radius:
		return
	link["hit_wait"] = int(params["hit_interval_ticks"])
	session.damage_player(pair[0].target.id,float(params["tether_damage"]),str(params.get("channel","physical")))

func on_death(enemy, session) -> void:
	if link.is_empty() or bool(link["cut"]):
		return
	var pair := _pair(session,link)
	_cut(session,[] if pair.is_empty() else [pair[1] if enemy == pair[0] else pair[0]])

## Idempotent: callers check link["cut"] first; dead eels are never stunned.
func _cut(session, stunned: Array) -> void:
	link["cut"] = true
	for eel in stunned:
		if eel.target.alive():
			eel.stun(session,int(params["stun_ticks"]))

static func _component(enemy):
	if not ("behaviours" in enemy):
		return null
	for behaviour in enemy.behaviours:
		if behaviour.get_script().resource_path == SCRIPT_PATH:
			return behaviour
	return null

## [eel A, eel B] EnemyCombats of a link, or [] if either is gone from the session.
static func _pair(session, shared: Dictionary) -> Array:
	var a = null
	var b = null
	for enemy in session.enemies:
		if enemy.target.id == int(shared["a_id"]):
			a = enemy
		elif enemy.target.id == int(shared["b_id"]):
			b = enemy
	return [] if a == null or b == null else [a,b]

## Links a freshly spawned lamprey to the nearest unlinked living lamprey (ties: lower target id).
static func link_on_spawn(session, enemy) -> void:
	var own = _component(enemy)
	if own == null:
		return
	var best = null
	var best_distance := INF
	for other in session.enemies:
		var component = _component(other) if other != enemy else null
		if component == null or not component.link.is_empty() or not other.target.alive():
			continue
		var distance: float = enemy.target.position.distance_to(other.target.position)
		if best == null or distance < best_distance or (distance == best_distance and other.target.id < best.target.id):
			best = other
			best_distance = distance
	if best == null:
		return
	var shared := {"a_id":mini(best.target.id,enemy.target.id),"b_id":maxi(best.target.id,enemy.target.id),
		"cut":false,"hit_wait":0,"last_tick":-1}
	own.link = shared
	_component(best).link = shared

## Every distinct link resolved for this call as {"link","a","b"}, ordered by eel A's target id (session.enemies order
## is spawn order, so ascending ids).
static func links(session) -> Array:
	var found: Array = []
	for enemy in session.enemies:
		var component = _component(enemy)
		if component != null and not component.link.is_empty() and int(component.link["a_id"]) == enemy.target.id:
			var pair := _pair(session,component.link)
			if not pair.is_empty():
				found.append({"link":component.link,"a":pair[0],"b":pair[1]})
	found.sort_custom(func(x,y): return x["a"].target.id < y["a"].target.id)
	return found

## Player beams and piercing projectiles crossing an intact tether cut it and stun both eels.
## `previous` maps projectile effect id -> its position before this tick's spell step.
static func check_spell_cuts(session, previous: Dictionary) -> void:
	var intact: Array = links(session).filter(func(l): return not bool(l["link"]["cut"]) and l["a"].target.alive() and l["b"].target.alive())
	if intact.is_empty():
		return
	var actor = session.sim.actor
	var dt: float = 1.0/float(session.sim.clock.tick_rate)
	for entry in session.sim.active:
		var effect = entry["effect"]
		if not (entry["kind"] in ["beam","projectile"]) or effect.team != actor.team:
			continue
		var from: Vector2
		var to: Vector2
		var pad := 0.0
		if entry["kind"] == "beam":
			if effect.expired:
				continue
			from = actor.position
			to = effect.end_point
		elif effect.root.get("modifiers",[]).any(func(m): return str(m.get("id","")) == "mod.pierce"):
			to = effect.position
			from = previous.get(effect.id,to-effect.direction*effect.speed*dt)
			pad = effect.radius
		else:
			continue
		for resolved in intact:
			if bool(resolved["link"]["cut"]):
				continue
			var component = _component(resolved["a"])
			var points: PackedVector2Array = Geometry2D.get_closest_points_between_segments(from,to,resolved["a"].target.position,resolved["b"].target.position)
			if points[0].distance_to(points[1]) <= float(component.params["tether_half_width"])+pad:
				component._cut(session,[resolved["a"],resolved["b"]])

static func validate(params: Dictionary) -> Array:
	var keys := ["tether_damage","hit_interval_ticks","tether_half_width","tether_max_length","stun_ticks"]
	var issues := check("lamprey_pair",params,keys,keys)
	for key in keys:
		if typeof(params.get(key)) in [TYPE_INT,TYPE_FLOAT] and float(params[key]) <= 0.0:
			issues.append("lamprey_pair: param '%s' must be > 0" % key)
	for key in ["hit_interval_ticks","stun_ticks"]:
		if typeof(params.get(key)) == TYPE_FLOAT and not is_equal_approx(float(params[key]),roundf(float(params[key]))):
			issues.append("lamprey_pair: param '%s' must be an integer" % key)
	return issues
