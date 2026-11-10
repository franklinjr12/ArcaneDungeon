extends RefCounted
## AD-200: lightweight session.enemies entry for elite mini-boss helpers: `homing_skull` (slow, destroyable) and `decoy` (stands still, copies casts).
## AD-201: `book_page` flies like a skull and also dies at once when it is Burning.
## Both are ordinary sim targets (spells hit them), so the fields other code reads (target, kind, tuning, state, ...) mirror the enemy entries. No RNG.
const AttackIntent = preload("res://combat/attack_intent.gd")
const FLYERS := ["homing_skull","book_page"]
const BURNING := "burning"
var target
var kind := ""
var tuning: Dictionary
var state := "idle"
var state_tick := 0
var cycle := 0
var transitions: Array = []
var intent
var summoner_id := -1
var mode := ""
var heading := Vector2.RIGHT
var _spec: Dictionary
var _announced := false

## Target + entry for a queued spawn spec {minion, position, summoner_id, settings, heading}; null when the spot does not fit.
static func build(session, spec: Dictionary):
	var settings: Dictionary = spec["settings"]
	var at: Vector2 = spec["position"]
	if not session.world.valid_position(at,float(settings["radius"])):
		return null
	var minion_kind := str(spec["minion"])
	var body = session.sim.add_target(at,Vector2.ZERO,float(settings["hp"]))
	body.radius = float(settings["radius"])
	body.tags = ["enemy",minion_kind]
	var entry = new(body,minion_kind,settings)
	entry.summoner_id = int(spec["summoner_id"])
	entry.heading = spec.get("heading",Vector2.RIGHT)
	if FLYERS.has(minion_kind):
		entry.state = "fly"
	return entry

func _init(body, minion_kind: String, settings: Dictionary) -> void:
	target = body
	kind = minion_kind
	mode = minion_kind
	_spec = settings.duplicate(true)
	tuning = {"color":str(settings.get("color","#b8a3d9")),"telegraph_ticks":0,"attack_range":float(settings["radius"]),"display_name":minion_kind}

func _state(to: String, tick: int) -> void:
	if state == to:
		return
	transitions.append({"from":state,"to":to,"tick":tick,"enemy_id":target.id})
	state = to
	state_tick = 0

## Decoy: shows the same telegraph as the boss's windup (`fields` already moved to the decoy's position).
func show_windup(fields: Dictionary) -> void:
	intent = AttackIntent.new(fields)
	tuning["telegraph_ticks"] = int(fields["telegraph_ticks"])
	tuning["attack_range"] = float(fields["range"])
	state = "windup"
	state_tick = 0

func end_windup() -> void:
	if state == "windup":
		intent = null
		state = "idle"
		state_tick = 0

func kill(session) -> void:
	target.receive_damage(target.health.current+1.0,"neutral",session.sim.actor.team,1.0)

func advance(session) -> void:
	if not target.alive():
		_state("dead",session.sim.clock.tick)
		if not _announced:
			_announced = true
			session.on_enemy_death(self)
		return
	if session.state != "playing":
		return
	state_tick += 1
	if FLYERS.has(mode):
		_fly(session)
	elif state == "windup" and state_tick > int(tuning["telegraph_ticks"])+2:
		end_windup() # safety net: the boss normally closes the copy when it fires

func _fly(session) -> void:
	if kind == "book_page" and target.status.has(BURNING,session.sim.clock.tick):
		kill(session)
		return
	var player = session.sim.actor
	var offset: Vector2 = player.position-target.position
	if player.alive() and not offset.is_zero_approx():
		var turn := deg_to_rad(float(_spec["turn_deg_per_tick"]))
		heading = heading.rotated(clampf(heading.angle_to(offset),-turn,turn))
	var at: Vector2 = target.position+heading*float(_spec["speed"])/float(session.sim.clock.tick_rate)
	if _in_wall(session,at) or state_tick >= int(_spec["lifetime_ticks"]):
		kill(session)
		return
	target.position = at
	if player.alive() and at.distance_to(player.position) <= target.radius+player.radius:
		var result: Dictionary = session.damage_player(target.id,float(_spec["damage"]),"physical")
		if str(result.get("reason","")) != "INVULNERABLE":
			kill(session)

## Walls and the arena edge only: a skull floats over deep water.
func _in_wall(session, at: Vector2) -> bool:
	var radius := float(target.radius)
	var bounds: Rect2 = session.world.bounds
	if at.x < bounds.position.x+radius or at.y < bounds.position.y+radius or at.x > bounds.end.x-radius or at.y > bounds.end.y-radius:
		return true
	for wall in session.world.walls:
		var nearest := Vector2(clampf(at.x,wall.position.x,wall.end.x),clampf(at.y,wall.position.y,wall.end.y))
		if nearest.distance_squared_to(at) < radius*radius:
			return true
	return false
