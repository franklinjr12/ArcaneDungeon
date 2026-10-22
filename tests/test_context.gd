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
