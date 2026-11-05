extends SceneTree
## Developer-only regeneration utility. Review fixture changes before accepting them.
## godot --headless --path . --script res://tests/ad_forms_golden_generator.gd
const Runner = preload("res://magic/runtime/spell_runner.gd")
const M1Golden = preload("res://tests/m1_trace_golden_generator.gd")
const SAMPLES = "res://magic/data/sandbox_samples_v1.json"
const SCENARIOS = ["beam_line_pulses","beam_wall_stop","field_cold_freeze"]
const SEED = 132132
const TAIL_TICKS = 10

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	var outputs: Dictionary = {}
	for scenario in SCENARIOS:
		outputs[scenario] = run_scenario(scenario)
	print("AD132_GOLDEN_OUTPUT:",JSON.stringify(outputs))
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
	run.settings["combat"]["regen_mana_per_tick"] = 0.0
	run.mana = float(run.settings["combat"]["player_max_mana"])
	var targets: Array = []
	var formula_id := "sample.fire_beam"
	var target_point = null
	match scenario:
		"beam_line_pulses":
			targets = [run.add_target(Vector2(260,340),Vector2.ZERO,100000.0),run.add_target(Vector2(360,340),Vector2.ZERO,100000.0)]
		"beam_wall_stop":
			targets = [run.add_target(Vector2(200,340),Vector2.ZERO,100000.0),run.add_target(Vector2(330,340),Vector2.ZERO,100000.0)]
			run.collision_walls = [Rect2(260,300,20,80)]
		"field_cold_freeze":
			formula_id = "sample.cold_field"
			target_point = Vector2(330,340)
			targets = [run.add_target(Vector2(330,340),Vector2.ZERO,100000.0)]
	run.equip(0,sample(formula_id))
	var accepted: Array = [run.try_cast(0,run.actor.position,Vector2.RIGHT,target_point)["accepted"]]
	var params: Dictionary = run.loadout.get_plan(0).snapshot()["root"]["params"]
	var ticks: int = int(params.get("lifetime_ticks",params.get("field_duration_ticks",0)))+TAIL_TICKS
	for i in ticks:
		run.step()
	return {"run":run,"targets":targets,"accepted":accepted}
