extends RefCounted
## TASK-044 transactional 2-slot editor, backed by the exact M1 SpellCompiler.
const Compiler = preload("res://magic/compile/spell_compiler.gd")
const Limits = preload("res://magic/runtime/spell_limits.gd")
const DEFAULT_CAP := 12
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
	return {"schema_version":1,"formula_id":"custom.slot_"+str(index+1),
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
	if manifestation != "form.projectile":
		draft["root"]["modifier_ids"] = []
		draft.erase("on_hit")
	return validate()

func toggle_modifier(rune_id: String) -> Dictionary:
	_record_undo()
	_mark_custom()
	var ids: Array = draft["root"]["modifier_ids"]
	if rune_id in ids:
		ids.erase(rune_id)
	else:
		ids.append(rune_id)
	return validate()

func set_trigger(enabled: bool, payload_essence: String = "essence.lightning") -> Dictionary:
	_record_undo()
	_mark_custom()
	if enabled:
		draft["on_hit"] = {"trigger_id":"trigger.on_hit","payload":{
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
