extends RefCounted
## Base enemy behaviour component (AD-136). Components are composed per enemy from
## tuning["behaviours"]; EnemyCombat keeps the state machine and calls these hooks in list order.
## ctx = {"toward","distance","sight","player"} computed once per tick by EnemyCombat.
var params: Dictionary

func _init(p: Dictionary = {}) -> void:
	params = p

## Component param, falling back to the (difficulty-scaled) enemy tuning for shared keys.
func param(enemy, key: String, fallback = null):
	return params.get(key,enemy.tuning.get(key,fallback))

func movement(_enemy, _session, _ctx: Dictionary) -> Vector2:
	return Vector2.ZERO

func wants_attack(_enemy, _session, _ctx: Dictionary) -> bool:
	return false

func build_attack(_enemy, _ctx: Dictionary) -> Dictionary:
	return {}

func execute_attack(_enemy, _session) -> void:
	pass

## Attack components with a multi-tick active phase (e.g. charge) return its length; EnemyCombat then
## enters state "attack" between windup and recover and calls active_tick() once per tick. 0 = instant attack.
func active_ticks(_enemy) -> int:
	return 0

func active_tick(_enemy, _session, _ctx: Dictionary) -> void:
	pass

## Modifier components (role "modifier") set flags on the enemy once at construction.
func modify(_enemy) -> void:
	pass

func on_death(_enemy, _session) -> void:
	pass

func tick(_enemy, _session, _ctx: Dictionary) -> void:
	pass

## Direction toward the destination: straight when the enemy phases through walls, else around obstacles.
func nav_direction(enemy, session, ctx: Dictionary) -> Vector2:
	if enemy.phase_walls:
		return ctx["toward"].normalized()
	return session.world.navigate_direction(enemy.target.position,ctx["player"].position,enemy.target.radius)

## Shared intent payload for attack components (fields read by UI telegraphs).
static func standard_intent(enemy, ctx: Dictionary) -> Dictionary:
	var tuning: Dictionary = enemy.tuning
	return {"source_id":enemy.target.id,"kind":enemy.kind,"geometry":str(tuning["attack_kind"]),
		"origin":enemy.target.position,"direction":ctx["toward"].normalized(),"range":float(tuning["attack_range"]),
		"telegraph_ticks":int(tuning["telegraph_ticks"]),"damage":float(tuning["damage"])}

## Issue strings for missing required keys or non-numeric numeric keys.
static func check(id: String, params: Dictionary, required: Array, numeric: Array, flags: Array = []) -> Array:
	var issues: Array = []
	for key in required:
		if not params.has(key):
			issues.append("%s: missing param '%s'" % [id,key])
	for key in numeric:
		if params.has(key) and not (typeof(params[key]) in [TYPE_INT,TYPE_FLOAT]):
			issues.append("%s: param '%s' must be numeric" % [id,key])
	for key in flags:
		if params.has(key) and typeof(params[key]) != TYPE_BOOL:
			issues.append("%s: param '%s' must be bool" % [id,key])
	return issues

static func validate(_params: Dictionary) -> Array:
	return []
