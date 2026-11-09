extends RefCounted
## TASK-024 / AD-012: 4 manual slots (slot 0 may be locked), independent cooldown and immutable compiler plans.
const Compiler = preload("res://magic/compile/spell_compiler.gd")
const SLOT_COUNT := 4
var registry
var compiler
var unlocked: Array = []
var slots: Array = []
var allow_edit := true
## Validity verdict per slot index (FORMULA_INVALID / FORMULA_STALE / OK); see check_slot for the validity conditions.
var _check_memo: Dictionary = {}

func _init(rune_registry, accessible: Array, max_complexity: int = 12) -> void:
	registry = rune_registry
	compiler = Compiler.new(registry,max_complexity)
	unlocked = accessible.duplicate()
	slots = []
	for i in SLOT_COUNT:
		slots.append({"formula_id":"","formula":{},"compiled":null,"builtin_definition":{},"cooldown":0,"locked":false})

func equip(index: int, formula: Variant) -> Dictionary:
	if not allow_edit:
		return {"ok":false,"reason":"EDIT_CONTEXT_BLOCKED","issues":[]}
	if index < 0 or index >= slots.size():
		return {"ok":false,"reason":"SLOT_INVALID","issues":[]}
	if slots[index]["locked"]:
		return {"ok":false,"reason":"SLOT_LOCKED","issues":[]}
	var result: Dictionary = compiler.compile(formula,unlocked)
	if not result["ok"]:
		return {"ok":false,"reason":"FORMULA_INVALID","issues":result["issues"]}
	slots[index]["formula_id"] = formula["formula_id"]
	slots[index]["formula"] = formula.duplicate(true)
	slots[index]["compiled"] = result["compiled_spell"]
	slots[index]["builtin_definition"] = {}
	# Preserve existing cooldown to prevent editing to reset cast cadence.
	return {"ok":true,"reason":"EQUIPPED","issues":[]}

func equip_builtin(index: int, definition: Dictionary) -> Dictionary:
	if not allow_edit:
		return {"ok":false,"reason":"EDIT_CONTEXT_BLOCKED","issues":[]}
	if index < 0 or index >= slots.size():
		return {"ok":false,"reason":"SLOT_INVALID","issues":[]}
	if slots[index]["locked"]:
		return {"ok":false,"reason":"SLOT_LOCKED","issues":[]}
	var result: Dictionary = compiler.compile_builtin(definition)
	if not result["ok"]:
		return {"ok":false,"reason":"FORMULA_INVALID","issues":result["issues"]}
	var formula: Dictionary = definition["formula"]
	slots[index]["formula_id"] = formula["formula_id"]
	slots[index]["formula"] = formula.duplicate(true)
	slots[index]["compiled"] = result["compiled_spell"]
	slots[index]["builtin_definition"] = definition.duplicate(true)
	return {"ok":true,"reason":"EQUIPPED","issues":[]}

func install_locked_builtin(index: int, definition: Dictionary) -> Dictionary:
	var result: Dictionary = equip_builtin(index,definition)
	if result["ok"]:
		slots[index]["locked"] = true
	return result

func clear(index: int) -> Dictionary:
	if not allow_edit:
		return {"ok":false,"reason":"EDIT_CONTEXT_BLOCKED","issues":[]}
	if index < 0 or index >= slots.size():
		return {"ok":false,"reason":"SLOT_INVALID","issues":[]}
	if slots[index]["locked"]:
		return {"ok":false,"reason":"SLOT_LOCKED","issues":[]}
	slots[index]["formula_id"] = ""
	slots[index]["formula"] = {}
	slots[index]["compiled"] = null
	slots[index]["builtin_definition"] = {}
	return {"ok":true,"reason":"CLEARED","issues":[]}

func is_locked(index: int) -> bool:
	return index >= 0 and index < slots.size() and bool(slots[index]["locked"])

func get_plan(index: int):
	if index < 0 or index >= slots.size():
		return null
	return slots[index]["compiled"]

func check_slot(index: int) -> String:
	if index < 0 or index >= slots.size():
		return "SLOT_INVALID"
	if slots[index]["compiled"] == null:
		return "SLOT_EMPTY"
	var verdict := _validity(index)
	if verdict != "OK":
		return verdict
	if slots[index]["cooldown"] > 0:
		return "COOLDOWN"
	return "READY"

## Compiler verdict for a filled slot, memoized while the compiled plan, formula, builtin definition, unlocked list and registry revision are unchanged.
func _validity(index: int) -> String:
	var slot: Dictionary = slots[index]
	var memo = _check_memo.get(index)
	if memo != null and is_same(memo["compiled"],slot["compiled"]) and memo["formula"] == slot["formula"] \
			and memo["builtin_definition"] == slot["builtin_definition"] and memo["unlocked"] == unlocked \
			and memo["revision"] == registry.revision:
		return memo["verdict"]
	var check: Dictionary
	if not slot["builtin_definition"].is_empty():
		check = compiler.compile_builtin(slot["builtin_definition"])
	else:
		check = compiler.compile(slot["formula"],unlocked)
	var verdict := "OK"
	if not check["ok"]:
		verdict = "FORMULA_INVALID"
	elif check["compiled_spell"].snapshot()["registry_revision"] != slot["compiled"].snapshot()["registry_revision"]:
		verdict = "FORMULA_STALE"
	_check_memo[index] = {"compiled":slot["compiled"],"formula":slot["formula"].duplicate(true),
		"builtin_definition":slot["builtin_definition"].duplicate(true),"unlocked":unlocked.duplicate(),
		"revision":registry.revision,"verdict":verdict}
	return verdict

func cooldown_tick() -> void:
	for slot in slots:
		slot["cooldown"] = maxi(0,int(slot["cooldown"])-1)

func preview(index: int) -> Dictionary:
	var plan = get_plan(index)
	if plan == null:
		return {}
	var data: Dictionary = plan.snapshot()
	return {"mana":data["mana_cost"],"cooldown":data["cooldown_ticks"],"complexity":data["complexity"],"formula_id":data["formula_id"]}
