# Menu audit (AD-205)

Status before = state before AD-205 (values: works / no effect / not applied / applies but not saved / disabled-unbacked / keyboard-only / mouse-only).
Root cause for the pause screens: `run_controller._input` marked every paused event handled, so all GUI mouse and keyboard input was dead there. Only Esc still worked.

## Pause menu

| control | expected effect | status before | fix |
|---|---|---|---|
| Resume | closes pause, resumes run | no effect (Esc worked) | GUI input no longer swallowed while paused |
| Loadout | opens loadout view | no effect; outside the cleared state it closed pause and opened nothing | works; hidden outside the cleared state |
| Controls | opens Settings > Controls | no effect | input unblocked |
| Settings | opens Settings screen | no effect | input unblocked |
| Save & Quit | saves, returns to title | no effect | input unblocked |
| Open Reports | opens reports folder | no effect | input unblocked; opener moved to `ui/os_shell.gd` |
| Abandon | asks to confirm abandoning the run | no effect | input unblocked |
| Confirm / Cancel | accept / dismiss the prompt | no effect | input unblocked |

## Title entry points

| control | expected effect | status before | fix |
|---|---|---|---|
| Settings | opens Settings | works | none |
| Controls | opens Settings > Controls | works | none |
| Quit | exits the game | works | none |

## Settings (reached from title and from pause)

From the title everything below worked, apart from the rows noted. From pause every control was "no effect" (see above).

| control | expected effect | status before | fix |
|---|---|---|---|
| Audio: master / music / SFX sliders | change volume immediately, persist | works (title); no effect (pause) | input unblocked |
| Audio: mute when unfocused | mute while window unfocused | disabled-unbacked | implemented, persisted |
| Audio: other mock widgets (spell sounds priority etc.) | n/a | disabled-unbacked | removed, see below |
| Video: fullscreen / window mode | apply immediately | works; borderless to windowed kept the full-screen size | window size restored |
| Video: VSync | toggle vsync | disabled-unbacked | implemented, persisted |
| Video: frame limit | cap FPS | disabled-unbacked | implemented, persisted |
| Video: lighting High/Low/Off, Show FPS | apply immediately | works (title); no effect (pause) | input unblocked |
| Video: UI scale | scales overlays | works for non-menu overlays | none |
| Video: particles, glow | n/a | disabled-unbacked | removed, see below |
| Controls: rebind buttons, conflict handling | rebind, resolve conflicts | works; no focus ring | focus ring added |
| Access: tips, reduce flash/shake | apply immediately | works (title) | input unblocked |
| Access: telemetry | opt-in local telemetry | not applied in-run until next run | applies when the pause menu closes |
| Access: colour-blind, text size, strong telegraphs, hold to cast, aim assist, visual sound cues | n/a | disabled-unbacked | removed, see below |
| Tabs | switch page | mouse-only (Tab key did not switch); no focus ring on active tab | Tab key switches tabs; focus ring added |
| Toggles, sliders, dropdowns | keyboard operable | keyboard path lacked focus ring | focus ring and vertical focus chains |
| Dropdown + Esc (from pause) | Esc closes the popup | Esc closed Settings instead | popup closes first |
| Defaults | reset values | works | covers new settings |
| Back / Apply | leave / commit | works (title) | none |

## Removed for Franklin

Removed because there is no backing feature, and building one is either larger than about 1 h or a design decision.

- spell sounds top priority
- particles
- glow
- colour-blind mode
- text size
- strong telegraphs
- hold to cast
- aim assist
- visual sound cues

## Not present / for Franklin to decide

- Pause has no Retry (same or new seed) button: AD-185 removed it and `test_ad_pause` asserts its absence. The retry hotkey remains.
- Pause has no Quit game: Quit is on the title; pause offers Abandon and Save & Quit.
- There is no enemy-SFX slider or separate bus.
- The Pause rebind row is intentionally locked to Esc (AD-152).
- The UI scale slider does not visibly change skin A menus or the HUD, because they refit to the window.

## PR notes: 2-minute manual check

1. Start a run and pause with Esc in a room. Click Resume with the mouse; the run continues.
2. Pause again and click Settings, then each tab (Audio, Video, Controls, Access), then Back.
3. On Audio, drag Master volume and hear the change.
4. On Video, switch Lighting High, Low, Off and see the room change. Toggle Show FPS.
5. On Controls, rebind Dash, go back, resume and use the new key to dash.
6. With the keyboard, open Settings and press Tab to cycle tabs. Check the focus ring is visible on each control.
7. Open a dropdown and press Esc: only the popup closes. Press Esc again: Settings closes. Once more: Resume.
8. Click Abandon, then Cancel, then Abandon and Confirm; check Save & Quit and Open Reports.
9. Turn on VSync, set a frame limit, then close the game.
10. Restart and reopen Settings from the title; the values you changed are still set.
