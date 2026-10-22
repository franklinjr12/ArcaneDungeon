# ArcaneDungeon — Magic Contract v1.4 (M0–M3)

**Contract version:** 1.4, extended during TASK-036–048; formula JSON schema remains version 1. **Status:** provisional prototype implementation contract; does not supersede owner decisions in `docs/Game Design & Project Reference.md`.

## Authority and change control

The living ArcaneDungeon GDD (local copy: `docs/Game Design & Project Reference.md`) is the **design authority**. `docs/backlog_v1.md` is the M0 implementation proposal; this document is the single shared technical contract for prototype grammar and APIs. Status labels: **DECIDED**, **DIRECTION**, **PROPOSED FOR PROTOTYPE**, **OPEN**, **OUT OF SCOPE**. Never silently upgrade the latter labels to permanent requirements.

Change control: modifying the schema, enum meanings, event execution phases or any public shared API requires (1) a version bump and explicit change entry here, (2) new or updated codec migration and golden fixtures, (3) golden trace regression tests, (4) owner approval if design semantics change. A patch to tuning values alone updates data/revision and golden cost fixtures, not formula schema.

## Data schemas

- `RuneDefinition` (Resource, read-only snapshot): `id`, `category` (essence/form/modifier/trigger), `schema_version=1`, `params` typed parameter descriptions, `compatibility_tags`, `complexity_weight`, `mana_cost`, `cooldown_ticks`, `description`, `display_key`. Stable string IDs, no translation or filename identity. Data is loaded centrally from `magic/data/runes_v1.json`; invalid or duplicate IDs reject the whole registry load.
- `EffectSpec`: `essence_id` (string, required), `manifestation_id` (string, required), `modifier_ids` (ordered, unique array of string IDs), `params` (typed primitive map).
- `SpellFormula`: `schema_version=1`, `formula_id`, `display_name`, `root:EffectSpec`, optional `on_hit:{trigger_id:"trigger.on_hit",payload:EffectSpec}`. Encoded as schema-versioned JSON containing **only** whitelisted stable IDs and primitive parameters; reject unknown fields/versions before compile. No game instance IDs, script paths, code or executable resources.
- `CompiledSpell`: immutable-to-caller snapshot owned by compiler/cache. Contents: source formula ID, cost/complexity/cooldown, resolved root operation, explicit optional trigger payload, fixed runtime phases. Reading a plan returns a deep copy; editing source never changes an in-flight plan.

### Legality and diagnostics

- Root manifestation: Projectile, Burst or Orbiting Orb. Three prototype essences: Fire, Water, Lightning.
- Homing, Split and Pierce: Projectile roots only. Duplicate modifiers rejected; stored modifier ordering is preserved for serialization, but **v1 fixed runtime phases ignore modifier list order**.
- On Hit: Projectile root only, requires explicit payload; payload is Burst with independent essence, no modifier or nested trigger. Every projectile instance owns the compiled trigger; Split children each trigger independently; Pierce can trigger once on each distinct enemy hit up to its cap. Root and payload costs paid together **once** at initial manual cast, never on trigger; a triggered Burst may hit the original target separately. No recursive child trigger in v1.
- Invalid formula: reject with stable `{code,path,message}` issues; no mana deducted, no effect spawned and no compiled plan returned. Use same validator for equip/editor/compiler. Locked or unknown IDs reject, as do illegal attachments and over-complex formulas.

## Event, simulation and targeting rules

Common target: stable runtime ID, caster/team ID, HP, resistance tags and StatusComponent. Friendly fire off in v1. All effects carry `cast_id,root_cast_id,caster_id,team_id,formula_id,parent_effect_id,effect_sequence`. Target selection by distance then ID on ties. Use fixed-tick simulation, seeded RNG and monotonic stable event IDs.

Phases are fixed: **request cast → check compiled formula/slot/mana/cooldown → spend mana once → spawn root → movement/collision → eligible hit → damage/status resolution → enqueue typed triggers and reactions → ordered queue drain → spawn payload → cleanup**. Never perform recursive casts from collision callbacks or alter compiled plans mid-cast.

Elemental semantic states: Fire causes damage + Burning; Water causes damage + Wet and extinguishes Burning; Lightning causes damage + Charged; Lightning striking Wet may arc once to nearest *other* Wet target (distance then ID), no recursion or Wet consumption. Burning ticks at fixed simulation intervals. Damage/state logic belongs in shared resolvers; rendering, sounds and sprites must not change simulation.

