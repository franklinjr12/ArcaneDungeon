# Ruins room pool (AD-128)

Room design rules (obstacles, interactions, shapes, spawns, dead corners; AD-202): [ROOM_RULES.md](ROOM_RULES.md).

Data: `world/data/rooms_ruins_v1.json` (stage `ruins`). Validator: `world/room_template.gd`. Tests: `tests/test_ad_rooms.gd`.
Screenshot sheet of all layouts: [ruins_layouts.png](ruins_layouts.png) (schematic render of the JSON: blue = entrance and 160 px spawn ring, yellow = reward, green = exit, circles = props, dots = enemies — white thrall, purple adept, orange hound; red outline = on-clear wave; pink diamonds = pedestals).

- **Pool:** `ruins_p01`..`ruins_p10`, combat rooms using only current enemies (`bone_thrall`, `fallen_adept`, `grave_hound`). New enemy rows add waves to these templates later.
- **Treasure:** `ruins_treasure_v1` — `pedestals` (artifact/rune) with `choice_count` 1; altar/chest props (AD-122 art).
- **Challenge:** `ruins_challenge_v1` — three waves, `elite` multipliers, `challenge_reward` knobs and an empty `mini_boss_slot` for later. All tunables live in the JSON.
- **Layout:** optional `layout.walls` ([x,y,w,h]) add obstacles to the shared arena walls; `layout.props` are decorative `[kind,x,y]`.
- **Rules** (`rules` block, data-driven): `min_spawn_distance` 160, `player_radius` 22, `grid_step` 20.

Validator checks (`Room.initialize`): required fields/type, scene, markers not blocked, spawn >= `min_spawn_distance` from entrance (default 45 when a template omits it), spawns not blocked, entrance→exit/reward/every spawn reachable (grid flood fill), treasure pedestals valid and reachable, challenge has elite/reward blocks.

