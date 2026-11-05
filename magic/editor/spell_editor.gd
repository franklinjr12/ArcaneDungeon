extends RefCounted
## TASK-044 transactional 2-slot editor, backed by the exact M1 SpellCompiler.
const Compiler = preload("res://magic/compile/spell_compiler.gd")
const Limits = preload("res://magic/runtime/spell_limits.gd")
const DEFAULT_CAP := 12
const ISSUE_KEYS := ["ROOT_FORM_INVALID","TRIGGER_UNKNOWN","RUNE_UNKNOWN","RUNE_WRONG_CATEGORY","RUNE_BUILTIN_FORBIDDEN","UNKNOWN_PARAMETER","PARAMETER_TYPE_INVALID","PARAMETER_OUT_OF_RANGE"]
var run
var registry
var compiler
var slot := 0
var draft: Dictionary = {}
var original: Dictionary = {}
var undo_history: Array = []
var errors: Array = []
var allowed := false
var is_new := false
var max_presets := 3
var complexity_cap := DEFAULT_CAP
## AD-130: optional guided mode (Sigil Desk prelude); empty means normal editing.
var guided_runes: Array = []

func _init(run_state, rune_registry, max_preset_slots: int = 3) -> void:
	run = run_state
	registry = rune_registry
	max_presets = max_preset_slots
	var limits = Limits.new()
	if limits.load_defaults()["ok"]:
		complexity_cap = limits.get_limit("max_complexity")
	compiler = Compiler.new(registry,complexity_cap)

func _starter_draft(index: int) -> Dictionary:
	var essence := "essence.fire"
	for entry in available("essence"):
		if not entry["locked"]:
			essence = entry["id"]
			break
	return {"schema_version":2,"formula_id":"custom.slot_"+str(index+1),
		"display_name":"Custom Spell "+str(index+1),
		"root":{"essence_id":essence,"manifestation_id":"form.projectile","modifier_ids":[],"params":{}}}

func open(index: int) -> Dictionary:
	if index < 0 or index >= max_presets or index > run.formulas.size():
		return {"ok":false,"reason":"SLOT_INVALID"}
	slot = index
	is_new = index == run.formulas.size()
	if is_new:
		original = {}
		draft = _starter_draft(index)
	else:
		original = run.formulas[index].duplicate(true)
		draft = original.duplicate(true)
	undo_history.clear()
	allowed = true
	return validate()

func set_root(essence: String, manifestation: String) -> Dictionary:
	_record_undo()
	_mark_custom()
	draft["root"]["essence_id"] = essence
	draft["root"]["manifestation_id"] = manifestation
	var kept: Array = []
	for id in draft["root"]["modifier_ids"]:
		if not ("projectile_only" in _tags(str(id)) and manifestation != "form.projectile"):
			kept.append(id)
	draft["root"]["modifier_ids"] = kept
	if draft.has("on_hit") and not _trigger_fits(str(draft["on_hit"].get("trigger_id","")),manifestation):
		draft.erase("on_hit")
	return validate()

func _tags(rune_id: String) -> Array:
	var rune = registry.get_rune(rune_id)
	return rune.snapshot()["compatibility_tags"] if rune != null else []

func _trigger_fits(trigger_id: String, form: String) -> bool:
	var tags := _tags(trigger_id)
	if "projectile_only" in tags and form != "form.projectile":
		return false
	if "lasting_only" in tags and form == "form.burst":
		return false
	return true

## {ok, reason_key}: whether a modifier or trigger rune may attach to the current draft form.
func can_attach(rune_id: String) -> Dictionary:
	var form := str(draft["root"]["manifestation_id"])
	var tags := _tags(rune_id)
	if "projectile_only" in tags and form != "form.projectile":
		return {"ok":false,"reason_key":"editor.issue.trigger_projectile_only" if rune_id.begins_with("trigger.") else "editor.issue.modifier_projectile_only"}
	if "lasting_only" in tags and form == "form.burst":
		return {"ok":false,"reason_key":"editor.issue.trigger_needs_lasting"}
	return {"ok":true,"reason_key":""}

## Maps a validator issue to a tr key (specific where the tag matters).
func issue_reason_key(issue: Dictionary) -> String:
	var code := str(issue.get("code",""))
	var path := str(issue.get("path",""))
	match code:
		"MODIFIER_INCOMPATIBLE": return "editor.issue.modifier_projectile_only"
		"TRIGGER_INCOMPATIBLE":
			var trigger_id := str(draft.get("on_hit",{}).get("trigger_id",""))
			return "editor.issue.trigger_needs_lasting" if "lasting_only" in _tags(trigger_id) else "editor.issue.trigger_projectile_only"
		"PAYLOAD_FORM_INVALID": return "editor.issue.payload_must_be_burst"
		"PAYLOAD_MODIFIER_FORBIDDEN": return "editor.issue.payload_no_modifiers"
		"COMPLEXITY_EXCEEDED": return "editor.issue.complexity_exceeded"
		"RUNE_LOCKED": return "editor.issue.rune_locked"
		"MODIFIER_DUPLICATE": return "editor.issue.modifier_duplicate"
	if code != "" and ISSUE_KEYS.has(code):
		return "editor.issue."+code.to_lower()
	return "editor.issue.generic"