`MagicEvent`: typed event with `event_id,sequence,cast_id,root_cast_id,formula_id,parent_effect_id,source_id,target_id,position,type,depth`, carried through bounded FIFO-by-sequence queue. `SpellLimits` config: complexity, event depth, events per root cast, spawned effects per root cast, global active effects, max lifetime, max chain targets, per-target rehit ticks. On any budget breach, drop extra work, append trace event `budget_exceeded`, remain responsive.

## Shared interfaces / ownership

| API | Owner / contract |
| --- | --- |
| `RuneRegistry.get_rune(id)` | M0 registry, returns separate defensive-copy RuneDefinition or null. `get_by_id` aliases it; native Godot `Object.get` cannot safely be overridden. |
| `SpellCodec.encode/decode` | Strict JSON v1, error objects with code/path/message; never deserialize scripts |
| `SpellValidator.validate(formula,unlocked_rune_ids)` | One legality implementation returning `{ok,issues}` |
| `SpellCompiler.compile(formula,unlocked_rune_ids)` | Validated cached `CompiledSpell` or issues, immutable snapshot |
| `SpellRunner.try_cast(slot_index,origin,direction)` | **Implemented M1**. Deterministic manual cast with `{accepted,reason,cast_id}`; cast actor, seed, and state are injected via runner instance, not call parameters. |
| `SimulationClock` | Fixed ticks, run-seeded RNG, monotonic ID assignment; determinism without rendering |
| `MagicEventQueue.push(event),drain(budget)` | Ordered typed events, no reentrant drain, enforced limits |
| `InteractionResolver.resolve(payload,target,target_store,tick)` | **Implemented M1**. Shared channel damage, status changes and deferred one-arc reaction request; no renderer dependency. |
| `RunState.snapshot(), restore(data,registry,max_rooms)` | **M3 implemented:** `{schema_version,seed,sequence_index,currency,unlocked,formulas,hp,max_hp,mana,collected,purchases,edit_seconds,edit_count,quick_edit_count}`. Only run-owned data; no runtime entities. Reject invalid schema or locked formula before applying. |
| `DebugTrace` | Opt-in trace, normalized JSON and filters; disabled instrumentation cannot change outcomes |

Use `magic/data/` for definitions, `magic/compile/` for parser/validator/compiler, `magic/runtime/` for event machinery, `game/core/` for clock and shared logging, `debug/` for traces, `tests/` for headless suites and golden fixtures. M1 combat must not duplicate M0 compiler/registry/queue.

## Provisional tuning — NOT owner-approved

These numeric settings are prototype knobs and must live in `magic/data/` (or explicit versioned configuration), **not** in named spell classes: rune mana/complexity/cooldown weights, max formula complexity, queue budgets, event depth, effect counts, chain length, lifetimes, rehit cooldowns. Changing any number is a balance experiment, not an approved product decision. Changes should note observed tests and adjust golden fixtures.

## Unresolved decisions

| Decision | Current stance | Owner approval | Next gate |
| --- | --- | --- | --- |
| Spell grammar and reordering semantics | PROPOSED: fixed v1 phases; preserve list order | Pending | Before expansion beyond M0 |
| Number of manual slots | PROPOSED: 2 keyboard/mouse | Pending | M1 |
| Godot 4.x minor and renderer | M0 environment-tested: 4.7.2 stable, GL Compatibility | Pending permanent approval | TASK-001 |
| Initial 10-rune roster | PROPOSED: 3/3/3/1 | Pending | M1 |
| Cost, cooldown, complexity and budgets | PROPOSED: data-driven values, not production balance | Pending | M1 |
| On Hit payload restriction and ownership | PROPOSED: one Burst child, no recursive triggers | Pending | M1 |
| Run-owned rune reuse/knowledge | PROPOSED: reusable unlocks | Pending | M3 |
| Between-room editing access | OPEN: workshop-only vs quick edit | Pending | TASK-047 |
| Reference performance hardware | OPEN | Pending | M4 |
| First playtest stage count | PROPOSED: 3 combat rooms + boss + workshop | Pending | M3 |
| Controller support, progression, branching graph | OPEN / POST | Pending | M4 go/no-go |

