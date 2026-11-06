extends RefCounted
## AD-145: meta progress (discoveries, milestones) and profile schema v2 migration.
const Service = preload("res://game/core/save_service.gd")
const Meta = preload("res://world/meta_progress.gd")
const DIR := "user://ad145_test/"
const Screen = preload("res://ui/compendium_screen.gd")
const Reward = preload("res://world/reward_generator.gd")
const Merchant = preload("res://world/merchant.gd")
const Flow = preload("res://world/run_flow.gd")
const State = preload("res://world/run_state.gd")

func _clean() -> void:
	DirAccess.make_dir_recursive_absolute(DIR)
	for f in DirAccess.get_files_at(DIR):
		DirAccess.remove_absolute(DIR + f)

func _write(name: String, text: String) -> void:
	var f := FileAccess.open(DIR + name, FileAccess.WRITE)
	f.store_string(text)
	f.close()

func _corrupt_count() -> int:
	var n := 0
	for f in DirAccess.get_files_at(DIR):
		if f.begins_with("profile.json.corrupt-"):
			n += 1
	return n

func _ids(prefix: String, n: int) -> Array:
	var out: Array = []
	for i in n:
		out.append("%s_%02d" % [prefix, i])
	return out

func run(t) -> void:
	_pools(t)
	_discoveries(t)
	_profile(t)
	_compendium(t)

func _fresh(cfg: Dictionary, run_seed: int):
	var st = State.new()
	var formulas := {}
	for id in cfg["initial_formulas"]:
		formulas[id] = {"id": id}
	st.initialize(run_seed, cfg, formulas)
	return st

func _pools(t) -> void:
	var cfg: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(Flow.CONFIG_V2))
	var empty := Meta.empty_meta()
	var lr: Array = Meta.locked_runes(empty)
	var la: Array = Meta.locked_artifacts(empty)
	var seen_a := {}
	var seen_r := {}
	var seen_m := {}
	var same := true
	var clean := true
	var open_rune := false
	var open_art := false
	var open_shop := false
	var met := Meta.empty_meta()
	Meta.merge(met, {"runes": _ids("r", 8), "reactions": _ids("x", 2), "enemies": _ids("e", 6), "artifacts": _ids("a", 4)})
	t.equal(Meta.locked_runes(met), [], "AD-145 milestones met -> no locked runes")
	t.equal(Meta.locked_artifacts(met), [], "AD-145 milestones met -> no locked artifacts")
	for n in 120:
		var st = _fresh(cfg, 7000 + n)
		var room_id := "room_%d" % (n % 7)
		var base = Reward.new(cfg)
		var plain = Reward.new(cfg, [], [])
		if base.choices(st, room_id, true) != plain.choices(st, room_id, true):
			same = false
		var locked = Reward.new(cfg, lr, la)
		for card in locked.choices(st, room_id, true):
			if card["kind"] == "artifact":
				seen_a[card["id"]] = true
			elif card["kind"] == "rune":
				seen_r[card["id"]] = true
		for card in base.choices(st, room_id, true):
			if card["kind"] == "artifact" and card["id"] in la:
				open_art = true
			elif card["kind"] == "rune" and card["id"] in lr:
				open_rune = true
		var shop = Merchant.new(cfg)
		shop.excluded_artifacts = la
		var ids: Array = cfg["reward_pool"] + lr
		var stock: Array = shop.build(st, ids, lr)
		st.currency = 999
		stock += shop.reroll(st).get("stock", [])
		for item in stock:
			if item["kind"] == "artifact":
				seen_m[item["artifact_id"]] = true
			elif item["kind"] == "rune":
				seen_m[item["rune_id"]] = true
		var open_shop_m = Merchant.new(cfg)
		for item in open_shop_m.build(_fresh(cfg, 7000 + n), ids, []):
			if (item["kind"] == "artifact" and item["artifact_id"] in la) or (item["kind"] == "rune" and item["rune_id"] in lr):
				open_shop = true
	t.equal(same, true, "AD-145 empty locks leave reward choices unchanged")
	for id in la:
		clean = clean and not seen_a.has(id) and not seen_m.has(id)
	for id in lr:
		clean = clean and not seen_r.has(id) and not seen_m.has(id)
	t.equal(clean, true, "AD-145 locked ids never appear in reward/merchant pools")
	t.equal(open_art, true, "AD-145 unlocked artifacts can appear for some seed")
	t.equal(open_rune or open_shop, true, "AD-145 unlocked runes can appear for some seed")

