extends RefCounted
## M1 deterministic sandbox simulation (TASK-011–025). Only data-driven generic spells.
const Clock = preload("res://game/core/simulation_clock.gd")
const Registry = preload("res://magic/data/rune_registry.gd")
const Limits = preload("res://magic/runtime/spell_limits.gd")
const Queue = preload("res://magic/runtime/magic_event_queue.gd")
const Trace = preload("res://debug/debug_trace.gd")
const Target = preload("res://combat/magic_target.gd")
const Store = preload("res://combat/target_store.gd")
const Resolver = preload("res://combat/interaction_resolver.gd")
const HitPayload = preload("res://combat/hit_payload.gd")
const Projectile = preload("res://magic/runtime/projectile_effect.gd")
const Burst = preload("res://magic/runtime/burst_effect.gd")
const Orb = preload("res://magic/runtime/orb_effect.gd")
const Loadout = preload("res://magic/runtime/spell_loadout.gd")
const CONFIG := "res://magic/data/magic_balance_v1.json"

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
var last_rejection := ""
var total_hit_count := 0
var run_seed_value := 12345
var initialized := false

func _init(run_seed: int = 12345, record_trace: bool = true) -> void:
	var data := FileAccess.open(CONFIG,FileAccess.READ)
	if data == null:
		printerr("M1 balance configuration unavailable")
		return
	var parsed = JSON.parse_string(data.get_as_text())
	if typeof(parsed) != TYPE_DICTIONARY or parsed.get("schema_version") != 1:
		printerr("Invalid M1 balance configuration")
		return
	settings = parsed
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

func try_cast(slot: int, origin: Vector2, direction: Vector2) -> Dictionary:
	var cast_id: int = clock.next_id("cast")
	var formula_id := ""
	if slot >= 0 and slot < 2:
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
	if mana + 0.00001 < float(plan["mana_cost"]):
		return _reject(ctx,"INSUFFICIENT_MANA")
	var kind := str(plan["root"]["manifestation"]["id"])
	if kind == "form.orb" and _active_orb_count() >= limits.get_limit("max_active_orbs"):
		return _reject(ctx,"ORB_BUDGET_EXCEEDED")
	var duration := 1
	if kind == "form.projectile" or kind == "form.orb":
		duration = int(plan["root"]["params"]["lifetime_ticks"])
	if not queue.reserve_effect(cast_id,duration,cast_id,formula_id):
		return _reject(ctx,"EFFECT_BUDGET_EXCEEDED")
	mana = maxf(0.0,mana-float(plan["mana_cost"]))
	loadout.slots[slot]["cooldown"] = int(plan["cooldown_ticks"])
	trace.record("cost_paid",{"cast_id":cast_id,"root_cast_id":cast_id,"formula_id":formula_id,"amount":int(plan["mana_cost"]),"tick":clock.tick})
	var base := {"cast_id":cast_id,"root_cast_id":cast_id,"caster_id":actor.id,"team":actor.team,
		"formula_id":formula_id,"parent_effect_id":0,"depth":0}
	_spawn_root(plan,origin,direction.normalized(),base)
	return {"accepted":true,"reason":"CAST","cast_id":cast_id}

func _reject(ctx: Dictionary, reason: String) -> Dictionary:
	last_rejection = reason
	var data := ctx.duplicate()
	data["reason"] = reason
	trace.record("rejected",data)
	return {"accepted":false,"reason":reason,"cast_id":int(ctx["cast_id"])}

func _spawn_root(plan: Dictionary, origin: Vector2, aim: Vector2, context: Dictionary) -> void:
	var root: Dictionary = plan["root"]
	var ids: Array = _modifier_ids(root)
	var kind := str(root["manifestation"]["id"])
	if kind == "form.projectile":
		var count := int(root["params"].get("projectile_count",1)) if "mod.split" in ids else 1
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
			var projectile = Projectile.new(spec)
			active.append({"kind":"projectile","effect":projectile,"context":context.duplicate(true)})
			_trace_spawn(context,int(spec["effect_id"]),origin)
	elif kind == "form.burst":
		_spawn_burst(root,origin,context,true)
	elif kind == "form.orb":
		var spec: Dictionary = context.duplicate()
		spec["effect_id"] = clock.next_id("effect")
		spec["root"] = root
		var orb = Orb.new(spec)
		active.append({"kind":"orb","effect":orb,"context":context.duplicate(true)})
		_trace_spawn(context,orb.id,origin)
	else:
		queue.release_effect()

