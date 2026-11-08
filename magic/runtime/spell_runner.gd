extends RefCounted
## M1 deterministic sandbox simulation (TASK-011–025). Only data-driven generic spells.
const Difficulty = preload("res://game/core/difficulty.gd")
const Clock = preload("res://game/core/simulation_clock.gd")
const Registry = preload("res://magic/data/rune_registry.gd")
const Limits = preload("res://magic/runtime/spell_limits.gd")
const Queue = preload("res://magic/runtime/magic_event_queue.gd")
const Trace = preload("res://magic/runtime/indexed_trace.gd")
const Target = preload("res://combat/magic_target.gd")
const Store = preload("res://combat/target_store.gd")
const Resolver = preload("res://combat/interaction_resolver.gd")
const HitPayload = preload("res://combat/hit_payload.gd")
const Projectile = preload("res://magic/runtime/projectile_effect.gd")
const Burst = preload("res://magic/runtime/burst_effect.gd")
const Orb = preload("res://magic/runtime/orb_effect.gd")
const Beam = preload("res://magic/runtime/beam_effect.gd")
const Field = preload("res://magic/runtime/field_effect.gd")
const Compiler = preload("res://magic/compile/spell_compiler.gd")
const Loadout = preload("res://magic/runtime/spell_loadout.gd")
const CONFIG := "res://magic/data/magic_balance_v1.json"
## Test-only path override (TestContext.with_frozen_balance); empty means CONFIG.
static var config_override := ""

var clock
var registry
var limits
var queue
var trace
var targets
var resolver
var loadout
var actor
var settings: Dictionary = {}
var bounds := Rect2(0.0,0.0,920.0,680.0)
var collision_walls: Array = []
var mana := 0.0
var active: Array = []
var visuals: Array = []
var recent_damage: Array = []
var _deferred_burst_cleanup: Array = []
var _contexts: Dictionary = {}
var _chain_seen: Dictionary = {}
var last_rejection := ""
var total_hit_count := 0
var run_seed_value := 12345
var initialized := false
## AD-143: target ids whose death already ran the on-kill artifact hooks (once per target).
var _kill_seen: Dictionary = {}
const ARTIFACT_COLD_ESSENCE := "essence.cold"
## AD-143: held artifacts (world/artifacts.gd instance) or null; null keeps behaviour unchanged.
var artifacts = null:
	set(value):
		artifacts = value
		if resolver != null:
			resolver.artifacts = value

func _init(run_seed: int = 12345, record_trace: bool = true) -> void:
	var data := FileAccess.open(config_override if not config_override.is_empty() else CONFIG,FileAccess.READ)
	if data == null:
		printerr("M1 balance configuration unavailable")
		return
	var parsed = JSON.parse_string(data.get_as_text())
	if typeof(parsed) != TYPE_DICTIONARY or parsed.get("schema_version") != 1:
		printerr("Invalid M1 balance configuration")
		return
	settings = parsed
	if Difficulty.mult("player_mana") != 1.0:
		settings["combat"]["player_max_mana"] = Difficulty.scale_f(float(settings["combat"]["player_max_mana"]),"player_mana")
	registry = Registry.new()
	if not registry.load_seed()["ok"]:
		printerr("Could not load rune registry")
		return
	limits = Limits.new()
	if not limits.load_defaults()["ok"]:
		printerr("Could not load budget limits")
		return
	trace = Trace.new(record_trace)
	run_seed_value = run_seed
	initialized = true
	reset(run_seed)

func reset(run_seed: int = -1) -> void:
	if not initialized:
		return
	if run_seed >= 0:
		run_seed_value = run_seed
	clock = Clock.new(run_seed_value)
	trace.clear()
	queue = Queue.new(clock,limits,trace)
	targets = Store.new()
	resolver = Resolver.new(settings)
	resolver.artifacts = artifacts
	loadout = Loadout.new(registry,registry.get_ids(),limits.get_limit("max_complexity"))
	actor = Target.new(clock.next_id("target"),int(settings["combat"]["player_team"]),Vector2(140,340),100.0)
	targets.add(actor)
	bounds = Rect2(Vector2.ZERO,Vector2(float(settings["sandbox"]["width"]),float(settings["sandbox"]["height"])))
	mana = float(settings["combat"]["player_max_mana"])
	active.clear()
	visuals.clear()
	recent_damage.clear()
	_deferred_burst_cleanup.clear()
	_contexts.clear()
	_chain_seen.clear()
	_kill_seen.clear()
	collision_walls.clear()
	last_rejection = ""
	total_hit_count = 0

func add_target(where: Vector2, motion: Vector2 = Vector2.ZERO, hp: float = -1.0):
	var t = Target.new(clock.next_id("target"),int(settings["combat"]["enemy_team"]),where,
		float(settings["combat"]["base_target_hp"]) if hp <= 0 else hp)
	t.motion = motion
	t.tags = ["dummy"] if motion.is_zero_approx() else ["dummy","moving"]
	targets.add(t)
	return t

func fill_targets() -> void:
	for point in [Vector2(365,255),Vector2(505,255),Vector2(650,255),Vector2(365,420),Vector2(505,420),Vector2(650,420)]:
		add_target(point)
	add_target(Vector2(775,335),Vector2(0,75))

func equip(slot: int, formula: Dictionary) -> Dictionary:
	return loadout.equip(slot,formula)

func equip_builtin(slot: int, definition: Dictionary) -> Dictionary:
	return loadout.equip_builtin(slot,definition)

func equip_starter_loadout(presets: Array) -> Dictionary:
	if not loadout.is_locked(0):
		var installed: Dictionary = loadout.install_locked_builtin(0,Compiler.load_builtin_definition()["definition"])
		if not installed["ok"]:
			return installed
	for i in presets.size():
		var equipped: Dictionary = loadout.equip(i+1,presets[i])
		if not equipped["ok"]:
			return equipped
	for index in range(presets.size()+1,loadout.slots.size()):
		var cleared: Dictionary = loadout.clear(index)
		if not cleared["ok"]:
			return cleared
	return {"ok":true}

