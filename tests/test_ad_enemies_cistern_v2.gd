extends RefCounted
## AD-238: new Cistern enemies. a: Tide Siphon puddles + wet-lightning combo, b: puddle reactions both ways,
## c: Lamprey pair tether, d: tether cut stuns the partner, e: data + determinism.
## Contract the later steps implement: behaviours `tide_siphon` / `lamprey_pair`; hazards kind "puddle", status "wet",
## source_id = siphon id; read-only `session.tether_view()` -> [{"a_id","b_id","from","to","cut"}]; a stunned eel is in
## state "stunned" for exactly the lamprey_pair `stun_ticks`.
const Session = preload("res://combat/combat_session.gd")
const Registry = preload("res://combat/enemy_behaviours/registry.gd")

func run(t) -> void:
	test_ad_238_a_tide_siphon_behaviour(t)
	test_ad_238_b_puddle_reactions_both_ways(t)
	test_ad_238_c_lamprey_pair_tether(t)
	test_ad_238_d_tether_cut_stuns_partner(t)
	test_ad_238_e_data_and_determinism(t)

func _cfg(s, kind: String) -> Dictionary:
	return s.data["enemies"].get(kind,{})

func _entry(cfg: Dictionary, id: String) -> Dictionary:
	for entry in cfg.get("behaviours",[]):
		if entry.get("id","") == id:
			return entry
	return {}

func _puddles(s, source_id: int = -1) -> Array:
	return s.hazards.filter(func(h): return h["kind"] == "puddle" and h["status"] == "wet" and (source_id < 0 or int(h["source_id"]) == source_id))

func _tethers(s) -> Array:
	return s.tether_view() if s.has_method("tether_view") else []

func _wet(s, who) -> void:
	who.status.apply("wet",s.sim.clock.tick,s.sim.settings["statuses"]["wet"],{"team":0})

func _lightning_taken(s, source_id: int) -> float:
	var hp: float = s.sim.actor.health.current
	s.damage_player(source_id,10.0,"lightning")
	var taken: float = hp-s.sim.actor.health.current
	s.sim.actor.health.current = hp
	return taken

func _siphon_session() -> Array:
	var s = Session.new(238,"empty",0)
	var siphon = s.spawn_enemy("tide_siphon",s.sim.actor.position+Vector2(300,0))
	return [s,siphon]

func test_ad_238_a_tide_siphon_behaviour(t) -> void:
	var s = Session.new(238,"empty",0)
	var cfg := _cfg(s,"tide_siphon")
	t.check(not cfg.is_empty() and Registry.validate_enemy(cfg).is_empty(),"AD-238 tide_siphon config exists and validates")
	var scenario := Session.new(238,"tide_siphon",0)
	var kinds: Array = scenario.enemies.map(func(e): return e.kind)
	t.check(kinds.has("tide_siphon"),"AD-238 scenario tide_siphon spawns a tide_siphon (%s)" % str(kinds))
	if cfg.is_empty() or not kinds.has("tide_siphon"):
		return
	var params := _entry(cfg,"tide_siphon")
	t.check(not params.is_empty() and params.has("max_puddles"),"AD-238 tide_siphon behaviour exposes max_puddles")
	var siphon = scenario.enemies[kinds.find("tide_siphon")]
	var max_puddles := int(params.get("max_puddles",0))
	var duration := int(params.get("puddle_duration_ticks",0))
	var peak := 0
	var seen := false
	for i in 600:
		scenario.step()
		var own := _puddles(scenario,siphon.target.id)
		seen = seen or not own.is_empty()
		peak = maxi(peak,own.size())
	t.check(seen,"AD-238 tide_siphon adds wet puddle hazards sourced from itself")
	t.check(peak >= 1 and peak <= max_puddles,"AD-238 puddle count bounded by max_puddles (%d vs %d)" % [peak,max_puddles])
	for h in _puddles(scenario,siphon.target.id):
		t.check(int(h["duration_ticks"]) == duration and float(h["radius"]) == float(params.get("puddle_radius",-1)),"AD-238 puddle size/lifetime come from data params")
	siphon.target.health.current = 0.0
	for i in duration+10:
		scenario.step()
	t.check(_puddles(scenario,siphon.target.id).is_empty(),"AD-238 puddles expire")
	# Wet-lightning combo against the player: a dry player vs a Wet player.
	var r := _siphon_session()
	var s2 = r[0]
	if r[1] == null:
		t.check(false,"AD-238 tide_siphon cannot be spawned for the wet-lightning combo")
		return
	var source: int = r[1].target.id
	var dry := _lightning_taken(s2,source)
	_wet(s2,s2.sim.actor)
	var wet := _lightning_taken(s2,source)
	t.check(dry > 0.0 and wet > dry,"AD-238 enemy lightning hurts a Wet player more than a dry one (%s vs %s)" % [wet,dry])
	var scale := float(params.get("wet_lightning_scale",0.0))
	t.check(scale > 1.0 and is_equal_approx(wet,dry*scale),"AD-238 the wet-lightning bonus is the data param wet_lightning_scale (%s)" % scale)

