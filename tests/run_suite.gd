extends SceneTree
## Runs one suite file: godot --headless --path . --script res://tests/run_suite.gd -- test_name.gd. Not auto-discovered (no test_ prefix).
const TestContext = preload("res://tests/test_context.gd")

func _initialize() -> void:
	call_deferred("_run_one")

func _run_one() -> void:
	var context := TestContext.new()
	var args := OS.get_cmdline_user_args()
	var script_name := str(args[0]) if not args.is_empty() else ""
	var suite_script = load("res://tests/" + script_name) if not script_name.is_empty() else null
	if suite_script == null or not suite_script.can_instantiate():
		context.check(false, "suite script load: " + script_name)
	else:
		var suite = suite_script.new()
		if suite.has_method("run"):
			print("SUITE ", script_name)
			suite.run(context)
		else:
			context.check(false, "suite exposes run(context): " + script_name)
	print("TEST SUMMARY: %d passed / %d failed" % [context.passed, context.failed])
	for failure in context.failures:
		printerr("FAILED: ", failure)
	quit(1 if context.failed > 0 else 0)
