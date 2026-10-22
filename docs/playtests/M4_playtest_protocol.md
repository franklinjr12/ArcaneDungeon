# M4 TASK-054 — Deferred human playtest protocol

**Status: NOT CONDUCTED.** The project owner specifically postponed playtesting until sprites have been added in a separate art workstream. Do not recruit participants, upload clips, report usability results or make product decisions from deterministic agent replays. This is a ready-to-execute protocol for later.

## Prerequisites

- User approves game visuals as adequate for qualitative first-use testing; original gameplay code and all M0–M4 automated validations green.
- Confirm intended test hardware and capture engine FPS in normal rooms. **60 FPS is only a proposed threshold**, not an approved pass/fail gate.
- Six first-time testers where feasible; 20–30 minutes each. Independent anonymous IDs `T-001` through `T-006`. Participation consent for video/steps and local opt-in telemetry separately. No personal identifiers or uploads.
- Explicitly note that gamepad and final audio/visual polish may still be missing; do not conflate incomplete presentation with grammar/system depth.

## Fixed test path (20–30 minutes)

1. 0–3 min: start a new seeded run; read/dismiss prompts at will; cast both starter spells with mouse and move/dodge using WASD/Space.
2. 3–9 min: complete room 1, choose rune vs currency reward, discuss what the acquired rune enables. Avoid telling participant which spell to make.
3. 9–16 min: continue encounters and boss, recording attack clarity, dodging, and whether a player freely chooses to edit between rooms when allowed.
4. 16–23 min: visit the workshop; ask player to build **two mechanically different valid spells** without detailed coaching. Record time from editor Apply to first cast on a practice dummy. Ask what each formula will do *before* casting. Use the Wet-cluster button and explain Water→Wet→Lightning once; ask them to predict what happens next.
5. 23–30 min: buy a rune/upgrade if affordable, test a changed spell, then enter stage two. Collect feedback independently for spell editor usability, magical interactions/depth and combat feel.

If completion stalls or a participant dies, record the reproduction steps and what failed; do not secretly manipulate the game state to claim success. If technical issues consume the slot, mark the observation **incomplete**.

## Measurement sheet

Copy `observations_template.json` to a **local, untracked** file (e.g., `C:\temp\m4_observations.json`). For each session, record:

```json
{
  "anonymous_id": "T-001",
  "completed": false,
  "two_distinct_spells_unaided": null,
  "predicts_wet_lightning": null,
  "voluntary_edit": null,
  "crash_or_softlock": null,
  "normal_room_fps": null,
  "reference_hardware": "",
  "expected_spell_behavior": "",
  "unexpected_behavior": "",
  "wanted_to_try": "",
  "editor_usability": "",
  "magic_depth": "",
  "combat_feel": "",
  "failure_clip_or_steps": ""
}
```

The participant may independently opt in with **Opt in / out of local telemetry**, then export anonymized JSON/CSV using the in-game Export button. The tool does not upload data, store names or record arbitrary user-entered spell titles. If a participant opts out, the in-memory telemetry buffer is cleared; previously exported files must be deleted manually if no longer authorized. The in-memory `RunState` continues to track gameplay edits, which do not automatically leave the device.

To synthesize a **clearly labeled incomplete report**, even with zero sessions:

```powershell
python scripts/summarize_m4_playtest.py --observations docs/playtests/observations_template.json --output C:\temp\m4_findings.md
```

Supply one or more exported opt-in logs by adding `--log <path>`. The script calculates counts, hash diversity and edit-to-test median, and compares **proposed** thresholds only when sufficient real session evidence exists. Fill the top-five prioritized changes and attach consented reproduction clips/steps manually after tests.

## Evidence separation

- **Editor usability:** chooser clarity, invalid reason recognition, undo/apply/cancel errors, time to first novel custom spell.
- **Magic system depth:** behavioral variety, predicted vs observed formula semantics, rune combinations, reaction understanding.
- **Combat feel:** dodges, collision legibility, attack warnings, readable elemental feedback, damage clarity and actual rendered FPS.

Use these as distinct categories in the later owner decision record; no synthetic driver can substitute for them.
