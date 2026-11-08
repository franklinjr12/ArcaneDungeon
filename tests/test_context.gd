extends RefCounted

var passed := 0
var failed := 0
var failures: Array[String] = []

func check(condition: bool, label: String) -> void:
	if condition:
		passed += 1
	else:
		failed += 1
		failures.append(label)
		printerr("FAIL: ", label)

func equal(actual: Variant, expected: Variant, label: String) -> void:
	check(actual == expected, "%s\n  expected: %s\n       got: %s" % [label, str(expected), str(actual)])

func contains_issue(issues: Array, code: String, label: String) -> void:
	for issue in issues:
		if issue.get("code", "") == code:
			check(true, label)
			return
	check(false, "%s; missing issue: %s in %s" % [label, code, str(issues)])

func fixture(path: String) -> Variant:
	var file := FileAccess.open("res://tests/fixtures/" + path, FileAccess.READ)
	if file == null:
		check(false, "fixture accessible: " + path)
		return null
	var parser := JSON.new()
	var error := parser.parse(file.get_as_text())
	check(error == OK, "fixture valid JSON: " + path)
	return parser.data if error == OK else null

const FROZEN_DIR := "res://tests/fixtures/balance_frozen/"

func frozen_path(file_name: String) -> String:
	return FROZEN_DIR + file_name

func frozen_json(file_name: String) -> Variant:
	var file := FileAccess.open(frozen_path(file_name), FileAccess.READ)
	if file == null:
		check(false, "frozen balance accessible: " + file_name)
		return null
	var parser := JSON.new()
	var error := parser.parse(file.get_as_text())
	check(error == OK, "frozen balance valid JSON: " + file_name)
	return parser.data if error == OK else null

func with_frozen_balance(body: Callable) -> void:
	var runner = load("res://magic/runtime/spell_runner.gd")
	var session = load("res://combat/combat_session.gd")
	var difficulty = load("res://game/core/difficulty.gd")
	runner.config_override = frozen_path("magic_balance_v1.json")
	session.tuning_override = frozen_path("combat_tuning_v1.json")
	difficulty.file_override = frozen_path("difficulty_v1.json")
	body.call()
	runner.config_override = ""
	session.tuning_override = ""
	difficulty.file_override = ""