## Contract change log

- **v1.0 / TASK-003:** Initial M0 contract; all source-derived proposed rules retain proposal status. No owner-approved migrations yet.
- **M0 implementation note:** The published backlog uses `RuneRegistry.get(id)` as conceptual syntax. Actual Godot API is `get_rune(id)` (and `get_by_id(id)`) because `Object.get` is a native method and overriding it triggers a parse warning/error. This is a compatibility naming adaptation, not a spell-schema change. Golden legal/invalid/budget traces are synthetic contract fixtures until the TASK-011–025 runtime exists.

## M1 runtime extension — contract revision 1.1 (TASK-011–025)

- This technical contract revision is **backward compatible** with formula JSON schema v1. New runtime tunables are optional, typed rune parameter defaults stored in `magic/data/runes_v1.json`, resolved by `SpellCompiler` into detached plan snapshots. No formula migration is required. Changing formula schema still requires migration, new fixtures and owner approval for semantics.
- `MagicTarget`: stable `id`, `team`, `position`, `radius`, `tags`, `health`, `status`, `removed` and optional motion. `TargetStore.query(center,radius,attacker_team,exclude_ids,status_id,tick)` filters dead/removed/friendly and sorts by squared distance, then stable ID. `HealthComponent.damage` applies armor and channel resistance before HP clamp.
- `InteractionResolver.resolve(payload,target,store,tick)` interprets essence IDs using `magic/data/magic_balance_v1.json` channels, independent of manifestation classes. Returns direct damage, status changes and at most one deferred arc request. `StatusComponent.tick` yields deterministic expiration/DOT events; direct hit and On Hit queue handling finish before DOT at the same tick. DOT stops at death.
- `SpellRunner` owns the simulation clock, event queue, target store, resolver, two-slot loadout, active manifestations, trace and sandbox tuning. Input/UI calls `try_cast(slot, origin, direction)`; the only effect of invalid/out-of-mana/on-cooldown calls is a logged rejection. Valid casts reserve a root effect, deduct mana **once**, and spawn the root. Trigger Burst payloads are separately reserved and never deduct mana. Each Split child is separately budgeted. A separately configured `max_active_orbs` prevents unlimited simultaneous orbiting effects, in addition to global/per-cast effect caps. Every resolved hit uses a validated `HitPayload` with essence/channel, base damage, source/ancestry and knockback metadata; physical knockback is deferred to M2. Status refresh is data-driven (`replace_duration`, `extend_duration`, `keep_duration`). No collision callback performs nested casts.
- `ProjectileEffect`: swept segment/circle collision, stable ordered contacts, finite lifetime/wall bounds; `mod.homing` uses nearest eligible target and turn-rate cap, `mod.split` uses symmetric offsets, `mod.pierce` uses a per-projectile distinct hit set. `BurstEffect`: one stable radial target query for root and On Hit child. `OrbEffect`: caster-anchored rotating contact area, per-target rehit delay, limited lifetime and no triggers.
- Every eligible Projectile hit may enqueue its On Hit child even if direct damage kills the original target. Bursts may damage their original triggering target independently if still alive. Wet + Lightning selects the nearest other eligible Wet target by distance/ID, executes **one** derived arc hit, does not chain and does not consume Wet. Water extinguishes Burning and applies Wet. Fire applies Burning. Charged has no automatic extra reaction in M1.
- Temporary geometry, trace panels, and WASD caster repositioning in the sandbox are debugging affordances, **not the M2 player locomotion implementation**. See `docs/M1_magic_sandbox.md` for reproduction, testing and open design assumptions.

### Revised contract changelog

- **v1.1 / TASK-011–025:** Explicit runtime interfaces and resolved tunable parameter defaults. Existing v1 formula files and M0 fixtures remain valid. This is a prototype engineering integration only; no owner approval of balance constants or open grammar decisions is implied.

- **v1.2 / M1 regression hardening:** Instant Burst effect reservations now remain active through the event-drain phase and are released after hit/trigger/reaction resolution. Consequently, Burst `cleanup` trace records follow its queued `hit` records, and same-tick triggered Bursts count against active-effect budgets until resolved. The versioned fixtures `tests/fixtures/m1_runtime_traces_v1.json` lock event order/ancestry for Split+On Hit and Pierce+On Hit. `tests/m1_trace_golden_generator.gd` is a deliberate regeneration utility, not a background updater. Formula JSON schema remains v1 and needs no migration.