func try_cast(slot: int, origin: Vector2, direction: Vector2, target_point = null) -> Dictionary:
	var cast_id: int = clock.next_id("cast")
	var formula_id := ""
	if slot >= 0 and slot < loadout.slots.size():
		formula_id = str(loadout.slots[slot]["formula_id"])
	var ctx := {"cast_id":cast_id,"root_cast_id":cast_id,"formula_id":formula_id,"tick":clock.tick}
	trace.record("cast_requested",ctx)
	if direction.is_zero_approx():
		return _reject(ctx,"AIM_INVALID")
	if not actor.alive():
		return _reject(ctx,"CASTER_DEAD")
	var reason: String = loadout.check_slot(slot)
	if reason != "READY":
		return _reject(ctx,reason)
	var compiled = loadout.get_plan(slot)
	var plan: Dictionary = compiled.snapshot()
	if int(plan["complexity"]) > limits.get_limit("max_complexity"):
		return _reject(ctx,"COMPLEXITY_EXCEEDED")
	var cost := float(plan["mana_cost"])
	var free_cast := _art("momentum_rune") and int(artifacts.state.get("momentum",0)) > 0
	if free_cast:
		cost = 0.0
	if mana + 0.00001 < cost:
		return _reject(ctx,"INSUFFICIENT_MANA")
	var kind := str(plan["root"]["manifestation"]["id"])
	if kind == "form.orb" and _active_orb_count() >= limits.get_limit("max_active_orbs"):
		return _reject(ctx,"ORB_BUDGET_EXCEEDED")
	if kind == "form.beam" and _active_count("beam") >= limits.get_limit("max_active_beams"):
		return _reject(ctx,"BEAM_BUDGET_EXCEEDED")
	if kind == "form.field" and _active_count("field") >= limits.get_limit("max_active_fields"):
		return _reject(ctx,"FIELD_BUDGET_EXCEEDED")
	var duration := 1
	if kind == "form.projectile" or kind == "form.orb" or kind == "form.beam":
		duration = int(plan["root"]["params"]["lifetime_ticks"])
	elif kind == "form.field":
		duration = int(plan["root"]["params"]["field_duration_ticks"])
	if not queue.reserve_effect(cast_id,duration,cast_id,formula_id):
		return _reject(ctx,"EFFECT_BUDGET_EXCEEDED")
	mana = maxf(0.0,mana-cost)
	if free_cast:
		artifacts.state["momentum"] = int(artifacts.state["momentum"])-1
	loadout.slots[slot]["cooldown"] = int(plan["cooldown_ticks"])
	trace.record("cost_paid",{"cast_id":cast_id,"root_cast_id":cast_id,"formula_id":formula_id,"amount":int(cost),"tick":clock.tick})
	var base := {"cast_id":cast_id,"root_cast_id":cast_id,"caster_id":actor.id,"team":actor.team,
		"formula_id":formula_id,"parent_effect_id":0,"depth":0}
	_spawn_root(plan,origin,direction.normalized(),base,target_point)
	if _art("echo_chamber"):
		_echo_cast(slot,plan,kind,origin,direction.normalized(),formula_id,target_point)
	return {"accepted":true,"reason":"CAST","cast_id":cast_id}

## AD-143: cheap guard; every artifact hook starts here so a null/empty holder changes nothing.
func _art(id: String) -> bool:
	return artifacts != null and artifacts.has(id)

## AD-143 Momentum Rune: a dash arms the next free_casts casts at zero mana.
func artifact_dash() -> void:
	if _art("momentum_rune"):
		artifacts.state["momentum"] = int(artifacts.param("momentum_rune","free_casts",1))

## AD-143 on-kill hooks (Shatterheart, Ember Heart); runs before the dead target's status is cleared.
## `ctx` is the killing hit's context or the DOT's status source. Blasts it spawns carry `artifact_kill`, so they never recurse.
func _on_target_died(target, ctx: Dictionary) -> void:
	if artifacts == null or artifacts.is_empty() or _kill_seen.has(target.id) or bool(ctx.get("artifact_kill",false)):
		return
	_kill_seen[target.id] = true
	var base := {"cast_id":int(ctx.get("cast_id",0)),"root_cast_id":int(ctx.get("root_cast_id",0)),"formula_id":str(ctx.get("formula_id","")),
		"caster_id":actor.id,"team":actor.team,"parent_effect_id":0,"depth":1,"artifact_kill":true}
	if int(base["cast_id"]) == 0:
		base["cast_id"] = clock.next_id("cast")
		base["root_cast_id"] = base["cast_id"]
	if _art("shatterheart") and target.status.has("frozen",clock.tick):
		trace.record("artifact",{"cast_id":base["cast_id"],"root_cast_id":base["root_cast_id"],"formula_id":base["formula_id"],
			"target_id":target.id,"reason":"artifact.shatterheart","tick":clock.tick})
		var blast := {"essence":{"id":ARTIFACT_COLD_ESSENCE},"modifiers":[],"params":{
			"burst_radius":float(artifacts.param("shatterheart","radius",70)),
			"base_damage":float(artifacts.param("shatterheart","damage",12))}}
		_spawn_burst(blast,target.position,base)
	if _art("ember_heart") and target.status.has("burning",clock.tick):
		var near: Array = targets.query(target.position,float(artifacts.param("ember_heart","radius",110)),actor.team,[target.id],"",clock.tick)
		if not near.is_empty():
			var neighbour = near[0]
			neighbour.status.apply("burning",clock.tick,settings["statuses"]["burning"],
				{"cast_id":base["cast_id"],"root_cast_id":base["root_cast_id"],"formula_id":base["formula_id"],"team":actor.team})
			trace.record("status",{"cast_id":base["cast_id"],"root_cast_id":base["root_cast_id"],"formula_id":base["formula_id"],
				"target_id":neighbour.id,"reason":"burning:applied","tick":clock.tick})

