# Meta progression and Compendium (AD-145)

Light, persistent progression for the closed demo. Numbers marked **PROPOSED** are tunable in `world/data/meta_v1.json`.

## Profile schema v3
`user://profile.json` gains `meta.discovered`: a sorted list of unique ids per category (`runes`, `reactions`, `enemies`, `artifacts`) (schema v2), and `meta.ink` (schema v3, see Arcane Ink below). Code: `world/meta_progress.gd`, `SaveService.meta()`, `record_discoveries()`, `locked_runes()`, `locked_artifacts()`.

## Migration
A v1 or v2 profile loads with its stats and discoveries intact; a missing `meta.ink` defaults to 0. The migration happens in memory; the file is written as v3 on the next save. A v1 profile loads with its stats intact and an empty `meta` block. A corrupt profile or an invalid `meta` block is quarantined and replaced with defaults (existing corrupt-profile handling).

## Discovery sources
At run end the run state reports ids seen during the run (runes owned, reactions triggered, enemies killed, artifacts held); `SaveService.record_run` merges them. Merging is idempotent and deterministic (no RNG, no clock).

## Milestones (PROPOSED)
| Id | Needs | Unlocks |
|---|---|---|
| runes_8 | 8 runes | rune `trigger.on_expire`, artifact `echo_chamber` |
| reactions_2 | 2 reactions | rune `trigger.timer`, artifact `stormglass` |
| enemies_6 | 6 enemies | artifacts `shatterheart`, `gravity_lens` |
| artifacts_4 | 4 artifacts | artifact `archivists_quill` |

Unlocked ids that are not met stay out of the reward and merchant pools (`_apply_meta_locks`).

## Arcane Ink (AD-233)
Persistent currency earned in every run and kept on death, quit and win. Currency only: nothing can be bought with it yet (spending is a later task) and it changes no stat.

- **Storage:** `meta.ink` in the v3 profile (int, default 0, negative or non-numeric is quarantined). `SaveService.record_run` adds the run's `ink_earned` via `MetaProgress.add_ink`; a missing or negative value is ignored. `SaveService.ink()` returns the total.
- **Earn rules:** the `ink` block in `world/data/meta_v1.json`: `room_cleared` 3, `mini_boss` 8, `boss` 20, `new_stage` 5, `run_won` 15 (PROPOSED).
- **Crediting:** `world/run_flow.gd` (`_credit_ink`) adds the amount when each event happens: room cleared, mini-boss defeated, boss defeated, new stage entered, run won. `ink_earned` resets at run start.
- **When saved:** at run end through `record_run`, for every ending: death (`lost`), win (`won`), and Quit to Title / pause-menu quit (`abandoned`). Until then the running total travels in the workshop-save payload (`ink_earned` in the flow counters), so Save & Continue keeps it.
- **Summary:** the run summary shows `Ink earned +N (total M)` (`run.summary.ink`), where N is this run and M is the saved total after the run is recorded.
- **Tests:** `tests/test_ad_meta_ink.gd` (config values, add/negative rules, v1/v2 to v3 migration keeping discoveries, ink kept on death/quit/win, save/relaunch round trip). It runs under `run_tests.gd` via `run(t)` and directly with `--script res://tests/test_ad_meta_ink.gd`.

## No stat power
Unlocks only widen which runes and artifacts can appear. Nothing changes HP, damage, mana or any other stat; a test asserts stats are untouched by milestones.

## Compendium
`ui/compendium_screen.gd`, opened from the main menu (`CompendiumButton`). Four sections shown as discovered/total, undiscovered entries show `???`, plus a Milestones list with progress and met/locked marks. Read-only; Back or `ui_cancel` returns to the title. Debug shot state: `AD_UI_SHOT_STATE=compendium`. Tests: `tests/test_ad_meta.gd`.

## Save & Continue (AD-146)
- The run is saved only in the workshop (autosave on arrival, after buy/reroll and after an editor apply/close, and on Save & Quit from the pause menu).
- It lives in `run.json` (schema v1, written atomically, quarantined if corrupt). Title shows Continue first while it exists.
- It is deleted on leaving the workshop, on death or win, on retry or new seed, on abandon (Quit to Title) and whenever New Run starts.
- There is no resume into combat: a mid-combat quit leaves no save.
