extends RefCounted
## AD-150 [PROPOSED FOR PROTOTYPE]: environment props (burnable crates/cobwebs, puddles that freeze into ice, braziers,
## breakable urns/cracked walls). Pure sim: no rendering, no RNG. Props are optional room dressing, never required to win.
## Rooms without props never construct this object, so existing behaviour and golden traces are untouched.
const WaterTiles = preload("res://world/water_tiles.gd")
const Projectile = preload("res://magic/runtime/projectile_effect.gd")
const DATA_FILE := "res://world/data/env_props_v1.json"
const KIND_IDS := ["crate","cobweb","puddle","brazier","urn","cracked_wall"]
const VISUAL_KINDS := ["burst","field","beam"]

var kinds: Dictionary = {}
var difficulty: Dictionary = {}
var props: Array = []
## Coins released by broken props, not yet collected (the economy consumer is a later step).
var pending_coins := 0
## Append-only deterministic log: {tick, prop_id, kind, action}.
var events: Array = []
var _session_ref: WeakRef = null ## weak: the session owns this object, a strong ref would leak both

static func load_data() -> Dictionary:
	var parsed = JSON.parse_string(FileAccess.get_file_as_string(DATA_FILE))
	return parsed if typeof(parsed) == TYPE_DICTIONARY else {}

static func _num_array(value, size: int) -> bool:
	if typeof(value) != TYPE_ARRAY or value.size() != size:
		return false
	for v in value:
		if typeof(v) != TYPE_INT and typeof(v) != TYPE_FLOAT:
			return false
	return true

## Layout entries: {id, kind, rect:[x,y,w,h]} or {id, kind, position:[x,y]} (circle kinds; rect kinds may omit rect to use the kind size).
static func validate(entries, kind_table: Dictionary) -> Array:
	var issues: Array = []
	if typeof(entries) != TYPE_ARRAY:
		issues.append({"code":"ENV_PROP_INVALID","path":"env_props","message":"env_props must be an array"})
		return issues
	var seen: Dictionary = {}
	for i in entries.size():
		var path := "env_props[%d]" % i
		var entry = entries[i]
		if typeof(entry) != TYPE_DICTIONARY:
			issues.append({"code":"ENV_PROP_INVALID","path":path,"message":"entry must be an object"})
			continue
		var id := str(entry.get("id",""))
		if typeof(entry.get("id")) != TYPE_STRING or id.is_empty() or seen.has(id):
			issues.append({"code":"ENV_PROP_INVALID","path":path+".id","message":"id must be a unique non-empty string"})
		seen[id] = true
		var kind := str(entry.get("kind",""))
		if not KIND_IDS.has(kind) or not kind_table.has(kind):
			issues.append({"code":"ENV_PROP_INVALID","path":path+".kind","message":"unknown prop kind"})
			continue
		var shape := str(kind_table[kind].get("shape","rect"))
		if shape == "circle":
			if not _num_array(entry.get("position"),2):
				issues.append({"code":"ENV_PROP_INVALID","path":path+".position","message":"position must be [x,y] numbers"})
		elif entry.has("rect"):
			var dims = entry["rect"]
			if not _num_array(dims,4) or float(dims[2]) <= 0.0 or float(dims[3]) <= 0.0:
				issues.append({"code":"ENV_PROP_INVALID","path":path+".rect","message":"rect must be [x,y,w,h] numbers with w,h > 0"})
		elif _num_array(entry.get("position"),2):
			pass
		else:
			issues.append({"code":"ENV_PROP_INVALID","path":path+".rect","message":"rect [x,y,w,h] or position [x,y] required"})
	return issues

func _init(entries: Array = [], data: Dictionary = {}) -> void:
	kinds = data.get("kinds",{})
	difficulty = data.get("difficulty",{})
	for entry in entries:
		var kind := str(entry["kind"])
		var rule: Dictionary = kinds[kind]
		var prop := {"id":str(entry["id"]),"kind":kind,"state":"intact","timer":0,"rule":rule}
		if str(rule.get("shape","rect")) == "circle":
			prop["center"] = Vector2(float(entry["position"][0]),float(entry["position"][1]))
			prop["radius"] = float(rule["radius"])
			prop["rect"] = Rect2(prop["center"]-Vector2(prop["radius"],prop["radius"]),Vector2(prop["radius"],prop["radius"])*2.0)
		elif entry.has("rect"):
			var d: Array = entry["rect"]
			prop["rect"] = Rect2(float(d[0]),float(d[1]),float(d[2]),float(d[3]))
		else:
			var size: Array = rule["size"]
			var p: Array = entry["position"]
			prop["rect"] = Rect2(float(p[0])-float(size[0])/2.0,float(p[1])-float(size[1])/2.0,float(size[0]),float(size[1]))
		props.append(prop)

## Registers solid rects (walking / spells) and puddles (water). Call after set_water, if both are used.
func attach(session) -> void:
	_session_ref = weakref(session)
	var puddles: Array = []
	for prop in props:
		var rule: Dictionary = prop["rule"]
		if bool(rule.get("solid_walk",false)):
			session.world.walls.append(prop["rect"])
		if bool(rule.get("blocks_spells",false)):
			session.sim.collision_walls.append(prop["rect"])
		if prop["kind"] == "puddle":
			puddles.append(_puddle_entry(prop))
	if not puddles.is_empty():
		if session.water == null:
			session.water = WaterTiles.new([])
			session.sim.resolver.water = session.water
		session.water.add_entries(puddles)

func _puddle_entry(prop: Dictionary) -> Dictionary:
	var r: Rect2 = prop["rect"]
	return {"kind":str(prop["rule"].get("water_kind","shallow")),"rect":[r.position.x,r.position.y,r.size.x,r.size.y],
		"tag":"env_puddle_"+str(prop["id"])}

