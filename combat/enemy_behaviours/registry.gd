extends RefCounted
## Behaviour component registry (AD-136): id -> script, list building and data validation.
const SCRIPTS := {
	"chase": preload("res://combat/enemy_behaviours/chase.gd"),
	"keep_distance": preload("res://combat/enemy_behaviours/keep_distance.gd"),
	"melee_attack": preload("res://combat/enemy_behaviours/melee_attack.gd"),
	"ranged_attack": preload("res://combat/enemy_behaviours/ranged_attack.gd"),
	"charge": preload("res://combat/enemy_behaviours/charge.gd"),
	"turret": preload("res://combat/enemy_behaviours/turret.gd"),
	"phase_walls": preload("res://combat/enemy_behaviours/phase_walls.gd"),
	"summon": preload("res://combat/enemy_behaviours/summon.gd"),
	"shield_front": preload("res://combat/enemy_behaviours/shield_front.gd"),
	"explode_on_death": preload("res://combat/enemy_behaviours/explode_on_death.gd"),
	"intangible_cycle": preload("res://combat/enemy_behaviours/intangible_cycle.gd"),
	"support_buff": preload("res://combat/enemy_behaviours/support_buff.gd"),
}

static func role(id: String) -> String:
	if not SCRIPTS.has(id):
		return ""
	return str(SCRIPTS[id].get_script_constant_map().get("ROLE",""))

## Instantiates components in list order; malformed/unknown entries are skipped (validate_enemy reports them).
static func build(list: Array) -> Array:
	var built: Array = []
	for entry in list:
		if typeof(entry) == TYPE_DICTIONARY and SCRIPTS.has(str(entry.get("id",""))):
			built.append(SCRIPTS[str(entry["id"])].new(entry))
	return built

static func validate_enemy(config: Dictionary) -> Array:
	var issues: Array = []
	if typeof(config.get("behaviours")) != TYPE_ARRAY:
		return ["behaviours: missing or not a list"]
	var movement := 0
	var attack := 0
	for entry in config["behaviours"]:
		if typeof(entry) != TYPE_DICTIONARY:
			issues.append("behaviours: entry is not an object")
			continue
		var id := str(entry.get("id",""))
		if not SCRIPTS.has(id):
			issues.append("behaviours: unknown id '%s'" % id)
			continue
		issues.append_array(SCRIPTS[id].validate(entry))
		for key in SCRIPTS[id].get_script_constant_map().get("CONFIG_KEYS",[]):
			if not entry.has(key) and not (typeof(config.get(key)) in [TYPE_INT,TYPE_FLOAT]):
				issues.append("%s: enemy needs numeric '%s'" % [id,key])
		match role(id):
			"movement":
				movement += 1
			"attack":
				attack += 1
	if movement != 1:
		issues.append("behaviours: need exactly one movement component, got %d" % movement)
	if attack > 1:
		issues.append("behaviours: at most one attack component, got %d" % attack)
	for key in ["preferred_range","attack_range","damage","telegraph_ticks","recovery_ticks","cooldown_ticks","move_speed","perception_radius"]:
		if not (typeof(config.get(key)) in [TYPE_INT,TYPE_FLOAT]):
			issues.append("enemy: '%s' missing or not numeric" % key)
	return issues