## AD-143 Archivist's Quill: counts the `threshold` fractions of max HP a boss/mini-boss has lost; true when a new step was crossed.
func _quill_crossed(target) -> bool:
	if not _art("archivists_quill") or not ("boss" in target.tags or "mini_boss" in target.tags):
		return false
	var step_size: float = float(target.health.maximum)*float(artifacts.param("archivists_quill","threshold",0.25))
	if step_size <= 0.0:
		return false
	var steps: int = floori((float(target.health.maximum)-float(target.health.current))/step_size+0.000001)
	var seen: Dictionary = artifacts.state.get("quill",{})
	artifacts.state["quill"] = seen
	if steps <= int(seen.get(target.id,0)):
		return false
	seen[target.id] = steps
	return true

## AD-143 Tidewalker's Boots: called each dash tick (after the move) to drop a trail point at the caster.
func artifact_dash_step() -> void:
	if not _art("tidewalkers_boots"):
		return
	var trail: Array = artifacts.state.get("trail",[])
	artifacts.state["trail"] = trail
	var life := int(artifacts.param("tidewalkers_boots","trail_ticks",90))
	trail.append({"position":actor.position,"expires":clock.tick+life,"wet":{}})
	visuals.append({"kind":"wet_trail","position":actor.position,"radius":float(artifacts.param("tidewalkers_boots","trail_radius",28)),
		"essence":"essence.water","until":clock.tick+life})

## Live trail points make eligible enemies Wet, at most once per target per point. Expired points drop out.
func _advance_trail() -> void:
	var trail: Array = artifacts.state.get("trail",[])
	var radius := float(artifacts.param("tidewalkers_boots","trail_radius",28))
	var wet: Dictionary = settings["statuses"]["wet"].duplicate()
	wet["duration_ticks"] = int(artifacts.param("tidewalkers_boots","wet_duration_ticks",180))
	for point in trail.duplicate():
		if int(point["expires"]) <= clock.tick:
			trail.erase(point)
			continue
		for target in targets.query(point["position"],radius,actor.team,point["wet"].keys(),"",clock.tick):
			point["wet"][target.id] = true
			target.status.apply("wet",clock.tick,wet,{"team":actor.team})
			trace.record("status",{"target_id":target.id,"reason":"wet:applied","tick":clock.tick})

## AD-143 Echo Chamber: every `every`-th accepted cast per slot repeats once, free, at damage_scale.
## The echo is a new cast (own cast_id and reservation) spawned after the original, never from a callback.
func _echo_cast(slot: int, plan: Dictionary, kind: String, origin: Vector2, aim: Vector2, formula_id: String, target_point) -> void:
	var counts: Dictionary = artifacts.state.get("echo_counts",{})
	artifacts.state["echo_counts"] = counts
	counts[slot] = int(counts.get(slot,0))+1
	if counts[slot] % maxi(1,int(artifacts.param("echo_chamber","every",5))) != 0:
		return
	if (kind == "form.orb" and _active_orb_count() >= limits.get_limit("max_active_orbs")) \
			or (kind == "form.beam" and _active_count("beam") >= limits.get_limit("max_active_beams")) \
			or (kind == "form.field" and _active_count("field") >= limits.get_limit("max_active_fields")):
		return
	var echo_id: int = clock.next_id("cast")
	if not queue.reserve_effect(echo_id,_plan_duration(plan,kind),echo_id,formula_id):
		return
	var echo_plan: Dictionary = plan.duplicate(true)
	var params: Dictionary = echo_plan["root"]["params"]
	params["base_damage"] = float(params["base_damage"])*float(artifacts.param("echo_chamber","damage_scale",0.5))
	var context := {"cast_id":echo_id,"root_cast_id":echo_id,"caster_id":actor.id,"team":actor.team,
		"formula_id":formula_id,"parent_effect_id":0,"depth":0}
	trace.record("artifact",{"cast_id":echo_id,"root_cast_id":echo_id,"formula_id":formula_id,
		"reason":"artifact.echo_chamber","tick":clock.tick})
	_spawn_root(echo_plan,origin,aim,context,target_point)

func _plan_duration(plan: Dictionary, kind: String) -> int:
	if kind == "form.projectile" or kind == "form.orb" or kind == "form.beam":
		return int(plan["root"]["params"]["lifetime_ticks"])
	if kind == "form.field":
		return int(plan["root"]["params"]["field_duration_ticks"])
	return 1

func _reject(ctx: Dictionary, reason: String) -> Dictionary:
	last_rejection = reason
	var data := ctx.duplicate()
	data["reason"] = reason
	trace.record("rejected",data)
	const REJECT_EVENT := {"SLOT_EMPTY":"empty_slot","INSUFFICIENT_MANA":"no_mana","COOLDOWN":"cooldown"}
	if REJECT_EVENT.has(reason):
		var rejected := ctx.duplicate()
		rejected["reason"] = REJECT_EVENT[reason]
		trace.record("cast_rejected",rejected)
	return {"accepted":false,"reason":reason,"cast_id":int(ctx["cast_id"])}

