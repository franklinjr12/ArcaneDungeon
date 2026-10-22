extends SceneTree
## TASK-002 deterministic discovery + nonzero exit + concise failure details.
const TestContext = preload("res://tests/test_context.gd")

func _initialize() -> void:
	call_deferred("_run_all")

func _run_all() -> void:
	var context := TestContext.new()
	var files := DirAccess.get_files_at("res://tests")
	files.sort()
	var suite_count := 0
	for filename in files:
		if not filename.begins_with("test_") or not filename.ends_with(".gd") or filename == "test_context.gd":
			continue
		suite_count += 1
		var suite_script := load("res://tests/" + filename)
		if suite_script == null or not suite_script.can_instantiate():
			context.check(false, "suite script load: " + filename)
			continue
		var suite = suite_script.new()
		if not suite.has_method("run"):
			context.check(false, "suite exposes run(context): " + filename)
			continue
		print("SUITE ", filename)
		suite.run(context)
	if "--self-test-failure" in OS.get_cmdline_user_args():
		context.check(false, "intentional failure probe")
	context.check(suite_count > 0, "at least one test suite discovered")
	print("TEST SUMMARY: %d passed / %d failed / %d suites" % [context.passed, context.failed, suite_count])
	for failure in context.failures:
		printerr("FAILED: ", failure)
	quit(1 if context.failed > 0 else 0)
