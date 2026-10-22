# ARCANE DUNGEON

## Game Design & Project Reference — Living Design Document \| Working title: ArcaneDungeon \| Baseline: 20 October 2026 \| Status: Early concept / pre-production

DOCUMENT PURPOSE

This is the shared reference for game design, prototyping, art, engineering, and AI-assisted development. It consolidates the brainstorming so far, records the user’s expressed preferences, and distinguishes actual decisions from illustrative proposals. It is NOT an approved production backlog or a complete specification. All teams and agents should read the status conventions and open-questions sections before implementing ambiguous features.

# 1\. Executive Summary

ArcaneDungeon is a proposed 2D pixel-art action roguelite/dungeon crawler about a mage who invents combat spells by combining reusable magical principles. The defining experience is discovering runes or magical components, constructing original spells from them, actively casting those spells in responsive top-down combat, and exploiting synergies between spells and elemental states.

The intended structure combines the combat pacing and campaign/dungeon progression associated with Wizard of Legend; experimental spell customization associated with Noita and Magicraft; and interlocking spell triggers and synergies inspired by Spell Disk. The goal is not to copy those games. The differentiation is a coherent, reusable magical language: the player creates spell behavior instead of selecting only predefined abilities.

The player explores a combat dungeon, defeats enemies, finds currency/runes/upgrades, faces a boss, and enters a safe shop \+ spell-customization/testing area before moving to the next dungeon stage. The workshop is a substantial part of play: players can buy options, rearrange formula components, try combinations, and prepare for the next challenge.

ArcaneDungeon is specifically an experiment in the combat-oriented magic ideas from the larger Arcane World vision, not a 2D port of Arcane World. Arcane World emphasizes exploratory, utility, and non-combat magic in a much broader 3D/VR world. ArcaneDungeon narrows the scope to accessible, replayable, action-oriented magic while retaining the fantasy of understanding and inventing spells.

## 1.1 Status legend and confidence

DECIDED \= explicitly stated or reinforced by the project owner in this conversation. DIRECTION \= strongly agreed design direction, but details can change. PROPOSED \= assistant-origin design suggestion; useful for exploration, not approved. OPEN \= needs deliberate decision or testing. EXAMPLE \= illustrative, not an implementation requirement. These labels apply even when a proposal appears in a detailed section below.

Critical rule for agents: Do not convert an EXAMPLE or PROPOSED detail into a mandatory feature without confirmation. When uncertain, preserve the design intent, document the choice, and prefer small experiments over large irreversible systems.

# 2\. Product Vision and Design Pillars

## 2.1 Core player fantasy — DECIDED

Become a creative combat mage who learns the principles of magic and invents a personal arsenal. Success comes both from player skill (aiming, dodging, positioning, timing) and from understanding what individual magical components do, how to arrange them, and how different spells interact.

## 2.2 Design pillars — DIRECTION

• Player-authored magic: abilities are constructed from reusable ingredients rather than entirely handcrafted spells.

• Experimentation is the reward: discovering a behavior or synergy should feel as valuable as acquiring raw damage.

• Active, satisfying combat: spell crafting complements action combat rather than replacing moment-to-moment mastery.

• Meaningfully distinct builds: different arrangements of the same components can yield mechanically different fighting styles.

• Coherent, learnable rules: effects should be predictable enough for players to reason about combinations.

• Small-team feasibility: concentrate complexity in reusable systems, not a massive world, narrative, or asset catalog.

• Replayable stages: loot choices, rune availability, dungeon order, and adaptation to enemies produce varied runs.

## 2.3 Non-goals and scope boundaries — DIRECTION

• Not a full 3D open world, VR experience, or recreation of Arcane World.

• Not primarily a non-combat exploration or puzzle-solving game, although light environmental interactions remain possible.

• Not a fully automatic Vampire Survivors-style game; manual control is part of the appeal.

• Not a Noita-scale particle/terrain/fluid physics simulator.

• Not dependent on dozens or hundreds of manually programmed bespoke spells.

• Not dependent on a large story campaign, complex NPC relationships, handcrafted open world, or extensive quests to make the prototype fun.

# 3\. References and Differentiation

Wizard of Legend — Reference for fast, responsive top-down wizard combat, dashing, enemy patterns, room exploration, boss encounters, progression between stages, and the high-level campaign feel. It is the primary reference for level structure and action pacing.

Magicraft — Reference for modular spells and the satisfaction of constructing increasingly surprising or powerful magical effects. Relevant to the rune economy, build crafting, and spectacular late-run outcomes.

