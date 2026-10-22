extends SceneTree
const Baseline = preload("res://tests/m2_baseline_driver.gd")
func _initialize() -> void:
	call_deferred("_test")
func _test() -> void:
	var outcomes: Array = []
	for key in ["single","mixed","cluster"]:
		for build in [0,2]:
			var result: Dictionary = Baseline.simulate(key,build)
			print("M2_SCENARIO:",JSON.stringify(result))
			outcomes.append(result)
	quit()
