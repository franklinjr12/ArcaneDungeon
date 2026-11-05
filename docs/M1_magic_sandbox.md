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

## Cold / Force (AD-131, Demo M2)

Reactions are **state rules** keyed on the hit channel plus the target's current states, never on named spell pairs. Rules live in `magic/data/magic_balance_v1.json` under `reactions` (`chill_freeze_stacks`, `knockback_immune_tags`, `rules[]`); statuses under `statuses`, Force knockback under `channels.essence.force` and `combat`.

- **Cold** applies Chilled (stacks, slows movement by `move_scale`); 3 stacks become Frozen (`chill_freeze`). Cold on Wet freezes directly (`wet_cold_freeze`).
- **Force** pushes the target along the hit direction (physics impulse in the sim; bosses are immune). Force on Frozen shatters it: Frozen is removed, Brittle applied, bonus damage x1.5 (`frozen_force_shatter`).
- **Fire** on Chilled/Frozen thaws it without Burning and emits Steam, which blinds enemies within 120 units for a short time (`fire_thaw_steam`). Blinded ranged enemies do not start attacks; Frozen enemies skip their whole AI tick.
- **New samples:** `sample.cold_shot`, `sample.force_shot`, `sample.water_pierce_cold_trigger` (Piercing Water -> Cold burst).
- **Golden traces:** `tests/ad_cold_force_golden_generator.gd` (`godot --headless --path . --script res://tests/ad_cold_force_golden_generator.gd`) -> `tests/fixtures/ad_cold_force_traces_v1.json` (`chill_to_frozen`, `wet_cold_force_shatter`, `cold_fire_steam`); review before accepting changes.
- **PROPOSED tuning (not approved balance):** Chilled 180 ticks / 3 stacks / 0.6 move scale; Frozen 120 ticks; Brittle 150 ticks, x1.25 damage taken; Blinded 90 ticks; Steam radius 120; shatter bonus x1.5; knockback force 420.

## Beam and Field (AD-132, Demo M3)

- **Beam** (`form.beam`, params `beam_length`, `beam_width`, `tick_interval_ticks`, `mana_per_tick`, `lifetime_ticks`): a channelled line from the caster along the aim. It pulses every `tick_interval_ticks`, starting the first tick after the cast, and hits up to `max_targets_per_pulse` targets on the line. The up-front plan mana is paid on cast and `mana_per_tick` is paid per pulse; a beam that cannot pay ends early (cleanup reason `no_mana`). The line is clipped at the first `collision_walls` rect and at arena bounds, so targets behind a wall get no hits.
- **Field** (`form.field`, params `field_radius`, `field_duration_ticks`, plus the pulse interval): a ground zone applying its essence to targets inside the radius every interval. The centre is the explicit `target_point` (or aim x `cast_range`), clamped to `cast_range`, stopped at the first wall and kept inside bounds.
- **Limits** (`spell_limits_v1.json`): `max_active_beams` (1), `max_active_fields` (3), `max_targets_per_pulse` (6); overflow is logged as `budget_exceeded`.
- **API:** `try_cast(slot, origin, dir, target_point = null)`, `stop_channel()` ends active beams, `is_channelling()` is true while a beam lives. Beams and fields reject Pierce/Homing/Split.
- **Samples:** `sample.fire_beam`, `sample.lightning_beam`, `sample.cold_field`. Goldens: `tests/ad_forms_golden_generator.gd` -> `tests/fixtures/ad_forms_traces_v1.json` (`beam_line_pulses`, `beam_wall_stop`, `field_cold_freeze`); review before accepting changes.
- **Visuals:** the canvases draw beam lines and field circles from `sim.visuals` (no new art); visuals never affect sim timing.
- **Not approved balance:** all values are prototype tuning. **Follow-ups:** hold-to-channel input wiring and the AD-121 mage channel animation tag.

## Chain, Expand, Rapid (AD-133, Demo M4)

