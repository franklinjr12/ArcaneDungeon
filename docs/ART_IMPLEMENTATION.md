# ArcaneDungeon — Reference-Guided Art Implementation

**Status:** First playable art pass integrated with Godot using IGH and Aseprite. Art style, sizes, palette, frame counts and animation timings are provisional pending owner review. Existing combat rules, spell grammar, collision and progression are unchanged.

## Canonical reference

Keep docs/assets/art_style_reference.png as the visual source of truth. The uploaded image has the same decoded RGB pixels as that existing file; it was neither altered nor replaced.

The image visibly uses near-black/navy interfaces, worn amber-gold frame edges, compact detailed 3/4-view pixel-character silhouettes, layered stone/wood/green foliage, highly saturated blue/orange elemental attacks, rune symbols and readable HP/mana bars. This pass follows those color and shape relationships without claiming to match the board's illustrator-level finish.

## Assets generated and currently used

| Runtime file under assets/pixel | Grid | Role |
| --- | --- | --- |
| mage_sheet.png | 10 × 48×56 | Playable mage; idle, walk, cast, hurt, fallen |
| pursuer_sheet.png | 10 × 48×56 | Goblin pursuer / melee enemy |
| ranged_sheet.png | 10 × 48×56 | Dark ranged cultist |
| flanker_sheet.png | 10 × 48×56 | Wolf-flanker |
| boss_sheet.png | 10 × 104×112 | Rune-encrusted stone chimera mini-boss |
| dummy_sheet.png | 10 × 48×56 | Training dummy |
| spell_effects.png | 8 × 8 cells of 32×32 | Fire, Water, Lightning, Orb, hostile, arc, impact, dodge effects |
| rune_icons.png | 8 × 3 cells of 32×32 | Ten rune families plus status, health, mana, runes, coin, door, shield and other system icons |
| dungeon_tiles.png | 8 × 3 cells of 32×32 | Worn stone floor, carved walls and greener/moss variants |
| dungeon_props.png | 8 × 48×48 | Brazier, crystal, rubble, moss, torch, altar, fern, runestone; **nonblocking decoration only** |
| panel_frame.png, button_frame.png | 32×32 and 32×24 | Dark/gold framed UI |
| menu_background.png | 1280×720 | Moonlit castle with illuminated portal backdrop |

**Review image:** art/previews/art_overview.png (regenerate with python art/source/render_art_preview.py). This contact sheet shows character, effects, prop, icon, and terrain samples in one view.

## Editable source and repeatable export

The deterministic source generator is art/source/generate_pixel_art.py (requires Pillow). It creates every runtime PNG with crisp, integer-aligned pixels.

Editable originals are kept in art/aseprite/:

- mage.aseprite, pursuer.aseprite, ranged.aseprite, flanker.aseprite, boss.aseprite and dummy.aseprite: **10 frames**, tags idle (0–1), walk (2–5), cast (6–7), hurt (8), dead (9).
- vfx_fire.aseprite, vfx_water.aseprite, vfx_lightning.aseprite, vfx_orb.aseprite, vfx_enemy.aseprite, vfx_arc.aseprite, vfx_impact.aseprite, vfx_dodge.aseprite: 8-frame timeline with a cycle tag.
- dungeon_tiles.aseprite, dungeon_props.aseprite, rune_icons.aseprite, spell_effects.aseprite, panel_frame.aseprite, button_frame.aseprite, menu_background.aseprite: editable complete atlases.

Two scripts reproduce the Aseprite sources from exported baselines:

    python art/source/generate_pixel_art.py

    aseprite -b --script-param project=C:\Repos\ArcaneDungeon --script art/source/import_aseprite.lua
    aseprite -b --script-param project=C:\Repos\ArcaneDungeon --script art/source/import_atlases_aseprite.lua

These commands have been executed through the connected IGH Aseprite capability. Editing an Aseprite asset is permitted: **do not rerun the baseline generator over manually edited art unless intentionally replacing the changes.** For hand-painted changes export updated PNG spritesheets before opening Godot.

The machine-independent manifest files in art/source/ document the frame grid, VFX order, icon order and decorative props. Frame count, size and origin are provisional. Actor origins: bottom center, 7 px above base (24,49 for 48×56; 52,105 for 104×112). Frame selection uses simulation tick only to pick render frames; positions, physics and attack timing are still exclusively determined by gameplay code. No directional 4-way animation exists in this pass.

## Where the assets are integrated

