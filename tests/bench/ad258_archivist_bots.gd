extends RefCounted
## AD-258 bench bots on the LIVE Drowned Archivist fight (world/data/run_v2.json cistern_boss, same setup as _live_bench in
## tests/test_ad_final_boss_v2.gd and tests/bench/boss_pacing_bench.gd). Deterministic: no RNG beyond the session seed.
## Policies: "average" walks into range, stands still and spams one skill (slot 2 lightning), never dashes;
## "skilled" reads the boss intent / hazards / shots, walks or dashes out of telegraphed areas, alternates water and
## lightning (AD-257 conduct combo), throws cold at the emerge pool (freeze stun) and keeps casting in punish windows.
## Both turn on the wisps while the wisp shield is up (the BenchHarness rule). Every player damage event is attributed to a
## threat and counted unavoidable when that threat's telegraph was visible for fewer than REACTION_TICKS before it landed.
## Usage: const Bots = preload("res://tests/bench/ad258_archivist_bots.gd"); Bots.run_all("skilled")
const Session = preload("res://combat/combat_session.gd")
const LIVE_FILE := "res://world/data/run_v2.json"
const AD258_SEEDS := [25801,25802,25803,25804,25805,25806,25807,25808,25809,25810]
const BUILD := 0
const MAX_TICKS := 15000
## 0.3 s at 60 ticks/s: the minimum telegraph a player can react to.
const REACTION_TICKS := 18
const KITE := 290.0
const LOOK := 8
const MARGIN := 8.0
const DASH_AT := 3
const SLOT_WATER := 1
const SLOT_LIGHTNING := 2
const SLOT_COLD := 3
const WATER_EVERY := 45

static var _cache := {}

static func _shot(essence: String) -> Dictionary:
	return {"schema_version":1,"formula_id":"ad258."+essence,"display_name":essence,
		"root":{"essence_id":essence,"manifestation_id":"form.projectile","modifier_ids":[],"params":{}}}

static func live_doc() -> Dictionary:
	return JSON.parse_string(FileAccess.get_file_as_string(LIVE_FILE))

## Runs (or returns the cached result of) one fight. Keys: won, died, seconds, unavoidable_damage_events (count) plus
## damage_log, telegraphs, tide_warns, gaps, starts, punish, flood_ticks, flood_overlap, max_phase.
static func run(policy: String, run_seed: int) -> Dictionary:
	var key := "%s:%d" % [policy,run_seed]
	if not _cache.has(key):
		_cache[key] = _fight(policy,run_seed)
	return _cache[key]

static func run_all(policy: String) -> Array:
	return AD258_SEEDS.map(func(run_seed): return run(policy,run_seed))

static func median(values: Array) -> float:
	if values.is_empty():
		return 0.0
	var sorted := values.duplicate()
	sorted.sort()
	var n := sorted.size()
	return float(sorted[n/2]) if n%2 == 1 else (float(sorted[n/2-1])+float(sorted[n/2]))/2.0

