extends RefCounted
## AD-242: boss-adjacent events (Herald of the Warden in ruins, Flood Gate in cistern): seeded roll, data-driven chance/reward, reward flow.
## ACCEPT c (bot bench run length 18-25 min) is a manual bench run, not part of this suite.
const Flow = preload("res://world/run_flow.gd")
const Session = preload("res://combat/combat_session.gd")
const FIRST_SEED := 20261022
const SEEDS := 200
const HERALD := "herald_of_the_warden"
const FLOOD := "flood_gate"

func run(t) -> void:
	test_ad_242_a_event_roll_seeded(t)
	test_ad_242_b_event_rewards(t)

func _cfg() -> Dictionary:
	var parsed = JSON.parse_string(FileAccess.get_file_as_string(Flow.CONFIG_V2))
	return parsed if parsed is Dictionary else {}

func _event_cfg(cfg: Dictionary, id: String) -> Dictionary:
	var events = cfg.get("events",{})
	var e = events.get(id,{}) if events is Dictionary else {}
	return e if e is Dictionary else {}

func _with_chance(cfg: Dictionary, id: String, chance: float) -> Dictionary:
	var copy: Dictionary = cfg.duplicate(true)
	if not copy.has("events") or not copy["events"] is Dictionary:
		copy["events"] = {}
	if not copy["events"].has(id) or not copy["events"][id] is Dictionary:
		copy["events"][id] = {}
	copy["events"][id]["chance"] = chance
	return copy

func _tagged(seq: Array, id: String) -> Array:
	var out: Array = []
	for i in seq.size():
		if str(seq[i].get("event","")) == id:
			out.append(i)
	return out

func _stage_entries(seq: Array, stage: int) -> Array:
	return seq.filter(func(e): return int(e.get("stage",-1)) == stage)

func test_ad_242_a_event_roll_seeded(t) -> void:
	var cfg := _cfg()
	var herald := _event_cfg(cfg,HERALD)
	var flood := _event_cfg(cfg,FLOOD)
	t.check(not herald.is_empty(),"AD-242 events.herald_of_the_warden exists in run_v2.json")
	t.check(not flood.is_empty(),"AD-242 events.flood_gate exists in run_v2.json")
	t.check(herald.has("chance") and herald.has("reward"),"AD-242 herald has data chance and reward")
	t.check(flood.has("chance") and flood.has("reward") and float(flood.get("duration_seconds",0)) > 0.0,"AD-242 flood gate has data chance, reward and duration_seconds")
	t.check(is_equal_approx(float(herald.get("chance",-1.0)),0.5),"AD-242 herald chance is 0.5 in data")
	var rolled := 0
	var deterministic := true
	var herald_ok := true
	var flood_ok := true
	var clean_ok := true
	var flood_cfg := _with_chance(cfg,FLOOD,1.0)
	for i in SEEDS:
		var seed_value := FIRST_SEED+i
		var a: Array = Flow.build_sequence(cfg,seed_value)
		var b: Array = Flow.build_sequence(cfg,seed_value)
		if a != b:
			deterministic = false
		var base: Array = Flow.build_sequence(_with_chance(cfg,HERALD,0.0),seed_value)
		var herald_idx := _tagged(a,HERALD)
		if herald_idx.size() > 1:
			herald_ok = false
		elif herald_idx.size() == 1:
			rolled += 1
			var entry: Dictionary = a[herald_idx[0]]
			if int(entry.get("stage",-1)) != 0 or int(entry.get("room",-1)) != 2 or str(entry.get("type","")) != "combat" or a.size() != base.size():
				herald_ok = false
		var full: Array = Flow.build_sequence(flood_cfg,seed_value)
		var flood_idx := _tagged(full,FLOOD)
		if flood_idx.size() != 1:
			flood_ok = false
		else:
			var at: int = flood_idx[0]
			var entry: Dictionary = full[at]
			var next: Dictionary = full[at+1] if at+1 < full.size() else {}
			var after: Dictionary = full[at+2] if at+2 < full.size() else {}
			if int(entry.get("stage",-1)) != 1 or str(next.get("id","")) != "workshop" or str(after.get("id","")) != "cistern_boss" or bool(entry.get("optional",false)):
				flood_ok = false
		for e in a:
			if str(e.get("event","")) == FLOOD:
				flood_ok = false
		for e in _stage_entries(base,0)+_stage_entries(Flow.build_sequence(_with_chance(_with_chance(cfg,HERALD,0.0),FLOOD,0.0),seed_value),1):
			if e.has("event"):
				clean_ok = false
	t.check(deterministic,"AD-242 build_sequence identical for the same seed (200 seeds)")
	t.check(rolled >= 70 and rolled <= 130,"AD-242 herald rolled for roughly 35-65%% of seeds (got %d/200)" % rolled)
	t.check(herald_ok,"AD-242 herald decorates exactly one existing ruins combat room at room index 2, length unchanged")
	t.check(flood_ok,"AD-242 flood gate appears once, in cistern, right before workshop then cistern_boss, mandatory; never from herald-only cfg")
	t.check(clean_ok,"AD-242 chance 0.0 yields no event keys")
	var always: bool = true
	var herald_all := _with_chance(cfg,HERALD,1.0)
	for i in 20:
		if _tagged(Flow.build_sequence(herald_all,FIRST_SEED+i),HERALD).size() != 1:
			always = false
	t.check(always,"AD-242 herald chance 1.0 rolls on every seed")