func _spawn_root(plan: Dictionary, origin: Vector2, aim: Vector2, context: Dictionary, target_point = null) -> void:
	var root: Dictionary = plan["root"]
	var ids: Array = _modifier_ids(root)
	var kind := str(root["manifestation"]["id"])
	if kind == "form.projectile":
		var count := int(root["params"].get("projectile_count",1)) if "mod.split" in ids else 1
		if "mod.split" in ids and _art("split_prism"):
			count += int(artifacts.param("split_prism","extra_projectiles",1))
		var spread := deg_to_rad(float(root["params"].get("spread_degrees",0))) if count > 1 else 0.0
		for index in count:
			var offset := (float(index)-(float(count)-1.0)/2.0)*spread
			if index > 0 and not queue.reserve_effect(int(context["root_cast_id"]),int(root["params"]["lifetime_ticks"]),
					int(context["cast_id"]),str(context["formula_id"])):
				continue
			var spec: Dictionary = context.duplicate()
			spec["effect_id"] = clock.next_id("effect")
			spec["position"] = origin
			spec["direction"] = aim.rotated(offset)
			spec["root"] = root
			spec["on_hit"] = plan["on_hit"]
			spec["max_targets"] = int(root["params"].get("max_targets",1)) if "mod.pierce" in ids else 1
			if _art("rebound_sigil"):
				spec["bounces_left"] = int(artifacts.param("rebound_sigil","bounces",1))
			var projectile = Projectile.new(spec)
			active.append(_entry("projectile",projectile,context,plan["on_hit"]))
			_trace_spawn(context,int(spec["effect_id"]),origin)
	elif kind == "form.burst":
		_spawn_burst(root,origin,context,true,plan["on_hit"])
	elif kind == "form.orb":
		var spec: Dictionary = context.duplicate()
		spec["effect_id"] = clock.next_id("effect")
		spec["root"] = root
		var orb = Orb.new(spec)
		active.append(_entry("orb",orb,context,plan["on_hit"]))
		_trace_spawn(context,orb.id,origin)
	elif kind == "form.beam":
		var spec: Dictionary = context.duplicate()
		spec["effect_id"] = clock.next_id("effect")
		spec["root"] = root
		spec["position"] = origin
		spec["direction"] = aim
		var beam = Beam.new(spec)
		active.append(_entry("beam",beam,context,plan["on_hit"]))
		_trace_spawn(context,beam.id,origin)
	elif kind == "form.field":
		var spec: Dictionary = context.duplicate()
		spec["effect_id"] = clock.next_id("effect")
		spec["root"] = root
		spec["position"] = _field_center(root["params"],origin,aim,target_point)
		var field = Field.new(spec)
		active.append(_entry("field",field,context,plan["on_hit"]))
		_trace_spawn(context,field.id,field.position)
	else:
		queue.release_effect()

## Root effect record; the trigger plan rides along so On Kill / On Expire / Timer need no lookup later.
func _entry(kind: String, effect, context: Dictionary, trigger: Dictionary) -> Dictionary:
	var entry := {"kind":kind,"effect":effect,"context":context.duplicate(),"trigger":trigger}
	if _trigger_id(trigger) == "trigger.timer":
		entry["timer_next"] = clock.tick+int(trigger["trigger_params"]["interval_ticks"])
	return entry

static func _trigger_id(trigger: Dictionary) -> String:
	return str(trigger["trigger"]["id"]) if not trigger.is_empty() else ""

## Field centre: target point (or aim * range) limited to cast_range, then stopped at the first wall and kept inside bounds.
func _field_center(params: Dictionary, origin: Vector2, aim: Vector2, target_point) -> Vector2:
	var reach := float(params["cast_range"])
	var offset: Vector2 = aim*reach
	if typeof(target_point) == TYPE_VECTOR2:
		offset = target_point-origin
		if offset.length() > reach:
			offset = offset.normalized()*reach
	var center := origin+offset
	var along := 1.0
	for wall in collision_walls:
		along = minf(along,Projectile.segment_wall_time(origin,center,wall,0.0))
	center = origin.lerp(center,along)
	return Vector2(clampf(center.x,bounds.position.x,bounds.end.x),clampf(center.y,bounds.position.y,bounds.end.y))

func _spawn_burst(effect_plan: Dictionary, origin: Vector2, context: Dictionary, already_reserved: bool = false, attached_trigger: Dictionary = {}) -> bool:
	if not already_reserved and not queue.reserve_effect(int(context["root_cast_id"]),1,
			int(context["cast_id"]),str(context["formula_id"])):
		return false
	var effect_id: int = clock.next_id("effect")
	_trace_spawn(context,effect_id,origin)
	var radius: float = float(effect_plan["params"]["burst_radius"])
	visuals.append({"kind":"burst","position":origin,"radius":radius,"essence":str(effect_plan["essence"]["id"]),"until":clock.tick+int(settings["sandbox"]["visual_ticks"])})
	for hit in Burst.contacts(origin,radius,int(context["team"]),targets):
		_queue_hit(effect_plan,int(hit["target_id"]),hit["position"],context,effect_id,attached_trigger if _trigger_id(attached_trigger) == "trigger.on_kill" else {})
	if already_reserved and int(context["depth"]) == 0 and _art("residue_crystal"):
		_spawn_residue(effect_plan,origin,context)
	# Hold the effect reservation until queued contacts finish resolving.
	# Releasing here would let same-tick trigger bursts bypass global active limits.
	_deferred_burst_cleanup.append({"effect_id":effect_id,"context":context.duplicate()})
	return true

## AD-143 Residue Crystal: a root Burst leaves a short Field of its essence. Skipped silently over budget.
func _spawn_residue(burst_plan: Dictionary, origin: Vector2, context: Dictionary) -> void:
	if _active_count("field") >= limits.get_limit("max_active_fields"):
		return
	var duration := int(artifacts.param("residue_crystal","duration_ticks",120))
	if not queue.reserve_effect(int(context["root_cast_id"]),duration,int(context["cast_id"]),str(context["formula_id"])):
		return
	var root := {"essence":burst_plan["essence"].duplicate(true),"manifestation":{"id":"form.field"},"modifiers":[],
		"params":{"field_radius":float(artifacts.param("residue_crystal","field_radius",48)),
			"field_duration_ticks":duration,
			"tick_interval_ticks":int(artifacts.param("residue_crystal","pulse_interval_ticks",30)),
			"cast_range":0.0,
			"base_damage":float(artifacts.param("residue_crystal","damage_per_pulse",2))}}
	var spec: Dictionary = context.duplicate()
	spec["effect_id"] = clock.next_id("effect")
	spec["root"] = root
	spec["position"] = origin
	var field = Field.new(spec)
	active.append(_entry("field",field,context,{}))
	_trace_spawn(context,field.id,origin)

