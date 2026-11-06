extends "res://combat/enemy_behaviours/behaviour.gd"
## Attack: the Deep eel lunges out of the water along the direction locked at windup start. Only starts
## from inside water; the ripple telegraph is presentation-only. Charge parameters and intent come from
## charge.gd, but deep-water blockers do not stop the lunge (walls and arena bounds do).
## One contact hit per lunge. Uses EnemyCombat's "attack" state.
const ROLE := "attack"
const Charge = preload("res://combat/enemy_behaviours/charge.gd")
const Lurk = preload("res://combat/enemy_behaviours/water_lurk.gd")
var _charge
var _direction := Vector2.ZERO
var _hit := false

func _init(p: Dictionary = {}) -> void:
	super(p)
	_charge = Charge.new(p)

func wants_attack(enemy, session, _ctx: Dictionary) -> bool:
	return session.water != null and session.water.in_water(enemy.target.position)

func active_ticks(enemy) -> int:
	return _charge.active_ticks(enemy)

func build_attack(enemy, ctx: Dictionary) -> Dictionary:
	var intent: Dictionary = _charge.build_attack(enemy,ctx)
	_direction = intent["direction"]
	_hit = false
	intent["telegraph"] = "ripple"
	intent["submerged_origin"] = enemy.target.position
	return intent

func active_tick(enemy, session, _ctx: Dictionary) -> void:
	var step: Vector2 = _direction*float(param(enemy,"charge_speed"))/float(session.sim.clock.tick_rate)
	enemy.target.position = Lurk.step_free(session,enemy.target.position,step,enemy.target.radius)
	var player = session.sim.actor
	if _hit or not player.alive():
		return
	if enemy.target.position.distance_to(player.position) <= enemy.target.radius+player.radius+float(params.get("contact_padding",0.0)):
		_hit = true
		session.damage_player(enemy.target.id,float(param(enemy,"damage")),str(params.get("channel","physical")))

static func validate(params: Dictionary) -> Array:
	var issues := Charge.validate(params)
	if params.has("contact_padding") and typeof(params["contact_padding"]) in [TYPE_INT,TYPE_FLOAT] and float(params["contact_padding"]) < 0.0:
		issues.append("lunge: param 'contact_padding' must be >= 0")
	return issues
