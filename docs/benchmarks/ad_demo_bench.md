# AD demo full-run benchmark (AD-156)

Command (about 35 min wall time for the full set; `-- --seeds=N --builds=a,b` runs a subset):

```
/usr/local/bin/godot --headless --path . --script res://tests/bench/run_bench.gd
```

Plays the whole `world/data/run_v2.json` run (ruins, workshop, cistern, final boss) with a scripted player. Scripted player only; no gameplay change. After the 20x3 runs it re-runs the first seed of every build and fails (`AD_DEMO_BENCH nondeterministic`) if the JSON differs.

Seeds: [20261022 .. 20261041] (20 consecutive seeds).

## Reference builds

- `weak`: starter loadout only (run_v2 initial_formulas). Takes the first reward option, never edits spells, never buys, skips optional rooms.
- `typical`: picks the first not-yet-unlocked rune reward. At the workshop buys the max-HP upgrade if affordable and applies one simple edit to editor slot 0 (water + projectile + first earned modifier). Takes optional rooms.
- `skilled`: picks runes by priority (essence.water, essence.lightning, essence.cold, mod.chain, mod.pierce, mod.homing, form.burst, ...). At the workshop buys in priority order (HP, rune, mana, dash, artifact) and builds the best legal formula it can for editor slots 0 and 1 (validated before applying). Takes optional rooms.

## Reasonable-player constants (top of `run_bench.gd`)

- Combat policy: kite at 120-220 px, navigate when out of sight, cycle slots 1.. then the slot 0 bolt, dash on telegraph or shot.
- `AIM_JITTER` 0.08 rad: random aim/cursor angle error per tick.
- `DODGE_CHANCE` 0.7: chance a given threat is dodged (rolled once per threat).
- `NAV_TICKS` 6: path-finding re-plan interval.
- `STUCK_TICKS` 6 / `NUDGE_TICKS` 12: sidestep when the player has not moved for 6 ticks (works around corners the navigation misjudges).
- `POINT_BLANK` 60 px: shoots the bolt at a foe this close even if the sight check fails.
- `ROOM_CAP_SECONDS` 360: a capped room ends the run as `timeout`. Per-run RNG is seeded from (seed, build name); no wall-clock time is read.
- "Total min" includes the ticks walking to each exit. "Max room s" is the fight time of one room (walking excluded). "Starved %" is mana-starved ticks / combat ticks (mana below the cheapest equipped spell cost).

## Targets (Demo Plan v1 §2, DECIDED D1)

- Winning run takes 30-40 min of sim time (typical and skilled wins; median per build). Bench sim time excludes menu and reading time.
- A weak starter build dies in stage 1 or at the first boss (ruins_boss) on most seeds (>= 11 of 20).
- No room takes more than 4 min (all builds).
- Mana-starved time < 20% of combat time (median per build).

## Before (pre-AD-156 tuning)

BENCH_MD_BEGIN
**weak**

| seed | outcome | died in | total min | max room s | starved % | rooms cleared |
|---|---|---|---|---|---|---|
| 20261022 | dead | stage2_boss | 3.764 | 91.567 | 56.327 | 12 |
| 20261023 | dead | stage2_boss | 2.626 | 35.633 | 56.085 | 11 |
| 20261024 | dead | stage2_boss | 2.052 | 25.333 | 59.841 | 12 |
| 20261025 | dead | stage2_boss | 3.143 | 52.883 | 58.226 | 13 |
| 20261026 | dead | stage2_boss | 3.588 | 85.25 | 59.371 | 12 |
| 20261027 | dead | stage2_rooms | 1.901 | 35.767 | 64.71 | 8 |
| 20261028 | dead | stage2_boss | 3.139 | 44.833 | 58.529 | 12 |
| 20261029 | dead | stage2_boss | 2.653 | 25.5 | 61.595 | 13 |
| 20261030 | dead | stage2_boss | 2.536 | 40.3 | 59.364 | 11 |
| 20261031 | won | - | 3.491 | 94.0 | 56.877 | 13 |
| 20261032 | dead | stage2_boss | 3.483 | 70.767 | 55.054 | 13 |
| 20261033 | won | - | 3.369 | 86.15 | 55.927 | 14 |
| 20261034 | dead | stage2_boss | 2.952 | 78.017 | 54.497 | 11 |
| 20261035 | dead | stage2_boss | 3.719 | 93.483 | 55.41 | 12 |
| 20261036 | dead | stage2_boss | 2.262 | 25.717 | 65.497 | 12 |
| 20261037 | dead | stage2_boss | 2.237 | 35.617 | 55.27 | 11 |
| 20261038 | dead | stage2_boss | 4.035 | 96.667 | 61.999 | 12 |
| 20261039 | dead | stage2_boss | 2.849 | 35.633 | 57.71 | 12 |
| 20261040 | dead | stage2_boss | 3.082 | 72.683 | 54.401 | 11 |
| 20261041 | dead | stage2_boss | 2.848 | 65.15 | 52.141 | 12 |

