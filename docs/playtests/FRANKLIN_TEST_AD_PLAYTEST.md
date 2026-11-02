# Franklin playtest-readiness checklist — AD-041 (about 15 minutes)

Replaces the AD-R1 checklist. Screenshots of the expected look are in [ad_r2_readiness/](ad_r2_readiness/README.md) (captured with the P1 default visuals on seed `20261022`).

Launch: from the repo root run `godot --path .` (Godot 4.7.1, see `docs/DEV.md`), then open the vertical slice (`run.tscn`) from the launcher. Use a debug build so the debug keys work. The scripted route seed is `20261022`.

## Keys
| Key | Action |
| --- | --- |
| WASD / arrows | Move |
| LMB / RMB | Cast slot 1 / 2 |
| Q / E | Cast slot 3 / 4 |
| Space | Dash |
| F | Interact |
| Esc | Pause |
| R | Retry same seed (run; also arena retry) |
| T | Reset test range (workshop only) |
| F2 | Policy debug (run, debug builds) |
| F3 | Toggle debug overlay (run and arena, debug builds) |
| F6 | Toggle P0 placeholder art (debug builds; P1 art is the default) |
| 1 / 2 / 3 | Arena only: scenario single / mixed / cluster |
| F4 | Arena only: flash |
| Tab | Arena only: starter loadout |

Telemetry has no keyboard keys. Use the sidebar buttons **Opt in / out of local telemetry** (OFF by default) and **Export opt-in JSON + CSV**.

## Checks
Expected look is linked as `(shot)`. Shot names are files in `ad_r2_readiness/`.

1. **HUD with P1 parts and rune icons:** portrait, HP/MP, 4 slots (slot 1 basic bolt, slots 2–3 presets, slot 4 empty) with icons, cooldowns, key labels LMB/RMB/Q/E and a dash marker. (`hud.png`; P0 comparison `p0_f6_comparison.png`.)
2. **Dash (Space):** short burst with i-frames; no dash through walls; the dash marker shows the cooldown. (No dedicated shot.)
3. **Cast each element and its status:** Fire → Burning, Water → Wet, Lightning → Charged. Check the projectile in flight and the on-hit burst plus status icon. (`fire_cast.png` / `fire_status.png`, `water_cast.png` / `water_status.png`, `lightning_cast.png` / `lightning_status.png`.)
4. **Wet → Lightning arc:** lightning hitting a Wet target arcs once to the nearest other Wet target, with the `ARC!` label. (`wet_lightning_arc.png`.)
5. **Enemy telegraphs:** each enemy shows its windup telegraph and countdown before attacking, and you can dodge it: bone thrall (`telegraph_bone_thrall.png`), fallen adept (`telegraph_fallen_adept.png`), grave hound (`telegraph_grave_hound.png`), Undead warden radial (`telegraph_undead_warden.png`). Note: the warden's radial disc covers most of its sprite during windup. This is the current P1 design, under review.
6. **Warden phase cue:** at 50% HP the warden shows a phase ring (`boss.phase`). (`warden_phase_cue.png`.)
7. **Damage numbers:** white, with an element glyph. (No dedicated shot; compare against `fire_status.png`.)
8. **Reward cards:** clearing a combat room shows 3 cards that each state the new behavior. Pick one. (`reward_pick.png`.)
9. **Editor rejection reason:** workshop editor lists 4 slots, slot 1 is locked, an illegal edit shows a rejection reason and Apply is disabled. The cost/complexity preview updates as you edit. T resets the test range. (`editor_rejection.png`.)
10. **Run summary:** on win or death, the summary offers **Retry same seed**, **New seed** and **Title**. Try each; there is no run resume. (`run_summary.png`.)
11. **Animated actors:** enemies and the mage play their animations while moving, winding up and attacking. (No dedicated shot; the `hitbox_*.png` shots show the sprites at 2x.)
12. **Audio (ids from `game/audio/audio_cues_v1.json`):**
   - Ambience: `amb.ruins` in the ruins, `amb.workshop` in the workshop.
   - Cast: `sfx.cast.neutral`, `sfx.cast.fire`, `sfx.cast.water`, `sfx.cast.lightning`.
   - Hit and dash: `sfx.hit.generic`, `sfx.dash`, `sfx.dash.iframe`.
   - Rewards and UI: `sfx.room.cleared`, `ui.reward_pick`, `ui.editor_error`.

## Pass/fail
- [ ] 1 HUD  - [ ] 2 dash  - [ ] 3 cast/status  - [ ] 4 arc
- [ ] 5 telegraphs  - [ ] 6 phase cue  - [ ] 7 numbers  - [ ] 8 cards
- [ ] 9 workshop  - [ ] 10 summary  - [ ] 11 actors  - [ ] 12 audio

## GDD §14 targets and how to measure
These are **proposed hypotheses, not KPIs** (GDD v1.0 §14).

1. In the sidebar, click **Opt in / out of local telemetry**. It is OFF by default and nothing is uploaded.
2. Play the slice (seed `20261022` or a seed of your choice) to the end.
3. Click **Export opt-in JSON + CSV**. The files are `user://arcane_m4_experiment.json` and `user://arcane_m4_experiment.csv` in the Godot user directory.
4. Read the JSON `summary` object:

| Field | Proposed target | Note |
| --- | --- | --- |
| `summary.distinct_spells_built` | at least 2 distinct spells, 5/6 players, unaided | Counts distinct formulas saved in the editor. It cannot show "unaided"; the observer decides that. |
| `summary.edit_to_test_median_ms` | under 45000 | `-1` means no edit→test pair was recorded. |
| `summary.crashes` | 0 | Counted when a previous session left its lock file behind. |
| `summary.slice_time_ms` | roughly 1,200,000–2,100,000 (20–35 min) | Array with one value per completed slice (`slice_complete` `duration_ms`). |

5. **FPS** on the reference machine (11th-gen i5 / 8 GB / GTX 1660) is measured separately; see `docs/M4_validation.md`. The sidebar FPS readout is not a validated benchmark.

Write issues (step number, what happened, seed from the summary) under "Notes" below.

## Notes
