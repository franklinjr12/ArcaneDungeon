# ArcaneDungeon — M4 Validation Implementation (TASK-049–055)

**Status:** TASK-049–053 automated/code work implemented. TASK-054 **human sessions explicitly delayed until owner requests them after sprite production**; TASK-055 **owner go/no-go undecided**. These are not claimed to be complete. All visual assets and changes to `docs/assets/art_style_reference.png` are out of scope. Godot 4.7.2 GL Compatibility is the tested build, not a final owner-approved engine pin.

## Launch and inspect

Launch the project, then **Start Run (M3)** to play the current combat vertical slice with M4 additions. It still has the two legal starter spells and the Stage 1 rooms → Boss → Safe Workshop → Stage 2 sequence. The UI includes:
- **Onboarding:** Context-sensitive *TIP* text for combat, rune rewards, doors, editor and workshop. Dismiss tips / Show tips actions do not block gameplay.
- **Telemetry consent:** **Opt in / out of local telemetry** is **OFF by default**. With opt-in, session metrics are collected in memory; **Export opt-in JSON + CSV** writes only local `user://arcane_m4_experiment.json` and `user://arcane_m4_experiment.csv`. Neither the game nor the scripts have an upload mechanism. Opt-out clears recorded memory. Previously exported files remain on disk until manually deleted; inform the participant.
- **Rendering measurement:** Sidebar displays actual engine-reported rendering FPS and the lowest sampled `_process` FPS. These are observed display values in the running game, **not** validated reference hardware or a synthetic benchmark FPS.
- **Safe learning:** The workshop has prepared Wet practice targets and uses exactly the same live spell compiler/resolver as the dungeon. Water applies Wet; Lightning hitting a Wet target may arc to another eligible Wet target.
- **M1 Sandbox:** A new **Profile** button runs the M4 synthetic 40-target stress preset and shows headless-like fixed-tick logic timing; **Stress** retains the original instant per-root budget probe. The later explicitly commissioned art workstream now replaces most playable placeholders with reference-guided sprites and UI. See `docs/ART_IMPLEMENTATION.md`; this document continues to cover M4 technical validation. The deferred human playtest still has not been conducted.

## Automated validation

```powershell
cd C:\Repos\ArcaneDungeon
python scripts/validate_godot.py --godot "C:\Users\sa-su\Documents\Godot\Godot_console.exe"
```

The validation script now runs parser/import, launcher navigation, M1 sandbox UI, M2 arena UI, M3+M4 run UI, deterministic test discovery, a 40-target stress probe, and an expected nonzero intentional-failure test. It rejects Godot engine error output even when the executable exits 0. CI should invoke this same wrapper.

```powershell
& "C:\Users\sa-su\Documents\Godot\Godot_console.exe" --headless --path . --script res://tests/m4_stress_probe.gd
```

This logs one `M4_STRESS` JSON object with `mean_tick_ms`, `p95_tick_ms`, `max_tick_ms`, `memory_static_start_bytes`, `memory_static_peak_bytes`, `memory_static_delta_bytes`, `peak_active_effects`, `peak_queued_events`, `budget_drop_records`, `hit_records`, `reaction_records`, `trigger_records`, root cap and counters. **Synthetic fixed-tick timings are not display-frame FPS.** Godot uses `RefCounted` and engine-managed allocations; an isolated tracing-GC pause statistic is not exposed by this benchmark, so `gc_pause_ms` is null and not fabricated. Do not compare two systems without identical hardware/load/renderer.

## M4 code and automated acceptance

