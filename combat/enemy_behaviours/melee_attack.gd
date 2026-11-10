extends "res://combat/enemy_behaviours/behaviour.gd"
## Attack: telegraphed melee strike; hits if the player is within attack_range + player radius on release.
const ROLE := "attack"

func wants_attack(_enemy, _session, _ctx: Dictionary) -> bool:
	return true

var _direction := Vector2.ZERO
var _hit := false

func _lunges() -> bool:
	return float(params.get("lunge_distance",0.0)) > 0.0

func active_ticks(_enemy) -> int:
	return int(params.get("lunge_ticks",0)) if _lunges() else 0

func build_attack(enemy, ctx: Dictionary) -> Dictionary:
	var intent: Dictionary = standard_intent(enemy,ctx)
	if _lunges():
		intent["range"] = float(param(enemy,"attack_range"))+float(params["lunge_distance"])
	return intent

## Lunge: closes lunge_distance over lunge_ticks along the direction locked on the first active tick; one hit.
func active_tick(enemy, session, _ctx: Dictionary) -> void:
	var player = session.sim.actor
	if enemy.state_tick == 1:
		_direction = (player.position-enemy.target.position).normalized()
		_hit = false
	if _hit:
		return
	var step: Vector2 = _direction*float(params["lunge_distance"])/float(params["lunge_ticks"])
	enemy.target.position = enemy.step_body(session,enemy.target.position,step)
	if player.alive() and enemy.target.position.distance_to(player.position) <= float(param(enemy,"attack_range"))+player.radius:
		_hit = true
		session.damage_player(enemy.target.id,float(param(enemy,"damage")),str(params.get("channel","physical")))

func execute_attack(enemy, session) -> void:
	var player = session.sim.actor
	if enemy.target.position.distance_to(player.position) <= float(param(enemy,"attack_range"))+player.radius:
		session.damage_player(enemy.target.id,float(param(enemy,"damage")),str(params.get("channel","physical")))

static func validate(params: Dictionary) -> Array:
	return _validate_lunge(params)

static func _validate_lunge(params: Dictionary) -> Array:
	var issues := check("melee_attack",params,[],["attack_range","damage","lunge_distance","lunge_ticks"])
	if issues.is_empty() and float(params.get("lunge_distance",0.0)) > 0.0 and float(params.get("lunge_ticks",0)) < 1.0:
		issues.append("melee_attack: lunge_ticks must be >= 1 when lunge_distance > 0")
	return issues
