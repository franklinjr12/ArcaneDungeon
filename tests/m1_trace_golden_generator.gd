extends SceneTree
## Developer-only regeneration utility. Review fixture changes before accepting them.
## godot --headless --path . --script res://tests/m1_trace_golden_generator.gd
const Runner = preload("res://magic/runtime/spell_runner.gd")
const FIXTURE = "res://magic/data/sandbox_samples_v1.json"
const TRACE_KINDS = ["cast_requested","cost_paid","spawn","hit","status","trigger","reaction","cleanup","budget_exceeded"]
const TRACE_FIELDS = ["type","cast_id","root_cast_id","effect_id","parent_effect_id","target_id","depth","reason"]

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	var formulas = JSON.parse_string(FileAccess.get_file_as_string(FIXTURE))["formulas"]
	var outputs: Dictionary = {}
	for scenario in ["split","pierce"]:
		var run = Runner.new(31415)
		var formula_id := "sample.split_fire_trigger" if scenario == "split" else "sample.pierce_water_trigger"
		for formula in formulas:
			if formula["formula_id"] == formula_id:
				run.equip(0,formula)
		if scenario == "split":
			for y in [275,340,405]:
				run.add_target(Vector2(325,y),Vector2.ZERO,1000.0)
		else:
			for x in [280,365,450]:
				run.add_target(Vector2(x,340),Vector2.ZERO,1000.0)
		run.try_cast(0,run.actor.position,Vector2.RIGHT)
		for i in 75:
			run.step()
		outputs[scenario] = normalize(run.trace.snapshot())
	print("M1_GOLDEN_OUTPUT:",JSON.stringify(outputs))
	quit()

static func normalize(records: Array) -> Array:
	var normalized: Array = []
	for entry in records:
		if entry["type"] not in TRACE_KINDS:
			continue
		var line := ""
		for key in TRACE_FIELDS:
			line += str(entry.get(key,""))+"|"
		normalized.append(line)
	return normalized
