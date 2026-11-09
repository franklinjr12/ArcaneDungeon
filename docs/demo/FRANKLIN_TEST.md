# Franklin demo test checklist

**Time budget (estimate):** non-combat sections 1, 2, 4, 6, 7 and 9 sum to about 20 min. Add the route median rounded up (31 min, from the AD-176 invulnerable route run) for about 51 min. This is an estimate, not a measurement, and it is above the 30-40 min target.

**Expected run length** (AD-176, simulation minutes; menus and reading excluded):

- Natural bot runs (weak, typical, skilled) all end in death, 0 of 60 won. Totals are 9.1-13.4 min. In AD-175, all of these runs died at the Undead Warden (`ruins_boss`).
- Invulnerable route bot takes 19.5-35.7 min for the whole route. 11 of 20 finished, in 30.2-35.7 min; 9 hit the 360 s room cap.
- The 30-40 min target is **not met**.
- Stage 2 sections (5 and 8) may be unreachable without surviving the Undead Warden: no bot won natural play in AD-175 or AD-176.

## Build and launch

Build and launch steps: [docs/demo/README.md](README.md). On the title screen, check that the build stamp matches the one you were given. The game shows as **ARCANE DUNGEON** (title string `menu.title`). Turn on **Local telemetry (opt-in)** first.

## Keys

Defaults. All are rebindable in Settings > Controls.

| Action | Default |
|---|---|
| Move | W A S D, or arrow keys |
| Dash | Space |
| Cast slot 1 / 2 | Left / right mouse button |
| Cast slot 3 / 4 | Q / E |
| Interact, exit door | F |
| Loadout view | Tab |
| Pause | Esc |
| Retry same seed | R |
| Reset test targets | T |
| Pick reward 1-9 | number keys 1-9 |

Fill the last column of each row with Pass, Fail, or a short Note.

## 1. Title, menus and settings (~4 min)



| # | Do | Expect | Pass / Fail / Note |
|---|---|---|---|
| 1 | Launch. Read the build stamp on the title screen. | Title shows ARCANE DUNGEON and the build stamp from the build you were given. |  |
| 2 | Press Esc/mouse through Settings tabs: Audio, Video, Controls, Accessibility. | All four tabs open and close; sliders respond. |  |
| 3 | Video: change Light quality (High / Low) and Frame limit. | Dropdown changes apply; Lighting help text appears. |  |
| 4 | Controls: rebind one key (e.g. dash), then try an already-used key. | `Press a key...` prompt; conflict panel `X is already used by Y. Swap or cancel?`. Reset keys restores defaults. |  |
| 5 | Accessibility: toggle the reduce-flash and reduce-shake options; turn on **Local telemetry (opt-in)**; click **Open log folder**. | Options persist after closing Settings. Log folder opens. |  |
| 6 | Open Compendium; click Runes, Reactions, Enemies, Artifacts. | Four tabs listed; entries show names, not raw keys. |  |
| 7 | Title -> New Run -> Sigil Desk, timed. | Menus take under 15 s. (There is no difficulty menu in the demo; difficulty is data-only.) |  |

## 2. Sigil Desk prelude (~4 min)

First run only; the desk lists 3 given runes: Lightning, Projectile, Split.

| # | Do | Expect | Pass / Fail / Note |
|---|---|---|---|
| 8 | Read the checklist: `Build slot N`, `Test-cast slot N on a dummy`, `Exit`. | Desk heading `Sigil Desk`; steps tick off as you do them. |  |
| 9 | Build slot 4 from the given runes. Stopwatch it. | Done in under 60 s; guided hints name the next rune. |  |
| 10 | Test-cast slot 4 on the dummy. | Spell fires and hits the dummy; a test-cast notice shows. |  |
| 11 | Walk into the right-hand door, or press F. | Run starts in Stage 1. |  |
| 12 | Start a second run (Retry same seed or New seed); find the desk again. | `Skip the desk` is offered and works. |  |

## 3. Stage 1: Ruins and Undead Warden (natural median ~11 min, see Expected run length)



| # | Do | Expect | Pass / Fail / Note |
|---|---|---|---|
| 13 | Clear the first combat room. | Doors open when the room is clear; reward cards appear. |  |
| 14 | Pick a reward with mouse click and with keys 1-3. | Rune or card is added to your pool/loadout; coins or duplicate-refund behave. |  |
| 15 | Clear 2-3 more rooms; try the optional side door if offered (`Enter the side door` / `Take the main path`). | Both choices work, no softlock. |  |
| 16 | Fight the **Undead Warden** boss. | Telegraphed wind-up before attacks; at half HP a faster second phase with radial shots. |  |
| 17 | Dash (Space) through a telegraph. | Dash dodges damage; no stuck states. |  |

## 4. Workshop and merchant (~4 min)



| # | Do | Expect | Pass / Fail / Note |
|---|---|---|---|
| 18 | Enter the workshop after the boss. | HP and mana restored; spell editor opens. |  |
| 19 | Make a legal edit (swap a rune in a slot) and confirm. | Edit accepted; loadout updates. |  |
| 20 | Make an illegal edit (e.g. an invalid rune order or too many runes). | Edit rejected with a reason shown; nothing changes. |  |
| 21 | Open the merchant (`Traders Guild Outpost`) and buy a rune or max-HP upgrade. | Coins go down by the price; item arrives. |  |
| 22 | Press **REROLL** once, then try again. | First reroll changes stock; second is blocked (`REROLLED`). |  |
| 23 | Check any artifact you hold, in the loadout (Tab) and Compendium > Artifacts. | Name and description show; effect works in play. |  |

