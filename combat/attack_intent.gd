extends RefCounted
## Telegraph data is explicit and visualizable independently of enemy sprite code.
var _data: Dictionary = {}
func _init(fields: Dictionary = {}) -> void:
	_data = fields.duplicate(true)
func snapshot() -> Dictionary:
	return _data.duplicate(true)
