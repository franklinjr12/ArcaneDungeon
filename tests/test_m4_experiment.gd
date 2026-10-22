extends RefCounted
## TASK-052–053 opt-in telemetry, export-only storage, and nonblocking teaching.
const Flow = preload("res://world/run_flow.gd")
const Log = preload("res://debug/experiment_log.gd")
const Prompts = preload("res://ui/onboarding_prompts.gd")
const Profiler = preload("res://debug/stress_profiler.gd")

func run(t) -> void:
	var f = Flow.new(20261022)
	var no_data: Dictionary = f.experiment.snapshot()
	t.check(not f.experiment.enabled,"TASK-052 experimental telemetry defaults OFF")
	t.equal(no_data["events"].size(),0,"TASK-052 disabled telemetry stores no event")
	f.step({"move":Vector2.RIGHT,"aim":Vector2.RIGHT,"cast":0})
	t.equal(f.experiment.summary()["events"],0,"TASK-052 no tracking while opted out")
	var same = Flow.new(20261022)
	same.experiment.configure(true)
	same.step({"move":Vector2.RIGHT,"aim":Vector2.RIGHT,"cast":0})
	t.equal(f.session.sim.trace_json(),same.session.sim.trace_json(),
		"TASK-052 enabled logging does not influence spells or causal trace")
	t.equal(f.session.sim.actor.position,same.session.sim.actor.position,
		"TASK-052 logging does not affect movement")
	t.check(same.experiment.summary()["counts"].has("dungeon_cast"),"TASK-052 dungeon cast captured")
	t.equal(same.experiment.summary()["events"],1,"TASK-052 only allowlisted actual cast captured")
	var custom: Dictionary = same.run.formulas[0].duplicate(true)
	var renamed: Dictionary = custom.duplicate(true)
	renamed["display_name"] = "=injected,private player free text"
	t.equal(Log.signature(custom),Log.signature(renamed),
		"TASK-052 formula signature excludes user supplied display names")
	t.check(Log.signature(custom).length() == 16,"TASK-052 signature has fixed length")
	var recorder = Log.new()
	t.equal(recorder.export_json("user://disabled_m4_telemetry.json"),ERR_UNAVAILABLE,
		"TASK-052 disabled logger refuses export")
	recorder.configure(true)
	recorder.record("editor_open",{"room_index":4,"slot":0,"name":"private"})
	recorder.record("formula_edit",{"slot":0,"display_name":"personal text"},custom)
	recorder.record("test_cast",{"slot":0,"cast_accepted":true},custom)
	recorder.record("rune_choice",{"room_index":2,"rune_index":1})
	recorder.record("death",{"room_index":2})
	recorder.record("room_clear",{"room_index":3})
	var summary: Dictionary = recorder.summary()
	t.equal(summary["distinct_formulas"],1,"TASK-052 distinct formula metric computed")
	t.equal(summary["edit_to_test_ms"].size(),1,"TASK-052 edit-to-first-test latency computable")
	t.check(float(summary["edit_to_test_ms"][0])>=0,"TASK-052 edit-to-test time cannot be negative")
	t.equal(summary["counts"]["death"],1,"TASK-052 death event counted")
	t.equal(summary["counts"]["room_clear"],1,"TASK-052 room clear counted")
	var json_result = recorder.export_json("user://m4_experiment_test.json")
	var csv_result = recorder.export_csv("user://m4_experiment_test.csv")
	t.equal(json_result,OK,"TASK-052 opt-in JSON export succeeds")
	t.equal(csv_result,OK,"TASK-052 opt-in CSV export succeeds")
	var raw: String = FileAccess.get_file_as_string("user://m4_experiment_test.json")
	var csv: String = FileAccess.get_file_as_string("user://m4_experiment_test.csv")
	t.check(raw.contains("formula_signature") and not raw.contains("private") and not raw.contains("personal"),
		"TASK-052 JSON contains hash and excludes private text")
	t.check(csv.contains("formula_signature") and not csv.contains("private"),
		"TASK-052 exported CSV has safe fields only")
	t.equal(JSON.parse_string(raw)["events"].size(),6,"TASK-052 JSON contains only recorded opt-in events")
	recorder.configure(false)
	t.equal(recorder.summary()["events"],0,"TASK-052 opting out clears local memory immediately")
	t.equal(recorder.export_csv("user://disabled_m4_telemetry.csv"),ERR_UNAVAILABLE,
		"TASK-052 cannot export while disabled")
	var guides = Prompts.new()
	t.check(guides.message("combat").contains("Water") and guides.message("combat").contains("Lightning"),
		"TASK-053 combat tip teaches Water then Lightning")
	t.check(guides.message("editor").contains("MUST include a Burst payload"),
		"TASK-053 On Hit explanation includes required Burst payload")
	t.check(guides.message("workshop").contains("without changing run HP"),
		"TASK-053 tutorial explains safe practice")
	guides.dismiss()
	t.equal(guides.message("editor"),"","TASK-053 hints dismissed nonblocking")
	guides.reopen()
	t.check(not guides.message("editor").is_empty(),"TASK-053 hints can be reopened")
	t.check(not guides.message("reward").is_empty(),"TASK-053 contextual reward hint available")
