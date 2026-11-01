# AD slice benchmark (AD-043 harness, AD-044 tuning)

Command:

```
/usr/local/bin/godot --headless --path . --script res://tests/bench/slice_bench.gd
```

Seeds: [20261022, 20261023, 20261024, 20261025, 20261026, 20261027, 20261028, 20261029, 20261030, 20261031]

## Targets (PROPOSED, AD-044)

Proposals from game design, not approved; to be re-tuned after the human playtest.

- Each combat room costs 15-45% of max HP (player.max_hp = 150 in combat/combat_tuning_v1.json; the bench buys no max-HP upgrades).
- No seed dies before the warden.
- Warden fight 60-150 s sim time.
- Mana-starved time < 20% of combat time.
- Slot 1 basic bolt < 60% of casts.
- Total slice sim time reported against the 20-35 min human target.

Targets were split into MUST vs REPORT by game design on 2026-10-31 (v2), with at most 3 tuning iterations.

## Before (pre-AD-044)

BENCH_MD_BEGIN
| seed | outcome | total s | HP lost | starved ticks | warden s | casts (slot0/1/2/3) | rewards |
|---|---|---|---|---|---|---|---|
| 20261022 | won | 71.733 | 11.0 | 2280 | 35.683 | 282/49/21/0 | mod.homing, trigger.on_hit, form.orb |
| 20261023 | won | 71.733 | 11.0 | 2280 | 35.683 | 282/49/21/0 | trigger.on_hit, form.orb, mod.homing |
| 20261024 | won | 75.783 | 11.0 | 2487 | 35.683 | 301/53/20/0 | form.orb, mod.pierce, trigger.on_hit |
| 20261025 | won | 71.733 | 11.0 | 2280 | 35.683 | 282/49/21/0 | form.orb, mod.homing, mod.pierce |
| 20261026 | won | 71.733 | 11.0 | 2280 | 35.683 | 282/49/21/0 | trigger.on_hit, mod.homing, form.orb |
| 20261027 | won | 71.733 | 11.0 | 2280 | 35.683 | 282/49/21/0 | form.orb, trigger.on_hit, mod.homing |
| 20261028 | won | 75.783 | 11.0 | 2487 | 35.683 | 301/53/20/0 | mod.pierce, form.orb, mod.homing |
| 20261029 | won | 75.783 | 11.0 | 2487 | 35.683 | 301/53/20/0 | trigger.on_hit, form.orb, mod.pierce |
| 20261030 | won | 71.733 | 11.0 | 2280 | 35.683 | 282/49/21/0 | mod.homing, trigger.on_hit, form.orb |
| 20261031 | won | 71.733 | 11.0 | 2280 | 35.683 | 282/49/21/0 | trigger.on_hit, mod.homing, form.orb |

| metric | median | min | max |
|---|---|---|---|
| total_seconds | 71.733 | 71.733 | 75.783 |
| total_hp_lost | 11.0 | 11.0 | 11.0 |
| total_mana_starved_ticks | 2280.0 | 2280.0 | 2487.0 |
| warden_seconds | 35.683 | 35.683 | 35.683 |
| deaths | 0.0 | 0.0 | 0.0 |
| casts slot 0 | 282.0 | 282.0 | 301.0 |
| casts slot 1 | 49.0 | 49.0 | 53.0 |
| casts slot 2 | 21.0 | 20.0 | 21.0 |
| casts slot 3 | 0.0 | 0.0 | 0.0 |

| room | n | median s | min s | max s | median HP lost | min HP lost | max HP lost |
|---|---|---|---|---|---|---|---|
| s1_r1 | 10 | 0.433 | 0.433 | 0.433 | 0.0 | 0.0 | 0.0 |
| s1_r2 | 10 | 8.417 | 8.417 | 8.417 | 0.0 | 0.0 | 0.0 |
| s1_r3 | 10 | 6.933 | 6.933 | 6.933 | 11.0 | 11.0 | 11.0 |
| s1_boss | 10 | 35.683 | 35.683 | 35.683 | 0.0 | 0.0 | 0.0 |
| s2_r1 | 10 | 20.267 | 20.267 | 24.317 | 0.0 | 0.0 | 0.0 |
BENCH_MD_END

Derived metrics (combat rooms = s1_r1, s1_r2, s1_r3, s2_r1; the warden room s1_boss is excluded from HP cost; mana-starved % = starved ticks / ticks over all rooms per seed):

| metric | median / min / max | PROPOSED target | pass |
|---|---|---|---|
| HP cost % of max HP, s1_r1 | 0.0 / 0.0 / 0.0 | 15-45 | NO |
| HP cost % of max HP, s1_r2 | 0.0 / 0.0 / 0.0 | 15-45 | NO |
| HP cost % of max HP, s1_r3 | 7.3 / 7.3 / 7.3 | 15-45 | NO |
| HP cost % of max HP, s2_r1 | 0.0 / 0.0 / 0.0 | 15-45 | NO |
| Deaths before warden | 0.0 / 0.0 / 0.0 | 0 | yes |
| Warden seconds | 35.7 / 35.7 / 35.7 | 60-150 | NO |
| Mana-starved % of combat ticks | 53.0 / 53.0 / 54.7 | <20 | NO |
| Basic bolt (slot 0 = GDD slot 1) % of casts | 80.1 / 80.1 / 80.5 | <60 | NO |
| Total slice sim time (min) | 1.20 / 1.20 / 1.26 | 20-35 human target (informational) | n/a |

