# Demo full-run bench

`run_bench.gd` plays the whole `world/data/run_v2.json` run with a scripted player for the `weak`, `typical` and `skilled` builds over 20 seeds (`SEEDS`, 20261022..20261041) and prints the BENCH_MD tables used by `docs/benchmarks/ad_demo_bench.md`. No gameplay change; sims run with `record_trace=false`.

G = `/usr/local/bin/godot --headless --path . --script res://tests/bench/run_bench.gd --`

## Options

| flag | meaning |
|---|---|
| `--seeds=N` | legacy: first N seeds, all in one process, prints the tables, replays the first seed per build as a determinism check |
| `--seeds=A..B` | chunk mode: 0-based inclusive indices into `SEEDS`; one result file per seed+build; existing results are skipped; no determinism replay |
| `--builds=a,b` | subset of builds (default all three) |
| `--results=DIR` | result folder (default `user://bench_results`) |
| `--jobs=N` | run N headless child processes in parallel (use 2 on the 2-core host) |
| `--summarize` | build the BENCH_MD tables from the result files; runs nothing |
| `--trace` | record sim traces (slower; for debugging only) |

## Full 20 seed x 3 build workflow

```
G --seeds=0..4 --jobs=2
G --seeds=5..9 --jobs=2
G --seeds=10..14 --jobs=2
G --seeds=15..19 --jobs=2
G --summarize
```

Each chunk prints `AD_DEMO_BENCH_WALL seed=... build=... wall_s=...` per pair. If a step is interrupted, re-run the same chunk command: finished pairs print `AD_DEMO_BENCH_SKIP` and only the rest are played. `--summarize` over an incomplete set still exits 0 but prints `AD_DEMO_BENCH_PARTIAL have=.. want=.. missing=..`.

## Result files

`DIR/<seed>_<build>.json` holds `{fingerprint, trace, wall_seconds, run}`. The fingerprint covers the bench script and the files it depends on; if it differs, the pair is re-played. Code changes outside the fingerprinted files are not detected: use a fresh `--results` folder after them. Do not commit result folders.

## Related

`tests/bench/boss_pacing_bench.gd` checks the final-boss window 150-210 s and may exit 1 on the current balance.

The scripted-player sanity table also reports `dashes per fought room (mean)` (report only, no threshold).

## AD-228 v1.1 bot mechanics

The bot in `run_bench.gd` now plays the v1.1 mechanics. No game code or data changed.

**What it dodges** (one dash roll per threat instance, still the single `DODGE_CHANCE` = 0.7 for every build; the dash fires once the telegraph deadline is within `DODGE_LEAD_TICKS`):

| threat type | telegraph data read |
|---|---|
| `lunge` / `boss_charge` | enemy intent snapshot `geometry=line` (`origin`, `direction`, `range`), enemy in `windup`; sidestep perpendicular to the line |
| `swipe_arc` (Ghoul) | snapshot `telegraph_shape=arc` (`arc_center`, `arc_radius`); dash away from the centre |
| `slam` / `boss_slam` (Riptide leaper, boss leap) | snapshot `telegraph_shape=slam` (`landing`, `range`); dash away from the landing point |
| `boss_beam` | snapshot `kind=beam_sweep` (`origin`, `range`, `beam_angle`) plus the live `boss_beam` hazard (`beam_angle`, `beam_width`, `radius`) |
| `tide_wave` | `boss_tide_wave` hazard (`y`, `thickness`, `gap_x`, `gap_width`); steer to the gap, dash when close |
| `boss_zone` | `boss_warning` / `boss_zone` / `boss_water_warning` hazards (`position`+`radius` or `rect`, `duration_ticks`, `age`) |
| `shot` | `session.enemy_shots` within 110 px |
| `melee` | generic windup fallback (`attack_range`) for enemies with no specific shape |

**Element mixing (typical and skilled).** The workshop picks two different essences once two are unlocked (water+lightning first, then other reacting pairs). Casts then alternate: prefer the slot whose essence reacts with a status already on the target, else the one that differs from the last cast essence. This triggers reactions (resonance refund, AD-193).

