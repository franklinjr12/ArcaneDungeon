extends RefCounted
const InputActions = preload("res://ui/input_actions.gd")
## AD-042: R1 onboarding tips from flavour_v1.json; max one on screen, once per profile, nonblocking.
const FLAVOUR_PATH := "res://world/data/flavour_v1.json"
const TIP_IDS := ["room1", "first_reward", "first_workshop", "telegraph", "spells_are_runes"]
const MAX_CHARS := 90
# AD-084: workshop_empty_slot wording is proposed (the editor uses rune pickers, not drag-and-drop).
const HINT_IDS := ["workshop_empty_slot", "test_on_dummy", "wet_try_lightning"]
const HINT_INDEX := {"workshop_empty_slot": 0, "test_on_dummy": 1, "wet_try_lightning": 2}
var tips: Dictionary = {}
var _templates: Dictionary = {}
## AD-185: Settings "Tips" toggle; when false nothing shows and nothing is marked seen.
var enabled := true
var tip_seconds: Dictionary = {}
var _now_ms := 0
var _deadline_ms := 0
var _interrupted := ""
var seen: Array = []
var dismissed := false
var current := ""
var pending: Array = []
var arc_seen := false
var shown_count := 0
var shown_log: Array = []
## AD-130: the Sigil Desk prelude teaches the workshop steps itself, so generic hints stay quiet.
var prelude_active := false

func _init() -> void:
	if not FileAccess.file_exists(FLAVOUR_PATH):
		return
	var data = JSON.parse_string(FileAccess.get_file_as_string(FLAVOUR_PATH))
	if data is Dictionary and data.get("onboarding") is Dictionary:
		tips = data["onboarding"]
	if data is Dictionary and data.get("onboarding_seconds") is Dictionary:
		tip_seconds = data["onboarding_seconds"]
	for id in tips.keys():
		_templates[id] = TranslationServer.translate(str(tips[id]))
	for id in HINT_IDS:
		_templates[id] = TranslationServer.translate("onboarding." + id)
	refresh_bindings()

## Re-expands {move}/{cast}/{dash} from the live InputMap (call after rebinding).
func refresh_bindings() -> void:
	var move: Array = []
	for action in ["move_up", "move_left", "move_down", "move_right"]:
		move.append(InputActions.action_text(action))
	var values := {"move": "/".join(move), "cast": InputActions.action_text("cast_slot_1"), "dash": InputActions.action_text("dash")}
	for id in _templates.keys():
		tips[id] = str(_templates[id]).format(values)

func load_seen(ids: Array) -> void:
	seen = []
	for id in ids:
		if (TIP_IDS.has(str(id)) or HINT_IDS.has(str(id))) and not seen.has(str(id)):
			seen.append(str(id))
	arc_seen = seen.has("wet_try_lightning")

func trigger(id: String) -> String:
	if not enabled:
		return ""
	if prelude_active and id == "first_workshop":
		return ""
	if not (TIP_IDS.has(id) or HINT_IDS.has(id)) or not tips.has(id) or seen.has(id) or dismissed:
		return ""
	seen.append(id)
	if tip_seconds.has(id):
		_interrupted = current if current != id else ""
		_deadline_ms = _now_ms + int(float(tip_seconds[id]) * 1000.0)
	current = id
	shown_count += 1
	shown_log.append(id)
	return str(tips[id])

func text() -> String:
	if not enabled or dismissed or current.is_empty():
		return ""
	return str(tips.get(current, ""))

func dismiss() -> void:
	dismissed = true
	current = ""
	_interrupted = ""
	_deadline_ms = 0

## Timed tips (tip_seconds) give way to the tip they interrupted once their deadline passes.
func tick(now_ms: int) -> void:
	_now_ms = now_ms
	if _deadline_ms > 0 and now_ms >= _deadline_ms:
		_deadline_ms = 0
		current = _interrupted
		_interrupted = ""

func is_timed_active() -> bool:
	return _deadline_ms > 0 and tip_seconds.has(current)

func note_telegraph() -> void:
	if enabled:
		_queue("telegraph")

func reopen() -> void:
	dismissed = false

func _queue(id: String) -> void:
	if not seen.has(id) and not pending.has(id):
		pending.append(id)

func _drop(id: String) -> void:
	pending.erase(id)
	if current == id:
		current = ""

func note_workshop(empty_slots: int) -> void:
	if prelude_active:
		return
	if empty_slots > 0:
		_queue("workshop_empty_slot")
	else:
		pending.erase("workshop_empty_slot")

func note_valid_edit() -> void:
	if prelude_active:
		return
	_queue("test_on_dummy")

## The desk taught the empty-slot and dummy steps; returns the ids newly marked seen for persistence.
func note_prelude_done() -> Array:
	var added: Array = []
	for id in ["workshop_empty_slot","test_on_dummy"]:
		_drop(id)
		if not seen.has(id):
			seen.append(id)
			added.append(id)
	return added

func note_test_cast() -> void:
	_drop("test_on_dummy")

func note_wet_kill() -> void:
	if not arc_seen:
		_queue("wet_try_lightning")

## Returns true when `seen` changed so the caller can persist.
func note_arc() -> bool:
	arc_seen = true
	_drop("wet_try_lightning")
	if seen.has("wet_try_lightning"):
		return false
	seen.append("wet_try_lightning")
	return true

func next_hint() -> String:
	if not enabled or dismissed or pending.is_empty():
		return ""
	return str(pending[0])