**typical**

| seed | outcome | died in | total min | max room s | starved % | rooms cleared |
|---|---|---|---|---|---|---|
| 20261022 | dead | stage2_boss | 3.899 | 56.2 | 56.896 | 13 |
| 20261023 | dead | stage2_rooms | 3.174 | 52.567 | 65.238 | 11 |
| 20261024 | dead | stage2_rooms | 3.096 | 80.5 | 54.206 | 12 |
| 20261025 | dead | stage2_boss | 4.842 | 103.6 | 51.121 | 14 |
| 20261026 | dead | stage2_rooms | 3.801 | 96.033 | 55.812 | 12 |
| 20261027 | dead | stage2_boss | 3.35 | 67.75 | 58.468 | 12 |
| 20261028 | dead | stage2_rooms | 4.281 | 105.683 | 55.246 | 12 |
| 20261029 | dead | stage2_rooms | 3.302 | 65.2 | 58.721 | 13 |
| 20261030 | dead | stage2_boss | 3.491 | 38.667 | 55.296 | 12 |
| 20261031 | dead | stage2_rooms | 3.177 | 61.05 | 60.613 | 12 |
| 20261032 | dead | stage2_rooms | 4.158 | 116.117 | 56.8 | 13 |
| 20261033 | dead | stage2_rooms | 3.079 | 50.95 | 56.386 | 13 |
| 20261034 | dead | stage2_rooms | 3.054 | 58.433 | 59.77 | 11 |
| 20261035 | dead | stage2_rooms | 4.168 | 106.7 | 54.947 | 12 |
| 20261036 | dead | stage2_boss | 3.55 | 73.667 | 55.651 | 13 |
| 20261037 | dead | stage2_boss | 3.296 | 53.167 | 57.629 | 12 |
| 20261038 | dead | stage2_rooms | 3.165 | 50.717 | 63.073 | 12 |
| 20261039 | dead | stage2_rooms | 3.682 | 53.383 | 59.326 | 12 |
| 20261040 | dead | stage2_rooms | 3.492 | 81.117 | 58.512 | 11 |
| 20261041 | dead | stage2_boss | 3.303 | 60.417 | 56.911 | 13 |

**skilled**