func _trace_spawn(ctx: Dictionary, effect_id: int, at: Vector2) -> void:
	trace.record("spawn",{"cast_id":ctx["cast_id"],"root_cast_id":ctx["root_cast_id"],
		"formula_id":ctx["formula_id"],"parent_effect_id":ctx["parent_effect_id"],
		"effect_id":effect_id,"depth":ctx["depth"],"position":at,"tick":clock.tick})

func _queue_hit(root: Dictionary, target_id: int, location: Vector2, ctx: Dictionary, effect_id: int, attached_trigger: Dictionary, chained: bool = false) -> void:
	var fields: Dictionary = {"type":"hit","cast_id":ctx["cast_id"],"root_cast_id":ctx["root_cast_id"],
		"formula_id":ctx["formula_id"],"parent_effect_id":effect_id,"source_id":ctx["caster_id"],
		"target_id":target_id,"position":location,"depth":ctx["depth"]}
	var event_id: int = queue.push_id(fields)
	if event_id >= 0:
		_contexts[event_id] = {"plan":root,"context":ctx.duplicate(),
			"on_hit":attached_trigger,"effect_id":effect_id,"location":location,"chained":chained}
		if not chained and _has_modifier(root,"mod.chain"):
			var seen: Dictionary = _chain_seen.get(int(ctx["root_cast_id"]),{})
			seen[target_id] = true
			_chain_seen[int(ctx["root_cast_id"])] = seen

func step() -> void:
	if clock.paused:
		return
	advance_one_tick()

func advance_one_tick() -> void:
	clock.step_once()
	loadout.cooldown_tick()
	mana = minf(float(settings["combat"]["player_max_mana"]),mana+float(settings["combat"]["regen_mana_per_tick"]))
	targets.advance_movers(1.0/float(clock.tick_rate),bounds)
	_advance_knockback()
	if _art("tidewalkers_boots"):
		_advance_trail()
	# Every source effect is moved once; callback work stays queued until the movement pass is complete.
	for entry in active.duplicate():
		var effect = entry["effect"]
		var hits: Array = []
		if entry["kind"] == "projectile":
			if effect.homing:
				effect.steer(1.0/float(clock.tick_rate),targets,effect.root["params"])
			hits = effect.advance(1.0/float(clock.tick_rate),targets,bounds,collision_walls)
		elif entry["kind"] == "orb":
			hits = effect.advance(1.0/float(clock.tick_rate),clock.tick,actor,targets,
				limits.get_limit("min_rehit_delay_ticks"))
		elif entry["kind"] == "beam":
			var pulse: Dictionary = effect.advance(clock.tick,actor,targets,bounds,collision_walls,
				limits.get_limit("max_targets_per_pulse"))
			hits = _charge_pulse(entry,pulse)
			visuals.append({"kind":"beam","from":actor.position,"to":effect.end_point,
				"essence":str(effect.root["essence"]["id"]),"until":clock.tick+1})
		elif entry["kind"] == "field":
			hits = _charge_pulse(entry,effect.advance(clock.tick,targets,limits.get_limit("max_targets_per_pulse")))
			if not effect.expired:
				visuals.append({"kind":"field","position":effect.position,"radius":effect.radius,
					"essence":str(effect.root["essence"]["id"]),"until":clock.tick+1})
		var trigger_id := _trigger_id(entry["trigger"])
		var hit_trigger: Dictionary = {}
		if trigger_id == "trigger.on_kill":
			hit_trigger = entry["trigger"]
		elif trigger_id == "trigger.on_hit" and entry["kind"] == "projectile":
			hit_trigger = effect.on_hit
		for hit in hits:
			_queue_hit(effect.root,int(hit["target_id"]),hit["position"],entry["context"],effect.id,hit_trigger)
			if entry["kind"] == "orb" and _art("gravity_lens"):
				_gravity_pull(int(hit["target_id"]))
		if not effect.expired and trigger_id == "trigger.timer" and clock.tick >= int(entry["timer_next"]):
			_fire_trigger(entry["trigger"],entry["context"],effect.id,0,_trigger_location(entry))
			entry["timer_next"] = int(entry["timer_next"])+int(entry["trigger"]["trigger_params"]["interval_ticks"])
		if effect.expired:
			active.erase(entry)
			queue.release_effect()
			if trigger_id == "trigger.on_expire":
				_fire_trigger(entry["trigger"],entry["context"],effect.id,0,_trigger_location(entry))
			var cleaned := {"cast_id":entry["context"]["cast_id"],"root_cast_id":entry["context"]["root_cast_id"],
				"formula_id":entry["context"]["formula_id"],"effect_id":effect.id,"tick":clock.tick}
			if entry["kind"] == "beam":
				cleaned["reason"] = effect.end_reason
			trace.record("cleanup",cleaned)
	# Damage/status from earlier hit events resolve ahead of periodic damage at the same tick.
	queue.drain(_process_event,1024)
	# Cleanup traces follow damage/trigger/reaction resolution, not precede it.
	if queue.pending_count() == 0:
		for pending in _deferred_burst_cleanup:
			var ctx: Dictionary = pending["context"]
			trace.record("cleanup",{"cast_id":ctx["cast_id"],"root_cast_id":ctx["root_cast_id"],
				"formula_id":ctx["formula_id"],"effect_id":pending["effect_id"],"tick":clock.tick})
			queue.release_effect()
		_deferred_burst_cleanup.clear()
	_prune_chain_seen()
	_tick_statuses()
	if not visuals.is_empty():
		visuals = visuals.filter(func(v): return int(v["until"]) > clock.tick)
	if not recent_damage.is_empty():
		var min_tick: int = clock.tick-int(settings["sandbox"]["dps_window_ticks"])
		recent_damage = recent_damage.filter(func(v): return int(v["tick"]) >= min_tick)

