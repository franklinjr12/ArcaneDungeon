extends RefCounted
## TASK-046 deterministic stock; all updates checked atomically.
var config: Dictionary
var stock: Array = []
var bought: Dictionary = {}
func _init(tuning: Dictionary) -> void:
	config = tuning["merchant"].duplicate(true)

func build(run, all_ids: Array) -> Array:
	var available: Array = []
	for id in all_ids:
		if id not in run.unlocked:
			available.append(id)
	available.sort()
	var selected := ""
	if not available.is_empty():
		var idx := posmod(run.seed*17+47,available.size())
		selected = available[idx]
	stock.clear()
	if not selected.is_empty():
		stock.append({"id":"rune."+selected,"kind":"rune","rune_id":selected,"price":int(config["rune_price"]),"label":"Rune "+selected})
	stock.append({"id":"upgrade.hp","kind":"upgrade","price":int(config["max_hp_upgrade_price"]),"amount":int(config["max_hp_upgrade_amount"]),"label":"Max HP +"+str(config["max_hp_upgrade_amount"])})
	bought.clear()
	for id in run.purchases:
		bought[str(id)] = true
	return stock.duplicate(true)

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
	run.currency -= int(item["price"])
	if item["kind"] == "rune":
		run.unlock(item["rune_id"],0)
	else:
		run.max_hp += float(item["amount"])
		run.hp = minf(run.max_hp,run.hp+float(item["amount"]))
	bought[item["id"]] = true
	run.purchases.append(item["id"])
	return {"ok":true,"kind":item["kind"],"id":item["id"]}
