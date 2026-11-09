# AD demo QA sweep (AD-158)

- Date: 2026-11-07
- Commit: 63b4123 (tests/qa scripts as committed in 68fb972 and 63b4123)
- Godot: 4.7.1.stable.official.a13da4feb
- Host CPU: Neoverse-N1 (`lscpu`), shared host. This is **NOT** the GDD §14 reference hardware (11th-gen i5 / GTX 1660).
- Status: measurement and QA only. No gameplay code, data or existing test was changed. Balance numbers are PROPOSED, not approved.
- Overall: smoke, determinism, test suite, UI sweep and validate are green. The perf budget and the AD-156 targets are not met (see Known issues). Natural play was run on tuned data in AD-176 (see "AD-176 natural smoke on tuned data" below): 0/60 wins; 9/20 route plays timed out.

## Reproduce

Run from the repo root. Outputs were saved under `/tmp/ad158/`. A fresh worktree needs `godot --headless --path . --import` once first (see issue 6).

```
/usr/local/bin/godot --headless --path . --script res://tests/qa/demo_smoke.gd -- --det-seeds=5 > /tmp/ad158/smoke.txt 2>&1
/usr/local/bin/godot --headless --path . --script res://tests/qa/demo_perf_probe.gd > /tmp/ad158/perf.txt 2>&1
/usr/local/bin/godot --headless --path . --script res://tests/run_tests.gd > /tmp/ad158/suite.txt 2>&1
bash tools/ui_matrix.sh --godot /usr/local/bin/godot --out /tmp/ad158/ui_matrix
python3 scripts/validate_godot.py --godot /usr/local/bin/godot > /tmp/ad158/validate.txt 2>&1
```

## 1. Full-run smoke (20 seeds)

Route mode (scripted player walks the whole `run_v2` route: ruins, workshop, cistern, final boss), `typical` build, seeds 20261022..20261041. Result: **20/20 green, 0 failing** (`AD_DEMO_QA_SUMMARY`: smoke_green 20, smoke_total 20).

QA_MD (from `smoke.txt`):

| seed | mode | build | outcome | rooms | total min | max room s | ok |
|---|---|---|---|---|---|---|---|
| 20261022 | route | typical | won | 16 | 5.249 | 113.433 | yes |
| 20261023 | route | typical | won | 15 | 5.262 | 106.05 | yes |
| 20261024 | route | typical | won | 16 | 4.926 | 116.75 | yes |
| 20261025 | route | typical | won | 17 | 6.026 | 103.6 | yes |
| 20261026 | route | typical | won | 16 | 5.484 | 117.533 | yes |
| 20261027 | route | typical | won | 15 | 4.964 | 101.1 | yes |
| 20261028 | route | typical | won | 16 | 6.382 | 126.367 | yes |
| 20261029 | route | typical | won | 17 | 5.496 | 106.45 | yes |
| 20261030 | route | typical | won | 15 | 4.606 | 102.567 | yes |
| 20261031 | route | typical | won | 16 | 4.786 | 95.117 | yes |
| 20261032 | route | typical | won | 17 | 5.796 | 128.35 | yes |
| 20261033 | route | typical | won | 17 | 5.618 | 111.35 | yes |
| 20261034 | route | typical | won | 15 | 6.233 | 125.0 | yes |
| 20261035 | route | typical | won | 16 | 5.962 | 129.983 | yes |
| 20261036 | route | typical | won | 16 | 4.729 | 79.733 | yes |
| 20261037 | route | typical | won | 15 | 4.477 | 95.517 | yes |
| 20261038 | route | typical | won | 16 | 5.589 | 112.917 | yes |
| 20261039 | route | typical | won | 16 | 6.007 | 98.383 | yes |
| 20261040 | route | typical | won | 15 | 5.621 | 129.483 | yes |
| 20261041 | route | typical | won | 16 | 4.072 | 106.55 | yes |

Notes:

- Route mode is a smoke test (every room loads, plays and exits), not a balance measure. Its 4.1-6.4 min totals are not comparable to the 30-40 min target.
- The natural-play run was not run in AD-158. It was run in AD-176 on tuned data (see the AD-176 section below).

## 2. Full-run determinism (extends AD-086)

The first 5 seeds (20261022..20261026) were each played twice and the full-run traces compared. A further check confirmed that seeds 20261022 and 20261023 give different traces (so the comparison is not vacuous).

