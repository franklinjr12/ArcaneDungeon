extends RefCounted
## TASK-039: serialized run progression, never runtime entities, queues or enemies.
const VERSION := 1
const Difficulty = preload("res://game/core/difficulty.gd")
const Artifacts = preload("res://world/artifacts.gd")
var seed := 0
var sequence_index := 0
var hp := 150.0
var mana := 120.0
var max_hp := 150.0
var currency := 0
var unlocked: Array = []
var formulas: Array = []
var collected: Array = []
var purchases: Array = []
var edit_seconds := 0.0
var edit_count := 0
var quick_edit_count := 0
var artifacts: Array = []
## AD-144 merchant upgrades, run-persistent.
var max_mana_bonus := 0.0
var dash_charges_bonus := 0

func initialize(run_seed: int, config: Dictionary, formulas_by_id: Dictionary) -> void:
	seed = run_seed
	sequence_index = 0
	hp = Difficulty.scale_f(150.0,"player_hp")
	mana = Difficulty.scale_f(120.0,"player_mana")
	max_hp = hp
	currency = int(config["initial_currency"])
	unlocked = config["initial_unlocked"].duplicate(true)
	formulas.clear()
	for id in config["initial_formulas"]:
		formulas.append(formulas_by_id[id].duplicate(true))
	collected.clear()
	purchases.clear()
	edit_seconds = 0
	edit_count = 0
	quick_edit_count = 0
	artifacts.clear()
	max_mana_bonus = 0.0
	dash_charges_bonus = 0

func snapshot() -> Dictionary:
	return {"schema_version":VERSION,"seed":seed,"sequence_index":sequence_index,
		"hp":hp,"mana":mana,"max_hp":max_hp,"currency":currency,"unlocked":unlocked.duplicate(true),
		"formulas":formulas.duplicate(true),"collected":collected.duplicate(true),
		"purchases":purchases.duplicate(true),"edit_seconds":edit_seconds,
		"edit_count":edit_count,"quick_edit_count":quick_edit_count,"artifacts":artifacts.duplicate(true),
		"max_mana_bonus":max_mana_bonus,"dash_charges_bonus":dash_charges_bonus}

