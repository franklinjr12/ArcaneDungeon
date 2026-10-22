# ArcaneDungeon — M1 Magic Sandbox (TASK-011–025)

**Status:** Implemented and locally validated as a **PROPOSED FOR PROTOTYPE** configuration, not an owner-approved final ruleset. Gameplay code is separated from placeholders. The base visual art reference `docs/assets/art_style_reference.png` is intentionally unchanged; no art assets were generated.

## Launch

Open `project.godot` in Godot **4.7.2 stable**, GL Compatibility. From the launcher choose **Magic Sandbox**, or run:

```sh
godot --path . --scene res://scenes/sandbox.tscn
python scripts/validate_godot.py --godot godot
```

The Combat Arena is still the M0 placeholder until M2. The Sandbox is deliberately not a production player/movement controller.

## Sandbox controls

| Control | Action |
| --- | --- |
| Left mouse click in world | Cast equipped slot 1 at cursor direction |
| Right mouse click in world | Cast slot 2 |
| WASD / arrows | Reposition test caster (M1 debug only; M2 movement is separate) |
| Middle mouse click on dummy | Inspect target HP, hit count, status state IDs |
| Equip to slot 1/2 | Pick which independent spell slot subsequent sample selections replace |
| Eight formula buttons | Equip Fire Shot, Water Shot, Lightning Shot, Homing Fire, Split Fire → Lightning Burst, Pierce Water → Lightning Burst, Water Burst, Orbiting Fire |
| Reset | Restore seed, targets, initial slots, health, mana, counters, and trace |
| Seed+ | Increment seed used by next Reset |
| Mana | Refill to prototype max mana |
| Pause / Resume / Step | Halt ticks, or execute exactly one deterministic simulation tick |
| Dummy / Moving | Add stationary / moving dummy at last world cursor position |
| Stress | Try 10,000 effect reservations; cap at data-driven per-cast and global limits |
| Export | Save normalized trace to `user://magic_sandbox_trace.json` |

A root **Burst** is centered on the cursor (click the desired impact point). Projectiles originate at the caster and aim toward the cursor. Orbiting Orbs are anchored to the caster. Spell slots have independent cooldowns; swapping formulas cannot clear an existing cooldown. Mana regenerates on fixed simulation ticks. UI feedback displays costs, complexity, cooldown, damage-per-second over a three-second window, hits, active effect counts, state IDs and recent trace events.

## Reproduction scenarios

**Fire → Burning → periodic damage:** Equip Fire Shot to slot 1, left-click a dummy, watch its Burning status and HP. The first DOT tick occurs after the data-configured interval. Time advances only with simulation ticks.

**Water → Wet → Lightning arc:** Equip Water Burst on slot 1. Left-click the left dummy in the upper pair; after the short cooldown, click its neighboring dummy so **both** are Wet. Equip Lightning Shot on slot 1. Aim at the left Wet dummy and click; a derived arc damages the nearest other Wet enemy once. The two upper targets begin 140 units apart (within the configured arc range). No arc occurs when Wet is absent.

**Split + On Hit:** Equip Split Fire → Lightning Burst. Left-click toward a three-dummy formation; the three independently spawned projectiles each own an On Hit trigger. Each valid collision queues a Burst with its own Lightning essence. The mana cost is paid once.

**Pierce + On Hit:** Equip Pierce Water → Lightning Burst, align multiple targets, fire. The same projectile can hit configured distinct targets and invoke a separate Burst for each; it never directly re-hits the same target.

**Orbiting Fire:** Equip Orbiting Fire; cast; move the caster with WASD. The orb follows and applies bounded contact hits with a per-target rehit delay. It expires after its fixed lifetime. Orbiting Orbs cannot own On Hit in v1.

**Budgets:** Use Stress. The test emits an `events_per_cast` / `effects_per_cast` or relevant `budget_exceeded` trace instead of spawning 10,000 unbounded effects. Use Export to inspect trace JSON. The current stress preset exercises the effect-reservation cap.

## Source of truth / architecture

- `docs/architecture/magic_contract_v1.md`: technical shared contract, v1.2 M1-compatible.
- `magic/data/runes_v1.json`: stable IDs and typed, bounded default parameters.
- `magic/data/magic_balance_v1.json`: prototype damage channels, state interactions, durations, DOT, mana, arc, spawn/debug tuning. These are **not approved balancing decisions**.
- `magic/data/spell_limits_v1.json`: finite resource and event budgets, including a dedicated max-active-Orbs limit (prototype 6).
- `magic/data/sandbox_samples_v1.json`: eight example formulas using **formula JSON schema v1**.
- `combat/{health_component,status_component,magic_target,target_store,hit_payload,interaction_resolver}.gd`: shared team, HP, time-bound status, typed hit metadata, targeting and elemental effects, separate from visuals.
- `magic/runtime/{spell_runner,spell_loadout,projectile_effect,burst_effect,orb_effect}.gd`: fixed-tick runner, compiled loadouts, and three generic manifestations.
- `magic/runtime/magic_event_queue.gd`: existing M0 bounded event queue used by the M1 executor; event payloads use private event-ID contexts, never anonymous recursive calls.
- `ui/{sandbox_controller,sandbox_canvas}.gd`: input/debug UI + primitive drawing only; never authoritative simulation.
- `tests/{test_m1_magic,test_m1_edge_cases,test_m1_trace_golden,sandbox_ui_smoke}.gd`: deterministic tests + end-to-end scene smoke. `tests/fixtures/m1_runtime_traces_v1.json` is the reviewed Split/Pierce ancestry-and-event-order golden fixture; regenerate deliberately with `godot --headless --path . --script res://tests/m1_trace_golden_generator.gd`, then update the fixture only after reviewing the semantic differences.

## Rules and order

The tick phases are: cooldown and mana regeneration → deterministic movement of dummy targets and effects → queue hits with stable contact ordering → drain typed event queue (damage, statuses, On Hit child Bursts, bounded lightning arcs) → release completed Burst reservations/emit cleanup → Burning DOT / status expiration → visual lifetime cleanup. Damage on a tick resolves before DOT on that tick; a dead target does not receive postmortem DOT. A root Projectile triggering On Hit still executes its child Burst if its direct hit killed the victim.

**When two Wet candidates are equally close, the lowest stable target ID wins.** Statuses remain on living enemies until expiration or a resolver rule removes them; Water removes Burning and adds Wet. The lightning reaction is a single derived hit and never recurses or consumes Wet. Split children and Pierce contacts preserve root cast, formula and parent effect IDs.

The formula JSON remains **schema_version=1**. Compiler plans include resolved defaults and immutable copied rune snapshots; M1 adds a backward-compatible technical contract revision, not a new formula file schema. Modifier order remains stored but does not change runtime phase order in v1.

## Validation

Run the local wrapper above. It scans stdout/stderr for Godot parser/runtime errors, imports the project, navigates the launcher, exercises the interactive sandbox, runs all headless suites and **verifies a failing test exits nonzero**. A clean clone should work without pre-existing `.godot/` cache.

## Open owner decisions

Initial 10-rune roster and restricted On Hit grammar, two manual slots, all damage numbers, mana, cooldowns, event caps, status durations, arc radius, orbit/split behavior and editor-access rules are **PROPOSED**, not approved final game balance. More complex spell graphs, VR, detailed final art/VFX/audio, broad dungeon progression, M2 player combat and M3 workshop systems remain outside M1 scope.
