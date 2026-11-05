extends RefCounted
const HitPayload = preload("res://combat/hit_payload.gd")
## Payload is element-agnostic; definition data provides channels and status rules.
var settings: Dictionary = {}

func _init(balance: Dictionary) -> void:
	settings = balance.duplicate(true)

func resolve(hit: Variant, target, target_store, tick: int) -> Dictionary:
	if hit is HitPayload and not hit.valid:
		return {"accepted":false,"damage":0.0,"reason":"HIT_PAYLOAD_INVALID","reaction":{}}
	var payload: Dictionary = hit.snapshot() if hit is HitPayload else hit
	# All hit eligibility (team / death) happens through MagicTarget.
	var team := int(payload.get("team",1))
	if not target.eligible(team):
		return {"accepted":false,"damage":0.0,"reason":"INELIGIBLE_TARGET","reaction":{}}
	var essence := str(payload.get("essence_id",""))
	var channels: Dictionary = settings.get("channels",{})
	if not channels.has(essence):
		return {"accepted":false,"damage":0.0,"reason":"UNKNOWN_ESSENCE","reaction":{}}
	var rule: Dictionary = channels[essence]
	var combat: Dictionary = settings["combat"]
	var statuses: Dictionary = settings["statuses"]
	var reactions: Dictionary = settings.get("reactions",{})
	var incoming := float(payload.get("damage",0))
	if target.status.has("brittle",tick):
		incoming *= float(statuses["brittle"].get("damage_taken_mult",1.0))
	var channel := str(rule["channel"])
	var damage: float = target.receive_damage(incoming,channel,team,float(combat["armor_scale"]))
	var outcome := {"accepted":true,"damage":damage,"status_events":[],"reaction":{},"reactions":[]}
	# If a direct hit kills a target, it cannot retain a new status or arc.
	if not target.alive():
		return outcome
	var context := {"cast_id":int(payload.get("cast_id",0)), "root_cast_id":int(payload.get("root_cast_id",0)), "formula_id":str(payload.get("formula_id","")),"team":team}
	var matched := _match_reaction(reactions.get("rules",[]),channel,target,tick)
	var suppress := false
	if not matched.is_empty():
		suppress = bool(matched.get("suppress_channel_apply",false))
		_apply_reaction(matched,payload,target,target_store,tick,context,outcome)
	if not suppress:
		for status_id in rule.get("remove",[]):
			if target.status.remove(str(status_id)):
				outcome["status_events"].append({"state":str(status_id),"action":"removed"})
		var apply_status := str(rule.get("apply",""))
		if not apply_status.is_empty():
			target.status.apply(apply_status,tick,statuses[apply_status],context)
			outcome["status_events"].append({"state":apply_status,"action":"applied"})
	var freeze_stacks := int(reactions.get("chill_freeze_stacks",0))
	if freeze_stacks > 0 and target.status.stacks("chilled",tick) >= freeze_stacks:
		target.status.remove("chilled")
		outcome["status_events"].append({"state":"chilled","action":"removed"})
		target.status.apply("frozen",tick,statuses["frozen"],context)
		outcome["status_events"].append({"state":"frozen","action":"applied"})
		outcome["reactions"].append({"id":"chill_freeze","target_id":target.id,"bonus_damage":0.0,"affected_ids":[]})
	var knockback := float(rule.get("knockback_force",0))
	if knockback > 0.0:
		var immune := false
		for tag in reactions.get("knockback_immune_tags",[]):
			if target.tags.has(tag):
				immune = true
		if not immune:
			outcome["knockback"] = {"force":knockback}
	if channel == "lightning" and target.status.has("wet",tick):
		var options: Array = target_store.query(target.position,float(combat["arc_radius"]),team,[target.id],"wet",tick)
		if not options.is_empty():
			outcome["reaction"] = {"source_id":target.id,"target_id":options[0].id,
				"damage":float(payload.get("damage",0))*float(combat["arc_damage_scale"]),
				"team":team,"channel":"lightning"}
	return outcome

## Rules are keyed on hit channel + target states, never on spell identity. First match wins.
func _match_reaction(rules: Array, channel: String, target, tick: int) -> Dictionary:
	for rule in rules:
		if str(rule.get("channel","")) != channel:
			continue
		for state_id in rule.get("requires_any",[]):
			if target.status.has(str(state_id),tick):
				return rule
	return {}

func _apply_reaction(rule: Dictionary, payload: Dictionary, target, target_store, tick: int, context: Dictionary, outcome: Dictionary) -> void:
	var statuses: Dictionary = settings["statuses"]
	for status_id in rule.get("remove",[]):
		if target.status.remove(str(status_id)):
			outcome["status_events"].append({"state":str(status_id),"action":"removed"})
	for status_id in rule.get("apply",[]):
		target.status.apply(str(status_id),tick,statuses[str(status_id)],context)
		outcome["status_events"].append({"state":str(status_id),"action":"applied"})
	var bonus := 0.0
	var scale := float(rule.get("bonus_damage_scale",0))
	if scale > 0.0:
		bonus = target.receive_damage(float(payload.get("damage",0))*scale,str(rule["channel"]),int(payload.get("team",1)),float(settings["combat"]["armor_scale"]))
		outcome["damage"] = float(outcome["damage"]) + bonus
	var affected: Array = []
	if rule.has("area_apply"):
		var area: Dictionary = rule["area_apply"]
		var area_status := str(area["status"])
		var team := int(payload.get("team",1))
		var ids: Array = [target.id]
		for other in target_store.query(target.position,float(area["radius"]),team,[],"",tick):
			if other.id != target.id:
				ids.append(other.id)
		ids.sort()
		for id in ids:
			var node = target if id == target.id else target_store.get_target(id)
			node.status.apply(area_status,tick,statuses[area_status],context)
			affected.append(id)
	outcome["reactions"].append({"id":str(rule["id"]),"target_id":target.id,"bonus_damage":bonus,"affected_ids":affected})

func resolve_arc(arc: Dictionary, target) -> float:
	if not target.eligible(int(arc["team"])):
		return 0.0
	return target.receive_damage(float(arc["damage"]),str(arc["channel"]),int(arc["team"]),float(settings["combat"]["armor_scale"]))