**Sigil Desk (AD-224).** At the Sigil Desk visits the typical/skilled bots equip the best runes found so far (`workshop: mix` / `best`).

**Weak bot** stays naive: first rune, no workshop edits, no shop, plain slot rotation, no mixing.

### INFO 2026-11-11: 8-seed results (seeds 20261022..20261029, all 3 builds)

Commands (`G="/usr/local/bin/godot --headless --path . --script res://tests/bench/run_bench.gd --"`), results in `/tmp/ad228_bench` (not committed):
`G --seeds=0..3 --jobs=2 --results=/tmp/ad228_bench`, `G --seeds=4..7 --jobs=2 --results=/tmp/ad228_bench`, `G --summarize --results=/tmp/ad228_bench` (prints `AD_DEMO_BENCH_PARTIAL have=24 want=60`, exit 0).
Route determinism: `godot --headless --path . --script res://tests/qa/demo_smoke.gd -- --seeds=2 --det-seeds=2` exits 0, `AD_DEMO_DETERMINISM ... ok=true` for both seeds.

Wins per build:

| build | wins | dies stage 1 or first boss |
|---|---|---|
| weak | 1/8 | 1/8 |
| typical | 1/8 | 1/8 |
| skilled | 0/8 | 1/8 |

Dodges per threat type (attempted / succeeded):

| threat type | weak | typical | skilled |
|---|---|---|---|
| melee | 128 / 126 | 139 / 136 | 126 / 123 |
| shot | 91 / 79 | 100 / 84 | 85 / 76 |
| swipe_arc | 14 / 14 | 20 / 20 | 28 / 28 |
| lunge | 1 / 1 | 5 / 5 | 3 / 3 |
| slam | 2 / 2 | 3 / 3 | 4 / 4 |
| boss_slam | 36 / 36 | 36 / 36 | 25 / 25 |
| boss_zone | 8 / 8 | 11 / 11 | 14 / 14 |
| boss_beam | 0 / 0 | 7 / 3 | 8 / 4 |
| tide_wave | 2 / 2 | 2 / 2 | 2 / 2 |
| boss_charge | 0 / 0 | 0 / 0 | 0 / 0 |

`boss_charge` was never attempted on these 8 seeds, so that path is not exercised here. `boss_beam` is the only type with a low success rate (42.9% typical, 50% skilled).

Reactions per fought room (resonance popups):

| build | boss rooms: reactions (mean) | challenge | combat | all |
|---|---|---|---|---|
| weak | 170 (11.333) | - | 214 (4.756) | 384 (6.4) |
| typical | 4 (0.308) | 4 (0.667) | 135 (3.068) | 143 (2.27) |
| skilled | 6 (0.545) | 6 (1.0) | 131 (2.977) | 143 (2.344) |

Top reactions: weak `water_extinguish` 384; typical `water_extinguish` 128, `wet_lightning_arc` 15; skilled `water_extinguish` 129, `wet_lightning_arc` 14. The weak bot's higher count is `water_extinguish` from its single water spell, not mixing. The mixing bots add `wet_lightning_arc` but get few reactions in boss rooms.

## AD-236 warden bench meta profile

`warden_bench.gd` takes `--meta=fresh|full` (user args after `--`, default `fresh`, behaviour unchanged). `full` sets every Scriptorium upgrade to `MetaProgress.max_tier(id)` (15 tiers) and applies `MetaProgress.bonuses` to the session like `run_flow.gd` does at run start (max HP, max mana, regen multiplier). Each fight line carries `meta=` and `damage_taken=`; each summary line adds `wins`, `losses` and `median_damage_taken`.

```
/usr/local/bin/godot --headless --path . --script res://tests/bench/warden_bench.gd -- --meta=full | grep WARDEN_BENCH_SUMMARY
```

## AD-241 room pool 12/14 + affixes

Command (all 20 seeds x 3 builds, results in a scratch folder, not committed):
`for r in 0..4 5..9 10..14 15..19; do G --seeds=$r --jobs=2 --results=$TMPDIR/b241; done`, then read `run.total_seconds` of every `won` result file.