| seed | outcome | died in | total min | max room s | starved % | rooms cleared |
|---|---|---|---|---|---|---|
| 20261022 | dead | stage2_rooms | 3.589 | 73.2 | 55.618 | 12 |
| 20261023 | dead | stage2_rooms | 2.934 | 55.783 | 54.435 | 11 |
| 20261024 | dead | stage2_rooms | 2.803 | 57.533 | 56.115 | 12 |
| 20261025 | dead | stage2_boss | 3.89 | 54.667 | 56.948 | 14 |
| 20261026 | dead | stage2_rooms | 3.625 | 102.717 | 54.642 | 12 |
| 20261027 | dead | stage2_boss | 2.881 | 39.7 | 62.074 | 12 |
| 20261028 | dead | stage2_boss | 3.442 | 72.433 | 53.902 | 13 |
| 20261029 | dead | stage2_boss | 3.44 | 45.95 | 61.347 | 14 |
| 20261030 | dead | stage2_boss | 3.328 | 51.433 | 58.464 | 12 |
| 20261031 | dead | stage2_boss | 3.387 | 52.3 | 56.635 | 13 |
| 20261032 | dead | stage2_rooms | 3.053 | 51.4 | 59.871 | 13 |
| 20261033 | dead | stage2_rooms | 2.831 | 50.2 | 56.239 | 13 |
| 20261034 | dead | stage2_rooms | 2.859 | 63.4 | 54.721 | 11 |
| 20261035 | dead | stage2_rooms | 3.197 | 39.517 | 62.359 | 12 |
| 20261036 | dead | stage2_boss | 3.133 | 34.133 | 60.594 | 13 |
| 20261037 | dead | stage2_rooms | 3.362 | 109.933 | 50.102 | 11 |
| 20261038 | dead | stage2_rooms | 3.428 | 65.783 | 58.011 | 12 |
| 20261039 | dead | stage2_rooms | 3.759 | 94.7 | 57.086 | 12 |
| 20261040 | dead | stage2_rooms | 3.291 | 66.367 | 53.4 | 11 |
| 20261041 | dead | stage2_boss | 3.123 | 59.267 | 58.855 | 13 |

| build | wins | win total min (median/min/max) | dies stage 1 or first boss | max room s | starved % median | starved % max |
|---|---|---|---|---|---|---|
| weak | 2/20 | 3.43 / 3.369 / 3.491 | 0/20 | 96.667 | 57.294 | 65.497 |
| typical | 0/20 | - | 0/20 | 116.117 | 56.904 | 65.238 |
| skilled | 0/20 | - | 0/20 | 109.933 | 56.792 | 62.359 |

| target | weak | typical | skilled |
|---|---|---|---|
| winning run 30-40 min sim | n/a | NO (median 0.0 min, 0 wins) | NO (median 0.0 min, 0 wins) |
| weak build dies in stage 1 or at the first boss on most seeds | NO (0/20 dead early, need 11) | n/a | n/a |
| no room > 4 min | PASS (max 96.667 s) | PASS (max 116.117 s) | PASS (max 109.933 s) |
| mana-starved < 20% | NO (median 57.294%) | NO (median 56.904%) | NO (median 56.792%) |

| room | n | median s | min s | max s | median HP lost | min HP lost | max HP lost |
|---|---|---|---|---|---|---|---|
| cistern_boss | 34 | 41.109 | 4.2 | 96.667 | 75.5 | 8.0 | 112.0 |
| cistern_challenge_v1 | 40 | 57.983 | 25.683 | 116.117 | 70.0 | 0.0 | 153.0 |
| cistern_p01 | 27 | 5.35 | 4.567 | 6.683 | 0.0 | 0.0 | 11.0 |
| cistern_p02 | 27 | 10.7 | 5.417 | 37.883 | 9.0 | 0.0 | 29.0 |
| cistern_p03 | 30 | 8.258 | 6.967 | 11.633 | 9.0 | 0.0 | 27.0 |
| cistern_p04 | 27 | 9.217 | 7.833 | 14.383 | 9.0 | 0.0 | 18.0 |
| cistern_p05 | 44 | 6.034 | 3.717 | 11.083 | 0.0 | 0.0 | 0.0 |
| cistern_p06 | 27 | 6.833 | 6.233 | 7.783 | 0.0 | 0.0 | 0.0 |
| cistern_p07 | 33 | 8.183 | 6.333 | 11.083 | 11.0 | 0.0 | 11.0 |
| cistern_p08 | 27 | 11.233 | 10.267 | 13.617 | 0.0 | 0.0 | 10.0 |
| cistern_p09 | 41 | 6.467 | 5.083 | 7.417 | 0.0 | 0.0 | 7.0 |
| cistern_p10 | 42 | 20.858 | 16.65 | 28.783 | 0.0 | 0.0 | 0.0 |
| ruins_boss | 60 | 22.975 | 10.9 | 39.7 | 32.0 | 0.0 | 121.0 |
| ruins_c01 | 36 | 0.5 | 0.5 | 0.5 | 0.0 | 0.0 | 0.0 |
| ruins_c02 | 36 | 2.583 | 2.567 | 2.583 | 0.0 | 0.0 | 0.0 |
| ruins_c03 | 36 | 2.409 | 2.383 | 2.5 | 0.0 | 0.0 | 0.0 |
| ruins_c04 | 48 | 4.534 | 3.033 | 7.95 | 11.0 | 0.0 | 22.0 |
| ruins_c05 | 39 | 5.6 | 4.867 | 10.917 | 9.0 | 0.0 | 27.0 |
| ruins_c06 | 42 | 7.559 | 6.217 | 12.4 | 0.0 | 0.0 | 33.0 |
| ruins_c07 | 45 | 5.917 | 5.367 | 15.133 | 11.0 | 0.0 | 22.0 |
| ruins_c08 | 45 | 8.3 | 5.45 | 10.617 | 9.0 | 0.0 | 29.0 |
BENCH_MD_END

