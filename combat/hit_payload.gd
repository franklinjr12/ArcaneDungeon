extends RefCounted
## TASK-012: typed hit contract shared by every manifestation and element.
## Knockback is metadata only in M1; M2 owns physical knockback and player physics.
var valid := false
var issues: Array = []
var _data: Dictionary = {}

func _init(fields: Dictionary = {}, channels: Dictionary = {}) -> void:
	from_dict(fields,channels)

func from_dict(fields: Dictionary, channels: Dictionary = {}) -> Dictionary:
	issues.clear()
	valid = false
	_data.clear()
	var essence = fields.get("essence_id")
	if typeof(essence) != TYPE_STRING or not channels.has(essence):
		issues.append({"code":"HIT_ESSENCE_INVALID","path":"essence_id","message":"Essence must have a registered channel"})
	var raw_damage = fields.get("damage")
	if typeof(raw_damage) not in [TYPE_FLOAT,TYPE_INT] or float(raw_damage) < 0:
		issues.append({"code":"HIT_DAMAGE_INVALID","path":"damage","message":"Base damage must be nonnegative numeric"})
	var team = fields.get("team")
	if typeof(team) != TYPE_INT:
		issues.append({"code":"HIT_TEAM_INVALID","path":"team","message":"Expected source team integer"})
	for key in ["cast_id","root_cast_id","caster_id"]:
		if typeof(fields.get(key,0)) != TYPE_INT:
			issues.append({"code":"HIT_SOURCE_INVALID","path":key,"message":"Expected stable source/cast ID integer"})
	if not issues.is_empty():
		return {"ok":false,"issues":issues.duplicate(true)}
	var direction := Vector2.ZERO
	var knockback = fields.get("knockback",{})
	if typeof(knockback) == TYPE_DICTIONARY and knockback.get("direction") is Vector2:
		direction = knockback["direction"]
	var amount: float = maxf(0,float(knockback.get("force",0))) if typeof(knockback) == TYPE_DICTIONARY else 0.0
	_data = {
		"essence_id":essence,"damage":float(raw_damage),"team":int(team),
		"channel":str(channels[essence]["channel"]),"channels":[str(channels[essence]["channel"])],
		"cast_id":int(fields.get("cast_id",0)),"root_cast_id":int(fields.get("root_cast_id",0)),
		"caster_id":int(fields.get("caster_id",0)),"formula_id":str(fields.get("formula_id","")),
		"knockback":{"force":amount,"direction":{"x":direction.x,"y":direction.y}}
	}
	valid = true
	return {"ok":true,"issues":[]}

func snapshot() -> Dictionary:
	return _data.duplicate(true)