Noita — Reference for composable wand/spell mechanics, triggers and modifiers, surprising emergent combinations, and the appeal of discovering unintended interactions. Explicitly NOT a requirement to implement its simulated world or pixel physics.

Spell Disk — Reference for interdependent spells, event-based automatic activation, resource loops, and cascading synergies. Automated trigger systems should complement, not fully displace, active spellcasting.

Differentiation hypothesis — DIRECTION: a consistent magical grammar plus both within-spell formula composition and across-spell/elemental interactions, deployed in a more structured dungeon campaign with a dedicated experimentation workshop.

# 4\. Macro Gameplay Structure

## 4.1 Core gameplay loop — DECIDED / DIRECTION

1\. Enter a dungeon/combat stage.

2\. Explore rooms, fight enemy encounters, and discover resources, unlockables, new runes, and upgrades.

3\. Make build decisions as loot becomes available; adapt to new enemy behavior.

4\. Reach and defeat the stage boss.

5\. Transition to a safe workshop/shop/customization area.

6\. Purchase items or upgrades, arrange and test spell combinations, optimize the loadout.

7\. Advance to the next dungeon stage and repeat until the run ends or the campaign is cleared.

The stage → boss → shop/workshop → next stage structure was explicitly proposed by the project owner and is the strongest current structural decision. How many stages, whether individual rooms are procedurally arranged, and how persistent progression works remain open.

## 4.2 Moment-to-moment dungeon play — DIRECTION

A top-down mage moves through interconnected combat rooms. Combat is active: the player controls movement, aims spells, dodges enemy attacks, chooses when to cast, and combines effects. Encounters provide currency, magical components, upgrades, or other progression rewards. Treasure/optional rooms and branching room choices are possibilities, not confirmed requirements.

Proposed room types: normal combat, elite/combat challenge, treasure, upgrade/rune reward, event, rest, and boss. Initially, a handful of handcrafted layouts assembled in randomized order may achieve variety faster than procedural terrain generation. Room entry/exits, encounter completion, and enemy telegraphs matter more than elaborate map generation for the first slice.

## 4.3 Stage pacing and run length — PROPOSED

A possible eventual run contains multiple dungeon regions with distinct enemies and bosses, taking around 30–45 minutes. An earlier brainstorm also contemplated 20–35 minutes. Neither number nor the number of biomes has been approved. The first prototype should be dramatically smaller: a short chain of combat rooms, a boss, and a workshop that demonstrates a complete adaptation cycle.

## 4.4 Why not a pure survivor format? — DECIDED / DIRECTION

The survivor format is attractive for rapid prototyping and spectacular automated builds, but frequent spell-construction pauses could interfere with uninterrupted wave survival. A dungeon crawler allows deliberate casting, positioning, elemental interactions, meaningful room-to-room decisions, and protected experimentation sessions. Survivor-style high-density action or triggered effects can still inform particular encounters or builds without defining the game’s genre.

# 5\. Combat Model

## 5.1 Core combat identity — DIRECTION

Combat should feel good even when the player has only simple spells. Responsive input, low ambiguity in hit detection, readable enemy attacks, sharp hit feedback, distinctive VFX, and meaningful movement/dodging are mandatory quality targets. The system should reward both a well-designed loadout and skillful execution.

## 5.2 Candidate player controls — PROPOSED, NOT LOCKED

Example PC keyboard/mouse mapping: left mouse button \= primary spell; right mouse button \= secondary spell; Q \= utility/special spell; Space \= dodge; mouse \= aim. Three configurable spell slots plus a dedicated dodge is a useful first prototype, not an agreed permanent limit. Controller support, additional slots, charge attacks, and spell switching are open.

## 5.3 Casting and spell roles — PROPOSED

All equipped spell slots should ideally use the same rune-construction system. The player could choose a projectile, an area control spell, and a defense; or could equip three offensive abilities. Avoid rigid classes that defeat the core creativity goal. Casting cadence may involve mana costs, cooldowns, cast time, charges, and/or global resource constraints; the exact model is undecided.

## 5.4 Enemies and bosses — DIRECTION / PROPOSED

Enemies need distinct movement patterns, attacks, spacing pressure, telegraphs, and vulnerabilities so that players have reasons to change magic. A proposed minimal selection is melee pursuer, ranged attacker, and mobile/dodging enemy. A boss should test both dodge/combat proficiency and adaptability of the chosen magical approach, without requiring a single puzzle-solution spell.