## AD-143 Gravity Lens: orb hits pull the target toward the orbit centre (the caster) through the knockback impulse.
func _gravity_pull(target_id: int) -> void:
	var target = targets.get_target(target_id)
	if target == null or not target.alive():
		return
	var toward: Vector2 = actor.position-target.position
	if not toward.is_zero_approx():
		target.impulse += toward.normalized()*float(artifacts.param("gravity_lens","pull_force",160))

## Where an On Expire / Timer payload lands: beams end at their end point, everything else at its position.
func _trigger_location(entry: Dictionary) -> Vector2:
	return entry["effect"].end_point if entry["kind"] == "beam" else entry["effect"].position

func _prune_chain_seen() -> void:
	for root_id in _chain_seen.keys():
		var live := false
		for entry in active:
			live = live or int(entry["context"]["root_cast_id"]) == root_id
		for pending in _deferred_burst_cleanup:
			live = live or int(pending["context"]["root_cast_id"]) == root_id
		if not live and queue.pending_count() == 0:
			_chain_seen.erase(root_id)

## Beams pay mana_per_tick on each pulse (no mana ends the beam without hits); both forms report cap truncation once.
func _charge_pulse(entry: Dictionary, pulse: Dictionary) -> Array:
	if not pulse["pulse"]:
		return []
	var effect = entry["effect"]
	if entry["kind"] == "beam":
		var cost := float(effect.root["params"]["mana_per_tick"])
		if mana + 0.00001 < cost:
			effect.expire("no_mana")
			return []
		mana = maxf(0.0,mana-cost)
		trace.record("cost_paid",{"cast_id":entry["context"]["cast_id"],"root_cast_id":entry["context"]["root_cast_id"],
			"formula_id":entry["context"]["formula_id"],"amount":roundi(cost),"tick":clock.tick})
	if pulse["truncated"]:
		queue.note_budget_exceeded(entry["context"],"targets_per_pulse","max_targets_per_pulse")
	return pulse["hits"]

## Hold-to-channel hooks (mage "channel" animation tag, AD-121, keys off is_channelling()).
func stop_channel() -> void:
	for entry in active:
		if entry["kind"] == "beam":
			entry["effect"].expire("released")

func set_channel_aim(direction: Vector2) -> void:
	for entry in active:
		if entry["kind"] == "beam":
			entry["effect"].set_aim(direction)

func is_channelling() -> bool:
	return _active_count("beam") > 0

func _process_event(event: Dictionary) -> void:
	var id: int = int(event["event_id"])
	var details: Dictionary = _contexts.get(id,{})
	_contexts.erase(id)
	var kind: String = str(event["type"])
	if kind == "hit":
		_hit(event,details)
	elif kind == "trigger":
		if not details.is_empty():
			_spawn_burst(details["effect"],details["location"],details["context"])
	elif kind == "reaction":
		_react(event,details)

func _hit(event: Dictionary, detail: Dictionary) -> void:
	if detail.is_empty():
		return
	var target = targets.get_target(int(event["target_id"]))
	if target == null or not target.eligible(int(detail["context"]["team"])):
		return
	var effect_plan: Dictionary = detail["plan"]
	var ctx: Dictionary = detail["context"]
	var push: Vector2 = target.position-Vector2(detail["location"])
	if push.is_zero_approx():
		push = target.position-actor.position
	if push.is_zero_approx():
		push = Vector2.RIGHT
	push = push.normalized()
	var payload: Dictionary = {
		"essence_id":str(effect_plan["essence"]["id"]),
		"damage":float(effect_plan["params"]["base_damage"]),
		"team":int(ctx["team"]),"caster_id":int(ctx["caster_id"]),
		"cast_id":int(ctx["cast_id"]),"root_cast_id":int(ctx["root_cast_id"]),
		"formula_id":str(ctx["formula_id"]),
		"knockback":{"force":0.0,"direction":push}}
	if bool(ctx.get("ignited",false)):
		payload["ignite"] = true
	var hit = HitPayload.new(payload,settings["channels"])
	var was_alive: bool = target.alive()
	var result: Dictionary = resolver.resolve(hit,target,targets,clock.tick)
	if not result["accepted"]:
		return
	if was_alive and not target.alive():
		_on_target_died(target,ctx)
	var quill_step: bool = target.alive() and _quill_crossed(target)
	total_hit_count += 1
	_track_damage(float(result["damage"]))
	if result.has("knockback"):
		target.impulse += push*float(result["knockback"]["force"])
	trace.record("hit",{"cast_id":ctx["cast_id"],"root_cast_id":ctx["root_cast_id"],
		"formula_id":ctx["formula_id"],"effect_id":detail["effect_id"],
		"target_id":target.id,"amount":roundi(float(result["damage"])),"tick":clock.tick})
	visuals.append({"kind":"hit","position":target.position,"radius":20.0,"essence":str(effect_plan["essence"]["id"]),"until":clock.tick+9})
	for state_change in result["status_events"]:
		trace.record("status",{"cast_id":ctx["cast_id"],"root_cast_id":ctx["root_cast_id"],"formula_id":ctx["formula_id"],
			"target_id":target.id,"reason":state_change["state"]+":"+state_change["action"],"tick":clock.tick})
	for entry in result["reactions"]:
		var bonus := float(entry["bonus_damage"])
		if bonus > 0.0:
			_track_damage(bonus)
			total_hit_count += 1
		trace.record("reaction",{"cast_id":ctx["cast_id"],"root_cast_id":ctx["root_cast_id"],
			"formula_id":ctx["formula_id"],"source_id":target.id,"target_id":target.id,
			"reason":str(entry["id"]),"amount":roundi(bonus),"tick":clock.tick})
		for affected_id in entry["affected_ids"]:
			if int(affected_id) != target.id:
				trace.record("status",{"cast_id":ctx["cast_id"],"root_cast_id":ctx["root_cast_id"],"formula_id":ctx["formula_id"],
					"target_id":int(affected_id),"reason":"blinded:applied","tick":clock.tick})
		visuals.append({"kind":"reaction","reaction":str(entry["id"]),"position":target.position,"until":clock.tick+17})
	if not result["reaction"].is_empty() and queue.chain_targets_allowed(1,ctx):
		var react_ctx := {"cast_id":ctx["cast_id"],"root_cast_id":ctx["root_cast_id"],
			"formula_id":ctx["formula_id"],"parent_effect_id":detail["effect_id"],
			"source_id":target.id,"target_id":result["reaction"]["target_id"],"depth":ctx["depth"]}
		var item_id: int = queue.push_id(react_ctx.merged({"type":"reaction"}))
		if item_id >= 0:
			_contexts[item_id] = {"arc":result["reaction"],"context":ctx.duplicate()}
	if not bool(detail.get("chained",false)) and _has_modifier(effect_plan,"mod.chain"):
		_chain_from(target,effect_plan,ctx,detail)
	# Only depth-0 (root) contexts fire triggers, so payload Bursts can never recurse.
	var trigger: Dictionary = detail["on_hit"]
	if trigger.is_empty() or int(ctx["depth"]) != 0:
		return
	var trigger_id := _trigger_id(trigger)
	if trigger_id == "trigger.on_kill" and quill_step and not bool(detail.get("chained",false)):
		trace.record("artifact",{"cast_id":ctx["cast_id"],"root_cast_id":ctx["root_cast_id"],"formula_id":ctx["formula_id"],
			"target_id":target.id,"reason":"artifact.archivists_quill","tick":clock.tick})
		_fire_trigger(trigger,ctx,int(detail["effect_id"]),target.id,target.position)
	elif trigger_id == "trigger.on_hit":
		_fire_trigger(trigger,ctx,int(detail["effect_id"]),target.id,detail["location"])
	# PROPOSED limits: kills from Burning DOT, lightning arcs and chain jumps do not fire On Kill.
	elif trigger_id == "trigger.on_kill" and was_alive and not target.alive() and not bool(detail.get("chained",false)):
		_fire_trigger(trigger,ctx,int(detail["effect_id"]),target.id,target.position)

