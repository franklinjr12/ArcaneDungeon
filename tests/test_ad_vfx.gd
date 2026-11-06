extends RefCounted
## AD-149: VFX data, pooled particles, deterministic emitters, hit-flash shader and the reduce-flash / reduce-shake policy.
const Data = preload("res://ui/vfx/vfx_data.gd")
const Pool = preload("res://ui/vfx/particle_pool.gd")
const Emitters = preload("res://ui/vfx/vfx_emitters.gd")
const Reduce = preload("res://ui/reduce_motion.gd")
const Settings = preload("res://game/core/settings.gd")
const Flow = preload("res://world/run_flow.gd")
const SEED := 20261022

class FakeEffect:
	extends RefCounted
	var id := 1
	var position := Vector2(100, 100)
	var root := {}

func _fake_session(essence: String):
	var flow = Flow.new(SEED)
	var fx := FakeEffect.new()
	fx.root = {"essence": {"id": essence}}
	flow.session.sim.active.append({"kind": "projectile", "effect": fx})
	flow.session.sim.visuals.append({"kind": "burst", "position": Vector2(200, 200), "radius": 40.0, "essence": essence, "until": 99999})
	return flow.session

func run(t) -> void:
	_data(t)
	_pool(t)
	_emitters(t)
	_reduce(t)
	_assets(t)

func _data(t) -> void:
	var d := Data.load_data()
	t.equal(int(d.get("version", 0)), 1, "AD-149 vfx_v1 parses, version 1")
	for el in ["fire", "water", "lightning", "cold", "force", "neutral"]:
		var e: Dictionary = d.get("elements", {}).get(el, {})
		for k in ["trail", "impact", "glow"]:
			t.check(e.has(k), "AD-149 element %s has %s" % [el, k])
	for s in ["burning", "wet", "charged", "chilled", "frozen", "brittle", "blinded"]:
		t.check(d.get("status", {}).has(s), "AD-149 status key " + s)
	t.equal(Data.particle_cap("off"), 0, "AD-149 off cap is 0")
	t.check(Data.particle_cap("low") <= Data.particle_cap("high"), "AD-149 low cap <= high")
	t.equal(Data.element_key("essence.fire"), "fire", "AD-149 element_key fire")
	t.equal(Data.element_key("essence.bogus"), "neutral", "AD-149 element_key unknown is neutral")
	t.equal(Data.particle_cap("bogus"), Data.particle_cap("high"), "AD-149 unknown mode falls back to high")

func _pool(t) -> void:
	var pool := Pool.new(8)
	var dropped := 0
	for i in 20:
		if not pool.emit(Vector2(i, 0), Vector2.RIGHT, 3, 2.0, Color.WHITE, Color.BLACK):
			dropped += 1
	t.equal(pool.active_count(), 8, "AD-149 pool never exceeds capacity")
	t.equal(dropped, 12, "AD-149 over-emit returns false when full")
	for n in 3:
		pool.step()
	t.equal(pool.active_count(), 0, "AD-149 step() recycles dead particles")
	t.check(pool.emit(Vector2.ZERO, Vector2.ZERO, 2, 1.0, Color.WHITE, Color.WHITE), "AD-149 slots reusable after recycle")
	t.check(pool.is_live(0), "AD-149 lowest free slot used first")
	pool.clear()
	t.equal(pool.active_count(), 0, "AD-149 clear empties the pool")
	t.equal(pool.capacity(), 8, "AD-149 capacity fixed after clear")
	t.equal(Pool.new(0).emit(Vector2.ZERO, Vector2.ZERO, 3, 1.0, Color.WHITE, Color.WHITE), false, "AD-149 zero-cap pool drops everything")

