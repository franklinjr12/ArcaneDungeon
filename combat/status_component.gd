extends RefCounted
## Status lifecycle is clock-tick-driven. No wall-clock timers or scene dependencies.
var _states: Dictionary = {}

func apply(state_id: String, current_tick: int, definition: Dictionary, source: Dictionary = {}, stacks: int = 1) -> Dictionary:
	if not definition.has("duration_ticks") or int(definition["duration_ticks"]) <= 0:
		return {"ok":false,"reason":"INVALID_DURATION"}
	var policy := str(definition.get("refresh","replace_duration"))
	if policy not in ["replace_duration","extend_duration","keep_duration"]:
		return {"ok":false,"reason":"INVALID_REFRESH_POLICY"}
	var max_stacks := maxi(1,int(definition.get("max_stacks",1)))
	var current: Dictionary = _states.get(state_id,{})
	var next_stacks := mini(max_stacks,int(current.get("stacks",0)) + stacks)
	var next_tick := int(current.get("next_dot_tick",current_tick+int(definition.get("dot_interval_ticks",0))))
	if current.is_empty():
		next_tick = current_tick + int(definition.get("dot_interval_ticks",0))
	var expires := current_tick + int(definition["duration_ticks"])
	if not current.is_empty():
		if policy == "extend_duration":
			expires = int(current["expires_tick"]) + int(definition["duration_ticks"])
		elif policy == "keep_duration":
			expires = int(current["expires_tick"])
	_states[state_id] = {
		"stacks":next_stacks,"intensity":float(definition.get("intensity",1.0)),
		"expires_tick":expires,"next_dot_tick":next_tick,
		"source":source.duplicate(true)}
	return {"ok":true,"refreshed":not current.is_empty(),"expires_tick":expires}

func has(state_id: String, current_tick: int = -1) -> bool:
	if not _states.has(state_id):
		return false
	return current_tick < 0 or int(_states[state_id]["expires_tick"]) > current_tick

func remove(state_id: String) -> bool:
	if not _states.has(state_id):
		return false
	_states.erase(state_id)
	return true

func tick(now: int, config: Dictionary) -> Array:
	# Returns due ticks and expirations, never mutates health directly.
	var events: Array = []
	var keys := _states.keys()
	keys.sort()
	for id in keys:
		var data: Dictionary = _states[id]
		if now >= int(data["expires_tick"]):
			_states.erase(id)
			events.append({"type":"expired","state_id":id,"source":data["source"].duplicate(true)})
			continue
		var rule: Dictionary = config.get(id,{})
		var interval := int(rule.get("dot_interval_ticks",0))
		if interval > 0 and now >= int(data["next_dot_tick"]):
			data["next_dot_tick"] += interval
			events.append({"type":"dot","state_id":id,"damage":float(rule.get("dot_damage",0)) * float(data["intensity"]) * int(data["stacks"]), "source":data["source"].duplicate(true)})
	return events

func snapshot(now: int = -1) -> Dictionary:
	var result: Dictionary = {}
	for id in _states:
		if now < 0 or int(_states[id]["expires_tick"]) > now:
			result[id] = _states[id].duplicate(true)
	return result

func clear() -> void:
	_states.clear()
