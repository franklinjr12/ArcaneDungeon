# Friends Demo v1 checklist (for Franklin)

These 8 gates decide whether the demo is ready to hand to friends. Franklin decides each one. Nothing below is marked as passed for you. QA results: [docs/benchmarks/ad_demo_qa.md](../benchmarks/ad_demo_qa.md), section "Friends Demo v1". Build and launch steps: [docs/demo/README.md](README.md).

## Demo v1.1: what changed and what to try

This section covers your feedback of 2026-11-09. QA numbers: [docs/benchmarks/ad_demo_qa.md](../benchmarks/ad_demo_qa.md), section "Demo v1.1" (AD-204). The G1-G8 gates below still decide the release. The bot numbers in that section are INFO only. A human has to judge feel.

### Combos

**What changed**

- Mana regen drops from 1.8 to 0.6 per tick, so one spell spammed over and over runs dry in about 7 s (AD-193).
- A reaction gives 12 mana back and shows a Resonance popup. Reactions that count: Wet + Lightning arc, Wet + Cold freeze, Force on Frozen (shatter), Fire on Chilled/Frozen (thaw steam), Water on Burning (extinguish) (AD-193).
- Every enemy has a weakness (damage x1.5) or a resistance. The first time you meet one, a popup shows it. The Compendium Enemies page shows weak and resist icons. Damage numbers are coloured by tier (AD-194).
- Reward cards lean toward runes that complete a reaction (AD-195).
- Clear a room with 3 or more combo reactions for a Resonant clear: one rarity step up on the reward, or +25 coins. The summary screen shows combo stats (AD-195).

**What to try**

1. Hold one Fire spell until mana runs out. Then swap to a Water spell and hit a Burning enemy. Watch the mana refund and the Resonance popup.
2. Wet an enemy, then hit it with Lightning, then with Cold, then with Force. Count the reactions.
3. Clear a room with 3 reactions to get a Resonant clear. Check the banner and the reward card.
4. Fire at a Ghoul stalker (weak to Fire) and a Grave hound, and compare the damage number colours. Open the Compendium Enemies page for the weak and resist icons.

**Your verdict:** better / same / worse  Notes:

### Dodge

**What changed**

- Dashing through an attack at the right moment (inside the dash i-frames) is a perfect dodge. It refunds 15 mana, once per dash. The player flashes briefly (AD-196).
- Melee enemies lunge forward. Ranged bursts: the adept fires 3 shots and the hound 2. Enemy projectiles are 20-30% faster. Dash cooldown is 40 ticks (AD-196).
- Two new fast enemies: the Ghoul stalker (arc swipe, weak to Fire) and the Riptide leaper (leaps to a landing circle, weak to Cold). Both have a slow, clear telegraph (AD-197).

**What to try**

1. Dash through a Ghoul stalker's swipe at the last moment. Check the mana refund and the flash.
2. Watch the Riptide leaper's landing circle appear, then dash out of it. Attack it in its recovery.
3. Fight a Grave hound and dash through its 2-shot burst. You get 15 mana once, not per shot.

**Your verdict:** better / same / worse  Notes:

### Rooms

**What changed**

- Every Ruins room (AD-202) and Cistern room (AD-203) follows the room rules in `docs/rooms/ROOM_RULES.md`: 2-5 obstacles, at least 1 interactive prop, one named shape, spawns 160 px or more from the entrance, no dead corners.
- Interactive props are crates, cobwebs, braziers, urns, cracked walls and pillars, and puddles. The Cistern has pools and deep channels that force a detour.
- Run length: 3 combat rooms per stage and a Sigil Desk before each boss (AD-224). Route bots clear 12 rooms.

**What to try**

1. Burn a crate or cobweb with Fire. Break a cracked pillar or wall with Force.
2. In the Cistern, stand a Wet enemy in a pool and use Lightning, so the arc jumps to a second Wet target. Freeze a pool with Cold.
3. Enter 3 rooms in a row and note whether each looks different. Look for a corner where you get stuck.