func test_ad_238_b_puddle_reactions_both_ways(t) -> void:
	var r := _siphon_session()
	var s = r[0]
	var siphon = r[1]
	var player = s.sim.actor
	t.check(siphon != null and _entry(_cfg(s,"tide_siphon"),"tide_siphon") != {},"AD-238 reactions test uses a real tide_siphon")
	if siphon == null:
		return
	# Player stands in a siphon puddle -> Wet.
	s.add_hazard({"kind":"puddle","status":"wet","position":player.position,"radius":60.0,"duration_ticks":300,"interval_ticks":10,"source_id":siphon.target.id})
	var foe = s.spawn_enemy("bone_thrall",player.position+Vector2(120,0))
	s.add_hazard({"kind":"puddle","status":"wet","position":foe.target.position,"radius":60.0,"duration_ticks":300,"interval_ticks":10,"source_id":siphon.target.id})
	var other = s.spawn_enemy("bone_thrall",foe.target.position+Vector2(40,0))
	s.step()
	t.check(player.status.has("wet",s.sim.clock.tick),"AD-238 the player standing in a siphon puddle is Wet")
	t.check(foe.target.status.has("wet",s.sim.clock.tick) and other.target.status.has("wet",s.sim.clock.tick),"AD-238 enemies in the puddle are Wet")
	# Player lightning on a Wet enemy in a puddle reacts (arc to the other Wet enemy).
	var formula = s.samples["sample.lightning_shot"]
	var equipped: Dictionary = s.sim.loadout.equip(1,formula)
	t.check(bool(equipped.get("ok",false)),"AD-238 player lightning spell equips (%s)" % str(equipped.get("reason","")))
	var hp_other: float = other.target.health.current
	var reaction_seen := false
	s.sim.actor.position = foe.target.position-Vector2(150,0)
	for i in 90:
		s.issue({"move":Vector2.ZERO,"aim":Vector2.RIGHT,"cursor":foe.target.position,"cast":1 if i == 0 else -1,"dash":false})
		s.step()
		reaction_seen = reaction_seen or other.target.health.current < hp_other
	t.check(reaction_seen,"AD-238 player lightning on a Wet puddle enemy applies the wet_lightning reaction to the neighbour")
	# Enemy lightning on the Wet player reacts too (both ways).
	var hp: float = player.health.current
	player.position = foe.target.position
	_wet(s,player)
	s.damage_player(siphon.target.id,10.0,"lightning")
	t.check(player.health.current < hp,"AD-238 enemy lightning lands on the Wet player")
	t.check(_lightning_taken(s,siphon.target.id) > 10.0*(1.0-float(player.health.resistances.get("lightning",0.0))),"AD-238 the Wet player takes the wet-lightning reaction bonus (both ways)")

