extends RefCounted
const Session = preload("res://combat/combat_session.gd")
const Enemy = preload("res://combat/enemy_combat.gd")
const Geometry = preload("res://world/arena_geometry.gd")
const Projectile = preload("res://magic/runtime/projectile_effect.gd")

func run(t) -> void:
	var game = Session.new(701,"single",0)
	t.check(game.initialized,"TASK-026 combat session initializes using M1 runner")
	t.equal(game.alive_enemies(),1,"TASK-035 single bone thrall scenario spawns")
	t.equal(game.sim.loadout.slots.size(),4,"AD-012 four loadout slots persist in combat")
	var start: Vector2 = game.sim.actor.position
	for raw in [Vector2.RIGHT,Vector2.LEFT,Vector2.UP,Vector2.DOWN,Vector2(1,1),
		Vector2(-1,1),Vector2(1,-1),Vector2(-1,-1)]:
		var from: Vector2 = game.sim.actor.position
		var response: Dictionary = game.issue({"move":raw,"aim":raw,"cast":-1,"dash":false})
		t.check(response["accepted"],"TASK-026 eight-way command accepted "+str(raw))
		t.check(game.sim.actor.position.distance_to(from)>0,"TASK-026 eight-way displacement "+str(raw))
		t.check(game.player.facing.is_equal_approx(raw.normalized()),"TASK-026 eight-way aim "+str(raw))
	t.check(start.distance_to(game.sim.actor.position)<15.0,"TASK-026 symmetric eight-way movement returns near origin")
	var speed: float = game.sim.actor.position.distance_to(
		game.world.move_body(game.sim.actor.position,Vector2.RIGHT*float(game.data["player"]["move_speed"])/60.0,game.sim.actor.radius))
	t.check(speed>2.0,"TASK-026 movement is nonzero at fixed 60 Hz")
	game.player.modal = true
	var blocked_point: Vector2 = game.sim.actor.position
	var modal_response: Dictionary = game.issue({"move":Vector2.RIGHT,"cast":0,"aim":Vector2.RIGHT})
	t.equal(modal_response["reason"],"MODAL_OPEN","TASK-026 modal blocks move+cast")
	t.equal(game.sim.actor.position,blocked_point,"TASK-026 modal does not move")
	game.player.modal = false
	game.sim.clock.set_paused(true)
	t.equal(game.issue({"move":Vector2.RIGHT,"cast":0,"aim":Vector2.RIGHT})["reason"],"PAUSED","TASK-026 pause blocks casts and movement")
	game.sim.clock.set_paused(false)
	var begin_mana: float = game.sim.mana
	var first: Dictionary = game.issue({"move":Vector2.ZERO,"aim":Vector2.RIGHT,"cast":0})
	t.check(first["accepted"],"TASK-026 manual cast accepted same command frame")
	t.check(game.sim.mana<begin_mana,"TASK-026 cast appears and spends resource without additional tick")
	t.check(game.sim.active.size()>0,"TASK-026 cast creates active projectile immediately")
	var dash: Dictionary = game.issue({"move":Vector2.RIGHT,"aim":Vector2.RIGHT,"dash":true,"cast":0})
	t.equal(dash["reason"],"DASH_LOCKOUT","TASK-027 dash cancels simultaneous cast")
	t.check(game.player.invulnerable(),"TASK-027 dash activates invulnerability")
	var blocker = game.world
	t.check(not blocker.clear_sight(Vector2(510,260),Vector2(750,260)),"TASK-033 solid wall blocks LOS")
	t.check(blocker.clear_sight(Vector2(510,450),Vector2(750,450)),"TASK-033 arena gap preserves LOS")
	var collided: Vector2 = blocker.move_body(Vector2(540,250),Vector2.RIGHT*180,17)
	t.check(collided.x<565,"TASK-027 dash speed cannot tunnel through solid wall")
	game.sim.actor.position = Vector2(540,250)
	game.issue({"move":Vector2.RIGHT,"dash":false,"aim":Vector2.RIGHT})
	t.check(game.sim.actor.position.x<565,"TASK-027 active dash cannot pass wall")
	game.sim.actor.position = Vector2(185,450)
	var source_id: int = game.enemies[0].target.id
	var dashed: Dictionary = game.damage_player(source_id,100,"physical")
	t.equal(dashed["reason"],"INVULNERABLE","TASK-027 attack during i-frames deals no damage")
	t.equal(game.sim.actor.health.current,float(game.data["player"]["max_hp"]),"TASK-027 dash avoids HP loss")
	var dashes: int = game.player.dashes
	game.issue({"move":Vector2.RIGHT,"dash":true})
	t.equal(game.player.dashes,dashes,"TASK-027 dash spam cannot restart during cooldown")
	for i in 70:
		game.player.step_timers()
	var hurt: Dictionary = game.damage_player(source_id,12,"physical")
	t.check(hurt["accepted"],"TASK-028 damage outside i-frames allowed")
	t.equal(game.damage_events.size(),1,"TASK-028 one attack records exactly one event")
	t.equal(game.damage_player(source_id,12,"physical",int(game.damage_events[0]["attack_id"]))["reason"],"ALREADY_APPLIED",
		"TASK-028 repeated attack ID does not double damage")
	t.equal(game.sim.actor.health.current,float(game.data["player"]["max_hp"])-12.0,"TASK-028 HP decremented once")
	var ally = game.sim.targets.get_target(game.sim.actor.id)
	t.equal(ally.receive_damage(500,"physical",ally.team,100),0.0,"TASK-028 friendly fire off")
	var snapshot: Dictionary = game.snapshot()
	t.equal(snapshot["hits_received"],1,"TASK-028 damage metrics reflect one event")
	t.check(game.player.dash_cooldown==0,"TASK-027 dash recovers after cooldown")
	var scene = Session.new(902,"mixed",1)
	t.equal(scene.alive_enemies(),3,"TASK-033 mixed scenario spawns all three archetypes")
	t.check(scene.enemies[0].kind!=scene.enemies[1].kind and scene.enemies[1].kind!=scene.enemies[2].kind,
		"TASK-029 shared controller configured three archetypes")
	var observed: Dictionary = {}
	for i in 70:
		scene.issue({"move":Vector2.ZERO,"aim":Vector2.RIGHT})
		scene.step()
		for foe in scene.enemies:
			observed[foe.kind]=foe.state
	t.check(scene.enemies[0].transitions.size()>0,"TASK-029 bone_thrall state transitions recorded")
	t.check(scene.enemies[1].transitions.size()>0,"TASK-029 ranged state transitions recorded")
	t.check(scene.enemies[2].transitions.size()>0,"TASK-029 grave_hound state transitions recorded")
	for foe in scene.enemies:
		t.check(scene.world.valid_position(foe.target.position,foe.target.radius),"TASK-032 "+foe.kind+" remains in arena")
	var flank_start: Vector2 = scene.enemies[2].target.position
	for i in 50:
		scene.step()
	var flank_direction: Vector2 = scene.enemies[2].target.position-flank_start
	t.check(absf(flank_direction.y)>3.0,"TASK-032 grave_hound has lateral displacement")
	var windup = Session.new(777,"single",0)
	var bone_thrall = windup.enemies[0]
	bone_thrall.target.position = windup.sim.actor.position+Vector2(60,0)
	bone_thrall.change_state("chase",windup.sim.clock.tick)
	bone_thrall.advance(windup)
	t.equal(bone_thrall.state,"windup","TASK-029 melee enemy advertises windup before damage")
	var healthy: float = windup.sim.actor.health.current
	for i in int(bone_thrall.tuning["telegraph_ticks"])-1:
		windup.step()
	t.equal(windup.sim.actor.health.current,healthy,"TASK-029 no damage during melee telegraph")
	windup.step()
	t.check(windup.sim.actor.health.current<healthy,"TASK-030 melee hits after completed telegraph")
	var killed = Session.new(777,"single",0)
	var victim = killed.enemies[0]
	victim.target.receive_damage(200,"fire",killed.sim.actor.team,100)
	killed.step()
	t.equal(killed.state,"cleared","TASK-028 last enemy death clears combat arena")
	t.equal(killed._death_ids.size(),1,"TASK-028 enemy death emitted once")
	killed.step()
	t.equal(killed._death_ids.size(),1,"TASK-028 dead enemy cannot reward or die twice")
	killed.restart(777,"single",0)
	t.equal(killed.state,"playing","TASK-028 retry resets result")
	t.equal(killed.sim.clock.tick,0,"TASK-028 retry resets simulation tick")
	t.equal(killed.sim.queue.active_effect_count(),0,"TASK-028 retry frees old effects")
	t.equal(killed._death_ids.size(),0,"TASK-028 retry clears death ledger")
	var doomed = Session.new(778,"single",0)
	doomed.damage_player(doomed.enemies[0].target.id,999,"physical")
	doomed.step()
	t.equal(doomed.state,"dead","TASK-028 player death terminates game")
	t.equal(doomed.issue({"cast":0,"move":Vector2.RIGHT})["reason"],"COMBAT_ENDED","TASK-028 dead player cannot act")
	doomed.restart(778,"single",0)
	t.equal(doomed.sim.actor.health.current,150.0,"TASK-028 retry restores HP")
	# Ranged: line-of-sight and projectile collision use shared world geometry.
	var gun = Session.new(888,"mixed",0)
	var shooter = gun.enemies[1]
	shooter.target.position = Vector2(495,260)
	gun.sim.actor.position = Vector2(735,260)
	t.check(not gun.world.clear_sight(shooter.target.position,gun.sim.actor.position),"TASK-031 occluded ranged target")
	shooter.change_state("chase",0)
	shooter.advance(gun)
	t.check(shooter.state!="windup","TASK-031 no attack through wall")
	gun.sim.actor.position = Vector2(735,450)
	shooter.target.position = Vector2(495,450)
	shooter.advance(gun)
	t.equal(shooter.state,"windup","TASK-031 clear LOS ranged attack announces windup")
	var original_shots: int = gun.enemy_shots.size()
	for i in int(shooter.tuning["telegraph_ticks"])-1:
		shooter.advance(gun)
	t.equal(gun.enemy_shots.size(),original_shots,"TASK-031 no projectile during windup")
	shooter.advance(gun)
	t.equal(gun.enemy_shots.size(),original_shots+1,"TASK-031 projectile launches after telegraph")
	var first_shot_id: int = int(gun.enemy_shots[0]["attack_id"])
	gun.player.invulnerable_left = 100
	for i in 110:
		gun.advance_enemy_projectiles()
	t.equal(gun.sim.actor.health.current,150.0,"TASK-031 ranged shot respects invulnerable state")
	t.check(gun.enemy_shots.is_empty(),"TASK-031 projectile removed after collision or timeout")
