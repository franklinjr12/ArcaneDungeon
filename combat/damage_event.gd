extends RefCounted
## All enemy attacks submit one typed damage intent before touching player HP.
var data: Dictionary = {}
func _init(source_id: int, attacker_team: int, target_id: int, amount: float, channel: String, attack_id: int, tick: int) -> void:
	data = {"source_id":source_id,"team":attacker_team,"target_id":target_id,
		"amount":amount,"channel":channel,"attack_id":attack_id,"tick":tick}
func snapshot() -> Dictionary:
	return data.duplicate(true)