func _pair_session() -> Array:
	var s = Session.new(238,"lamprey_pair",0)
	var eels: Array = s.enemies.filter(func(e): return e.kind == "lamprey")
	return [s,eels]

func test_ad_238_c_lamprey_pair_tether(t) -> void:
	var s = Session.new(238,"empty",0)
	var cfg := _cfg(s,"lamprey")
	t.check(not cfg.is_empty() and Registry.validate_enemy(cfg).is_empty(),"AD-238 lamprey config exists and validates")
	var r := _pair_session()
	var pair: Array = r[1]
	t.equal(pair.size(),2,"AD-238 scenario lamprey_pair spawns two lampreys")
	var tethers := _tethers(r[0])
	t.check(tethers.size() == 1 and not bool(tethers[0].get("cut",true)),"AD-238 one live tether is exposed read-only via session.tether_view()")
	if cfg.is_empty() or pair.size() != 2 or tethers.size() != 1:
		return
	var s2 = r[0]
	var params := _entry(cfg,"lamprey_pair")
	var interval := int(params.get("hit_interval_ticks",0))
	t.check(interval > 0 and int(params.get("stun_ticks",0)) > 0,"AD-238 lamprey_pair has hit_interval_ticks and stun_ticks params")
	var player = s2.sim.actor
	var seg: Dictionary = _tethers(s2)[0]
	var mid: Vector2 = (seg["from"]+seg["to"])*0.5
	player.position = mid
	var hp0: float = player.health.current
	var hits := 0
	var last: float = hp0
	for i in interval*3+1:
		s2.step()
		if player.health.current < last:
			hits += 1
		last = player.health.current
	t.check(hits >= 2 and hits <= 4,"AD-238 tether damages the player about once per hit_interval_ticks (%d hits in 3 intervals)" % hits)
	var r2 := _pair_session()
	var s3 = r2[0]
	s3.sim.actor.position = (_tethers(s3)[0]["from"]+_tethers(s3)[0]["to"])*0.5+Vector2(0,400)
	var hp1: float = s3.sim.actor.health.current
	for i in interval*3:
		s3.step()
	t.check(s3.sim.actor.health.current == hp1,"AD-238 a player outside the tether segment takes no tether damage")

func _stunned_run(s, eel) -> int:
	var n := 0
	while eel.state == "stunned" and n < 600:
		s.step()
		n += 1
	return n

