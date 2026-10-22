# M4 TASK-055 — Owner Go/No-Go and Contract v2 Decision Record

**Decision status: DEFERRED / NOT AUTHORIZED.** Owner will first commission sprites in a separate task, then conduct TASK-054 human playtesting. The assistant has **not** run playtests or granted approval to start POST tasks. Do not claim v2 schema approved.

## Engineering evidence (automated only)

- [x] TASK-049 grammar matrix, legal/illegal cases, fixture/golden plan/trace regression tests run in Godot.
- [x] TASK-050 cross-element status and combat regression, stable normalized seed replay.
- [x] TASK-051 synthetic 40-target stress and cap measurement, timings/memory recorded in separate logs.
- [x] TASK-052 opt-in anonymous local telemetry / export controls and tests implemented.
- [x] TASK-053 contextual onboarding and nonblocking prompt controls implemented.
- [ ] TASK-051 actual 60-FPS normal-room result on **owner-approved reference hardware**, with an agreed target.
- [ ] TASK-054 ~6 real first-time testers and their qualitative evidence **deferred until sprite work**.
- [ ] TASK-055 explicit owner decision after evidence.
- [ ] Final scope / spell grammar decisions approved for v2 (DO NOT START).
- [ ] Any POST/TASK-056–061 approved (DO NOT START).

## Proposed hypotheses, not approved success KPIs

| Question | Proposed benchmark from `backlog_v1.md` | Evidence needed |
| --- | --- | --- |
| Creative ability | 5/6 create two distinct valid spells unaided | Human observations and formula signatures |
| Coherent elemental rules | 4/6 predict Water→Lightning after explanation | Asked before running a test |
| Short edit loop | Median Apply-to-test under 45 seconds | Opt-in timestamps and observed edits |
| Voluntary experimentation | 4/6 voluntarily change formula after new rune | Unprompted decisions |
| Stability | Zero crashes/softlocks | Session failures and reproduction clips |
| Rendering | 60 FPS on chosen normal-room reference hardware | Measured on approved rig; hardware still OPEN |

## Open questions for owner

1. Keep fixed v1 spell grammar and single Burst On Hit child, or experiment with graph-like spell construction?
2. Keep workshop-only editing or permit cleared-room quick edits?
3. Is combat sufficiently readable with final placeholder replacement and VFX, including the boss?
4. Rune duplicate policy: currency compensation or deterministic reroll?
5. Should the two-slot limit, mana economy, boss pacing and spell complexity caps remain?
6. Which hardware is the reference performance rig, and what FPS threshold should be binding?

## Authorized options (select only after TASK-054)

- [ ] PROCEED with scoped iteration (requires owner approval).
- [ ] REVISE SPELL GRAMMAR and editor (requires owner approval and schema migration plan).
- [ ] REVISE COMBAT and telegraphs (requires owner approval).
- [ ] PAUSE concept / more research (requires owner approval).

**Owner decision:** PENDING. **Date/evidence reference:** PENDING. **Rejected/accepted hypotheses:** PENDING. **Top-five evidence-backed changes:** PENDING. **v2 migration:** NOT CREATED. **POST gate:** CLOSED.
