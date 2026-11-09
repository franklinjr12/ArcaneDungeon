extends RefCounted
## AD-167: the frozen balance fixture has the same structure as live data and the loader overrides work.
## AD-169: live pacing tuning changes values on purpose, so frozen vs live is compared structurally (nested keys, value types, scalar-array lengths, element types of wave/enemy lists), not by value.
const FILES := {
	"magic_balance_v1.json": "res://magic/data/magic_balance_v1.json",
	"combat_tuning_v1.json": "res://combat/combat_tuning_v1.json",
	"run_v2.json": "res://world/data/run_v2.json",
	"difficulty_v1.json": "res://game/data/difficulty_v1.json",
}
const Runner = preload("res://magic/runtime/spell_runner.gd")
const Session = preload("res://combat/combat_session.gd")
const Diff = preload("res://game/core/difficulty.gd")

func _structure_issue(frozen, live, path: String) -> String:
	if typeof(frozen) == TYPE_DICTIONARY and typeof(live) == TYPE_DICTIONARY:
		for key in frozen:
			if not live.has(key):
				return "%s/%s missing in live" % [path, key]
			var issue := _structure_issue(frozen[key], live[key], "%s/%s" % [path, key])
			if issue != "":
				return issue
		for key in live:
			if not frozen.has(key):
				return "%s/%s missing in frozen" % [path, key]
		return ""
	if typeof(frozen) == TYPE_ARRAY and typeof(live) == TYPE_ARRAY:
		var nested := false
		for item in frozen:
			nested = nested or typeof(item) == TYPE_ARRAY or typeof(item) == TYPE_DICTIONARY
		# Arrays of scalars (positions, id lists) keep their length; arrays of waves/enemies may grow, each live element
		# must then match the frozen element at the same index (or the last frozen one).
		if (not nested and frozen.size() != live.size()) or (frozen.is_empty() and not live.is_empty()):
			return "%s array length %d vs %d" % [path, frozen.size(), live.size()]
		for i in live.size():
			var issue := _structure_issue(frozen[mini(i, frozen.size() - 1)], live[i], "%s[%d]" % [path, i])
			if issue != "":
				return issue
		return ""
	# JSON numbers parse to float, so ints and floats count as the same type.
	if typeof(frozen) != typeof(live):
		return "%s type %d vs %d" % [path, typeof(frozen), typeof(live)]
	return ""

func run(t) -> void:
	for name in FILES:
		var live = JSON.parse_string(FileAccess.get_file_as_string(FILES[name]))
		var issue := _structure_issue(t.frozen_json(name), live, name)
		t.check(issue == "", "AD-167 frozen %s has the same structure as live %s" % [name, issue])
	var frozen_regen = t.frozen_json("magic_balance_v1.json")["combat"]["regen_mana_per_tick"]
	var frozen_tuning = t.frozen_json("combat_tuning_v1.json")
	t.with_frozen_balance(func():
		t.check(Runner.config_override == t.frozen_path("magic_balance_v1.json"), "AD-167 runner override set")
		t.equal(Runner.new().settings["combat"]["regen_mana_per_tick"], frozen_regen, "AD-167 runner reads frozen")
		t.check(Session.new().data == frozen_tuning, "AD-167 session reads frozen tuning")
		t.check(Diff.file_override == t.frozen_path("difficulty_v1.json"), "AD-167 difficulty override set"))
	t.check(Runner.config_override == "" and Session.tuning_override == "" and Diff.file_override == "", "AD-167 overrides reset")
