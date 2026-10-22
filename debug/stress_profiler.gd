extends RefCounted
## TASK-051 bounded synthetic load; headless data, not a claim about rendered FPS.
const Runner = preload("res://magic/runtime/spell_runner.gd")
const SAMPLES := "res://magic/data/sandbox_samples_v1.json"

static func benchmark(seed: int = 5151, ticks: int = 300, target_count: int = 40) -> Dictionary:
	var r = Runner.new(seed)
	var doc: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(SAMPLES))
	var by_id: Dictionary = {}
	for f in doc["formulas"]:
		by_id[str(f["formula_id"])] = f
	r.equip(0,by_id["sample.split_fire_trigger"])
	r.equip(1,by_id["sample.pierce_water_trigger"])
	for i in target_count:
		# 8x5 spread lets many Split/Pierce/On Hit children collide.
		var p := Vector2(260+(i%8)*71,110+(i/8)*100)
		var movement := Vector2(0,24) if i%6==0 else Vector2.ZERO
		var target = r.add_target(p,movement,10000)
		if i%3==0:
			target.status.apply("wet",0,r.settings["statuses"]["wet"])
		if i%4==0:
			target.status.apply("burning",0,r.settings["statuses"]["burning"])
	var samples_usec: Array = []
	var memory_initial: int = int(Performance.get_monitor(Performance.MEMORY_STATIC))
	var memory_peak := memory_initial
	var peak_active := 0
	var peak_pending := 0
	var overflow = r.stress()
	for i in ticks:
		if i == ticks/2:
			r.equip(1,by_id["sample.orbit_fire"])
		if i%3==0:
			r.mana = float(r.settings["combat"]["player_max_mana"])
			r.try_cast(0,r.actor.position,Vector2.RIGHT)
		if i%7==0:
			r.try_cast(1,r.actor.position,Vector2.RIGHT)
		var start: int = Time.get_ticks_usec()
		r.step()
		samples_usec.append(Time.get_ticks_usec()-start)
		peak_active = maxi(peak_active,r.queue.active_effect_count())
		peak_pending = maxi(peak_pending,r.queue.pending_count())
		memory_peak = maxi(memory_peak,int(Performance.get_monitor(Performance.MEMORY_STATIC)))
	var counts: Dictionary = {}
	for entry in r.trace.snapshot():
		var kind: String = str(entry["type"])
		counts[kind] = int(counts.get(kind,0))+1
	samples_usec.sort()
	var micros := 0
	for measure in samples_usec:
		micros += int(measure)
	return {"seed":seed,"ticks":ticks,"targets":target_count,
		"mean_tick_ms":snappedf(float(micros)/maxf(1,ticks)/1000.0,0.001),
		"p95_tick_ms":float(samples_usec[clampi(roundi(ticks*.95),0,samples_usec.size()-1)])/1000.0,
		"max_tick_ms":float(samples_usec[-1])/1000.0,
		"memory_static_start_bytes":memory_initial,"memory_static_peak_bytes":memory_peak,
		"memory_static_delta_bytes":memory_peak-memory_initial,
		"gc_pause_ms":null,"gc_note":"GDScript RefCounted/native allocations: no isolated GC-pause metric exposed",
		"peak_active_effects":peak_active,"peak_queued_events":peak_pending,
		"budget_drop_records":int(counts.get("budget_exceeded",0)),
		"hit_records":int(counts.get("hit",0)),"reaction_records":int(counts.get("reaction",0)),
		"trigger_records":int(counts.get("trigger",0)),
		"cap_attempted":overflow["attempted"],"cap_accepted":overflow["accepted"],
		"cap_per_cast":overflow["cap"],"limits":r.limits.snapshot(),
		"pending_end":r.queue.pending_count(),"alive":r.actor.alive()}