## After (AD-156)

Result: **no data change was kept. All four targets are NOT MET** (room length passes, as before). The final data equals the Before data, so the final bench is the Before run again (the bench is deterministic). Every tuning lever that moves the bench is pinned by golden-trace suites, and the rules for this step forbid editing tests or code.

PROPOSED values, to be re-tuned after human playtests. Nothing below is approved balance.

### Data changes (all reverted)

Three iterations. Iterations 1-2 used `-- --seeds=N` subsets of the bench; the full 20-seed set takes about 35 min wall.

| iter | file | key | old -> new | why | outcome |
|---|---|---|---|---|---|
| 1 | magic/data/magic_balance_v1.json | combat.regen_mana_per_tick | 0.3 -> 0.9 | mana-starved was ~57% | bench (4 seeds): starved median ~31-34%, still above 20%; all builds won 4/4 in ~2.4 min. Reverted: with this change alone, validate_godot.py fails 23 checks (TASK-035 golden traces, AD-142 fight-length checks `lasts 90-180 s`). |
| 2 | magic/data/magic_balance_v1.json | combat.regen_mana_per_tick | 0.9 -> 1.2 | still starved | starved unchanged (~31%). Reverted. |
| 2 | combat/combat_tuning_v1.json | enemies.*.hp (all 13) | x4 | stretch rooms toward 30-40 min | Reverted. |
| 2 | combat/combat_tuning_v1.json | enemies.*.damage (all 13) | x1.5, rounded | make the weak build die earlier | Reverted. |
| 2 | world/data/run_v2.json | bosses.ruins_warden.hp and boss.hp | 590 -> 1770 | longer first boss | Reverted. |
| 2 | world/data/run_v2.json | bosses.cistern_boss.hp | 950 -> 2850 | longer final boss | Reverted. |
| 3 | (none) | - | - | Used to isolate the pinned suites: the regen-only change above already breaks 23 checks. | - |

Iteration 2 bench (3 seeds, all three builds): 0/3 wins for every build, runs ended at 2.1-4.7 min total (deaths in stage 2 rooms or the stage 2 boss), max room 39-79 s, starved median 30.6-32.4%. Full `validate_godot.py` with the iteration 2 data failed 63 checks (TASK-035 mixed/cluster/single, AD-136 golden, AD-142, TASK-028), so it was reverted.

### Final bench (identical to Before: data is back at the pre-AD-156 values)

BENCH_MD_BEGIN
**weak**

