extends RefCounted
const RewardGenerator = preload("res://world/reward_generator.gd")
const Artifacts = preload("res://world/artifacts.gd")
var tuning: Dictionary = {}
## TASK-046 deterministic stock; all updates checked atomically.
var config: Dictionary
var stock: Array = []
var bought: Dictionary = {}
var flavour: Dictionary = {}
var _all_ids: Array = []
var _excluded_ids: Array = []
## AD-145: meta-locked artifacts never enter the offer.
var excluded_artifacts: Array = []
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
	_all_ids = all_ids.duplicate()
	_excluded_ids = excluded_ids.duplicate()
	var rerolled: bool = not reroll_available(run)
	var reroll_salt := int(config.get("reroll_salt",0)) if rerolled else 0
	var source: Array = tuning.get("reward_pool",[])
	if source.is_empty():
		source = all_ids
	var available: Array = []
	for id in source:
		if id not in run.unlocked and id not in excluded_ids and id not in available and (all_ids.is_empty() or id in all_ids):
			available.append(id)
	available.sort()
	var random := RandomNumberGenerator.new()
	random.seed = posmod(int(run.seed)*2654435761+int(config.get("seed_salt",0))+reroll_salt,0x7fffffff)
	var count_random := RandomNumberGenerator.new()
	count_random.seed = posmod(int(run.seed)*2654435761+int(config.get("rune_count_salt",0)),0x7fffffff)
	var count := count_random.randi_range(int(config.get("rune_count_min",1)),int(config.get("rune_count_max",1)))
	var picked: Array = RewardGenerator.pick_weighted(available,count,random,tuning)
	stock.clear()
	for selected in picked:
		stock.append({"id":"rune."+selected,"kind":"rune","rune_id":selected,"price":int(config["rune_price"]),
			"label_key":"run.shop.rune_label","label_args":["rune."+selected+".name"],"label":"Rune "+selected})
	stock.append(_upgrade("upgrade.hp","max_hp","max_hp_upgrade","run.shop.hp_label"))
	if config.has("max_mana_upgrade_price"):
		stock.append(_upgrade("upgrade.mana","max_mana","max_mana_upgrade","run.shop.mana_label"))
	if config.has("dash_charge_upgrade_price"):
		stock.append(_upgrade("upgrade.dash","dash_charge","dash_charge_upgrade","run.shop.dash_label"))
	# AD-143: one artifact offer appended after the existing items, seeded separately.
	var artifact_id := _artifact_pick(run,reroll_salt)
	if artifact_id != "":
		var def: Dictionary = Artifacts.definitions()[artifact_id]
		stock.append({"id":"artifact."+artifact_id,"kind":"artifact","artifact_id":artifact_id,
			"price":int(Artifacts.config().get("merchant_artifact_price",0)),
			"desc_key":str(def["desc_key"]),"label_key":"run.shop.artifact_label","label_args":[str(def["name_key"])]})
	bought.clear()
	for id in run.purchases:
		bought[str(id)] = true
	return stock.duplicate(true)

func _upgrade(id: String, stat: String, prefix: String, label_key: String) -> Dictionary:
	var amount := int(config[prefix+"_amount"])
	return {"id":id,"kind":"upgrade","stat":stat,"price":int(config[prefix+"_price"]),"amount":amount,
		"label_key":label_key,"label_args":[amount],"label":id+" +"+str(amount)}

static func reroll_marker(run) -> String:
	var index = run.get("sequence_index")
	return "reroll@%d" % (int(index) if index != null else 0)

func reroll_available(run) -> bool:
	return reroll_marker(run) not in run.purchases

## One paid reroll per visit; the marker lives in run.purchases so a restore rebuilds the same stock.
func reroll(run) -> Dictionary:
	if not reroll_available(run):
		return {"ok":false,"reason":"REROLL_USED"}
	var price := int(config.get("reroll_price",0))
	if run.currency < price:
		return {"ok":false,"reason":"INSUFFICIENT_CURRENCY"}
	run.currency -= price
	run.purchases.append(reroll_marker(run))
	build(run,_all_ids,_excluded_ids)
	return {"ok":true,"kind":"reroll","stock":stock.duplicate(true)}

func _artifact_pick(run, salt: int = 0) -> String:
	if run.artifacts.size() >= Artifacts.max_held():
		return ""
	var candidates: Array = Artifacts.definitions().keys().filter(func(id): return id not in run.artifacts and id not in excluded_artifacts)
	candidates.sort()
	if candidates.is_empty():
		return ""
	var random := RandomNumberGenerator.new()
	random.seed = posmod(int(run.seed)*2654435761+int(Artifacts.config().get("seed_salt",0))+salt,0x7fffffff)
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
		match str(item.get("stat","max_hp")):
			"max_mana":
				run.max_mana_bonus += float(item["amount"])
				run.mana += float(item["amount"])
			"dash_charge":
				run.dash_charges_bonus += int(item["amount"])
			_:
				run.max_hp += float(item["amount"])
				run.hp = minf(run.max_hp,run.hp+float(item["amount"]))
	bought[item["id"]] = true
	run.purchases.append(item["id"])
	return {"ok":true,"kind":item["kind"],"id":item["id"]}
