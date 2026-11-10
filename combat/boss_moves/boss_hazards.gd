extends RefCounted
## AD-198: per-phase boss arena hazards (zone, debris, rising_water), all data. One controller per boss, driven by boss_combat.gd.
## Warnings and active zones are published through session.add_hazard for rendering only (status "" so _step_hazards ignores them);
## damage is applied here through session.damage_player so dash i-frames work as usual. Only debris touches the boss RNG.
const WATER_TAG := "boss_rising_water"
const KINDS := ["boss_warning","boss_water_warning","boss_zone"]
const TYPES := {"zone":["radius","active_ticks","damage","damage_interval_ticks"],"debris":["count","scatter","radius","damage"],
	"rising_water":["duration_ticks","sets"]}
var _specs: Array = []
var _age := 0
var _next: Array = []
var _spawned: Array = []
var _live: Array = []

func enter_phase(specs: Array) -> void:
	_specs = specs
	_age = 0
	_next = []
	_spawned = []
	for spec in specs:
		_next.append(int(spec["first_ticks"]))
		_spawned.append(0)
	_live = []

## One tick: step the running instances (spec order of creation), then start the specs that are due.
func advance(boss, session) -> void:
	if _specs.is_empty():
		return
	var still: Array = []
	for inst in _live:
		inst["age"] = int(inst["age"])+1
		if _step(inst,boss,session):
			still.append(inst)
	_live = still
	for index in _specs.size():
		if _age == _next[index]:
			_next[index] += int(_specs[index]["every_ticks"])
			_start(index,boss,session)
	_age += 1

func clear(boss, session) -> void:
	_live = []
	_specs = []
	session.remove_hazards_from(boss.target.id,KINDS)
	if session.water != null:
		session.water.remove_tag(WATER_TAG)

func _publish(kind: String, boss, at: Vector2, radius: float, ticks: int, session, extra: Dictionary = {}) -> void:
	session.add_hazard({"kind":kind,"status":"","position":at,"radius":radius,"duration_ticks":ticks,"interval_ticks":1,
		"source_id":boss.target.id}.merged(extra))

func _start(index: int, boss, session) -> void:
	var spec: Dictionary = _specs[index]
	var warn := int(spec["warn_ticks"])
	var inst := {"spec":index,"age":0,"warn":warn}
	var count: int = _spawned[index]
	_spawned[index] = count+1
	match str(spec["type"]):
		"zone":
			var at: Vector2 = session.sim.actor.position
			if str(spec["at"]) == "points":
				var points: Array = spec["points"]
				at = Vector2(float(points[count%points.size()][0]),float(points[count%points.size()][1]))
			inst["points"] = [at]
			inst["radius"] = float(spec["radius"])
		"debris":
			var rng: RandomNumberGenerator = boss.rng(session)
			var centre: Vector2 = session.sim.actor.position
			var bounds: Rect2 = session.world.bounds
			var points: Array = []
			for i in int(spec["count"]):
				var spot := centre+Vector2.RIGHT.rotated(rng.randf()*TAU)*sqrt(rng.randf())*float(spec["scatter"])
				points.append(Vector2(clampf(spot.x,bounds.position.x,bounds.end.x),clampf(spot.y,bounds.position.y,bounds.end.y)))
			inst["points"] = points
			inst["radius"] = float(spec["radius"])
		"rising_water":
			var sets: Array = spec["sets"]
			var rects: Array = []
			for entry in sets[count%sets.size()]:
				var dims: Array = entry["rect"]
				rects.append({"kind":str(entry["kind"]),"rect":dims.duplicate()})
			inst["rects"] = rects
			for entry in rects:
				var rect := Rect2(float(entry["rect"][0]),float(entry["rect"][1]),float(entry["rect"][2]),float(entry["rect"][3]))
				_publish("boss_water_warning",boss,rect.get_center(),rect.size.length()*0.5,warn+1,session,{"rect":rect})
	if inst.has("points"):
		for point in inst["points"]:
			_publish("boss_warning",boss,point,float(inst["radius"]),warn+1,session)
	_live.append(inst)

## False once the instance is finished. Age == warn is the activation tick (active age 1).
func _step(inst: Dictionary, boss, session) -> bool:
	var spec: Dictionary = _specs[int(inst["spec"])]
	var age: int = inst["age"]
	var warn: int = inst["warn"]
	if age < warn:
		return true
	var active := age-warn+1
	match str(spec["type"]):
		"zone":
			if active > int(spec["active_ticks"]):
				return false
			if active == 1:
				var extra := {}
				if str(spec.get("status","")) != "":
					extra["status"] = str(spec["status"])
				_publish("boss_zone",boss,inst["points"][0],float(inst["radius"]),int(spec["active_ticks"])+1,session,extra)
			if (active-1)%int(spec["damage_interval_ticks"]) == 0:
				_hit(inst["points"][0],inst,spec,boss,session)
			return true
		"debris":
			for point in inst["points"]:
				_hit(point,inst,spec,boss,session)
			return false
		"rising_water":
			if active == 1:
				if session.water == null:
					session.set_water([])
				session.water.remove_tag(WATER_TAG)
				session.water.add_entries(inst["rects"].map(func(entry): return entry.merged({"tag":WATER_TAG})))
			if active > int(spec["duration_ticks"]):
				session.water.remove_tag(WATER_TAG)
				return false
	return true

