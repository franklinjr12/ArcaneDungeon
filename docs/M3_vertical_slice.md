# ArcaneDungeon — M3 Vertical Slice (TASK-036–048)

**Status:** Playable fixed-stage prototype implemented and validated using Godot 4.7.2 (GL Compatibility). **The GDD, magic formula v1, rune roster and visual reference remain unchanged.** Everything described as a design/tuning choice below is **PROPOSED FOR PROTOTYPE**, not owner-approved final behavior.

## Run the game

Open `project.godot` → **Start Run (M3)**. Direct scene path:

```powershell
cd C:\Repos\ArcaneDungeon
& "C:\Users\sa-su\Documents\Godot\Godot_console.exe" --path . res://scenes/run.tscn
```

Controls: **WASD/arrows** movement, **mouse** aim, **left/right click** manually cast, **Space** dodge, **E** attempt exit when close, **Q / T** open spell editor for slot 1/2 when allowed, **R** restart from the first room, **F2** toggle the experiment's edit policy, **F3** collision/telegraph debug. Equivalent sidebar buttons are provided. Spells and movement are blocked while editing.

Progression is a fixed, hand-authored route, not a procedural dungeon:

1. Stage 1 room 1: pursuer → select one rune or currency reward.
2. Room 2: pursuer/ranged wave, then a **delayed flanker wave** → reward.
3. Room 3: mixed cluster of three enemies → reward.
4. Mini-boss: alternates **telegraphed radial projectile burst** and **telegraphed targeted shot**, with a faster windup under half health. Boss awards configured currency automatically and opens the exit once defeated.
5. **Safe workshop**: merchant, transactional structured spell editor, and isolated practice range. Entering the range restores only **test** HP/mana; dungeon HP/currency are unaffected.
6. Stage 2 room 1: ranged + flanker, demonstrating persistence across the boss/workshop transition. The vertical slice ends after this room.

**Human demo / fallback build:** Begin with the default **Fire Shot (slot 1) + Water Burst (slot 2)**. This initial pair uses only already-unlocked runes, so every fresh run can cast both spells even if no new rune is picked up. Clear room 1, choose a rune reward, progress to the boss, and use **R** to restart cleanly if defeated. In the workshop, acquire another rune if affordable, open the editor with **Q**, adjust Essence/Manifestation/Modifiers, Apply, then click on a dummy to test. Exit the workshop and clear the first stage-two room. If a custom build becomes invalid or ineffective, choose **Reset draft** before applying or **Cancel** to restore the previous equipped formula. The original Fire Shot + Water Burst pair remains the reproducible fallback at the start of a new run.

In combat, an **EXIT LOCKED** marker appears while threats or scheduled waves remain; it turns **EXIT OPEN** after the encounter is truly clear. The player must reach the exit marker; the transition has a brief cosmetic fade. A reward marker appears after non-boss combat. Reward buttons choose one of the seeded options; selecting is optional, and the same room can never grant a second reward.

## Workshop

The shop lists at least one still-locked rune and a numerical **+25 maximum HP** upgrade, priced with data. Affordability is checked **before** any purchase; attempts to re-buy stock or spend too much cannot change currency. Purchases persist in `RunState`. The boss's prototype currency grant is configured in data, as are duplicate-rune fallback currency values.

The editor uses `SpellCompiler` and `SpellValidator` from M0/M1, and shows actual mana/complexity/cooldown and typed errors. Root **Essence** and **Manifestation** dropdowns, compatible **Modifier** checkboxes, and optional **On Hit → Burst** payload essence are provided. Locked options are visibly disabled. **Undo**, **Reset**, **Cancel**, **Apply** operate on isolated draft data; only valid Apply transactions replace a slot. Modified spells receive a distinct `custom.slot_1` or `custom.slot_2` ID and display name; v1 formula grammar is not changed.

The practice range uses a **separate SpellRunner** with the same magic plans/resolver as combat and the M1 sandbox. It includes six static and one moving dummy, **Reset**, **Refill test mana**, and **Prepare two Wet cluster targets** for experimenting with Lightning arcs. Its HUD shows hit counts, statuses, reactions, On Hit triggers, and effect budget warnings. Test casts never spend dungeon mana/currency or affect encounters. Editor Apply resets *only* the practice runtime and lets users immediately cast the new formula without restarting the run.

Editing access is a configurable experiment, not a final rule: `edit_policy = "workshop_only"` by default, or `"cleared_room"`. The F2/sidebar switch demonstrates both. Cleared-room editing uses exactly the same compiler/editor, but disables the merchant and range. During active combat, **both policies deny editing**. `RunState` tracks edit count, quick edit count, and time in the editor; anonymous telemetry/export is deferred to M4.