func _spawn_burst(effect_plan: Dictionary, origin: Vector2, context: Dictionary, already_reserved: bool = false) -> bool:
	if not already_reserved and not queue.reserve_effect(int(context["root_cast_id"]),1,
			int(context["cast_id"]),str(context["formula_id"])):
		return false
	var effect_id: int = clock.next_id("effect")
	_trace_spawn(context,effect_id,origin)
	var radius: float = float(effect_plan["params"]["burst_radius"])
	visuals.append({"kind":"burst","position":origin,"radius":radius,"until":clock.tick+int(settings["sandbox"]["visual_ticks"])})
	for hit in Burst.contacts(origin,radius,int(context["team"]),targets):
		_queue_hit(effect_plan,int(hit["target_id"]),hit["position"],context,effect_id,{})
	# Hold the effect reservation until queued contacts finish resolving.
	# Releasing here would let same-tick trigger bursts bypass global active limits.
	_deferred_burst_cleanup.append({"effect_id":effect_id,"context":context.duplicate(true)})
	return true

func _trace_spawn(ctx: Dictionary, effect_id: int, at: Vector2) -> void:
	trace.record("spawn",{"cast_id":ctx["cast_id"],"root_cast_id":ctx["root_cast_id"],
		"formula_id":ctx["formula_id"],"parent_effect_id":ctx["parent_effect_id"],
		"effect_id":effect_id,"depth":ctx["depth"],"position":at,"tick":clock.tick})

func _queue_hit(root: Dictionary, target_id: int, location: Vector2, ctx: Dictionary, effect_id: int, attached_trigger: Dictionary) -> void:
	var fields: Dictionary = {"type":"hit","cast_id":ctx["cast_id"],"root_cast_id":ctx["root_cast_id"],
		"formula_id":ctx["formula_id"],"parent_effect_id":effect_id,"source_id":ctx["caster_id"],
		"target_id":target_id,"position":location,"depth":ctx["depth"]}
	var pushed: Dictionary = queue.push(fields)
	if pushed["accepted"]:
		_contexts[int(pushed["event"]["event_id"])] = {"plan":root.duplicate(true),"context":ctx.duplicate(true),
			"on_hit":attached_trigger.duplicate(true),"effect_id":effect_id,"location":location}

func step() -> void:
	if clock.paused:
		return
	advance_one_tick()