**Your verdict:** better / same / worse  Notes:

### Bosses

**What changed**

- Bosses move, pick attacks from weighted pools, roar between phases, and can be punished after big attacks (stagger window, +50% damage). All of it is data (AD-198).
- Undead Warden (AD-199, 1800 HP, phases at 60% and 25%): melee combos, spear line, Grave rise summons. Phase 2: cracked pillars appear and the leap lands with a shockwave ring. Phase 3: faster windups and timed summons.
- Mini-bosses (AD-200): Elite fallen adept (blink, homing skulls, a decoy) and Elite storm crystal (electrifies water, small crystals). They sit in the optional challenge rooms.
- Drowned Archivist (AD-201, 2400 HP, phases at 66% and 33%): dives into pools and surfaces at another one with a ripple warning, throws book pages, sends a tide wave with a gap in phase 2, and uses lantern wisps and a storm pulse in phase 3.
- No boss HP was raised.

**What to try**

1. Break a cracked pillar with Force while the Warden stands within 190 px of it. It is stunned for 2 s (120 ticks).
2. Freeze a pool with Cold before the Archivist emerges there (phase 2). It surfaces stunned and takes +50% damage.
3. Dash through the Archivist's tide wave body, or walk through its gap.
4. In phase 3, shoot the 2 lantern wisps first. They shield the boss.
5. Note how long each boss fight took and whether it felt like an event.

**Your verdict:** better / same / worse  Notes:

### Audio

**What changed**

- Enemy and cast sounds are quieter and rate-limited. Settings > Audio has a new Enemy SFX volume slider (AD-191).
- `docs/demo/AUDIO_PRIORITY.md` lists the first 20 cues to replace with real files (AD-192).
- Audio prompts are committed, and the Ghoul stalker and Riptide leaper have telegraph cues (AD-226).
- All 79 cues are still placeholder or silent (`audio_check.py`, AD-204).

**What to try**

1. Fight a crowded room. Check that enemy attacks no longer drown out your casts.
2. Move the Enemy SFX slider and listen.
3. Pick the first rows of `AUDIO_PRIORITY.md` to record or generate next.

**Your verdict:** better / same / worse  Notes:

## G1 Feel

**Requirement:** rooms are quick and satisfying, no room runs over about 3 min, bosses feel like events and not sponges, and a winning run takes 18-25 min. The run length is a human guideline: read it from the run log and the summary timer, not from a bot number.

**What you do:**

1. Play 3 full runs.
2. After each run, note the summary timer, the longest room, and how each boss felt.
3. Open the run log JSON of each run (see Reporting) to read the room times.

**Evidence (from AD-204, Demo v1.1):** bot numbers are INFO only and do not decide G1. 20-seed smoke: 80 of 80 rows ok. Route bots (typical build) won 20 of 20 in 2.7-3.4 min. Natural bots won 1 of 60 (weak 1, typical 0, skilled 0) and mostly died between rooms 5 and 12. The longest room was 70.6 s, far under the 360 s cap. `test_ad_feel_bands.gd` ran green, so no HP sponges. The old rune and artifact table from before AD-224 is dropped. Bots are far below a human run length.

**Status:** Franklin to check.

**G1 result:** PASS / FAIL  Notes:

## G2 Onboarding

**Requirement:** a friend with no explanation moves, dashes, casts, reads a telegraph and crafts one spell within about 5 min.

**What you do:**

1. Give the build to one friend. Say nothing about the controls.
2. Watch and time them. Do not help.
3. Note which of the five steps they reached in 5 min: move, dash, cast, read a telegraph, craft one spell.

**Evidence:** `docs/demo/ONBOARDING.md` says this human test has not been run.

**Status:** Franklin to check.

**G2 result:** PASS / FAIL  Notes:

## G3 Stability

**Requirement:** no crash or softlock in the 20-seed smoke and in your runs. Workshop save and quit works.

