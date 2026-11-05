extends "res://combat/enemy_behaviours/behaviour.gd"
## Attack: telegraphed melee strike; hits if the player is within attack_range + player radius on release.
const ROLE := "attack"

func wants_attack(_enemy, _session, _ctx: Dictionary) -> bool:
	return true

func build_attack(enemy, ctx: Dictionary) -> Dictionary:
	return standard_intent(enemy,ctx)

func execute_attack(enemy, session) -> void:
	var player = session.sim.actor
	if enemy.target.position.distance_to(player.position) <= float(param(enemy,"attack_range"))+player.radius:
		session.damage_player(enemy.target.id,float(param(enemy,"damage")),str(params.get("channel","physical")))

static func validate(params: Dictionary) -> Array:
	return check("melee_attack",params,[],["attack_range","damage"])
