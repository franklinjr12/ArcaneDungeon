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

## After (AD-196)

Player: `dash_cooldown_ticks` 40, `move_speed` 255. Reach = `attack_range` + `lunge_distance` for lunging melee enemies.

| enemy | telegraph ticks | recovery ticks | reach px | projectile speed | shots per attack |
|---|---|---|---|---|---|
| bone_thrall | 31 | 28 | 140 (76 + 64 lunge) | - | - |
| fallen_adept | 43 | 30 | 560 | 400 | 3 |
| grave_hound | 34 | 26 | 420 | 420 | 2 |
| ossuary_shieldbearer | 40 | 34 | 130 (80 + 50 lunge) | - | - |
| wailing_spirit | 45 | 30 | 420 | 330 | 1 |
| corpse_bloat | 62 | 36 | 130 (84 + 46 lunge) | - | - |
| cistern_slime | 40 | 30 | 130 (80 + 50 lunge) | - | - |
| cistern_slimelet | 30 | 24 | 120 (54 + 66 lunge) | - | - |
| drowned_acolyte | 48 | 30 | 440 | - | - |
| deep_eel | 30 | 60 | 130 (lunge, charge 520 px/s x 14 ticks) | - | - |
| rust_golem | 50 | 40 | 140 (90 + 50 lunge) | - | - |
| lantern_wisp | 40 | 30 | 300 | - | - |
| storm_crystal | 45 | 30 | 150 (pulse radius) | - | - |
| ruins_adept_elite (mini-boss) | 48 | 40 | 190 | 400 | 1 (fan 5, radial 8) |
| cistern_crystal_elite (mini-boss) | 50 | 40 | 150 | 350 | 1 (radial 8) |

What changed:

- `dash_cooldown_ticks` 53 -> 40.
- Perfect dodge: dashing through an enemy hit within its active frames refunds 15 mana, once per dash [PROPOSED FOR PROTOTYPE]. The player flashes for 10 ticks (`perfect_dodge_flash_ticks`); the flash is off under reduce-flash.
- Melee enemies lunge forward during the swing (8 ticks); telegraphs unchanged except `cistern_slimelet` 26 -> 30 so all melee windups are >= 30.
- Enemy projectile speeds are about +20-30%; adepts fire 3-shot bursts, hounds 2-shot bursts.
- `world/data/run_v2.json` boss `shot_speed` was left unchanged: outside this task's scope.
- Shot damage was not changed, so bursts raise incoming damage per attack.

## Bench INFO

Command: `godot --headless --path . --script res://tests/bench/run_bench.gd -- --seeds=0..1 --builds=typical --jobs=2 --results=/tmp/ad196_before`, then `--summarize` with the same seeds, build and results folder.

Seeds: 2 (result files 20261022 and 20261023), build: typical. This is a 2-seed, typical-only, report-only sample, not a pass/fail gate.

| hit rate median | dashes per fought room (mean) |
|---|---|
| 0.459 | 7.04 |

After: same command with `--results=/tmp/ad196_after`, same seeds, build and summarize step. Both runs ended `dead`.

| | hit rate median | dashes per fought room (mean) |
|---|---|---|
| before | 0.459 | 7.04 |
| after | 0.429 | 5.833 |

Dash use per fought room did not go up in this sample (7.04 -> 5.83). The sample is only 2 seeds with the typical build, so this is report-only and no tuning was done to move it.