Result: **6/6 green** (`determinism_green` 6, `determinism_total` 6): 5 same-seed matches plus 1 distinct-seed check.

## 3. Perf probe (AD-087 method)

Worst rooms chosen by the probe from 16 candidates (`AD_DEMO_PERF_ROOMS`), plus the two bosses. Same method as AD-087: worst valid formula (complexity 10 of cap 12), 8 extra enemies, 600 ticks, seed 20261022, 75 casts, budget 4.0 ms p95.

PERF_MD (from `perf.txt`):

| room | stage | enemies alive peak | p50 ms | p95 ms | max ms | peak effects | drops | verdict |
|---|---|---|---|---|---|---|---|---|
| cistern_boss | 2 | 9 | 42.211 | 82.261 | 94.875 | 57 | 0 | FAIL (>4.0 ms) |
| ruins_boss | 1 | 9 | 35.229 | 92.970 | 105.488 | 53 | 0 | FAIL (>4.0 ms) |
| ruins_c07 | 1 | 10 | 39.121 | 91.328 | 104.319 | 55 | 0 | FAIL (>4.0 ms) |
| cistern_p10 | 2 | 12 | 53.777 | 130.599 | 147.849 | 49 | 0 | FAIL (>4.0 ms) |

Comparison with `docs/playtests/ad_perf_probe.md` (AD-087, 2026-11-03, `s1_boss`, same host class): sim p95 was 39.5-42.8 ms in 3 runs. Here p95 is 82-131 ms, about 2-3x higher. The p50 values (35-54 ms) are close to the AD-087 p95. The p95 is much higher than p50 in every room, so the spikes are bursty. This run shared the host with other jobs, so wall-time noise is likely a large part of the gap; it was not re-run in isolation. No budget drops were recorded in any room (`budget_drop_records` 0). The budget verdict is FAIL in all 4 rooms, as it was in AD-087. Measurement only; nothing was optimised.

### AD-176 re-run (tuned data)

Base commit `be03ccc` (AD-175 tuned HP and damage). Worst rooms this time: ruins_c02, cistern_p08, plus ruins_c08 and cistern_p02 (the next two by enemy count), and both bosses. This table is run 1 of 3, the run closest to the median on p95. Medians of the 3 runs and the full method are in `docs/playtests/ad_perf_probe.md` (section "AD-176 pacing check"). Host load was 0.94 at the start of run 1.

PERF_MD (from `after_1.txt`, run 1):

| room | stage | enemies alive peak | p50 ms | p95 ms | max ms | peak effects | drops | verdict | proxy verdict |
|---|---|---|---|---|---|---|---|---|---|
| cistern_boss | 2 | 9 | 5.496 | 8.455 | 9.782 | 57 | 0 | FAIL (>4.0 ms) | FAIL (>8.0 ms) |
| ruins_boss | 1 | 9 | 3.281 | 7.238 | 9.499 | 53 | 0 | FAIL (>4.0 ms) | PASS |
| ruins_c02 | 1 | 11 | 4.441 | 11.208 | 16.284 | 57 | 0 | FAIL (>4.0 ms) | FAIL (>8.0 ms) |
| cistern_p08 | 2 | 11 | 6.380 | 14.418 | 19.651 | 49 | 0 | FAIL (>4.0 ms) | FAIL (>8.0 ms) |
| ruins_c08 | 1 | 11 | 3.548 | 7.243 | 9.544 | 54 | 0 | FAIL (>4.0 ms) | PASS |
| cistern_p02 | 2 | 11 | 4.551 | 9.200 | 12.256 | 50 | 0 | FAIL (>4.0 ms) | FAIL (>8.0 ms) |

Across the 3 runs, p95 ranged from 7.1 to 14.9 ms (rooms: 7.1 ruins_boss to 14.9 cistern_p08), and the peaks were 11 enemies alive and 57 active effects. The 4 ms budget fails in all 6 rooms, and the 8 ms proxy fails in 4 of 6.

## 4. UI matrix sweep

(a) Bounds test, in the full suite run (after import): `TEST SUMMARY: 19377 passed / 0 failed / 68 suites`. `SUITE test_ad_ui_bounds.gd` printed `AD-090 UI-BOUNDS REPORT total issues: 0 (report_only=false)`, so bounds are asserted, not report-only. It covers the window-size matrix across menu and run states, including sigil_desk.