| Task | Implementation / tests | Status |
| --- | --- | --- |
| TASK-049 Spell grammar | `tests/test_m4_grammar.gd`: 3 Essences × 3 Manifestations, all legal Projectile modifiers, On Hit Burst, explicitly pinned costs/complexities/phases, invalid type/schema/ownership/duplicates/locked runes. Existing `tests/test_m1_trace_golden.gd` locks Split+On Hit and Pierce+On Hit causal event order; compiler plan changes are caught. | Coding/tests done; permanent v1 semantics still subject to owner |
| TASK-050 Cross-spell and combat | `tests/test_m4_reactions.gd`: Fire/Burning refresh/DOT/death, Water extinguish, Wet expiration tick, Lightning targeting/tie IDs, removal before arc, zero eligible, resistance, team, boss element policy, repeatable normalized traces, double reward safeguards; M2 dodge tests remain in `test_m2_combat.gd`. | Coding/tests done |
| TASK-051 Stress/profiling | `debug/stress_profiler.gd`, `tests/test_m4_stress.gd`, `tests/m4_stress_probe.gd`: 36–40 targets including movers/statuses, Split+On Hit, Pierce+On Hit, Orb, traced 10,000 attempted reservations; cap, responsiveness and later casts asserted. In-game M1 Profile button. | **Synthetic code/tests done**. Normal-room 60 FPS on owner-approved hardware and 10-minute human/visual stability checks **pending** |
| TASK-052 Local telemetry | `debug/experiment_log.gd`, RunFlow and UI opt-in hooks, `test_m4_experiment.gd`. Anonymous event kinds: rune choices, room clears, deaths, dungeon casts, reaction counts, test casts, editor open/close/apply, purchases, restarts. Formula signatures hash **only stable rune/mechanics IDs** (excluding display names and free text). Local JSON+CSV. Invariant test: opt-in vs disabled yields same gameplay trace. | Code/tests done; no real participant logs yet |
| TASK-053 First-use guidance | `ui/onboarding_prompts.gd`, `ui/run_controller.gd`: dismiss/reopen and contextual explanation of Essence, Form, Modifier, and On Hit Burst payload, starter cast instructions, Wet→Lightning range preset already in M3. `test_m4_experiment.gd` and UI smoke assertions. | Coding done. One-minute first-user performance requires **human testing** |
| TASK-054 Human playtest | `docs/playtests/M4_playtest_protocol.md`, `observations_template.json`, and `scripts/summarize_m4_playtest.py`. Local report generator clearly prints **pending** if participants are absent. | **Deferred by owner until sprites are ready** |
| TASK-055 Decision & v2 | `docs/playtests/M4_decision_record.md` lists proposed metrics, owner questions, evidence gaps, possible decisions. | **Not decided. No v2 migration and no POST work authorized** |

Tuning limits have **not been increased merely to improve reported stress throughput**. All current M0–M3 v1 formula JSON and golden fixtures are unchanged; existing deterministic tests remain the authority on compatibility.

### Observed synthetic benchmark (one local execution; seed 5151)

The 300-tick 40-target reference run completed, with **325 hits, 90 On Hit triggers, 43 arc reactions**, 25 peak active effects, no events left queued, and one traced budget drop. It explicitly attempted 10,000 effect reservations; 32 were accepted by the configured per-root cap of 32. On that run, mean fixed-simulation-step time was approximately 1.44 ms and p95 3.00 ms; **these numbers vary by load and are not actual rendered FPS or owner-defined performance targets**.

## Deferred human review process

Review `docs/playtests/M4_playtest_protocol.md` **after** commissioning assets in a separate execution. For ~6 new testers, run 20–30 minute sessions, keep anonymous local notes, record independent reactions and voluntary editing behavior, and opt in to telemetry separately. Proposed hypotheses from the backlog: 5/6 create two distinct spells unaided, 4/6 predict Wet→Lightning, median edit-to-test below 45 seconds, 4/6 voluntarily edit after rune discovery, no crashes/softlocks, and 60 FPS on agreed reference hardware. **They are hypotheses, not approved KPIs.**

Then locally run:

```powershell
python scripts/summarize_m4_playtest.py --observations C:\temp\m4_observations.json --log C:\temp\m4_session1.json --output C:\temp\m4_findings.md
```

More `--log` arguments can be added. The script does no network access; it labels incomplete data as pending and includes sections for expected vs experienced spell behaviors, editor usability, magic-system depth, combat feel and five owner-prioritized changes.

`docs/playtests/M4_decision_record.md` remains **PENDING** until the owner reviews actual playtest evidence. Never perform TASK-056–061 or a v2 schema migration based on synthetic-agent success alone.
