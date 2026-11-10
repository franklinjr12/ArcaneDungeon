extends RefCounted
## AD-194: every regular enemy has exactly one weakness channel (negative channel_resistances) in live data.
const Session = preload("res://combat/combat_session.gd")
const EnemyAffinity = preload("res://ui/enemy_affinity.gd")
const Screen = preload("res://ui/compendium_screen.gd")

const WEAK := {
	"bone_thrall": "force",
	"fallen_adept": "lightning",
	"grave_hound": "fire",
	"ossuary_shieldbearer": "force",
	"wailing_spirit": "fire",
	"corpse_bloat": "fire",
	"cistern_slime": "lightning",
	"cistern_slimelet": "cold",
	"drowned_acolyte": "lightning",
	"deep_eel": "cold",
	"rust_golem": "lightning",
	"lantern_wisp": "water",
	"storm_crystal": "force",
}

func run(t) -> void:
	var data: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://combat/combat_tuning_v1.json"))
	var enemies: Dictionary = data["enemies"]
	_data(t, enemies)
	_behaviour(t)
	_colours(t)
	_affinity(t, enemies)
	_screen(t)

func _negatives(res: Dictionary) -> Array:
	var out: Array = []
	for channel in res:
		if float(res[channel]) < 0.0:
			out.append(channel)
	return out

func _data(t, enemies: Dictionary) -> void:
	var weak_channels := {}
	for kind in enemies:
		var res: Dictionary = enemies[kind].get("channel_resistances", {})
		var negatives := _negatives(res)
		t.check(not negatives.is_empty(),"AD-194 %s has a weakness" % kind)
		t.check(WEAK.has(kind) and negatives == [WEAK[kind]],"AD-194 %s weakness matches the table (%s)" % [kind, str(negatives)])
		for channel in res:
			t.check(absf(float(res[channel])) <= 1.0,"AD-194 %s %s within -1..1" % [kind, channel])
		for channel in negatives:
			weak_channels[channel] = true
	t.check(weak_channels.size() >= 4,"AD-194 at least 4 distinct weakness channels (%d)" % weak_channels.size())
	for kind in WEAK:
		t.check(enemies.has(kind),"AD-194 table kind %s exists in live data" % kind)

func _hit(kind: String, channel: String) -> float:
	var s = Session.new(194,"empty",0)
	var e = s.spawn_enemy(kind,Vector2(300,300))
	return e.target.receive_damage(10.0,channel,s.sim.actor.team,100000.0)

func _behaviour(t) -> void:
	var base := _hit("bone_thrall","physical")
	t.check(base > 0.0,"AD-194 base physical hit on thrall deals damage (%f)" % base)
	t.check(is_equal_approx(_hit("bone_thrall","force"),base*1.5),"AD-194 thrall weak to Force takes 1.5x physical")
	t.check(is_equal_approx(_hit("bone_thrall","cold"),base*0.5),"AD-194 thrall resists Cold to 0.5x physical")
	t.check(is_equal_approx(_hit("storm_crystal","lightning"),0.0),"AD-194 storm crystal is immune to Lightning")

func _colours(t) -> void:
	const DN = preload("res://ui/damage_numbers.gd")
	const Target = preload("res://combat/magic_target.gd")
	t.check(DN.format(5.0,"fire","weak")["color"] == DN.COLOR_WEAK,"AD-194 weak number colour")
	t.check(DN.format(5.0,"fire","resist")["color"] == DN.COLOR_RESIST,"AD-194 resist number colour")
	t.check(DN.format(5.0,"fire")["color"] == Color.WHITE,"AD-194 normal number stays white")
	var target = Target.new(5,2,Vector2(10,20),100.0,18.0,0.0,{"fire":-0.5,"cold":0.5})
	var tracker := DN.new()
	tracker.update([target],0)
	for channel in ["fire","cold","physical"]:
		target.receive_damage(5.0,channel,1,1.0)
	var tiers: Array = target.damage_log.map(func(e): return e["tier"])
	t.check(tiers == ["weak","resist",""],"AD-194 damage_log tiers (%s)" % str(tiers))
	tracker.update([target],10)
	var colours: Array = tracker.popups.map(func(p): return p["color"])
	t.check(colours == [DN.COLOR_WEAK,DN.COLOR_RESIST,Color.WHITE],"AD-194 popup colours in order")

func _affinity(t, enemies: Dictionary) -> void:
	t.equal(EnemyAffinity.of("rust_golem")["weak"], ["lightning"], "AD-194 golem weak list")
	t.equal(EnemyAffinity.of("storm_crystal")["resist"], ["lightning"], "AD-194 crystal resist list")
	t.check("lightning" in EnemyAffinity.of("drowned_archivist")["weak"], "AD-194 archivist weak to lightning")
	t.equal(EnemyAffinity.of("nope"), {"weak": [], "resist": []}, "AD-194 unknown kind empty")
	var channels := {}
	for kind in enemies:
		var aff: Dictionary = EnemyAffinity.of(kind)
		for channel in aff["weak"] + aff["resist"]:
			channels[channel] = true
	for channel in channels:
		var icon: AtlasTexture = EnemyAffinity.icon(channel)
		t.check(icon != null and icon.region.has_area(), "AD-194 icon for %s" % channel)

func _screen(t) -> void:
	var root = (Engine.get_main_loop() as SceneTree).root
	var old_size: Vector2i = root.size
	root.size = Vector2i(1280, 720)
	var screen = Screen.new()
	root.add_child(screen)
	screen.select_tab("enemies")
	var vp := Rect2(Vector2.ZERO, screen.get_viewport_rect().size)
	var ids: Array = screen.entries("enemies")
	screen._meta = screen._meta.duplicate(true)
	screen._meta["discovered"]["enemies"] = screen._catalogs["enemies"].duplicate()
	for i in ids.size():
		screen._select("enemies", i)
		var d: Dictionary = screen._detail["enemies"]
		var weak: Array = EnemyAffinity.of(ids[i])["weak"]
		var shown := 0
		for pic in d["weak_icons"]:
			if pic.visible:
				shown += 1
				t.check(vp.encloses(Rect2(pic.global_position, pic.size)), "AD-194 %s weak icon inside viewport" % ids[i])
		t.equal(shown, weak.size(), "AD-194 %s visible weak icons" % ids[i])
	screen._meta["discovered"]["enemies"] = []
	screen._select("enemies", 0)
	var d2: Dictionary = screen._detail["enemies"]
	var any: bool = d2["weak_label"].visible or d2["resist_label"].visible
	for pic in d2["weak_icons"] + d2["resist_icons"]:
		any = any or pic.visible
	t.check(not any, "AD-194 undiscovered entry hides the rows")
	screen.free()
	root.size = old_size