(b) Screenshot sweep (`tools/ui_matrix.sh`): `SUMMARY: 182 shots, 0 failed`. Contact sheets were written for 14 states: combat, compendium, compendium_artifacts, compendium_enemies, compendium_reactions, loadout, merchant, pause, reward, settings, summary, summary_win, title, workshop_editor. PNGs are in `/tmp/ad158/ui_matrix` and were not committed or visually reviewed in this step.

- The script prints NOTE lines for `fullscreen_1280x720_on_1920x1080`: the saved image stays 1280x720 because Xvfb has no window manager. This is the documented AD-090 behaviour, not a failure.
- **Not covered by the screenshot script:** sigil_desk (and any state not in the 14 above, for example in-run debug overlays). Bounds-test coverage only; Franklin's manual checklist should look at these.

## 5. validate_godot.py

Exit code: **0**. It ran the suite twice: `TEST SUMMARY: 19377 passed / 0 failed / 68 suites`, then the negative probe `Negative failure probe: PASS (exit=1, engine_errors=0, elapsed=199.8s)`. The `1 failed` line in `validate.txt` is that deliberate probe, not a failure.

## AD-176 natural smoke on tuned data (report only)

- Date: 2026-11-08 (run started 23:24Z; the slower chunk exited 00:05Z on 2026-11-09)
- Commit: e31c1df (the parent of the step commit that adds the `--first=` / `--trace=` flags to `tests/qa/demo_smoke.gd`). Data as in `be03ccc` (AD-175 tuned HP and damage).
- Commands (run from the repo root, two processes in parallel):

```
/usr/local/bin/godot --headless --path . --script res://tests/qa/demo_smoke.gd -- --natural=1 --seeds=10 --first=0 --det-seeds=0 --trace=0 > $TMPDIR/ad176/smoke_a.txt 2>&1
/usr/local/bin/godot --headless --path . --script res://tests/qa/demo_smoke.gd -- --natural=1 --seeds=10 --first=10 --det-seeds=0 --trace=0 > $TMPDIR/ad176/smoke_b.txt 2>&1
```

- These two commands split `--natural=1 --seeds=20` into two chunks of 10 seeds (seeds 20261022..20261031 and 20261032..20261041). Together they cover all 20 route plays and all 60 natural plays.
- Traces were off (`--trace=0`). AD-173 showed trace on and off give identical run results.
- `--det-seeds=0`: section 2 determinism was **NOT** re-run in AD-176.
- Wall time: about 41 min for the slower chunk (both ran in parallel on the 2-core host). Well inside the 120 min cap; no process was stopped early.
- Result: **not green.** Route smoke 36/40 (chunk a) and 35/40 (chunk b). Natural rows 60/60 were `dead` and counted as ok. The 9 route failures are timeouts (room cap 360 s), not crashes. Exit code 1 in both chunks.

```
AD_DEMO_QA_SUMMARY:{"determinism_green":0,"determinism_total":0,"failing":["20261024:route","20261025:route","20261028:route","20261030:route"],"smoke_green":36,"smoke_total":40}
AD_DEMO_QA_SUMMARY:{"determinism_green":0,"determinism_total":0,"failing":["20261034:route","20261037:route","20261038:route","20261039:route","20261041:route"],"smoke_green":35,"smoke_total":40}
```

### Merged rows (verbatim from both `QA_MD` blocks; route first, then natural, each in seed order)