Outcomes: weak 11/20 won, typical 9/20, skilled 4/20 (60 runs, 24 wins).

Full successful runs, minutes (`total_seconds / 60`):

| build | wins | median | min | max |
|---|---|---|---|---|
| weak | 11 | 2.3 | 2.1 | 2.7 |
| typical | 9 | 3.1 | 2.7 | 3.8 |
| skilled | 4 | 3.1 | 3.1 | 3.1 |
| all | 24 | 2.8 | 2.1 | 3.8 |

**Not in the 18-25 min target.** The scripted player clears rooms in seconds (see the AD-2xx note in `docs/benchmarks/ad_demo_bench.md`: bench runs are 2-5 min, not 30-40), so adding 8 rooms and affixes does not move the bot's run length into 18-25 min. No room data was tuned: enemy HP is not stretched (no HP sponges) and the boss numbers and feel bands are frozen. The 18-25 min figure needs a human playtest, not this bot.

## AD-264 Archivist storm_conduct rendered frame-time bench

`archivist_storm_render_bench.gd` opens the real `run.tscn` on `cistern_boss` (live data), steps it with `run_controller.perf_step` and measures frames before and after the boss's own `_fire_storm_pulse` runs `storm_conduct` on the full cistern (re-fired whenever the water goes dark). Needs a display; under `--headless` it prints `AD264_RENDER_BENCH_SKIP` and exits 2.

```
xvfb-run -a -s "-screen 0 1920x1080x24" /usr/local/bin/godot --path . --script res://tests/bench/archivist_storm_render_bench.gd -- --size=1920x1080 --frames=60 --budget-ms=33
```

Per phase (`calm`, `electrified`) it prints two lines: `_wall` = frame to frame including GPU raster (vsync off); `_cpu` = `perf_step` through every canvas `_draw` up to `RenderingServer.frame_pre_draw` (raster excluded). Then a probe canvas times the water draw path piece by piece (`AD264_RENDER_BENCH_PROFILE`) and prints per-frame call counts (`AD264_RENDER_BENCH_COUNTS`). **Exit 1 when any `electrified_cpu` frame is over `--budget-ms`** (default 33): this is the gate AD-256 a) should turn green. About 3 min per run on the VM.

### INFO 2026-11-26: VM results (diagnosis, no fix)

VM: Xvfb, `opengl3` on `llvmpipe (LLVM 21.1.8)` software GL, 2 CPUs, Godot 4.7.1, `gl_compatibility`, project viewport 1280x720 `canvas_items`/`expand`, `use_art_export=false` (default). Cistern: 4 water rects, `storm_conduct` = 120 ticks / 5 dmg / 20-tick interval; one pulse electrifies **169 cells**.

| size | phase | cpu mean | cpu p95 | cpu max | cpu frames > 33 ms | wall mean |
|---|---|---|---|---|---|---|
| 1920x1080 | calm | 15.5 ms | 24.0 | 25.7 | 0/60 | 1102 ms |
| 1920x1080 | electrified | 36.2 ms | 51.6 | 81.7 | 43/60 | 1239 ms |
| 1280x720 | calm | 26.5 ms* | 64.1 | 73.9 | 17/60 | 728 ms |
| 1280x720 | electrified | 36.6 ms | 54.7 | 66.5 | 45/60 | 582 ms |

\* 720p calm had VM noise spikes (p50 20.6 ms). An earlier 1080p run gave calm 13.9 / electrified 42.5 ms mean (max 69, 55/60 over). Sim time stays < 1 ms mean (max ~5 ms) in both phases, which is why the headless AD-256 test passes. The **wall** numbers (0.6-1.3 s per frame even when calm) are llvmpipe software raster and say nothing about a real GPU; only the `_cpu` lines are comparable to Franklin's machine.

**It reproduces on the CPU side: electrifying the cistern adds ~20-28 ms of main-thread time per frame**, pushing 70-90 % of frames past 33 ms.

Hot spot, per frame while electrified (probe means, 1080p run, 1 call each per frame unless noted):

