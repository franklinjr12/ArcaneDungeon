extends SceneTree
## Developer-only regeneration utility. Review fixture changes before accepting them.
## godot --headless --path . --script res://tests/ad_cold_force_golden_generator.gd
const Runner = preload("res://magic/runtime/spell_runner.gd")
const M1Golden = preload("res://tests/m1_trace_golden_generator.gd")
const SAMPLES = "res://magic/data/sandbox_samples_v1.json"
const SCENARIOS = ["chill_to_frozen","wet_cold_force_shatter","cold_fire_steam"]
const SEED = 27182
const GAP_TICKS = 60

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	preload("res://tests/test_context.gd").set_frozen_balance(true)
	var outputs: Dictionary = {}
	for scenario in SCENARIOS:
		outputs[scenario] = run_scenario(scenario)
	print("AD131_GOLDEN_OUTPUT:",JSON.stringify(outputs))
	quit()

static func normalize(records: Array) -> Array:
	return M1Golden.normalize(records)

static func sample(formula_id: String) -> Dictionary:
	for formula in JSON.parse_string(FileAccess.get_file_as_string(SAMPLES))["formulas"]:
		if formula["formula_id"] == formula_id:
			return formula
	return {}

## Plays one scripted scenario; returns the normalized trace. Use play() for the runner and targets.
static func run_scenario(scenario: String) -> Array:
	return normalize(play(scenario)["run"].trace.snapshot())

static func play(scenario: String) -> Dictionary:
	var run = Runner.new(SEED)
	var targets: Array = [run.add_target(Vector2(440,340),Vector2.ZERO,1000.0)]
	var casts: Array = []
	match scenario:
		"chill_to_frozen":
			casts = ["sample.cold_shot","sample.cold_shot","sample.cold_shot"]
		"wet_cold_force_shatter":
			casts = ["sample.water_shot","sample.cold_shot","sample.force_shot"]
		"cold_fire_steam":
			targets.append(run.add_target(Vector2(440,410),Vector2.ZERO,1000.0))
			casts = ["sample.cold_shot","sample.fire_shot"]
	var accepted: Array = []
	for formula_id in casts:
		run.equip(0,sample(formula_id))
		accepted.append(run.try_cast(0,run.actor.position,Vector2.RIGHT)["accepted"])
		for i in GAP_TICKS:
			run.step()
	return {"run":run,"targets":targets,"accepted":accepted}
