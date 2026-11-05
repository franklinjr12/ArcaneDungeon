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

## Enemy framework v2 (AD-136)

Enemies are composed from a `behaviours` list in `combat/combat_tuning_v1.json` (`enemies.<kind>.behaviours`, objects `{"id": ..., params...}`); `combat/enemy_behaviours/registry.gd` validates ids and params (`Registry.validate_enemy`). Exactly one movement component and at most one attack component per enemy; any number of tick/modifier components. Component params override the enemy-level key of the same name; new damage/speed/telegraph keys follow `EnemyCombat._scale` (difficulty).

| id | role | params |
| --- | --- | --- |
| `chase` | movement | `preferred_range` |
| `keep_distance` | movement | `approach_margin`, `retreat_margin`, opt. `approach_weight`, `retreat_weight`, `strafe_factor`, `approach_without_sight` |
| `turret` | movement (never moves) | none |
| `melee_attack` / `ranged_attack` | attack | ranged: opt. `shots`, `spread_step_degrees` |
| `charge` | attack | `charge_speed`, `charge_ticks`, opt. `contact_padding`, `damage`, `channel` |
| `phase_walls` | modifier | opt. `ignore_sight` |
| `summon` | tick | `summon_kind`, `summon_cooldown_ticks`, `count`, `max_alive`, `summon_radius` |
| `shield_front` | tick | `front_damage_scale`, `front_arc_degrees` (half-angle around `heading`, which tracks the player) |
| `explode_on_death` | on death | `explode_radius`, `explode_damage`, opt. `explode_channel` |
| `support_buff` | tick | `buff_radius`, opt. `buff_damage_scale`, `buff_speed_scale` |

Summons are queued in `CombatSession.pending_spawns` and spawned right after the AI loop (so `enemies` is never mutated mid-iteration); summons record `summoner_id`. `shield_front` and `support_buff` damage scales multiply into `MagicTarget.damage_scale` (`shield_scale * buff_damage_scale`, recomputed every tick from 1.0); buffs also scale move speed and lapse the tick the supporter dies, freezes or the ally leaves range. A frozen shielded enemy keeps its last scale. `explode_on_death` is allowed to damage from a dead source (`damage_player(..., allow_dead_source)`) and posts a `*` feedback marker.

To add an enemy, copy an entry in `enemies`, edit its stats, and swap `behaviours`, e.g. a summoner: `[{"id":"chase"},{"id":"summon","summon_kind":"bone_thrall","summon_cooldown_ticks":240,"count":2,"max_alive":4,"summon_radius":60}]`. Then run `tests/test_ad_enemy_v2.gd`; golden traces for the three shipped enemies must stay unchanged (`tests/fixtures/ad_enemy_traces_v1.json`).

### Stage 1 enemies (AD-137, numbers PROPOSED)

Added to `enemies` in `combat/combat_tuning_v1.json` and to Ruins pool rooms p03-p10 (`world/data/rooms_ruins_v1.json`; spirit from p03, bloat from p06, shieldbearer from p07). Sprites are placeholders (`PLACEHOLDER_KIND` in `ui/pixel_art_renderer.gd` borrows bone_thrall/grave_hound art, tinted by the enemy `color`); telegraphs below are presentation only.

| enemy | telegraph | counter |
| --- | --- | --- |
| Ossuary shieldbearer (`turn_rate_degrees_per_tick` 2.5, `shield_front` x0.2 in a 70 deg half-arc) | pale arc on its facing side, hidden once the shield is broken | flank it (dash/circle faster than it turns) or Force knockback (`break_impulse_speed` 150) |
| Wailing spirit (`phase_walls` with `ignore_sight` false, so it passes walls but still needs line of sight; `intangible_cycle` 180/30/45; `channel_resistances` fire -0.5) | flickers during the 30-tick warning, semi-transparent while intangible (0 damage) | Fire deals 1.5x; hit it outside the intangible window |
| Corpse bloat (62-tick melee telegraph, `explode_on_death` radius 90, `death_puddle` Wet r90 for 300 ticks) | green radius ring while winding up or at <=30% HP; blue disc for the puddle | kill it from beyond 90 px; use the Wet puddle for Lightning |

Scripted counter scenarios live in `tests/test_ad_enemies_s1.gd`. `sfx.tele.<kind>` has no cue for these kinds yet; `AudioDirector` warns once and returns false for unknown cues (no crash).

### Stage 2 enemies part 1 (AD-139, numbers PROPOSED)

Components: `split_on_death` (`split_kind`, `count`, `split_radius`), `zone_cast` (`zone_radius`, `zone_duration_ticks`, `zone_interval_ticks`; drops a Wet zone), `water_lurk` (stays in water tiles, only acts from them) and `lunge` (`charge_speed`, `charge_ticks`, `contact_padding`). Enemies live in `combat/combat_tuning_v1.json`; tests in `tests/test_ad_enemies_s2.gd`.

| enemy | behaviour | counter |
| --- | --- | --- |
| Cistern slime (`split_on_death` into 2 `cistern_slimelet`, which do not split) | melee chaser | kill it with room to handle the extra bodies |
| Drowned acolyte (`zone_cast` Wet r80 for 240 ticks, telegraph 48) | keeps distance, casts where you stood | keep moving; use Wet for Lightning |
| Deep eel (`water_lurk` + `lunge`, ripple telegraph 30 ticks = 0.5 s, >= 0.5 s) | lurks in water, lunges out, never attacks without water | leave the lunge line when the ripple shows, punish after |

Cistern rooms (`world/data/rooms_cistern_v1.json`): slime from p02, acolyte from p03, eel from p05 (p05, p07, p09, p10, challenge; eel spawns are in shallow water the validator treats as walkable, since deep water is solid; slime/acolyte never in deep water). Placeholder sprites via `PLACEHOLDER_KIND`: slime/slimelet borrow bone_thrall, acolyte fallen_adept, eel grave_hound, tinted by `color`.

## Boundaries and owner decisions

The arena is *not* M3 room progression, boss design, loot, a spell editor, a production sprite pipeline or gamepad integration. Player motion, dodge timings, enemy archetypes/HP and attack damage, Burst range/LOS, fixed arena obstacles, accessible flash treatment, two loadout slots, initial seed, and encounter recipes are **PROPOSED FOR PROTOTYPE**, not locked design. A later human playtest should verify warning legibility, pacing, actual 60-FPS rendering, camera comfort and combat feel before treating M2 as polished.