func restore(data: Variant, registry, max_rooms: int) -> Dictionary:
	if typeof(data) != TYPE_DICTIONARY:
		return {"ok":false,"reason":"RUN_NOT_OBJECT"}
	for key in ["schema_version","seed","sequence_index","hp","mana","max_hp","currency","unlocked","formulas","collected","purchases","edit_seconds","edit_count","quick_edit_count"]:
		if not data.has(key):
			return {"ok":false,"reason":"RUN_MISSING_"+key}
	if data["schema_version"] != VERSION or not _whole_number(data["seed"]) or not _whole_number(data["sequence_index"]):
		return {"ok":false,"reason":"RUN_VERSION_OR_INDEX_INVALID"}
	if int(data["sequence_index"]) < 0 or int(data["sequence_index"]) >= max_rooms:
		return {"ok":false,"reason":"RUN_SEQUENCE_INVALID"}
	if typeof(data["unlocked"]) != TYPE_ARRAY or typeof(data["formulas"]) != TYPE_ARRAY or (data["formulas"].size() < 1 or data["formulas"].size() > 3):
		return {"ok":false,"reason":"RUN_INVENTORY_INVALID"}
	if typeof(data["collected"]) != TYPE_ARRAY or typeof(data["purchases"]) != TYPE_ARRAY:
		return {"ok":false,"reason":"RUN_HISTORY_INVALID"}
	for key in ["hp","max_hp","mana","currency","edit_seconds","edit_count","quick_edit_count"]:
		if typeof(data[key]) not in [TYPE_INT,TYPE_FLOAT] or float(data[key]) < 0:
			return {"ok":false,"reason":"RUN_VALUE_INVALID_"+key}
	for key in ["currency","edit_count","quick_edit_count"]:
		if not _whole_number(data[key]):
			return {"ok":false,"reason":"RUN_INTEGER_INVALID_"+key}
	# AD-144: optional so saves from before merchant upgrades still load.
	for key in ["max_mana_bonus","dash_charges_bonus"]:
		if data.has(key) and (typeof(data[key]) not in [TYPE_INT,TYPE_FLOAT] or not is_finite(float(data[key])) or float(data[key]) < 0):
			return {"ok":false,"reason":"RUN_UPGRADES_INVALID"}
	if data.has("dash_charges_bonus") and not _whole_number(data["dash_charges_bonus"]):
		return {"ok":false,"reason":"RUN_UPGRADES_INVALID"}
	var mana_bonus := float(data.get("max_mana_bonus",0.0))
	if float(data["max_hp"]) < 1.0 or float(data["hp"]) > float(data["max_hp"]) or float(data["mana"]) > Difficulty.scale_f(120.0,"player_mana")+mana_bonus:
		return {"ok":false,"reason":"RUN_RESOURCES_INVALID"}
	# AD-143: optional so saves from before artifacts still load.
	if data.has("artifacts"):
		if typeof(data["artifacts"]) != TYPE_ARRAY or data["artifacts"].size() > Artifacts.max_held():
			return {"ok":false,"reason":"RUN_ARTIFACTS_INVALID"}
		var seen: Array = []
		for artifact in data["artifacts"]:
			if typeof(artifact) != TYPE_STRING or not Artifacts.is_known(artifact) or artifact in seen:
				return {"ok":false,"reason":"RUN_ARTIFACTS_INVALID"}
			seen.append(artifact)
	var ids: Array = registry.get_ids()
	for rune in data["unlocked"]:
		if typeof(rune) != TYPE_STRING or rune not in ids:
			return {"ok":false,"reason":"RUN_RUNE_INVALID"}
	var compiler = preload("res://magic/compile/spell_compiler.gd").new(registry,_max_complexity())
	for formula in data["formulas"]:
		if not compiler.compile(formula,data["unlocked"])["ok"]:
			return {"ok":false,"reason":"RUN_FORMULA_INVALID"}
	seed = int(data["seed"])
	sequence_index = int(data["sequence_index"])
	hp = float(data["hp"])
	mana = float(data["mana"])
	max_hp = float(data["max_hp"])
	currency = int(data["currency"])
	unlocked = data["unlocked"].duplicate(true)
	formulas = data["formulas"].duplicate(true)
	collected = data["collected"].duplicate(true)
	purchases = data["purchases"].duplicate(true)
	edit_seconds = float(data["edit_seconds"])
	edit_count = int(data["edit_count"])
	quick_edit_count = int(data["quick_edit_count"])
	artifacts = data["artifacts"].duplicate(true) if data.has("artifacts") else []
	max_mana_bonus = mana_bonus
	dash_charges_bonus = int(data.get("dash_charges_bonus",0))
	return {"ok":true,"reason":"LOADED"}

func add_artifact(id: String) -> Dictionary:
	var holder = Artifacts.new(artifacts)
	var outcome: Dictionary = holder.add(id)
	if outcome["ok"]:
		artifacts = holder.ids()
	return outcome

func unlock(rune_id: String, duplicate_currency: int) -> Dictionary:
	if rune_id in unlocked:
		currency += duplicate_currency
		return {"ok":true,"kind":"duplicate","currency":duplicate_currency}
	unlocked.append(rune_id)
	unlocked.sort()
	return {"ok":true,"kind":"unlock","rune":rune_id}

static func _whole_number(value: Variant) -> bool:
	return typeof(value) in [TYPE_INT,TYPE_FLOAT] and is_finite(float(value)) and floor(float(value))==float(value)

func _max_complexity() -> int:
	var limits = preload("res://magic/runtime/spell_limits.gd").new()
	return limits.get_limit("max_complexity") if limits.load_defaults()["ok"] else 12
