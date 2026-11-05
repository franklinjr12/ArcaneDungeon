extends RefCounted
## AD-129: spell language schema v2 (rune categories, param blocks, formula migration v1->v2).
const Registry = preload("res://magic/data/rune_registry.gd")
const Codec = preload("res://magic/compile/spell_codec.gd")
const Validator = preload("res://magic/compile/spell_validator.gd")
const Compiler = preload("res://magic/compile/spell_compiler.gd")
const LEGACY := "res://tests/fixtures/runes_v1_legacy.json"
const Flow = preload("res://world/run_flow.gd")
const CATEGORY_IDS := ["essence", "form", "modifier", "trigger"]

func run(t) -> void:
	var registry = Registry.new()
	t.check(registry.load_seed()["ok"], "AD-129 v2 seed loads")
	var categories: Array = registry.list_categories()
	var ids: Array = []
	for c in categories:
		ids.append(c["id"])
		t.equal(c["display_key"], "rune_category." + str(c["id"]), "AD-129 category display key " + str(c["id"]))
	t.equal(ids, CATEGORY_IDS, "AD-129 category order")
	var legacy: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(LEGACY))
	var legacy_ids: Array = []
	for entry in legacy["runes"]:
		if not bool(entry.get("builtin", false)):
			legacy_ids.append(entry["id"])
	legacy_ids.sort()
	t.equal(registry.get_ids(), legacy_ids, "AD-129 same 10 collectible rune ids")
	t.equal(registry.get_ids().size(), 10, "AD-129 ten collectible runes")
	t.equal(registry.get_all_ids().size(), 11, "AD-129 eleven runes incl. builtin")
	var migrated = Registry.new()
	t.check(migrated.load_seed(LEGACY)["ok"], "AD-129 legacy v1 rune file loads via migration")
	for entry in legacy["runes"]:
		var snap: Dictionary = registry.get_rune(entry["id"]).snapshot()
		var old: Dictionary = migrated.get_rune(entry["id"]).snapshot()
		for key in ["params", "mana_cost", "cooldown_ticks", "complexity_weight", "category"]:
			t.equal(snap[key], entry[key], "AD-129 %s %s equals legacy" % [entry["id"], key])
		t.equal(snap, old, "AD-129 v2 and migrated v1 snapshots identical " + str(entry["id"]))
		t.equal(snap["schema_version"], 2, "AD-129 rune snapshot schema 2 " + str(entry["id"]))
	_registry_capacity(t)
	_formula_migration(t, registry)

func _synthetic(count: int) -> Array:
	var runes: Array = []
	for i in count:
		var category: String = CATEGORY_IDS[i % 4]
		runes.append({"id": "%s.synthetic_%d" % [category, i], "category": category, "schema_version": 2,
			"param_blocks": ["shared"], "params": {"extra": {"type": "int", "default": i, "min": 0, "max": 99}},
			"compatibility_tags": ["synthetic"], "complexity_weight": 1, "mana_cost": 1, "cooldown_ticks": 1,
			"description": "Synthetic.", "display_key": "synthetic.%d" % i})
	return runes

func _registry_capacity(t) -> void:
	var cats: Array = []
	for i in CATEGORY_IDS.size():
		cats.append({"id": CATEGORY_IDS[i], "display_key": "rune_category." + CATEGORY_IDS[i], "label": CATEGORY_IDS[i], "order": i})
	var blocks := {"shared": {"power": {"type": "float", "default": 1.0, "min": 0.0, "max": 5.0}}}
	var big = Registry.new()
	var loaded: Dictionary = big.replace_all(_synthetic(32), cats, blocks)
	t.check(loaded["ok"], "AD-129 32 synthetic runes load: " + str(loaded["issues"]))
	t.equal(big.get_ids().size(), 32, "AD-129 registry holds 32 runes")
	var listed := 0
	for id in CATEGORY_IDS:
		listed += big.list_by_category(id).size()
	t.equal(listed, 32, "AD-129 list_by_category returns all 32")
	t.equal(big.get_rune("form.synthetic_1").snapshot()["params"]["power"]["default"], 1.0, "AD-129 block param resolved")
	t.equal(big.get_rune("form.synthetic_1").snapshot()["params"]["extra"]["default"], 1, "AD-129 own param kept")
	var before: int = big.revision
	var unknown_block := _synthetic(4)
	unknown_block[2]["param_blocks"] = ["missing_block"]
	var rejected: Dictionary = big.replace_all(unknown_block, cats, blocks)
	t.contains_issue(rejected["issues"], "REGISTRY_PARAM_BLOCK_UNKNOWN", "AD-129 unknown param block rejected")
	t.equal(big.revision, before, "AD-129 rejected load leaves registry untouched")
	var unknown_category := _synthetic(4)
	unknown_category[1]["category"] = "sigil"
	t.contains_issue(big.replace_all(unknown_category, cats, blocks)["issues"], "RUNE_CATEGORY_INVALID", "AD-129 unknown category rejected")
	var overlay := _synthetic(4)
	overlay[0]["params"]["power"] = {"default": 2.0}
	big.replace_all(overlay, cats, blocks)
	var merged: Dictionary = big.get_rune("essence.synthetic_0").snapshot()["params"]["power"]
	t.equal([merged["default"], merged["max"]], [2.0, 5.0], "AD-129 field-level override merges over block")

