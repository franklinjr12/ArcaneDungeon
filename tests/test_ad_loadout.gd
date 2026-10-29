extends RefCounted
## AD-012: 4-slot loadout, locked basic bolt in slot 1, starter presets, cast_rejected trace.
const Compiler = preload("res://magic/compile/spell_compiler.gd")
const Runner = preload("res://magic/runtime/spell_runner.gd")

func _formula(id: String) -> Dictionary:
	var data: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://magic/data/sandbox_samples_v1.json"))
	for entry in data["formulas"]:
		if entry["formula_id"] == id:
			return entry
	return {}

func _rejections(runner, reason: String) -> int:
	var count := 0
	for event in JSON.parse_string(runner.trace_json()) if typeof(JSON.parse_string(runner.trace_json())) == TYPE_ARRAY else JSON.parse_string(runner.trace_json()).get("events",[]):
		if event.get("type","") == "cast_rejected" and event.get("reason","") == reason:
			count += 1
	return count

func _runner(t):
	var runner = Runner.new(20261029)
	var result: Dictionary = runner.equip_starter_loadout([_formula("sample.fire_shot"),t.fixture("split_water.json")])
	t.check(result["ok"],"AD-012 starter loadout equips")
	return runner

func run(t) -> void:
	var runner = _runner(t)
	var loadout = runner.loadout
	var definition: Dictionary = Compiler.load_builtin_definition()["definition"]
	# (a) layout
	t.equal(loadout.slots.size(),4,"AD-012 exactly 4 slots")
	t.equal(loadout.slots[0]["formula_id"],"builtin.basic_bolt","AD-012 slot 1 basic bolt")
	t.check(loadout.is_locked(0),"AD-012 slot 1 locked")
	t.equal(loadout.slots[1]["formula_id"],"sample.fire_shot","AD-012 slot 2 fire shot")
	t.equal(loadout.slots[2]["formula_id"],"sample.split_water","AD-012 slot 3 split water")
	t.equal(loadout.check_slot(3),"SLOT_EMPTY","AD-012 slot 4 empty")
	# (b) lock
	t.equal(loadout.equip(0,_formula("sample.fire_shot"))["reason"],"SLOT_LOCKED","AD-012 locked slot rejects equip")
	t.equal(loadout.equip_builtin(0,definition)["reason"],"SLOT_LOCKED","AD-012 locked slot rejects equip_builtin")
	t.equal(loadout.clear(0)["reason"],"SLOT_LOCKED","AD-012 locked slot rejects clear")
	t.equal(loadout.install_locked_builtin(0,definition)["reason"],"SLOT_LOCKED","AD-012 locked slot rejects reinstall")
	t.equal(loadout.slots[0]["formula_id"],"builtin.basic_bolt","AD-012 slot 1 unchanged after attempts")
	t.check(loadout.clear(1)["ok"] and loadout.check_slot(1) == "SLOT_EMPTY","AD-012 unlocked slot clears")
	# (c) empty slot
	var before: float = runner.mana
	var empty: Dictionary = runner.try_cast(3,runner.actor.position,Vector2.RIGHT)
	t.check(not empty["accepted"] and empty["reason"] == "SLOT_EMPTY","AD-012 empty slot no cast")
	t.equal(runner.mana,before,"AD-012 empty slot costs no mana")
	t.equal(_rejections(runner,"empty_slot"),1,"AD-012 empty_slot cast_rejected traced")
	# (d) per-slot cooldown independence
	runner = _runner(t)
	t.check(runner.try_cast(0,runner.actor.position,Vector2.RIGHT)["accepted"],"AD-012 slot 1 casts")
	var again: Dictionary = runner.try_cast(0,runner.actor.position,Vector2.RIGHT)
	t.equal(again["reason"],"COOLDOWN","AD-012 slot 1 on cooldown")
	t.equal(_rejections(runner,"cooldown"),1,"AD-012 cooldown cast_rejected traced")
	t.check(runner.try_cast(1,runner.actor.position,Vector2.RIGHT)["accepted"],"AD-012 slot 2 unaffected by slot 1 cooldown")
	t.equal(runner.loadout.check_slot(2),"READY","AD-012 slot 3 unaffected")
	# (e) mana paid once per cast, including split
	runner = _runner(t)
	var cost: int = int(runner.loadout.get_plan(2).snapshot()["mana_cost"])
	before = runner.mana
	t.check(runner.try_cast(2,runner.actor.position,Vector2.RIGHT)["accepted"],"AD-012 split water casts")
	t.equal(before-runner.mana,float(cost),"AD-012 mana paid once per manual cast")
	# (f) no mana
	runner = _runner(t)
	runner.mana = 0.0
	var dry: Dictionary = runner.try_cast(1,runner.actor.position,Vector2.RIGHT)
	t.equal(dry["reason"],"INSUFFICIENT_MANA","AD-012 no mana rejects")
	t.equal(_rejections(runner,"no_mana"),1,"AD-012 no_mana cast_rejected traced")
