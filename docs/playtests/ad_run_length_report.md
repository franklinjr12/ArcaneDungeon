# AD-085 Run length and difficulty report

- Date: 2026-11-03
- Commit (tool version): c87ff6c
- Godot: 4.7.1.stable.official.a13da4feb
- Reproduce: `godot --headless --path . --script res://tools/run_length_report.gd -- --check-determinism --out /tmp/ad_run_length_data.md`
- Measured wall time: 8 m 53 s (real) for 20 seeds, run with `--check-determinism`, exit code 0 (limit: 10 min). Each run took about 12.5 s of wall time.
- Determinism: `--check-determinism` passed (exit code 0).
- Status: measurement only. No tuning was done. Not a human playtest (TASK-054 is deferred).

### Seeds

20261022, 20261023, 20261024, 20261025, 20261026, 20261027, 20261028, 20261029, 20261030, 20261031, 20261032, 20261033, 20261034, 20261035, 20261036, 20261037, 20261038, 20261039, 20261040, 20261041

### Per-run results

| seed | outcome | rooms cleared | per-room seconds | per-room damage | deaths | boss s | reward picks | total combat s |
|---|---|---|---|---|---|---|---|---|
| 20261022 | won/completed | 5 | s1_r1=0.417, s1_r2=7.133, s1_r3=6.383, s1_boss=61.55, s2_r1=24.567 | s1_r1=0.0, s1_r2=0.0, s1_r3=0.0, s1_boss=0.0, s2_r1=0.0 | 0 | 61.55 | unlock:mod.homing, unlock:trigger.on_hit, unlock:form.orb | 100.05 |
| 20261023 | won/completed | 5 | s1_r1=0.417, s1_r2=7.133, s1_r3=6.383, s1_boss=61.55, s2_r1=24.567 | s1_r1=0.0, s1_r2=0.0, s1_r3=0.0, s1_boss=0.0, s2_r1=0.0 | 0 | 61.55 | unlock:trigger.on_hit, unlock:form.orb, unlock:mod.homing | 100.05 |
| 20261024 | won/completed | 5 | s1_r1=0.417, s1_r2=7.133, s1_r3=6.383, s1_boss=61.55, s2_r1=24.567 | s1_r1=0.0, s1_r2=0.0, s1_r3=0.0, s1_boss=0.0, s2_r1=0.0 | 0 | 61.55 | unlock:form.orb, unlock:mod.pierce, unlock:trigger.on_hit | 100.05 |
| 20261025 | won/completed | 5 | s1_r1=0.417, s1_r2=7.133, s1_r3=6.383, s1_boss=61.55, s2_r1=24.567 | s1_r1=0.0, s1_r2=0.0, s1_r3=0.0, s1_boss=0.0, s2_r1=0.0 | 0 | 61.55 | unlock:form.orb, unlock:mod.homing, unlock:mod.pierce | 100.05 |
| 20261026 | won/completed | 5 | s1_r1=0.417, s1_r2=7.133, s1_r3=6.383, s1_boss=61.55, s2_r1=24.567 | s1_r1=0.0, s1_r2=0.0, s1_r3=0.0, s1_boss=0.0, s2_r1=0.0 | 0 | 61.55 | unlock:trigger.on_hit, unlock:mod.homing, unlock:form.orb | 100.05 |
| 20261027 | won/completed | 5 | s1_r1=0.417, s1_r2=7.133, s1_r3=6.383, s1_boss=61.55, s2_r1=24.567 | s1_r1=0.0, s1_r2=0.0, s1_r3=0.0, s1_boss=0.0, s2_r1=0.0 | 0 | 61.55 | unlock:form.orb, unlock:trigger.on_hit, unlock:mod.homing | 100.05 |
| 20261028 | won/completed | 5 | s1_r1=0.417, s1_r2=7.133, s1_r3=6.383, s1_boss=61.55, s2_r1=24.567 | s1_r1=0.0, s1_r2=0.0, s1_r3=0.0, s1_boss=0.0, s2_r1=0.0 | 0 | 61.55 | unlock:mod.pierce, unlock:form.orb, unlock:mod.homing | 100.05 |
| 20261029 | won/completed | 5 | s1_r1=0.417, s1_r2=7.133, s1_r3=6.383, s1_boss=61.55, s2_r1=24.567 | s1_r1=0.0, s1_r2=0.0, s1_r3=0.0, s1_boss=0.0, s2_r1=0.0 | 0 | 61.55 | unlock:trigger.on_hit, unlock:form.orb, unlock:mod.pierce | 100.05 |
| 20261030 | won/completed | 5 | s1_r1=0.417, s1_r2=7.133, s1_r3=6.383, s1_boss=61.55, s2_r1=24.567 | s1_r1=0.0, s1_r2=0.0, s1_r3=0.0, s1_boss=0.0, s2_r1=0.0 | 0 | 61.55 | unlock:mod.homing, unlock:trigger.on_hit, unlock:form.orb | 100.05 |
| 20261031 | won/completed | 5 | s1_r1=0.417, s1_r2=7.133, s1_r3=6.383, s1_boss=61.55, s2_r1=24.567 | s1_r1=0.0, s1_r2=0.0, s1_r3=0.0, s1_boss=0.0, s2_r1=0.0 | 0 | 61.55 | unlock:trigger.on_hit, unlock:mod.homing, unlock:form.orb | 100.05 |
| 20261032 | won/completed | 5 | s1_r1=0.417, s1_r2=7.133, s1_r3=6.383, s1_boss=61.55, s2_r1=24.567 | s1_r1=0.0, s1_r2=0.0, s1_r3=0.0, s1_boss=0.0, s2_r1=0.0 | 0 | 61.55 | unlock:mod.pierce, unlock:mod.homing, unlock:trigger.on_hit | 100.05 |
| 20261033 | won/completed | 5 | s1_r1=0.417, s1_r2=7.133, s1_r3=6.383, s1_boss=61.55, s2_r1=24.567 | s1_r1=0.0, s1_r2=0.0, s1_r3=0.0, s1_boss=0.0, s2_r1=0.0 | 0 | 61.55 | unlock:form.orb, unlock:mod.homing, unlock:trigger.on_hit | 100.05 |
| 20261034 | won/completed | 5 | s1_r1=0.417, s1_r2=7.133, s1_r3=6.383, s1_boss=61.55, s2_r1=24.567 | s1_r1=0.0, s1_r2=0.0, s1_r3=0.0, s1_boss=0.0, s2_r1=0.0 | 0 | 61.55 | unlock:trigger.on_hit, unlock:mod.pierce, unlock:form.orb | 100.05 |
| 20261035 | won/completed | 5 | s1_r1=0.417, s1_r2=7.133, s1_r3=6.383, s1_boss=61.55, s2_r1=24.567 | s1_r1=0.0, s1_r2=0.0, s1_r3=0.0, s1_boss=0.0, s2_r1=0.0 | 0 | 61.55 | unlock:form.orb, unlock:mod.pierce, unlock:mod.homing | 100.05 |
| 20261036 | won/completed | 5 | s1_r1=0.417, s1_r2=7.133, s1_r3=6.383, s1_boss=61.55, s2_r1=24.567 | s1_r1=0.0, s1_r2=0.0, s1_r3=0.0, s1_boss=0.0, s2_r1=0.0 | 0 | 61.55 | unlock:mod.pierce, unlock:trigger.on_hit, unlock:mod.homing | 100.05 |
| 20261037 | won/completed | 5 | s1_r1=0.417, s1_r2=7.133, s1_r3=6.383, s1_boss=61.55, s2_r1=24.567 | s1_r1=0.0, s1_r2=0.0, s1_r3=0.0, s1_boss=0.0, s2_r1=0.0 | 0 | 61.55 | unlock:mod.pierce, unlock:trigger.on_hit, unlock:form.orb | 100.05 |
| 20261038 | won/completed | 5 | s1_r1=0.417, s1_r2=7.133, s1_r3=6.383, s1_boss=61.55, s2_r1=24.567 | s1_r1=0.0, s1_r2=0.0, s1_r3=0.0, s1_boss=0.0, s2_r1=0.0 | 0 | 61.55 | unlock:mod.homing, unlock:form.orb, unlock:mod.pierce | 100.05 |
| 20261039 | won/completed | 5 | s1_r1=0.417, s1_r2=7.133, s1_r3=6.383, s1_boss=61.55, s2_r1=24.567 | s1_r1=0.0, s1_r2=0.0, s1_r3=0.0, s1_boss=0.0, s2_r1=0.0 | 0 | 61.55 | unlock:mod.pierce, unlock:trigger.on_hit, unlock:mod.homing | 100.05 |
| 20261040 | won/completed | 5 | s1_r1=0.417, s1_r2=7.133, s1_r3=6.383, s1_boss=61.55, s2_r1=24.567 | s1_r1=0.0, s1_r2=0.0, s1_r3=0.0, s1_boss=0.0, s2_r1=0.0 | 0 | 61.55 | unlock:form.orb, unlock:mod.pierce, unlock:mod.homing | 100.05 |
| 20261041 | won/completed | 5 | s1_r1=0.417, s1_r2=7.133, s1_r3=6.383, s1_boss=61.55, s2_r1=24.567 | s1_r1=0.0, s1_r2=0.0, s1_r3=0.0, s1_boss=0.0, s2_r1=0.0 | 0 | 61.55 | unlock:mod.homing, unlock:form.orb, unlock:trigger.on_hit | 100.05 |

