extends RefCounted
## TASK-009: bounded FIFO events. Callbacks may enqueue but cannot recursively drain.
const MagicEvent = preload("res://magic/runtime/magic_event.gd")
var clock
var limits
var trace
var _pending: Array = []
var _event_counts: Dictionary = {}
var _effect_counts: Dictionary = {}
var _budget_reasons_logged: Dictionary = {}
var _active_effect_count := 0
var _draining := false

func _init(simulation_clock, spell_limits, debug_trace) -> void:
	clock = simulation_clock
	limits = spell_limits
	trace = debug_trace

func push(event_data: Dictionary) -> Dictionary:
	var item = MagicEvent.new()
	var validation: Dictionary = item.from_dict(event_data)
	if not validation["ok"]:
		return {"accepted":false,"reason":"EVENT_INVALID","issues":validation["issues"]}
	var event: Dictionary = item.snapshot()
	var root := int(event["root_cast_id"])
	if event["depth"] > limits.get_limit("max_event_depth"):
		_budget_exceeded(event,"event_depth","max_event_depth")
		return {"accepted":false,"reason":"EVENT_DEPTH_EXCEEDED"}
	if int(_event_counts.get(root,0)) >= limits.get_limit("max_events_per_root_cast"):
		_budget_exceeded(event,"events_per_cast","max_events_per_root_cast")
		return {"accepted":false,"reason":"EVENT_BUDGET_EXCEEDED"}
	event["event_id"] = clock.next_id("event")
	event["sequence"] = event["event_id"]
	_event_counts[root] = int(_event_counts.get(root,0)) + 1
	_pending.append(event)
	return {"accepted":true,"event":event.duplicate(true)}

func reserve_effect(root_cast_id: int, lifetime_ticks: int, cast_id: int = 0, formula_id: String = "") -> bool:
	var context := {"root_cast_id":root_cast_id,"cast_id":cast_id,"formula_id":formula_id}
	if lifetime_ticks < 0 or lifetime_ticks > limits.get_limit("max_lifetime_ticks"):
		_budget_exceeded(context,"effect_lifetime","max_lifetime_ticks")
		return false
	if int(_effect_counts.get(root_cast_id,0)) >= limits.get_limit("max_effects_per_cast"):
		_budget_exceeded(context,"effects_per_cast","max_effects_per_cast")
		return false
	if _active_effect_count >= limits.get_limit("max_active_effects"):
		_budget_exceeded(context,"active_effects","max_active_effects")
		return false
	_effect_counts[root_cast_id] = int(_effect_counts.get(root_cast_id,0)) + 1
	_active_effect_count += 1
	return true

func release_effect() -> void:
	_active_effect_count = maxi(0,_active_effect_count-1)

func chain_targets_allowed(count: int, context: Dictionary = {}) -> bool:
	if count <= limits.get_limit("max_chain_targets"):
		return true
	_budget_exceeded(context,"chain_targets","max_chain_targets")
	return false

func rehit_delay_valid(ticks_since_previous_hit: int, context: Dictionary = {}) -> bool:
	if ticks_since_previous_hit >= limits.get_limit("min_rehit_delay_ticks"):
		return true
	_budget_exceeded(context,"rehit_delay","min_rehit_delay_ticks")
	return false

func drain(on_event: Callable, budget: int = 1024) -> Dictionary:
	if _draining:
		return {"ok":false,"processed":0,"reason":"REENTRANT_DRAIN"}
	_draining = true
	var count := 0
	while not _pending.is_empty() and count < budget:
		# FIFO in monotonic event sequence; enqueued during callbacks goes last.
		var data: Dictionary = _pending.pop_front()
		on_event.call(data.duplicate(true))
		count += 1
	_draining = false
	return {"ok":true,"processed":count,"remaining":_pending.size()}

func pending_count() -> int:
	return _pending.size()

func active_effect_count() -> int:
	return _active_effect_count

func _budget_exceeded(event: Dictionary, reason: String, limit_key: String) -> void:
	var root := int(event.get("root_cast_id",event.get("cast_id",0)))
	var key := str(root)+":"+reason
	if _budget_reasons_logged.has(key):
		return
	_budget_reasons_logged[key] = true
	trace.record("budget_exceeded",{
		"cast_id":int(event.get("cast_id",0)),
		"root_cast_id":root,
		"formula_id":str(event.get("formula_id","")),
		"parent_effect_id":int(event.get("parent_effect_id",0)),
		"reason":reason,
		"limit":limits.get_limit(limit_key),
		"tick":clock.tick
	})

func reset() -> void:
	_pending.clear()
	_event_counts.clear()
	_effect_counts.clear()
	_budget_reasons_logged.clear()
	_active_effect_count = 0
	_draining = false