- **Params (PROPOSED, in `runes_v2.json`):** `mod.chain` `chain_count` 2 (1-4), `chain_radius` 160 (1-400); `mod.expand` `expand_area_scale` 1.5 (1-2.5), `expand_speed_scale` 0.7 (0.25-1); `mod.rapid` `rapid_cooldown_scale` 0.6 (0.2-1), `rapid_damage_scale` 0.7 (0.1-1).
- **Chain:** a hit jumps up to `chain_count` times to the nearest eligible target within `chain_radius` (ties broken by id). A target is a chain target at most once per root cast (no repeat), chained hits do not chain again or fire On Hit triggers, and jumps are capped by `max_chain_targets`. Each jump emits a `chain` trace record and a short arc visual.
- **Expand / Rapid:** compile-time param scaling per form, applied in fixed order Expand then Rapid. Expand enlarges area/length (burst radius, field radius, beam length, projectile/orb reach) and slows speed/pulse rate; Rapid shortens the slot cooldown and lowers damage. Results are clamped to the rune param ranges.
- **Order:** modifier order still has no runtime effect; the editor label reads "Modifiers (order has no effect)".
- **Compatibility:** all modifiers except Homing/Split/Pierce attach to any form (including Beam and Field).
- **Samples:** `sample.chain_bolt`, `sample.expand_burst`, `sample.rapid_beam`, `sample.chain_field`. Goldens: `tests/ad_modifiers_golden_generator.gd` -> `tests/fixtures/ad_modifiers_traces_v1.json` (`chain_bolt_jumps`, `expand_burst_reach`, `rapid_beam_cooldown`, `chain_field_no_repeat`); review before accepting changes.

## Triggers (AD-134, Demo M5) — all values and rules PROPOSED

- **On Kill** fires at the killed target. It fires only on direct, non-chained hits of the root effect, not on DOT, arc or chain kills.
- **On Expire** fires where a lasting effect ends, for any end reason. Beams use the beam end point.
- **Timer** fires every `interval_ticks` (30) while the effect lives.
- **Payload** is always a Burst without modifiers. Depth stays 1 (payload effects fire no triggers). Event, effect and depth budgets log `budget_exceeded`. Trigger trace records carry `reason` = trigger id.
- **Compatibility:** On Hit stays Projectile-only. On Expire and Timer need a lasting form (not Burst).
- **Samples:** `sample.kill_burst` (Fire projectile, On Kill → Lightning Burst), `sample.expire_bolt` (Water projectile, On Expire → Cold Burst), `sample.timer_field` (Fire field, Timer → Force Burst). Goldens: `godot --headless --path . --script res://tests/ad_triggers_golden_generator.gd` -> `tests/fixtures/ad_triggers_traces_v1.json` (`kill_burst_chain_kill`, `expire_bolt_open_space`, `timer_field_pulses`); review before accepting changes.

## Source of truth / architecture

- `docs/architecture/magic_contract_v1.md`: technical shared contract, v1.2 M1-compatible.
- `magic/data/runes_v2.json`: stable IDs and typed, bounded default parameters.
- `magic/data/magic_balance_v1.json`: prototype damage channels, state interactions, durations, DOT, mana, arc, spawn/debug tuning. These are **not approved balancing decisions**.
- `magic/data/spell_limits_v1.json`: finite resource and event budgets, including a dedicated max-active-Orbs limit (prototype 6).
- `magic/data/sandbox_samples_v1.json`: example formulas (eight M1 + three AD-131 Cold/Force + three AD-132 Beam/Field + four AD-133 modifier samples) using **formula JSON schema v1**.
- `combat/{health_component,status_component,magic_target,target_store,hit_payload,interaction_resolver}.gd`: shared team, HP, time-bound status, typed hit metadata, targeting and elemental effects, separate from visuals.
- `magic/runtime/{spell_runner,spell_loadout,projectile_effect,burst_effect,orb_effect}.gd`: fixed-tick runner, compiled loadouts, and three generic manifestations.
- `magic/runtime/magic_event_queue.gd`: existing M0 bounded event queue used by the M1 executor; event payloads use private event-ID contexts, never anonymous recursive calls.
- `ui/{sandbox_controller,sandbox_canvas}.gd`: input/debug UI + primitive drawing only; never authoritative simulation.
- `tests/{test_m1_magic,test_m1_edge_cases,test_m1_trace_golden,sandbox_ui_smoke}.gd`: deterministic tests + end-to-end scene smoke. `tests/fixtures/m1_runtime_traces_v1.json` is the reviewed Split/Pierce ancestry-and-event-order golden fixture; regenerate deliberately with `godot --headless --path . --script res://tests/m1_trace_golden_generator.gd`, then update the fixture only after reviewing the semantic differences.

## Rules and order