func _hit(at: Vector2, inst: Dictionary, spec: Dictionary, boss, session) -> void:
	var player = session.sim.actor
	if player.alive() and at.distance_to(player.position) <= float(inst["radius"])+player.radius:
		session.damage_player(boss.target.id,float(spec["damage"]),str(spec.get("channel","physical")))

static func _num(value) -> bool:
	return typeof(value) == TYPE_INT or typeof(value) == TYPE_FLOAT

static func _point(value) -> bool:
	return typeof(value) == TYPE_ARRAY and value.size() == 2 and _num(value[0]) and _num(value[1])

static func _param(path: String, key: String, message: String) -> Dictionary:
	return {"code":"BOSS_HAZARD_PARAM","path":"%s.%s" % [path,key],"message":message}

## Issues for phase `hazards` arrays: BOSS_HAZARD_TYPE, BOSS_HAZARD_PARAM, BOSS_HAZARD_DEEP_WATER.
static func validate(settings: Dictionary) -> Array:
	var issues: Array = []
	var phases = settings.get("phases",[])
	if typeof(phases) != TYPE_ARRAY:
		return issues
	for p in phases.size():
		if typeof(phases[p]) != TYPE_DICTIONARY or not phases[p].has("hazards"):
			continue
		var list = phases[p]["hazards"]
		if typeof(list) != TYPE_ARRAY:
			issues.append(_param("phases[%d]" % p,"hazards","hazards must be an array"))
			continue
		for h in list.size():
			var path := "phases[%d].hazards[%d]" % [p,h]
			var spec = list[h]
			if typeof(spec) != TYPE_DICTIONARY or not TYPES.has(str(spec.get("type",""))):
				issues.append({"code":"BOSS_HAZARD_TYPE","path":path+".type","message":"type must be one of %s" % str(TYPES.keys())})
				continue
			for key in ["first_ticks","every_ticks","warn_ticks"]:
				var minimum := 0 if key == "first_ticks" else 1
				if not spec.has(key) or not _num(spec[key]) or float(spec[key]) < minimum:
					issues.append(_param(path,key,"%s must be a number >= %d" % [key,minimum]))
			for key in TYPES[str(spec["type"])]:
				if not spec.has(key):
					issues.append(_param(path,key,"%s hazard needs '%s'" % [spec["type"],key]))
				elif key != "sets" and (not _num(spec[key]) or float(spec[key]) <= 0.0 and key != "damage" and key != "scatter"):
					issues.append(_param(path,key,"'%s' must be a positive number" % key))
			match str(spec["type"]):
				"zone":
					var at := str(spec.get("at",""))
					if at != "player" and at != "points":
						issues.append(_param(path,"at","at must be 'player' or 'points'"))
					elif at == "points":
						var points = spec.get("points",[])
						var ok: bool = typeof(points) == TYPE_ARRAY and not points.is_empty()
						if ok:
							for point in points:
								ok = ok and _point(point)
						if not ok:
							issues.append(_param(path,"points","points must be a non-empty array of [x,y]"))
				"rising_water":
					_validate_sets(spec.get("sets"),path,issues)
	return issues

static func _validate_sets(sets, path: String, issues: Array) -> void:
	var ok: bool = typeof(sets) == TYPE_ARRAY and not sets.is_empty()
	if not ok:
		if sets != null:
			issues.append(_param(path,"sets","sets must be a non-empty array of entry arrays"))
		return
	for s in sets.size():
		var entries = sets[s]
		if typeof(entries) != TYPE_ARRAY or entries.is_empty():
			issues.append(_param(path,"sets[%d]" % s,"each set must be a non-empty array"))
			continue
		for e in entries.size():
			var entry = entries[e]
			var entry_path := "sets[%d][%d]" % [s,e]
			var rect = entry.get("rect") if typeof(entry) == TYPE_DICTIONARY else null
			if typeof(rect) != TYPE_ARRAY or rect.size() != 4 or not rect.all(func(v): return typeof(v) == TYPE_INT or typeof(v) == TYPE_FLOAT):
				issues.append(_param(path,entry_path+".rect","rect must be [x,y,w,h]"))
			var kind := str(entry.get("kind","")) if typeof(entry) == TYPE_DICTIONARY else ""
			if kind == "deep":
				issues.append({"code":"BOSS_HAZARD_DEEP_WATER","path":"%s.%s.kind" % [path,entry_path],"message":"rising water must be shallow (deep rects are not registered as ground blockers at runtime)"})
			elif kind != "shallow":
				issues.append(_param(path,entry_path+".kind","kind must be 'shallow'"))