Environmental props such as destructible obstacles, wet zones, electrical crystals, or flammable objects could add tactical depth. These are illustrative optional affordances, not a commitment to full environment simulation.

# 6\. Magic Design: Conceptual Model

## 6.1 Arcane World inheritance — DIRECTION

The original Arcane World brainstorming used a conceptual grammar resembling Essence → Form → Behavior → Target/Relationship → Conditions. ArcaneDungeon’s more combat-oriented candidate taxonomy is Essence, Manifestation, Modifier, and Trigger. These are compatible viewpoints, not a fully reconciled schema. The final spell language remains OPEN and should be defined before large-scale implementation.

## 6.2 Candidate rune families — PROPOSED

ESSENCE / ELEMENT: fundamental magical property or energy. Examples: Fire, Water, Ice/Cold, Lightning, Arcane, Force. An essence can define elemental damage, status application, visuals, and interactions.

MANIFESTATION / FORM: how energy exists in space. Examples: Projectile, Beam, Area, Orb, Barrier, Cone.

BEHAVIOR / MODIFIER: how a construct behaves or is transformed. Examples: Split, Homing, Pierce, Orbit, Accelerate, Duplicate, Seek.

TRIGGER / CONDITION: when a later action executes. Examples: On Hit, On Contact, On Expire, On Death, After Delay, On Kill.

PAYLOAD / NESTED EFFECT: what another operation spawns or executes on a trigger. Examples: Explosion, Lightning Arc, Summon Orb, a second spell formula.

These examples should not be interpreted as a finalized rune inventory. Certain terms overlap, e.g. Lightning Arc may be a manifestation plus an element rather than an atomic rune; Orbit may be a behavior rather than a manifestation; and On Death needs a specific event owner. A clean semantic model is required.

## 6.3 Core creation experience — DECIDED / DIRECTION

Players collect magical components and assemble or reorder them into spell formulas. Replacing a component should change how a spell behaves, not merely its attack multiplier. For instance, a Fire \+ Sphere \+ Projectile combination behaves differently when Projectile is replaced with Orbit, or when Split or Homing is added. The executor should interpret combinations generically wherever possible.

Example 1 — Fire \+ Projectile \= direct fire shot.

Example 2 — Fire \+ Projectile \+ Homing \= tracking fire shot.

Example 3 — Fire \+ Orbit \+ On Contact \+ Explode \= orbiting explosive flame.

Example 4 — Water \+ Projectile \+ Pierce \+ On Hit → Lightning Arc \= piercing water effect with linked electric discharge.

Example 5 — Fire Projectile \+ On Hit → \[Explosion AND Summon Lightning Orb\] \= branching nested spell formula. All are EXAMPLES; their exact mechanics and validity depend on the formal magic grammar.

## 6.4 Formula ordering and composition — OPEN

Two potential user-facing modes have been discussed. Structured construction: Essence → Manifestation → Modifiers → Triggers, easier to teach, validate, and balance. Composable instruction system: CREATE PROJECTILE → APPLY FIRE → DUPLICATE → ON COLLISION → SPAWN EFFECT, closer to an event graph or a small visual programming language. The current preferred proposal is to prototype a structured visual editor over a reusable operation/event runtime, leaving future room for branching and more open graphs.

Open semantics: Does rune order alter results? How do modifiers select their target? Can a trigger have multiple outputs? Can generated effects themselves own triggers? Can formulas summon autonomous constructs? What does an invalid combination look like? How are inherited elemental properties applied? These decisions cannot be guessed silently by implementation agents.

## 6.5 Nested and cascading effects — DIRECTION / PROPOSED

A compelling advanced example is Fire Projectile → On Hit → Explode and Summon Orb → Orb automatically seeks targets and casts Lightning. Another is a resonance artifact that gains charge when Fire hits and automatically activates a linked spell at a threshold. Such systems are inspired by Noita and Spell Disk and could create highly creative builds, but must be gated in complexity during development.

The player should be able to discover spectacular or unexpectedly strong synergies. Safety and performance constraints are still necessary: event budgets, finite recursion depth, number-of-spawns caps, lifetime limits, and readable behavior. These should be designed as understandable magical rules rather than invisible arbitrary failures.

# 7\. Magical Interactions Beyond a Single Spell

## 7.1 Two layers of combination — DIRECTION

Layer A: within a spell, runes define an authored formula (for example Fire \+ Projectile \+ Split). Layer B: across independent spells, elemental states and target properties interact (for example Water to apply Wet, then Lightning to chain through Wet enemies). Both layers reinforce the fantasy of understanding magic.