The tick phases are: cooldown and mana regeneration → deterministic movement of dummy targets and effects → queue hits with stable contact ordering → drain typed event queue (damage, statuses, On Hit child Bursts, bounded lightning arcs) → release completed Burst reservations/emit cleanup → Burning DOT / status expiration → visual lifetime cleanup. Damage on a tick resolves before DOT on that tick; a dead target does not receive postmortem DOT. A root Projectile triggering On Hit still executes its child Burst if its direct hit killed the victim.

**When two Wet candidates are equally close, the lowest stable target ID wins.** Statuses remain on living enemies until expiration or a resolver rule removes them; Water removes Burning and adds Wet. The lightning reaction is a single derived hit and never recurses or consumes Wet. Split children and Pierce contacts preserve root cast, formula and parent effect IDs.

The formula JSON was **schema_version=1** in M1; AD-129 bumped it to v2 (`SpellCodec.migrate` upgrades v1 formulas, no structural change; rune data now `runes_v2.json` with categories and param blocks). Compiler plans include resolved defaults and immutable copied rune snapshots; M1 adds a backward-compatible technical contract revision, not a new formula file schema. Modifier order remains stored but does not change runtime phase order in v1.

## Validation

Run the local wrapper above. It scans stdout/stderr for Godot parser/runtime errors, imports the project, navigates the launcher, exercises the interactive sandbox, runs all headless suites and **verifies a failing test exits nonzero**. A clean clone should work without pre-existing `.godot/` cache.

## Open owner decisions

Initial 10-rune roster and restricted On Hit grammar, two manual slots, all damage numbers, mana, cooldowns, event caps, status durations, arc radius, orbit/split behavior and editor-access rules are **PROPOSED**, not approved final game balance. More complex spell graphs, VR, detailed final art/VFX/audio, broad dungeon progression, M2 player combat and M3 workshop systems remain outside M1 scope.

## AD-135 rune pool and balance pass

All numbers below are **PROPOSED**, not approved balance.

- **Pool:** all 20 player runes (5 essences, 5 forms, 6 modifiers, 4 triggers; `essence.neutral` is built-in and never offered) are in `world/data/run_v2.json` `reward_pool`. Rarity tier per rune is `rune_rarity`; weights `rarity_weights` are common 6, uncommon 3, rare 1 (uncommon: cold, force, orb, beam, field, chain, expand, rapid, On Hit; rare: On Kill, On Expire, Timer). Reward cards never repeat a rune within one pick and are deterministic per run seed + room.
- **Merchant:** stocks exactly one not-yet-unlocked rune per visit, chosen by the same seeded weighted pick; nothing is stocked once all 20 are unlocked. Card name/description use `rune.<id>.name` / `rune.<id>.desc` tr keys.
- **Editor reasons:** invalid combinations (modifier/trigger/payload incompatibilities, over-complexity) show translated reasons from the validation issue codes.
- **Balance targets** (`magic/data/magic_balance_v1.json` `balance_targets`): `max_root_mana` 40, `max_total_mana` 40 (>= 3 casts from 120 mana), `max_cooldown_ticks` 30, `min_casts_from_full_mana` 3, `min_complexity_headroom_for_core_combo` 3 (1 form + 1 essence + 1 any-form modifier + 1 trigger with Burst payload, cap 12), `trigger_mana_premium_max` 22 (trigger + payload mana over the same spell without trigger).
- **Sweep result:** 4,200 legal formulas (5 essences x 5 forms x 0-1 modifier or any legal pair x no trigger or each trigger with each essence Burst payload): mana 6..40, cooldown 1..12, max complexity 9/12.
- **Cost changes** (only `mana_cost`; first sweep had combos at 41-42 mana):

| Rune | Mana before | Mana after | Reason |
|---|---|---|---|
| `form.field` | 10 | 9 | cheapest field+timer stacks exceeded 40 mana |
| `mod.expand` | 3 | 2 | slows Burst cooldown, so priced like Rapid/Pierce |
| `mod.chain` | 3 | 2 | stacked modifier pairs plus Timer payload exceeded 40 |

No cooldown or complexity values changed; no golden fixtures changed.
- **Rerun the sweep:** `godot --headless --path . --script res://tests/run_tests.gd` (the `_balance_sweep` section of `tests/test_ad_rune_pool.gd` prints an `AD-135 sweep:` summary line and lists any `target miss`).
