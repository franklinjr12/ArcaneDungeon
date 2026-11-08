extends RefCounted
## AD-167: the frozen balance fixture matches live data today and the loader overrides work.
const FILES := {
	"magic_balance_v1.json": "res://magic/data/magic_balance_v1.json",
	"combat_tuning_v1.json": "res://combat/combat_tuning_v1.json",
	"run_v2.json": "res://world/data/run_v2.json",
	"difficulty_v1.json": "res://game/data/difficulty_v1.json",
}
const Runner = preload("res://magic/runtime/spell_runner.gd")
const Session = preload("res://combat/combat_session.gd")
const Diff = preload("res://game/core/difficulty.gd")

func run(t) -> void:
	for name in FILES:
		var live = JSON.parse_string(FileAccess.get_file_as_string(FILES[name]))
		t.check(t.frozen_json(name) == live, "AD-167 frozen %s equals live" % name)
	var frozen_regen = t.frozen_json("magic_balance_v1.json")["combat"]["regen_mana_per_tick"]
	var frozen_tuning = t.frozen_json("combat_tuning_v1.json")
	t.with_frozen_balance(func():
		t.check(Runner.config_override == t.frozen_path("magic_balance_v1.json"), "AD-167 runner override set")
		t.equal(Runner.new().settings["combat"]["regen_mana_per_tick"], frozen_regen, "AD-167 runner reads frozen")
		t.check(Session.new().data == frozen_tuning, "AD-167 session reads frozen tuning")
		t.check(Diff.file_override == t.frozen_path("difficulty_v1.json"), "AD-167 difficulty override set"))
	t.check(Runner.config_override == "" and Session.tuning_override == "" and Diff.file_override == "", "AD-167 overrides reset")
