# Room design rules (AD-202)

Source: Franklin feedback 2026-11-09 ("room design is raw") and Sigilwright Demo Plan §20. Every number and shape below is **[PROPOSED FOR PROTOTYPE]** unless it comes from the owner list. Thresholds are data: `world/data/run_v2.json` → `room_rules`. The checker is `Room.rule_report()` in `world/room_template.gd`; tests are in `tests/test_ad_room_rules.gd`.

## Rules

Every **combat** room, and the **treasure** room (except the spawn rules, since it has no waves), must satisfy:

1. **Obstacles:** 2-5 obstacle/cover pieces [PROPOSED]. Counted: `layout.walls` entries + solid env props (`solid_walk`: pillar, cracked_pillar, rubble, sarcophagus, broken_wall, column, crate, cracked_wall) + the 3 shared arena walls unless the room sets `layout.arena_walls` to `false`. Pits, water and non-solid props (cobweb, urn, puddle, brazier) are not counted. `RULE_OBSTACLES`.
2. **Environment interaction:** at least 1 prop from `env_props_v1` of kind `crate`, `cobweb`, `brazier`, `urn`, `cracked_wall`, `cracked_pillar`, `broken_wall` or `puddle` (burnable crates/cobwebs, braziers, breakable urns/walls, puddles). Plain cover (pillar, rubble, sarcophagus, column) does not count. `RULE_INTERACTION`.
3. **Shape:** exactly one `shape` id, stored as the top-level template field `shape`. `RULE_SHAPE`.
4. **Spawns away from the entrance:** every enemy spawn at least `min_spawn_distance` (160) from the entrance. `RULE_SPAWN_NEAR_ENTRANCE`. (`Room.initialize` keeps its own per-room `min_spawn_distance` check.)
5. **No dead corners:** on the grid of step 40 (`dead_corner_step`) for a body of radius 22 (`player_radius`), every walkable cell is reachable from the entrance (`RULE_POCKET_UNREACHABLE`), and no reachable cell has 3 or more of its 4 neighbours blocked (`RULE_DEAD_CORNER`). A neighbour is blocked when a body of that radius does not fit there (wall, pit, deep water, solid prop or arena edge).
6. **Props never block** entrance, exit, reward or spawns. Already enforced by `Room.initialize` (`ROOM_ENV_PROP_BLOCKS`, `ROOM_MARKER_BLOCKED`, `ROOM_SPAWN_BLOCKED`, `ROOM_*_UNREACHABLE`); no new code.

## Shapes

Owner list (5): `open_hall`, `pillared_hall`, `corridor_chamber`, `ring_pit`, `split_bridges`.
[PROPOSED] extras, needed because the Ruins stage has 9 rooms that must each differ: `cross_hall`, `l_bend`, `colonnade`, `dais_island`. AD-203 adds `eel_lanes` and `flooded_arena` because the Cistern needs 11 different shapes (10 pool rooms plus the challenge room).

| id | Meaning |
|---|---|
| `open_hall` | Big open floor, a few cover pieces scattered |
| `pillared_hall` | Regular grid of pillars/columns to weave through |
| `corridor_chamber` | Long corridor opening into a chamber |
| `ring_pit` | Walkable ring around a central pit |
| `split_bridges` | Room split by a pit/wall; bridges (gaps) join the halves |
| `cross_hall` | Two crossing halls; four arms |
| `l_bend` | L-shaped route with an inner corner |
| `colonnade` | Rows of columns along the long axis |
| `dais_island` | Raised central island ringed by cover |
| `eel_lanes` | Parallel deep-water lanes beside the walking lanes; eels lurk in them (AD-203 Cistern) |
| `flooded_arena` | Mini-boss arena that reuses the `cistern_boss` water features (AD-203 Cistern) |

## Obstacle schema

All fields live under a template's `layout`.

- `layout.walls`: `[[x,y,w,h], ...]` solid rects. Block movement and projectiles. Not breakable.
- `layout.pits`: `[[x,y,w,h], ...]` block walking only (like deep water); spells and sight cross them.
- `layout.arena_walls`: `false` drops the 3 shared arena walls from `combat/combat_tuning_v1.json`; omitted or `true` keeps them.
- `layout.env_props`: `[{id, kind, rect:[x,y,w,h]}` or `{id, kind, position:[x,y]}` for circle kinds`]`. Cover kinds (`world/data/env_props_v1.json`): `pillar`, `cracked_pillar`, `rubble`, `sarcophagus`, `broken_wall`, `column`; all are `solid_walk` and `blocks_spells`.
- **Force-breakable** = the kind has `break_by: ["essence.force"]` (`cracked_pillar`, `broken_wall`, also `cracked_wall`). A destroyed prop stops blocking walking and spells and drops its coins. Pillars, rubble, sarcophagi and columns are permanent. A room must stay valid with every breakable piece intact.

## Checking and sheet

`Room.rule_report(room, arena, env_data, rules)` returns `{ok, obstacles, interactions, shape, issues:[{code, message}]}`; codes: `RULE_OBSTACLES`, `RULE_INTERACTION`, `RULE_SHAPE`, `RULE_SPAWN_NEAR_ENTRANCE`, `RULE_DEAD_CORNER`, `RULE_POCKET_UNREACHABLE`. It is read-only and deterministic; it does not change `Room.initialize` verdicts.

Layout sheet of a stage (pool order, then the optional room):
`godot --headless --path . --script res://tools/room_layout_sheet.gd -- res://world/data/run_v2.json docs/rooms/ruins_rooms_before.png --stage=ruins`
Legend additions: near-black = pits; grey-brown = solid cover; orange = burnable (crate, cobweb); cyan = puddle; red = brazier; gold = breakable (urn, cracked wall/pillar, broken wall; Force-breakable cover keeps a cover-coloured outline); top-left square = shape (colour per shape id, black with red outline = no shape yet) followed by one tick per room position in the sheet.

`ruins_rooms_before.png` is the Ruins pool before the AD-202 rework: all 8 combat rooms share one layout and the treasure room has no cover.

## Art needs (for game-art)

Placeholders today, to be replaced (list for the AD-202 PR):

- Cover kinds `pillar`, `cracked_pillar`, `broken_wall`, `column` reuse the `cracked_wall` frames.
- `rubble` and `sarcophagus` reuse the rubble set or flat placeholders.
- Pits have no Ruins pit or pit-edge tiles.
- Bridge edge tiles (ruins_c06 split_bridges) are missing.
- The approved AD-217 Ruins cover art (intact/cracked pillar, rubble, sarcophagi, broken walls, with collision footprints) still needs wiring into `env_props_v1`. `art/arcane_dungeon/AD-217/` did not exist in this worktree, so it could not be checked or wired here.

Still missing for the Cistern (AD-203):

- The AD-219 r2 channel and bridge tiles and the AD-227 crystal platform and bridge decks (walkable 68x60 / 120x60 u; decks 56 u) are not wired. Today bridges are plain floor gaps and the island is plain floor.
- The AD-218 Cistern cover (pipes, grates) is still placeholder.
- The AD-099 r3 Cistern tiles.
