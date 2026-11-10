# AD-090 UI test matrix (baseline)

Baseline screenshots of every UI state at every target resolution, captured **before** the U-series UI fixes so later rows can be compared the same way.
Captured 2026-11-02 on hermes-vm (xvfb-run, software rendering).

## Run

```
bash tools/ui_matrix.sh [--godot PATH] [--out DIR] [--states "title combat"] [--sizes "1280x720 1920x1080"]
```

Full run = 104 shots, about 10 min. Each shot uses a fresh `XDG_DATA_HOME`, `timeout 60`, `xvfb-run -s "-screen 0 WxHx24"` and `godot --resolution WxH` (`window_set_size` does not resize under Xvfb). Output: `<WxH>/<state>.png` plus `sheets/<state>.png` contact sheets (ImageMagick montage). The script prints the actual PNG size of each shot and exits non-zero only if a shot is missing.

## States and env vars (debug builds only)

States: `title settings combat reward workshop_editor merchant pause summary`.
`AD_UI_SHOT_STATE`, `AD_UI_SHOT_OUT` (absolute PNG path; the game saves and quits), `AD_UI_SHOT_DELAY_MS` (default 800), `AD_UI_SHOT_FULLSCREEN=1`.

## Matrix

16:9 1280x720 (base), 1366x768, 1600x900, 1920x1080, 2560x1440, 3840x2160; 16:10 1280x800 (Steam Deck), 1920x1200; 21:9 2560x1080, 3440x1440; 4:3 1024x768; plus `fullscreen_1280x720_on_1920x1080/` and `resize_1280x720_to_1920x1080/`.

## Reading the baseline (important)

The shot is the game viewport image, not the window. The project keeps the 16:9 base aspect, so the identify sizes are:

- 16:9 sizes match the window exactly (1366x768 gives 1365x768, a rounding quirk).
- Non-16:9 windows produce a letterboxed 16:9 viewport: 1280x800 -> 1280x720, 1920x1200 -> 1920x1080, 2560x1080 -> 1920x1080, 3440x1440 -> 2560x1440, 1024x768 -> 1024x576. The black bars are not in the PNG.
- **Fullscreen** (the script prints a NOTE, not a WARN, because no window manager exists under Xvfb): with `AD_UI_SHOT_FULLSCREEN=1` on a 1920x1080 screen the saved image is still 1280x720, so the viewport was not enlarged; treat this set as showing the base-size layout (the fullscreen toggle did not change the rendered viewport under Xvfb).
- **Live resize**: `xdotool windowsize 1920 1080` after start **did take effect**; all `resize_*` PNGs are 1920x1080. They are taken after a 3000 ms delay.

All 8 sheets were inspected: real content (HUD, workshop, etc.), no black frames. No hook problems found.

## Bounds test

`tests/test_ad_ui_bounds.gd` checks at each matrix size that visible Controls are inside the viewport and interactive Controls do not overlap. It runs in `REPORT_ONLY` mode until U2 (failures are printed, not asserted). Look for lines starting `AD-090 UI-BOUNDS REPORT`; each lists one issue, and the final line gives the total. Run: `godot --headless --path . --script res://tests/run_tests.gd`.
Current result: `AD-090 UI-BOUNDS REPORT total issues: 0 (report_only=true)`. Note the headless test measures layout in the viewport, so letterbox and fullscreen behaviour above is not covered by it.

## AD-091 (post-fix matrix)

The PNGs and sheets in this folder were regenerated after AD-091 (`bash tools/ui_matrix.sh`, 104 shots, exit 0). Everything above describes the AD-090 baseline; the letterbox notes no longer apply.

- **Stretch:** `canvas_items` + aspect `expand`, base 1280x720. The logical viewport grows with the window aspect, so there are no letterbox bars. Every screen is built from anchors and containers.
- **Arena texel rule:** one art texel (2 world units) is 2 physical pixels, or 3 when at least 900x600 world units still fit at that scale (`RunController.arena_texel`). The arena canvas is scaled through its node `scale` so the zoom is a whole number of physical pixels. The dark frame appears only where the arena is smaller than the free area (3440x1440, 3840x2160).
- **Settings:** Window mode (windowed / fullscreen / borderless) and UI scale (90-150%), saved through SaveService. The HUD sits bottom-centre of the arena area with a 16 px safe margin.
- **Bounds test:** `tests/test_ad_ui_bounds.gd` now enforces (`REPORT_ONLY := false`): 0 issues across 11 sizes x 8 states.
- **Xvfb limits:** the fullscreen shots are still 1280x720 (no window manager, so fullscreen has no effect); the live resize to 1920x1080 does work.