func test_ad_238_d_tether_cut_stuns_partner(t) -> void:
	var r := _pair_session()
	var s = r[0]
	var pair: Array = r[1]
	if pair.size() != 2:
		t.check(false,"AD-238 lamprey pair missing; cannot test the tether cut")
		return
	var stun := int(_entry(_cfg(s,"lamprey"),"lamprey_pair").get("stun_ticks",0))
	t.equal(stun,120,"AD-238 stun_ticks is 120 (2 s at 60 ticks/s)")
	pair[0].target.health.current = 0.0
	s.step()
	t.check(pair[1].state == "stunned","AD-238 killing one eel stuns the survivor")
	t.equal(_stunned_run(s,pair[1]),stun-1,"AD-238 survivor stays stunned for exactly stun_ticks")
	t.check(_tethers(s).is_empty() or bool(_tethers(s)[0].get("cut",false)),"AD-238 killing an eel ends the tether")
	var player = s.sim.actor
	var hp: float = player.health.current
	player.position = pair[1].target.position
	for i in 120:
		s.step()
	t.check(player.health.current == hp or player.health.current > 0.0,"AD-238 no tether damage after the cut")
	# Pierce / beam spells crossing the segment cut the tether and stun the partner(s).
	for formula_id in ["sample.lightning_beam","sample.pierce_water_trigger"]:
		var r2 := _pair_session()
		var s2 = r2[0]
		var eels: Array = r2[1]
		var seg: Dictionary = _tethers(s2)[0] if not _tethers(s2).is_empty() else {}
		if seg.is_empty():
			t.check(false,"AD-238 %s: no tether to cut" % formula_id)
			continue
		var mid: Vector2 = (seg["from"]+seg["to"])*0.5
		var dir: Vector2 = (seg["to"]-seg["from"]).orthogonal().normalized()
		var p = s2.sim.actor
		p.position = mid-dir*160.0
		t.check(bool(s2.sim.loadout.equip(1,s2.samples[formula_id]).get("ok",false)),"AD-238 %s equips" % formula_id)
		for i in 30:
			s2.issue({"move":Vector2.ZERO,"aim":dir,"cursor":mid,"cast":1 if i == 0 else -1,"dash":false})
			s2.step()
		t.check(bool(_tethers(s2)[0].get("cut",false)),"AD-238 %s crossing the tether cuts it" % formula_id)
		t.check(eels.all(func(e): return e.state == "stunned" or not e.target.alive()),"AD-238 %s cut stuns the eels" % formula_id)
		for i in 400:
			s2.step()
		t.check(bool(_tethers(s2)[0].get("cut",false)),"AD-238 a cut tether stays cut")
	# A plain bolt does not cut it.
	var r3 := _pair_session()
	var s3 = r3[0]
	var seg3: Dictionary = _tethers(s3)[0] if not _tethers(s3).is_empty() else {}
	if seg3.is_empty():
		t.check(false,"AD-238 no tether for the non-piercing bolt check")
		return
	var mid3: Vector2 = (seg3["from"]+seg3["to"])*0.5
	var dir3: Vector2 = (seg3["to"]-seg3["from"]).orthogonal().normalized()
	s3.sim.actor.position = mid3-dir3*160.0
	s3.sim.loadout.equip(1,s3.samples["sample.fire_shot"])
	for i in 30:
		s3.issue({"move":Vector2.ZERO,"aim":dir3,"cursor":mid3,"cast":1 if i == 0 else -1,"dash":false})
		s3.step()
	t.check(not bool(_tethers(s3)[0].get("cut",true)),"AD-238 a non-piercing bolt crossing the tether does not cut it")

func _run_state(scenario: String, ticks: int) -> Array:
	var s = Session.new(238,scenario,0)
	for i in ticks:
		s.step()
	return [s.hazards.duplicate(true),_tethers(s).duplicate(true),s.sim.actor.health.current,s.enemies.map(func(e): return [e.kind,e.target.position,e.target.health.current,e.state])]

func test_ad_238_e_data_and_determinism(t) -> void:
	var meta = JSON.parse_string(FileAccess.get_file_as_string("res://world/data/meta_v1.json"))
	var comp: Array = meta["compendium"]["enemies"]
	var cfgs: Dictionary = Session.new(238,"empty",0).data["enemies"]
	var sponge: float = float(cfgs.get("rune_sentry",{}).get("hp",60))
	for kind in ["tide_siphon","lamprey"]:
		t.check(comp.has(kind),"AD-238 %s listed in meta compendium.enemies" % kind)
		var hp := float(cfgs.get(kind,{}).get("hp",9999))
		t.check(hp <= 80.0 and hp > 0.0,"AD-238 %s is no HP sponge (hp %s)" % [kind,hp])
		t.check(not cfgs.get(kind,{}).is_empty(),"AD-238 %s config present for the determinism runs" % kind)
	t.check(sponge > 0.0,"AD-238 reference rune_sentry hp readable")
	for scenario in ["tide_siphon","lamprey_pair"]:
		var a := _run_state(scenario,300)
		var b := _run_state(scenario,300)
		t.check(a == b,"AD-238 scenario %s run deterministic (hazards, tether, hp)" % scenario)
		t.check(not (a[3] as Array).is_empty(),"AD-238 scenario %s spawns enemies" % scenario)
