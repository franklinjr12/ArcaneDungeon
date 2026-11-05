# Ruins room pool (AD-128)

Data: `world/data/rooms_ruins_v1.json` (stage `ruins`). Validator: `world/room_template.gd`. Tests: `tests/test_ad_rooms.gd`.
Screenshot sheet of all layouts: [ruins_layouts.png](ruins_layouts.png) (schematic render of the JSON: blue = entrance and 160 px spawn ring, yellow = reward, green = exit, circles = props, dots = enemies — white thrall, purple adept, orange hound; red outline = on-clear wave; pink diamonds = pedestals).

- **Pool:** `ruins_p01`..`ruins_p10`, combat rooms using only current enemies (`bone_thrall`, `fallen_adept`, `grave_hound`). New enemy rows add waves to these templates later.
- **Treasure:** `ruins_treasure_v1` — `pedestals` (artifact/rune) with `choice_count` 1; altar/chest props (AD-122 art).
- **Challenge:** `ruins_challenge_v1` — three waves, `elite` multipliers, `challenge_reward` knobs and an empty `mini_boss_slot` for later. All tunables live in the JSON.
- **Layout:** optional `layout.walls` ([x,y,w,h]) add obstacles to the shared arena walls; `layout.props` are decorative `[kind,x,y]`.
- **Rules** (`rules` block, data-driven): `min_spawn_distance` 160, `player_radius` 22, `grid_step` 20.

Validator checks (`Room.initialize`): required fields/type, scene, markers not blocked, spawn >= `min_spawn_distance` from entrance (default 45 when a template omits it), spawns not blocked, entrance→exit/reward/every spawn reachable (grid flood fill), treasure pedestals valid and reachable, challenge has elite/reward blocks.

Not yet wired: `run_flow.gd` still builds the run from `run_v2.json` templates and one shared arena; hooking this pool into the stage pool and rendering per-room walls is a follow-up. `name_key` strings were not added (i18n files are outside this task's area).
