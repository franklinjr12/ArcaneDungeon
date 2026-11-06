extends RefCounted
const RewardGenerator = preload("res://world/reward_generator.gd")
const Artifacts = preload("res://world/artifacts.gd")
var tuning: Dictionary = {}
## TASK-046 deterministic stock; all updates checked atomically.
var config: Dictionary
var stock: Array = []
var bought: Dictionary = {}
var flavour: Dictionary = {}
const FLAVOUR_PATH := "res://world/data/flavour_v1.json"

static func load_flavour() -> Dictionary:
	var file := FileAccess.open(FLAVOUR_PATH, FileAccess.READ)
	if file == null:
		return {}
	var parsed = JSON.parse_string(file.get_as_text())
	return parsed if parsed is Dictionary else {}

func _init(tuning: Dictionary) -> void:
	self.tuning = tuning.duplicate(true)
	config = tuning["merchant"].duplicate(true)
	flavour = load_flavour()

func _line(key: String, index: int) -> String:
	var lines: Array = flavour.get("merchant", {}).get(key, [])
	return "" if lines.is_empty() else str(lines[posmod(index, lines.size())])

func greeting(run_seed: int) -> String:
	return _line("greetings", run_seed)

func purchase_line(count: int) -> String:
	return _line("purchase", count)

func build(run, all_ids: Array, excluded_ids: Array = []) -> Array:
	var source: Array = tuning.get("reward_pool",[])
	if source.is_empty():
		source = all_ids
	var available: Array = []
	for id in source:
		if id not in run.unlocked and id not in excluded_ids and id not in available and (all_ids.is_empty() or id in all_ids):
			available.append(id)
	available.sort()
	var random := RandomNumberGenerator.new()
	random.seed = posmod(int(run.seed)*2654435761+int(config.get("seed_salt",0)),0x7fffffff)
	var picked: Array = RewardGenerator.pick_weighted(available,1,random,tuning)
	stock.clear()
	if not picked.is_empty():
		var selected: String = picked[0]
		stock.append({"id":"rune."+selected,"kind":"rune","rune_id":selected,"price":int(config["rune_price"]),
			"label_key":"run.shop.rune_label","label_args":["rune."+selected+".name"],"label":"Rune "+selected})
	stock.append({"id":"upgrade.hp","kind":"upgrade","price":int(config["max_hp_upgrade_price"]),"amount":int(config["max_hp_upgrade_amount"]),
		"label_key":"run.shop.hp_label","label_args":[int(config["max_hp_upgrade_amount"])],"label":"Max HP +"+str(config["max_hp_upgrade_amount"])})
	# AD-143: one artifact offer appended after the existing items, seeded separately.
	var artifact_id := _artifact_pick(run)
	if artifact_id != "":
		var def: Dictionary = Artifacts.definitions()[artifact_id]
		stock.append({"id":"artifact."+artifact_id,"kind":"artifact","artifact_id":artifact_id,
			"price":int(Artifacts.config().get("merchant_artifact_price",0)),
			"desc_key":str(def["desc_key"]),"label_key":"run.shop.artifact_label","label_args":[str(def["name_key"])]})
	bought.clear()
	for id in run.purchases:
		bought[str(id)] = true
	return stock.duplicate(true)

func _artifact_pick(run) -> String:
	if run.artifacts.size() >= Artifacts.max_held():
		return ""
	var candidates: Array = Artifacts.definitions().keys().filter(func(id): return id not in run.artifacts)
	candidates.sort()
	if candidates.is_empty():
		return ""
	var random := RandomNumberGenerator.new()
	random.seed = posmod(int(run.seed)*2654435761+int(Artifacts.config().get("seed_salt",0)),0x7fffffff)
	return str(candidates[random.randi() % candidates.size()])

## Localised stock label; label_args entries that are tr keys are translated.
static func item_label(item: Dictionary) -> String:
	if not item.has("label_key"):
		return str(item.get("label",""))
	var args: Array = []
	for arg in item.get("label_args",[]):
		args.append(TranslationServer.translate(arg) if arg is String and (arg.begins_with("rune.") or arg.begins_with("artifact.")) else arg)
	return TranslationServer.translate(str(item["label_key"])) % args

func purchase(index: int, run) -> Dictionary:
	if index < 0 or index >= stock.size():
		return {"ok":false,"reason":"STOCK_INVALID"}
	var item: Dictionary = stock[index]
	if bought.has(item["id"]):
		return {"ok":false,"reason":"ALREADY_BOUGHT"}
	if run.currency < int(item["price"]):
		return {"ok":false,"reason":"INSUFFICIENT_CURRENCY"}
	if item["kind"] == "rune" and item["rune_id"] in run.unlocked:
		return {"ok":false,"reason":"ALREADY_UNLOCKED"}
	if item["kind"] == "artifact":
		var held := Artifacts.new(run.artifacts)
		if not held.can_add(str(item["artifact_id"])):
			return {"ok":false,"reason":"ARTIFACT_LIMIT" if held.ids().size() >= Artifacts.max_held() else "ARTIFACT_DUPLICATE"}
	run.currency -= int(item["price"])
	if item["kind"] == "rune":
		run.unlock(item["rune_id"],0)
	elif item["kind"] == "artifact":
		run.add_artifact(str(item["artifact_id"]))
	else:
		run.max_hp += float(item["amount"])
		run.hp = minf(run.max_hp,run.hp+float(item["amount"]))
	bought[item["id"]] = true
	run.purchases.append(item["id"])
	return {"ok":true,"kind":item["kind"],"id":item["id"]}
