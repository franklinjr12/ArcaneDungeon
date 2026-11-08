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

### Step 4/4: after-state (before/after)

Date 2026-11-08, after-state commit `8f55aa4` (fixes `ac9988f`..`8f55aa4`), baseline commit `1cbba25`. Same command, same rooms (`--rooms=ruins_c07,cistern_p10`, which still runs all four target rooms), 3 runs, median per room, 600 ticks, seed 20261022.

**Host load.** Baseline: 1-minute load 0.70 / 1.93 / 2.53 (run 1 started at 0.60-0.70; later values include the probe itself). After: waited until the load fell under 1.0 (it reached 0.95 after the wait), then `AD_DEMO_PERF_HOST` logged 0.87 / 0.94 / 0.91. The two states differ by well under 0.5, so the comparison is fair and no baseline worktree re-measure was needed. The host is not fully idle (shared, load around 0.9), so treat it as "near idle", not idle.

| room | base p50 ms | base p95 ms | base max ms | after p50 ms | after p95 ms | after max ms | p95 reduction | vs 50% |
|---|---|---|---|---|---|---|---|---|
| cistern_boss | 42.331 | 80.193 | 108.424 | 9.489 | 12.533 | 14.655 | 84.4% | PASS |
| ruins_boss | 34.370 | 93.125 | 128.097 | 6.364 | 10.288 | 12.913 | 89.0% | PASS |
| ruins_c07 | 39.087 | 95.904 | 126.372 | 7.231 | 11.334 | 19.638 | 88.2% | PASS |
| cistern_p10 | 51.687 | 131.433 | 183.529 | 12.037 | 16.299 | 22.386 | 87.6% | PASS |

All four rooms reach the >= 50% p95 reduction target. Tick cost no longer grows with the trace (cistern_p10 p50 first 100 ticks 13.9 ms, last 100 ticks 11.8 ms).

**Fixes mapped to the top-5 hotspots.**

| # | hotspot | status | fix |
|---|---|---|---|
| 1 | `_audio_step` trace re-filtering | fixed | by-type trace index plus a `status_seen` cursor (`ac9988f`); resets if the trace is cleared |
| 2 | `filter_records("reaction")` in `CombatSession.step` | fixed | same index and incremental counting (`ac9988f`) |
| 3 | `filter_records("reaction")` in `RunFlow.step` | not fixed | `world/run_flow.gd` is out of scope, so this still scans per tick. Follow-up. |
| 4 | `sim.step` | partly fixed | `TargetStore.all()` cached (`490974e`), projectile homing flag cached (`e04ad44`), per-hit deep copies dropped (`ccddb93`), root essence/form ids memoized and empty `feedback`, `status`, `visuals` and `recent_damage` filters skipped (`971349f`, `8f55aa4`) |
| 5 | `session.issue` | not separately targeted | partly probe workload; its cost fell with the other changes. |

**Left for follow-up.** Remaining cost is not re-profiled in this step because the target was met. Known candidates outside the allowed files: the `RunFlow.step` reaction scan, and `navigate_direction` visibility-graph search per enemy (`world/arena_geometry.gd`, `combat/enemy_behaviours/`).

**Budget verdict.** The 4 ms budget still FAILS in all four rooms (p95 10.3-16.3 ms). That verdict is host-specific: Neoverse-N1 (aarch64, 2 cores), not the GDD reference hardware. The AD-158 numbers were taken on a shared host, so the comparison base is this section's baseline, not AD-158.

## AD-174 simulation performance pass 2

Step 1/5 (probe, digests, baseline, profile). No gameplay change.

**Date / base.** 2026-11-08, base commit `41a28b2` (stacked on AD-173). Seed 20261022, 600 ticks, 4 rooms (`cistern_boss`, `ruins_boss`, `ruins_c07`, `cistern_p10`).

**Proxy target.** Game-design ruling 2026-11-08: until the reference PC (i5 11th gen / GTX 1660) is measured, the VM proxy target is p95 <= 8 ms per room (assumes the reference CPU is about 2x this host per core; to confirm). The 4 ms budget stays as the real budget. The probe now has `PROXY_TARGET_MS`, a `proxy_pass` JSON field and a proxy verdict column.

