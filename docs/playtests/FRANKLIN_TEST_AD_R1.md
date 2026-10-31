# Franklin manual test — Round AD-R1 (about 10 minutes)

Launch: from the repo root run `godot --path .` (Godot 4.7.1, see `docs/DEV.md`), then open the vertical slice (`run.tscn`) from the launcher. Use a debug build so the debug keys work.

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
| 1 / 2 / 3 | Arena only: scenario single / mixed / cluster |
| F4 | Arena only: flash |
| Tab | Arena only: starter loadout |

## Checks
1. HUD: 4 slots (slot 1 basic bolt, slots 2-3 presets, slot 4 empty) with key labels LMB/RMB/Q/E, a dash marker and a mana bar.
2. Dash (Space): short burst with i-frames (enemy hits during it do nothing); you cannot dash through walls. The dash marker shows the cooldown.
3. Hit an enemy: the damage number is white with an element symbol.
4. Clear a combat room: 3 reward cards appear. Each states the new behavior. Pick one.
5. Enemy names are bone thrall, fallen adept, grave hound; the boss is the Undead warden. Watch its telegraphs before attacks and dodge them.
6. Workshop: the editor lists 4 slots, slot 1 is locked, and an illegal edit shows a rejection reason. The cost/complexity preview updates as you edit. T resets the test range.
7. Run end (win or die): the summary offers Retry same seed, New seed and Title. Try each. There is no run resume.
8. Audio (ids from `game/audio/audio_cues_v1.json`):
   - Ambience: `amb.ruins` in the ruins, `amb.workshop` in the workshop.
   - Cast: `sfx.cast.neutral`, `sfx.cast.fire`, `sfx.cast.water`, `sfx.cast.lightning`.
   - Hit and dash: `sfx.hit.generic`, `sfx.dash`, `sfx.dash.iframe`.
   - Rewards and UI: `sfx.room.cleared`, `ui.reward_pick`, `ui.editor_error`.

## Pass/fail
- [ ] 1 slots/HUD  - [ ] 2 dash  - [ ] 3 numbers  - [ ] 4 cards
- [ ] 5 roster/warden  - [ ] 6 workshop  - [ ] 7 summary  - [ ] 8 audio

Write issues (step number, what happened, seed from the summary) under "Notes" below.

## Notes