| seed | outcome | died in | total min | max room s | starved % | rooms cleared |
|---|---|---|---|---|---|---|
| 20261022 | dead | stage2_boss | 3.764 | 91.567 | 56.327 | 12 |
| 20261023 | dead | stage2_boss | 2.626 | 35.633 | 56.085 | 11 |
| 20261024 | dead | stage2_boss | 2.052 | 25.333 | 59.841 | 12 |
| 20261025 | dead | stage2_boss | 3.143 | 52.883 | 58.226 | 13 |
| 20261026 | dead | stage2_boss | 3.588 | 85.25 | 59.371 | 12 |
| 20261027 | dead | stage2_rooms | 1.901 | 35.767 | 64.71 | 8 |
| 20261028 | dead | stage2_boss | 3.139 | 44.833 | 58.529 | 12 |
| 20261029 | dead | stage2_boss | 2.653 | 25.5 | 61.595 | 13 |
| 20261030 | dead | stage2_boss | 2.536 | 40.3 | 59.364 | 11 |
| 20261031 | won | - | 3.491 | 94.0 | 56.877 | 13 |
| 20261032 | dead | stage2_boss | 3.483 | 70.767 | 55.054 | 13 |
| 20261033 | won | - | 3.369 | 86.15 | 55.927 | 14 |
| 20261034 | dead | stage2_boss | 2.952 | 78.017 | 54.497 | 11 |
| 20261035 | dead | stage2_boss | 3.719 | 93.483 | 55.41 | 12 |
| 20261036 | dead | stage2_boss | 2.262 | 25.717 | 65.497 | 12 |
| 20261037 | dead | stage2_boss | 2.237 | 35.617 | 55.27 | 11 |
| 20261038 | dead | stage2_boss | 4.035 | 96.667 | 61.999 | 12 |
| 20261039 | dead | stage2_boss | 2.849 | 35.633 | 57.71 | 12 |
| 20261040 | dead | stage2_boss | 3.082 | 72.683 | 54.401 | 11 |
| 20261041 | dead | stage2_boss | 2.848 | 65.15 | 52.141 | 12 |

**typical**

| seed | outcome | died in | total min | max room s | starved % | rooms cleared |
|---|---|---|---|---|---|---|
| 20261022 | dead | stage2_boss | 3.899 | 56.2 | 56.896 | 13 |
| 20261023 | dead | stage2_rooms | 3.174 | 52.567 | 65.238 | 11 |
| 20261024 | dead | stage2_rooms | 3.096 | 80.5 | 54.206 | 12 |
| 20261025 | dead | stage2_boss | 4.842 | 103.6 | 51.121 | 14 |
| 20261026 | dead | stage2_rooms | 3.801 | 96.033 | 55.812 | 12 |
| 20261027 | dead | stage2_boss | 3.35 | 67.75 | 58.468 | 12 |
| 20261028 | dead | stage2_rooms | 4.281 | 105.683 | 55.246 | 12 |
| 20261029 | dead | stage2_rooms | 3.302 | 65.2 | 58.721 | 13 |
| 20261030 | dead | stage2_boss | 3.491 | 38.667 | 55.296 | 12 |
| 20261031 | dead | stage2_rooms | 3.177 | 61.05 | 60.613 | 12 |
| 20261032 | dead | stage2_rooms | 4.158 | 116.117 | 56.8 | 13 |
| 20261033 | dead | stage2_rooms | 3.079 | 50.95 | 56.386 | 13 |
| 20261034 | dead | stage2_rooms | 3.054 | 58.433 | 59.77 | 11 |
| 20261035 | dead | stage2_rooms | 4.168 | 106.7 | 54.947 | 12 |
| 20261036 | dead | stage2_boss | 3.55 | 73.667 | 55.651 | 13 |
| 20261037 | dead | stage2_boss | 3.296 | 53.167 | 57.629 | 12 |
| 20261038 | dead | stage2_rooms | 3.165 | 50.717 | 63.073 | 12 |
| 20261039 | dead | stage2_rooms | 3.682 | 53.383 | 59.326 | 12 |
| 20261040 | dead | stage2_rooms | 3.492 | 81.117 | 58.512 | 11 |
| 20261041 | dead | stage2_boss | 3.303 | 60.417 | 56.911 | 13 |

**skilled**

