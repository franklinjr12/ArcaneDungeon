# ArcaneDungeon — Magic Contract v1 (M0)

**Contract version:** 1.0, created in TASK-003. **Status:** provisional prototype implementation contract; does not supersede owner decisions in `docs/Game Design & Project Reference.md`.

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
| `SpellRunner.try_cast(slot_id,caster,origin,direction,run_seed)` | **Future TASK-023/024:** `{accepted,reason,cast_id}`. Do not build a fake casting runtime in M0 |
| `SimulationClock` | Fixed ticks, run-seeded RNG, monotonic ID assignment; determinism without rendering |
| `MagicEventQueue.push(event),drain(budget)` | Ordered typed events, no reentrant drain, enforced limits |
| `InteractionResolver.resolve(payload,target,context)` | **Future TASK-012:** semantic damage/state/reaction output, not implemented in M0 |
| `RunState` | **Future TASK-039:** `{schema_version,seed,stage_index,room_index,currency,unlocked_rune_ids,equipped_formulas,hp,mana}` |
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

- **v1.0 / TASK-003:** Initial M0 contract; all source-derived proposed rules retain proposal status. No owner-approved migrations yet.\n- **M0 implementation note:** The published backlog uses `RuneRegistry.get(id)` as conceptual syntax. Actual Godot API is `get_rune(id)` (and `get_by_id(id)`) because `Object.get` is a native method and overriding it triggers a parse warning/error. This is a compatibility naming adaptation, not a spell-schema change. Golden legal/invalid/budget traces are synthetic contract fixtures until the TASK-011–025 runtime exists.