## Enqueues one trigger payload through the bounded queue (depth and per-root event budgets live there).
func _fire_trigger(trigger_plan: Dictionary, ctx: Dictionary, parent_effect_id: int, target_id: int, location: Vector2) -> bool:
	var child: Dictionary = ctx.duplicate()
	child["parent_effect_id"] = parent_effect_id
	child["depth"] = int(ctx["depth"])+1
	var spawned_id: int = queue.push_id({"type":"trigger","cast_id":ctx["cast_id"],"root_cast_id":ctx["root_cast_id"],
		"formula_id":ctx["formula_id"],"source_id":ctx["caster_id"],"target_id":target_id,
		"parent_effect_id":parent_effect_id,"depth":child["depth"],"position":location})
	if spawned_id < 0:
		return false
	var record := {"cast_id":ctx["cast_id"],"root_cast_id":ctx["root_cast_id"],
		"formula_id":ctx["formula_id"],"parent_effect_id":parent_effect_id,"depth":child["depth"],"tick":clock.tick}
	var trigger_id := _trigger_id(trigger_plan)
	if trigger_id != "trigger.on_hit":
		record["reason"] = trigger_id
		if trigger_id == "trigger.on_kill":
			record["target_id"] = target_id
	trace.record("trigger",record)
	_contexts[spawned_id] = {
		"effect":trigger_plan["effect"],"location":location,"context":child}
	return true

## Chain: up to chain_count jumps to the nearest unseen eligible target (ties by id); a target is a chain target once per root cast.
func _chain_from(origin_target, effect_plan: Dictionary, ctx: Dictionary, detail: Dictionary) -> void:
	var params: Dictionary = effect_plan["params"]
	var seen: Dictionary = _chain_seen.get(int(ctx["root_cast_id"]),{})
	_chain_seen[int(ctx["root_cast_id"])] = seen
	var from = origin_target
	for jump in int(params["chain_count"]):
		var pick = null
		var best := INF
		for candidate in targets.all():
			if not candidate.eligible(int(ctx["team"])) or not candidate.alive() or seen.has(candidate.id):
				continue
			var distance: float = from.position.distance_to(candidate.position)
			if distance <= float(params["chain_radius"]) and distance < best:
				best = distance
				pick = candidate
		if pick == null or not queue.chain_targets_allowed(jump+1,ctx):
			return
		seen[pick.id] = true
		trace.record("chain",{"cast_id":ctx["cast_id"],"root_cast_id":ctx["root_cast_id"],"formula_id":ctx["formula_id"],
			"effect_id":detail["effect_id"],"source_id":from.id,"target_id":pick.id,"tick":clock.tick})
		visuals.append({"kind":"arc","from":from.position,"to":pick.position,"until":clock.tick+17})
		_queue_hit(effect_plan,pick.id,pick.position,ctx,int(detail["effect_id"]),{},true)
		from = pick

func _react(event: Dictionary, detail: Dictionary) -> void:
	if detail.is_empty():
		return
	var arc: Dictionary = detail["arc"]
	var selected = targets.get_target(int(arc["target_id"]))
	var source = targets.get_target(int(arc["source_id"]))
	if selected == null or source == null:
		return
	var arc_was_alive: bool = selected.alive()
	var dealt: float = resolver.resolve_arc(arc,selected)
	if dealt <= 0:
		return
	if arc_was_alive and not selected.alive():
		_on_target_died(selected,detail["context"])
	total_hit_count += 1
	_track_damage(dealt)
	trace.record("reaction",{"cast_id":event["cast_id"],"root_cast_id":event["root_cast_id"],
		"formula_id":event["formula_id"],"source_id":source.id,"target_id":selected.id,
		"reason":"wet_lightning_arc","amount":roundi(dealt),"tick":clock.tick})
	visuals.append({"kind":"arc","from":source.position,"to":selected.position,"until":clock.tick+17})
	if int(arc.get("jumps_left",0)) > 0:
		_storm_jump(event,detail,arc,selected)