**What you do:**

1. Play your runs from G1 and note any crash, freeze or stuck room.
2. In the workshop, press Esc > Save & Quit, then Title > Continue. The run must resume where you left it.

**Evidence:** 20-seed smoke (natural + route, AD-204): 80 of 80 rows ok, no crash, no script error, no room hit the 360 s cap. Test suite 24830 passed, 0 failed, 92 suites, including the resume suite (AD-204).

**Status:** partial. Smoke and the resume test are clean. Franklin to check your own runs and the workshop save and quit by hand.

**G3 result:** PASS / FAIL  Notes:

## G4 Performance

**Requirement:** 60 FPS at 1080p on the reference PC (i5 11th gen / GTX 1660) with Lighting High. Lighting Low is allowed as a documented fallback.

**What you do:**

1. Follow [PERF_TEST.md](PERF_TEST.md) on the reference PC.
2. Run `perf_test_high.bat`.
3. Run `perf_test_low.bat` only if High fails, and record that result as a retest, not a pass at High.
4. Also check the FPS overlay and the F8 report dialog by hand. The UI matrix cannot shoot them.

**Evidence:** only headless numbers from a shared 2-core VM exist. They are INFO and not valid for G4. The sim probe was over its budget in all 4 rooms there (AD-204), and the host was loaded by other jobs. Not run on the reference PC.

**Status:** Franklin to check.

**G4 result:** PASS / FAIL  Notes:

## G5 Build

**Requirement:** one script makes versioned Windows and Linux zips. The release build has no debug keys or menus. It launches without Godot.

**What you do:**

1. Optional: run `python3 scripts/export_demo.py --godot <godot>` yourself.
2. Copy `Sigilwright-0.1.0-demo-windows.zip` to a PC without Godot, unzip it and start the game.
3. Check that the title screen shows the build stamp and that no debug keys or menus work.

**Evidence:** `export_demo.py` exit 0. It made the 0.1.0-demo Windows and Linux zips again in AD-204. All 4 Linux zip checks passed, including the release probe for debug keys. The Windows zip was exported but not run.

**Status:** partial. Franklin to check that the Windows zip starts on a PC without Godot.

**G5 result:** PASS / FAIL  Notes:

## G6 Feedback

**Requirement:** a run log JSON per run, an F8 snapshot, a feedback form, and clear "send this folder" instructions.

**What you do:**

1. Finish one run.
2. Press F8 once, type one line and save.
3. Check that the run JSON and the report exist in the folders listed under Reporting.
4. Read [FEEDBACK_FORM.md](FEEDBACK_FORM.md) and the send instructions. Check that a friend could follow them.

**Evidence:** the run log and F8 snapshot test suites ran clean. The feedback form exists. The F8 dialog was not checked in a real build.

**Status:** partial. Franklin to check F8 in a real build and the instructions text.

**G6 result:** PASS / FAIL  Notes:

## G7 Assets

**Requirement:** the placeholder list is known. Your audio is in, or accepted as placeholder. Credits and licences are complete.

**What you do:**

1. Read [ASSET_STATUS.md](ASSET_STATUS.md) and [AUDIO_STATUS.md](AUDIO_STATUS.md).
2. Decide whether to ship placeholder audio.
3. Open Credits from the main menu and check it.
4. Find the licence of `art/export/fnt/arc_fnt_digits_3x5.png` and record it. It is flagged because none is recorded.

**Evidence:** 393 art files: 390 placeholder, 3 third-party, 1 flagged (the digits font above). Audio: 79 of 79 cues are placeholder or silent (AD-204). The credits screen is built from `game/data/credits_v1.json` and is in the UI matrix.

**Status:** partial. Licences are not complete until the font licence is found. Franklin to check that and to accept placeholder audio.

**G7 result:** PASS / FAIL  Notes:

## G8 Known issues

**Requirement:** a known issues list ships in the friends package.

**What you do:**

