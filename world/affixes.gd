class_name Affixes
extends RefCounted
## AD-239: elite enemy affixes as data. roll() picks at most one affix per elite from the seed;
## apply() stamps it on an enemy (never on boss/mini_boss). Effects are read via definitions().
const PATH := "res://world/data/affixes_v1.json"
const ShieldFront = preload("res://combat/enemy_behaviours/shield_front.gd")
const Difficulty = preload("res://game/core/difficulty.gd")
## Tag the interaction resolver and the session honour for knockback-immune affixes (anchored).
const KNOCKBACK_IMMUNE_TAG := "knockback_immune"
const EXCLUDED_TAGS := ["boss","mini_boss"]
static var _cache: Dictionary = {}

static func load_config() -> Dictionary:
	var file := FileAccess.open(PATH, FileAccess.READ)
	if file == null:
		return {}
	var parsed = JSON.parse_string(file.get_as_text())
	return parsed if parsed is Dictionary else {}

static func config() -> Dictionary:
	if _cache.is_empty():
		_cache = load_config()
	return _cache

static func definitions() -> Dictionary:
	return config().get("affixes", {})

static func ids() -> Array:
	var out := definitions().keys()
	out.sort()
	return out

static func is_known(id: String) -> bool:
	return definitions().has(id)

static func param(id: String, key: String, default: Variant = null) -> Variant:
	return definitions().get(id, {}).get(key, default)

## room_index is 1-based within the stage; optional rooms use their own chance at any depth.
static func chance_for(room_index: int, optional: bool) -> float:
	var table: Dictionary = config().get("spawn_chance_by_depth", {})
	if optional:
		return float(table.get("optional", 0.0))
	if room_index < int(config().get("min_room", 2)):
		return 0.0
	return float(table.get(str(room_index), table.get("3", 0.0)))

## Deterministic: "" or one affix id.
static func roll(seed_value: int, room_index: int, optional: bool) -> String:
	var chance := chance_for(room_index, optional)
	if chance <= 0.0:
		return ""
	var rng := RandomNumberGenerator.new()
	rng.seed = hash([seed_value, room_index, optional])
	if rng.randf() >= chance:
		return ""
	var list := ids()
	return str(list[rng.randi_range(0, list.size() - 1)])

## Which wave spawn is the room's elite: [wave, index] from data; mini-bosses are never it.
static func elite_slot() -> Array:
	var slot: Dictionary = config().get("elite_spawn", {})
	return [int(slot.get("wave", 0)), int(slot.get("index", 0))]

## Seed for a room: run seed mixed with the room id so every room rolls independently.
static func room_seed(run_seed: int, room_id: String) -> int:
	return hash([run_seed, room_id])

static func outline_color(id: String) -> Color:
	return Color.html(str(param(id, "outline_color", "#ffffff")))

static func eligible(enemy) -> bool:
	if enemy == null or enemy.target == null:
		return false
	for tag in EXCLUDED_TAGS:
		if tag in enemy.target.tags:
			return false
	return true

## Stamps the affix id and its persistent effects (all numbers from data; HP is never raised).
static func apply(_session, enemy, id: String) -> void:
	if not is_known(id) or not eligible(enemy):
		return
	enemy.affix = id
	enemy.target.tags.append("affix:" + id)
	enemy.affix_speed_scale = float(param(id, "speed_multiplier", 1.0))
	match id:
		"warded":
			var counters: Dictionary = param(id, "counters", {})
			var essences: Array = counters.keys()
			essences.sort()
			var rng := RandomNumberGenerator.new()
			rng.seed = hash([enemy.target.id, id])
			enemy.affix_essence = str(essences[rng.randi_range(0, essences.size() - 1)])
			# Resistance 1.0 = immune; a negative resistance is a weakness (1 - weak_multiplier). The ward replaces the
			# kind's natural weaknesses so its counter essence is the one weakness the player reads.
			var resistances: Dictionary = {}
			for channel in enemy.target.health.resistances:
				if float(enemy.target.health.resistances[channel]) >= 0.0:
					resistances[channel] = enemy.target.health.resistances[channel]
			resistances[enemy.affix_essence] = 1.0
			resistances[str(counters[enemy.affix_essence])] = 1.0 - float(param(id, "weak_multiplier", 1.0))
			enemy.target.health.resistances = resistances
		"shielded":
			enemy.affix_shield = ShieldFront.new({"front_damage_scale": float(param(id, "front_damage_scale", 1.0)),
				"front_arc_degrees": float(param(id, "front_arc_degrees", 0.0))})
		"anchored":
			if bool(param(id, "knockback_immune", false)):
				enemy.target.tags.append(KNOCKBACK_IMMUNE_TAG)

## Session calls this each tick after EnemyCombat.begin_tick and before the AI rewrites heading: the shield arc
## uses the facing the enemy showed during the previous tick. Knockback-immune elites drop any impulse.
static func tick(session, enemy) -> void:
	if enemy.affix == "" or not enemy.target.alive():
		return
	if KNOCKBACK_IMMUNE_TAG in enemy.target.tags:
		enemy.target.impulse = Vector2.ZERO
	if enemy.affix_shield != null and not enemy.target.status.has("frozen", session.sim.clock.tick):
		enemy.affix_shield.tick(enemy, session, {"toward": session.sim.actor.position - enemy.target.position})

## Death effects, run once from CombatSession.on_enemy_death. Children of a splitting elite carry no affix.
static func on_death(session, enemy) -> void:
	var id: String = str(enemy.get("affix")) if enemy.get("affix") != null else ""
	if id == "" or not is_known(id):
		return
	var at: Vector2 = enemy.target.position
	match id:
		"volatile":
			# Telegraphed blast: drawn as a boss_warning circle; session._step_hazards deals the damage at blast_age.
			var ticks := Difficulty.scale_i(int(param(id, "telegraph_ticks", 1)), "telegraph_length")
			session.add_hazard({"kind": "boss_warning", "status": "", "position": at, "radius": float(param(id, "blast_radius", 0.0)),
				"duration_ticks": ticks + 1, "interval_ticks": ticks + 1, "source_id": enemy.target.id, "telegraph": true,
				"blast_age": ticks, "blast_damage": Difficulty.scale_f(float(param(id, "blast_damage", 0.0)), "enemy_damage"),
				"blast_channel": str(param(id, "blast_channel", "physical"))})
		"splitting":
			var count := int(param(id, "children", 0))
			var hp := float(session.data["enemies"][enemy.kind]["hp"]) * float(param(id, "hp_fraction", 1.0))
			var radius: float = enemy.target.radius * float(param(id, "radius_scale", 1.0))
			for i in count:
				var angle: float = TAU * float(i) / float(count)
				session.pending_spawns.append({"kind": enemy.kind, "summoner_id": enemy.target.id,
					"position": at + Vector2.RIGHT.rotated(angle) * float(param(id, "split_radius", 0.0)),
					"overrides": {"hp": hp, "radius": radius}})