## AD-143 Stormglass: queue the next arc to the nearest eligible target not yet in this arc chain (distance, then id).
func _storm_jump(event: Dictionary, detail: Dictionary, arc: Dictionary, from) -> void:
	var seen: Array = arc["seen"]
	var near: Array = targets.query(from.position,float(settings["combat"]["arc_radius"]),int(arc["team"]),seen,"",clock.tick)
	if near.is_empty() or not queue.chain_targets_allowed(seen.size(),detail["context"]):
		return
	var next_arc: Dictionary = arc.duplicate(true)
	next_arc["source_id"] = from.id
	next_arc["target_id"] = near[0].id
	next_arc["jumps_left"] = int(arc["jumps_left"])-1
	next_arc["seen"] = seen+[near[0].id]
	var item_id: int = queue.push_id({"type":"reaction","cast_id":event["cast_id"],"root_cast_id":event["root_cast_id"],
		"formula_id":event["formula_id"],"parent_effect_id":event.get("parent_effect_id",0),
		"source_id":from.id,"target_id":near[0].id,"depth":event["depth"]})
	if item_id >= 0:
		_contexts[item_id] = {"arc":next_arc,"context":detail["context"].duplicate()}

## Deterministic knockback: id-ordered, wall/bounds-safe, fixed-tick decay (all rates from data).
func _advance_knockback() -> void:
	var dt := 1.0/float(clock.tick_rate)
	var decay := float(settings["combat"]["knockback_decay_per_tick"])
	var min_speed := float(settings["combat"]["knockback_min_speed"])
	for t in targets.all():
		if t.impulse.is_zero_approx():
			continue
		if not t.alive():
			t.impulse = Vector2.ZERO
			continue
		var next: Vector2 = t.position+t.impulse*dt
		next.x = clampf(next.x,bounds.position.x+t.radius,bounds.end.x-t.radius)
		next.y = clampf(next.y,bounds.position.y+t.radius,bounds.end.y-t.radius)
		var blocked := false
		for wall in collision_walls:
			if _circle_hits_rect(next,t.radius,wall):
				blocked = true
				break
		if not blocked:
			t.position = next
		t.impulse *= decay
		if t.impulse.length() < min_speed:
			t.impulse = Vector2.ZERO

static func _circle_hits_rect(center: Vector2, radius: float, rect: Rect2) -> bool:
	var closest := Vector2(clampf(center.x,rect.position.x,rect.end.x),clampf(center.y,rect.position.y,rect.end.y))
	return closest.distance_squared_to(center) < radius*radius

func _tick_statuses() -> void:
	for t in targets.all():
		if not t.alive():
			t.impulse = Vector2.ZERO
			t.status.clear()
			continue
		for due in t.status.tick(clock.tick,settings["statuses"]):
			if due["type"] == "expired":
				trace.record("status",{"target_id":t.id,"reason":due["state_id"]+":expired","tick":clock.tick})
			elif due["type"] == "dot" and t.alive():
				var source: Dictionary = due["source"]
				var dealt: float = t.receive_damage(float(due["damage"]),"fire",int(source.get("team",1)),
					float(settings["combat"]["armor_scale"]))
				if dealt > 0:
					total_hit_count += 1
					_track_damage(dealt)
					trace.record("status",{"cast_id":source.get("cast_id",0),"root_cast_id":source.get("root_cast_id",0),
						"formula_id":source.get("formula_id",""),"target_id":t.id,
						"reason":due["state_id"]+":dot","amount":roundi(dealt),"tick":clock.tick})
				if _art("archivists_quill"):
					_quill_crossed(t)
				if not t.alive():
					_on_target_died(t,source)
					t.status.clear()
					break

func _track_damage(dealt: float) -> void:
	if dealt > 0:
		recent_damage.append({"tick":clock.tick,"damage":dealt})

func _modifier_ids(plan: Dictionary) -> Array:
	var result: Array = []
	for modifier in plan.get("modifiers",[]):
		result.append(modifier["id"])
	return result

func _has_modifier(plan: Dictionary, id: String) -> bool:
	for modifier in plan.get("modifiers",[]):
		if modifier["id"] == id:
			return true
	return false

func _active_orb_count() -> int:
	return _active_count("orb")

func _active_count(kind: String) -> int:
	var count := 0
	for entry in active:
		if entry["kind"] == kind and not entry["effect"].expired:
			count += 1
	return count

func dps() -> float:
	var total := 0.0
	for item in recent_damage:
		total += float(item["damage"])
	return total * float(clock.tick_rate)/float(settings["sandbox"]["dps_window_ticks"])

func stress() -> Dictionary:
	# A synthetic workload to expose the same production per-cast/global caps.
	var root_id: int = clock.next_id("cast")
	var accepted := 0
	for i in 10000:
		if queue.reserve_effect(root_id,20,root_id,"sandbox.stress"):
			accepted += 1
	for i in accepted:
		visuals.append({"kind":"burst","position":Vector2(240+(i%8)*60,90+floori(float(i)/8.0)*50),
			"radius":18.0,"until":clock.tick+20})
		queue.release_effect()
	return {"accepted":accepted,"attempted":10000,"cap":limits.get_limit("max_effects_per_cast")}

func inspect() -> Dictionary:
	var roster: Array = []
	for t in targets.all():
		if t.id == actor.id:
			continue
		roster.append({"id":t.id,"position":t.position,"hp":t.health.current,"alive":t.alive(),
			"hits":t.hit_count,"states":t.status.snapshot(clock.tick)})
	return {"seed":run_seed_value,"tick":clock.tick,"mana":mana,"paused":clock.paused,
		"active_effects":queue.active_effect_count(),"event_pending":queue.pending_count(),
		"total_hits":total_hit_count,"dps":dps(),"targets":roster,"slots":[loadout.preview(0),loadout.preview(1)],
		"last_rejection":last_rejection}

func trace_json() -> String:
	return trace.to_json()
