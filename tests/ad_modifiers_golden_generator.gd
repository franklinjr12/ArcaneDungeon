extends SceneTree
## Developer-only regeneration utility. Review fixture changes before accepting them.
## godot --headless --path . --script res://tests/ad_modifiers_golden_generator.gd
const Runner = preload("res://magic/runtime/spell_runner.gd")
const M1Golden = preload("res://tests/m1_trace_golden_generator.gd")
const SAMPLES = "res://magic/data/sandbox_samples_v1.json"
const SCENARIOS = ["chain_bolt_jumps","expand_burst_reach","rapid_beam_cooldown","chain_field_no_repeat"]
const SEED = 133133
const TAIL_TICKS = 10

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	preload("res://tests/test_context.gd").set_frozen_balance(true)
	var outputs: Dictionary = {}
	for scenario in SCENARIOS:
		outputs[scenario] = run_scenario(scenario)
	print("AD133_GOLDEN_OUTPUT:",JSON.stringify(outputs))
	quit()

## Same line format as the M1 normalizer, plus "chain" records.
static func normalize(records: Array) -> Array:
	var kinds: Array = M1Golden.TRACE_KINDS + ["chain"]
	var normalized: Array = []
	for entry in records:
		if entry["type"] not in kinds:
			continue
		var line := ""
		for key in M1Golden.TRACE_FIELDS:
			line += str(entry.get(key,""))+"|"
		normalized.append(line)
	return normalized

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
	var formula_id := "sample.chain_bolt"
	var target_point = null
	var p: Vector2 = run.actor.position
	match scenario:
		"chain_bolt_jumps":
			targets = [run.add_target(p+Vector2(120,0),Vector2.ZERO,100000.0),run.add_target(p+Vector2(150,90),Vector2.ZERO,100000.0),run.add_target(p+Vector2(150,-60),Vector2.ZERO,100000.0)]
		"expand_burst_reach":
			formula_id = "sample.expand_burst"
			targets = [run.add_target(p+Vector2(100,0),Vector2.ZERO,100000.0)]
		"rapid_beam_cooldown":
			formula_id = "sample.rapid_beam"
			targets = [run.add_target(p+Vector2(120,0),Vector2.ZERO,100000.0)]
		"chain_field_no_repeat":
			formula_id = "sample.chain_field"
			target_point = p+Vector2(190,0)
			targets = [run.add_target(p+Vector2(190,0),Vector2.ZERO,100000.0),run.add_target(p+Vector2(190,130),Vector2.ZERO,100000.0),run.add_target(p+Vector2(190,-130),Vector2.ZERO,100000.0)]
	run.equip(0,sample(formula_id))
	var accepted: Array = [run.try_cast(0,run.actor.position,Vector2.RIGHT,target_point)["accepted"]]
	var params: Dictionary = run.loadout.get_plan(0).snapshot()["root"]["params"]
	var ticks: int = int(params.get("lifetime_ticks",params.get("field_duration_ticks",30 if scenario == "expand_burst_reach" else 0)))+TAIL_TICKS
	if scenario == "expand_burst_reach":
		ticks = 30
	for i in ticks:
		run.step()
	if scenario == "rapid_beam_cooldown":
		while int(run.loadout.slots[0]["cooldown"]) > 0:
			run.step()
		accepted.append(run.try_cast(0,run.actor.position,Vector2.RIGHT)["accepted"])
		for i in ticks:
			run.step()
	return {"run":run,"targets":targets,"accepted":accepted}