func advance_one_tick() -> void:
	clock.step_once()
	loadout.cooldown_tick()
	mana = minf(float(settings["combat"]["player_max_mana"]),mana+float(settings["combat"]["regen_mana_per_tick"]))
	targets.advance_movers(1.0/float(clock.tick_rate),bounds)
	# Every source effect is moved once; callback work stays queued until the movement pass is complete.
	for entry in active.duplicate():
		var effect = entry["effect"]
		var hits: Array = []
		if entry["kind"] == "projectile":
			if "mod.homing" in _modifier_ids(effect.root):
				effect.steer(1.0/float(clock.tick_rate),targets,effect.root["params"])
			hits = effect.advance(1.0/float(clock.tick_rate),targets,bounds,collision_walls)
		elif entry["kind"] == "orb":
			hits = effect.advance(1.0/float(clock.tick_rate),clock.tick,actor,targets,
				limits.get_limit("min_rehit_delay_ticks"))
		for hit in hits:
			_queue_hit(effect.root,int(hit["target_id"]),hit["position"],entry["context"],effect.id,
				effect.on_hit if entry["kind"] == "projectile" else {})
		if effect.expired:
			active.erase(entry)
			queue.release_effect()
			trace.record("cleanup",{"cast_id":entry["context"]["cast_id"],"root_cast_id":entry["context"]["root_cast_id"],
				"formula_id":entry["context"]["formula_id"],"effect_id":effect.id,"tick":clock.tick})
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
	_tick_statuses()
	visuals = visuals.filter(func(v): return int(v["until"]) > clock.tick)
	var min_tick: int = clock.tick-int(settings["sandbox"]["dps_window_ticks"])
	recent_damage = recent_damage.filter(func(v): return int(v["tick"]) >= min_tick)

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
	var payload: Dictionary = {
		"essence_id":str(effect_plan["essence"]["id"]),
		"damage":float(effect_plan["params"]["base_damage"]),
		"team":int(ctx["team"]),"caster_id":int(ctx["caster_id"]),
		"cast_id":int(ctx["cast_id"]),"root_cast_id":int(ctx["root_cast_id"]),
		"formula_id":str(ctx["formula_id"]),
		"knockback":{"force":0.0,"direction":Vector2.ZERO}}
	var hit = HitPayload.new(payload,settings["channels"])
	var result: Dictionary = resolver.resolve(hit,target,targets,clock.tick)
	if not result["accepted"]:
		return
	total_hit_count += 1
	_track_damage(float(result["damage"]))
	trace.record("hit",{"cast_id":ctx["cast_id"],"root_cast_id":ctx["root_cast_id"],
		"formula_id":ctx["formula_id"],"effect_id":detail["effect_id"],
		"target_id":target.id,"amount":roundi(float(result["damage"])),"tick":clock.tick})
	visuals.append({"kind":"hit","position":target.position,"radius":20.0,"until":clock.tick+9})
	for state_change in result["status_events"]:
		trace.record("status",{"cast_id":ctx["cast_id"],"root_cast_id":ctx["root_cast_id"],"formula_id":ctx["formula_id"],
			"target_id":target.id,"reason":state_change["state"]+":"+state_change["action"],"tick":clock.tick})
	if not result["reaction"].is_empty() and queue.chain_targets_allowed(1,ctx):
		var react_ctx := {"cast_id":ctx["cast_id"],"root_cast_id":ctx["root_cast_id"],
			"formula_id":ctx["formula_id"],"parent_effect_id":detail["effect_id"],
			"source_id":target.id,"target_id":result["reaction"]["target_id"],"depth":ctx["depth"]}
		var item = queue.push(react_ctx.merged({"type":"reaction"}))
		if item["accepted"]:
			_contexts[int(item["event"]["event_id"])] = {"arc":result["reaction"],"context":ctx.duplicate(true)}
	if not detail["on_hit"].is_empty():
		var child: Dictionary = ctx.duplicate()
		child["parent_effect_id"] = detail["effect_id"]
		child["depth"] = int(ctx["depth"])+1
		var spawned = queue.push({"type":"trigger","cast_id":ctx["cast_id"],"root_cast_id":ctx["root_cast_id"],
			"formula_id":ctx["formula_id"],"source_id":ctx["caster_id"],"target_id":target.id,
			"parent_effect_id":detail["effect_id"],"depth":child["depth"],"position":detail["location"]})
		if spawned["accepted"]:
			trace.record("trigger",{"cast_id":ctx["cast_id"],"root_cast_id":ctx["root_cast_id"],
				"formula_id":ctx["formula_id"],"parent_effect_id":detail["effect_id"],"depth":child["depth"],"tick":clock.tick})
			_contexts[int(spawned["event"]["event_id"])] = {
				"effect":detail["on_hit"]["effect"].duplicate(true),"location":detail["location"],"context":child}
	
func _react(event: Dictionary, detail: Dictionary) -> void:
	if detail.is_empty():
		return
	var arc: Dictionary = detail["arc"]
	var selected = targets.get_target(int(arc["target_id"]))
	var source = targets.get_target(int(arc["source_id"]))
	if selected == null or source == null:
		return
	var dealt: float = resolver.resolve_arc(arc,selected)
	if dealt <= 0:
		return
	total_hit_count += 1
	_track_damage(dealt)
	trace.record("reaction",{"cast_id":event["cast_id"],"root_cast_id":event["root_cast_id"],
		"formula_id":event["formula_id"],"source_id":source.id,"target_id":selected.id,
		"reason":"wet_lightning_arc","amount":roundi(dealt),"tick":clock.tick})
	visuals.append({"kind":"arc","from":source.position,"to":selected.position,"until":clock.tick+17})

func _tick_statuses() -> void:
	for t in targets.all():
		if not t.alive():
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
				if not t.alive():
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

func _active_orb_count() -> int:
	var count := 0
	for effect in active:
		if effect["kind"] == "orb":
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