**Behaviour digests.** The probe computes `digest` = sha256 of `trace.to_json()` plus the end state (tick, player position and mana, per enemy target id, state, x, y, hp). Two runs gave identical digests for all four rooms; they are stored in `BASELINE_DIGESTS`. `--verify-digests` requires 600 ticks and exact matches (else `AD_DEMO_PERF_DIGEST_MISMATCH`, exit 1). A legitimate data retune invalidates them; the flag is only for no-behaviour-change perf work.

**Host load.** Waited until the 1-minute load was < 1.0. `AD_DEMO_PERF_HOST` for the 3 baseline runs: 0.93, 1.01 and 1.07 (1-minute). Near idle, not fully idle.

**Commands.**

```
[ -f .godot/global_script_class_cache.cfg ] || godot --headless --path . --import
godot --headless --path . --script res://tests/qa/demo_perf_probe.gd -- --rooms=ruins_c07,cistern_p10   # x3 -> /tmp/ad174/base_N.txt
godot --headless --path . --script res://tests/qa/demo_perf_probe.gd -- --rooms=ruins_c07,cistern_p10 --verify-digests
```

**Baseline (median of 3 runs).**

| room | p50 ms | p95 ms | max ms | vs 8 ms proxy | vs 4 ms budget |
|---|---|---|---|---|---|
| cistern_boss | 9.486 | 12.914 | 22.190 | FAIL | FAIL |
| ruins_boss | 6.406 | 10.253 | 13.065 | FAIL | FAIL |
| ruins_c07 | 7.224 | 11.499 | 15.741 | FAIL | FAIL |
| cistern_p10 | 12.188 | 16.581 | 23.306 | FAIL | FAIL |

**Profile.** Temporary `Time.get_ticks_usec()` accumulators, stored per tick (reverted; `git status` shows only the probe and this doc). Cells: mean ms per tick / % of mean tick / % of the slowest 10% of ticks. Times are inclusive, so rows nest and overlap (`navigate` includes `clear_sight` via `walk_clear`; `issue_total` includes `try_cast` includes `check_slot`; `sim_step` includes `homing`, `proj_advance`, `drain`, `statuses`, `filters`; `drain` includes `process_event` includes `hit`; `enemy_advance` includes `navigate`, `clear_sight`, `behaviour_ticks`, `move_all`). Probe mean tick in the instrumented run: 9.75 / 6.86 / 7.96 / 12.82 ms (slowest 10%: 13.3 / 10.7 / 12.5 / 17.9 ms); the timers add a little overhead.