## 7.2 Candidate semantic states — PROPOSED

Wet: can alter conductivity or freezing interactions.

Burning: damage-over-time and interactions with flammable targets.

Chilled / Frozen: movement restriction, possible creation of Brittle state.

Charged: may conduct, arc, or discharge based on rules.

Brittle: vulnerable to impact/Force damage.

Other future ideas: soaked ground, ignited surfaces, summoned wards, conductive props.

Illustrative combinations: Water Burst → Wet; Lightning Bolt → jumps among Wet targets; Frost Field → freezes Wet targets; Force Blast → knocks a Brittle target into an obstacle for shatter damage. These must be deterministic and testable in an early version. Avoid implementing a continuous fluid, heat-transfer, or pixel-material simulator.

## 7.3 Environment interaction level — OPEN

Minimal: states only on enemies. Intermediate: enemies plus a few tagged props and floor areas. Advanced: persistent elemental fields, surfaces, and destructibility. Proposed prototype target is minimal-to-intermediate; choose the smallest simulation that produces visibly meaningful synergies.

# 8\. Spell Constraints, Balance and Readability

## 8.1 Candidate limitations — PROPOSED

Mana / energy: controls cast frequency or sustained effects.

Complexity or slot budget: caps the number/weight of runes and sub-effects in a formula.

Cooldown / cast time: distinguishes rapid spells from high-impact spells.

Trigger constraints: cap recursive loops, spawn count, chained activations, and active summons.

Equipment or artifacts: change budgets, enable additional links, or alter resource behavior.

Illustrative values from early brainstorming: Basic Fireball mana 10 / complexity 1 / stability 100%; elaborate recursive Lightning Storm mana 90 / complexity 8 / stability 65%. These numbers were not playtested and must NOT be used as defaults.

## 8.2 Stability model — explicitly unresolved

An earlier concept proposed a spell Stability value where complex magic might fail or produce unexpected behavior. Later discussion favored initially avoiding randomized instability so the player can reproduce experiments reliably. Current recommendation: deterministic outcomes for the prototype; revisit instability as an optional mechanic later, if it adds meaningful choices. Do not implement random misfires as an assumed feature.

## 8.3 Balance philosophy — DIRECTION

Avoid balancing everything as flat \+damage upgrades. Mechanical differences—travel pattern, shape, target selection, trigger condition, resource consumption, duration, and synergies—are more important. Embrace some overpowered late-run combinations so creative discovery feels satisfying, while keeping a finite and performant simulation. Challenges should vary enough that a single formula is not optimal for every situation.

# 9\. Loot, Economy and Progression

## 9.1 Reward categories — DIRECTION / PROPOSED

During a stage, the player can encounter magical runes, equipment/artifacts, currency, upgrades, and unlockables. Bosses provide a major reward and passage to the next workshop. The exact choice mechanics (random drop, three-way pick, shop prices, rarity) are OPEN.

A useful distinction: a rune unlocks a new action the player can express; an artifact changes how existing actions work or interact; a conventional upgrade increases numeric effectiveness or available budgets. Prioritize new possibilities over passive percentage boosts.

## 9.2 Permanent versus per-run progression — PROPOSED

Conceptually separate permanent magical knowledge (discoveries, a Compendium, saved formula blueprints) from per-run access to components (runes, artifacts, currency, immediate upgrades). A player may know how to build a prior formula but still need to find its runes during a new run. This preserves discovery and replayability.

No final decision exists on metaprogression. Alternatives include knowledge-only unlocks, a limited persistent rune pool, or selective persistent power. Avoid building a large permanent progression tree without a clear design choice.

## 9.3 Spell Compendium — PROPOSED

A saved spell record might contain a player-provided name, ordered component graph, semantic version/schema version, rune requirements, optional notes, and perhaps test statistics. Example name: Thunderstorm V3. The Compendium remembers blueprints between runs for reference or later reconstruction. Whether the player can import immediately, share spells, or use a search/tag browser remains OPEN.

# 10\. The Arcane Workshop

## 10.1 Workshop purpose — DECIDED

After each boss, the player reaches a safe location combining a shop with a customization space where they can experiment with rune combinations. This is a core part of the game loop and should feel like a rewarding creative intermission, not an obligatory menu.

## 10.2 Core stations and functions — DIRECTION / PROPOSED

Merchant: purchase runes, artifacts, additional capacity, or general upgrades using dungeon-earned currency.

Spell editor: inspect rune inventory, build/modify formulas, understand requirements, see estimated costs and limitations, and assign spells to slots.