## First seed whose sequence carries `id` (with the event forced on when chance is below 1).
func _find(cfg: Dictionary, id: String) -> Array:
	for i in SEEDS:
		var idx := _tagged(Flow.build_sequence(cfg,FIRST_SEED+i),id)
		if idx.size() == 1:
			return [FIRST_SEED+i,idx[0]]
	return []

func _kill_all(flow) -> void:
	for e in flow.session.enemies:
		if e.target.alive():
			e.target.health.current = 0.0

func _enter(t, cfg: Dictionary, id: String, label: String):
	var found := _find(cfg,id)
	t.check(found.size() == 2,"AD-242 %s: a seed rolls the event" % label)
	if found.size() != 2:
		return null
	var flow = Flow.new(int(found[0]))
	flow.start_new(int(found[0]))
	flow.run.sequence_index = int(found[1])
	flow._enter_current()
	t.check(flow.state == "fighting","AD-242 %s: event room enters fighting" % label)
	return flow if flow.state == "fighting" else null

func _check_artifact_reward(t, flow, label: String) -> void:
	var ids := {}
	var all_artifacts: bool = flow.reward_options.size() > 0
	for o in flow.reward_options:
		if str(o.get("kind","")) != "artifact":
			all_artifacts = false
		ids[str(o.get("id",""))] = true
	t.check(all_artifacts and ids.size() >= 2,"AD-242 %s: reward is an artifact choice of 2+ distinct ids" % label)
	if flow.reward_options.is_empty():
		return
	var pick: String = str(flow.reward_options[0].get("id",""))
	flow.choose_reward(0)
	t.check(pick in flow.run.artifacts,"AD-242 %s: chosen artifact lands in run.artifacts" % label)

func _no_sponges(t, flow, label: String) -> void:
	var ref = Session.new(1,"empty",0)
	var ok := true
	for e in flow.session.enemies:
		if e.target.tags.has("mini_boss") or e.target.tags.has("boss"):
			continue
		var base = ref.spawn_enemy(str(e.kind),Vector2(700,450))
		if base != null and e.target.health.maximum > base.target.health.maximum + 0.001:
			ok = false
	t.check(ok,"AD-242 %s: no enemy HP above its normal data" % label)

func test_ad_242_b_event_rewards(t) -> void:
	var cfg := _cfg()
	# Herald: elite adept ambush, artifact choice, fixed ink from data.
	var herald_flow = _enter(t,_with_chance(cfg,HERALD,0.5),HERALD,"herald")
	if herald_flow != null:
		var spawned := false
		var guard := 0
		while herald_flow.state == "fighting" and guard < 3000:
			_kill_all(herald_flow)
			herald_flow.step()
			if herald_flow.encounter != null and herald_flow.encounter.log.any(func(l): return l.get("event","") == "mini_boss_spawn" and l.get("id","") == "ruins_adept_elite"):
				spawned = true
			guard += 1
		t.check(spawned,"AD-242 herald: ruins_adept_elite mini-boss spawned")
		t.check(herald_flow.state == "cleared","AD-242 herald: room clears once enemies are dead")
		var ink := int(_event_cfg(cfg,HERALD).get("reward",{}).get("ink",-1))
		t.check(ink == 8,"AD-242 herald: data reward ink is 8")
		t.check(herald_flow.ink_earned == ink,"AD-242 herald: ink_earned equals the event ink only (no generic mini-boss/room ink on top)")
		_check_artifact_reward(t,herald_flow,"herald")
	# Flood gate: survive duration_seconds, then a relic (artifact) choice.
	var flood_cfg := _with_chance(cfg,FLOOD,1.0)
	var flood_flow = _enter(t,flood_cfg,FLOOD,"flood gate")
	if flood_flow != null:
		var seconds := float(_event_cfg(cfg,FLOOD).get("duration_seconds",0))
		var rate: int = int(flood_flow.session.sim.clock.tick_rate)
		var need := int(round(seconds*rate))
		t.check(need > 0,"AD-242 flood gate: duration_seconds is positive in data")
		var early_clear := false
		var started: int = flood_flow.ticks_elapsed
		_no_sponges(t,flood_flow,"flood gate")
		var guard := 0
		while flood_flow.state == "fighting" and guard < need+600:
			var health = flood_flow.session.sim.actor.health
			health.maximum = 1.0e9
			health.current = 1.0e9
			flood_flow.step()
			guard += 1
			if flood_flow.state == "cleared" and flood_flow.ticks_elapsed-started < need:
				early_clear = true
		t.check(not early_clear,"AD-242 flood gate: does not clear before duration_seconds*tick_rate ticks")
		t.check(flood_flow.state == "cleared" and flood_flow.ticks_elapsed-started >= need,"AD-242 flood gate: clears once the timer elapsed")
		_check_artifact_reward(t,flood_flow,"flood gate")