func _discoveries(t) -> void:
	var cfg: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(Flow.CONFIG_V2))
	var a = Flow.new(4242, Flow.CONFIG_V2)
	var b = Flow.new(4242, Flow.CONFIG_V2)
	for i in 300:
		a.step({})
		b.step({})
	var da: Dictionary = a.discoveries()
	t.equal(da, b.discoveries(), "AD-145 same seed gives same discoveries")
	for id in cfg["initial_unlocked"]:
		t.equal(id in da["runes"], true, "AD-145 discoveries include initial rune %s" % id)
	var sorted_ok := true
	for key in da:
		var copy: Array = (da[key] as Array).duplicate()
		copy.sort()
		sorted_ok = sorted_ok and copy == da[key]
	t.equal(sorted_ok, true, "AD-145 discoveries sorted")
	t.equal(da.keys().size(), 4, "AD-145 discoveries has four categories")
	t.equal(a.summary().has("discovered"), false, "AD-145 summary excludes discoveries")

func _profile(t) -> void:
	_clean()
	var svc = Service.new()
	svc.set_base_dir(DIR)
	t.equal(svc.meta(), Meta.empty_meta(), "AD-145 default meta empty")
	t.equal(svc.locked_runes(), ["trigger.on_expire", "trigger.timer"], "AD-145 default locked runes")
	t.equal(svc.locked_artifacts(), ["archivists_quill", "echo_chamber", "gravity_lens", "shatterheart", "stormglass"], "AD-145 default locked artifacts")
	# Persistence across instances.
	svc.record_run({"outcome": "lost", "seed": 5, "discovered": {"runes": ["form.burst", "essence.fire"], "enemies": ["rust_golem"]}})
	var svc2 = Service.new()
	svc2.set_base_dir(DIR)
	t.equal(svc2.meta()["discovered"]["runes"], ["essence.fire", "form.burst"], "AD-145 discovery persists (sorted)")
	t.equal(svc2.meta()["discovered"]["enemies"], ["rust_golem"], "AD-145 enemy discovery persists")
	t.equal(svc2.stats()["runs"], 1, "AD-145 stats kept with meta")
	# Merge idempotent and sorted.
	var m := Meta.empty_meta()
	var a := Meta.merge(m, {"runes": ["b", "a", "b"]})
	t.equal(a["runes"], ["a", "b"], "AD-145 merge returns new sorted unique")
	t.equal(Meta.merge(m, {"runes": ["a", "b"]})["runes"], [], "AD-145 merge idempotent")
	t.equal(m["discovered"]["runes"], ["a", "b"], "AD-145 merged list sorted")
	# Milestones.
	var before := Meta.empty_meta()
	var after := Meta.empty_meta()
	Meta.merge(after, {"reactions": ["chill_freeze", "wet_lightning_arc"]})
	t.equal(Meta.milestones_met(after), ["reactions_2"], "AD-145 reactions milestone met")
	t.equal(Meta.newly_met(before, after), ["reactions_2"], "AD-145 newly met")
	t.check("trigger.timer" not in Meta.locked_runes(after) and "stormglass" not in Meta.locked_artifacts(after), "AD-145 milestone unlocks leave locked lists")
	t.check("trigger.on_expire" in Meta.locked_runes(after), "AD-145 other milestone stays locked")
	Meta.merge(after, {"runes": _ids("r", 8), "enemies": _ids("e", 6), "artifacts": _ids("x", 4)})
	t.equal(Meta.milestones_met(after), ["runes_8", "reactions_2", "enemies_6", "artifacts_4"], "AD-145 all milestones in data order")
	t.equal([Meta.locked_runes(after), Meta.locked_artifacts(after)], [[], []], "AD-145 nothing locked after all milestones")
	# record_discoveries reports milestones and persists.
	var res: Dictionary = svc2.record_discoveries({"reactions": ["chill_freeze", "fire_thaw_steam"]})
	t.equal(res["milestones"], ["reactions_2"], "AD-145 record_discoveries milestone")
	t.equal(res["new"]["reactions"], ["chill_freeze", "fire_thaw_steam"], "AD-145 record_discoveries new ids")
	t.check("trigger.timer" not in svc2.locked_runes(), "AD-145 unlock changes the pool")
	# Unlocks never touch stats.
	var stats_before: Dictionary = svc2.stats()
	svc2.record_discoveries({"enemies": _ids("e", 6)})
	t.equal(svc2.stats(), stats_before, "AD-145 milestones change no stat keys")
	# v1 file migrates with stats kept.
	_write("profile.json", JSON.stringify({"schema_version": 1, "stats": {"runs": 4, "wins": 1, "deaths": 3, "best_time_seconds": 50.0, "last_seed": 9}}))
	svc2.load_profile()
	t.equal(svc2.profile["schema_version"], 2, "AD-145 v1 migrated to v2")
	t.equal(svc2.meta(), Meta.empty_meta(), "AD-145 v1 gets empty meta")
	t.equal(svc2.stats()["runs"], 4, "AD-145 v1 stats kept")
	# Invalid meta / junk -> quarantined, defaults.
	_write("profile.json", JSON.stringify({"schema_version": 2, "stats": Service.DEFAULT_STATS, "meta": {"discovered": {"runes": 5, "reactions": [], "enemies": [], "artifacts": []}}}))
	svc2.load_profile()
	t.equal(svc2.meta(), Meta.empty_meta(), "AD-145 invalid meta -> defaults")
	t.equal(_corrupt_count(), 1, "AD-145 invalid meta quarantined")
	_write("profile.json", JSON.stringify({"schema_version": 2, "stats": Service.DEFAULT_STATS, "meta": {"discovered": {"runes": [1], "reactions": [], "enemies": [], "artifacts": []}}}))
	svc2.load_profile()
	t.equal(_corrupt_count(), 2, "AD-145 non-string ids quarantined")
	_write("profile.json", "{not json")
	svc2.load_profile()
	t.equal(_corrupt_count(), 3, "AD-145 non-JSON quarantined")
	_write("profile.json", JSON.stringify({"schema_version": 3, "stats": {}}))
	svc2.load_profile()
	t.equal(_corrupt_count(), 4, "AD-145 future version quarantined")
	t.equal(svc2.profile, Service.default_profile(), "AD-145 defaults after quarantine")
	svc2.free()
	svc.free()
	_clean()
	DirAccess.remove_absolute(DIR)