static func _fight(policy: String, run_seed: int) -> Dictionary:
	var doc := live_doc()
	var cfg: Dictionary = doc["bosses"]["cistern_boss"]
	var s = Session.new(run_seed,"empty",BUILD)
	s.defer_clear = true
	s.set_water(doc["room_templates"]["cistern_boss"]["layout"]["water"])
	var boss = s.spawn_boss(cfg,Vector2(float(cfg["position"][0]),float(cfg["position"][1])))
	s.sim.loadout.allow_edit = true
	s.sim.equip(SLOT_WATER,_shot("essence.water"))
	s.sim.equip(SLOT_LIGHTNING,_shot("essence.lightning"))
	s.sim.equip(SLOT_COLD,_shot("essence.cold"))
	var mem := {"intent":null,"intent_kind":"","intent_start":0,"intent_ticks":0,"intent_declared":0,"intent_phase":1,
		"starts_at":{},"shot_start":{},"enemy_start":{},"tide_start":-1,"tide_seen":{},"events_seen":0,
		"last_start":-1,"last_start_phase":0,"broken":false,"last_state":boss.state,"heading":Vector2.ZERO,"cold_intent":null,"water_at":-1000,
		"out":{"damage_log":[],"telegraphs":[],"tide_warns":[],"gaps":{1:[],2:[],3:[]},"starts":{1:0,2:0,3:0},
			"punish":{1:0,2:0,3:0},"flood_ticks":{1:0,2:0,3:0},"flood_overlap":{1:0,2:0,3:0},"max_phase":1,
			"phase_ticks":{1:0,2:0,3:0},"shielded_ticks":0}}
	for i in MAX_TICKS:
		if s.state != "playing" or not boss.target.alive():
			break
		_observe_threats(s,boss,mem)
		var command := _skilled(s,boss,mem,i) if policy == "skilled" else _average(s,boss)
		s.issue(command)
		s.step()
		_observe_after(s,boss,mem)
	_close_intent(boss,mem,true)
	var out: Dictionary = mem["out"]
	var unavoidable: Array = out["damage_log"].filter(func(e): return bool(e["unavoidable"]))
	out["won"] = not boss.target.alive()
	out["died"] = not s.sim.actor.alive()
	out["seconds"] = float(s.sim.clock.tick)/60.0
	out["unavoidable_damage_events"] = unavoidable.size()
	out["unavoidable"] = unavoidable
	out["seed"] = run_seed
	out["policy"] = policy
	out["player_hp"] = s.sim.actor.health.current
	out["boss_hp_fraction"] = boss.target.health.current/boss.target.health.maximum
	out["casts"] = s.player.casts
	out["dashes"] = s.player.dashes
	return out

## Wisp-shield harness rule: while shielded the player turns on the nearest live wisp.
static func _target_point(s, boss) -> Vector2:
	if boss.shielded:
		var best = null
		for e in s.enemies:
			if e.kind == "lantern_wisp" and e.target.alive() and (best == null or e.target.position.distance_to(s.sim.actor.position) < best.target.position.distance_to(s.sim.actor.position)):
				best = e
		if best != null:
			return best.target.position
	return boss.target.position

static func _aim(from: Vector2, to: Vector2) -> Vector2:
	var d := to-from
	return d.normalized() if not d.is_zero_approx() else Vector2.RIGHT

## Average: walk into range, then stand and spam the lightning slot. No dodge, no dash.
static func _average(s, boss) -> Dictionary:
	var actor: Vector2 = s.sim.actor.position
	var at := _target_point(s,boss)
	var move := Vector2.ZERO
	if actor.distance_to(at) > 240.0 or not s.world.clear_sight(actor,at,8):
		move = s.world.navigate_direction(actor,at,s.sim.actor.radius)
	return {"move":move,"aim":_aim(actor,at),"cursor":at,"cast":SLOT_LIGHTNING,"dash":false}

# ---- threat model (skilled policy) ----

static func _tide_spec(boss) -> Dictionary:
	for spec in boss.tuning["phases"][boss.phase-1].get("hazards",[]):
		if str(spec["type"]) == "tide_wave":
			return spec
	return {}

## Every telegraphed threat on screen this tick, in the form _hit_eta reads.
static func _context(s, boss) -> Dictionary:
	var ctx := {"slams":[],"storm_eta":-1,"tide":{},"rings":[],"shots":[],"pages":[],"r":s.sim.actor.radius,"water":s.water,"shock":not s.water_shock.is_empty()}
	if boss.state == "windup" and boss.intent != null:
		var snap: Dictionary = boss.intent.snapshot()
		var eta := int(snap["telegraph_ticks"])-int(boss.state_tick)
		match str(snap["kind"]):
			"emerge":
				ctx["slams"].append({"c":snap["landing"],"reach":float(snap["range"]),"eta":eta})
			"storm_pulse":
				ctx["slams"].append({"c":boss.target.position,"reach":float(boss.tuning["storm_pulse_radius"]),"eta":eta})
				ctx["storm_eta"] = eta
	var tide := _tide_spec(boss)
	for h in s.hazards:
		if str(h["kind"]) == "boss_tide_wave" and not tide.is_empty():
			var warn_rem := maxi(0,int(tide["warn_ticks"])-int(h["age"])) if bool(h.get("telegraph",false)) else 0
			ctx["tide"] = {"gap_x":float(h["gap_x"]),"half":float(h["gap_width"])*0.5,"y":float(h["y"]),"thick":float(h["thickness"]),
				"spd":float(tide["speed"])/60.0,"warn":warn_rem}
	for ring in boss._aftermath:
		if bool(ring["ring_open"]):
			ctx["rings"].append({"at":ring["at"],"radius":float(ring["per_tick"])*float(ring["age"]),"per":float(ring["per_tick"]),
				"half":float(ring["width"])*0.5,"max":float(ring["max_radius"])})
	for shot in s.enemy_shots:
		ctx["shots"].append({"p":shot["position"],"d":shot["direction"],"spd":float(shot["speed"])/60.0,"rad":float(shot["radius"])})
	for e in s.enemies:
		if e.kind == "book_page" and e.target.alive():
			ctx["pages"].append({"p":e.target.position,"rad":e.target.radius})
	return ctx