## Architecture and authority

- `world/data/vertical_slice_v1.json` — canonical proposed M3 sequence, wave timing, room markers, enemy cap, boss tuning, shop/reward policy, seed, edit policy, and workshop settings.
- `world/room_template.gd` (`Resource`) — validates room scenes, type, entrance/exit/reward and enemy spawns against shared M2 collision geometry.
- `world/encounter_director.gd` — schedules first/delayed second wave, prevents premature room clear, and emits one completion event.
- `world/run_state.gd` — versioned saveable run state. Stores only seed, sequence, HP/max HP, mana, currency, unlocked rune IDs, v1 formulas, collected/purchased IDs and edit metrics. **Never serializes** enemies, status instances, active spells, queues, bullets or scene references. Validate before accepting JSON-loaded save data; reject locked/invalid formulas.
- `world/run_flow.gd` — owns linear transitions, preserves RunState, reconstructs a clean M2 CombatSession per room, arbitrates door/reward/editor/shop/test requests and implements workshop isolation.
- `combat/boss_combat.gd` — one shared-target, phase-aware boss using the M2 hostile projectile/damage pipeline (no special elemental immunities).
- `world/reward_generator.gd` — seed+room-specific RNG, repeatable choice and one-time acquisition, duplicate fallback.
- `world/merchant.gd` — immutable-seeded stock decisions and guarded purchases.
- `magic/editor/spell_editor.gd` — transactional changes using the same M1 compiled spell format, legality checks, unlocks and budgets.
- `ui/run_controller.gd`, `ui/run_canvas.gd`, `scenes/run.tscn` — front end and placeholder-only visuals. The existing M1 sandbox and M2 standalone combat arena remain available from the launcher.

**No new art files, spell essence families, spell JSON schema or post-validation mechanics were introduced.** Only the provisional M2 combat scenario dictionary receives an `empty` encounter entry so the M3 encounter director can own spawning without any hidden M2 automatic enemies.

## Deterministic replay and acceptance

```powershell
python scripts/validate_godot.py --godot "C:\Users\sa-su\Documents\Godot\Godot_console.exe"
```

This validates the editor parser, launcher (Sandbox → Menu → Arena → Menu → Run), M1/M2/M3 scene smoke, all headless `tests/test_*.gd` suites including **real-command M3 combat**, and the nonzero intentional-failure probe. Key files:

- `tests/test_m3_core.gd` — room schema diagnostics, overlap/door locks, delayed waves, seeded rewards, duplicated grants, locked inventory, transaction cancel/apply, policy switching and save restore.
- `tests/test_m3_boss.gd` — strict radial/targeted telegraphs, alternation, second phase, boss death once, and JSON save round-trip.
- `tests/test_m3_vertical_slice.gd` — **20261022** full route to and through the stage-two room using **only normal player input commands for combat**; checks rune pickup, boss payout, merchant stock/affordability, an edited spell, isolated test range vs identical M1 trace, full RunState continuity, and death/restart clearing.
- `tests/run_ui_smoke.gd` — all scene, button, UI editor, merchant, range and stage-exit actions.
- `tests/m3_smoke_probe.gd` — short printable full-route diagnostic for reproducing real-command casts, clear times and persistent state; `tests/m3_run_driver.gd` is the deterministic replay input policy.
- `tests/m3_nav_probe.gd` — optional obstacle/exit movement diagnostic.

The first **seed 20261022** full replay observed: stage-1 rooms cleared at 27, 781 and 490 fixed ticks; boss defeated at 2606 ticks; stage-two room defeated at 983 ticks. It earned **trigger.on_hit**, **mod.split**, and **form.orb**, purchased **mod.pierce**, edited a Water Pierce Projectile, used it on workshop dummies, then entered and cleared stage two. These are deterministic scripted replay outcomes, **not human game-balance or rendered-FPS evidence**. At the end of that baseline the run had 119 HP and 55 currency after buying one rune. The documented route is illustrative; different seed/choices create different unlock histories.

## Open questions and limitations

- Final combat pace, health restoration between rooms, rune rewards/price policy, store stock, 2-slot spell cap, the boss phase thresholds, quick-edit access and dungeon topology all remain **PROPOSED**.
- `RunState.snapshot/restore` supports versioned serialization/deserialization; this M3 build keeps it in-memory during the continuous run. A production save/load UX and mid-combat checkpoint design are not included or claimed.
- There is no final art, sprite animation, audio, procedural map, extra biome, persistent account progression, controller mode or gameplay telemetry upload.
- M4 must conduct real player usability/balance testing and decide whether to keep or change the magic language and edit-access policy.