1. Read the KNOWN ISSUES section of `README_FRIENDS.txt` inside the zip.
2. Read [KNOWN_ISSUES.md](KNOWN_ISSUES.md).
3. Decide whether `KNOWN_ISSUES.md` must also ship. `scripts/export_demo.py` currently bundles only README_FRIENDS.md and FEEDBACK_FORM.md.

**Evidence:** the README KNOWN ISSUES section ships in the zip. `KNOWN_ISSUES.md` exists in the repo but is not bundled.

**Status:** partial. Franklin to check that the README list is enough, or order `KNOWN_ISSUES.md` bundled.

**G8 result:** PASS / FAIL  Notes:

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
| Send a report | F8 |

## Detailed walkthrough (supports G1-G3, G6)

Build and launch: [README.md](README.md). On the title screen, check that the build stamp matches the one you were given. The game title shows SIGILWRIGHT (string `menu.title`). Turn on **Local telemetry (opt-in)** first. Known problems you do not need to report: [KNOWN_ISSUES.md](KNOWN_ISSUES.md).

Fill the last column of each row with Pass, Fail, or a short Note. Stage 2 sections (5 and 8) need you to survive the Undead Warden.

### 1. Title, menus and settings (~4 min)



| # | Do | Expect | Pass / Fail / Note |
|---|---|---|---|
| 1 | Launch. Read the build stamp on the title screen. | Title shows SIGILWRIGHT and the build stamp from the build you were given. |  |
| 2 | Press Esc/mouse through Settings tabs: Audio, Video, Controls, Accessibility. | All four tabs open and close; sliders respond. |  |
| 3 | Video: change Light quality (High / Low) and Frame limit. | Dropdown changes apply; Lighting help text appears. |  |
| 4 | Controls: rebind one key (e.g. dash), then try an already-used key. | `Press a key...` prompt; conflict panel `X is already used by Y. Swap or cancel?`. Reset keys restores defaults. |  |
| 5 | Accessibility: toggle the reduce-flash and reduce-shake options; turn on **Local telemetry (opt-in)**; click **Open log folder**. | Options persist after closing Settings. Log folder opens. |  |
| 6 | Open Compendium; click Runes, Reactions, Enemies, Artifacts. | Four tabs listed; entries show names, not raw keys. |  |
| 7 | Title -> New Run -> Sigil Desk, timed. | Menus take under 15 s. (There is no difficulty menu in the demo; difficulty is data-only.) |  |

### 2. Sigil Desk prelude (~4 min)

First run only; the desk lists 3 given runes: Lightning, Projectile, Split.

| # | Do | Expect | Pass / Fail / Note |
|---|---|---|---|
| 8 | Read the checklist: `Build slot N`, `Test-cast slot N on a dummy`, `Exit`. | Desk heading `Sigil Desk`; steps tick off as you do them. |  |
| 9 | Build slot 4 from the given runes. Stopwatch it. | Done in under 60 s; guided hints name the next rune. |  |
| 10 | Test-cast slot 4 on the dummy. | Spell fires and hits the dummy; a test-cast notice shows. |  |
| 11 | Walk into the right-hand door, or press F. | Run starts in Stage 1. |  |
| 12 | Start a second run (Retry same seed or New seed); find the desk again. | `Skip the desk` is offered and works. |  |

### 3. Stage 1: Ruins and Undead Warden



| # | Do | Expect | Pass / Fail / Note |
|---|---|---|---|
| 13 | Clear the first combat room. | Doors open when the room is clear; reward cards appear. |  |
| 14 | Pick a reward with mouse click and with keys 1-3. | Rune or card is added to your pool/loadout; coins or duplicate-refund behave. |  |
| 15 | Clear the remaining combat rooms (3 per stage), then try the optional door (`Enter the side door` / `Take the main path`). | Both choices work, no softlock. |  |

### 4. Workshop and merchant (~4 min)