| function | mean ms | per-frame call counts |
|---|---|---|
| `ui/pixel_art_renderer.gd` `draw_water` (total) | 15.9 | 1 |
| of which `_draw_water_states` (line ~464) | 15.7 | 1; loops 169 cells; 169 `draw_texture_rect_region` + 169 `_queue_glow` |
| `extra_sheet_frame` (line ~346), called per cell | 9.0 | **169** calls; each does `FileAccess.file_exists(json)` + `ResourceLoader.exists(png)` + `ResourceLoader.exists(glow_png)` = **507 filesystem checks/frame** (5.4 ms of the 9.0) plus dictionary/Rect2 building |
| `world/water_tiles.gd` `state_view` (line ~187) | 2.0 | 1; `sort_custom` with a GDScript lambda (~906 comparator calls) + 169 dict `map` |
| deep-rect test + `water_state_tag` loop | 2.2 | 169 `water_state_tag`, 169 `Rect2.has_point` (1 deep rect) |
| `draw_actor_glows` (the 169 water glows, vfx layer) | 0.4 | 1; 169 additive quads |
| base water `_draw_water_cells` | ~0.2 | 150 cell draws (unchanged by electrify) |

Named hot spot: **`pixel_art_renderer._draw_water_states` → per-cell `extra_sheet_frame` (507 filesystem `exists` checks per frame) and the per-frame `WaterTiles.state_view` lambda sort**. The probe accounts for ~16 ms of the ~21-28 ms delta; the remaining ~5-12 ms is not attributed by the probe (likely contention between the main thread and llvmpipe raster threads on 2 cores, plus GPU-side cost of the 2 x 169 extra quads), so expect a smaller delta on a real GPU.

What differs from Franklin's machine: real GPU vs llvmpipe software raster (wall times not comparable); 2 VM cores shared with raster threads; Xvfb window instead of a desktop window/fullscreen; the bench sets vsync off and `Engine.max_fps = 0`; filesystem `exists` cost depends on disk and OS (not measured on Windows; if it is slower there, the freeze would be worse). Not measured: an exported build (`res://` from a .pck instead of the filesystem).

## AD-256 Archivist lightning-on-water freeze

Hot spot (AD-264 rendered bench, 1920x1080, 169 electrified cistern cells): `Art._draw_water_states` did, per cell and per frame, an `extra_sheet_frame` lookup (3 filesystem/`ResourceLoader.exists` checks each, ~507 per frame), a deep-rect test and `water_state_tag`, one `draw_texture_rect_region`, one `_queue_glow`, on top of a per-frame `state_view` rebuild/sort (~900 sort-lambda calls). Reproduced loop cost was ~8.7 ms mean / 31 ms max for `extra_sheet_frame` alone.

Replaced by: `WaterTiles.electrified_rects()` (merged rects, cached between state changes), one shared flicker tint `draw_rect` per merged rect (alpha from tick only, constant under reduced motion) and at most `spark_cap` (6) deterministic sparks from `Art.water_electric_sparks`. Frozen cells keep the sheet path but cache frames per call and skip entirely when nothing is frozen.

Command: `xvfb-run -a -s "-screen 0 1920x1080x24" godot --path . --script res://tests/bench/archivist_storm_render_bench.gd -- --size=1920x1080 --frames=60 --budget-ms=33` (software GL llvmpipe, 2 CPUs). Result `ok=true`: `electrified_cpu` mean 9.65 ms, p95 18.94 ms, max 29.84 ms, 0 frames over 33 ms (the bench's own `_draw_water_states` timer: 0.018 ms mean). The bench's per-cell "loop:" and COUNTS lines still replay the old per-cell path for comparison and are not the current draw cost.

## AD-257 combo DPS bench

| script | prints |
|---|---|
| `ad257_combo_bench.gd` (headless, seeds 257001..257003, 600 ticks, 4 dummies) | `AD257_BENCH seed=.. single_dps=.. combo_dps=.. ratio=..`: best single-skill spam vs best combo rotation, same sim as `test_ad_257_d_combo_dps_bar` (bar: ratio >= `combos.balance.min_ratio` 1.6) |