| phase | cistern_boss | ruins_boss | ruins_c07 | cistern_p10 |
|---|---|---|---|---|
| session.issue total | 2.16 / 22% / 18% | 2.13 / 31% / 22% | 2.15 / 27% / 19% | 2.21 / 17% / 13% |
| try_cast | 2.13 / 22% / 18% | 2.10 / 31% / 22% | 2.12 / 27% / 19% | 2.17 / 17% / 13% |
| loadout.check_slot | 2.01 / 21% / 15% | 1.99 / 29% / 20% | 2.00 / 25% / 17% | 2.04 / 16% / 12% |
| sim.step total | 3.19 / 33% / 39% | 2.86 / 42% / 48% | 3.41 / 43% / 56% | 3.43 / 27% / 37% |
| homing steer | 0.85 / 9% / 8% | 0.64 / 9% / 5% | 0.91 / 11% / 10% | 0.57 / 4% / 3% |
| projectile advance | 0.88 / 9% / 8% | 0.62 / 9% / 5% | 0.81 / 10% / 7% | 0.51 / 4% / 2% |
| queue.drain | 0.63 / 6% / 14% | 0.79 / 12% / 24% | 0.82 / 10% / 26% | 1.19 / 9% / 24% |
| process_event (in drain) | 0.61 / 6% / 14% | 0.77 / 11% / 23% | 0.80 / 10% / 26% | 1.16 / 9% / 23% |
| _hit (in process_event) | 0.45 / 5% / 10% | 0.57 / 8% / 17% | 0.58 / 7% / 18% | 0.84 / 7% / 17% |
| queue.push | 0.12 / 1% / 3% | 0.15 / 2% / 5% | 0.15 / 2% / 5% | 0.23 / 2% / 4% |
| statuses | 0.05 / 1% / 0% | 0.06 / 1% / 1% | 0.06 / 1% / 1% | 0.07 / 1% / 0% |
| visuals/recent_damage filters | 0.43 / 4% / 5% | 0.46 / 7% / 9% | 0.49 / 6% / 8% | 0.81 / 6% / 6% |
| advance_movers | 0.01 / 0% / 0% | 0.01 / 0% / 0% | 0.01 / 0% / 0% | 0.01 / 0% / 0% |
| enemy.advance total | 2.77 / 28% / 20% | 0.95 / 14% / 4% | 1.42 / 18% / 4% | 4.55 / 36% / 29% |
| world.navigate_direction | 2.34 / 24% / 17% | 0.64 / 9% / 2% | 1.00 / 13% / 1% | 3.99 / 31% / 25% |
| world.clear_sight (all callers) | 1.30 / 13% / 9% | 0.42 / 6% / 1% | 0.65 / 8% / 1% | 1.89 / 15% / 12% |
| _move incl. separation | 0.16 / 2% / 1% | 0.11 / 2% / 1% | 0.17 / 2% / 1% | 0.22 / 2% / 1% |
| separation loop | 0.08 / 1% / 0% | 0.06 / 1% / 0% | 0.10 / 1% / 0% | 0.11 / 1% / 1% |
| behaviour ticks | 0.07 / 1% / 0% | 0.02 / 0% / 0% | 0.03 / 0% / 0% | 0.10 / 1% / 1% |
| advance_enemy_projectiles | 0.00 / 0% / 0% | 0.03 / 0% / 0% | 0.03 / 0% / 0% | 0.01 / 0% / 0% |
| env_props pre / post | 0.00 / 0% / 0% | 0.00 / 0% / 0% | 0.00 / 0% / 0% | 0.00 / 0% / 0% |
| run_flow reaction scan (line ~414) | 1.13 / 12% / 17% | 0.54 / 8% / 18% | 0.57 / 7% / 15% | 1.85 / 14% / 16% |
| trace.record total | 0.16 / 2% / 3% | 0.20 / 3% / 5% | 0.21 / 3% / 6% | 0.27 / 2% / 5% |

**Top 5 hotspots** (by mean cost, with the slowest-10% share):

1. `world.navigate_direction` (visibility-graph search per enemy, includes `walk_clear`/`clear_sight`): 0.64-3.99 ms per tick, 9-31% of the mean tick, up to 25% of the slow ticks (cistern_p10, cistern_boss). In `world/arena_geometry.gd`.
2. `loadout.check_slot` (re-compiles the slot through the compiler cache on every cast attempt): about 2.0 ms per tick in all rooms, 16-29% of the mean tick and 12-20% of the slow ticks. The probe attempts a cast every tick; the cost is the compiler cache key (JSON encode and sha256 of the formula) in `magic/compile/`, called from `magic/runtime/spell_loadout.gd`.
3. `RunFlow.step` reaction scan (`filter_records("reaction")`, deep copies): 0.54-1.85 ms, 7-14% of the mean and 15-18% of the slow ticks. In `world/run_flow.gd`.
4. `queue.drain` -> `_process_event` -> `_hit`: 0.63-1.19 ms, 6-12% of the mean but 14-26% of the slow ticks; this is what drives the p95 spikes on cast and hit ticks. `magic/runtime/spell_runner.gd`.
5. Homing steer plus projectile advance: 0.57-0.91 ms each (4-11% each) in `spell_runner.gd` / `magic/runtime/projectile_effect.gd`. Next: `clear_sight` from `enemy.advance` (the sight check, shared with hotspot 1), then the visuals/recent_damage filters (0.43-0.81 ms, 4-7%).

**Editable-file scope.** These files are outside this task's editable files: `world/run_flow.gd`, `world/arena_geometry.gd`, `combat/enemy_behaviours/` and `magic/compile/`. Hotspots 1, 2 and 3 live mainly there, so fixes must happen in the editable callers (for example caching around the call sites in `combat/`, `magic/runtime/`) or need a planner decision.

### Step 5/5: final before/after (AD-174)