func _compendium(t) -> void:
	_clean()
	var root = (Engine.get_main_loop() as SceneTree).root
	var svc = Service.new()
	svc.set_base_dir(DIR)
	svc.record_discoveries({"runes": ["essence.fire"], "reactions": ["chill_freeze"]})
	var screen = Screen.new()
	screen.save_service = svc
	root.add_child(screen)
	var cats := Screen.catalogs_by_category()
	var cfg: Dictionary = Meta.load_config()
	t.equal(screen.section_labels.keys(), ["runes", "reactions", "enemies", "artifacts"], "AD-145 compendium four sections")
	t.check(screen.section_labels["runes"].text.ends_with("1/%d" % cats["runes"].size()), "AD-145 compendium runes count")
	t.check(screen.section_labels["reactions"].text.ends_with("1/%d" % cfg["compendium"]["reactions"].size()), "AD-145 compendium reactions count")
	t.check(screen.section_labels["enemies"].text.ends_with("0/%d" % cfg["compendium"]["enemies"].size()), "AD-145 compendium enemies count")
	t.check(screen.section_labels["artifacts"].text.ends_with("0/%d" % cats["artifacts"].size()), "AD-145 compendium artifacts count")
	var texts := []
	for l in screen.find_children("*", "Label", true, false):
		texts.append(l.text)
	t.check(screen.tr("rune.essence.fire.name") in texts and screen.tr("rune.essence.water.name") not in texts, "AD-145 discovered rune named")
	t.check(screen.tr("compendium.unknown") in texts, "AD-145 undiscovered shows ???")
	t.equal(screen.milestone_rows.size(), cfg["milestones"].size(), "AD-145 milestone rows match data")
	for i in screen.milestone_rows.size():
		t.equal(screen.milestone_rows[i]["id"], cfg["milestones"][i]["id"], "AD-145 milestone row id " + str(i))
	t.check(screen.back_button.focus_mode == Control.FOCUS_ALL, "AD-145 compendium back focusable")
	var hits := []
	screen.back_requested.connect(func(): hits.append(1))
	screen.back_button.pressed.emit()
	t.equal(hits.size(), 1, "AD-145 compendium back emits back_requested")
	t.equal(svc.meta()["discovered"]["runes"], ["essence.fire"], "AD-145 compendium read-only")
	screen.free()
	var menu = load("res://scenes/main.tscn").instantiate()
	menu.show_debug_entries = false
	root.add_child(menu)
	var btn = menu.find_child("CompendiumButton", true, false)
	t.check(btn != null, "AD-145 CompendiumButton exists")
	if btn != null:
		btn.pressed.emit()
		t.check(menu.compendium_screen != null and menu.compendium_screen.visible and not menu.panel.visible, "AD-145 button opens compendium")
		menu.compendium_screen.back_requested.emit()
		t.check(menu.panel.visible and not menu.compendium_screen.visible, "AD-145 back restores title")
	menu.free()
	svc.free()
	_clean()
	DirAccess.remove_absolute(DIR)
