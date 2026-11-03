# AD-087 Perf budget probe (headless)

- Date: 2026-11-03
- Commit (tool version): be59edb
- Godot: 4.7.1.stable.official.a13da4feb
- Host CPU: Neoverse-N1 (`lscpu`). This is **NOT** the GDD §14 reference hardware (11th-gen i5 / GTX 1660). On-hardware 60 FPS sign-off (TASK-051) remains pending.
- Reproduce: `godot --headless --path . --script res://tests/m4_stress_probe.gd`
- Measured wall time (real, 3 runs): 22.662 s, 21.628 s, 21.155 s.
- Status: measurement only. No optimisation was done. Not a human playtest (TASK-054 is deferred).
- **Overall budget verdict: FAIL.** Sim p95 exceeded 4 ms in all 3 runs (39.5–42.8 ms).

## 1. Scenario

- Room: `s1_boss` (boss room), with Undead Warden present (`boss_present: true`) and 8 extra enemies spawned (`enemies_spawned: 8`; peak enemies alive: 9).
- Worst-case spell formula (`formula_id: ad087.worst_case`, schema_version 1):
  - Root: essence.fire, form.projectile, modifiers `[mod.split, mod.pierce, mod.homing]`, params `{}`
  - On Hit: trigger.on_hit, payload essence.lightning, form.burst, modifiers `[]`, params `{}`
- Complexity: **10 against a cap of 12** (`complexity_cap: 12`). This is the worst valid formula the probe builds with Split + Pierce + On Hit. It is not at the cap, so it is not a max-complexity build.
- Ticks: 600 per run. Seed: 20261022 (probe seed). Each run casts 75 times.

## 2. Sim tick table (AD_PERF_PROBE, per run)

| run | p50 ms | p95 ms | max ms | mean ms | peak active effects | peak queued events | budget_exceeded drops | casts |
|---|---|---|---|---|---|---|---|---|
| 1 | 18.311 | 42.758 | 115.224 | 21.524 | 57 | 0 | 0 | 75 |
| 2 | 17.434 | 41.307 | 87.716 | 20.633 | 57 | 0 | 0 | 75 |
| 3 | 16.909 | 39.462 | 100.187 | 20.020 | 57 | 0 | 0 | 75 |

Drops are from the probe's `budget_drop_records` field (0 in each run). The cap-attempt check in the same script reports 1 drop record, as in the baseline section.

## 3. Budget verdict

Budget: sim p95 < 4 ms per tick.

| run | p95 ms | verdict |
|---|---|---|
| 1 | 42.758 | **FAIL** (exceeds 4 ms) |
| 2 | 41.307 | **FAIL** (exceeds 4 ms) |
| 3 | 39.462 | **FAIL** (exceeds 4 ms) |

**Overall: FAIL.** All three runs exceed the budget, and the runs are flagged as exceeding. Their p95 is roughly 10× the budget. The probe itself printed `AD_PERF_PROBE: BUDGET EXCEEDED` for each run.

## 4. Render-side proxies

| metric | value |
|---|---|
| node count peak / mean | 82 / 82.0 |
| scene nodes peak | 68 |
| particle nodes peak / particles amount peak | 0 / 0 (the project uses no particle nodes) |
| effect visuals peak | 59 |
| frames sampled | 300 (1280x720 viewport) |

Draw-call and FPS monitors are **unavailable** in headless mode (dummy renderer). The arena draws on one canvas node via custom `_draw`, so effect visuals are counted from sim effects and enemy shots, not from scene nodes.

## 5. Baseline M4 40-target stress (M4_STRESS line)

Baseline for comparison. Scenario: 40 targets, 300 ticks, seed 5151, peak active effects 25.

| run | p95 ms | mean ms | max ms |
|---|---|---|---|
| 1 | 5.821 | 2.705 | 27.996 |
| 2 | 3.333 | 2.049 | 19.603 |
| 3 | 3.250 | 1.921 | 6.523 |

The baseline stress run has `cap_attempted` 10000, `cap_accepted` 32, and `budget_drop_records` 1. Its `reaction_records` are 43 and its `trigger_records` are 90. Its `hit_records` are 325.

## 6. Caveats

- Headless timing on a dev host (Neoverse-N1), not the GDD §14 reference hardware. The 60 FPS sign-off on the reference hardware is still pending (TASK-051).
- Wall-clock noise: tick times vary between runs (p95 39.5–42.8 ms). The three runs are consistent with each other, but the absolute ms values are host-specific.
- No rendering cost was measured. Only node counts and effect counts are proxies.
- The probe's sim numbers are the only numbers in this report that come from a timed measurement. The render section is counts, not time.
- Nothing here was tuned or optimised. Finding the cause of the overrun is left to a separate profiling step.
