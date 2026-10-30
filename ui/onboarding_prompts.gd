extends RefCounted
## AD-042: R1 onboarding tips from flavour_v1.json; max one on screen, once per profile, nonblocking.
const FLAVOUR_PATH := "res://world/data/flavour_v1.json"
const TIP_IDS := ["room1", "first_reward", "first_workshop"]
const MAX_CHARS := 90
var tips: Dictionary = {}
var seen: Array = []
var dismissed := false
var current := ""

func _init() -> void:
	if not FileAccess.file_exists(FLAVOUR_PATH):
		return
	var data = JSON.parse_string(FileAccess.get_file_as_string(FLAVOUR_PATH))
	if data is Dictionary and data.get("onboarding") is Dictionary:
		tips = data["onboarding"]

func load_seen(ids: Array) -> void:
	seen = []
	for id in ids:
		if TIP_IDS.has(str(id)) and not seen.has(str(id)):
			seen.append(str(id))

func trigger(id: String) -> String:
	if not TIP_IDS.has(id) or not tips.has(id) or seen.has(id) or dismissed:
		return ""
	seen.append(id)
	current = id
	return str(tips[id])

func text() -> String:
	if dismissed or current.is_empty():
		return ""
	return str(tips.get(current, ""))

func dismiss() -> void:
	dismissed = true
	current = ""

func reopen() -> void:
	dismissed = false

func message(_context: String) -> String:
	return text()