## Ticks until some visible threat hits a player standing at `p` (INF when none does).
static func _hit_eta(p: Vector2, ctx: Dictionary) -> float:
	var r: float = ctx["r"]
	var best := INF
	for slam in ctx["slams"]:
		if p.distance_to(slam["c"]) <= float(slam["reach"])+r+MARGIN:
			best = minf(best,float(slam["eta"]))
	var water = ctx["water"]
	if water != null:
		if int(ctx["storm_eta"]) >= 0 and water.in_water(p,r):
			best = minf(best,float(ctx["storm_eta"]))
		if bool(ctx["shock"]) and water.is_electrified(p):
			best = 0.0
	var tide: Dictionary = ctx["tide"]
	if not tide.is_empty() and absf(p.x-float(tide["gap_x"])) > float(tide["half"])-r-4.0 and p.y+r >= float(tide["y"]):
		var dist := maxf(0.0,(p.y-r)-(float(tide["y"])+float(tide["thick"])))
		best = minf(best,float(tide["warn"])+dist/float(tide["spd"]))
	for ring in ctx["rings"]:
		var d: float = p.distance_to(ring["at"])
		var edge: float = float(ring["half"])+r
		if d-edge > float(ring["max"]) or d < float(ring["radius"])-edge:
			continue
		best = minf(best,maxf(0.0,d-edge-float(ring["radius"]))/float(ring["per"]))
	for shot in ctx["shots"]:
		var rel: Vector2 = p-shot["p"]
		var along: float = rel.dot(shot["d"])
		var reach: float = float(shot["rad"])+r+MARGIN
		if along < -reach or absf((shot["d"] as Vector2).cross(rel)) > reach:
			continue
		var eta := maxf(0.0,along-reach)/float(shot["spd"])
		if eta <= 45.0:
			best = minf(best,eta)
	for page in ctx["pages"]:
		var gap: float = p.distance_to(page["p"])-float(page["rad"])-r
		if gap < 70.0:
			best = minf(best,maxf(0.0,gap)/2.0)
	return best

static func _cost(s, boss, ctx: Dictionary, p: Vector2, punish: bool) -> float:
	var cost := 0.0
	var eta := _hit_eta(p,ctx)
	if eta < INF:
		cost += 60.0/(1.0+eta)+(6.0 if eta <= LOOK else 0.0)
	var kite := 230.0 if punish else KITE
	cost += absf(p.distance_to(boss.target.position)-kite)/120.0
	if s.water != null and s.water.in_water(p,ctx["r"]):
		cost += 0.6
	var tide: Dictionary = ctx["tide"]
	if not tide.is_empty() and p.y+float(ctx["r"]) >= float(tide["y"]):
		cost += absf(p.x-float(tide["gap_x"]))/150.0
	return cost