func _reason_args(issue: Dictionary) -> Array:
	match str(issue.get("code","")):
		"COMPLEXITY_EXCEEDED":
			var found := RegEx.create_from_string("(\\d+) exceeds cap (\\d+)").search(str(issue.get("message","")))
			if found != null:
				return [int(found.get_string(1)),int(found.get_string(2))]
			return [0,complexity_cap]
		"RUNE_LOCKED":
			return [str(issue.get("message","")).get_slice(": ",1)]
	return []

func toggle_modifier(rune_id: String) -> Dictionary:
	_record_undo()
	_mark_custom()
	var ids: Array = draft["root"]["modifier_ids"]
	if rune_id in ids:
		ids.erase(rune_id)
	else:
		ids.append(rune_id)
	return validate()

func set_trigger(enabled: bool, payload_essence: String = "essence.lightning", trigger_id: String = "trigger.on_hit") -> Dictionary:
	_record_undo()
	_mark_custom()
	if enabled:
		if draft.has("on_hit") and str(draft["on_hit"].get("trigger_id","")) != trigger_id:
			draft["on_hit"]["trigger_id"] = trigger_id
			return validate()
		draft["on_hit"] = {"trigger_id":trigger_id,"payload":{
			"essence_id":payload_essence,"manifestation_id":"form.burst","modifier_ids":[],"params":{}}}
	else:
		draft.erase("on_hit")
	return validate()

func change_payload_essence(essence_id: String) -> Dictionary:
	if not draft.has("on_hit"):
		return {"ok":false,"reason":"ON_HIT_ABSENT"}
	_record_undo()
	_mark_custom()
	draft["on_hit"]["payload"]["essence_id"] = essence_id
	return validate()

func _mark_custom() -> void:
	draft["formula_id"] = "custom.slot_"+str(slot+1)
	draft["display_name"] = "Custom Spell "+str(slot+1)

func _record_undo() -> void:
	undo_history.append(draft.duplicate(true))
	if undo_history.size() > 40:
		undo_history.remove_at(0)

func undo() -> Dictionary:
	if not undo_history.is_empty():
		draft = undo_history.pop_back()
	return validate()

func reset_draft() -> Dictionary:
	_record_undo()
	draft = _starter_draft(slot) if is_new else original.duplicate(true)
	return validate()

func validate() -> Dictionary:
	var result: Dictionary = compiler.compile(draft,run.unlocked)
	errors = result["issues"].duplicate(true)
	for issue in errors:
		issue["reason_key"] = issue_reason_key(issue)
		issue["reason_args"] = _reason_args(issue)
	if result["ok"]:
		var plan: Dictionary = result["compiled_spell"].snapshot()
		return {"ok":true,"issues":[],"mana":plan["mana_cost"],"complexity":plan["complexity"],"complexity_cap":complexity_cap,
			"cooldown":plan["cooldown_ticks"],"summary":str(draft["root"]["essence_id"])+
			" / "+str(draft["root"]["manifestation_id"])+" / "+str(draft["root"]["modifier_ids"])}
	return {"ok":false,"issues":errors.duplicate(true)}

func apply() -> Dictionary:
	if not allowed:
		return {"ok":false,"reason":"EDITOR_CLOSED"}
	var valid: Dictionary = validate()
	if not valid["ok"]:
		return {"ok":false,"reason":"FORMULA_INVALID","issues":errors.duplicate(true)}
	if is_new:
		run.formulas.append(draft.duplicate(true))
		is_new = false
	else:
		run.formulas[slot] = draft.duplicate(true)
	original = draft.duplicate(true)
	allowed = false
	return {"ok":true,"reason":"APPLIED","formula":run.formulas[slot].duplicate(true)}

func cancel() -> void:
	draft = _starter_draft(slot) if is_new else original.duplicate(true)
	undo_history.clear()
	allowed = false

func available(category: String) -> Array:
	var result: Array = []
	for rune in registry.list_by_category(category):
		result.append({"id":rune["id"],"locked":rune["id"] not in run.unlocked,
			"description":rune["description"]})
	return result

## One entry per registry category, in registry order, for the data-driven palette.
func palette() -> Array:
	var result: Array = []
	for category in registry.list_categories():
		result.append({"id":category["id"],"display_key":category["display_key"],
			"label":category["label"],"runes":available(str(category["id"]))})
	return result

func set_guided(runes: Array) -> void:
	guided_runes = runes.duplicate()

## First guided rune missing from the draft, in essence, manifestation, modifier order; "" when none.
func guided_next() -> String:
	var held: Array = []
	if draft.has("root"):
		held = [str(draft["root"]["essence_id"]),str(draft["root"]["manifestation_id"])]
		held.append_array(draft["root"]["modifier_ids"])
	for prefix in ["essence.","form.","mod."]:
		for id in guided_runes:
			if str(id).begins_with(prefix) and str(id) not in held:
				return str(id)
	return ""

func guided_done() -> bool:
	return guided_next() == "" and validate()["ok"]
