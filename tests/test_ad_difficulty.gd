extends RefCounted
## AD-126 difficulty block: 1.0 keeps traces identical; multipliers scale HP and telegraphs.
const Session = preload("res://combat/combat_session.gd")
const Difficulty = preload("res://game/core/difficulty.gd")
const KEYS := ["enemy_hp","enemy_damage","enemy_speed","spawn_density","telegraph_length","reward_rate","coin_rate","player_hp","player_mana"]

func _trace(overrides: Dictionary) -> String:
	if overrides.is_empty():
		Difficulty.clear_override()
	else:
		Difficulty.set_override(overrides)
	var game = Session.new(5160,"mixed",0)
	for tick in 300:
		var slot := 1+(tick%2) if tick%7 == 0 else -1
		game.issue({"move":Vector2.RIGHT if tick%60 < 30 else Vector2.DOWN,"aim":Vector2.RIGHT,"cursor":game.sim.actor.position+Vector2(200,0),"cast":slot,"dash":tick%90 == 45})
		game.step()
	return game.sim.trace_json()

func run(t) -> void:
	var parsed = JSON.parse_string(FileAccess.get_file_as_string(Difficulty.FILE))
	var preset: Dictionary = parsed["presets"][parsed["active"]]
	for key in KEYS:
		t.check(preset.has(key),"AD-126 preset has "+key)
	for key in preset:
		t.equal(float(preset[key]),1.0,"AD-126 default "+key+" is 1.0")
	var base := _trace({})
	var ones := {}
	for key in KEYS:
		ones[key] = 1.0
	var same := _trace(ones)
	Difficulty.clear_override()
	t.check(base == same,"AD-126 all-1.0 override gives byte-identical trace")
	var tuning = JSON.parse_string(FileAccess.get_file_as_string(Session.TUNING_FILE))
	var boss_cfg: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://world/data/vertical_slice_v1.json"))["boss"]
	Difficulty.set_override({"enemy_hp":2.0})
	var game = Session.new(5160,"single",0)
	t.equal(game.enemies[0].target.health.maximum,2.0*float(tuning["enemies"]["bone_thrall"]["hp"]),"AD-126 enemy_hp 2.0 doubles bone_thrall HP")
	var boss = game.spawn_boss(boss_cfg,Vector2(boss_cfg["position"][0],boss_cfg["position"][1]))
	t.check(boss != null,"AD-126 boss spawned")
	if boss != null:
		t.equal(boss.target.health.maximum,2.0*float(boss_cfg["hp"]),"AD-126 enemy_hp 2.0 doubles boss HP")
	Difficulty.set_override({"telegraph_length":2.0})
	game = Session.new(5160,"single",0)
	t.equal(int(game.enemies[0].tuning["telegraph_ticks"]),2*int(tuning["enemies"]["bone_thrall"]["telegraph_ticks"]),"AD-126 telegraph_length 2.0 doubles telegraph ticks")
	Difficulty.clear_override()
