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
	var damage: float = target.receive_damage(float(payload.get("damage",0)),str(rule["channel"]),team,float(combat["armor_scale"]))
	var outcome := {"accepted":true,"damage":damage,"status_events":[],"reaction":{}}
	# If a direct hit kills a target, it cannot retain a new status or arc.
	if not target.alive():
		return outcome
	for status_id in rule.get("remove",[]):
		if target.status.remove(str(status_id)):
			outcome["status_events"].append({"state":str(status_id),"action":"removed"})
	var apply_status := str(rule.get("apply",""))
	if not apply_status.is_empty():
		var context := {"cast_id":int(payload.get("cast_id",0)), "root_cast_id":int(payload.get("root_cast_id",0)), "formula_id":str(payload.get("formula_id","")),"team":team}
		target.status.apply(apply_status,tick,settings["statuses"][apply_status],context)
		outcome["status_events"].append({"state":apply_status,"action":"applied"})
	if str(rule["channel"]) == "lightning" and target.status.has("wet",tick):
		var options: Array = target_store.query(target.position,float(combat["arc_radius"]),team,[target.id],"wet",tick)
		if not options.is_empty():
			outcome["reaction"] = {"source_id":target.id,"target_id":options[0].id,
				"damage":float(payload.get("damage",0))*float(combat["arc_damage_scale"]),
				"team":team,"channel":"lightning"}
	return outcome

func resolve_arc(arc: Dictionary, target) -> float:
	if not target.eligible(int(arc["team"])):
		return 0.0
	return target.receive_damage(float(arc["damage"]),str(arc["channel"]),int(arc["team"]),float(settings["combat"]["armor_scale"]))