| seed | mode | build | outcome | rooms | total min | max room s | ok |
|---|---|---|---|---|---|---|---|
| 20261022 | route | typical | won | 16 | 35.697 | 254.967 | yes |
| 20261023 | route | typical | won | 15 | 30.18 | 300.433 | yes |
| 20261024 | route | typical | timeout | 11 | 22.358 | 360.0 | NO |
| 20261025 | route | typical | timeout | 14 | 29.432 | 360.0 | NO |
| 20261026 | route | typical | won | 16 | 33.223 | 226.033 | yes |
| 20261027 | route | typical | won | 15 | 30.316 | 234.583 | yes |
| 20261028 | route | typical | timeout | 14 | 31.575 | 360.0 | NO |
| 20261029 | route | typical | won | 17 | 34.844 | 252.667 | yes |
| 20261030 | route | typical | timeout | 10 | 19.544 | 360.0 | NO |
| 20261031 | route | typical | won | 16 | 32.045 | 283.417 | yes |
| 20261032 | route | typical | won | 17 | 33.933 | 231.75 | yes |
| 20261033 | route | typical | won | 17 | 33.45 | 224.167 | yes |
| 20261034 | route | typical | timeout | 10 | 20.837 | 360.0 | NO |
| 20261035 | route | typical | won | 16 | 34.338 | 251.0 | yes |
| 20261036 | route | typical | won | 16 | 32.137 | 328.2 | yes |
| 20261037 | route | typical | timeout | 15 | 31.288 | 360.0 | NO |
| 20261038 | route | typical | timeout | 13 | 28.289 | 360.0 | NO |
| 20261039 | route | typical | timeout | 11 | 22.598 | 360.0 | NO |
| 20261040 | route | typical | won | 15 | 29.173 | 218.6 | yes |
| 20261041 | route | typical | timeout | 12 | 25.391 | 360.0 | NO |
| 20261022 | natural | weak | dead | 6 | 10.611 | 140.6 | yes |
| 20261022 | natural | typical | dead | 7 | 10.801 | 139.933 | yes |
| 20261022 | natural | skilled | dead | 7 | 9.382 | 139.783 | yes |
| 20261023 | natural | weak | dead | 6 | 9.848 | 117.6 | yes |
| 20261023 | natural | typical | dead | 7 | 10.469 | 136.817 | yes |
| 20261023 | natural | skilled | dead | 7 | 10.443 | 116.067 | yes |
| 20261024 | natural | weak | dead | 7 | 13.245 | 145.517 | yes |
| 20261024 | natural | typical | dead | 8 | 13.06 | 139.667 | yes |
| 20261024 | natural | skilled | dead | 8 | 12.531 | 140.267 | yes |
| 20261025 | natural | weak | dead | 7 | 10.914 | 117.583 | yes |
| 20261025 | natural | typical | dead | 8 | 12.015 | 132.667 | yes |
| 20261025 | natural | skilled | dead | 8 | 11.036 | 115.817 | yes |
| 20261026 | natural | weak | dead | 7 | 13.288 | 139.95 | yes |
| 20261026 | natural | typical | dead | 8 | 12.515 | 139.35 | yes |
| 20261026 | natural | skilled | dead | 8 | 13.444 | 146.717 | yes |
| 20261027 | natural | weak | dead | 6 | 10.644 | 149.717 | yes |
| 20261027 | natural | typical | dead | 7 | 11.281 | 143.017 | yes |
| 20261027 | natural | skilled | dead | 7 | 11.512 | 144.9 | yes |
| 20261028 | natural | weak | dead | 6 | 11.901 | 137.867 | yes |
| 20261028 | natural | typical | dead | 7 | 10.946 | 139.75 | yes |
| 20261028 | natural | skilled | dead | 7 | 11.008 | 140.417 | yes |
| 20261029 | natural | weak | dead | 7 | 12.776 | 140.9 | yes |
| 20261029 | natural | typical | dead | 8 | 12.468 | 143.483 | yes |
| 20261029 | natural | skilled | dead | 8 | 13.134 | 144.267 | yes |
| 20261030 | natural | weak | dead | 6 | 10.357 | 131.583 | yes |
| 20261030 | natural | typical | dead | 7 | 10.168 | 125.9 | yes |
| 20261030 | natural | skilled | dead | 7 | 10.027 | 111.667 | yes |
| 20261031 | natural | weak | dead | 6 | 9.582 | 160.0 | yes |
| 20261031 | natural | typical | dead | 7 | 9.098 | 127.333 | yes |
| 20261031 | natural | skilled | dead | 7 | 9.949 | 125.933 | yes |
| 20261032 | natural | weak | dead | 7 | 10.912 | 128.067 | yes |
| 20261032 | natural | typical | dead | 8 | 12.59 | 130.667 | yes |
| 20261032 | natural | skilled | dead | 8 | 11.198 | 128.067 | yes |
| 20261033 | natural | weak | dead | 7 | 11.976 | 143.95 | yes |
| 20261033 | natural | typical | dead | 8 | 11.595 | 136.833 | yes |
| 20261033 | natural | skilled | dead | 8 | 12.689 | 136.867 | yes |
| 20261034 | natural | weak | dead | 6 | 12.475 | 144.483 | yes |
| 20261034 | natural | typical | dead | 7 | 11.112 | 140.583 | yes |
| 20261034 | natural | skilled | dead | 7 | 12.169 | 139.883 | yes |
| 20261035 | natural | weak | dead | 7 | 11.944 | 141.483 | yes |
| 20261035 | natural | typical | dead | 8 | 12.363 | 140.267 | yes |
| 20261035 | natural | skilled | dead | 8 | 13.079 | 142.667 | yes |
| 20261036 | natural | weak | dead | 6 | 9.907 | 124.883 | yes |
| 20261036 | natural | typical | dead | 7 | 10.406 | 135.767 | yes |
| 20261036 | natural | skilled | dead | 7 | 9.722 | 115.317 | yes |
| 20261037 | natural | weak | dead | 6 | 10.524 | 113.483 | yes |
| 20261037 | natural | typical | dead | 7 | 9.803 | 115.333 | yes |
| 20261037 | natural | skilled | dead | 7 | 9.853 | 135.633 | yes |
| 20261038 | natural | weak | dead | 6 | 10.33 | 143.283 | yes |
| 20261038 | natural | typical | dead | 7 | 10.771 | 139.217 | yes |
| 20261038 | natural | skilled | dead | 7 | 11.368 | 142.267 | yes |
| 20261039 | natural | weak | dead | 7 | 12.913 | 138.2 | yes |
| 20261039 | natural | typical | dead | 8 | 13.273 | 153.433 | yes |
| 20261039 | natural | skilled | dead | 8 | 13.338 | 143.15 | yes |
| 20261040 | natural | weak | dead | 6 | 10.248 | 133.317 | yes |
| 20261040 | natural | typical | dead | 7 | 9.871 | 123.217 | yes |
| 20261040 | natural | skilled | dead | 7 | 9.993 | 121.3 | yes |
| 20261041 | natural | weak | dead | 7 | 12.808 | 152.233 | yes |
| 20261041 | natural | typical | dead | 8 | 13.134 | 146.117 | yes |
| 20261041 | natural | skilled | dead | 8 | 12.846 | 151.133 | yes |