## Skilled: pick the cheapest of 16 headings + standing still, dash on an imminent hit, alternate water / lightning.
static func _skilled(s, boss, mem: Dictionary, i: int) -> Dictionary:
	var actor: Vector2 = s.sim.actor.position
	var r: float = s.sim.actor.radius
	var ctx := _context(s,boss)
	var punish: bool = boss.staggered or boss.state == "recover"
	var step: float = float(s.data["player"]["move_speed"])/60.0
	var now_eta := _hit_eta(actor,ctx)
	if i%2 == 0 or now_eta <= float(LOOK):
		var best_dir := Vector2.ZERO
		var best_cost := _cost(s,boss,ctx,actor,punish)
		var tangent := _aim(boss.target.position,actor).rotated(PI/2.0)
		for k in 16:
			var dir := Vector2.RIGHT.rotated(TAU*float(k)/16.0)
			var p: Vector2 = s.world.move_body(actor,dir*step*LOOK,r)
			var c := _cost(s,boss,ctx,p,punish)-0.05*dir.dot(tangent)
			if c < best_cost-0.001:
				best_cost = c
				best_dir = dir
		mem["heading"] = best_dir
	var move: Vector2 = mem["heading"]
	var dash: bool = now_eta <= float(DASH_AT) and s.player.dash_cooldown == 0
	if dash and move.is_zero_approx():
		move = _aim(boss.target.position,actor).rotated(PI/2.0)
	# Target: a page closing in, else the boss (or a wisp while shielded).
	var at := _target_point(s,boss)
	for page in ctx["pages"]:
		if actor.distance_to(page["p"]) < 200.0:
			at = page["p"]
			break
	# AD-257 conduct combo: one water shot to Wet the target (re-sent at most every WATER_EVERY ticks), lightning otherwise.
	var tick: int = s.sim.clock.tick
	var slot := SLOT_LIGHTNING
	if not boss.target.status.has("wet",tick) and tick-int(mem["water_at"]) >= WATER_EVERY and _ready(s,SLOT_WATER):
		slot = SLOT_WATER
		mem["water_at"] = tick
	var aim_at := at
	# Freeze the emerge pool: a cold shot through the ripple stuns the boss when it surfaces.
	if boss.state == "windup" and boss.intent != null and str(boss.intent.snapshot()["kind"]) == "emerge" and mem["cold_intent"] != boss.intent:
		var landing: Vector2 = boss.intent.snapshot()["landing"]
		if actor.distance_to(landing) < 520.0 and _ready(s,SLOT_COLD):
			slot = SLOT_COLD
			aim_at = landing
			mem["cold_intent"] = boss.intent
	return {"move":move,"aim":_aim(actor,aim_at),"cursor":aim_at,"cast":slot,"dash":dash}

static func _ready(s, slot: int) -> bool:
	var plan = s.sim.loadout.get_plan(slot)
	return plan != null and int(s.sim.loadout.slots[slot]["cooldown"]) == 0 and s.sim.mana >= float(plan.snapshot()["mana_cost"])

# ---- recording ----

## Before the player acts: first-seen ticks of shots, minions and tide waves (what the player can see this tick).
static func _observe_threats(s, boss, mem: Dictionary) -> void:
	var tick: int = s.sim.clock.tick
	for shot in s.enemy_shots:
		var id := int(shot["attack_id"])
		if not mem["shot_start"].has(id):
			mem["shot_start"][id] = mini(tick,int(mem["starts_at"].get("water_bolt",tick)))
	for e in s.enemies:
		var id: int = e.target.id
		if id != boss.target.id and not mem["enemy_start"].has(id):
			mem["enemy_start"][id] = mini(tick,int(mem["starts_at"].get("page_throw",tick)) if e.kind == "book_page" else tick)
	for h in s.hazards:
		if str(h["kind"]) == "boss_tide_wave" and not mem["tide_seen"].has(int(h["id"])):
			mem["tide_seen"][int(h["id"])] = {"start":tick,"warn":0,"phase":boss.phase}
			mem["tide_start"] = tick
		if str(h["kind"]) == "boss_tide_wave" and bool(h.get("telegraph",false)):
			mem["tide_seen"][int(h["id"])]["warn"] = int(mem["tide_seen"][int(h["id"])]["warn"])+1

## `ended`: the fight stopped (player or boss died) while this windup was still running, so it was cut short, not shortened.
static func _close_intent(boss, mem: Dictionary, ended: bool = false) -> void:
	if mem["intent"] == null:
		return
	var interrupted: bool = (ended or boss.state in ["roar","stagger","dead"]) and int(mem["intent_ticks"]) < int(mem["intent_declared"])
	if not interrupted:
		mem["out"]["telegraphs"].append({"kind":mem["intent_kind"],"phase":mem["intent_phase"],"declared":mem["intent_declared"],"measured":mem["intent_ticks"]})
	mem["intent"] = null