## After (AD-044)

**MUST NOT MET**: room HP cost is 0-11 of 150 max HP (0-7%, target 15-45%) in every combat room. The extra waves from the earlier iterations were removed because they broke the TASK-037, AD-031, AD-039, TASK-041, TASK-047 and TASK-048 suites (those pin wave counts and clear s1_r3 with the starter loadout). Only the warden tuning survives. The planner decides the next step (3-iteration limit reached). The warden fight (66.7 s) and zero deaths pass.

BENCH_MD_BEGIN
| seed | outcome | total s | HP lost | starved ticks | warden s | casts (slot0/1/2/3) | rewards |
|---|---|---|---|---|---|---|---|
| 20261022 | won | 102.8 | 11.0 | 2855 | 66.733 | 359/75/36/0 | mod.homing, trigger.on_hit, form.orb |
| 20261023 | won | 102.8 | 11.0 | 2855 | 66.733 | 359/75/36/0 | trigger.on_hit, form.orb, mod.homing |
| 20261024 | won | 105.25 | 11.0 | 3000 | 66.733 | 370/77/36/0 | form.orb, mod.pierce, trigger.on_hit |
| 20261025 | won | 102.8 | 11.0 | 2855 | 66.733 | 359/75/36/0 | form.orb, mod.homing, mod.pierce |
| 20261026 | won | 102.8 | 11.0 | 2855 | 66.733 | 359/75/36/0 | trigger.on_hit, mod.homing, form.orb |
| 20261027 | won | 102.8 | 11.0 | 2855 | 66.733 | 359/75/36/0 | form.orb, trigger.on_hit, mod.homing |
| 20261028 | won | 105.25 | 11.0 | 3000 | 66.733 | 370/77/36/0 | mod.pierce, form.orb, mod.homing |
| 20261029 | won | 105.25 | 11.0 | 3000 | 66.733 | 370/77/36/0 | trigger.on_hit, form.orb, mod.pierce |
| 20261030 | won | 102.8 | 11.0 | 2855 | 66.733 | 359/75/36/0 | mod.homing, trigger.on_hit, form.orb |
| 20261031 | won | 102.8 | 11.0 | 2855 | 66.733 | 359/75/36/0 | trigger.on_hit, mod.homing, form.orb |

| metric | median | min | max |
|---|---|---|---|
| total_seconds | 102.8 | 102.8 | 105.25 |
| total_hp_lost | 11.0 | 11.0 | 11.0 |
| total_mana_starved_ticks | 2855.0 | 2855.0 | 3000.0 |
| warden_seconds | 66.733 | 66.733 | 66.733 |
| deaths | 0.0 | 0.0 | 0.0 |
| casts slot 0 | 359.0 | 359.0 | 370.0 |
| casts slot 1 | 75.0 | 75.0 | 77.0 |
| casts slot 2 | 36.0 | 36.0 | 36.0 |
| casts slot 3 | 0.0 | 0.0 | 0.0 |

| room | n | median s | min s | max s | median HP lost | min HP lost | max HP lost |
|---|---|---|---|---|---|---|---|
| s1_r1 | 10 | 0.433 | 0.433 | 0.433 | 0.0 | 0.0 | 0.0 |
| s1_r2 | 10 | 8.417 | 8.417 | 8.417 | 0.0 | 0.0 | 0.0 |
| s1_r3 | 10 | 6.933 | 6.933 | 6.933 | 11.0 | 11.0 | 11.0 |
| s1_boss | 10 | 66.733 | 66.733 | 66.733 | 0.0 | 0.0 | 0.0 |
| s2_r1 | 10 | 20.283 | 20.283 | 22.733 | 0.0 | 0.0 | 0.0 |
BENCH_MD_END

Derived metrics (same definitions as Before):

| metric | median / min / max | target | pass |
|---|---|---|---|
| HP cost % of max HP, s1_r1 | 0.0 / 0.0 / 0.0 | MUST 15-45 | NO |
| HP cost % of max HP, s1_r2 | 0.0 / 0.0 / 0.0 | MUST 15-45 | NO |
| HP cost % of max HP, s1_r3 | 7.3 / 7.3 / 7.3 | MUST 15-45 | NO |
| HP cost % of max HP, s2_r1 | 0.0 / 0.0 / 0.0 | MUST 15-45 | NO |
| Deaths before warden | 0 / 0 / 0 | MUST 0 | yes |
| Warden seconds | 66.7 / 66.7 / 66.7 | MUST 60-150 | yes |
| Total slice sim time (min) | 1.71 / 1.71 / 1.75 | REPORT ONLY | n/a |

Mana-starved and basic-bolt share are REPORT ONLY (not tuned): see the per-seed table (slot 0 is about 75% of casts).

## Changed keys

Only `world/data/vertical_slice_v1.json` differs from the baseline.

- world/data/vertical_slice_v1.json: boss.hp 430 -> 590
