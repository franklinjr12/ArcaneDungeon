# Meta progression and Compendium (AD-145)

Light, persistent progression for the closed demo. Numbers marked **PROPOSED** are tunable in `world/data/meta_v1.json`.

## Profile schema v2
`user://profile.json` gains `meta.discovered`: a sorted list of unique ids per category (`runes`, `reactions`, `enemies`, `artifacts`). Code: `world/meta_progress.gd`, `SaveService.meta()`, `record_discoveries()`, `locked_runes()`, `locked_artifacts()`.

## Migration
A v1 profile loads with its stats intact and an empty `meta` block. A corrupt profile or an invalid `meta` block is quarantined and replaced with defaults (existing corrupt-profile handling).

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

## No stat power
Unlocks only widen which runes and artifacts can appear. Nothing changes HP, damage, mana or any other stat; a test asserts stats are untouched by milestones.

## Compendium
`ui/compendium_screen.gd`, opened from the main menu (`CompendiumButton`). Four sections shown as discovered/total, undiscovered entries show `???`, plus a Milestones list with progress and met/locked marks. Read-only; Back or `ui_cancel` returns to the title. Debug shot state: `AD_UI_SHOT_STATE=compendium`. Tests: `tests/test_ad_meta.gd`.