## After the tick: windup starts/lengths, pattern gaps, punish windows, flood overlap and the damage events this tick.
static func _observe_after(s, boss, mem: Dictionary) -> void:
	var tick: int = s.sim.clock.tick
	var out: Dictionary = mem["out"]
	var phase: int = boss.phase
	out["max_phase"] = maxi(int(out["max_phase"]),phase)
	out["phase_ticks"][phase] = int(out["phase_ticks"][phase])+1
	if boss.shielded:
		out["shielded_ticks"] = int(out["shielded_ticks"])+1
	if boss.state in ["stagger","roar"]:
		mem["broken"] = true
	if boss.state == "stagger" and (mem["last_state"] != "stagger" or boss.state_tick == 0):
		out["punish"][phase] = int(out["punish"][phase])+1
	mem["last_state"] = boss.state
	var current = boss.intent if boss.state == "windup" else null
	if current != mem["intent"]:
		_close_intent(boss,mem)
		if current != null:
			var snap: Dictionary = current.snapshot()
			var kind := str(snap["kind"])
			mem["intent"] = current
			mem["intent_kind"] = kind
			mem["intent_start"] = tick
			mem["intent_ticks"] = 0
			mem["intent_declared"] = int(snap["telegraph_ticks"])
			mem["intent_phase"] = phase
			mem["starts_at"][kind] = tick
			if kind != "emerge":
				out["starts"][phase] = int(out["starts"][phase])+1
				if int(mem["last_start_phase"]) == phase and not bool(mem["broken"]):
					out["gaps"][phase].append(tick-int(mem["last_start"]))
				mem["last_start"] = tick
				mem["last_start_phase"] = phase
				mem["broken"] = false
	if mem["intent"] != null:
		mem["intent_ticks"] = int(mem["intent_ticks"])+1
	if boss.flood_age >= 0 and boss.target.alive():
		out["flood_ticks"][phase] = int(out["flood_ticks"][phase])+1
		var other: bool = not s.enemy_shots.is_empty() or not boss._aftermath.is_empty() or not s.water_shock.is_empty() \
			or s.hazards.any(func(h): return str(h["kind"]) == "boss_tide_wave")
		if boss.state == "windup" and boss.intent != null and not ["flood","wet_zone","summon_wisps"].has(str(boss.intent.snapshot()["kind"])):
			other = true
		if other:
			out["flood_overlap"][phase] = int(out["flood_overlap"][phase])+1
	for h in s.hazards:
		if str(h["kind"]) == "boss_tide_wave" and not bool(h.get("telegraph",false)):
			var seen: Dictionary = mem["tide_seen"].get(int(h["id"]),{})
			if not seen.is_empty() and not seen.has("logged"):
				seen["logged"] = true
				out["tide_warns"].append({"phase":seen["phase"],"warn":seen["warn"]})
	var events: Array = s.damage_events
	for index in range(int(mem["events_seen"]),events.size()):
		out["damage_log"].append(_attribute(events[index],boss,mem))
	mem["events_seen"] = events.size()

## Which threat dealt `ev` and how long its telegraph had been visible.
static func _attribute(ev: Dictionary, boss, mem: Dictionary) -> Dictionary:
	var tick := int(ev["tick"])
	var src := int(ev["source_id"])
	var channel := str(ev["channel"])
	var source := "unknown"
	var start := tick
	if mem["shot_start"].has(int(ev["attack_id"])):
		source = "shot"
		start = int(mem["shot_start"][int(ev["attack_id"])])
	elif src != boss.target.id:
		source = "minion"
		start = int(mem["enemy_start"].get(src,tick))
	elif channel == "water":
		source = "tide_wave"
		start = int(mem["tide_start"]) if int(mem["tide_start"]) >= 0 else tick
	elif channel == "lightning":
		source = "storm_pulse_or_shock"
		start = int(mem["starts_at"].get("storm_pulse",tick))
	else:
		# Physical boss hit: an emerge slam / splash ring, or water-bolt shots that spawned and hit within one tick.
		source = "emerge_slam_or_ring"
		start = int(mem["starts_at"].get("emerge",-1))
		var bolt := int(mem["starts_at"].get("water_bolt",-1))
		if bolt > start:
			source = "shot"
			start = bolt
		if start < 0:
			start = tick
	var warn := tick-start
	return {"tick":tick,"source":source,"channel":channel,"amount":float(ev.get("dealt",ev["amount"])),"warn_ticks":warn,
		"unavoidable":warn < REACTION_TICKS}
