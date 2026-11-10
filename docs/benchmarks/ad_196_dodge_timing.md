# AD-196 dodge timing: before/after

Task AD-196 (Dodge 1). Numbers below come from `combat/combat_tuning_v1.json`. Reach = `attack_range` unless noted.

## Before (AD-196 baseline)

Player: `dash_cooldown_ticks` 53, `move_speed` 255.

| enemy | telegraph ticks | recovery ticks | reach px | projectile speed | shots per attack |
|---|---|---|---|---|---|
| bone_thrall | 31 | 28 | 76 | - | - |
| fallen_adept | 43 | 30 | 560 | 310 | 1 |
| grave_hound | 34 | 26 | 420 | 340 | 1 |
| ossuary_shieldbearer | 40 | 34 | 80 | - | - |
| wailing_spirit | 45 | 30 | 420 | 260 | 1 |
| corpse_bloat | 62 | 36 | 84 | - | - |
| cistern_slime | 40 | 30 | 80 | - | - |
| cistern_slimelet | 26 | 24 | 54 | - | - |
| drowned_acolyte | 48 | 30 | 440 | - | - |
| deep_eel | 30 | 60 | 130 (lunge, charge 520 px/s x 14 ticks) | - | - |
| rust_golem | 50 | 40 | 90 | - | - |
| lantern_wisp | 40 | 30 | 300 | - | - |
| storm_crystal | 45 | 30 | 150 (pulse radius) | - | - |
| ruins_adept_elite (mini-boss) | 48 | 40 | 190 | 310 | 1 (fan 5, radial 8) |
| cistern_crystal_elite (mini-boss) | 50 | 40 | 150 | 280 | 1 (radial 8) |

## Bench INFO

Command: `godot --headless --path . --script res://tests/bench/run_bench.gd -- --seeds=0..1 --builds=typical --jobs=2 --results=/tmp/ad196_before`, then `--summarize` with the same seeds, build and results folder.

Seeds: 2 (result files 20261022 and 20261023), build: typical. This is a 2-seed, typical-only, report-only sample, not a pass/fail gate.

| hit rate median | dashes per fought room (mean) |
|---|---|
| 0.459 | 7.04 |
