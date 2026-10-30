extends RefCounted
const Session = preload("res://combat/combat_session.gd")

func run(t) -> void:
	_dash_through_attack(t)
	_dash_into_wall(t)

func _dash_through_attack(t) -> void:
	var game = Session.new(701,"single",0)
	var source_id: int = game.enemies[0].target.id
	var max_hp: float = float(game.data["player"]["max_hp"])
	var response: Dictionary = game.issue({"move":Vector2.RIGHT,"aim":Vector2.RIGHT,"dash":true,"cast":-1})
	t.check(response["accepted"] or response["reason"] == "DASH_LOCKOUT","AD-013 dash command processed")
	t.equal(game.player.dashes,1,"AD-013 dash starts")
	t.check(game.player.invulnerable(),"AD-013 dash grants i-frames")
	var hit: Dictionary = game.damage_player(source_id,100,"physical")
	t.equal(hit["reason"],"INVULNERABLE","AD-013 dash-through-attack: hit during i-frames avoided")
	t.equal(game.sim.actor.health.current,max_hp,"AD-013 dash-through-attack: no HP lost")

func _dash_into_wall(t) -> void:
	var game = Session.new(701,"single",0)
	game.sim.actor.position = Vector2(540,250)
	game.issue({"move":Vector2.RIGHT,"aim":Vector2.RIGHT,"dash":true,"cast":-1})
	for i in 30:
		game.issue({"move":Vector2.RIGHT,"aim":Vector2.RIGHT,"dash":false,"cast":-1})
	t.check(game.sim.actor.position.x<565,"AD-013 dash into wall stops at wall")
	t.check(game.sim.actor.position.x>540.0,"AD-013 dash into wall still moved toward wall")