### Summary (computed from the rows above only)

Total min is over all rows of that mode and build, including timeouts for route. `won` rows only: route typical 30.180 to 35.697 min (11 rows).

| mode | build | n | outcomes | total min min / median / max | max of max room s | rows ok=NO |
|---|---|---|---|---|---|---|
| route | typical | 20 | won 11, timeout 9 | 19.544 / 30.802 / 35.697 | 360.0 | 9 |
| natural | weak | 20 | dead 20 | 9.582 / 10.913 / 13.288 | 160.0 | 0 |
| natural | typical | 20 | dead 20 | 9.098 / 11.197 / 13.273 | 153.433 | 0 |
| natural | skilled | 20 | dead 20 | 9.382 / 11.283 / 13.444 | 151.133 | 0 |

Notes:

- **Route mode is an invulnerable bot.** It cannot die, so its totals measure the whole route. 9 of 20 plays hit the 360 s room cap (`timeout`) on tuned data. AD-158 route (pre-tuning) had 20/20 wins at 4.1-6.4 min; on tuned data the 11 winning plays take 30.2-35.7 min. These are real route timeouts on tuned data: a finding for the owner, not fixed here.
- **Natural builds all died (0/60 wins), at 6-8 rooms cleared.** The `QA_MD` rows do not record the death room, so these rows alone do not show where each run died. AD-175 recorded all 60 natural runs dying at `ruins_boss` (`docs/benchmarks/ad_demo_bench.md`, AD-175 sections). Stage 2 is not measured by any natural run in AD-176.
- Compared with AD-158 route (4.1-6.4 min, pre-tuning, invulnerable): longer on tuned data, and 9 of 20 plays timed out.
- Compared with AD-175 natural (9.1-13.4 min): AD-176 natural totals are 9.1-13.4 min (rounded from 9.098-13.444). Same range.
- **Targets: NOT MET.** The 30-40 min winning-run target is not met for natural play (0 of 60 wins). For the invulnerable route, 11 of 20 plays win in 30.2-35.7 min, but 9 time out, so the route target is not met either. The 4 min room limit (no room over 240 s) is not met: on route plays, max room s is 218.6-328.2 for the 11 wins and 360.0 (cap) for the 9 timeouts. The weak-build target (dies in stage 1 or at ruins_boss on at least 11/20): 20/20 natural weak plays died, but the rows do not record where, so this is not confirmed by AD-176 output alone.

