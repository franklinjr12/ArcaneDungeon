extends RefCounted
## Fixed-seed reproducible M3 play policy: only CombatSession.issue commands damage enemies.
const Flow = preload("res://world/run_flow.gd")
const SEED := 20261022

static func fight(flow, maximum_ticks: int = 4000) -> Dictionary:
	for iteration in maximum_ticks:
		if flow.state != "fighting":
			break
		var session = flow.session
		var actor: Vector2 = session.sim.actor.position
		var foe = _nearest(session)
		var movement := Vector2.ZERO
		var direction := Vector2.RIGHT
		var cursor: Vector2 = actor + Vector2.RIGHT*130
		var distance := INF
		var sight := false
		if foe != null:
			cursor = foe.target.position
			var displacement: Vector2 = cursor-actor
			distance = displacement.length()
			direction = displacement.normalized()
			if direction.is_zero_approx():
				direction = Vector2.RIGHT
			sight = session.world.clear_sight(actor,cursor,8)
			if distance > 220 or not sight:
				movement = session.world.navigate_direction(actor,cursor,session.sim.actor.radius)
			elif distance < 120:
				movement = -direction
			else:
				movement = direction.rotated(PI/2.0)*0.4
		else:
			# Waiting for delayed wave; do not accidentally transition early.
			movement = Vector2.ZERO
		var dodge := false
		if session.player.dodge_cooldown == 0:
			for enemy in session.enemies:
				if enemy.target.alive() and enemy.state == "windup":
					var deadline: int = int(enemy.tuning["telegraph_ticks"])-enemy.state_tick
					if deadline <= 7 and actor.distance_to(enemy.target.position) < float(enemy.tuning["attack_range"])+65:
						dodge = true
						movement = direction.rotated(PI/2.0)
						break
			for shot in session.enemy_shots:
				if actor.distance_to(shot["position"]) < 110:
					dodge = true
					movement = shot["direction"].rotated(PI/2.0)
					break
		var slot := -1
		if foe != null and session.player.dodge_left == 0 and session.player.recovery_left == 0:
			for idx in [1+iteration%2,2-iteration%2]:
				if session.sim.loadout.slots[idx]["cooldown"] > 0:
					continue
				var spell = session.sim.loadout.get_plan(idx)
				if spell == null or session.sim.mana < float(spell.snapshot()["mana_cost"]):
					continue
				var form: String = str(spell.snapshot()["root"]["manifestation"]["id"])
				if form == "form.projectile" and sight:
					slot = idx
					break
				if form == "form.burst" and sight and distance <= float(session.data["player"]["max_burst_distance"])-10:
					slot = idx
					break
				if form == "form.orb" and distance < 160:
					slot = idx
					break
			if slot == -1 and sight:
				var bolt = session.sim.loadout.get_plan(0)
				if bolt != null and session.sim.loadout.slots[0]["cooldown"] == 0 and session.sim.mana >= float(bolt.snapshot()["mana_cost"]):
					slot = 0
		flow.step({"move":movement,"aim":direction,"cursor":cursor,"cast":slot,"dodge":dodge})
	return {"state":flow.state,"tick":flow.session.sim.clock.tick,
		"hp":flow.session.sim.actor.health.current,"casts":flow.session.player.casts,
		"enemies":flow.session.alive_enemies()}

static func reach_exit(flow, max_ticks: int = 1100) -> Dictionary:
	for i in max_ticks:
		if flow.session.sim.actor.position.distance_to(flow.room.marker("exit")) <= 65:
			return flow.try_exit(flow.session.sim.actor.position)
		var point: Vector2 = flow.session.sim.actor.position
		var direction: Vector2 = flow.session.world.navigate_direction(point,flow.room.marker("exit"),
			flow.session.sim.actor.radius)
		flow.move_after_clear({"move":direction,"aim":direction})
	return {"ok":false,"reason":"EXIT_NAV_TIMEOUT","position":flow.session.sim.actor.position}

static func _nearest(session):
	var target = null
	var best := INF
	for enemy in session.enemies:
		if not enemy.target.alive():
			continue
		var point: Vector2 = enemy.target.position
		var length: float = point.distance_squared_to(session.sim.actor.position)
		var los: bool = session.world.clear_sight(point,session.sim.actor.position,8)
		var weighted := length+(50000 if not los else 0)
		if weighted < best:
			best = weighted
			target = enemy
	return target