Not yet wired: `run_flow.gd` still builds the run from `run_v2.json` templates and one shared arena; hooking this pool into the stage pool and rendering per-room walls is a follow-up. `name_key` strings were not added (i18n files are outside this task's area).

# Cistern room pool (AD-138)

Data: `world/data/rooms_cistern_v1.json` (stage `cistern`), loaded by `run_v2.json` through `room_template_files` (`RunFlow.merged_templates`). Validator: `world/room_template.gd`. Water rules: `world/water_tiles.gd`, `combat/combat_session.gd` (`set_water`). Tests: `tests/test_ad_cistern.gd`.

Screenshot sheet of all layouts: [cistern_layouts.png](cistern_layouts.png) (pool order, then treasure, then challenge; schematic at 1/5 scale). Legend as the ruins sheet, plus: light blue = shallow water, dark blue = deep water, grey = shared arena and layout walls, brown circles = props. Regenerate (headless, deterministic; same script renders any room JSON): `godot --headless --path . --script res://tools/room_layout_sheet.gd -- res://world/data/rooms_cistern_v1.json docs/rooms/cistern_layouts.png`.

- **Pool:** `cistern_p01`..`cistern_p10`, combat rooms using only current enemies (`bone_thrall`, `fallen_adept`, `grave_hound`); every room has water and at least four have deep channels that force a detour. Stage-2 enemies are added to these templates in a later row.
- **Treasure:** `cistern_treasure_v1` — two pedestals (artifact/rune), `choice_count` 1, shallow pools and a deep channel.
- **Challenge:** `cistern_challenge_v1` — two waves, `elite` multipliers, `challenge_reward` knobs, empty `mini_boss_slot`; it is the stage's `optional_room`. The old `cistern_c01`..`cistern_c08` and `cistern_challenge` placeholders in `run_v2.json` were removed.
- **Water schema:** `layout.water` is an array of `{"kind":"shallow"|"deep","rect":[x,y,w,h]}`. Touching or overlapping rects form one water body. Malformed entries give `WATER_TILE_INVALID` with path `layout.water[i]...`.
- **Rules** [PROPOSED FOR PROTOTYPE]: anyone standing in water (player and enemies) gets Wet every `water.wet_interval_ticks` (`combat/combat_tuning_v1.json`). Deep water blocks walking but not spells or sight. Lightning striking a target in water arcs once to the nearest other target in the same body within `combat.water_conduct_radius`. All numbers are data.
- **Validator:** deep rects count as ground blockers, so markers, spawns and pedestals in deep water fail with the existing codes, and so do exits or spawns cut off by a deep channel (`ROOM_EXIT_UNREACHABLE`, `ROOM_SPAWN_UNREACHABLE`). Rooms without water validate as before.
- **Run wiring:** `run_flow.gd` appends `layout.walls` to the live session walls and collision walls and calls `set_water` when a room has water.
- **Art:** water tiles, grates, pipes and pillars are placeholders until the art import row.

# AD-202 Ruins v2 layouts

Rules: [ROOM_RULES.md](ROOM_RULES.md). Before / after sheets: [ruins_rooms_before.png](ruins_rooms_before.png), [ruins_rooms_after.png](ruins_rooms_after.png). The 8 combat rooms and the treasure room in `world/data/run_v2.json` (`ruins_c01`..`ruins_c08`, `ruins_treasure`) each use a different shape. Regenerate the after sheet (headless): `godot --headless --path . --script res://tools/room_layout_sheet.gd -- res://world/data/run_v2.json docs/rooms/ruins_rooms_after.png --stage=ruins`.

| Room | Shape | Obstacles (walls / pits / solid props) | Interactions |
|---|---|---|---|
| `ruins_c01` | open_hall | sarcophagus, rubble | crate, brazier, cobweb |
| `ruins_c02` | pillared_hall | 4 pillars, cracked pillar | cracked pillar (Force), 2 urns |
| `ruins_c03` | ring_pit | 1 pit, rubble, sarcophagus, column | 2 puddles |
| `ruins_c04` | corridor_chamber | 2 walls, sarcophagus | broken wall (Force), 2 braziers |
| `ruins_c05` | cross_hall | 4 walls | crate, cobweb, urn |
| `ruins_c06` | split_bridges | 3 pits, rubble, sarcophagus, column | brazier, urn |
| `ruins_c07` | l_bend | 2 walls, column, rubble | cobweb, urn |
| `ruins_c08` | colonnade | 4 columns | 2 braziers, cobweb |
| `ruins_treasure` | dais_island | sarcophagus, 2 cracked pillars | 4 braziers, cracked pillars (Force) |

Results (2026-11-10): `demo_smoke.gd --seeds=20 --det-seeds=5` green, no failing seeds; `scripts/validate_godot.py --godot /usr/local/bin/godot` exit 0; `tests/test_ad_room_rules.gd` green. Bot bench numbers are INFO only.

Perf probe digest: `tests/qa/demo_perf_probe.gd` `BASELINE_DIGESTS["ruins_c07"]` was **not** recomputed. `ruins_c07` is not in the default seed's room sequence (`--rooms=ruins_c07` gives "room not in sequence"), and the `cistern_boss` / `ruins_boss` digests already differ in `--verify-digests` runs, so the baselines need a separate refresh by the perf owner. The probe is measurement only and is not part of validate or smoke.

# AD-203 Cistern v2 layouts

Rules: [ROOM_RULES.md](ROOM_RULES.md). Before / after sheets: [cistern_rooms_before.png](cistern_rooms_before.png), [cistern_rooms_after.png](cistern_rooms_after.png); the legacy per-template sheet [cistern_layouts.png](cistern_layouts.png) was regenerated too. The 10 combat rooms and the challenge room in `world/data/rooms_cistern_v1.json` each use a different shape. Regenerate the after sheet (headless): `godot --headless --path . --script res://tools/room_layout_sheet.gd -- res://world/data/run_v2.json docs/rooms/cistern_rooms_after.png --stage=cistern`.

| Room | Shape | Obstacles (walls / pipes / deep channels / solid props) | Interactions |
|---|---|---|---|
| `cistern_p01` | open_hall | 2 walls, 4 pipes | crate, puddle (conducts), 3 shallow pools |
| `cistern_p02` | pillared_hall | 4 walls, pillars | crate, cobweb, 2 shallow pools |
| `cistern_p03` | split_bridges | 2 walls, pipes, 3 deep channel segments | crate, puddle; two bridges between the segments |
| `cistern_p04` | corridor_chamber | 2 walls, pipes, 2 deep walls around the corridor | crate, puddle |
| `cistern_p05` | ring_pit | 3 walls, pipes, central deep pool | urn, brazier, puddle; eel in the shallow rim |
| `cistern_p06` | cross_hall | 2 walls, pipes, 4 deep arms | crate, urn; centre crossing |
| `cistern_p07` | eel_lanes | 2 walls, pipes, 2 long deep lanes | crate, cobweb; eels in the shallow lanes |
| `cistern_p08` | colonnade | 4 walls, pillars | puddle, cracked wall |
| `cistern_p09` | dais_island | 2 walls, pillar, pipes, 6 deep rects around the crystal-platform island | crate, brazier |
| `cistern_p10` | l_bend | 2 walls, pipes, one large deep block | puddle, crate |
| `cistern_challenge_v1` | flooded_arena | 3 walls, pillar, pipes, deep pool | brazier, puddle, 4 shallow pools (cistern_boss pools) |

Water vocabulary: **channels** are deep rects (block walking, not spells or sight); **bridges** are the floor gaps between deep rects, at least 80 u wide (board minimum 56 u); **grates** and **pipes** are `layout.props` cover; **puddles** are `env_props` that conduct lightning like shallow water; **eel lanes** are shallow strips between deep water (p05, p07) where eels stay; the **crystal-platform island** is the p09 centre; the challenge room reuses the `cistern_boss` pools for the mini-boss arena.

Results (2026-11-10): `demo_smoke.gd --seeds=20 --det-seeds=5` green (20/20 smoke, 6/6 determinism, no failing seeds); `scripts/validate_godot.py --godot /usr/local/bin/godot` exit 0; `tests/test_ad_room_rules.gd` green. Bot bench numbers are INFO only; no HP or tuning changed.

Perf probe: `tests/qa/demo_perf_probe.gd` baselines were **not** recomputed.
