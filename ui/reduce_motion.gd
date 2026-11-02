extends RefCounted
## AD-083: central reduce-flash / reduce-shake policy. Presentation only; pure static helpers.
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

static func fx_draw_params(reduced: bool, event: String, age: int) -> Dictionary:
	if not reduced or event.begins_with("telegraph.") or not FLASH_EVENTS.has(event):
		return {"age": age, "modulate": Color.WHITE}
	return {"age": 0, "modulate": REDUCED_FX}