| seed | outcome | died in | total min | max room s | starved % | rooms cleared |
|---|---|---|---|---|---|---|
| 20261022 | dead | stage2_rooms | 3.589 | 73.2 | 55.618 | 12 |
| 20261023 | dead | stage2_rooms | 2.934 | 55.783 | 54.435 | 11 |
| 20261024 | dead | stage2_rooms | 2.803 | 57.533 | 56.115 | 12 |
| 20261025 | dead | stage2_boss | 3.89 | 54.667 | 56.948 | 14 |
| 20261026 | dead | stage2_rooms | 3.625 | 102.717 | 54.642 | 12 |
| 20261027 | dead | stage2_boss | 2.881 | 39.7 | 62.074 | 12 |
| 20261028 | dead | stage2_boss | 3.442 | 72.433 | 53.902 | 13 |
| 20261029 | dead | stage2_boss | 3.44 | 45.95 | 61.347 | 14 |
| 20261030 | dead | stage2_boss | 3.328 | 51.433 | 58.464 | 12 |
| 20261031 | dead | stage2_boss | 3.387 | 52.3 | 56.635 | 13 |
| 20261032 | dead | stage2_rooms | 3.053 | 51.4 | 59.871 | 13 |
| 20261033 | dead | stage2_rooms | 2.831 | 50.2 | 56.239 | 13 |
| 20261034 | dead | stage2_rooms | 2.859 | 63.4 | 54.721 | 11 |
| 20261035 | dead | stage2_rooms | 3.197 | 39.517 | 62.359 | 12 |
| 20261036 | dead | stage2_boss | 3.133 | 34.133 | 60.594 | 13 |
| 20261037 | dead | stage2_rooms | 3.362 | 109.933 | 50.102 | 11 |
| 20261038 | dead | stage2_rooms | 3.428 | 65.783 | 58.011 | 12 |
| 20261039 | dead | stage2_rooms | 3.759 | 94.7 | 57.086 | 12 |
| 20261040 | dead | stage2_rooms | 3.291 | 66.367 | 53.4 | 11 |
| 20261041 | dead | stage2_boss | 3.123 | 59.267 | 58.855 | 13 |

| build | wins | win total min (median/min/max) | dies stage 1 or first boss | max room s | starved % median | starved % max |
|---|---|---|---|---|---|---|
| weak | 2/20 | 3.43 / 3.369 / 3.491 | 0/20 | 96.667 | 57.294 | 65.497 |
| typical | 0/20 | - | 0/20 | 116.117 | 56.904 | 65.238 |
| skilled | 0/20 | - | 0/20 | 109.933 | 56.792 | 62.359 |

| target | weak | typical | skilled |
|---|---|---|---|
| winning run 30-40 min sim | n/a | NO (median 0.0 min, 0 wins) | NO (median 0.0 min, 0 wins) |
| weak build dies in stage 1 or at the first boss on most seeds | NO (0/20 dead early, need 11) | n/a | n/a |
| no room > 4 min | PASS (max 96.667 s) | PASS (max 116.117 s) | PASS (max 109.933 s) |
| mana-starved < 20% | NO (median 57.294%) | NO (median 56.904%) | NO (median 56.792%) |