## AD-092 (side menu redesign)

Regenerated 2026-11-03 (`bash tools/ui_matrix.sh`, 104 shots, 0 failed).

- **What changed:** the permanent run sidebar is gone and the arena takes the full width. The bottom-centre HUD (portrait, HP, MP, 4 slots with keys, mana cost and the dash) is the only HP/MP display. Top-left shows the objective (room name + goal) and coins, top-right the Pause button, with toasts at the top centre. The run summary and the reward cards are centred overlays. The pause menu now has Controls and Back to Menu. The dev overlay (F3) exists only in debug builds.
- **Release-like shots:** the screenshot hook sets `show_dev_tools = false`, so no dev overlay or dev text appears in any PNG in this folder. The workshop/merchant side panel remains the only scrolling panel besides the spell editor.
- **Bounds test:** `tests/test_ad_ui_bounds.gd` runs the run states with dev tools off and enforces at every size: no dev text, no ScrollContainer around the HUD/objective/reward/pause UI, HUD slot keys LMB/RMB/Q/E with slot 1 a locked Basic Bolt, loadout buttons numbered Slot 1-4, and text of at least 14 px at 1280x720. Result: `AD-090 UI-BOUNDS REPORT total issues: 0 (report_only=false)`; `validate_godot.py` exit 0.

## AD-093 (contextual panels)

Regenerated 2026-11-03 for reward, merchant, workshop_editor and summary (`bash tools/ui_matrix.sh --godot /usr/local/bin/godot --states "reward merchant workshop_editor summary"`; the run ended with `SUMMARY: ... 0 failed`).

- **Reward pick:** three side-by-side centred cards (art AD-038), keys 1-3 or a click.
- **Merchant:** a centred shop panel with card-framed items over the test range. It opens on workshop entry and from "Open merchant" in the side panel. The shop card art bakes in a RUNE label and price, so only its frame is used (`draw_center = false`).
- **Workshop editor:** docked to the right of the test range; the range is scaled to fit so no dummy is covered. Tip/notice toasts are hidden while it is open so they do not cover its heading. Toasts are now centred on the screen.
- **Run summary:** a centred modal with a Retry same seed / New seed / Title button row (buttons no longer wrap).
- **Floating text:** damage numbers, status labels and ARC! stack per actor without overlap; the DEFEATED banner is screen-centre text, not over the mage.
- **Tests:** the floating-text overlap test (6 damage numbers + a status label on one enemy) and the editor-vs-dummies check in `tests/test_ad_ui_bounds.gd`, plus per-panel coverage in `tests/run_ui_smoke.gd`.

## AD-152 (skin A front-end)

Regenerated 2026-11-06: `bash tools/ui_matrix.sh --godot /usr/local/bin/godot --states "title settings settings_video settings_controls settings_access pause"`; the run ended with `SUMMARY: 78 shots, 0 failed`. Pause was re-shot once after `i18n/strings_en.en.translation` was re-imported (the committed file lacked the new `pause.*` keys). Sheets are in `sheets/<state>.png`.

- **New shot states** (main menu debug hook): `title`, `settings` (audio tab), `settings_audio`, `settings_video`, `settings_controls`, `settings_access`, `compendium`. `pause` is a run state.
- **Mocks:** `mocks/ad_ui_screen_<menu|settings_audio|settings_video|settings_controls|settings_access|pause>_2x.png`. The 1280x720 shot is compared with the 2x mock; other sizes were checked for clipping and overlap.
- **Title:** AD-098 illustration, logo and menu panel match the mock layout (New Run, Compendium, Settings, Quit).
- **Settings (4 tabs):** same tab strip, section headers, rows, side info panel, light preview and footer buttons as the mocks.
- **Pause:** same panel, run-info line and button stack as the mock; backdrop dim is 50% per game-art (AD-159) rather than the mock's dither.

