# Friends demo onboarding (AD-185, Gate G2)

Goal of Gate G2: a new player starts, moves, dashes, casts, reads a telegraph, opens the editor and crafts one spell within about 5 minutes without help.

## Step -> tip -> trigger

| Step | Tip id | Trigger |
| --- | --- | --- |
| Start | `spells_are_runes` | Sigil Desk prelude (AD-130) is active and the editor is not open; the desk panel steps teach the first spell. |
| Move, aim, cast, dash | `room1` | First fight room of a run (`sequence_index == 0`). Text shows the current bindings (move, cast, dash, aim). |
| Read a telegraph | `telegraph` | First enemy windup. Shown for `onboarding_seconds.telegraph` (6 s, in `flavour_v1.json`), then `room1` returns if it was interrupted. |
| Open the editor and craft | `spells_are_runes`, `workshop_empty_slot`, `test_on_dummy` | Desk panel steps; empty slot hint and the test-on-dummy hint in the workshop editor. |
| First reward | `first_reward` | Room cleared and the reward is not collected yet. |
| First workshop | `first_workshop` | Entering the workshop outside the prelude. |
| Wet then lightning | `wet_try_lightning` | Reaction hint after the matching status in a fight. |

Tip texts live in `world/data/flavour_v1.json` (`onboarding`, `onboarding_seconds`) and `i18n/`.

## Audit outcome

- Already existed: `room1`, `first_reward`, `first_workshop`, the hints (`workshop_empty_slot`, `test_on_dummy`, `wet_try_lightning`) and the AD-130 Sigil Desk prelude.
- Added: binding-aware `room1` strip, `telegraph`, `spells_are_runes` pointer, the one-tip rule, Settings > Accessibility Tips on/off, and a Controls page reachable from the pause menu.
- Fixed: the `room1` trigger waited for an `s1_r1` room, which `run_v2` does not have. It now fires on `sequence_index == 0`.

## Rules

- At most one tip is on screen.
- Each tip shows once per profile (`stats.onboarding_seen`).
- Settings > Accessibility > Tips on/off does not use tips up.
- Controls opens from pause and reads the live bindings.
- The new wording is proposed, not approved.

## UI matrix shots

```
bash tools/ui_matrix.sh --states "tip_room1 tip_telegraph tip_wet_try_lightning tip_first_reward tip_first_workshop tip_workshop_empty_slot tip_test_on_dummy tip_spells_are_runes pause_controls settings_access" --sizes "1024x768 1280x720 1920x1080"
```

Shots are in `docs/ui/matrix/<size>/<state>.png` with contact sheets next to them. The `tip_*` states pin one tip on a debug build only.

## Not done yet

The 5-minute human test with a friend has not been run, so Gate G2 is not confirmed.
