# ArcaneDungeon — Art Reference and Asset Creation Guide

## Canonical visual reference

**Required reference image:** [art_style_reference.png](assets/art_style_reference.png)

Repository-relative path: `docs/assets/art_style_reference.png`

This existing PNG is the visual reference for ArcaneDungeon's future assets. Open it directly and inspect its shapes, silhouettes, proportions, shading, textures, palette relationships, density and readability **before** generating sprites, animations, effects, icons, UI artwork or environment tiles. Do not assume its palette, tile dimensions, sprite resolution or detailed aesthetic properties without examining it. Do not edit or replace the reference PNG without explicit approval.

## What is decided versus not yet specified

- **Decided:** 2D, top-down, pixel-art presentation; combat-first roguelite focused on crafting and combining magic.
- **Visual priority:** legible characters, enemy telegraphs, spell trajectories, impact areas and statuses while moving and dodging.
- **Not yet specified in the gameplay backlog:** exact base sprite dimensions, tile size, palette swatches, animation FPS/frame counts, export sheet format, UI component kit and VFX visual treatments.
- **Reference hierarchy:** approved art specifications/owner decisions (when available) + the reference PNG govern visuals; the gameplay backlog governs mechanics. Inspiration from other games is not permission to silently replace the project's reference.

Record assumptions and options for missing art specifications rather than introducing purportedly final standards.

## Workflow whenever art generation is explicitly assigned

1. **Review the reference:** inspect `docs/assets/art_style_reference.png`, plus any approved art brief and relevant gameplay context. Note characteristics that are actually visible; separate observations from interpretations.
2. **Define the deliverable:** category (character, enemy, tile, projectile, explosion, HUD icon, etc.), required animations/states, target render scale and gameplay readability. Confirm unresolved dimensions/palette requirements or label prototypes provisional.
3. **Create consistent, editable sources:** prefer Aseprite source files (or other agreed editable source formats) for pixel-art sprites, then export PNG/spritesheets. Use tools available to the execution environment; do not assume an app was run unless it was.
4. **Document game-ready details:** source/export paths, dimensions, frame ordering/timing, pivot/origin, collision-independent dimensions, intended filtering and any import instructions.
5. **Integrate without changing semantics:** effects and visuals should subscribe to simulation events, not become the source of game rules. Test scale, visual clarity and layering in Godot once a project exists.
6. **Compare the result with the reference:** check silhouette, shape language, shading density, relative saturation, texture density and overall consistency at native pixel size and in actual gameplay.
7. **Report:** describe assets generated, locations, intended use, source format, exports and any deviations or visual decisions requiring approval.

## Technical cautions for 2D pixel art

- Prefer crisp pixel-aligned artwork and nearest-neighbor texture sampling when they match the approved style. Verify Godot texture import/filter and scaling on actual assets instead of assuming.
- Avoid accidental smoothing, inconsistent mixed pixel densities, clipped sprite frames or inconsistent pivots across animations.
- Separate collision/hitbox geometry from sprite artwork. Keep gameplay, UI and VFX legible over the intended environment.
- Keep assets reusable and named consistently. Once the Godot project is initialized, establish a documented directory convention for editable sources versus imported exports; do not invent existing paths now.
- Do not add detailed final art to satisfy gameplay-only tasks. Placeholder shapes/text/debug particles are acceptable and explicitly in scope.

## Relationship to implementation

- **Gameplay backlog:** [backlog_v1.md](backlog_v1.md). It explicitly excludes final art creation for the initial gameplay prototype. Refer to its task acceptance criteria for gameplay feedback needs.
- **Agent instructions:** [../AGENTS.md](../AGENTS.md).
- **Future detailed art specification:** a separate approved art workstream can add sprite sizes, palettes, sheets, UI component guidelines and animation requirements while retaining this reference as the shared anchor.

If the reference cannot be opened in the current environment, record that limitation and avoid claiming a faithful style match.