## Known issues

| # | area | symptom | evidence (file/command) | severity | owner decision needed |
|---|---|---|---|---|---|
| 1 | perf (sim) | Sim p95 exceeds the 4.0 ms budget in all 4 probed rooms: 82.3 / 93.0 / 91.3 / 130.6 ms on this host. No budget drops. | `/tmp/ad158/perf.txt`; section 3; `docs/playtests/ad_perf_probe.md`; AD-176 re-run on tuned data (3 runs, 6 rooms): p95 medians 7.2-14.4 ms (per run 7.1-14.9 ms), 1-min load 0.92-0.99 at each start | high on this host, unknown on target hardware | Accept until TASK-051 on-hardware run, or order a sim optimisation pass. |
| 2 | perf (sign-off) | TASK-051 on-hardware 60 FPS sign-off (GDD §14: 11th-gen i5 / GTX 1660) is still pending. All numbers here come from a Neoverse-N1 host, which is not the reference hardware. | `docs/playtests/ad_perf_probe.md`; header of this file | high | Franklin to run the demo build on the reference machine. |
| 3 | perf (GPU) | GPU and draw cost are not measured: the headless/dummy renderer skips rendering, so only sim time is covered. | `demo_perf_probe.gd` runs `--headless` | medium | Measure with a real renderer on target hardware. |
| 4 | balance (AD-156) | Run-length target (30-40 min), weak-dies-early (>= 11/20) and mana-starved (< 20%) targets are NOT MET: typical and skilled win 0/20 in the natural bench, starved 56.8-57.3%. Room length passes. AD-176 natural smoke on tuned data: 0/60 natural wins, all 60 runs dead at 6-8 rooms. AD-175 bots all die at `ruins_boss`. Values are PROPOSED. | `docs/benchmarks/ad_demo_bench.md` (summary table, "Why NOT MET, and the knobs needed", AD-175 sections); AD-176 section above | high for demo pacing | Approve the tuning knobs listed in the bench doc (needs golden-trace updates). The golden-trace blocker is lifted by AD-167: golden/scenario suites read `tests/fixtures/balance_frozen/`, not live data. |
| 5 | QA coverage | Natural-play smoke was run by AD-176 on tuned data (`--natural=1 --seeds=20`, two traces-off chunks): 0/60 natural wins; 9/20 route plays hit the 360 s room cap. Determinism (section 2) was not re-run (`--det-seeds=0`). | AD-176 section above; `/workspace/tmp/ad-AD-176/ad176/` (scratch, not committed) | low (AD-156 covers natural runs) | None; re-run if the tuning in issue 4 changes. |
| 6 | tooling | In a fresh worktree without `.godot/`, `run_tests.gd` fails: texture `.ctex` files fail to load (many `FAIL: AD-065/AD-030 png loads`) and `class_name` calls such as `damage_glyph_width` are missing. The first, un-imported run (`/tmp/ad158/suite_noimport.txt`) exited 1. After `godot --headless --path . --import` the suite is 19377 passed / 0 failed. | `/tmp/ad158/suite_noimport.txt`, `/tmp/ad158/suite.txt` | low (environment, not a code bug) | Decide whether the test runner or docs should run the import step automatically. |
| 7 | UI coverage | `tools/ui_matrix.sh` has no sigil_desk state, and fullscreen is not testable under Xvfb. The screenshots were not visually reviewed in this step. | section 4 | low | Check these by hand in `docs/demo/FRANKLIN_TEST.md`. |
| 8 | perf (noise) | Perf run shared the host with other jobs; p95 is 2-3x the AD-087 figure. Not re-run in isolation. | section 3; AD-176 re-run: 1-min load 0.94 / 0.99 / 0.92 at the start of runs 1 / 2 / 3, rising to 1.02-1.19 during each run, so the probe kept the host near saturation | low | Re-run on an idle host if a trend matters. |

## Friends Demo v1 (AD-190)

Date 2026-11-09. Commit `c7b7ef6` (branch task/AD-190-hermes-software-exec-ad, plus the `tools/ui_matrix.sh` state change committed before the run). Godot 4.7.1.stable.official.a13da4feb. Host: aarch64 2-core shared VM, NOT the reference PC. 1-min load at the start of the UI matrix 1.93, of the perf run 1.60 (so the host was not idle).

