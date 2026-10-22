extends RefCounted
## Deterministic non-cheating command policy for M2 repeatable baseline scenarios.
## It uses only issued player commands; no direct target damage, mana refill or godmode.
const Session = preload("res://combat/combat_session.gd")
const FIXED_SEED := 20261022

static func simulate(scenario: String, loadout: int, max_ticks: int = 2400) -> Dictionary:
	var game = Session.new(FIXED_SEED,scenario,loadout)
	var previous_reactions := 0
	var total_ms := 0.0
	for tick in max_ticks:
		if game.state != "playing":
			break
		var actor_pos: Vector2 = game.sim.actor.position
		var foe = _choose_target(game)
		if foe == null:
			break
		var difference: Vector2 = foe.target.position-actor_pos
		var dist: float = difference.length()
		var aim: Vector2 = difference.normalized()
		if aim.is_zero_approx():
			aim = Vector2.RIGHT
		var clear: bool = game.world.clear_sight(actor_pos,foe.target.position,8)
		var move := Vector2.ZERO
		if dist > 255.0 or not clear:
			move = game.world.navigate_direction(actor_pos,foe.target.position,game.sim.actor.radius)
		elif dist < 130.0:
			move = -aim
		elif dist < 255.0:
			move = aim.rotated(PI/2.0)*0.3
		var dodge := false
		for enemy in game.enemies:
			if enemy.state == "windup" and enemy.target.alive() and game.player.dodge_cooldown == 0:
				var eta: int = int(enemy.tuning["telegraph_ticks"])-enemy.state_tick
				if eta <= 7 and actor_pos.distance_to(enemy.target.position)<float(enemy.tuning["attack_range"])+60:
					dodge = true
					move = aim.rotated(PI/2.0)
					break
		for shot in game.enemy_shots:
			if game.player.dodge_cooldown == 0 and actor_pos.distance_to(shot["position"]) < 85:
				dodge = true
				move = shot["direction"].rotated(PI/2.0)
				break
		var slot := -1
		var cursor: Vector2 = foe.target.position
		for index in [tick%2,1-(tick%2)]:
			if game.sim.loadout.slots[index]["cooldown"]>0:
				continue
			var plan = game.sim.loadout.get_plan(index)
			if plan == null or game.sim.mana < float(plan.snapshot()["mana_cost"]):
				continue
			var form: String = str(plan.snapshot()["root"]["manifestation"]["id"])
			if form == "form.burst" and dist < float(game.data["player"]["max_burst_distance"])-10 and clear:
				slot = index
				break
			elif form == "form.projectile" and clear:
				slot = index
				break
			elif form == "form.orb" and dist < 260:
				slot = index
				break
		var response = game.issue({"move":move,"aim":aim,"cursor":cursor,"cast":slot,"dodge":dodge})
		game.step()
		total_ms += game.elapsed_frame_ms
	var summary: Dictionary = game.snapshot()
	return {
		"scenario":scenario,"loadout":loadout,"seed":FIXED_SEED,
		"completed":game.state=="cleared","result":game.state,
		"ticks":game.sim.clock.tick,"damage_received":snappedf(game.damage_received,0.01),
		"casts":game.player.casts,"dodges":game.player.dodges,"reactions":game.reactions,
		"enemies_remaining":game.alive_enemies(),
		"hp_remaining":snappedf(game.sim.actor.health.current,0.01),
		"max_frame_ms":snappedf(game.elapsed_frame_ms,0.01),
		"avg_sim_fps":snappedf(1000.0/(maxf(0.0001,total_ms/maxf(1.0,float(game.sim.clock.tick)))),0.1)
	}

static func _choose_target(game):
	var chosen = null
	var best := INF
	for enemy in game.enemies:
		if not enemy.target.alive():
			continue
		var gap: float = enemy.target.position.distance_squared_to(game.sim.actor.position)
		var visible: bool = game.world.clear_sight(enemy.target.position,game.sim.actor.position,8)
		var ranking := gap + (30000.0 if not visible else 0.0)
		if ranking < best:
			best = ranking
			chosen = enemy
	return chosen
