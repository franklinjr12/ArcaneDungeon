extends RefCounted
## AD-149 pure emit-request builders: session/fx state in, particle requests out. Never draws, never writes the session.
## Requests are {at, vel, life, size, color, color_end}. Jitter is a pure integer hash of (tick, index, entity id), never sim RNG.
const Data = preload("res://ui/vfx/vfx_data.gd")
const Art = preload("res://ui/pixel_art_renderer.gd")
const IMPACT_PREFIXES := ["impact.", "burst."]

## Pure integer hash -> [0, 65535]. Masked at every step so results are identical on every platform.
static func hash3(a: int, b: int, c: int) -> int:
	var h := (a * 73856093) ^ (b * 19349663) ^ (c * 83492791)
	h &= 0x7fffffff
	h = ((h >> 13) ^ h) & 0x7fffffff
	h = (h * 1274126177) & 0x7fffffff
	return (h ^ (h >> 16)) & 0xffff

static func unit(a: int, b: int, c: int) -> float:
	return float(hash3(a, b, c)) / 65535.0

static func _dir(a: int, b: int, c: int) -> Vector2:
	return Vector2.from_angle(unit(a, b, c) * TAU)

static func _req(at: Vector2, vel: Vector2, life: int, size: float, color: Color, color_end: Color) -> Dictionary:
	return {"at": at, "vel": vel, "life": life, "size": size, "color": color, "color_end": color_end}

## Reduce-flash colour policy: clamp alpha to max_alpha and (no_white_core) pull near-white toward the tint.
static func reduced_color(c: Color, params: Dictionary) -> Color:
	var out := c
	out.a = minf(out.a, float(params.get("max_alpha", 1.0)))
	if bool(params.get("no_white_core", false)):
		var peak := maxf(out.r, maxf(out.g, out.b))
		var low := minf(out.r, minf(out.g, out.b))
		if peak > 0.9 and low > 0.8:
			out = Color(out.r * 0.8, out.g * 0.8, out.b * 0.8, out.a)
	return out

static func _finish(reqs: Array, params: Dictionary) -> Array:
	if params.is_empty():
		return reqs
	for r in reqs:
		r["color"] = reduced_color(r["color"], params)
		r["color_end"] = reduced_color(r["color_end"], params)
	return reqs

## Per-tick trail particles behind projectiles and orbs. `reduced` is a Dictionary from the data `reduced` block, or {}.
static func trail_requests(session, tick: int, reduced: Dictionary = {}) -> Array:
	var out: Array = []
	for entry in session.sim.active:
		var kind := str(entry.get("kind", ""))
		if kind != "projectile" and kind != "orb":
			continue
		var fx = entry["effect"]
		var cfg: Dictionary = Data.element_cfg(str(fx.root.get("essence", {}).get("id", ""))).get("trail", {})
		if cfg.is_empty():
			continue
		var rate := float(cfg.get("rate_per_tick", 0.0))
		var n := floori(rate * float(tick + 1)) - floori(rate * float(tick))
		for i in n:
			var d := _dir(tick, i, int(fx.id))
			var jitter := d * unit(tick, i + 97, int(fx.id)) * 2.0
			out.append(_req(fx.position + jitter, d * float(cfg["speed"]), int(cfg["life_ticks"]), float(cfg["size"]),
				Color(str(cfg["color"])), Color(str(cfg["color_end"]), 0.0)))
	return _finish(out, reduced)

## One burst per impact.* / burst.* / hit.spark fx at age 0 (Art.collect_fx output).
static func impact_requests(fx_list: Array, tick: int, reduced: Dictionary = {}) -> Array:
	var out: Array = []
	var mult := float(reduced.get("impact_count_mult", 1.0)) if not reduced.is_empty() else 1.0
	for idx in fx_list.size():
		var fx: Dictionary = fx_list[idx]
		if int(fx.get("age", -1)) != 0:
			continue
		var ev := str(fx.get("event", ""))
		var el := ""
		if ev == "hit.spark":
			el = "neutral"
		else:
			for p in IMPACT_PREFIXES:
				if ev.begins_with(p):
					el = ev.trim_prefix(p)
		if el == "":
			continue
		var cfg: Dictionary = Data.element_cfg("essence." + el).get("impact", {})
		if cfg.is_empty():
			continue
		var at: Vector2 = fx["at"]
		var count := roundi(float(cfg["count"]) * mult)
		for i in count:
			var d := _dir(tick, i, idx)
			var spd := float(cfg["speed"]) * (0.5 + unit(tick, i + 31, idx))
			var c := Color(str(cfg["color"]))
			out.append(_req(at, d * spd, int(cfg["life_ticks"]), float(cfg["size"]), c, Color(c, 0.0)))
	return _finish(out, reduced)

## Rising status motes on every living target, one per rate_period_ticks (staggered by target id).
static func status_requests(session, tick: int, reduced: Dictionary = {}) -> Array:
	var out: Array = []
	for target in session.sim.targets.all():
		if not target.alive():
			continue
		var snap: Dictionary = target.status.snapshot(tick)
		var ids: Array = snap.keys()
		ids.sort()
		for sid in ids:
			var cfg: Dictionary = Data.status_cfg(str(sid))
			if cfg.is_empty():
				continue
			var period := maxi(1, int(cfg["rate_period_ticks"]))
			if (tick + int(target.id)) % period != 0:
				continue
			var ox := (unit(tick, 1, int(target.id)) - 0.5) * 2.0 * float(target.radius)
			var oy := (unit(tick, 2, int(target.id)) - 0.5) * float(target.radius)
			var c := Color(str(cfg["color"]))
			out.append(_req(target.position + Vector2(ox, oy), Vector2(0.0, -float(cfg["rise"])),
				int(cfg["life_ticks"]), float(cfg["size"]), c, Color(c, 0.0)))
	return _finish(out, reduced)

## Additive glow sprites: projectile/orb cores plus field/burst visuals. [{at, radius, color(with alpha)}]
static func glow_sources(session, reduced: Dictionary = {}) -> Array:
	var out: Array = []
	var amult := float(reduced.get("glow_alpha_mult", 1.0)) if not reduced.is_empty() else 1.0
	var sources: Array = []
	for entry in session.sim.active:
		var kind := str(entry.get("kind", ""))
		if kind == "projectile" or kind == "orb":
			var fx = entry["effect"]
			sources.append([fx.position, str(fx.root.get("essence", {}).get("id", "")), -1.0])
	for v in session.sim.visuals:
		var vk := str(v.get("kind", ""))
		if vk == "field" or vk == "burst":
			sources.append([v["position"], str(v.get("essence", "")), float(v.get("radius", -1.0))])
	for s in sources:
		var cfg: Dictionary = Data.element_cfg(s[1]).get("glow", {})
		if cfg.is_empty():
			continue
		var radius := float(cfg["radius"]) if s[2] < 0.0 else maxf(float(cfg["radius"]), float(s[2]))
		var color := Color(Art.essence_color(s[1]), float(cfg["alpha"]) * amult)
		if not reduced.is_empty():
			color = reduced_color(color, reduced)
		out.append({"at": s[0], "radius": radius, "color": color, "texture": str(cfg.get("texture", ""))})
	return out
