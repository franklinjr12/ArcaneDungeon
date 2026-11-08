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

## AD-170 simulation performance pass

Step 1/4: baseline and profile, no optimisation yet. Date 2026-11-08, base commit `1cbba25` (branch stacked on `origin/ad-hermes-2026-11-06`, which includes AD-169), Godot 4.7.1-stable, host Neoverse-N1 (aarch64, 2 cores, shared).

**Host load.** Not a fully idle host. The 1-minute load average was 0.60-0.70 when run 1 started (below the 1.0 threshold). Runs 2 and 3 started back-to-back and logged 1.93 and 2.53, but most of that is the previous probe run itself. Each run logs `AD_DEMO_PERF_HOST:` (`/proc/loadavg`): `0.70 0.87 1.27`, `1.93 1.31 1.39`, `2.53 1.71 1.53`. The other processes seen on the host were idle-level (about 5% CPU each). Absolute numbers are still high on this shared box. Use the before/after ratio.

**Commands** (the probe targets cistern_boss, ruins_boss, ruins_c07 and cistern_p10; every room was in the sequence, so no rerun without `--rooms`):
```
/usr/local/bin/godot --headless --path . --import
mkdir -p /tmp/ad170; for i in 1 2 3; do /usr/local/bin/godot --headless --path . --script res://tests/qa/demo_perf_probe.gd -- --rooms=ruins_c07,cistern_p10 > /tmp/ad170/base_$i.txt 2>&1; done
```

### Baseline (median of 3 runs, 600 ticks, seed 20261022)

| room | p50 ms | p95 ms | max ms | trace_records | p50 first 100 ticks ms | p50 last 100 ticks ms |
|---|---|---|---|---|---|---|
| cistern_boss | 42.331 | 80.193 | 108.424 | 7125 | 7.548 | 76.670 |
| ruins_boss | 34.370 | 93.125 | 128.097 | 8971 | 6.289 | 88.728 |
| ruins_c07 | 39.087 | 95.904 | 126.372 | 9038 | 9.020 | 90.206 |
| cistern_p10 | 51.687 | 131.433 | 183.529 | 11733 | 16.824 | 123.405 |

The hypothesis is **confirmed**. Tick cost grows linearly with the trace, from 6-17 ms in the first 100 ticks to 77-123 ms in the last 100 (about 10x). p95 is about 2x p50 because of this growth, not because of noisy spikes. The trace is deterministic and must stay byte-identical, so the fix is to stop re-scanning and deep-copying it every tick, not to trim it.

### Profile (temporary `Time.get_ticks_usec()` accumulators, reverted; shares of mean tick time, 600 ticks)

| room | mean tick ms (instrumented) | `_audio_step` | `filter_records("reaction")` in `CombatSession.step` | `filter_records("reaction")` in `RunFlow.step` | `sim.step` | `session.issue` | `enemy.advance` loop |
|---|---|---|---|---|---|---|---|
| cistern_boss | 40.0 | 56.3% | 11.0% | 10.2% | 9.4% | 5.9% | 6.0% |
| ruins_boss | 39.9 | 62.5% | 10.0% | 9.4% | 8.9% | 6.3% | 2.1% |
| ruins_c07 | 42.1 | 62.1% | 9.7% | 9.2% | 9.5% | 5.7% | 2.9% |
| cistern_p10 | 57.5 | 58.7% | 11.4% | 10.6% | 6.7% | 4.2% | 7.0% |

Inside `sim.step` (SpellRunner.advance_one_tick), as a share of the whole tick: homing steer 1-3%, projectile advance 1-3%, `queue.drain` about 2%, `visuals`/`recent_damage` filters about 1.2%, `_tick_statuses` and `_prune_chain_seen` under 0.3%. `env_props` pre/post, hazards/water, `apply_scales`, `advance_enemy_projectiles` and the `feedback` filter are each below 0.2%. Shares are the first profiling run; the `_audio_step` share was confirmed in a second run on ruins_c07 (62.1% there, with `apply_scales` 0.02% and `advance_enemy_projectiles` 0.12%).

### Top 5 hotspots

| # | phase | file:function | share of mean tick | planned fix |
|---|---|---|---|---|
| 1 | audio cue derivation: 4 full `filter_records` scans per tick (hit, each `_audio_trace` type, status) | `combat/combat_session.gd:_audio_step` | 56-63% | Keep per-kind cursors and counts, and read only records appended since the last tick instead of re-filtering the whole trace. Output-only, so no sim change. A shared per-kind append index needs `debug/debug_trace.gd` (see note). |
| 2 | reaction count: `filter_records(-1,"","reaction")` | `combat/combat_session.gd:step` | 10-11% | Count only new records using a cursor, or one shared per-tick reaction count. |
| 3 | reaction scan to feed `_seen_reactions` | `world/run_flow.gd:step` | 9-11% | Same shared incremental reaction count, reading only `[_prior_reactions:]`. `run_flow.gd` is outside the allowed file list (see note). |
| 4 | simulation step (movement, collision, homing steer) | `magic/runtime/spell_runner.gd:advance_one_tick` | 7-10% (steer plus advance about 2-5%) | Cut per-tick allocations: the `active.duplicate()` copy, repeated `_modifier_ids`, and the per-tick `visuals`/`recent_damage` `filter` lambdas. |
| 5 | player command issue | `combat/combat_session.gd:issue` (called from `RunFlow.step`) | 4-6% | Profile in step 2. This is the probe's per-tick cast command, so it is partly probe workload. Fix only if it is not the compile or validate path called for every cast. |

**Scope notes.** The trace storage lives in `debug/debug_trace.gd`, which is outside the allowed edit scope. `filter_records` deep-copies each matching entry (`entry.duplicate(true)`) and `snapshot()` copies the whole array. Hotspots 1 and 2 can be fixed inside `combat/combat_session.gd` using cursors over the records. Reading the trace through `snapshot()` would still copy it, so a clean fix needs a cheap read API on the trace (a size or kind-count accessor, or a `filter_records` with a start index). Hotspot 3 sits in `world/run_flow.gd`, also outside the allowed scope. If it stays out of scope, `CombatSession` can expose the per-tick reaction count that `RunFlow` reads. Both points need a decision from the planner before step 2.