Testing arena: test spells against dummy targets or simple spawned enemies without jeopardizing a run. Feedback could include damage, projectile count, duration, targets hit, trigger frequency, and resource costs.

Compendium: browse discovered runes, save named spell formulas, and inspect known interactions.

## 10.3 Between-room modifications — PROPOSED

An important concern is pacing: finding a rune early but being forced to wait for a distant boss to test it may feel frustrating. Suggested compromise: limited/basic edits between cleared rooms; unrestricted rearrangement, purchasing, and extended testing in the post-boss workshop. Exact restrictions and access points are OPEN.

## 10.4 Example workshop interaction — EXAMPLE

The player buys Lightning after a boss, adds On Hit → Lightning to an existing Split Fire Projectile, tests it, notices that split projectiles each trigger a discharge, saves the resulting formula, and enters the next dungeon with a materially different fighting style. The purpose of the example is to illustrate the reward of invention and immediate validation.

# 11\. Dungeon Campaign, Content, and Variety

## 11.1 Dungeon generation — PROPOSED

Use a library of authored room templates with procedural connection/order, random encounters, and randomized rewards. Preserve readable paths, combat space, and boss pacing. Full procedural terrain and sophisticated world topology can wait.

## 11.2 Encounter variation — PROPOSED

Different enemy archetypes should stress different builds: quick dodge-capable enemies punish slow projectiles, armored enemies reward pierce/impact, clustered enemies reward area/chain, ranged enemies pressure movement, elemental resistances or hazards encourage adaptation. Telegraph clarity and fairness should take priority over complicated AI.

## 11.3 Bosses — DIRECTION

Bosses should punctuate dungeon stages and unlock the workshop stage. They ought to reward timing, movement, and intelligent magic, rather than demanding a single prescribed spell. Specific boss count, phases, mechanics, and artwork are uncommitted.

## 11.4 Campaign and death — OPEN

Not yet decided: whether the player restarts the entire campaign on death; whether workshops persist within a run; what carries across runs; whether stages form branches; whether completed regions can be revisited; whether the run has a final boss or endless mode. A traditional finite roguelite run is the current working hypothesis, not a binding decision.

# 12\. Visual and Audio Direction

## 12.1 Core look — DECIDED / DIRECTION

2D pixel-art, top-down action presentation. The magical effects must be exciting, legible, and expressive. Clear silhouettes, enemy readability, cast anticipation, impact feedback, and distinct elemental identities are particularly important.

Inspired by the level/campaign feel of Wizard of Legend, but no exact sprite resolution, palette, camera zoom, environment architecture, character proportions, or UI skin has yet been chosen. Do not import Battlemage Arena’s existing visual specifications wholesale without approval; it is a separate project.

## 12.2 Game feel requirements — DIRECTION

Candidate feedback channels: brief anticipation/cast pose; projectile trails; element-specific particles and glow; collision flashes; hit-stun or readable reaction; directional knockback where appropriate; brief camera shake on heavy hits; impact sounds; chained-effect clarity; responsive dodge animation; strongly differentiated fire, water, frost, lightning, and Force effects. Values and style should be tuned during combat prototyping.

## 12.3 Spell readability challenge — OPEN

Late-run builds may spawn many projectiles and nested effects. Establish VFX budgets, telegraph priority, visual layering, screen shake limits, performance targets, and accessibility options (flashes, shake, color dependence) before scaling up. More particles should not automatically mean better combat.

# 13\. Candidate Technical Architecture

## 13.1 Tool and engine direction — PROPOSED

Godot is the natural current implementation candidate given the user’s tooling and other game projects; this conversation did not explicitly finalize engine version, repository, deployment platform, or performance target. Godot 4 with reusable Resources and scripted executor nodes is a reasonable prototype hypothesis, not a confirmed engineering mandate.

## 13.2 Data model — PROPOSED

RuneDefinition: immutable ID, category, parameters, requirements, documentation, preview metadata, semantic operations.

SpellFormula: ordered components or a small graph, input/output edges, rune references, selected parameters, version, validation state.

SpellLoadout: equipped formula IDs per slot and relevant equipment modifiers.

SpellExecutionContext: caster, origin, direction, selected targets, elemental context, modifiers, seed, resource/budget handles.

EffectEntity: instantiated projectile/area/orb/barrier/summon with lifetime and event emission.

StatusComponent: per-target elemental states with application, expiration, resistance, and interaction rules.

TriggerEvent: typed OnHit/OnExpire/etc. event with source, target, context, and recursive depth.