### Per-room aggregate

| room | sec min | sec median | sec max | dmg min | dmg median | dmg max |
|---|---|---|---|---|---|---|
| s1_boss | 61.55 | 61.55 | 61.55 | 0.0 | 0.0 | 0.0 |
| s1_r1 | 0.417 | 0.417 | 0.417 | 0.0 | 0.0 | 0.0 |
| s1_r2 | 7.133 | 7.133 | 7.133 | 0.0 | 0.0 | 0.0 |
| s1_r3 | 6.383 | 6.383 | 6.383 | 0.0 | 0.0 | 0.0 |
| s2_r1 | 24.567 | 24.567 | 24.567 | 0.0 | 0.0 | 0.0 |

### Overall aggregate

| metric | min | median | max |
|---|---|---|---|
| combat_seconds | 100.05 | 100.05 | 100.05 |
| rooms_cleared | 5.0 | 5.0 | 5.0 |
| damage | 0.0 | 0.0 | 0.0 |
| boss_seconds | 61.55 | 61.55 | 61.55 |

Deaths (sum): 0 over 20 runs.

Reward picks: `{"unlock:form.orb":17,"unlock:mod.homing":16,"unlock:mod.pierce":12,"unlock:trigger.on_hit":15}`

## Method & assumptions

- Bot: the scripted baseline policy in `tests/m3_run_driver.gd`. It targets the nearest enemy, kites at 120–220 px, dashes on telegraphs or near shots, always picks reward option 0, buys merchant item 0 and does not edit spells.
- Times are simulation combat time at the fixed tick. They exclude menus, reward, merchant, workshop and editor time. They also exclude walking to exits unless the tool measured it.
- **ASSUMPTION (PROPOSED, not a design rule):** human run time ≈ bot sim time × 2–3.