## M2 combat integration — technical revision 1.3 (TASK-026–035)

- `CombatSession.issue(command)` is the deterministic command dispatch surface. `PlayerCombat.process_command` owns direction normalization, mouse-aim independent movement, dodge i-frames, cast lockout, recovery and context blocking; the scene controller only collects input. `CombatSession` wraps the existing `SpellRunner` with its clock and team/health/status/compiled-plan interfaces, not a duplicate runner.
- `ProjectileEffect.advance(dt,target_store,bounds,walls=[])` optionally sweeps against solid AABBs and remains backward-compatible for M1 (default empty walls). `SpellRunner.collision_walls` is optional, cleared on reset. M2 uses common geometry for movement, line of sight, telegraphs and both friendly and hostile projectile occlusion. A scoped M2-only manual Burst range and LOS restriction are **PROPOSED** and belong to `combat/combat_tuning_v1.json`.
- Enemy attacks carry stable `DamageEvent` IDs and teams. Dodge invulnerability is checked before shared `MagicTarget.receive_damage`, preserving channel resistance/armor/HP clamp; repeated attack IDs cannot apply damage twice. Enemy AI `idle/acquire/chase/windup/recover/dead` is deterministic and independent from art; its typed `AttackIntent` is exposed to placeholder warning drawings.
- `tests/fixtures/m2_baseline_v1.json` locks six seed-replay outcomes. `tests/m2_baseline_driver.gd` exercises ordinary player commands, not privileged HP/mana changes. The M1 formula schema and M1 causal golden traces remain unchanged. No schema migration or owner-approved gameplay redesign occurred.

### M2 contract change log

- **v1.3 / TASK-026–035:** Opt-in solid-wall swept projectile collision, command-driven combat session, typed hostile damage and telegraph interfaces. M0/M1 APIs remain compatible; all M2 numeric balance constants and input bindings are provisional. See `docs/M2_combat.md` for acceptance details.

## M3 contract extension — technical revision 1.4 (TASK-036–048)

- `RoomTemplate.initialize(data,arena,known_enemy_types)` validates marker coordinates, blocked entrances, known enemies and scene. A room definition references the M3 scene, markers and data-only waves; no production procedural graph is implied.
- `EncounterDirector` schedules initial and optional on-clear delayed waves, owns the authoritative room-clear guard when `CombatSession.defer_clear` is true, and emits completion at most once. A timed wave prevents clearing on temporarily zero living enemies. `RunFlow` serially instantiates a new M2 `CombatSession` on room transition, transfers validated run-owned resources/formulas and discards runtime bullets, statuses and effect queues.
- `RunState` stores finite JSON-compatible values, rune knowledge licenses, the two v1 formulas, per-room reward grants, merchant purchase IDs and editor experiment metrics. JSON number normalization permits integral floats during deserialization. `restore` validates then atomically copies the state. Saves are in-memory across the single continuous M3 scene; a disk save/load UI is **outside this milestone**.
- The `SpellEditor` uses the exact v1 `SpellCompiler`, rune access list and formula grammar; changes are kept in an undoable draft until an entirely valid Apply. Modified IDs `custom.slot_1/custom.slot_2` distinguish player-crafted builds without affecting existing golden samples. Edit policy `workshop_only/cleared_room` is a prototype data flag and active-fight edits are blocked.
- `RunFlow.enter_test_range` builds an isolated `SpellRunner` using the same compiled plans/elemental semantics. Range casts/health/mana/traces cannot affect the saved dungeon HP, money or progression. The optional prepared Wet cluster is distinct from the default, M1-identical reset preset.
- The M3 boss uses the shared M2 enemy target/HP/damage/hostile projectile API and alternate finite radial/targeted warning patterns. Rewards and shop are deterministic from seed+room/run inventory, duplicate rune fallback currency and numeric upgrade costs are **PROPOSED**, not approved design.
- The formula JSON schema remains v1; no migration required. **v1.4 / TASK-036–048** adds run/room/editor interfaces, six room templates, seed-based reward policy and M3 end-to-end test. Existing M0–M2 execution semantics are preserved; no permanent product decisions implied.
