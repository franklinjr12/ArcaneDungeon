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