| | bot sim (s) | human est. ×2 | human est. ×3 |
|---|---|---|---|
| min | 100.05 | 200 s (3.3 min) | 300 s (5.0 min) |
| median | 100.05 | 200 s (3.3 min) | 300 s (5.0 min) |
| max | 100.05 | 200 s (3.3 min) | 300 s (5.0 min) |

GDD v1.0 §11 has "Run length: PROPOSAL 20–35 min target for the slice". GDD §10 has "Difficulty curve: unknown. To be tuned from M2/M4 data".

## Design read

- **Far short of the target.** Under the ×2–3 assumption the slice is about 3.3–5 min, against the proposed 20–35 min. Even a ×10 multiplier gives only about 17 min. The slice is 3 combat rooms, the boss, the workshop and 1 stage-2 room, so this is expected. The slice is not built to fill 20–35 min.
- **Time sits in the boss and the stage-2 room.** The boss takes 61.55 s (62% of the 100.05 s) and `s2_r1` takes 24.6 s. `s1_r1` is 0.4 s (25 ticks), `s1_r2` 7.1 s and `s1_r3` 6.4 s. The three stage-1 combat rooms total about 14 s.
- **No damage and no deaths.** Damage was 0.0 in every room on every seed, with 0 deaths over 20 runs, and HP stayed at 150 throughout. Against this baseline bot the slice is too easy. The boss is a time sink, not a difficulty spike.
- **Caveat on bot strength.** The bot kites and dashes perfectly and may be stronger than a typical human. Zero damage is a floor on difficulty, not a human prediction.
- **Seeds add almost no variance.** Times, damage and rooms cleared are identical across all 20 seeds (min = median = max). The seeds only change the reward offer order. Because the bot always picks option 0, picks vary by seed: form.orb 17, mod.homing 16, trigger.on_hit 15, mod.pierce 12. The bot's clear time did not depend on the pick. The run to run variety the roguelike needs is not exercised by this bot.
- **Combat rooms 1–3 may be too trivial.** `s1_r1` clears in under half a second. [OPEN] Owner decision: whether the opening rooms should be a gentle ramp or need more enemies.
- **[OPEN] Owner decisions for the playtest (TASK-054):** whether 20–35 min is still the target for this slice or applies only to a full run, whether the ×2–3 factor is right, and what damage or death rate counts as acceptable. This report does not propose balance numbers.
- **Report limits.** It covers one bot policy, with no spell editing or merchant adaptation, and the data is sim time only. A human playtest is needed before any difficulty or length conclusion.
