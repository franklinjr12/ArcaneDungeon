extends RefCounted
const Health = preload("res://combat/health_component.gd")
const Status = preload("res://combat/status_component.gd")
var id := 0
var team := 2
var position := Vector2.ZERO
var radius := 18.0
var tags: Array = []
var removed := false
var motion := Vector2.ZERO
## Sim state (AD-131): knockback velocity in px/s, decayed per tick by SpellRunner; part of the deterministic simulation.
var impulse := Vector2.ZERO
## Sim state (AD-136): incoming-damage multiplier set each tick by enemy components (shield_front, support_buff); 1.0 = untouched.
var damage_scale := 1.0
var health
var status
var hit_count := 0
var total_received := 0.0
## Presentation only (AD-015): recent damage hits for damage numbers; never serialized. (Unlike `impulse`, not sim state.)
var damage_log: Array = []

func _init(stable_id: int, target_team: int, point: Vector2, hp: float = 100.0, hit_radius: float = 18.0, defense: float = 0.0, channel_resistances: Dictionary = {}) -> void:
	id = stable_id
	team = target_team
	position = point
	radius = hit_radius
	health = Health.new(hp,defense,channel_resistances)
	status = Status.new()

func eligible(attacker_team: int) -> bool:
	return not removed and health.alive() and team != attacker_team

func alive() -> bool:
	return not removed and health.alive()

func receive_damage(amount: float, channel: String, attacker_team: int, armor_scale: float) -> float:
	if not eligible(attacker_team):
		return 0.0
	if damage_scale != 1.0:
		amount *= damage_scale
	var dealt: float = health.damage(amount,channel,armor_scale)
	if dealt > 0:
		hit_count += 1
		total_received += dealt
		damage_log.append({"amount": dealt, "channel": channel})
		if damage_log.size() > 16:
			damage_log.pop_front()
	return dealt