This section supersedes the older sections and the Known issues table above where they differ. For example, `sigil_desk` IS now in the UI matrix (it was missing in issue 7), and the matrix now also shoots `compendium_runes`, `settings_audio`, `settings_video`, `settings_controls`. Bot win rate, mana-starved % and bot room lengths are INFO and not gates (Demo Plan 19.1).

Commands (G=/usr/local/bin/godot, outputs in /tmp/ad190, export on /workspace scratch):

- `$G --headless --path . --import`
- `$G --headless --path . --script res://tests/qa/demo_smoke.gd -- --natural=1 --seeds=10 --first=0 --det-seeds=0 --trace=0` and the same with `--first=10` (two parallel chunks)
- `bash tools/ui_matrix.sh --godot $G --out /tmp/ad190/ui_matrix`
- `python3 scripts/export_demo.py --godot $G --out <scratch>/export`
- `$G --headless --path . --script res://tests/run_tests.gd`
- `XDG_DATA_HOME=/tmp/ad190/perf_xdg $G --headless --path . -- --perf-run`, then `$G --headless --path . --script res://tests/qa/demo_perf_probe.gd`

### Smoke (20 seeds 20261022-20261041, natural + route)

Both chunks exited 0: `smoke_green` 40/40 per chunk, 80 rows in total, no failing seeds, no SCRIPT ERROR or crash lines. Determinism: not re-run (`--det-seeds=0`).

| mode | build | n | outcomes | total min min / median / max | max of max room s | rows ok=NO |
|---|---|---|---|---|---|---|
| route | typical | 20 | won 20 | 3.048 / 3.459 / 3.745 | 64.083 | 0 |
| natural | weak | 20 | won 17, dead 3 | 2.338 / 2.670 / 2.939 | 52.167 | 0 |
| natural | typical | 20 | won 18, dead 2 | 3.048 / 3.349 / 3.745 | 64.083 | 0 |
| natural | skilled | 20 | won 6, dead 14 | 2.936 / 3.589 / 4.295 | 91.550 | 0 |

No route timeout at the 360 s room cap, so no possible softlock was seen in this smoke. These numbers differ strongly from the AD-176 section above (route 30 min, 9 timeouts, natural 0 wins at 9-13 min): the bots now win in about 3 minutes. Cause not investigated here (data or bot changes since AD-176); recorded as INFO for the owner. Bot run length is far below the 25-40 min G1 target, but bot numbers do not decide G1.

### UI matrix

30 states x 13 size modes: 390 shots taken, 390 headings, 0 FAIL, 0 WARN lines, 30 NOTE lines (fullscreen under Xvfb without a window manager: known limit). Every shot was reported at the requested size. The script did NOT print a `SUMMARY:` line: the contact-sheet step failed (`montage: unable to write ... pause_controls.png`) because /tmp, a 1.9 GB tmpfs, was full (25 of 30 sheets written), and `set -e` stopped the script. Not a UI defect; a scratch-space limit. PNGs were not visually reviewed and were deleted afterwards to free space.

### Release export

`scripts/export_demo.py` exit 0. Zips: `Sigilwright-0.1.0-demo-windows.zip` (38.6 MB) and `Sigilwright-0.1.0-demo-linux.zip` (29.4 MB). Linux zip verification: PASS starts headless and quits cleanly; PASS AD_UI_SHOT_STATE hook inert in release build; PASS release probe (debug keys, title, arena, run) + shipped pck contents; PASS perf run on shipped binary writes a valid report (4 rooms). Host is aarch64, so the arm64 release template ran the pack. The Windows zip was exported but not run. A first attempt with `--out /tmp/ad190/export` failed at "Prepare Template: Failed to copy export template" (same full /tmp tmpfs); the re-run on /workspace passed.

### Test suite (run log, F8 snapshot, resume)

`run_tests.gd` exit 0. TEST SUMMARY: 19558 passed / 0 failed / 78 suites. `test_ad_run_log.gd`, `test_ad_feedback_snapshot.gd` and `test_ad_resume.gd` all ran with no FAIL lines.

### Perf on the VM (INFO, headless, not valid for G4)

`--perf-run` (headless, gl_compatibility, lighting high, dev build, target p95 16.7 ms), per room, ms:

| room | frame p50 | frame p95 | frame max | sim p50 | sim p95 | sim max |
|---|---|---|---|---|---|---|
| ruins_c07 | 45.701 | 135.713 | 164.928 | 5.662 | 11.316 | 20.181 |
| cistern_p10 | 115.797 | 191.986 | 212.778 | 7.676 | 16.717 | 22.829 |
| ruins_boss | 81.658 | 154.282 | 180.634 | 5.689 | 11.107 | 14.159 |
| cistern_boss | 106.975 | 136.267 | 156.949 | 7.437 | 11.144 | 18.278 |

`demo_perf_probe.gd` (sim only, 4.0 ms budget, host load 1.23 at start): all 4 rooms over budget, 0 budget drops.

| room | p50 ms | p95 ms | max ms | proxy verdict |
|---|---|---|---|---|
| cistern_boss | 5.561 | 8.514 | 17.652 | FAIL (>8.0) |
| ruins_boss | 3.564 | 7.932 | 10.898 | PASS |
| ruins_c05 | 4.130 | 9.864 | 15.200 | FAIL (>8.0) |
| cistern_p08 | 6.588 | 14.737 | 20.904 | FAIL (>8.0) |

Frame times here come from a dummy renderer on a shared 2-core VM and say nothing about 60 FPS on the reference PC.

### Manual checks (the matrix cannot shoot these)

The UI hook has no state for the F8 report dialog or the FPS overlay, and adding one is out of scope. Franklin to check both by hand.

### Gates (Demo Plan 19.4; Franklin decides)

| gate | requirement | evidence | status |
|---|---|---|---|
| G1 | Feel: Franklin plays 3 runs; rooms quick and satisfying, no room over ~3 min, bosses feel like events, winning run 25-40 min | Bot numbers are INFO only: max room 91.6 s, bot wins take 2.3-4.3 min (far below 25-40 min) | Franklin to check |
| G2 | Onboarding: a friend with no explanation moves, dashes, casts, reads a telegraph and crafts one spell within ~5 min | `docs/demo/ONBOARDING.md` says the human test has not been run | Franklin to check |
| G3 | Stability: no crash or softlock in 20-seed smoke + Franklin's runs; workshop save/quit works | 80/80 smoke rows ok, no crash, no SCRIPT ERROR, no 360 s timeout; suite 19558/0 incl. test_ad_resume | Partial: 20-seed smoke and resume test are clean; Franklin to check his own runs and workshop save/quit by hand |
| G4 | Performance: 60 FPS at 1080p on the reference PC (i5 11th gen / GTX 1660), Lighting High (Low allowed) | Only headless VM numbers (INFO, above); `docs/demo/PERF_TEST.md` not run on the reference PC | Franklin to check |
| G5 | Build: one script makes versioned Windows/Linux zips; no debug keys or menus; launches without Godot | `export_demo.py` exit 0, 0.1.0-demo zips for both; Linux zip verify 4/4 PASS incl. release probe | Partial: script, versioned zips and Linux release checks pass; Franklin to check the Windows zip launches without Godot |
| G6 | Feedback: run log JSON per run, F8 snapshot, feedback form, clear 'send this folder' instructions | Suites test_ad_run_log and test_ad_feedback_snapshot clean; `docs/demo/FEEDBACK_FORM.md` exists | Partial: suites pass and form exists; Franklin to check F8 in a real build (report dialog) and the instructions text |
| G7 | Assets: placeholder list known; audio in or accepted as placeholder; credits and licences complete | `docs/demo/ASSET_STATUS.md`: 393 files, 390 placeholder, 3 third-party, 1 flagged (`art/export/fnt/arc_fnt_digits_3x5.png` has no recorded licence); `docs/demo/AUDIO_STATUS.md`: 77 of 77 cues placeholder or silent; credits screen from `game/data/credits_v1.json` is in the matrix | Partial: placeholder lists known and credits screen exists; Franklin to check the font licence (licences NOT complete until then) and accept placeholder audio |
| G8 | Known issues list in the friends package | `README_FRIENDS.md` has a short KNOWN ISSUES section that ships in the zip via `write_readme`. `docs/demo/KNOWN_ISSUES.md` is added by the next step, but `export_demo.py` only bundles README_FRIENDS.md + FEEDBACK_FORM.md, so KNOWN_ISSUES.md itself will NOT be in the zip (owner follow-up) | Partial: README KNOWN ISSUES ships; Franklin to check that list is enough or order KNOWN_ISSUES.md bundled |