| room | n | median s | min s | max s | median HP lost | min HP lost | max HP lost |
|---|---|---|---|---|---|---|---|
| cistern_boss | 34 | 41.109 | 4.2 | 96.667 | 75.5 | 8.0 | 112.0 |
| cistern_challenge_v1 | 40 | 57.983 | 25.683 | 116.117 | 70.0 | 0.0 | 153.0 |
| cistern_p01 | 27 | 5.35 | 4.567 | 6.683 | 0.0 | 0.0 | 11.0 |
| cistern_p02 | 27 | 10.7 | 5.417 | 37.883 | 9.0 | 0.0 | 29.0 |
| cistern_p03 | 30 | 8.258 | 6.967 | 11.633 | 9.0 | 0.0 | 27.0 |
| cistern_p04 | 27 | 9.217 | 7.833 | 14.383 | 9.0 | 0.0 | 18.0 |
| cistern_p05 | 44 | 6.034 | 3.717 | 11.083 | 0.0 | 0.0 | 0.0 |
| cistern_p06 | 27 | 6.833 | 6.233 | 7.783 | 0.0 | 0.0 | 0.0 |
| cistern_p07 | 33 | 8.183 | 6.333 | 11.083 | 11.0 | 0.0 | 11.0 |
| cistern_p08 | 27 | 11.233 | 10.267 | 13.617 | 0.0 | 0.0 | 10.0 |
| cistern_p09 | 41 | 6.467 | 5.083 | 7.417 | 0.0 | 0.0 | 7.0 |
| cistern_p10 | 42 | 20.858 | 16.65 | 28.783 | 0.0 | 0.0 | 0.0 |
| ruins_boss | 60 | 22.975 | 10.9 | 39.7 | 32.0 | 0.0 | 121.0 |
| ruins_c01 | 36 | 0.5 | 0.5 | 0.5 | 0.0 | 0.0 | 0.0 |
| ruins_c02 | 36 | 2.583 | 2.567 | 2.583 | 0.0 | 0.0 | 0.0 |
| ruins_c03 | 36 | 2.409 | 2.383 | 2.5 | 0.0 | 0.0 | 0.0 |
| ruins_c04 | 48 | 4.534 | 3.033 | 7.95 | 11.0 | 0.0 | 22.0 |
| ruins_c05 | 39 | 5.6 | 4.867 | 10.917 | 9.0 | 0.0 | 27.0 |
| ruins_c06 | 42 | 7.559 | 6.217 | 12.4 | 0.0 | 0.0 | 33.0 |
| ruins_c07 | 45 | 5.917 | 5.367 | 15.133 | 11.0 | 0.0 | 22.0 |
| ruins_c08 | 45 | 8.3 | 5.45 | 10.617 | 9.0 | 0.0 | 29.0 |
BENCH_MD_END

### Before / after summary

| target | before | after | status |
|---|---|---|---|
| winning run 30-40 min sim (typical, skilled) | 0/20 wins for both; weak wins 2/20 at ~3.4 min | unchanged | NOT MET |
| weak build dies in stage 1 or first boss on >= 11/20 seeds | 0/20 | unchanged | NOT MET |
| no room > 4 min | PASS (max 116.1 s) | unchanged | PASS |
| mana-starved < 20% (median per build) | 56.8-57.3% | unchanged (best probe: ~31% with regen 0.9) | NOT MET |

### Why NOT MET, and the knobs needed

- Runs last 2-5 min, not 30-40. Rooms clear in 0.5-10 s and the scripted player dies in stage 2 within minutes, so scaling enemy HP alone does not stretch the run: the bot dies instead (iteration 2). A 10x longer run needs roughly 6-10x enemy/boss HP together with lower enemy damage or higher player survivability. `player.max_hp` is also hard-coded as 150 in `world/run_state.gd`, and `player_max_mana` as 120 in `world/run_state.gd`, so those two cannot be tuned from data alone.
- The weak build reaches the stage 2 boss (likely because the starter spells out-damage stage 1 enemies; not verified). It would need higher stage 1 and ruins_boss damage plus lower starter spell damage. Enemy/boss damage keys are pinned by the TASK-035, AD-136 and AD-142 golden traces.
- Mana-starved needs regen above 0.3/tick or cheaper starter spells. `regen_mana_per_tick` is read by the TASK-035 golden traces and AD-142's fight-length checks.
- To unblock: regenerate those golden traces (tests/ad_*_golden_generator.gd and the TASK-035 expectations) in a follow-up that is allowed to edit tests, then apply: regen 0.9 or higher, enemy HP x4-x10, boss HP x3, with matching damage changes, and re-run the bench.

## Boss pacing (AD-167)

The Drowned Archivist fight-length window (90-180 s, builds 0 and 2, live balance data) moved out of `tests/test_ad_final_boss.gd` so unit tests can run on the frozen balance fixture. Run:

```
/usr/local/bin/godot --headless --path . --script res://tests/bench/boss_pacing_bench.gd
```

Prints `BOSS_PACING build=<n> tick=<t> seconds=<s> target=90-180 PASS|FAIL` per build and exits 1 if any build is out of range.
