extends RefCounted
const Generator = preload("res://tests/ad_enemy_golden_generator.gd")

func run(t) -> void:
	_golden(t)

func _golden(t) -> void:
	var fixture: Dictionary = t.fixture("ad_enemy_traces_v1.json")
	var cases: Dictionary = fixture["cases"]
	t.equal(cases.keys().size(),Generator.CASES.size(),"AD-136 golden case count")
	for case_name in cases:
		var expected: Array = cases[case_name]
		var actual: Array = Generator.run_case(case_name)
		var message := ""
		if actual.size() != expected.size():
			message = "length %d != %d" % [actual.size(),expected.size()]
		for i in mini(actual.size(),expected.size()):
			if actual[i] != expected[i]:
				message = "line %d: got '%s' expected '%s'" % [i,actual[i],expected[i]]
				break
		t.check(message == "","AD-136 golden %s %s" % [case_name,message])