## 5. Stage 2: Flooded Cistern (time: see Expected run length)



| # | Do | Expect | Pass / Fail / Note |
|---|---|---|---|
| 24 | Enter the Cistern. | New tiles and lighting; water tiles visible. |  |
| 25 | Walk on water, then cast Lightning near water. | Walking/spell behaviour changes on water (shock/wet reaction). |  |
| 26 | Cast Cold at a puddle; cast Fire at a crate or cobweb. | Puddle freezes into ice; crate/cobweb burns. Braziers glow. |  |
| 27 | Fight Drowned Acolyte, Cistern Slime (splits into Slimelets), Deep Eel. | Each enemy is distinct and has a readable telegraph. |  |
| 28 | Clear the Cistern rooms to the Drowned Archivist door. | No stuck rooms. |  |

## 6. New runes (~5 min)

Build each in the workshop, then cast on enemies/dummy. Check the visible effect.

| # | Do | Expect | Pass / Fail / Note |
|---|---|---|---|
| 29 | **Cold** (Cold + Projectile). | Blue shot; target slowed/chilled status. |  |
| 30 | **Force** (Force + Projectile or Burst). | Knockback or push on target. |  |
| 31 | **Beam** form. | Continuous line hits everything along it. |  |
| 32 | **Field** form. | Zone stays on the floor and hits those inside. |  |
| 33 | **Chain** mod (with Lightning). | Jumps to nearby enemies. |  |
| 34 | **Expand** mod. | Visibly larger area or radius. |  |
| 35 | **Rapid** mod. | Faster casting/projectile rate. |  |
| 36 | **On Kill** trigger. | Second effect fires when the first kills. |  |
| 37 | **On Expire** trigger. | Second effect fires when the first ends. |  |
| 38 | **Timer** trigger. | Second effect fires after a delay. |  |

## 7. Lighting and VFX (~2 min)



| # | Do | Expect | Pass / Fail / Note |
|---|---|---|---|
| 39 | Compare Settings > Video > Light quality High, Low and Lighting off (lighting hint says Off = low-end PCs). | Rooms get darker with High/Low; Off is bright and flat. Enemies and floor stay readable in all modes. |  |
| 40 | Cast with lighting on. | Spells glow and light nearby floor; no stutter you can feel. |  |

## 8. Final boss, summary, save and resume (time: see Expected run length)



| # | Do | Expect | Pass / Fail / Note |
|---|---|---|---|
| 41 | Fight the **Drowned Archivist**. | Phase cues are readable. |  |
| 42 | Win or die. Read the Run Summary. | `RUN COMPLETE` or `RUN OVER` with stage, rooms, time, kills, spells, coins, final loadout. |  |
| 43 | Use **Retry same seed**. | Same rooms and rewards as before. |  |
| 44 | Start **New seed**. | Different layout. |  |
| 45 | Mid-run: Esc -> **Save & Quit**, then Title -> **Continue**. | Run resumes where you left it. |  |
| 46 | Esc -> Settings, Loadout and Abandon. | Each opens; Abandon asks first. |  |

## 9. Send logs back (~1 min)



| # | Do | Expect | Pass / Fail / Note |
|---|---|---|---|
| 47 | Settings > Accessibility > **Open log folder**; collect every `session_*.json` and `crash_*.txt`. | Files exist (telemetry must have been on from the start). |  |

## Known issues (do not report)

From [docs/benchmarks/ad_demo_qa.md](../benchmarks/ad_demo_qa.md):

| # | Area | Symptom | Severity |
|---|---|---|---|
| 1 | perf (sim) | Sim p95 over the 4.0 ms budget in all 4 probed rooms on the QA host. | high on QA host |
| 2 | perf (sign-off) | 60 FPS sign-off on reference hardware (i5 / GTX 1660) pending. Your run helps here: note FPS if it dips. | high |
| 3 | perf (GPU) | GPU and draw cost not measured (headless QA). | medium |
| 4 | balance | Run length not met: natural bots never won (0/60 in AD-176; all died at 9-13 min). Invulnerable route runs took 19.5-35.7 min, with 9/20 timeouts at the room cap. | high for pacing |
| 5 | QA coverage | Natural smoke run by AD-176 on tuned data: 0/60 wins; route smoke 9/20 timeouts. Determinism not re-run. | low |
| 6 | tooling | Fresh checkout needs `godot --headless --path . --import` once before tests. | low |
| 7 | UI coverage | UI matrix has no Sigil Desk state; fullscreen untestable under Xvfb. Section 2 and the Video tab here cover it by hand. | low |
| 8 | perf (noise) | QA perf numbers were taken on a shared host. | low |

## Reporting

Send every `session_*.json` and `crash_*.txt` from the log folder, plus the failed check numbers and notes from this page. Nothing is uploaded automatically.

- Windows: `%APPDATA%\Godot\app_userdata\ArcaneDungeon\logs`
- Linux: `~/.local/share/godot/app_userdata/ArcaneDungeon/logs`
- Or Settings > Accessibility > **Open log folder**.
