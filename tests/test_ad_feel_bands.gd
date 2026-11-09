extends RefCounted
## AD-182: feel-band guardrail. Run length must come from rooms/density/content, never from HP sponges:
## hits-to-kill with the basic neutral bolt (raw hp / raw bolt damage, no channel resistance) stays inside fixed bands on LIVE data.
const TUNING := "res://combat/combat_tuning_v1.json"
const RUN := "res://world/data/run_v2.json"
const RUNES := "res://magic/data/runes_v2.json"
const HEAVY := ["ossuary_shieldbearer", "corpse_bloat", "cistern_slime", "rust_golem"]
const HEAVY_LIMIT := 30
const LIGHT_LIMIT := 15
const MINI_BOSS_LIMIT := 70
const BOSS_LIMIT := 320

func run(t) -> void:
	var tuning = JSON.parse_string(FileAccess.get_file_as_string(TUNING))
	var run_data = JSON.parse_string(FileAccess.get_file_as_string(RUN))
	var runes = JSON.parse_string(FileAccess.get_file_as_string(RUNES))
	var bolt := 0.0
	for r in runes["runes"]:
		if r["id"] == "essence.neutral":
			bolt = float(r["params"]["base_damage"]["default"])
	t.check(bolt > 0.0, "AD-182 basic bolt damage > 0 (%s)" % bolt)
	if bolt <= 0.0:
		return
	for kind in tuning["enemies"]:
		var limit: int = HEAVY_LIMIT if kind in HEAVY else LIGHT_LIMIT
		_band(t, "enemy", kind, float(tuning["enemies"][kind]["hp"]), bolt, limit)
	for kind in tuning["mini_bosses"]:
		_band(t, "mini_boss", kind, float(tuning["mini_bosses"][kind]["hp"]), bolt, MINI_BOSS_LIMIT)
	for kind in run_data["bosses"]:
		_band(t, "boss", kind, float(run_data["bosses"][kind]["hp"]), bolt, BOSS_LIMIT)

func _band(t, group: String, kind: String, hp: float, bolt: float, limit: int) -> void:
	var hits := int(ceil(hp / bolt))
	t.check(hits <= limit, "AD-182 %s %s hits-to-kill %d <= limit %d" % [group, kind, hits, limit])