func _emitters(t) -> void:
	var a = _fake_session("essence.fire")
	var b = _fake_session("essence.fire")
	for tick in [0, 1, 2, 7]:
		t.equal(Emitters.trail_requests(a, tick), Emitters.trail_requests(b, tick), "AD-149 trail deterministic at tick %d" % tick)
	t.check(Emitters.trail_requests(a, 3).size() >= 1, "AD-149 trail emits for a projectile")
	var fx := [{"event": "impact.fire", "at": Vector2(5, 5), "age": 0, "rotation": 0.0, "length": 0.0, "slot": 0},
		{"event": "burst.water", "at": Vector2(9, 9), "age": 3, "rotation": 0.0, "length": 0.0, "slot": 0},
		{"event": "hit.spark", "at": Vector2(1, 1), "age": 0, "rotation": 0.0, "length": 0.0, "slot": 0}]
	var i1 := Emitters.impact_requests(fx, 12)
	t.equal(i1, Emitters.impact_requests(fx, 12), "AD-149 impacts deterministic")
	var expect := int(Data.element_cfg("essence.fire")["impact"]["count"]) + int(Data.element_cfg("essence.neutral")["impact"]["count"])
	t.equal(i1.size(), expect, "AD-149 impacts only at age 0")
	var g := Emitters.glow_sources(a)
	t.equal(g.size(), 2, "AD-149 glow covers projectile core and burst")
	t.equal(Emitters.glow_sources(a), Emitters.glow_sources(b), "AD-149 glow deterministic")
	var target = a.sim.targets.all()[0]
	target.status.apply("burning", 0, {"duration_ticks": 600})
	var s1 := Emitters.status_requests(a, 40)
	var any := false
	for tick in 40:
		any = any or Emitters.status_requests(a, tick).size() > 0
	t.check(any, "AD-149 burning target emits status particles")
	t.equal(s1, Emitters.status_requests(a, 40), "AD-149 status deterministic")
	t.equal(Emitters.hash3(3, 4, 5), Emitters.hash3(3, 4, 5), "AD-149 hash is pure")
	t.check(Emitters.hash3(3, 4, 5) != Emitters.hash3(3, 4, 6), "AD-149 hash varies with inputs")

func _reduce(t) -> void:
	t.equal(Reduce.hit_flash_strength(true, 5, 6), 0.0, "AD-149 reduce-flash: hit flash strength 0")
	t.check(Reduce.hit_flash_strength(false, 5, 6) > 0.0, "AD-149 full effects: hit flash strength > 0")
	t.equal(Reduce.hit_flash_strength(false, 0, 6), 0.0, "AD-149 no flash when ticks_left is 0")
	t.equal(Reduce.vfx_params(false), {}, "AD-149 no reduced params when flashes on")
	var rp := Reduce.vfx_params(true)
	t.check(float(rp["glow_alpha_mult"]) < 1.0 and float(rp["impact_count_mult"]) < 1.0, "AD-149 reduced multipliers below 1")
	var a = _fake_session("essence.lightning")
	var full := Emitters.glow_sources(a)
	var red := Emitters.glow_sources(a, rp)
	t.check(red[0]["color"].a < full[0]["color"].a, "AD-149 reduced glow alpha scaled down")
	t.check(red[0]["color"].a <= float(rp["max_alpha"]) + 0.0001, "AD-149 reduced glow respects max_alpha")
	var fx := [{"event": "impact.lightning", "at": Vector2.ZERO, "age": 0, "rotation": 0.0, "length": 0.0, "slot": 0}]
	var n_full := Emitters.impact_requests(fx, 1).size()
	var n_red := Emitters.impact_requests(fx, 1, rp).size()
	t.equal(n_red, roundi(n_full * float(rp["impact_count_mult"])), "AD-149 reduced impact count scaled")
	for r in Emitters.impact_requests(fx, 1, rp):
		t.check(r["color"].a <= float(rp["max_alpha"]) + 0.0001, "AD-149 reduced particle alpha capped")
		break
	var white := Emitters.reduced_color(Color(1, 1, 1, 1), rp)
	t.check(white.r < 1.0 and white.a <= float(rp["max_alpha"]), "AD-149 no_white_core removes pure white")
	var s := Settings.new()
	s.screen_shake = false
	t.equal(Reduce.particle_jitter_enabled(s), false, "AD-149 screen_shake off disables particle jitter")
	s.screen_shake = true
	t.equal(Reduce.particle_jitter_enabled(s), true, "AD-149 screen_shake on keeps particle jitter")
	t.equal(Reduce.particle_jitter_enabled(null), true, "AD-149 null settings keeps particle jitter")

func _assets(t) -> void:
	t.check(load("res://shaders/hit_flash.gdshader") is Shader, "AD-149 hit_flash shader loads")
	t.check(Data.texture("", "glow") is Texture2D, "AD-149 procedural glow fallback")
	t.check(Data.texture("res://nope/missing.png", "particle") is Texture2D, "AD-149 missing path falls back")
	t.check(Data.texture("", "glow") == Data.texture("", "glow"), "AD-149 procedural texture cached")
