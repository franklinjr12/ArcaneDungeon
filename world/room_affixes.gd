extends RefCounted
## AD-241 [PROPOSED FOR PROTOTYPE]: runtime for the room affixes dark / unstable / haunted (run_v2.json "room_affixes").
## Pure sim: tick-based, no RNG, no rendering. One instance per combat room; "none" rooms keep every hook a no-op.
const CONFIG := "res://world/data/run_v2.json"
## Cracked tile states; art (AD-251) hooks onto these exact tag names.
const TILE_STATES := ["idle","telegraph","collapse","pit"]
static var _config: Dictionary = {}

var id := "none"
var settings: Dictionary = {}
## Unstable: [{rect, state, stepped_tick, collapse_tick}] in layout order.
var tiles: Array = []
## Haunted: [{enemy, position, due, done}] for each wave wisp, in spawn order.
var wisps: Array = []
var events: Array = []

static func load_config() -> Dictionary:
	if _config.is_empty():
		var parsed = JSON.parse_string(FileAccess.get_file_as_string(CONFIG))
		if parsed is Dictionary and parsed.get("room_affixes") is Dictionary:
			_config = parsed["room_affixes"]
	return _config

## `room` is RoomTemplate.values (already validated).
func setup(room: Dictionary) -> void:
	id = str(room.get("room_affix","none"))
	var config := load_config()
	settings = config.get(id,{}) if config.get(id) is Dictionary else {}
	tiles.clear()
	wisps.clear()
	events.clear()
	if id == "unstable":
		var layout = room.get("layout",{})
		for dims in layout.get("cracked_tiles",[]) if layout is Dictionary else []:
			tiles.append({"rect":Rect2(float(dims[0]),float(dims[1]),float(dims[2]),float(dims[3])),"state":"idle","stepped_tick":-1,"collapse_tick":-1})

## Dark: light radius in world units around the player; 0 means unlimited (no darkness).
func light_radius() -> float:
	return float(settings.get("light_radius",0)) if id == "dark" else 0.0

## Haunted: called by the director for each wave spawn.
func track_spawn(enemy, kind: String, at: Vector2) -> void:
	if id == "haunted" and enemy != null and kind == str(settings.get("respawn_kind","lantern_wisp")):
		wisps.append({"enemy":enemy,"kind":kind,"position":at,"due":-1,"done":false})

## True while a dead wisp still owes its one respawn; the director holds the room clear until then.
func pending_respawn() -> bool:
	for entry in wisps:
		if not bool(entry["done"]) and not entry["enemy"].target.alive():
			return true
	return false

## Haunted: first death schedules the respawn respawn_delay_ticks later at the original spawn; respawned wisps are not tracked,
## so each wisp comes back at most once. Returns new log entries.
func step_haunted(session, now: int) -> Array:
	var out: Array = []
	for entry in wisps:
		if bool(entry["done"]) or entry["enemy"].target.alive():
			continue
		if int(entry["due"]) < 0:
			entry["due"] = now+int(settings.get("respawn_delay_ticks",90))
		if now < int(entry["due"]):
			continue
		entry["done"] = true
		# A blocked spawn point gives up rather than holding the clear forever.
		var spawned = session.spawn_enemy(str(entry["kind"]),entry["position"])
		out.append({"event":"haunted_respawn","kind":str(entry["kind"]),"tick":now,"ok":spawned != null})
	return out

## Unstable: per tick, from CombatSession.step. idle -> telegraph when the player body first overlaps the tile;
## collapse exactly collapse_delay_ticks after that step (becomes a ground blocker); pit after collapse_anim_ticks.
func step(session) -> void:
	if id != "unstable":
		return
	var tick: int = session.sim.clock.tick
	var delay := int(settings.get("collapse_delay_ticks",120))
	var anim := int(settings.get("collapse_anim_ticks",20))
	var actor = session.sim.actor
	for index in tiles.size():
		var tile: Dictionary = tiles[index]
		var rect: Rect2 = tile["rect"]
		match str(tile["state"]):
			"idle":
				if actor.alive() and _overlaps(rect,actor.position,actor.radius):
					tile["state"] = "telegraph"
					tile["stepped_tick"] = tick
					events.append({"event":"tile_telegraph","index":index,"tick":tick})
			"telegraph":
				if tick-int(tile["stepped_tick"]) >= delay:
					tile["state"] = "collapse"
					tile["collapse_tick"] = tick
					session.world.add_ground_blockers([rect])
					events.append({"event":"tile_collapse","index":index,"tick":tick})
					_evict(session,rect)
			"collapse":
				if tick-int(tile["collapse_tick"]) >= anim:
					tile["state"] = "pit"

## AD-202 pits have no fall/damage rule, so a body caught on a collapsing tile is pushed to the nearest open spot, no damage.
func _evict(session, rect: Rect2) -> void:
	var bodies: Array = [session.sim.actor]
	for enemy in session.enemies:
		if enemy.target.alive():
			bodies.append(enemy.target)
	for body in bodies:
		if _overlaps(rect,body.position,body.radius):
			body.position = nearest_open(session.world,rect,body.position,body.radius)

## Nearest valid point just outside `rect` (straight out of each edge, then a widening ring); stays put if none fits.
static func nearest_open(world, rect: Rect2, from: Vector2, radius: float) -> Vector2:
	var pad := radius+1.0
	var best := from
	var best_distance := INF
	for ring in 12:
		var grow := pad+float(ring)*20.0
		var outer := rect.grow(grow)
		var candidates: Array = [Vector2(outer.position.x,from.y),Vector2(outer.end.x,from.y),Vector2(from.x,outer.position.y),Vector2(from.x,outer.end.y),
			outer.position,Vector2(outer.end.x,outer.position.y),Vector2(outer.position.x,outer.end.y),outer.end]
		for candidate in candidates:
			var distance: float = candidate.distance_squared_to(from)
			if distance < best_distance and world.valid_position(candidate,radius):
				best = candidate
				best_distance = distance
		if best_distance < INF:
			return best
	return best

static func _overlaps(rect: Rect2, at: Vector2, radius: float) -> bool:
	var nearest := Vector2(clampf(at.x,rect.position.x,rect.end.x),clampf(at.y,rect.position.y,rect.end.y))
	return nearest.distance_squared_to(at) < radius*radius

## Read-only for rendering: [{rect, state, age}] where age counts ticks in the current state.
func tile_view(tick: int) -> Array:
	var view: Array = []
	for tile in tiles:
		var since := int(tile["collapse_tick"]) if str(tile["state"]) in ["collapse","pit"] else int(tile["stepped_tick"])
		view.append({"rect":tile["rect"],"state":str(tile["state"]),"age":tick-since if since >= 0 else 0})
	return view