Known deviations:
- Engine default font instead of m5x7, so text is mixed case and sized differently from the mock.
- Settings widgets with no backing setting (frame limit, VSync, particles, glow, show FPS and similar) are drawn disabled.
- The UI scale slider sits in the mock's Resolution slot; a telemetry toggle is an extra row at the bottom of the accessibility Input section.
- Pause: Retry, Tips and Controls are removed (Controls moved to the Settings tab). Save+Quit is not visible in the shot (hidden in that state), leaving a gap above Abandon.
- Title: the water strip is a scripted AD-160 placeholder until the Cistern anchor is signed off.
- Title: Continue is hidden when there is no save, so the shot shows four buttons.
- Settings video shot: the light preview uses the in-game test sprite, not the mock's mage.

Review: game-design and game-art review is pending.

## AD-153 (skin A in-run)

Regenerated 2026-11-06: `bash tools/ui_matrix.sh --godot /usr/local/bin/godot --states "combat reward workshop_editor merchant summary summary_win loadout compendium compendium_reactions compendium_enemies compendium_artifacts"`; the run ended with `SUMMARY: 143 shots, 0 failed`. Sheets are in `sheets/<state>.png`. `tests/test_ad_ui_bounds.gd` enforces bounds for the new states at every size.

- **New shot states:** run hook `summary_win` (reached by the `_dev_advance` clear/reward/exit loop until `flow.state == "won"`, so it is deterministic); `loadout` already existed. Main-menu hook: `compendium_runes`, `compendium_reactions`, `compendium_enemies`, `compendium_artifacts` (via `select_tab`); `compendium` stays the default (runes) tab.
- **Mock to state** (`mocks/ad_ui_screen_<mock>_2x.png`): hud -> `combat`; reward -> `reward`; merchant -> `merchant`; editor -> `workshop_editor`; loadout -> `loadout`; summary_win -> `summary_win`; summary_lose -> `summary`; compendium_<tab> -> `compendium` (runes), `compendium_reactions`, `compendium_enemies`, `compendium_artifacts`.

Known deviations:
- Engine default font instead of m5x7, so text is mixed case and sized differently from the mocks.
- Placeholder copy: stand-in text and procedural rune/enemy/reaction art until the AD-159 finals are swapped in (layout unchanged).
- Summary: stats not tracked by the sim (damage dealt, compendium unlocks, milestone line) are replaced by tracked ones (spells used, coins held); the Final Loadout shows the 4 spell slots only (no artifact row) and spell names are clipped in their cells (for example "BASIC B"); the mock's right-hand hero art and the Compendium button are absent; the stage shows "2" rather than "2 / 2".
- Loadout: no artifact rarity cards (generic glyphs), upgrades use placeholder rows.
- Compendium: entries show only the name or `?`; per-entry stats and the milestone list are not tracked, so they are absent.
- Reward and merchant extras icons fall back to the MVP atlas when the AD-123 atlas lacks an icon.

Review: game-design and game-art review pending.

## AD-164

Sigilwright wordmark (AD-162) imported into the main menu `logo` widget (`assets/ui/logo/`), with an additive `LogoGlow`.
Command: `bash tools/ui_matrix.sh --godot /usr/local/bin/godot --states title` (2026-11-07). Result: 13 shots, 0 failed. The 1280x720 logo area (x320-960, y48-240) matches the AD-163 2x menu mock (letters, slab, sigil; no old-logo pixels). Menu mocks were replaced with the AD-163 FINAL re-renders.

## AD-193

New `combat_resonance` state: the combat HUD plus two reaction popups (`FREEZE +12`, `SHATTER +12`) right of the MP value text, fade-only.
Command: `bash tools/ui_matrix.sh --godot /usr/local/bin/godot --states "combat_resonance"` (2026-11-10). Result: `SUMMARY: 13 shots, 0 failed`. At 1280x720 the popup is readable and overlaps nothing.

## AD-195

New `reward_resonant` state (reward cards with the Resonant clear banner and a `+25 COINS` tag on a max-rarity card). The `summary` and `summary_win` shots now carry a centred combo line (`REACTIONS: 7   ELEMENTS: 3   SPELLS CRAFTED: 0`) in the free band under the loadout row.
Command: `bash tools/ui_matrix.sh --godot /usr/local/bin/godot --states "summary summary_win reward_resonant"` (2026-11-10). Result: `SUMMARY: 39 shots, 0 failed`. At 1280x720 the combo line is readable and overlaps nothing; the `RESONANT CLEAR: +1 RARITY` banner sits under the title and the tag fits its tooltip.