ArtifactDefinition: event listener or conditional effect altering spell behavior.

Inventory/RunState: held runes, currency, artifacts, room completion, boss progress.

## 13.3 Generic runtime rather than bespoke spells — DIRECTION

A single projectile manifestation should carry different elemental payloads, modifiers, hit effects, and triggers. A new rune ideally extends the operation interpreter, not the permutation of every existing spell. Distinguish compile/validate time (is the formula legal, what does it cost?) from runtime execution (instantiate effect, dispatch events, resolve targets/states, spend resources).

## 13.4 Operational safety — DIRECTION / PROPOSED

Enforce deterministic semantics and hard limits on chain depth, event count, active projectiles, triggered casts, particle load, and summon count. Make the results debug-visible so designers can understand why a formula behaves as it does. Prevent an invalid or runaway formula from crashing the game. Save/load formats must version formulas so later rune evolution does not silently corrupt a saved blueprint.

## 13.5 Testing and observability — PROPOSED

Build a standalone magic sandbox before extensive campaign content. Prefer automated tests for rune validation, trigger ordering, status interactions, resource budgets, and serialization, plus in-engine visual tests for feel. Instrument per-spell effects, hit counts, activations, spawn counts, frame cost, and rune usage. In testing scenes, allow quickly swapping formulas without restarting combat.

# 14\. First Vertical Slice / Prototype

## 14.1 Core question — DECIDED / DIRECTION

Can players invent meaningfully different combat spells using a small reusable set of runes, and is experimenting with those spells genuinely fun during a short dungeon run? Prioritize answering this over constructing a full campaign.

## 14.2 Proposed first slice — PROPOSED

• One mage with responsive 2D movement, aim, dodge, and a few configurable spell slots.

• Approximately 12–15 runes as an upper-level initial planning example, not fixed scope.

• Core elements initially Fire, Water, Lightning; optional early Cold/Force after system validation.

• Simple linear formulas with one optional triggered payload; branching later.

• A small set of statuses such as Wet, Burning, Charged, with clear deterministic reactions.

• Three enemy archetypes with differentiated attack patterns.

• Five or six combat rooms and one boss as a candidate test run.

• A basic post-boss workshop with merchant, editor, and testing targets.

• Rune rewards, a basic currency loop, and enough variability to test different builds.

• Strong base spell audiovisual feedback, not final production art.

## 14.3 Prototype acceptance signals — PROPOSED

A player can construct several mechanically distinct useful spells from the same limited rune pool; a modifier visibly changes geometry/behavior, not just numbers; at least one cross-spell interaction is reproducible; swapping a rune works without custom spell code; the short combat loop is enjoyable with basic spells; boss-to-workshop transition works; experiments can be tested safely; invalid combinations are explained; worst-case combinations remain performant.

## 14.4 Suggested implementation sequence — PROPOSED, not a backlog

First establish the spell language, formula validation, and executor in a sandbox; then basic aiming, movement, dodging, and enemies; then status interactions and triggers; then editor UX and testing targets; then a short dungeon and boss; then rewards, merchant, and stage transition; finally tune game feel and run a playtest focused on creativity. This sequence describes dependencies only; task allocation and scope still require an approved backlog.

# 15\. Risks and Design Trade-offs

Combinatorial illusion: many nominal formulas might perform identically. Mitigate with distinctive behavior types, strong previews, and tests of whether choices alter player tactics.

Editor complexity: a powerful spell graph can resemble programming homework. Mitigate with progressive disclosure, safe defaults, visual connections, immediate previews, recommended starter formulas, and reversible editing.

Combat overshadowed by menus: long crafting intervals may hurt pacing. Mitigate with fast mid-run tweaks and a richer, optional deep workshop after bosses.

Simulation scope creep: realistic materials, persistent liquids, and world physics can consume the entire project. Favor target states and selective tagged props.

Automatic-trigger snowball: elaborate cascades can become unbounded or remove the need to play skillfully. Use transparent budgets and preserve manual-combat advantage.

Content burden: dungeon variety and bosses still require time even when spells are systemic. Start with small handcrafted arenas and reusable enemies; validate depth per room before expanding breadth.

Learning and balance: players may not know why a synergy occurred or failed. Provide event/interaction feedback, inspectable formulas, simple naming, and controlled testing targets.

Technical cost: projectile-heavy cascades plus VFX can cause frame drops. Profile and cap effects as part of the core engine.

# 16\. Working Decision Register

D-001 \[DECIDED\] Working title: ArcaneDungeon; not final branding.

