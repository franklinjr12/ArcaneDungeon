extends SceneTree
## AD-257 single-suite runner (not discovered by run_tests.gd: name does not start with test_).
const TestContext = preload("res://tests/test_context.gd")

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	var context := TestContext.new()
	var suite = load("res://tests/test_ad_257_combos.gd").new()
	suite.run(context)
	print("TEST SUMMARY: %d passed / %d failed" % [context.passed,context.failed])
	for failure in context.failures:
		printerr("FAILED: ",failure)
	quit(1 if context.failed > 0 else 0)
