extends RefCounted
## AD-015: damage numbers neutral white + element symbol.
const DN = preload("res://ui/damage_numbers.gd")
const Target = preload("res://combat/magic_target.gd")

func run(t) -> void:
	for pair in [["fire","flame"],["water","droplet"],["lightning","bolt"],["essence.fire","flame"],["neutral",""],["physical",""],["",""],["bogus",""]]:
		t.equal(DN.symbol_for(pair[0]),pair[1],"AD-015 symbol for "+pair[0])
	for element in ["fire","water","lightning","neutral","physical"]:
		t.equal(DN.format(7.4,element)["color"],Color(1,1,1,1),"AD-015 white for "+element)
	t.equal(DN.format(7.4,"fire")["text"],"7","AD-015 rounds")
	t.equal(DN.format(0.2,"fire")["text"],"1","AD-015 sub-1 shows 1")
	var target = Target.new(5,2,Vector2(10,20),100.0)
	var tracker = DN.new()
	tracker.update([target],0)
	t.equal(tracker.popups.size(),0,"AD-015 first sight spawns nothing")
	target.receive_damage(5.0,"fire",1,1.0)
	target.receive_damage(3.0,"lightning",1,1.0)
	tracker.update([target],10)
	t.equal(tracker.popups.size(),2,"AD-015 two popups")
	t.equal(tracker.popups[0]["symbol"],"flame","AD-015 first popup flame")
	t.equal(tracker.popups[1]["symbol"],"bolt","AD-015 second popup bolt")
	tracker.update([target],10+DN.LIFETIME_TICKS+1)
	t.equal(tracker.popups.size(),0,"AD-015 popups expire")
	for i in 20:
		target.receive_damage(1.0,"water",1,1.0)
	t.check(target.damage_log.size() <= 16,"AD-015 damage log capped")
