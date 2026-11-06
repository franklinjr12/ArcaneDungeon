extends RefCounted
## AD-083: central reduce-flash / reduce-shake policy. Presentation only; pure static helpers.
const VfxData = preload("res://ui/vfx/vfx_data.gd")
const FLASH_EVENTS := ["hit.spark", "reaction.arc", "boss.phase"]
const MAX_TINT_HZ := 3.0
## [PROPOSED FOR PROTOTYPE] peak shake amplitude in pixels and the hit_flash value it scales against.
const SHAKE_PX := 3.0
const HIT_FLASH_REF := 10.0
const REDUCED_HURT := Color(1.0, 0.72, 0.72)
const REDUCED_FX := Color(1, 1, 1, 0.45)

static func flashes_reduced(settings, session) -> bool:
	if settings != null and settings.reduce_flashes:
		return true
	return session != null and session.reduce_flashes

static func shake_enabled(settings) -> bool:
	return settings == null or settings.screen_shake

static func shake_offset(settings, hit_flash: int, tick: int) -> Vector2:
	if not shake_enabled(settings) or hit_flash <= 0:
		return Vector2.ZERO
	var amp := SHAKE_PX * minf(float(hit_flash), HIT_FLASH_REF) / HIT_FLASH_REF
	return Vector2(amp if tick % 2 == 0 else -amp, 0.0)

static func hurt_tint(reduced: bool, hit_flash: int) -> Color:
	if hit_flash <= 0 or not reduced:
		return Color.WHITE
	return REDUCED_HURT

static func overlay_alpha(reduced: bool, hit_flash: int) -> float:
	if reduced:
		return 0.0
	return 0.055 if hit_flash > 0 and hit_flash % 3 == 0 else 0.0

## AD-088: telegraphs are never suppressed/dimmed by reduce-flash; softness and swell come from world/data/presentation_v1.json.
static func fx_draw_params(reduced: bool, event: String, age: int) -> Dictionary:
	if not reduced or event.begins_with("telegraph.") or not FLASH_EVENTS.has(event):
		return {"age": age, "modulate": Color.WHITE}
	return {"age": 0, "modulate": REDUCED_FX}

## AD-149: VFX multipliers from world/data/vfx_v1.json `reduced`; empty when full effects are on.
static func vfx_params(reduced: bool) -> Dictionary:
	if not reduced:
		return {}
	return VfxData.reduced_cfg().duplicate(true)

## AD-149: actor hit-flash strength (0..1). Always 0 when reduce-flash is on; otherwise fades over `total` ticks.
static func hit_flash_strength(reduced: bool, ticks_left: int, total: int) -> float:
	var cfg: Dictionary = VfxData.hit_flash_cfg()
	if reduced:
		return float(cfg.get("reduced_strength", 0.0))
	if ticks_left <= 0 or total <= 0:
		return 0.0
	return float(cfg.get("strength", 0.0)) * clampf(float(ticks_left) / float(total), 0.0, 1.0)

## AD-149: reduce-shake (screen_shake off) also disables positional particle jitter / kick.
static func particle_jitter_enabled(settings) -> bool:
	return shake_enabled(settings)
