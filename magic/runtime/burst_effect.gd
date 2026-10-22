extends RefCounted
## Instant circular query, stable ordered and one hit per target for this instance.
static func contacts(center: Vector2, radius: float, team: int, target_store) -> Array:
	var result: Array = []
	for target in target_store.query(center,radius,team):
		result.append({"target_id":target.id,"position":target.position})
	return result
