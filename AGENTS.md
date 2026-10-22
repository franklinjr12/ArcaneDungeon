# ArcaneDungeon — Agent Instructions

These instructions apply to the whole repository. Read this file before making changes. Use `docs/README.md` as the navigation index.

## Project identity and current scope

ArcaneDungeon is a **2D, top-down, pixel-art, combat-first dungeon roguelite** about inventing and combining spells. The core loop is: fight through rooms, earn new runes, defeat a boss, then visit a safe workshop/shop/testing area to revise magic before continuing. Skillful movement, aiming and dodging remain important even when spells become powerful.

M0–M3 are now implemented as proposed **magic debugging sandbox + combat arena + short vertical slice**: deterministic spells, elemental reactions, movement/dodge, three enemies, three rooms, mini-boss, seeded reward choices, merchant, safe workshop, transactional spell editor and stage-two entrance. Read `docs/M3_vertical_slice.md`. Inspect current files before editing. M4 TASK-049–053 engineering tests, profiling, opt-in local telemetry and onboarding are implemented; human playtesting TASK-054 is deliberately deferred until separate owner-commissioned sprites, and owner go/no-go TASK-055 remains pending. Read `docs/M4_validation.md` and the pending decision record. An owner-requested reference-guided first art pass (sprites, tiles, effects, UI) is now integrated; production polishing/owner visual approval remain pending. Read `docs/ART_IMPLEMENTATION.md`.

## Required sources and authority

