# AD demo QA sweep (AD-158)

- Date: 2026-11-07
- Commit: 63b4123 (tests/qa scripts as committed in 68fb972 and 63b4123)
- Godot: 4.7.1.stable.official.a13da4feb
- Host CPU: Neoverse-N1 (`lscpu`), shared host. This is **NOT** the GDD §14 reference hardware (11th-gen i5 / GTX 1660).
- Status: measurement and QA only. No gameplay code, data or existing test was changed. Balance numbers are PROPOSED, not approved.
- Overall: smoke, determinism, test suite, UI sweep and validate are green. The perf budget and the AD-156 targets are not met (see Known issues).

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
- The natural-play run (`-- --natural=1 --seeds=20`) was **not run** (time budget). AD-156 already has 20x3 natural runs: see `docs/benchmarks/ad_demo_bench.md`.

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

## 4. UI matrix sweep

(a) Bounds test, in the full suite run (after import): `TEST SUMMARY: 19377 passed / 0 failed / 68 suites`. `SUITE test_ad_ui_bounds.gd` printed `AD-090 UI-BOUNDS REPORT total issues: 0 (report_only=false)`, so bounds are asserted, not report-only. It covers the window-size matrix across menu and run states, including sigil_desk.

(b) Screenshot sweep (`tools/ui_matrix.sh`): `SUMMARY: 182 shots, 0 failed`. Contact sheets were written for 14 states: combat, compendium, compendium_artifacts, compendium_enemies, compendium_reactions, loadout, merchant, pause, reward, settings, summary, summary_win, title, workshop_editor. PNGs are in `/tmp/ad158/ui_matrix` and were not committed or visually reviewed in this step.

- The script prints NOTE lines for `fullscreen_1280x720_on_1920x1080`: the saved image stays 1280x720 because Xvfb has no window manager. This is the documented AD-090 behaviour, not a failure.
- **Not covered by the screenshot script:** sigil_desk (and any state not in the 14 above, for example in-run debug overlays). Bounds-test coverage only; Franklin's manual checklist should look at these.

## 5. validate_godot.py

Exit code: **0**. It ran the suite twice: `TEST SUMMARY: 19377 passed / 0 failed / 68 suites`, then the negative probe `Negative failure probe: PASS (exit=1, engine_errors=0, elapsed=199.8s)`. The `1 failed` line in `validate.txt` is that deliberate probe, not a failure.

## Known issues

| # | area | symptom | evidence (file/command) | severity | owner decision needed |
|---|---|---|---|---|---|
| 1 | perf (sim) | Sim p95 exceeds the 4.0 ms budget in all 4 probed rooms: 82.3 / 93.0 / 91.3 / 130.6 ms on this host. No budget drops. | `/tmp/ad158/perf.txt`; section 3; `docs/playtests/ad_perf_probe.md` | high on this host, unknown on target hardware | Accept until TASK-051 on-hardware run, or order a sim optimisation pass. |
| 2 | perf (sign-off) | TASK-051 on-hardware 60 FPS sign-off (GDD §14: 11th-gen i5 / GTX 1660) is still pending. All numbers here come from a Neoverse-N1 host, which is not the reference hardware. | `docs/playtests/ad_perf_probe.md`; header of this file | high | Franklin to run the demo build on the reference machine. |
| 3 | perf (GPU) | GPU and draw cost are not measured: the headless/dummy renderer skips rendering, so only sim time is covered. | `demo_perf_probe.gd` runs `--headless` | medium | Measure with a real renderer on target hardware. |
| 4 | balance (AD-156) | Run-length target (30-40 min), weak-dies-early (>= 11/20) and mana-starved (< 20%) targets are NOT MET: typical and skilled win 0/20 in the natural bench, starved 56.8-57.3%. Room length passes. Values are PROPOSED. | `docs/benchmarks/ad_demo_bench.md` (summary table, "Why NOT MET, and the knobs needed") | high for demo pacing | Approve the tuning knobs listed in the bench doc (needs golden-trace updates). The golden-trace blocker is lifted by AD-167: golden/scenario suites read `tests/fixtures/balance_frozen/`, not live data. |
| 5 | QA coverage | Natural-play smoke (`--natural=1 --seeds=20`) was not run here; route-mode smoke only. Route totals (4.1-6.4 min) do not reflect real play length. | section 1 | low (AD-156 covers natural runs) | None; re-run if the tuning in issue 4 changes. |
| 6 | tooling | In a fresh worktree without `.godot/`, `run_tests.gd` fails: texture `.ctex` files fail to load (many `FAIL: AD-065/AD-030 png loads`) and `class_name` calls such as `damage_glyph_width` are missing. The first, un-imported run (`/tmp/ad158/suite_noimport.txt`) exited 1. After `godot --headless --path . --import` the suite is 19377 passed / 0 failed. | `/tmp/ad158/suite_noimport.txt`, `/tmp/ad158/suite.txt` | low (environment, not a code bug) | Decide whether the test runner or docs should run the import step automatically. |
| 7 | UI coverage | `tools/ui_matrix.sh` has no sigil_desk state, and fullscreen is not testable under Xvfb. The screenshots were not visually reviewed in this step. | section 4 | low | Check these by hand in `docs/demo/FRANKLIN_TEST.md`. |
| 8 | perf (noise) | Perf run shared the host with other jobs; p95 is 2-3x the AD-087 figure. Not re-run in isolation. | section 3 | low | Re-run on an idle host if a trend matters. |