func _live(prop: Dictionary) -> bool:
	return prop["state"] != "destroyed"

func _scaled(value: int, key: String) -> int:
	return maxi(1,roundi(float(value)*float(difficulty.get(key,1.0))))

## Runs before sim.step: sweeps each live projectile's step against the props, in list order.
func pre_step(sim) -> void:
	var dt := 1.0/float(sim.clock.tick_rate)
	for entry in sim.active:
		if entry["kind"] != "projectile" or entry["effect"].expired:
			continue
		var effect = entry["effect"]
		var start: Vector2 = effect.position
		var finish: Vector2 = start+effect.direction*effect.speed*dt
		var essence := str(effect.root["essence"]["id"])
		for prop in props:
			if not _live(prop):
				continue
			if prop["kind"] == "brazier":
				if bool(prop["rule"].get("lit",false)) and not (prop["rule"].get("ignite_except",[]) as Array).has(essence) \
						and Projectile._segment_circle_time(start,finish,prop["center"],float(prop["radius"])+effect.radius) >= 0.0:
					entry["context"]["ignited"] = true
			elif Projectile.segment_wall_time(start,finish,prop["rect"],effect.radius) < 1.0 or prop["rect"].grow(effect.radius).has_point(start):
				_apply(prop,essence,sim.clock.tick+1)

## Runs after sim.step: burst/field/beam areas of this tick. Bursts are marked so they apply once.
func post_step(sim) -> void:
	var tick: int = sim.clock.tick
	for visual in sim.visuals:
		var kind := str(visual["kind"])
		if not VISUAL_KINDS.has(kind) or visual.has("env_seen"):
			continue
		if kind == "burst":
			visual["env_seen"] = true
		for prop in props:
			if not _live(prop):
				continue
			var touched := false
			if kind == "beam":
				touched = Projectile.segment_wall_time(visual["from"],visual["to"],prop["rect"],0.0) < 1.0
			else:
				touched = _circle_touches(visual["position"],float(visual["radius"]),prop)
			if touched and prop["kind"] != "brazier":
				_apply(prop,str(visual["essence"]),tick)

func _circle_touches(center: Vector2, radius: float, prop: Dictionary) -> bool:
	if prop.has("center"):
		return center.distance_to(prop["center"]) <= radius+float(prop["radius"])
	var r: Rect2 = prop["rect"]
	var closest := Vector2(clampf(center.x,r.position.x,r.end.x),clampf(center.y,r.position.y,r.end.y))
	return closest.distance_squared_to(center) < radius*radius

func _apply(prop: Dictionary, essence: String, tick: int) -> void:
	var rule: Dictionary = prop["rule"]
	var state: String = prop["state"]
	if (rule.get("ignite_by",[]) as Array).has(essence) and state == "intact":
		prop["state"] = "burning"
		prop["timer"] = tick+_scaled(int(rule["burn_ticks"]),"burn_ticks_scale")
		events.append({"tick":tick,"prop_id":prop["id"],"kind":prop["kind"],"action":"ignite"})
	elif (rule.get("freeze_by",[]) as Array).has(essence) and state == "intact" and _session() != null:
		prop["state"] = "frozen"
		prop["timer"] = tick+int(rule["ice_ticks"])
		if _session().water != null:
			_session().water.remove_tag("env_puddle_"+str(prop["id"]))
		events.append({"tick":tick,"prop_id":prop["id"],"kind":prop["kind"],"action":"freeze"})
	elif (rule.get("break_by",[]) as Array).has(essence) and state == "intact":
		_destroy(prop,tick,"break")

func _destroy(prop: Dictionary, tick: int, action: String) -> void:
	prop["state"] = "destroyed"
	var rule: Dictionary = prop["rule"]
	if _session() != null:
		_session().world.walls.erase(prop["rect"])
		_session().sim.collision_walls.erase(prop["rect"])
	var coins := roundi(float(int(rule.get("coins",0)))*float(difficulty.get("coin_scale",1.0)))
	pending_coins += coins
	events.append({"tick":tick,"prop_id":prop["id"],"kind":prop["kind"],"action":action,"coins":coins})

## Burn expiry and ice melting.
func step_timers(tick: int) -> void:
	for prop in props:
		if prop["state"] == "burning" and tick >= int(prop["timer"]):
			_destroy(prop,tick,"burn_out")
		elif prop["state"] == "frozen" and tick >= int(prop["timer"]):
			prop["state"] = "intact"
			if _session() != null and _session().water != null:
				_session().water.add_entries([_puddle_entry(prop)])
			events.append({"tick":tick,"prop_id":prop["id"],"kind":prop["kind"],"action":"thaw"})

func on_ice(pos: Vector2) -> bool:
	for prop in props:
		if prop["state"] == "frozen" and prop["rect"].has_point(pos):
			return true
	return false

func ice_grip() -> float:
	return float(kinds.get("ice",{}).get("enemy_grip",1.0))

## Read-only rendering view.
func view() -> Array:
	var result: Array = []
	for prop in props:
		result.append({"id":prop["id"],"kind":prop["kind"],"state":prop["state"],"rect":prop["rect"],
			"lit":prop["kind"] == "brazier" and bool(prop["rule"].get("lit",false))})
	return result

func snapshot() -> Dictionary:
	var states: Array = []
	for prop in props:
		states.append([prop["id"],prop["state"],int(prop["timer"])])
	return {"props":states,"pending_coins":pending_coins,"events":events.duplicate(true)}

func _session():
	return _session_ref.get_ref() if _session_ref != null else null