D-002 \[DECIDED\] 2D pixel-art action game focused on combat-oriented spell experimentation.

D-003 \[DECIDED\] Dungeon crawler/explorer is preferred to a conventional Vampire Survivors-like structure.

D-004 \[DECIDED\] Development should be materially simpler and more iterative than building Arcane World itself.

D-005 \[DECIDED\] Core references are Spell Disk, Noita, Magicraft, and Wizard of Legend; Wizard of Legend informs campaign/level structure.

D-006 \[DECIDED\] Dungeons involve exploration, fighting, finding unlockables and upgrades, and a boss.

D-007 \[DECIDED\] After the boss, there is a shop/customization area where the player can experiment with spell combinations.

D-008 \[DIRECTION\] Created spells derive behavior from composable magical components.

D-009 \[DIRECTION\] Manual responsive spell combat with movement and dodging is favored over purely automated fighting.

D-010 \[DIRECTION\] The workshop and spell testing are important parts of progression.

D-011 \[DIRECTION\] Magic interactions can take place both inside a formula and between separate spells/statuses.

D-012 \[PROPOSED\] Formal rune families: Essence, Manifestation, Modifier, Trigger; reconcile with Arcane World grammar.

D-013 \[PROPOSED\] Three spell slots and example PC mapping; not locked.

D-014 \[PROPOSED\] Semantic elemental states instead of Noita-style pixel simulation.

D-015 \[PROPOSED\] Handcrafted room templates procedurally assembled.

D-016 \[PROPOSED\] Permanent Compendium and saved blueprints, but rune access resets by run.

D-017 \[PROPOSED\] Limited editing between rooms; full experimentation after boss.

D-018 \[PROPOSED\] Start deterministic; no randomized stability/misfire mechanic initially.

D-019 \[PROPOSED\] Godot 4 \+ resource-based spell formulas; engine and repository still to be officially set.

D-020 \[OPEN\] Formula grammar, validity, trigger semantics, balance budgets, and long-term campaign economy.

# 17\. Outstanding Design Questions

Q-001: What is the canonical spell representation—fixed rune slots, ordered operations, branching graph, or hybrid? Does ordering matter?

Q-002: Which 8–15 magical primitives offer the best variety for the first playable prototype? What interactions are first-class?

Q-003: What is the exact relationship between Essence/Form/Behavior/Target/Condition and Essence/Manifestation/Modifier/Trigger?

Q-004: How do the spell editor and in-dungeon edit UI work? Drag/drop, sockets, graph, textual formula, or other?

Q-005: Which combinations are valid, what are type constraints, and what feedback appears for invalid formulas?

Q-006: How are spawned effects, nested triggers, recursion, propagation, and target acquisition resolved?

Q-007: Does casting use mana, cooldowns, charges, per-spell slots, or a combination? How are costs calculated?

Q-008: Are spell slots fixed? Are defensive, utility, melee, and summoning builds equally supported?

Q-009: When exactly is spell editing allowed during the stage? What requires the post-boss workshop?

Q-010: Are runes permanently unlocked, run-limited, consumable, duplicated, leveled, or weighted by rarity?

Q-011: What persists through death: knowledge, blueprints, runes, currencies, or unlocks?

Q-012: What is the structure and length of the full run, including number of stages, bosses, and end condition?

Q-013: How much environment simulation is worthwhile before it distracts from combat?

Q-014: How much automated magic (Spell Disk-like) should be supported relative to manually cast spells?

Q-015: What are the art resolution, camera, HUD, input platforms, engine/repo, and release targets?

Q-016: How should player experiments be explained: testing sandbox, spell telemetry, compendium discoveries, tutorials?

Q-017: How can a boss test creativity without becoming invulnerable to unanticipated player builds?

# 18\. Coordination Guidelines for Agents

## 18.1 Document usage

Treat this document as design context, not as permission to implement all brainstormed ideas. Begin a workstream by citing the relevant sections and the decision status. If a feature is OPEN or PROPOSED, formulate an experiment or decision request before committing to an architecture that is costly to reverse. Maintain a separate implementation backlog; this document describes the game, not ticket ownership.

## 18.2 Suggested workstreams — PROPOSED

Game Design: define spell grammar and core balance; document status changes, encounter structure, progression, and workshop UX.

Magic/Engine: generic rune data model, validation, execution, trigger event system, status interactions, performance limits.

Combat: movement, aim/cast, dodge, hit reactions, enemy AI, boss prototypes, encounter pacing.

UI/UX: grimoire/editor, rune inventory, shop, compendium, tooltips, testing feedback.

