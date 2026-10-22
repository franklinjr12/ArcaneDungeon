# ArcaneDungeon — M2 Combat (TASK-026–035)

**Status:** Implemented **PROPOSED FOR PROTOTYPE** playable arena, validated headlessly. No permanent combat, balance, input, final art, or accessibility decisions are being claimed.

## How to play

Open `project.godot` in Godot **4.7.2 stable** (GL Compatibility), select **Combat Arena** in the launcher, or execute `godot --path . res://scenes/arena.tscn`.

| Input | Combat action |
| --- | --- |
| WASD / arrows | 8-way deterministic movement |
| Mouse | Aim and select Burst impact point |
| Left mouse | Manually cast equipped slot 1 |
| Right mouse | Manually cast equipped slot 2 |
| Space | Directional dodge with invulnerability, recovery and cooldown |
| 1 / 2 / 3 | Single pursuer / mixed enemies / Wet–Lightning cluster |
| Tab | Cycle between starter build presets (restarts test scenario) |
| R | Retry same scenario/seed/loadout |
| P | Pause/resume |
| F3 | Debug range, geometry, attack state and hit intent |
| F4 | Disable optional bright damage flashes (symbol/text feedback remains) |

**Commands are collected by `ui/combat_arena_controller.gd` and processed by `combat/player_combat.gd`.** The latter does not access `Input`. The runner accepts a cast on the same simulation frame as a click. Paused, dead and modal contexts block commands. During dodge, casts are locked until recovery ends; no cancel exploit or wall tunneling.

The 1320×900 test arena uses a clamped, player-following 916×650 view, three handcrafted rectangular solid obstacles and six nominal spawn markers in a data file. Navigation selects deterministic visible corners around obstacles. This is a fixed test map, not procedural dungeon generation.

## Combat model and architecture

- `combat/combat_session.gd` wraps the existing `magic/runtime/spell_runner.gd` and **uses the same player/enemy `MagicTarget`, health, status, compiler, mana, projectiles, event queue and elemental resolver**. M2 does not implement a parallel player spell system.
- `combat/player_combat.gd` owns command acceptance, movement, dodge timing, cast lockout and camera-independent aim. `world/arena_geometry.gd` is the shared bounded collision and line-of-sight system; the projectile manifestation accepts optional solid walls while retaining its M1 default behavior. Continuous collision and substepping are used for fast movement.
- `combat/damage_event.gd` records enemy attack source/team/type/amount/ID/tick. Every melee hit or launched hostile projectile has a stable attack ID; duplicate hits with the same ID are rejected. Invulnerability is evaluated before `MagicTarget.receive_damage`. Friendly hits are rejected, armor/resistance and HP clamping remain in the shared health component.
- `combat/enemy_combat.gd` is one reusable idle → acquire → chase → windup → recover → chase (or dead) state machine, with a typed `AttackIntent`. Pursuer approaches and attacks in melee; Ranged backs off or approaches to maintain spacing and launches a line-of-sight-checked projectile; Flanker uses lateral motion and the same telegraphed ranged pipeline. Projectiles are blocked by walls and boundaries. The debug overlay exposes intents and states.
- `ui/combat_canvas.gd` draws **placeholder geometry** (characters, walls, statuses, hit markers, health bars, arc lines, warning circles and enemy projectiles). `ui/combat_arena_controller.gd` displays HP, mana, names, costs, cooldowns, dodge invulnerability and recovery, cast rejection reasons and text status/reaction notices. No final sprites, icons, VFX or audio were generated.
- **M2 prototype-only Burst restriction:** `max_burst_distance` limits player Burst targeting to a line-of-sight point within the configured range. The M1 sandbox remains unrestricted for experimentation. Players cannot cast through an occluding solid wall. Both `BURST_OCCLUDED` and `BURST_OUT_OF_RANGE` are surfaced as cast rejection reasons.

Restart creates a new `SpellRunner`, resets seed IDs/active effects, player HP/mana, cooldowns, enemy HP/AI, current attack ledger, statuses, active hostile shots, metric counters, and transient visual feedback. Death blocks inputs; each enemy death is emitted once.

## Tuning and acceptance tests

All new numeric tuning and scenario definitions are in **`combat/combat_tuning_v1.json`**, not hardcoded spell names or enemy subclass damage. The numbers were chosen for prototype readability, not player-tested balance. Experiment by editing *data constants only*, then rerun scenarios; check desired line of sight, telegraph timing and travel speed.

**Three fixed scenarios** are selectable in combat:

1. `single` — one pursuer for dodge, approach and range control;
2. `mixed` — pursuer + ranged attacker + flanker across obstacles;
3. `cluster` — close formation for repeated Wet → Lightning reaction opportunities.

**Repeatable seed:** `20261022`. **Baseline fixture:** `tests/fixtures/m2_baseline_v1.json` locks six deterministic combinations (3 scenarios × starter loadouts 0 and 2). The `tests/m2_baseline_driver.gd` helper plays with ordinary `CombatSession.issue` commands: no direct enemy damage, mana grants, invulnerability override or HP mutation. `tests/m2_baseline_probe.gd` prints per-run metrics: time to clear in fixed 60 Hz ticks, damage taken, player casts/dodges, reactions, HP, and **headless simulation throughput** (not a measured display FPS).

The first local fixture recorded:

| Scenario | Build | Clear (ticks) | Damage taken | Casts | Dodges | Reactions |
| --- | ---: | ---: | ---: | ---: | ---: | ---: |
| Single | 0 | 27 | 0 | 16 | 0 | 0 |
| Single | 2 | 29 | 0 | 14 | 0 | 0 |
| Mixed | 0 | 531 | 20 | 36 | 6 | 0 |
| Mixed | 2 | 1005 | 56 | 49 | 13 | 2 |
| Cluster | 0 | 406 | 0 | 32 | 7 | 0 |
| Cluster | 2 | 407 | 0 | 28 | 8 | 6 |

**Interpreting the baseline:** these results demonstrate repeatable beatability under one scripted, skilled input policy, not that a novice can clear these encounters easily or that attacks are universally avoidable. The single scenario is very short; enemy health/damage, Burst range, mana, cooldown, and windups clearly need human playtesting. The two tested loadouts are the first (Fire Shot + Water Burst) and third (Water Burst + Lightning Shot); the other preset is available in the interface but is not part of this six-case acceptance fixture.

## Validation

```powershell
cd C:\Repos\ArcaneDungeon
python scripts/validate_godot.py --godot "C:\Users\sa-su\Documents\Godot\Godot_console.exe"
```

The wrapper checks editor parser/import, scene navigation, M1 sandbox, M2 arena UI, deterministic regression suites (including M1 unchanged), baseline fixture, and intentional failure detection. Standalone:

```sh
godot --headless --path . --script res://tests/combat_ui_smoke.gd
godot --headless --path . --script res://tests/m2_baseline_probe.gd
```

## Boundaries and owner decisions

The arena is *not* M3 room progression, boss design, loot, a spell editor, a production sprite pipeline or gamepad integration. Player motion, dodge timings, enemy archetypes/HP and attack damage, Burst range/LOS, fixed arena obstacles, accessible flash treatment, two loadout slots, initial seed, and encounter recipes are **PROPOSED FOR PROTOTYPE**, not locked design. A later human playtest should verify warning legibility, pacing, actual 60-FPS rendering, camera comfort and combat feel before treating M2 as polished.
