# AD-149 spell particles, glow and hit flash: perf probe and captures

Date: 2026-11-06 · Godot 4.7.1-stable (official) · headless probe uses the dummy renderer; captures ran under xvfb.

## Reproduce

```
/usr/local/bin/godot --headless --path . --script res://tests/m4_stress_probe.gd
xvfb-run -a /usr/local/bin/godot --path . --script res://tests/capture_ad_vfx.gd -- docs/playtests/ad_vfx
```

## What was added

- `ui/vfx/vfx_layer.gd` (child `Vfx` of the combat canvas): additive pooled particles (per-element trails, impacts, status motes) plus additive glow sprites for projectiles, orbs and bursts. Pool is fixed-size, advances only when the sim tick changes, and never writes sim state.
- `ui/vfx/hit_flash_overlay.gd` (child `HitFlash`) with `shaders/hit_flash.gdshader`: white silhouette over damaged actors.
- Tuning lives in `world/data/vfx_v1.json`: `particle_cap` and `spawn_per_tick_cap` (per quality mode high/low/off, tied to the lighting setting), `elements.<id>` (trail, impact, glow), `status.<id>` (colour, rise, rate_period_ticks, life_ticks, size), `reduced` (glow_alpha_mult, impact_count_mult, max_alpha, no_white_core), `hit_flash` (ticks, strength, reduced_strength, color), `particle_texture`, `glow_texture`, `fallback_texture_px`.

## Missing art: procedural fallbacks

The AD-117 particle textures and the game-art `*_glow` layers are not in the repo, so `Data.texture` generates procedural radial textures. When they land, fill `particle_texture` / `glow_texture` in `vfx_v1.json`, or the per-element `glow.texture`; no code change is needed.

## Reduce flashes / reduce shake

- `reduce_flashes` (Settings, or the session's own flag) removes the white hit-flash entry for the mage and uses `hit_flash.reduced_strength` (currently 0.0, so none) for enemies; glow alpha, impact count and peak alpha are scaled by `reduced`, and the white core is dropped.
- Reduced mode also zeroes particle velocity jitter when `ReduceMotion.particle_jitter_enabled` is false, and camera shake follows `ReduceMotion.shake_offset`.
- Covered by `tests/test_ad_vfx.gd` and `tests/test_ad_reduce_motion.gd`.

## Perf probe (AD-087 method, s1_boss, Split+Pierce+Homing Fire + On Hit Lightning Burst)

Same 300-frame render pass as AD-148 with lighting/VFX `high`, then 300 frames with it `off` (cap 0). `process ms` is `Performance.TIME_PROCESS`; the second pass continues the same sim, so the comparison is rough.

| Metric | Value |
|---|---|
| particles peak / cap | 256 / 256 (saturated; `vfx_within_cap` true, pool never grew) |
| glow sprites peak | 76 |
| process ms p95, VFX high | 76.5 |
| process ms p95, VFX off | 210.9 (host noise: the off pass ran slower, so no per-frame overhead can be claimed) |
| sim p95 (unchanged AD-087 check) | 72.2 ms vs 4.0 ms budget: **FAILS** |

The AD-087 sim budget already fails on this non-reference host (see AD-148 note); VFX is render-only and does not affect it. BUDGET_MS is not loosened. The dummy renderer does not draw, so GPU cost still needs a real-GPU check on the reference machine.

## Captures (Ruins combat room, 1280x720)

| Element | Trail | Impact |
|---|---|---|
| Fire | [trail](ad_vfx/trail_fire.png) | [impact](ad_vfx/impact_fire.png) |
| Water | [trail](ad_vfx/trail_water.png) | [impact](ad_vfx/impact_water.png) |
| Lightning | [trail](ad_vfx/trail_lightning.png) | [impact](ad_vfx/impact_lightning.png) |
| Cold | [trail](ad_vfx/trail_cold.png) | [impact](ad_vfx/impact_cold.png) |
| Force | [trail](ad_vfx/trail_force.png) | [impact](ad_vfx/impact_force.png) |

Status particles: [burning](ad_vfx/status_burning.png), [wet](ad_vfx/status_wet.png), [charged](ad_vfx/status_charged.png), [chilled](ad_vfx/status_chilled.png), [all four on different enemies](ad_vfx/status_all.png).
Hit flash: [on](ad_vfx/hit_flash_on.png), [reduce_flashes](ad_vfx/hit_flash_reduced.png).