func _formula_migration(t, registry) -> void:
	var formulas: Array = []
	for name in ["fire_shot.json", "split_water.json", "spark_burst.json"]:
		formulas.append(t.fixture(name))
	for path in ["res://tests/fixtures/m1_samples.json", "res://magic/data/sandbox_samples_v1.json"]:
		formulas.append_array(JSON.parse_string(FileAccess.get_file_as_string(path))["formulas"])
	var validator = Validator.new(registry)
	var compiler = Compiler.new(registry)
	var unlocked: Array = registry.get_ids()
	t.check(formulas.size() >= 9, "AD-129 formula fixtures collected")
	for v1 in formulas:
		if v1 == null:
			continue
		var label: String = str(v1["formula_id"])
		t.equal(int(v1["schema_version"]), 1, "AD-129 fixture is v1 " + label)
		var decoded: Dictionary = Codec.decode(JSON.stringify(v1))
		t.check(decoded["ok"], "AD-129 v1 decodes " + label)
		if not decoded["ok"]:
			continue
		t.equal(decoded["from_version"], 1, "AD-129 from_version 1 " + label)
		t.equal(int(decoded["formula"]["schema_version"]), 2, "AD-129 migrated to v2 " + label)
		var v2: Dictionary = decoded["formula"]
		var rest_old: Dictionary = v1.duplicate(true)
		var rest_new: Dictionary = v2.duplicate(true)
		rest_old.erase("schema_version")
		rest_new.erase("schema_version")
		t.equal(JSON.stringify(rest_new), JSON.stringify(rest_old), "AD-129 migration changes only schema_version " + label)
		t.check(validator.validate(v2, unlocked)["ok"], "AD-129 migrated formula validates " + label)
		t.check(validator.validate(v1, unlocked)["ok"], "AD-129 v1 dict still validates " + label)
		var plan_old = compiler.compile(v1, unlocked)
		var plan_new = compiler.compile(v2, unlocked)
		t.check(plan_old["ok"] and plan_new["ok"], "AD-129 both compile " + label)
		if plan_old["ok"] and plan_new["ok"]:
			t.equal(plan_new["compiled_spell"].snapshot(), plan_old["compiled_spell"].snapshot(), "AD-129 equal plans " + label)
		var again: Dictionary = Codec.migrate(v2)
		t.equal([again["ok"], again["from_version"], again["formula"]], [true, 2, v2], "AD-129 v2 passes through migrate " + label)
	var future: Dictionary = formulas[0].duplicate(true)
	future["schema_version"] = 3
	t.contains_issue(Codec.decode(JSON.stringify(future))["issues"], "SCHEMA_UNSUPPORTED", "AD-129 schema 3 rejected by decode")
	t.contains_issue(Codec.migrate(future)["issues"], "SCHEMA_UNSUPPORTED", "AD-129 schema 3 rejected by migrate")
	t.contains_issue(validator.validate(future, unlocked)["issues"], "SCHEMA_UNSUPPORTED", "AD-129 schema 3 rejected by validator")

	var flow = Flow.new(20261029)
	flow.run.sequence_index = flow.config["rooms"].size() - 2
	flow._enter_current()
	t.check(flow.open_editor(2)["ok"], "AD-129 editor opens for palette")
	var palette: Array = flow.editor.palette()
	var palette_ids: Array = []
	var palette_runes := 0
	for entry in palette:
		palette_ids.append(entry["id"])
		palette_runes += entry["runes"].size()
		for rune in entry["runes"]:
			t.check(rune["id"] != "essence.neutral", "AD-129 palette excludes builtin " + str(rune["id"]))
	t.equal(palette_ids, CATEGORY_IDS, "AD-129 palette category order")
	t.equal(palette_runes, 10, "AD-129 palette lists 10 runes")
