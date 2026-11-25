extends "res://combat/enemy_behaviours/behaviour.gd"
## Tick component (AD-237): fire_ward. Every tick each other living non-boss ally within ward_radius that is not
## Wet gets health.resistances["fire"] = ward_fire_resistance (0.75 = fire does 25%). The ally's original fire
## resistance (or its absence) is remembered here and restored exactly the tick it leaves range or becomes Wet, and
## for every warded ally when the censer dies (on_death). An ally that already resists fire at least as much (or
## is warded by another censer) is left alone. All state stays inside the component.
const ROLE := "tick"

## ally target id -> {"enemy": EnemyCombat, "had": bool, "original": float}
var _warded: Dictionary = {}

func tick(enemy, session, _ctx: Dictionary) -> void:
	var radius: float = float(params["ward_radius"])
	var ward: float = float(params["ward_fire_resistance"])
	var now: int = session.sim.clock.tick
	for other in session.enemies:
		if other == enemy or not ("buff_damage_scale" in other): # EliteMinion is not an EnemyCombat and takes no wards
			continue
		var id: int = other.target.id
		var eligible: bool = other.target.alive() and not ("boss" in other.target.tags) \
			and enemy.target.position.distance_to(other.target.position) <= radius \
			and not other.target.status.has("wet",now)
		if _warded.has(id):
			if eligible:
				continue
			_restore(id)
		elif eligible and float(other.target.health.resistances.get("fire",0.0)) < ward:
			var resistances: Dictionary = other.target.health.resistances
			_warded[id] = {"enemy":other,"had":resistances.has("fire"),"original":float(resistances.get("fire",0.0))}
			resistances["fire"] = ward

func on_death(_enemy, _session) -> void:
	for id in _warded.keys():
		_restore(id)

func warded_ids() -> Array:
	var ids := _warded.keys()
	ids.sort()
	return ids

func _restore(id: int) -> void:
	var entry: Dictionary = _warded[id]
	var resistances: Dictionary = entry["enemy"].target.health.resistances
	if bool(entry["had"]):
		resistances["fire"] = float(entry["original"])
	else:
		resistances.erase("fire")
	_warded.erase(id)

static func validate(params: Dictionary) -> Array:
	var issues := check("fire_ward",params,["ward_radius","ward_fire_resistance"],["ward_radius","ward_fire_resistance"])
	if typeof(params.get("ward_radius")) in [TYPE_INT,TYPE_FLOAT] and float(params["ward_radius"]) <= 0.0:
		issues.append("fire_ward: param 'ward_radius' must be > 0")
	if typeof(params.get("ward_fire_resistance")) in [TYPE_INT,TYPE_FLOAT] and (float(params["ward_fire_resistance"]) < 0.0 or float(params["ward_fire_resistance"]) > 1.0):
		issues.append("fire_ward: param 'ward_fire_resistance' must be within 0..1")
	return issues