World/Content: room templates, encounter layouts, environment props, progression regions, bosses.

Art/VFX/Audio: pixel-art visual language, element-specific effects, sound design, readability and performance budgets.

QA/Automation: automated formula tests, stress tests, gameplay smoke tests, visual checks, build verification.

## 18.3 Architecture boundaries and collaboration

Define clear contracts around SpellFormula serialization, RuneDefinition IDs, validation, runtime spell events, StatusComponent interfaces, resource cost callbacks, and VFX effect descriptors before delegating work to independent agents. Parallel work should share stubs and tests rather than each agent inventing its own incompatible spell format. Preserve upgrade paths through schema versioning, and keep gameplay simulation logic separate from rendering and editor UI.

## 18.4 Definition of a successful early prototype

The player can start a run, fight through a small room sequence with crafted spells, discover new runes, experience at least one meaningful emergent interaction, defeat a boss, visit the shop/workshop, modify and test a formula, and continue. The distinguishing success criterion is whether players repeatedly invent combinations with behavior they can predict, understand, and enjoy—not the amount of finished content.

## 18.5 Change-control convention

For future updates, mark each significant statement as DECIDED, DIRECTION, PROPOSED, OPEN, or EXAMPLE. Update the decision register when a choice is made; add a dated change note to this document; update related API/UX sections together; do not silently erase alternative approaches that remain relevant. Derived specs and backlogs should identify which baseline/version they use.

# 19\. Example Spell and Build Catalog (Illustrative Only)

Fireball: Fire → Projectile. Baseline aimable ranged attack.

Tracking Fireball: Fire → Projectile → Homing. Trades complexity/resources for reliability against mobile foes.

Tri-Fireball: Fire → Projectile → Split. Three paths for coverage, with possible on-hit interactions.

Flame Halo: Fire → Orb/Orbit → On Contact. Persistent close-range area denial.

Explosive Flame Halo: Fire → Orbit → On Contact → Explode. Converts protective orbitals into damage bursts.

Charged Water Lance: Water → Projectile → Pierce → On Hit: Lightning Arc. Applies Wet and electric follow-up.

Frost Nova: Cold/Ice → Area → Around Caster. Applies Chill or Freeze; can interact with Wet.

Force Cone: Force → Cone → Push. Defensive knockback and environmental impact.

Shattering Combo: Water Area → Frost Field → Force Blast. Demonstrates cross-spell state synergy.

Resonance Artifact Build: manual Fire hits fill an energy gauge; a linked Lightning spell auto-casts after threshold. Demonstrates Spell Disk-inspired automation.

Fire Summon Chain: Fire Projectile → On Hit → Explosion \+ Orb Summon → Lightning Seek. Advanced illustrative branching.

Each example is conceptual. No damage, hit count, mana value, or exact spell legality has been validated.

# 20\. Design History and Next Decision

Brainstorm phase 1: considered adapting Arcane World magic generation to either survivor-style action or dungeon-crawler combat, emphasizing rune/formula invention, environmental and cross-spell interactions, and knowledge-driven progression.

Brainstorm phase 2: project owner explicitly favored a smaller combat-first game rather than Arcane World’s exploration/noncombat emphasis; expressed that a dungeon crawler would probably better support this than pure survivor gameplay; named Spell Disk, Noita, Magicraft, and Wizard of Legend as reference games; proposed combat dungeons followed by boss, shop, and dedicated spell customization/testing.

Brainstorm phase 3: fleshed out candidate spell editor, manual combat, progression, workshop, boss/dungeon structure, and a Godot-friendly prototype approach. These elaborations are documented here with proposal labels, not misrepresented as locked requirements.

Next design priority: formally define the minimum spell language and its interaction rules. In particular, decide what a rune represents, how rune order/attachments work, how a formula is executed, how an effect triggers another, and how players see/test the result. Validate that small system in a magic sandbox before expanding the dungeon campaign.

SOURCE NOTES

Primary source: the ArcaneDungeon brainstorming in this project through 20 October 2026\. External inspiration references: Wizard of Legend (https\://wizardoflegend.com/), Noita (https\://store.steampowered.com/app/881100/Noita/), Magicraft (https\://store.steampowered.com/app/2103140/Magicraft/), Spell Disk (https\://store.steampowered.com/app/2292060/Spell\_Disk/). No external source should supersede owner decisions.

CHANGE LOG

2026-10-20 — v0.1 baseline: consolidated brainstorming into a cross-agent living design document. No implementation decisions beyond the status register were newly approved by creating this document.