1. **Game design decisions:** [ArcaneDungeon living GDD](https://docs.google.com/document/d/1fYI_7zgrL-xbm4WV52z6mimLcU6s_N8HKZKPppVY6_0/edit). The GDD is the design authority; if access is unavailable, work only from local documented decisions and disclose what could not be verified. You also have a offline copy of this document at `docs\Game Design & Project Reference.md`.
2. **Gameplay implementation plan:** `docs/backlog_v1.md` (v1.0, 2026-10-22). Follow the relevant `TASK-XXX` goal, dependencies, requirements and acceptance criteria. This backlog is a **proposal**, not blanket approval for every design choice.
3. **Magic system inspiration (not a feature checklist):** [Arcane World — Magic and World Interactions](https://docs.google.com/document/d/13l4Aqtsrp0f47Uuj-7BatHlrwJv7RlUCY2HO92KQCng/edit) and [Arcane World — World Knowledge](https://docs.google.com/document/d/1PSme3lsfFgC6T2nVckuKikEATj0A-CcFZodu8q1Ae4U/edit).
4. **Visual reference:** `docs/assets/art_style_reference.png`; instructions: `docs/art_direction.md`. **Inspect the image before any asset-creation work.**
5. **Versioned magic contract:** `docs/architecture/magic_contract_v1.md`, created for `TASK-003`; follow it for shared spell semantics and APIs.

Use the source labels as written in the backlog:
- **[DECIDED]** established product direction.
- **[DIRECTION]** guiding design principle, not necessarily an exact implementation.
- **[PROPOSED FOR PROTOTYPE]** useful initial constraint, subject to owner approval.
- **[OPEN]** unresolved: present tradeoffs and record decisions; never invent permanent rules.
- **[OUT OF SCOPE]** exclude from the gameplay prototype unless specifically authorized.

If sources disagree, avoid quietly changing mechanics. Record the discrepancy and request an owner decision when necessary. Do not convert examples, placeholder numbers, or hypotheses into approved game design.

## Implementation roadmap

- **M0 / TASK-001–010:** Godot bootstrap, headless tests, versioned spell definitions/contracts, compiler, event queue, trace.
- **M1 / TASK-011–025:** implemented prototype magic sandbox, manifestations/modifiers, bounded On Hit, elemental states and cross-spell reactions. `docs/M1_magic_sandbox.md` explains current behavior and how to test.
- **M2 / TASK-026–035:** implemented movement/dodge, combat damage, enemies, arena, HUD and prototype tuning. Consult `docs/M2_combat.md` and the replay seed fixture.
- **M3 / TASK-036–048:** implemented proposed linear short run, boss, shop/workshop, spell editor, run state and automated full-route tests. See `docs/M3_vertical_slice.md`.
- **M4 / TASK-049–055:** TASK-049–053 coding implemented; TASK-051 on-hardware FPS sign-off still pending; TASK-054 human sessions deferred by owner until sprite work; TASK-055 decision unapproved. See `docs/M4_validation.md`.
- **POST / TASK-056–061:** gated proposals only. Never start without explicit go/no-go approval.

Work on one `TASK-XXX` or a tightly coupled pair per change set. Check dependencies before proceeding. Do not mark an acceptance criterion complete without evidence. Keep implementations as small as possible while providing reproducible behavior.

## Provisional engineering constraints (from backlog v1)

- **Engine:** Godot 4.x is proposed, not yet pinned. `TASK-001` must select/document the tested minor version and renderer. Target keyboard/mouse first; controller support is still open.
- **Initial magic:** two manual spell slots; Fire, Water, Lightning essences; Projectile, Burst, Orbiting Orb manifestations; Homing, Split, Pierce modifiers; one On Hit trigger. These are prototype limits, not a final production cap.
- **Spell data:** stable rune IDs; schema-versioned `SpellFormula` with `EffectSpec`; strict JSON codec; central registry, validator and compiler. Invalid or locked formulas must never cast. Compiled plans must remain immutable during active casts.
- **M1 attachment rules:** Homing/Split/Pierce only for Projectile; On Hit only on Projectile, requiring an explicit Burst payload with its own essence; no nested trigger or unrestricted graph. Modifier order is stored but runtime phases are fixed in v1.
- **Events and safety:** resolve collisions through typed events, never recursively cast in collision callbacks. Apply configurable per-cast/global effect and event budgets; log `budget_exceeded` without freezing the game.
- **Interactions:** Fire applies Burning; Water applies Wet and extinguishes Burning; Lightning striking Wet can arc **once** to the nearest other Wet target. Do not hard-code named spell combinations; resolve from target states and elemental payloads.
- **Determinism:** fixed-tick simulation, run-seeded RNG, stable IDs and tie-breaks, normalized traces. Simulation must not depend on rendering or final art.
- **Architecture:** respect the backlog's shared API boundaries (`RuneRegistry`, `SpellValidator`, `SpellCompiler`, `SpellRunner`, `MagicEventQueue`, `InteractionResolver`, `RunState`, `SpellCodec`). Suggested locations include `res://game/core/`, `res://magic/{data,compile,runtime}/`, `res://combat/`, `res://world/`, `res://ui/`, `res://debug/`, `res://tests/`. The M0–M4 code directories now exist.

See `docs/backlog_v1.md` for detailed contracts, examples, legality rules, exact task acceptance criteria, and regression scenarios. Do not rely on this short summary instead of the full task specification.

## Visuals and art-generation rules

- **Current art implementation:** `docs/ART_IMPLEMENTATION.md`, `art/source/`, `art/aseprite/` and `assets/pixel/`. The first pass is editable/provisional, not final owner art approval.
- **Single local visual anchor:** `docs/assets/art_style_reference.png` (relative to repo root), supported by `docs/art_direction.md`.
- Whenever a task includes sprite, tile, character, enemy, icon, animation, effect, or UI-asset creation, **open and study that PNG before generating any assets**. Do not invent a fixed palette, sprite dimensions or aesthetic details that have not been established by the reference or an approved art specification.
- The **gameplay backlog intentionally excludes final art, animation, VFX and audio production**. The user has now explicitly assigned the sprite-art workstream; it has generated the first pass. This does **not** authorize launching M4 human playtests, recruitment, contract v2, or the owner go/no-go process. For gameplay-only tasks, retain the existing reference-inspired assets without adding mechanics. Future final art edits belong to explicitly assigned art work. Final asset generation belongs to a separately assigned art task/workstream.
- When art is explicitly requested, use repeatable source/export workflows (e.g., Aseprite for pixel art when available), preserve editable sources and document export layout, frame sizes, pivots, animations and Godot import settings. Keep visual outputs consistent with the reference.
- Visual work must not change collision/health/spell semantics. Test at in-game scale. See `docs/art_direction.md`.

## Agent execution and quality bar

1. Inspect the current repository and source documents. Note missing prerequisites and pre-existing uncommitted work; do not delete or overwrite unrelated work.
2. Identify the assigned `TASK-XXX` IDs; read full requirements, acceptance criteria and dependencies before editing code.
3. Implement against shared contracts; avoid duplicate spell models/resolvers, bespoke elemental spell classes, and hidden hardcoded combinations.
4. Add or update deterministic tests and fixtures with the feature. Run `python scripts/validate_godot.py --godot <path-to-godot>` to check parser, scene navigation, M1 sandbox UI, M2 combat UI, M3/M4 UI and full route, M4 stress profiler, suite, baseline replays, and failure detection; never report tests as passed without running them.
5. Provide reproduction/demo steps, parser/runtime errors when applicable, and describe how each acceptance criterion was verified. If you cannot run a test, say why.
6. In the handoff/PR include: task IDs, changed files, tests/results, schema/API changes, assumptions labelled as proposed, and unresolved owner decisions.
7. Avoid committing generated runtime caches, temporary harness artifacts, secret tokens, or unrelated files. Do not silently update the GDD, implementation backlog or baseline art reference.

Preferred local tooling where connected: Indie Game Harness (IGH) for project inspection, Godot tasks and reproducible runs; Aseprite for sprite creation; Blender only when a task requires it. Never claim tool operations or file changes without checking results.

## Design references and boundaries

Wizard of Legend informs active top-down combat; Magicraft informs modular spell construction; Noita informs modifier/trigger possibilities **without** large-scale material physics; Spell Disk informs bounded event-driven combinations **without** replacing manual combat. Arcane World informs semantic magic interactions, not VR gesture casting or a full world simulation.

Success means a small, playable, understandable spell-invention prototype, not a broad content expansion.