Final probe: 3 runs per room (`/tmp/ad174/after_N.txt`), median per room, taken after waiting for the 1-minute load to drop under 1.0. `AD_DEMO_PERF_HOST` 1-minute load for the 3 after runs: 0.99, 0.89, 0.99 (baseline: 0.93, 1.01, 1.07). The difference is under 0.5, so the ratios are comparable, but the host was not fully idle (about 1 busy core of 2), so treat them as approximate.

| room | base p50 / p95 / max ms | after p50 / p95 / max ms | p95 reduction | vs 8 ms proxy | vs 4 ms budget |
|---|---|---|---|---|---|
| cistern_boss | 9.486 / 12.914 / 22.190 | 5.488 / 8.414 / 10.273 | 34.8% | FAIL (8.41) | FAIL |
| ruins_boss | 6.406 / 10.253 / 13.065 | 3.317 / 7.715 / 9.780 | 24.8% | PASS | FAIL |
| ruins_c07 | 7.224 / 11.499 / 15.741 | 3.672 / 8.300 / 12.218 | 27.8% | FAIL (8.30) | FAIL |
| cistern_p10 | 12.188 / 16.581 / 23.306 | 5.662 / 13.067 / 18.635 | 21.2% | FAIL (13.07) | FAIL |

**Result: the 8 ms proxy is NOT reached.** Only ruins_boss passes. Behaviour is unchanged: `--verify-digests` matches in all rooms, `--check-equivalence` passes, the suite reports 19586 passed / 0 failed, `tests/fixtures` is untouched.

**Fixes by commit.**

| commit | fix |
|---|---|
| `6d0e16e` | memoize `check_slot`, cut per-event deep copies |
| `89b2eb8` | nearest-target query and swept wall broad-phase |
| `38516fb` | cached navigation geometry and enemy AI trims |
| step 5 commit `AD-174: trace and VFX bookkeeping, before/after table` | `DebugTrace.record` integer-field dictionary lookup; `trace.enabled` guards in `_trace_spawn` and the `hit` record; plain loops for the visuals, recent_damage and feedback filters |

**Remaining top 3 hotspots** (re-profiled with temporary `Time.get_ticks_usec()` accumulators, since reverted; mean ms per tick / share of the mean flow tick; instrumented run, so absolute values differ slightly from the table). Columns: cistern_boss, ruins_boss, ruins_c07, cistern_p10; mean flow tick 5.55 / 4.01 / 4.20 / 6.63 ms.

| # | hotspot | cistern_boss | ruins_boss | ruins_c07 | cistern_p10 |
|---|---|---|---|---|---|
| 1 | `sim.step` (SpellRunner homing steer, projectile advance, queue drain/`_hit`) | 2.72 / 49% | 2.45 / 61% | 2.59 / 62% | 2.79 / 42% |
| 2 | `RunFlow.step` reaction scan (`world/run_flow.gd` ~line 414) | 1.25 / 23% | 0.61 / 15% | 0.55 / 13% | 1.89 / 29% |
| 3 | `enemy.advance` (includes `navigate_direction` 0.55 / 0.18 / 0.27 / 0.67) | 0.95 / 17% | 0.46 / 11% | 0.60 / 14% | 1.13 / 17% |

Follow-ups (files outside this task's scope, not edited):
- `world/run_flow.gd` line 414: `filter_records(-1,"","reaction")` deep-copies every record each tick to read the new reactions. Proposed fix: use `trace.count_of("reaction")` and read only the records from `_prior_reactions` onward (an index-based accessor on the trace). This is the biggest single cheap win, up to 1.9 ms in cistern_p10.
- `world/arena_geometry.gd` / `combat/enemy_behaviours/`: `navigate_direction` still costs 0.18-0.67 ms. Proposed fix: cache the path per enemy and re-plan only when the target moves more than a tile or the enemy is blocked.
- `sim.step` (0.42-0.62 of the tick) is mostly `magic/runtime/` homing and projectile work. Proposed fix: a spatial grid for homing target selection, and projectile-advance batching. `magic/compile/` is not on this list any more because `check_slot` is memoized.

**Proxy note.** The 8 ms proxy assumes the reference PC (i5 11th gen / GTX 1660) is about 2x this host per core. That is unconfirmed until Franklin measures on the reference machine. The real budget remains 4 ms.