- ui/pixel_art_renderer.gd: tile and prop layout; actor, status and spell atlas rendering. Draws visuals only.
- ui/combat_canvas.gd: reads M2/M3 combat entities and replaces placeholder colored circles with animation sheets. Preserves enemy telegraph geometry, damage indicators, health bars and debug overlay; suppresses short-range enemy labels outside debug.
- ui/sandbox_canvas.gd: displays mage, dummies, projectiles, statuses and chain arcs with the same assets. Existing M1 interactions unchanged.
- ui/run_canvas.gd: uses a fantasy portal exit and rune pickup symbol instead of placeholder circles.
- ui/pixel_theme.gd: shared antique gold frame borders, dark panels and button treatment.
- ui/pixel_hud.gd: portrait, active HP/mana bars and two equipped spell icons/costs.
- ui/run_controller.gd: shared theme and the current (real, validated) formula icons in editor choices.
- ui/main_menu.gd: background illustration; preserved launcher controls.
- ui/combat_arena_controller.gd and ui/sandbox_controller.gd: shared visual theme.
- tests/test_pixel_assets.gd: imported image dimensions, genuine frame differences, Aseprite source presence, theme and canonical reference checks.

Effects are read from the existing M1 SpellRunner visual event stream. Decorative props remain **non-interactive and non-solid**; no false collision geometry or reward behavior was added.

## Validation

Run:

    python scripts/validate_godot.py --godot "C:\Users\sa-su\Documents\Godot\Godot_console.exe"

The regression covers Godot parser/import, all scene navigation and UI smoke tests, original spell/combat/run tests, pixel asset import and the stress probe. A graphical Godot game window was also launched to inspect appearance at the actual 1280×720 window scale. Aseprite frame/tag validation passed for character and effects sources.

## Explicitly outside this art pass

The uploaded board includes several playable classes, bosses, equipment systems, inventory, bestiary, journal and biome options which the **current ArcaneDungeon game does not implement**. This execution creates art for all current gameplay categories, not fictitious art for unapproved mechanics. The asset pass is not a claim of final studio-polished textures or a perfect recreation of the reference.

Owner review is still needed for more intricate character detailing, directional animations, richer boss poses, unique room compositions, VFX timing and final palette/render-scale choices. The previously deferred first-human playtest (TASK-054), decision gate (TASK-055) and any new magic features remain pending.

## AD-065 actor animation import

- **Source rows:** mage AD-061, AD-062, AD-064; fallen adept AD-053 + AD-063; grave hound AD-054 + AD-063; Undead warden AD-055 + AD-056 + AD-063 (`main` sheet) and AD-064 (`late` sheet); bone thrall AD-052. Tag names, frame counts and per-frame ms come from the Art 02 cards and are recorded in `art/export/actors/actors_manifest.json`.
- **Import:** `python3 scripts/import_art_exports.py --actors` writes `art/export/actors/` and the manifest.
- **State -> tag:** mage idle/walk from velocity, facing from aim (3 directions, side mirrored), cast on cast event, dash for the dash window, hit on damage, death at HP 0. Enemies/warden: idle, move, telegraph, attack, hit, death, spawn from the AI state. Sprites draw at scale 2.
- **Telegraph stretch:** the telegraph tag is stretched/held to exactly `telegraph_ticks` (warden: `windup_ticks` / `second_phase_windup_ticks`) from data so the read and the hit line up. Sim timing is never changed.
- **Hurtbox-centre anchoring (PROPOSED):** the centre of the art hurtbox slice is drawn on the sim position.
- **Hurtbox radii (PROPOSED rule):** `radius = ceil((w + h) / 2)` of the hurtbox slice (= mean(w, h) * scale 2 / 2); raised only if larger than the current radius. Player radius stays 17.

  | actor | slice w x h | old -> new radius |
  |---|---|---|
  | bone_thrall | 20x25 | 19 -> 23 |
  | fallen_adept | 18x27 | 18 -> 23 |
  | grave_hound | 27x18 | 17 -> 23 |
  | undead_warden | 44x53 | 35 -> 49 |

  Edited: `combat/combat_tuning_v1.json` `enemies.<kind>.radius`, `world/data/vertical_slice_v1.json` `boss.radius`. Regenerated: `tests/fixtures/m2_baseline_v1.json` (via `tests/m2_baseline_probe.gd`; ticks/hits shift only because targets are bigger). M1 magic goldens are untouched. `tests/test_ad_audio.gd` got a scripted dash-through-hit so the `sfx.dash.iframe` cue is still covered (the autoplay route no longer hit it by chance).
- **Debug overlay:** with `show_debug` on, `ui/combat_canvas.gd` draws the sim radius (magenta arc) around the mage and every live enemy/warden.
- **Capture (developer only):** `xvfb-run -a /usr/local/bin/godot --path . --script res://tests/capture_actor_anim.gd -- /tmp/ad065_captures` writes a scale-2 frame strip per actor per tag and one in-play shot per actor with the overlay. Outputs are not committed.