| # | Do | Expect | Pass / Fail / Note |
|---|---|---|---|
| 18 | The Sigil Desk opens after the optional room, right before the boss. | Mana refilled, HP carried over, editor opens. |  |
| 19 | Make a legal edit (swap a rune in a slot) and confirm. | Edit accepted; loadout updates. |  |
| 20 | Make an illegal edit (e.g. an invalid rune order or too many runes). | Edit rejected with a reason shown; nothing changes. |  |
| 21 | Open the merchant (`Traders Guild Outpost`) and buy a rune or max-HP upgrade. | Coins go down by the price; item arrives. The first desk comes before any boss coins, so buying is mainly possible at the second desk after the 95 boss coins. |  |
| 22 | Press **REROLL** once, then try again. | First reroll changes stock; second is blocked (`REROLLED`). |  |
| 23 | Check any artifact you hold, in the loadout (Tab) and Compendium > Artifacts. | Name and description show; effect works in play. |  |
| 16 | Fight the **Undead Warden** boss. | Telegraphed wind-up before attacks; at half HP a faster second phase with radial shots. |  |
| 17 | Dash (Space) through a telegraph. | Dash dodges damage; no stuck states. |  |

### 5. Stage 2: Flooded Cistern



| # | Do | Expect | Pass / Fail / Note |
|---|---|---|---|
| 24 | Enter the Cistern. | New tiles and lighting; water tiles visible. |  |
| 25 | Walk on water, then cast Lightning near water. | Walking/spell behaviour changes on water (shock/wet reaction). |  |
| 26 | Cast Cold at a puddle; cast Fire at a crate or cobweb. | Puddle freezes into ice; crate/cobweb burns. Braziers glow. |  |
| 27 | Fight Drowned Acolyte, Cistern Slime (splits into Slimelets), Deep Eel. | Each enemy is distinct and has a readable telegraph. |  |
| 28 | Clear the Cistern rooms, then the second Sigil Desk, then the Drowned Archivist door. | No stuck rooms. |  |

### 6. New runes (~5 min)

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

### 7. Lighting and VFX (~2 min)



| # | Do | Expect | Pass / Fail / Note |
|---|---|---|---|
| 39 | Compare Settings > Video > Light quality High, Low and Lighting off (lighting hint says Off = low-end PCs). | Rooms get darker with High/Low; Off is bright and flat. Enemies and floor stay readable in all modes. |  |
| 40 | Cast with lighting on. | Spells glow and light nearby floor; no stutter you can feel. |  |

### 8. Final boss, summary, save and resume



| # | Do | Expect | Pass / Fail / Note |
|---|---|---|---|
| 41 | Fight the **Drowned Archivist**. | Phase cues are readable. |  |
| 42 | Win or die. Read the Run Summary. | `RUN COMPLETE` or `RUN OVER` with stage, rooms, time, kills, spells, coins, final loadout. |  |
| 43 | Use **Retry same seed**. | Same rooms and rewards as before. |  |
| 44 | Start **New seed**. | Different layout. |  |
| 45 | Mid-run: Esc -> **Save & Quit**, then Title -> **Continue**. | Run resumes where you left it. |  |
| 46 | Esc -> Settings, Loadout and Abandon. | Each opens; Abandon asks first. |  |

### 9. Send logs back (~1 min)



| # | Do | Expect | Pass / Fail / Note |
|---|---|---|---|
| 47 | Settings > Accessibility > **Open log folder**; collect every `session_*.json` and `crash_*.txt`. | Files exist (telemetry must have been on from the start). |  |

## Reporting

Send the folders below, plus the gate results and the failed check numbers and notes from this page. Nothing is uploaded automatically.

Folder: `%APPDATA%\Godot\app_userdata\Sigilwright\` (Linux: `~/.local/share/godot/app_userdata/Sigilwright/`)

- `logs`: `session_*.json` and `crash_*.txt`, only with telemetry on.
- `runs`: one JSON per run.
- `reports`: F8 reports.
- `perf`: perf run JSON.
