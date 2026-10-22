# Epic: ArcaneDungeon — Gameplay Prototype and Magic System


## Context


**Version:** 1.0 — 2026-10-22. **Audience:** AI coding agents, gameplay engineers, QA, and game design. **Deliverable:** executable Godot gameplay prototype and short vertical slice. **Status:** implementation PROPOSAL derived from the living GDD; this backlog does not convert unapproved ideas into owner decisions.


### Sources and decision taxonomy


- **[DECIDED]** A 2D pixel-art, combat-first top-down dungeon roguelite about inventing spells. Active aiming, movement, dodging, combat rooms, a stage boss, then a safe shop/spell workshop/testing area are central.
- **[DIRECTION]** Magic is made of reusable concepts; both within-spell formula composition and cross-spell elemental interactions matter. The language must be predictable and extensible.
- **[PROPOSED FOR PROTOTYPE]** Godot 4.x, keyboard/mouse first, two manual spell slots, dodge, 3 essences (Fire/Water/Lightning), 3 manifestations (Projectile/Burst/Orbiting Orb), 3 modifiers (Homing/Split/Pierce), and one trigger (On Hit). These are not approved permanent production limits.
- **[OPEN]** Final spell grammar, controller support, full cost model, long-run progression, between-room editing, permanent unlocks, and branching formulas.
- **[OUT OF SCOPE]** Art asset creation, final VFX/animation/audio, multiplayer, VR, large narrative, open world, procedural terrain, voxel/fluid physics, full campaign, unrestricted recursive spell graphs. Placeholder visuals and gameplay feedback are in scope.
- [ArcaneDungeon living GDD](https://docs.google.com/document/d/1fYI_7zgrL-xbm4WV52z6mimLcU6s_N8HKZKPppVY6_0/edit)
- [Arcane World — Magic and World Interactions](https://docs.google.com/document/d/13l4Aqtsrp0f47Uuj-7BatHlrwJv7RlUCY2HO92KQCng/edit)
- [Arcane World — World Knowledge](https://docs.google.com/document/d/1PSme3lsfFgC6T2nVckuKikEATj0A-CcFZodu8q1Ae4U/edit)


### Reference games and boundaries


- **Wizard of Legend:** skillful top-down wizard combat, room pressure, dodging, enemy telegraphs, boss pacing, stage transitions; https://wizardoflegend.com/
- **Magicraft:** modular spell construction, rune rewards, build discovery; https://store.steampowered.com/app/2103140/Magicraft/
- **Noita:** spell modifiers, triggers, surprising systemic outcomes; exclude Noita-scale material/pixel physics; https://store.steampowered.com/app/881100/Noita/
- **Spell Disk:** event-driven synergies and spell cascades; preserve manual combat and enforce limits; https://store.steampowered.com/app/2292060/Spell_Disk/
- **Arcane World principle:** spells express interaction payloads, while targets and their states determine reactions. Adapt Essence → Form → Behavior → Target/Relation → Conditions into Essence + Manifestation + Modifiers + typed Trigger + Payload. Do not port Arcane World's full mana physiology, VR gesture language, world simulation, or lore progression.


### Milestones and gates


| Gate | Tasks | Proof |
|---|---|---|
| M0 Contracts | TASK-001–010 | project boots, headless tests, versioned spell schema, validator/compiler contracts |
| M1 Magic sandbox | TASK-011–025 | cast/edit/test distinct spells, bounded On Hit payload, Wet → Lightning, trace events |
| M2 Combat | TASK-026–035 | movement, dodge, damage, 3 enemy roles, readable arena |
| M3 Vertical slice | TASK-036–048 | three combat rooms → boss → merchant/workshop → next combat room |
| M4 Validation | TASK-049–055 | test suite, profiling, telemetry, first human playtest, decision record |
| POST (gated) | TASK-056–061 | advanced formula graph, more interactions, progression only after validation |


**Agent workflow:** One task/PR or a small coupled pair. Every PR includes tests, demo steps, schema changes, and open design questions. Complete dependencies before integration. Parallel agents share the contracts below and never introduce incompatible duplicate representations.


### Provisional spell language v1 — freeze before coding


**RuneDefinition:** stable string ID (e.g. essence.fire, form.projectile, mod.homing, trigger.on_hit), category, schema_version, parameter definitions, compatibility tags, complexity weight, cost contribution, description, placeholder display key. IDs do not depend on filenames or translations.


**EffectSpec:** essence_id (required), manifestation_id (required), modifier_ids (ordered list), params (typed map).


**SpellFormula:** schema_version=1, formula_id, display_name, root:EffectSpec, optional on_hit:{trigger_id:trigger.on_hit,payload:EffectSpec}. No arbitrary scripts or engine class names in user-authored data.


**M1 legality:** root can be Projectile, Burst, or Orbiting Orb. On Hit only attaches to Projectile roots, and requires an explicit payload. Trigger payload must be Burst with its own explicit essence, no modifiers, no further triggers. Homing/Split/Pierce are Projectile-only. Reject duplicate modifiers, unknown IDs, missing slots, and incompatible attachments with path-specific errors. Modifier order is stored but v1 runtime uses fixed operation phases, so reordering modifiers has no effect; tell players this. A graph is NOT implemented in M1.


**On Hit ownership:** every projectile instance owns a copy of the compiled trigger reference. Split creates separate projectiles, each eligible to trigger. A projectile can trigger once per unique enemy target; Pierce can hit additional distinct targets up to its cap. Burst appears at hit position and may separately hit the triggering enemy once. The full root + payload mana and complexity are paid at manual cast; triggers cost no additional mana. No recursive payload triggers in M1.


**Teams and targeting:** every effect carries cast_id, caster_id, team_id, formula_id, parent_effect_id, root_cast_id, and deterministic effect sequence. Friendly fire off in v1. Targets expose stable runtime IDs, team, HP, resistance tags, and StatusComponent. Orb is caster-anchored contact damage with per-target hit cooldown and fixed lifetime, no On Hit child in M1.


**Interaction payloads and states:** Fire applies damage + Burning; Water applies damage + Wet and extinguishes Burning; Lightning applies damage + Charged feedback. A Lightning hit on a Wet enemy may arc once to the nearest OTHER Wet enemy in radius; stable tie-break by distance then target ID; arc does not recurse. Burning ticks at fixed simulation intervals. Wet is not consumed by lightning in v1. All numerical values are data-driven and provisional. Resolve through common target state/properties, not hard-coded named spell pairs.


**Fixed execution phases:** request cast → verify compiled formula/slot/mana/cooldown → spend mana once → spawn root effect → movement/collision → eligible hit → damage/status resolver → enqueue triggers/reactions → drain typed queue in sequence → spawn payload effects → cleanup. Do not recursively cast inside collision callbacks. Do not mutate a compiled spell during a cast.


**Limits:** configurable max complexity, max event depth, max events per root cast, max effects per cast, max active effects globally, max lifetime, max chain targets, and per-target rehit delay. On limit violation, drop excess work, trace budget_exceeded, and continue. Initial event depth <=1; structure code for future depth.


**Determinism:** run-seeded RNG, stable target ordering, monotonic event sequence, fixed-step state ticking. Repro tests compare normalized event traces. Rendering is downstream of simulation and never affects outcomes.


### Shared APIs and code boundaries


- RuneRegistry.get(id) → RuneDefinition or null.
- SpellValidator.validate(formula, unlocked_rune_ids) → {ok, issues:[{code,path,message}]}.
- SpellCompiler.compile(formula, unlocked_rune_ids) → {ok, compiled_spell, issues}; compiled data immutable.
- SpellRunner.try_cast(slot_id,caster,origin,direction,run_seed) → {accepted,reason,cast_id}.
- MagicEventQueue.push(event), drain(budget); MagicEvent carries event_id, sequence, cast_id, parent_effect_id, source_id, target_id, position, type, depth.
- InteractionResolver.resolve(payload,target,context) → {damage,state_changes,reaction_events}.
- RunState → {schema_version,seed,stage_index,room_index,currency,unlocked_rune_ids,equipped_formulas,hp,mana}.
- SpellCodec.encode/decode → schema-versioned plain JSON with strict whitelist and actionable errors.
- Suggested folders: res://game/core/, magic/data/, magic/compile/, magic/runtime/, combat/, world/, ui/, debug/, tests/. No simulation code should import final sprites or audio.


### Example formulas and expected behavior


    {"schema_version":1,"formula_id":"sample.fire_shot","display_name":"Fire Shot","root":{"essence_id":"essence.fire","manifestation_id":"form.projectile","modifier_ids":[],"params":{}}}
    {"schema_version":1,"formula_id":"sample.split_water","display_name":"Split Water","root":{"essence_id":"essence.water","manifestation_id":"form.projectile","modifier_ids":["mod.split"],"params":{}}}
    {"schema_version":1,"formula_id":"sample.spark_burst","display_name":"Spark Burst","root":{"essence_id":"essence.fire","manifestation_id":"form.projectile","modifier_ids":["mod.pierce"],"params":{}},"on_hit":{"trigger_id":"trigger.on_hit","payload":{"essence_id":"essence.lightning","manifestation_id":"form.burst","modifier_ids":[],"params":{}}}}


Fire Shot burns. Split Water creates multiple Wet-applying projectiles. Spark Burst pierces distinct enemies and emits Lightning Bursts at hit locations; a Wet target can provoke a bounded lightning arc. Invalid Fire + Burst + Homing returns MODIFIER_INCOMPATIBLE; Projectile + OnHit without payload returns TRIGGER_PAYLOAD_REQUIRED. Invalid formulas cannot be cast.


### Definition of done and playtest criteria


Every task must have a reproducible demo/test, visible error behavior, no hidden hardcoded spell permutations, no dependency on final art, and a short PR note on changed interfaces. A first human playtest requires M1/M2 smoke tests green, at least six distinct legal formulas, clear invalid-formula feedback, no crash in a 10-minute sandbox stress run, and a playable combat room. Proposed M4 targets: 5/6 players create two mechanically distinct spells unaided; 4/6 predict Water → Lightning after one explanation; median edit-and-test under 45 seconds; 4/6 voluntarily change a spell after finding a rune; zero crashes/softlocks; target 60 FPS on reference hardware in normal rooms. These are hypotheses, not approved KPIs.


### Risks and mitigations


- Superficial combinations → behavior-based acceptance tests, varied enemy pressure.
- Editor resembles programming homework → structured slots, reversible actions, presets, live test target.
- Menus eclipse combat → active aim/dodge and a fast edit loop.
- Trigger explosion → explicit queue budgets, trace, and profiler.
- Simulation scope creep → semantic states on actors only; environmental props optional later.
- Save corruption during grammar evolution → versioned codec, migrations, golden files.
- Unapproved design choices → label every proposed constant and log owner decisions.


---


## TASK-001 — Repository bootstrap and scene entry points


**Milestone:** M0 | **Dependencies:** — | **Priority:** P0


### Goal
Create a clean Godot 4 project that opens on a launcher with buttons for Sandbox and Combat Arena.


### Requirements
- Pin tested Godot 4.x minor version and renderer; set input actions and scene directory conventions.
- Add main scene, sandbox scene, arena scene, error log, and placeholder primitive sprites/shapes.
- Document headless launch and export commands; avoid external assets.


### Acceptance Criteria
- [ ] Fresh clone opens without missing imports.
- [ ] Sandbox and arena can launch from main scene.
- [ ] Headless project load exits successfully.


## TASK-002 — Headless test runner and CI


**Milestone:** M0 | **Dependencies:** 001 | **Priority:** P0


### Goal
Make behavior verifiable without manual clicking.


### Requirements
- Create res://tests/run_tests.gd with deterministic test discovery, assertions and nonzero exit on failure.
- Add CI command for headless Godot, lint/parser check, and fixture loading.
- Emit concise failure diffs and test counts.


### Acceptance Criteria
- [ ] A deliberately failing test fails CI.
- [ ] Passing smoke tests run on clean checkout.
- [ ] Runner does not depend on graphical desktop.


## TASK-003 — Design contract and change-control registry


**Milestone:** M0 | **Dependencies:** 001 | **Priority:** P0


### Goal
Prevent parallel agents from inventing conflicting spell rules.


### Requirements
- Create docs/architecture/magic_contract_v1.md based on Context grammar, status labels, API signatures and phase ordering.
- Record OPEN decisions with owner-approval column; classify every provisional constant as tuning data.
- Document allowed schema changes and migration requirements.


### Acceptance Criteria
- [ ] Contracts cover On Hit ownership, targets, costs, invalid formula behavior and order semantics.
- [ ] A new agent can locate the canonical definitions without reading code.
- [ ] Changes to shared interfaces require a single documented version update.


## TASK-004 — RuneDefinition resource and registry


**Milestone:** M0 | **Dependencies:** 001,003 | **Priority:** P0


### Goal
Provide a single source of truth for rune metadata.


### Requirements
- Implement immutable RuneDefinition Resources and RuneRegistry keyed by stable IDs.
- Validate uniqueness, category, typed parameter schema, compatibility tags, cost/complexity fields.
- Ship seed data for 3 essences, 3 manifestations, 3 modifiers and On Hit.


### Acceptance Criteria
- [ ] All 10 prototype IDs load and resolve.
- [ ] Duplicate ID and missing category fail validation with diagnostics.
- [ ] UI can enumerate registry by category without hardcoded lists.


## TASK-005 — Formula model and JSON codec v1


**Milestone:** M0 | **Dependencies:** 003,004 | **Priority:** P0


### Goal
Make player-authored spells portable, inspectable and versionable.


### Requirements
- Implement EffectSpec, SpellFormula and strict JSON codec; serialize stable rune IDs and params only.
- Reject unknown schema versions and unsafe/unrecognized fields; validate types and maximum lengths.
- Provide golden fixtures for the three example formulas and malformed inputs.


### Acceptance Criteria
- [ ] Encode → decode → encode is stable for valid fixtures.
- [ ] Malformed JSON, unknown version and missing root produce typed errors.
- [ ] No Godot instance IDs or executable resource paths are stored in formula JSON.


## TASK-006 — Formula validation and diagnostics


**Milestone:** M0 | **Dependencies:** 004,005 | **Priority:** P0


### Goal
Reject illegal rune attachments before gameplay execution.


### Requirements
- Check required essence/manifestation, rune ownership, duplicate modifiers, root compatibility, payload constraints, and complexity cap.
- Return issues with code, field path, and user-facing explanation; no silent correction.
- Unit-test missing payload, On Hit on Burst, Homing on Burst, duplicate modifier, unknown rune and locked rune.


### Acceptance Criteria
- [ ] Every invalid fixture has stable expected issue codes.
- [ ] Valid example formulas pass.
- [ ] Compiler and editor consume the same validator output.


## TASK-007 — Compiler and immutable execution plan


**Milestone:** M0 | **Dependencies:** 004–006 | **Priority:** P0


### Goal
Translate legal formulas into resolved data without handcrafting spell permutations.


### Requirements
- Build SpellCompiler that resolves rune data, calculates cost/cooldown/complexity and emits immutable CompiledSpell.
- Encode fixed modifier execution phases and explicit trigger payload plan.
- Cache by canonical formula hash plus registry revision; invalidate when rune data changes.


### Acceptance Criteria
- [ ] All example formulas compile to distinct operation plans.
- [ ] Repeated compilation is stable; mutation of source formula cannot change an in-flight plan.
- [ ] Invalid formula never produces a runnable plan.


## TASK-008 — Simulation clock, IDs, seeded RNG


**Milestone:** M0 | **Dependencies:** 001,002 | **Priority:** P0


### Goal
Make interactions reproducible and safe to test.


### Requirements
- Implement fixed-tick simulation service, monotonic cast/effect/event IDs and seeded RNG injection.
- Define stable ordering for target ties and queued events.
- Add normalized trace fixture helpers that omit engine-only nondeterministic identifiers.


### Acceptance Criteria
- [ ] Same seed + inputs yield identical normalized event order.
- [ ] Different seed affects only explicitly random mechanics.
- [ ] Pause and fixed-step debug modes do not change outcomes.


## TASK-009 — Typed event queue and execution budgets


**Milestone:** M0 | **Dependencies:** 003,008 | **Priority:** P0


### Goal
Prevent re-entrant collision logic and runaway cascades.


### Requirements
- Implement MagicEvent with typed source/target/position/ancestry and FIFO-by-sequence dispatch.
- Implement SpellLimits for depth, per-cast events/spawns, global active effects, lifetime and chain count.
- Budget breaches emit traceable budget_exceeded and never throw or hang.


### Acceptance Criteria
- [ ] Event ordering remains stable under multiple same-frame collisions.
- [ ] Synthetic 10,000-event loop is capped and completes.
- [ ] No callback recursively dispatches gameplay effects.


## TASK-010 — Debug event trace and contract test fixtures


**Milestone:** M0 | **Dependencies:** 002,005–009 | **Priority:** P0


### Goal
Give AI agents visibility into why a formula behaves as it does.


### Requirements
- Capture cast request, cost, spawn, hit, state, trigger, reaction, cleanup, rejection and budget events.
- Add filters by cast_id, source formula and event type; export normalized JSON traces.
- Create golden traces for legal, invalid and budget-exceeded cases.


### Acceptance Criteria
- [ ] Trace identifies parent/root cast for every spawned payload.
- [ ] Golden trace tests detect changed semantics.
- [ ] Trace collection can be disabled without changing simulation.


## TASK-011 — MagicTarget, health and team contract


**Milestone:** M1 | **Dependencies:** 008–010 | **Priority:** P0


### Goal
Define one damageable/interactive target interface shared by players, enemies and dummies.


### Requirements
- Implement stable target ID, team, tags, HealthComponent, StatusComponent slot and damage receiver.
- Apply friendly-fire-off and alive/dead eligibility in one place.
- Expose deterministic target queries with radius, team filter, and distance/ID ordering.


### Acceptance Criteria
- [ ] No friendly damage occurs.
- [ ] Dead/removed targets are excluded from targeting.
- [ ] Queries return deterministic order on equal distances.


## TASK-012 — Generic damage and interaction resolver


**Milestone:** M1 | **Dependencies:** 004,009,011 | **Priority:** P0


### Goal
Resolve elemental payloads against target properties rather than named spells.


### Requirements
- Define HitPayload with essence, base damage, interaction channels, knockback metadata and source context.
- Centralize armor/resistance multipliers, damage events and state changes.
- Use registry data to map Fire/Water/Lightning into channels; separate math from visuals.


### Acceptance Criteria
- [ ] The same projectile class can carry all three essences.
- [ ] Damage results match headless fixtures.
- [ ] Adding an essence needs data/resolver registration, not a new projectile spell class.


## TASK-013 — Projectile manifestation


**Milestone:** M1 | **Dependencies:** 007–012 | **Priority:** P0


### Goal
Support manually aimed, finite-lifetime traveling magic.


### Requirements
- Build one reusable projectile entity with speed, radius, lifetime, collision, owner/team and hit callback.
- Use swept collision or adequate high-speed detection; record one hit per target unless a modifier explicitly permits more.
- Spawn from compiled plan and pass all contact through resolver + event queue.


### Acceptance Criteria
- [ ] Fire, Water and Lightning projectiles reuse one implementation.
- [ ] Projectile despawns on lifetime/wall or valid hit per policy.
- [ ] Fast projectiles do not routinely tunnel through targets.


## TASK-014 — Burst manifestation and radius resolution


**Milestone:** M1 | **Dependencies:** 007–012 | **Priority:** P0


### Goal
Provide area effects usable as root spells and trigger payloads.


### Requirements
- Implement instant circular Burst centered at cast point or On Hit contact point.
- Query eligible targets once, stable-sort them, apply one hit per target, then clean up.
- Expose radius/damage/cost in data; use temporary circle overlay for readability.


### Acceptance Criteria
- [ ] Burst hits all and only eligible targets in radius.
- [ ] Same target is not hit twice by one Burst instance.
- [ ] Root Burst and triggered Burst share the same manifestation class.


## TASK-015 — Orbiting Orb manifestation


**Milestone:** M1 | **Dependencies:** 007–012 | **Priority:** P0


### Goal
Test a spatially distinct, caster-anchored spell archetype.


### Requirements
- Implement timed orb orbiting caster at data-driven radius/speed with collision/contact damage.
- Maintain per-target rehit cooldown and max active-orb budget.
- Disallow trigger attachments in v1, with validator explaining restriction.


### Acceptance Criteria
- [ ] Orb follows moving caster and expires.
- [ ] Stationary overlapping target takes bounded contact hits.
- [ ] No implicit auto-cast or recursive trigger is created.


## TASK-016 — Homing modifier


**Milestone:** M1 | **Dependencies:** 013,008,007 | **Priority:** P0


### Goal
Create visible trajectory changes from one reusable modifier.


### Requirements
- Steer projectile velocity toward nearest eligible target in acquisition radius; stable tie-break and turn-rate cap.
- Define behavior when target dies or exits range: continue last velocity; never teleport.
- Read tunables from RuneDefinition/CompiledSpell, not spell-name conditionals.


### Acceptance Criteria
- [ ] Projectile curves toward eligible moving target.
- [ ] No-target and target-loss cases remain stable.
- [ ] Same seed and target positions produce identical paths.


## TASK-017 — Split modifier


**Milestone:** M1 | **Dependencies:** 013,007,009 | **Priority:** P0


### Goal
Demonstrate multiplicative spatial behavior without bespoke multi-shot spells.


### Requirements
- Spawn fixed-count child projectiles with symmetric angle offsets around aim direction.
- Each child inherits caster, root cast, elemental payload, On Hit reference and per-instance collision state.
- Charge mana once for the parent cast; enforce total spawn budgets before spawning.


### Acceptance Criteria
- [ ] Three-way spread uses one Projectile implementation.
- [ ] Each child can hit/trigger independently.
- [ ] Under tight budget, extra children are dropped and logged without crash.


## TASK-018 — Pierce modifier


**Milestone:** M1 | **Dependencies:** 013,007,011 | **Priority:** P0


### Goal
Allow a projectile to affect several distinct enemies.


### Requirements
- Keep a per-projectile hit set and maximum distinct target count.
- On eligible hit, resolve payload and On Hit once per target, then continue until pierce limit or lifetime.
- Walls block unless separately supported; repeated overlap does not multiply hits.


### Acceptance Criteria
- [ ] One piercing projectile hits up to configured distinct target count.
- [ ] Same target cannot be hit again by that instance.
- [ ] Trigger count equals distinct valid hits, subject to budgets.


## TASK-019 — On Hit trigger and explicit Burst payload


**Milestone:** M1 | **Dependencies:** 009,013,014,017,018 | **Priority:** P0


### Goal
Implement a useful, bounded linked effect with clear ownership.


### Requirements
- Attach typed trigger to Projectile plan only; enqueue on eligible collision, never inside collision callback.
- Spawn payload Burst at recorded hit position, using payload's own essence and parent/root IDs.
- Allow each Split child and Pierce hit to activate; enforce per-cast event/depth budgets and one-hit-per-target rule.


### Acceptance Criteria
- [ ] Fire Projectile → On Hit Lightning Burst works.
- [ ] Split+On Hit and Pierce+On Hit counts match golden traces.
- [ ] Payload Burst cannot recursively trigger and budget overflow is visible.


## TASK-020 — StatusComponent and fixed-tick lifecycle


**Milestone:** M1 | **Dependencies:** 008,011,012 | **Priority:** P0


### Goal
Provide reusable time-bound states for cross-spell experiments.


### Requirements
- Store states keyed by stable ID with stacks/intensity, duration, source and refresh policy.
- Implement fixed-tick apply/refresh/remove/expire and event hooks.
- Start with Wet, Burning, Charged; keep visuals optional and data-driven.


### Acceptance Criteria
- [ ] Wet and Burning can coexist unless a resolver rule removes one.
- [ ] Expired states no longer affect targeting/reactions.
- [ ] Same tick sequence yields same status trace.


## TASK-021 — Water–Fire and Burning interactions


**Milestone:** M1 | **Dependencies:** 012,020 | **Priority:** P0


### Goal
Make different elemental casts alter future combat outcomes.


### Requirements
- Fire applies/refreshes Burning; Burning inflicts data-driven periodic damage.
- Water applies Wet and extinguishes Burning through generic state rule.
- Define update ordering for direct hit vs DOT tick and target death; prevent postmortem DOT.


### Acceptance Criteria
- [ ] Fire hit creates Burning and timed damage.
- [ ] Water extinguishes Burning while applying Wet.
- [ ] DOT is stable under pause/replay and stops on death.


## TASK-022 — Wet–Lightning reaction and bounded arcs


**Milestone:** M1 | **Dependencies:** 012,020,009 | **Priority:** P0


### Goal
Demonstrate a second-layer combination across separate spells.


### Requirements
- Lightning hit on Wet target queries other Wet enemy targets in radius, chooses nearest by distance then stable ID.
- Apply one derived arc damage/event to that target; derived arc does not chain or consume Wet in v1.
- Render temporary debug line/label and trace originating hit, reaction and selected target.


### Acceptance Criteria
- [ ] Water then Lightning creates one bounded arc when second Wet target exists.
- [ ] Lightning alone does not arc; no eligible second target means no arc.
- [ ] Equidistant targets produce stable result across runs.


## TASK-023 — Mana, cooldown and complexity accounting


**Milestone:** M1 | **Dependencies:** 007,008,019 | **Priority:** P0


### Goal
Make spell construction have legible resource tradeoffs.


### Requirements
- Store mana reserve/regeneration on caster and per-slot cooldown timers; costs derived from compiled formula.
- Pay once on successful manual cast; no additional charge for trigger payload or Split children.
- Reject insufficient mana, cooldown, or over-complexity with reason; expose cost preview in editor.


### Acceptance Criteria
- [ ] Rejected cast changes neither mana nor effect count.
- [ ] Valid cast deducts exactly compiled mana cost once.
- [ ] Regeneration and cooldown tick at fixed rate; no negative mana.


## TASK-024 — Spell loadout and hot-swappable compiled plans


**Milestone:** M1 | **Dependencies:** 005–007,023 | **Priority:** P0


### Goal
Support two independently equipped, player-authored spells.


### Requirements
- Create two slots with independent formula ID, compiled plan and cooldown; avoid hardcoded offensive/defensive roles.
- Allow edits/equip only at permitted test/workshop contexts; revalidate against current rune access.
- Define replacement behavior: existing spawned effects finish with their original immutable plan.


### Acceptance Criteria
- [ ] Two distinct slots cast different formulas.
- [ ] Editing a slot never mutates already spawned projectiles.
- [ ] Locked/invalid spell cannot be equipped.


## TASK-025 — Magic sandbox and target inspection


**Milestone:** M1 | **Dependencies:** 010–024 | **Priority:** P0


### Goal
Make invention testable without running a dungeon.


### Requirements
- Build debug room with stationary/moving targets, clustered Wet candidates, mana reset, pause/step and spawn controls.
- Show hit counts, DPS over fixed window, state tags, active effects, budgets, trace and compiled costs.
- Allow quick selection of six sample formulas and repeatable reset with seed.


### Acceptance Criteria
- [ ] Designer can reproduce Fire→Burning, Water→Wet→Lightning and On Hit payload in under a minute.
- [ ] Sandbox reset returns same initial state and trace.
- [ ] A stress preset exposes effect caps without freezing.


## TASK-026 — Player movement, aim and input map


**Milestone:** M2 | **Dependencies:** 001,011,024 | **Priority:** P0


### Goal
Make a mage responsive with simple placeholder graphics.


### Requirements
- Implement acceleration/deceleration or immediate movement as tunable, mouse aim and two cast inputs.
- Separate input collection from gameplay command processing for deterministic tests.
- Prevent casting during dead, paused or modal-editor states.


### Acceptance Criteria
- [ ] Player can move/aim/cast in eight directions.
- [ ] Input-to-cast latency is within one gameplay frame in normal play.
- [ ] No movement or cast commands leak through open modal UI.


## TASK-027 — Dodge, invulnerability and recovery


**Milestone:** M2 | **Dependencies:** 026,011 | **Priority:** P0


### Goal
Give combat a skillful defensive timing mechanic.


### Requirements
- Implement directional dodge with speed, duration, cooldown and configurable i-frames.
- Handle wall collision, repeated input, cast cancellation/lockout and post-dodge recovery explicitly.
- Expose debug invulnerability and cooldown indicators.


### Acceptance Criteria
- [ ] Dodge travels predictably and cannot pass solid walls.
- [ ] Attacks during i-frames do not damage; outside i-frames they do.
- [ ] Spamming dodge cannot bypass cooldown.


## TASK-028 — Enemy/player damage pipeline and death


**Milestone:** M2 | **Dependencies:** 011,012,026,027 | **Priority:** P0


### Goal
Unify damage, hit feedback and combat termination.


### Requirements
- Define DamageEvent source/team/type/amount, resistance calculation, invulnerability check and HP clamp.
- Provide short hit flash, numeric log and health bar using placeholder UI.
- Player death stops commands and opens retry/restart; enemy death emits once and cleans up.


### Acceptance Criteria
- [ ] One attack causes one damage event unless explicitly multi-hit.
- [ ] Dead entities cannot attack or receive repeated rewards.
- [ ] Retry resets scene state, RNG and active effects.


## TASK-029 — Enemy AI framework and telegraph interface


**Milestone:** M2 | **Dependencies:** 008,011,028 | **Priority:** P0


### Goal
Support reusable deterministic enemy state machines.


### Requirements
- Implement idle/acquire/chase/attack/recover/dead states, perception range and simple steering.
- Define AttackIntent with telegraph duration, hit geometry, cooldown and damage; expose placeholder warning shapes.
- Keep targeting, navigation and attack logic independent from enemy art.


### Acceptance Criteria
- [ ] Enemies respect telegraph before damage.
- [ ] AI state changes are logged and testable.
- [ ] No attack can hit during its own windup.


## TASK-030 — Melee pursuer archetype


**Milestone:** M2 | **Dependencies:** 029,027 | **Priority:** P0


### Goal
Create close-range pressure that rewards positioning and area control.


### Requirements
- Chase player within arena, wind up short-range strike, recover, and reacquire.
- Handle player dodge, walls, collision separation and death.
- Use tunable health/speed/telegraph/range.


### Acceptance Criteria
- [ ] Melee pursuer can be kited, dodged and killed.
- [ ] Attack has readable windup and finite recovery.
- [ ] It cannot attack through a wall.


## TASK-031 — Ranged attacker archetype


**Milestone:** M2 | **Dependencies:** 029 | **Priority:** P0


### Goal
Create projectile pressure and movement decisions.


### Requirements
- Maintain desired distance and line-of-sight; telegraph then fire enemy-owned projectile.
- Use same team/health pipeline but enemy attack logic separate from player formula inventory.
- Make projectile speed, spread and recovery tunable.


### Acceptance Criteria
- [ ] Enemy telegraph is visible before launch.
- [ ] Enemy projectile collides with player/walls and respects dodge i-frames.
- [ ] Ranged enemy cannot fire through occluding wall.


## TASK-032 — Mobile flanker archetype


**Milestone:** M2 | **Dependencies:** 029 | **Priority:** P0


### Goal
Create an enemy that tests Homing, Burst and aim skill.


### Requirements
- Implement strafe/reposition behavior with bounded lateral movement and attack cooldown.
- Avoid teleportation and impossible instant direction changes.
- Keep simple behavior states inspectable in debug.


### Acceptance Criteria
- [ ] Flanker moves differently from pursuer and ranged archetype.
- [ ] Homing can track it; Burst can punish clustering.
- [ ] No offscreen/infinite kiting or wall clipping.


## TASK-033 — Combat arena layout and camera


**Milestone:** M2 | **Dependencies:** 026–032 | **Priority:** P0


### Goal
Provide a readable bounded space to test spell and enemy pressure.


### Requirements
- Create handcrafted arena with collision walls, spawn markers and temporary floor shapes.
- Camera follows player, clamps to bounds, and keeps threats visible; do not implement procedural terrain.
- Add debug overlays for attack hitboxes, target acquisition and collision masks.


### Acceptance Criteria
- [ ] Player/enemies/projectiles respect boundaries.
- [ ] Three enemy archetypes can spawn together without softlock.
- [ ] Collision debug mode makes hit decisions inspectable.


## TASK-034 — Combat HUD and immediate feedback


**Milestone:** M2 | **Dependencies:** 023,028,033 | **Priority:** P0


### Goal
Make costs, states and combat outcomes understandable.


### Requirements
- Show HP, mana, spell slot icons/names, cooldowns and equipped formula summary.
- Display short-lived hit/status text, On Hit and reaction notices with color-independent symbols.
- Use placeholder panels and text; expose accessibility toggle for flashes/shake.


### Acceptance Criteria
- [ ] Player can tell why a cast failed.
- [ ] Wet/Burning/Lightning reaction can be identified without reading event logs.
- [ ] UI stays usable at target reference resolution.


## TASK-035 — Combat tuning and baseline scenario tests


**Milestone:** M2 | **Dependencies:** 026–034 | **Priority:** P0


### Goal
Verify basic spell combat is playable before adding run structure.


### Requirements
- Build three fixed scenarios: single pursuer, mixed wave, Wet/Lightning cluster.
- Record damage received, time to clear, casts, dodges, reactions and framerate.
- Tune only data constants and document tradeoffs; no new mechanics.


### Acceptance Criteria
- [ ] All three scenarios are beatable with at least two starter loadouts.
- [ ] No unavoidable attacks under normal telegraph visibility.
- [ ] Baseline test fixture and replay seed are checked in.


## TASK-036 — Room template and doorway contract


**Milestone:** M3 | **Dependencies:** 033,035 | **Priority:** P0


### Goal
Create deterministic room-to-room traversal without procedural terrain.


### Requirements
- Define RoomTemplate Resource with arena scene, entrance/exit markers, spawn points, reward spawn and room type.
- Lock exits during combat; unlock only after all required enemies die.
- Validate no missing exits/spawns and safe player placement.


### Acceptance Criteria
- [ ] A room opens its exit after encounter completion.
- [ ] Entering a room does not overlap player with a wall or enemy.
- [ ] Malformed room template fails with actionable diagnostic.


## TASK-037 — Encounter director and wave completion


**Milestone:** M3 | **Dependencies:** 029–033,036 | **Priority:** P0


### Goal
Spawn enemies and signal combat completion reliably.


### Requirements
- Implement encounter definitions with enemy type/count, wave trigger, spawn delays and completion conditions.
- Support one initial wave and optional second wave; cap active enemies.
- Ensure death/cleanup and delayed spawn cannot prematurely clear a room.


### Acceptance Criteria
- [ ] Room clear fires exactly once after all required enemies and pending waves finish.
- [ ] A killed enemy cannot be counted twice.
- [ ] Restarting a room with same seed gives same spawn plan.


## TASK-038 — Short stage sequence and transitions


**Milestone:** M3 | **Dependencies:** 036,037 | **Priority:** P0


### Goal
Prove the dungeon → boss → workshop → next stage macro loop.


### Requirements
- Build deterministic first stage of three combat rooms followed by boss; persist RunState across scene transitions.
- Add room transition fade/teleport and return-to-menu path; stage two starts with one combat room.
- Keep map topology linear in v1; branch/procedural room graph is post-validation.


### Acceptance Criteria
- [ ] Completing three rooms reaches boss, then workshop, then next combat room.
- [ ] Player HP/mana/runes/currency persist as specified.
- [ ] No duplicated enemies/effects after transitions.


## TASK-039 — RunState, restart and seeded run creation


**Milestone:** M3 | **Dependencies:** 005,008,024,038 | **Priority:** P0


### Goal
Make each short run coherent and reproducible.


### Requirements
- Create new run with seed, initial two spells, unlocked rune set, player resources and stage progress.
- Distinguish runtime transient effects from serializable state.
- On death/retry reset run-local unlocks/currency; do not invent permanent progression.


### Acceptance Criteria
- [ ] Same seed produces same room/reward schedule.
- [ ] Run restart clears all old effects, statuses and cooldowns.
- [ ] Invalid saved state is rejected gracefully.


## TASK-040 — Rune unlock inventory and loadout legality


**Milestone:** M3 | **Dependencies:** 004,006,024,039 | **Priority:** P0


### Goal
Connect discovery to new formula possibilities.


### Requirements
- Represent run-owned rune IDs as nonconsumable knowledge licenses; reuse across slots in prototype.
- Show locked/unlocked status and compile/equip against current access.
- On duplicate reward convert to a small currency amount or reroll per data setting; mark policy PROPOSED.


### Acceptance Criteria
- [ ] Picking up new rune makes it immediately selectable at next edit opportunity.
- [ ] Locked rune in saved formula cannot be equipped.
- [ ] Duplicate reward behavior is deterministic and documented.


## TASK-041 — Reward generator and pickup flow


**Milestone:** M3 | **Dependencies:** 037,039,040 | **Priority:** P0


### Goal
Make combat rewards encourage experimentation.


### Requirements
- Create seeded reward pools with new rune preference, currency fallback and a simple choice UI.
- Grant reward only once per cleared room; support one optional pickup per room.
- Display a short explanation of what new behavior the rune enables.


### Acceptance Criteria
- [ ] Two seeds can yield different available rune choices.
- [ ] Same seed yields same reward choices.
- [ ] Re-entering a cleared room cannot duplicate reward.


## TASK-042 — Mini-boss state machine and patterns


**Milestone:** M3 | **Dependencies:** 027–035,037 | **Priority:** P0


### Goal
Create a boss that tests dodging and build adaptability.


### Requirements
- Implement one boss with HP, two alternating telegraphed patterns (radial burst and targeted dash/shot), recover windows and phase threshold.
- Avoid requiring a specific element to win; boss uses shared health/status/damage pipeline.
- On death emit boss_defeated exactly once and unlock workshop.


### Acceptance Criteria
- [ ] Boss can be defeated with at least two distinct valid spell builds.
- [ ] All damage patterns telegraph before applying damage.
- [ ] Boss death transitions without duplicate rewards or stuck exits.


## TASK-043 — Workshop scene and safe simulation boundary


**Milestone:** M3 | **Dependencies:** 024,038,042 | **Priority:** P0


### Goal
Make a safe place for experimenting between stages.


### Requirements
- Build a no-hostile workshop scene with access to spell editor, testing zone, merchant and exit.
- Separate testing dummies from run HP/reward progression; testing does not spend permanent currency or advance room state.
- Restore HP/mana to defined workshop values when entering test zone; document policy as tunable.


### Acceptance Criteria
- [ ] Player cannot die or farm currency from test targets.
- [ ] Exiting workshop preserves equipped spells and purchases.
- [ ] No enemy encounter events fire in workshop.


## TASK-044 — Structured spell editor UI


**Milestone:** M3 | **Dependencies:** 004–007,024,040,043 | **Priority:** P0


### Goal
Let players author spells without writing JSON.


### Requirements
- Expose root Essence/Manifestation, compatible Modifiers, optional On Hit and required Burst payload Essence.
- Filter available runes; show why a slot is disabled, live validation, mana/complexity preview and resulting behavior summary.
- Support undo/reset/cancel/apply; edits are transactional and never partially equip invalid spells.


### Acceptance Criteria
- [ ] A novice can build Fire Projectile and Water Split Projectile using UI.
- [ ] Invalid formula shows specific issue and cannot be applied.
- [ ] Cancel restores previous equipped formula exactly.


## TASK-045 — Workshop testing range and rapid iteration


**Milestone:** M3 | **Dependencies:** 025,043,044 | **Priority:** P0


### Goal
Shorten the build → cast → observe → revise loop.


### Requirements
- Provide static and moving dummies, clustered Wet targets, instant reset and test-only mana refill.
- Show recent hit count, status/reaction summary, trigger count and budget warnings.
- Editor and test range share the exact same compiled spell and resolver used in dungeon.


### Acceptance Criteria
- [ ] Edited formula can be tested without restarting a run.
- [ ] Test results match sandbox traces for identical setup.
- [ ] Testing does not alter dungeon rewards or enemy progression.


## TASK-046 — Merchant inventory, prices and purchase flow


**Milestone:** M3 | **Dependencies:** 040,041,043 | **Priority:** P0


### Goal
Turn boss reward currency into meaningful spell-building choices.


### Requirements
- Create deterministic shop inventory: at least one unowned rune option and one numeric upgrade; costs in data.
- Show affordability and effect preview; purchase updates RunState atomically.
- No reroll, sell, or elaborate rarity system in first slice.


### Acceptance Criteria
- [ ] Purchasing a rune unlocks it in editor.
- [ ] Insufficient funds cannot create negative currency.
- [ ] Shop stock and prices are reproducible for a run seed.


## TASK-047 — Between-room edit access experiment


**Milestone:** M3 | **Dependencies:** 038,040,044 | **Priority:** P0


### Goal
Test the pacing tradeoff without permanently locking a rule.


### Requirements
- Expose a configurable policy: workshop-only editing or cleared-room quick editing.
- Quick edit uses the same validator/compiler but no test range or merchant.
- Track time spent editing and player behavior; owner chooses policy after playtest.


### Acceptance Criteria
- [ ] Both policies can be switched via data flag.
- [ ] Combat rooms cannot open editor mid-attack.
- [ ] Changing policy does not change formula format or invalidate a run.


## TASK-048 — Vertical-slice end-to-end smoke run


**Milestone:** M3 | **Dependencies:** 036–047 | **Priority:** P0


### Goal
Make the full intended progression executable and restartable.


### Requirements
- Add scripted smoke path: new run → room 1 → rune reward → rooms 2–3 → boss → shop/editor/test → next room.
- Assert no lost RunState, double rewards, invalid equipped formulas or lingering effects across transitions.
- Document human demo route and fallback starter loadout.


### Acceptance Criteria
- [ ] Automated or reproducible manual smoke reaches next-stage room.
- [ ] At least one newly obtained rune can be used in post-boss workshop.
- [ ] Death/restart and boss/workshop exits do not softlock.


## TASK-049 — Spell grammar regression suite


**Milestone:** M4 | **Dependencies:** 004–024 | **Priority:** P1


### Goal
Freeze intended v1 semantics before expanding content.


### Requirements
- Add matrix tests for every valid essence × root manifestation combination and each legal modifier/trigger.
- Cover invalid ownership, missing payload, duplicate IDs, wrong types, unknown versions and over-complexity.
- Golden test expected costs, compiled plans, event order and child effect counts.


### Acceptance Criteria
- [ ] Adding a rune does not change unrelated golden formulas.
- [ ] All illegal cases fail with stable typed diagnostics.
- [ ] CI runs entire suite headlessly.


## TASK-050 — Cross-spell reaction and combat regression suite


**Milestone:** M4 | **Dependencies:** 020–035 | **Priority:** P1


### Goal
Prevent status and damage bugs as enemy content grows.


### Requirements
- Test Burning refresh/tick/death, Water extinguish, Wet duration, Lightning arc targeting/tie-break and resistance.
- Test dodge i-frames, team rules, multiple hits, boss immunity policy and target removal mid-event.
- Include edge cases: zero eligible targets, target dies on hit, simultaneous status expiry/hit.


### Acceptance Criteria
- [ ] Identical seed/commands produce identical normalized traces.
- [ ] No double damage/reward after death.
- [ ] Status resolution matches documented fixed-phase order.


## TASK-051 — Stress, profiling and budget tuning


**Milestone:** M4 | **Dependencies:** 009,015–025,33,48 | **Priority:** P1


### Goal
Keep combinatorial builds safe under realistic action load.


### Requirements
- Benchmark many Split/Pierce/On Hit casts, simultaneous status ticks, orb overlaps and 30+ targets.
- Record frame time, active effects, events dropped, memory and GC spikes; tune limits via data.
- Provide in-game stress preset and headless completion criterion.


### Acceptance Criteria
- [ ] Synthetic cascade stops within configured budgets.
- [ ] Normal-room reference target reaches agreed FPS on documented hardware.
- [ ] Budget overflow is visible and does not corrupt later casts.


## TASK-052 — Telemetry and player experiment logging


**Milestone:** M4 | **Dependencies:** 010,044,045,048 | **Priority:** P1


### Goal
Measure whether players actually invent magic.


### Requirements
- Capture anonymous local session metrics: formula edits, rune choices, test casts, dungeon casts, reactions, time in editor, deaths and room clears.
- Provide opt-in/export-only CSV/JSON; no external analytics or identifying data in prototype.
- Tag formula signatures without collecting player-entered free text unless explicitly enabled.


### Acceptance Criteria
- [ ] A tester can export one session log locally.
- [ ] Edit-to-test time and distinct-formula count can be computed.
- [ ] Disabling telemetry changes no gameplay behavior.


## TASK-053 — Onboarding and first-use guidance


**Milestone:** M4 | **Dependencies:** 044,045,048 | **Priority:** P1


### Goal
Teach magic composition without overexplaining.


### Requirements
- Provide two starter formula presets and brief contextual prompts for Essence, Manifestation, Modifier and On Hit payload.
- Add one scripted Water→Lightning learning encounter or dummy setup.
- Allow prompts to be dismissed/reopened; no blocking tutorial campaign.


### Acceptance Criteria
- [ ] New player can cast a basic spell within first minute.
- [ ] Prompt explains why On Hit needs a payload.
- [ ] Water→Lightning reaction can be learned from game feedback.


## TASK-054 — First human playtest and qualitative review


**Milestone:** M4 | **Dependencies:** 049–053 | **Priority:** P1


### Goal
Validate the central invention fantasy before expanding scope.


### Requirements
- Recruit approximately six first-time testers; run 20–30 minute guided/unmoderated sessions using fixed checklist.
- Record spell diversity, time to first custom spell, successful reaction predictions, voluntary edits, combat clarity and observed frustration.
- Ask what each player believed their formula would do, what surprised them, and what they want to try next.


### Acceptance Criteria
- [ ] Playtest report includes anonymized observations, metrics and failure clips/steps.
- [ ] Findings distinguish editor usability from magic-system depth and combat feel.
- [ ] Top five changes are prioritized with evidence and owner decision needed.


## TASK-055 — Go/no-go review and contract v2 proposal


**Milestone:** M4 | **Dependencies:** 051–054 | **Priority:** P1


### Goal
Decide whether to expand or redesign before adding advanced magic.


### Requirements
- Compare results with proposed thresholds in Context and list unmet hypotheses.
- Write owner-facing decision record: proceed, revise grammar, revise combat, or pause.
- Only after explicit approval create v2 schema migration and post-validation sprint scope.


### Acceptance Criteria
- [ ] Decision record names accepted/rejected hypotheses and tradeoffs.
- [ ] No POST task is marked ready without gate approval.
- [ ] Open GDD questions are updated or linked to specific follow-up experiments.


## TASK-056 — POST: typed effect graph and branching payloads


**Milestone:** POST | **Dependencies:** 055 | **Priority:** P2


### Goal
Support multi-output formulas if linear v1 proves compelling but limiting.


### Requirements
- Design DAG-style nodes with typed ports, one root and bounded branches; preserve import from v1.
- Add cycle detection and explicit ownership/target inheritance per edge.
- Introduce editor graph only after API and usability experiment.


### Acceptance Criteria
- [ ] Existing v1 formulas migrate losslessly.
- [ ] Cycles and type-incompatible edges are rejected.
- [ ] Two On Hit payload branches execute deterministically within budgets.


## TASK-057 — POST: additional essences and reactions


**Milestone:** POST | **Dependencies:** 055,056 optional | **Priority:** P2


### Goal
Increase tactical breadth only where behavior remains distinct.


### Requirements
- Candidate Cold/Freeze/Brittle and Force/Impulse; resolve through semantic target properties.
- Add at least one interaction requiring two different spells, such as Wet→Freeze→Force shatter.
- Do not implement fluids, voxel deformation or general physics simulation.


### Acceptance Criteria
- [ ] New interaction is reproducible without bespoke spell-name checks.
- [ ] At least one enemy encounter rewards the new interaction.
- [ ] Status and budget regression tests remain green.


## TASK-058 — POST: more triggers and autonomous constructs


**Milestone:** POST | **Dependencies:** 055,056 | **Priority:** P2


### Goal
Explore Spell Disk-like systems without replacing active combat.


### Requirements
- Candidate On Expire, On Contact and timed repeat; autonomous orb/summon uses explicit owner and event budgets.
- Enforce cycle/depth/spawn caps and show execution ancestry in editor.
- Prototype one triggered system, not an unlimited trigger catalog.


### Acceptance Criteria
- [ ] Trigger graph cannot hang or allocate unbounded entities.
- [ ] Automated effects are still attributable to a manual source/action.
- [ ] Performance remains within approved stress budgets.


## TASK-059 — POST: compendium and saved spell blueprints


**Milestone:** POST | **Dependencies:** 055,005 | **Priority:** P2


### Goal
Let players retain knowledge without guaranteeing rune access.


### Requirements
- Save named formulas in a schema-versioned local Compendium; list missing runes on import.
- Separate permanent knowledge from run-scoped inventory and balance.
- Support rename, delete, duplicate and migration tests.


### Acceptance Criteria
- [ ] Blueprint survives game restart.
- [ ] A blueprint using locked runes remains visible but cannot be equipped.
- [ ] Corrupt/old entry does not prevent other blueprints loading.


## TASK-060 — POST: modular artifacts and passive synergies


**Milestone:** POST | **Dependencies:** 055,009 | **Priority:** P2


### Goal
Experiment with conditional build engines after base formulas are fun.


### Requirements
- Add one event-listening artifact prototype (e.g. every N manual Fire hits charges one Lightning Burst).
- Artifact hooks into typed event bus and budget accounting; no direct access to manifestation internals.
- Compare combat engagement and performance with/without artifact.


### Acceptance Criteria
- [ ] Artifact activates only at defined threshold.
- [ ] Removing artifact cancels future activation without mutating active effects.
- [ ] Artifact cannot bypass event budgets or create a trigger loop.


## TASK-061 — POST: room variety and run-length expansion


**Milestone:** POST | **Dependencies:** 055,038 | **Priority:** P2


### Goal
Extend replayability after confirming the short loop.


### Requirements
- Candidate authored room library, encounter variations, one elite enemy and optional branching rewards.
- Introduce seeded room graph only with connectivity validation and safe spawn placement.
- Defer additional biomes, bosses and campaign scope to separate content planning.


### Acceptance Criteria
- [ ] Every generated route reaches a boss and workshop.
- [ ] Reward progression remains playable under at least 100 seeded runs.
- [ ] New content does not require spell-system special cases.


---


### Parallel work and integration checklist


- **Track A — Magic core:** TASK-004–025; owner of registry, formula codec, compiler, runtime events, statuses and reactions. Do not let UI or combat duplicate spell semantics.
- **Track B — Combat:** TASK-026–035; may start after MagicTarget and SpellRunner contracts are frozen. Use test double spell casts until runtime integrates.
- **Track C — Dungeon/progression:** TASK-036–042; may scaffold room data after RunState and encounter contracts exist. Avoid bespoke boss damage rules.
- **Track D — Workshop/UI:** TASK-043–047; may prototype UI against validator/compiler stubs, then swap to real APIs.
- **Track E — QA/instrumentation:** TASK-002,010,025,049–055; create fixtures as features land, not only at the end.
- **Integration gates:** M0 contract sign-off before parallel coding; M1 sandbox acceptance before dungeon expansion; M2 combat feel before boss tuning; M3 end-to-end smoke before human playtest; M4 owner go/no-go before POST.
- **Suggested first agent assignment:** TASK-001 → 002 → 003 → 004 → 005 → 006 → 007 → 008 → 009 → 010. Then implement 011–014 and 20–23 to reach a first cast + Water/Lightning sandbox quickly; defer Orb and elaborate UI until basic spells are fun.


### Regression scenarios that must remain runnable


1. Compile and cast Fire Projectile; one valid target takes one direct hit and Burning.
2. Cast Water Projectile, then Lightning Projectile into two Wet enemies; one bounded arc hits the nearest second Wet target.
3. Fire Projectile + Split + On Hit → Lightning Burst; each child can activate once on distinct hit, with no recursive triggers.
4. Fire Projectile + Pierce + On Hit → Lightning Burst; trigger count equals distinct eligible contacts within cap.
5. Invalid Burst + Homing; invalid On Hit without payload; unknown rune; locked rune; over-complex formula; all reject before spending mana.
6. Cast then edit equipped formula; existing projectile resolves using original compiled plan.
7. Exceed event/effect budget; log budget_exceeded and continue to next cast.
8. Dodge through a telegraphed enemy attack, then take damage after i-frames expire.
9. Clear three rooms, collect a rune, defeat boss, buy another rune, edit/test a spell, continue into next stage.
10. Restart with same seed and scripted commands; normalized event traces and reward schedule match.


### Handoff and owner approvals


Before agents expand beyond M0, confirm or explicitly keep provisional: Godot version, input slots, initial rune roster, numeric cost/complexity weights, formula-order semantics, On Hit payload restriction, rune ownership/reuse, mid-run editing policy, reference hardware and whether a single short stage suffices for the first playtest. Changes should be written into the ArcaneDungeon living GDD's decision register; this backlog remains a versioned implementation plan, not the design authority.