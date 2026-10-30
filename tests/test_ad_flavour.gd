extends RefCounted
## AD-022: flavour text limits, rune descriptions, rift line shown once per run.
const Merchant = preload("res://world/merchant.gd")
const Controller = preload("res://ui/run_controller.gd")
const RUNES := "res://magic/data/runes_v1.json"

func run(t) -> void:
	var f: Dictionary = Merchant.load_flavour()
	t.check(not f.is_empty(), "AD-022 flavour loads")
	var rift := str(f.get("rift_line", ""))
	t.equal(rift, "Something in the Uncatalogued Ruins has opened a rift, and the Undead it wakes now guard it.", "AD-022 rift line")
	var slice: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://world/data/vertical_slice_v1.json"))
	for room in slice["rooms"]:
		t.check(f["room_names"].has(room["id"]), "AD-022 room name: " + str(room["id"]))
	var lines: Array = f["merchant"]["greetings"] + f["merchant"]["purchase"]
	t.equal(lines.size(), 5, "AD-022 merchant has 5 lines")
	var strings: Array = lines + f["room_names"].values() + [rift, f["merchant"]["title"]]
	var runes: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(RUNES))
	t.equal(runes["runes"].size(), 11, "AD-022 11 runes")
	for r in runes["runes"]:
		var d := str(r["description"])
		t.check(d.length() <= 90 and d.ends_with("."), "AD-022 rune description limit: " + str(r["id"]))
		strings.append(d)
	for line in lines:
		t.check(str(line).length() <= 90, "AD-022 merchant line length")
	for s in strings:
		t.check(not str(s).containsn("battlemage"), "AD-022 no Battlemage")
	var m = Merchant.new({"merchant": {}})
	t.equal(m.greeting(0), f["merchant"]["greetings"][0], "AD-022 greeting deterministic")
	t.equal(m.greeting(-1), f["merchant"]["greetings"][2], "AD-022 greeting posmod")
	t.equal(m.purchase_line(3), f["merchant"]["purchase"][1], "AD-022 purchase line")
	var c = Controller.new()
	t.equal(c.room_display_name("s1_boss"), "Warden's Rift", "AD-022 boss room name")
	t.equal(c.room_display_name("unknown"), "unknown", "AD-022 name fallback")
	t.equal(c.stage_banner(), rift, "AD-022 rift line first call")
	t.equal(c.stage_banner(), "", "AD-022 rift line only once")
	c.free()
