# AD-148 2D lighting: perf probe and lit/unlit captures

Date: 2026-11-06 · Base commit: 26935d4 (captures and probe run on top of it) · Godot 4.7.1-stable (official) · headless probe uses the dummy renderer.

## Reproduce

```
/usr/local/bin/godot --headless --path . --script res://tests/m4_stress_probe.gd
xvfb-run -a godot --path . --script res://tests/capture_ad_lighting.gd -- docs/playtests/ad_lighting
```

## Perf probe (AD-087 method, s1_boss, Split+Pierce+Homing Fire + On Hit Lightning Burst)

The render section forces Settings.lighting `high`, runs 300 frames, then repeats 300 frames with lighting `off`.
`process ms` is `Performance.TIME_PROCESS` per frame. The second pass continues the same sim, so the lit/off comparison is rough.

| Metric | Value |
|---|---|
| spell lights peak / cap / pool size | 24 / 24 / 24 (cap saturated; `lights_within_cap` true) |
| process ms p95, lighting high | 242.06 |
| process ms p95, lighting off | 228.17 |
| sim p95 (context, unchanged AD-087 check) | 76.35 ms vs 4.0 ms budget: **FAILS** |

The AD-087 sim budget already FAILS on this non-reference host (and the host was loaded: the probe took ~80 s instead of ~22 s). Lighting is render-only and never read by the sim, so it does not affect that result. The dummy renderer does not draw lights, so process ms only covers node and script cost (about 6% over `off` here), not GPU cost. A real-GPU frame-time check on the reference machine is still needed.

## Captures

Run screen at 1280x720, lighting High (`_lit`) vs Off (`_unlit`):

| Room | Lit | Unlit |
|---|---|---|
| Ruins combat | [lit](ad_lighting/ruins_combat_lit.png) | [unlit](ad_lighting/ruins_combat_unlit.png) |
| Cistern combat | [lit](ad_lighting/cistern_combat_lit.png) | [unlit](ad_lighting/cistern_combat_unlit.png) |
| Ruins boss | [lit](ad_lighting/ruins_boss_lit.png) | [unlit](ad_lighting/ruins_boss_unlit.png) |
| Cistern boss | [lit](ad_lighting/cistern_boss_lit.png) | [unlit](ad_lighting/cistern_boss_unlit.png) |
| Spells in flight + enemy windup (Cistern) | [lit](ad_lighting/telegraph_spells_lit.png) | [unlit](ad_lighting/telegraph_spells_unlit.png) |

The script waits for an enemy mid-windup with spell lights active, but gives up after 400 ticks and shoots anyway. Confirm the windup is visible in the telegraph pair when reviewing.

## Design note

- Ambience is a SUB DirectionalLight2D on arena light mask 2 rather than a CanvasModulate, so the HUD and UI stay undimmed.
- Cookie is a procedural radial gradient because the AD-117 cookies are not in the repo. `cookie_texture` in the data can point at a real texture.
- Spell lights come from a fixed pool sized to the mode cap (high 24, low 8, off 0); the pool never grows.
- All values are [PROPOSED FOR PROTOTYPE] in `world/data/lighting_v1.json`.

## Telegraph readability - pending game-design review

- [ ] Ruins combat: enemy telegraphs (circle, line, dash lane) readable at least as well as unlit.
- [ ] Cistern combat: telegraphs not lost against the blue ambience and fixed lights.
- [ ] Both boss arenas: warden windup and phase cue readable; arena fill feels lit, not washed out.
- [ ] 24 spell lights in flight do not hide or tint a telegraph into another colour.
- [ ] Low mode (8 lights) is an acceptable fallback; Off matches the previous look.
- [ ] Player, projectiles and hazards remain distinguishable in both biomes.
