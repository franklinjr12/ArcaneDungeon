# Boss framework (AD-198)

Code: `combat/boss_combat.gd`, `combat/boss_moves/` (`boss_pattern_pool.gd`, `boss_movement.gd`, `boss_hazards.gd`), `world/arena_geometry.gd` (`pick_anchor`, `nearest_open_point`). Tests: `tests/test_ad_boss_framework.gd`. Validator: `BossCombat.validate(settings)` returns `[{code,path,message}]` (empty = valid).

Purpose: bosses that move, pick from weighted pattern pools, change the arena per phase and can be punished after big attacks, all from data. Every number below is [PROPOSED FOR PROTOTYPE].

**Back-compat rule:** a boss without the new keys behaves exactly as before (ordered `patterns` cycle, fixed position, no hazards, no roar, no stagger) and consumes no RNG. The framework only applies to bosses that use `phases`. The new RNG, hazard controller and flags exist only when a phase uses `pool`, `hazards`, etc.

## Data reference

Top level (boss settings): `anchors` `[[x,y],...]` arena points used by moves; `stagger` `{ticks, damage_taken_multiplier}` (multiplier must be > 1; ex. 90 / 1.5). `phases` is an array; each phase has `threshold` (hp fraction, phase = highest index reached, never goes back), `windup_ticks` and any of:

### `pool`
Replaces `patterns` in that phase. Entries:
- `{"pattern":"radial"}` — one attack (`radial`, `fan`, `targeted`, `pulse`, ...).
- `{"combo":["fan","radial"],"gap_ticks":12}` — A then B; `gap_ticks` (default 12) replaces `recovery_ticks` between members, each member gets a full windup.
- `{"move":{"mode":...}}` — a movement entry (below).
- `weight` integer >= 1 (default 1); `big` true = stagger after the entry finishes (after the last combo member, a landed leap, a finished emerge).
- **At least 3 distinct attack patterns** per pool (`pattern` entries and combo first members; moves do not count): `BOSS_POOL_TOO_SMALL`.
- **No immediate repeat:** the pick skips the entry whose key (pattern, combo's first pattern, or `move:<mode>`) equals the last one used (a combo counts as its last member). If that leaves nothing it falls back to the whole pool. A phase change clears the combo queue and the last key.

### `movement` (continuous, per phase)
Runs only in `acquire` and `recover`, never during a windup.
- `walk_to_player`: `speed` (px/s), `stop_range`.
- `strafe`: `speed`, `preferred_range`, `margin` (approach beyond range+margin, back off below range-margin, circle in between; flips side when blocked).

### Pool `move` modes (discrete, one no-repeat step each)
- `reposition`: `speed`, `max_ticks`, optional `anchor_pick` (`farthest` default from the player, or `nearest`). Walks to an anchor, no telegraph. State `moving`.
- `leap`: `telegraph_ticks`, `flight_ticks`, `radius`, `damage`; optional `target` (`player` = nearest open point to the player, or `anchor`) and `anchor_pick`. Telegraphed slam circle at the landing point, then flies in `moving`, damages at landing.
- `submerge`: `telegraph_ticks`, `submerged_ticks`, `emerge_telegraph_ticks`, `radius`, `damage`, optional `anchor_pick`. Telegraph, then vanishes (`submerged` flag, untargetable, still alive and counted), then a telegraphed emerge at the chosen anchor with a slam on reappearing.
- Anchors are needed by every move except a `leap` that targets the player: `BOSS_MOVE_ANCHORS`. Missing keys: `BOSS_MOVE_PARAM`; unknown mode: `BOSS_MOVE_MODE`.

- `blink` (AD-200): `blink_ticks`, `radius`, optional `anchor_pick` (default `farthest` from the player). Telegraphed slam circle at the landing anchor, then the boss appears there. Anchors within 8 px of the boss are skipped so it always moves. `blink_ticks` is not `telegraph_ticks`: it gets no difficulty scale and no `min_telegraph_ticks` floor.

### `hazards` (per phase list)
Common keys: `type`, `first_ticks` (>= 0, first start after the phase starts), `every_ticks` (>= 1), `warn_ticks` (>= 1, raised to `min_telegraph_ticks`), `damage` (scaled like boss damage), `channel` (default `physical`). Hazard damage goes through `damage_player`, so dash i-frames apply.
- `zone`: `at` (`player` locks on the player when the warning starts, or `points` `[[x,y],...]` used in turn), `radius`, `active_ticks`, `damage_interval_ticks`, optional `status`. Damages on its first active tick, then each interval.
- `debris`: `count`, `scatter`, `radius`, `damage`. Impacts land within `scatter` of the player (clamped to the arena), positions locked for the warning, one hit at the end. The only hazard that rolls RNG.
- `rising_water`: `duration_ticks`, `sets` (array of entry arrays used in turn, each entry `{"kind":"shallow","rect":[x,y,w,h]}`). Shallow only: `BOSS_HAZARD_DEEP_WATER`. Uses its own water tag and recedes after `duration_ticks`; other water is untouched.
- Errors: `BOSS_HAZARD_TYPE`, `BOSS_HAZARD_PARAM`.

### Undead Warden keys (AD-199)
- `melee` (top level): named sweeps usable as pool `pattern`/`combo` members. `{"shape":"arc","windup_ticks","reach","arc_degrees","damage"}` draws a cone telegraph; `{"shape":"slam","windup_ticks","reach","damage"}` draws a circle (the dash test). Live: `sweep_1` 40, `sweep_2` 32, `overhead_slam` 48 ticks, reach 150.
- `spear_line` (top level): `{windup_ticks,count,start,spacing,radius,damage}`. `count` ground warnings (`boss_warning` circles) in a line toward the player, starting `start` px from the boss every `spacing` px, then all hit. Its telegraph shape is `none`: the renderer skips the intent shape so no extra dash lane is drawn.
- `grave_rise` (top level): `{windup_ticks,kind,offsets,cap,radius}`. Summons `kind` at each `offsets` entry relative to the boss, never above `cap` thralls alive (live: 2 per cast, cap 3). Thralls die with the boss.
- Pool `max_range` / `min_range` (px, optional on any entry): the entry is blocked while the player is farther than `max_range` or closer than `min_range` from the boss (else the fallback is the whole pool). `BOSS_POOL_RANGE` if not a number > 0 or min > max.
- Phase `windup_scale` (default 1.0): multiplies melee and spear windups for that phase, never below `min_telegraph_ticks` (live phase 3: 0.85, floor 30).
- Leap `shockwave` `{speed,width,max_radius,damage}`: on landing an expanding ring (`boss_ring` hazard) hits once if the player is on the ring band (dash i-frames apply); walls block it. `burst_delay_ticks` (needs a `shockwave` plus `radial_shots`, `radial_damage`, `shot_speed` on the boss): a radial bone burst that many ticks after landing.
- Phase `timed_summon` `{first_ticks,every_ticks}`: reuses the `grave_rise` block on a timer (live phase 3: first at 120 ticks, then every 1200 = 20 s). Pauses during roar, resets on a phase change.
- `arena_change.props` (in `transition`): `[{"id","kind":"boss_pillar","position":[x,y]}]` installs 64x64 cracked pillars as walls (they stop shots and block movement) when the roar starts; an overlapping player or boss is moved to the nearest open point. Force breaks a pillar and frees its wall.
- `pillar_debris` (top level) `{radius,stun_ticks}`: a pillar broken within `radius` of the boss cancels its action and staggers (`stun_ticks`, damage multiplier from `stagger`). Needs a `stagger` block.
- Validator: `BOSS_POOL_RANGE` (bad `max_range`/`min_range`), `BOSS_WARDEN_PARAM` (missing or non-numeric keys of `melee`, `spear_line`, `grave_rise`, `pillar_debris`, `shockwave`, `timed_summon`, `burst_delay_ticks` rules).
- Renderer: hazard `boss_ring` draws the shockwave ring (width `ring_width`, radius grows `ring_per_tick`); intent `telegraph_shape` `none` draws nothing.

### `transition` (phase 2 and later)
`{"roar_ticks":90,"arena_change":{"clear_hazards":true,"water":[{"kind":"shallow","rect":[x,y,w,h]}]}}`. 90 ticks = 1.5 s at 60 Hz. On the threshold the boss cancels its windup, clears the combo queue and phase hazards, becomes invulnerable (`damage_scale` 0) for `roar_ticks`, applies the arena change (clear boss-owned hazards and flood; add shallow water with the `boss_arena` tag), then starts the new phase's hazards. Crossing several thresholds at once plays one roar for the highest phase. `BOSS_TRANSITION_PARAM` for roar_ticks < 1 or non-shallow water.
**Deferred roar:** if the boss is in `moving`, `submerged` or the emerge windup, the roar waits until that move ends. A threshold crossed in the stagger or an ordinary windup starts the roar at once.

### `stagger` (top level)
After a `big` entry the boss enters `stagger` for `ticks`: it does not move, `damage_taken_multiplier` (1.5 = +50%) applies through `damage_scale`, `staggered` is true and the renderer draws a gold ring. Then it opens its next windup. `BOSS_STAGGER_PARAM` for ticks < 1 or multiplier <= 1.

## States
`acquire` (first tick, may walk) -> `windup` -> (`recover` | `stagger`) -> `windup`... Moves add `moving` (reposition, leap flight) and `submerged`. `roar` interrupts anything except a move in progress (see deferred roar). `dead` clears hazards, `submerged`, `staggered` and arena water. `damage_scale` is 1.0 except in `stagger` (multiplier) and `roar` (0); `submerged` is true only in `submerged` and the emerge windup.

## Determinism
The boss has a private `RandomNumberGenerator` seeded lazily from `session.seed*31 + target.id`; pool picks and debris use it. The shared sim stream is never touched (tested: a pool boss leaves `sim.clock` RNG identical to a fresh session). Same seed = identical per-tick trace (state, position, intent, hazards, player hp); a different seed diverges.

## Telegraph rules
- `min_telegraph_ticks` (boss setting, e.g. 36) is a floor after difficulty scaling for `windup_ticks`, move `telegraph_ticks` / `emerge_telegraph_ticks` and hazard `warn_ticks`.
- Attacks reuse existing telegraph shapes; leap/submerge/emerge use the `slam` shape at the landing/emerge point. Hazard warnings are `boss_warning` / `boss_water_warning` circles/rects shown for the whole warning; active zones are `boss_zone`.
- Reduce-flash: zones use a solid tint with no per-tick alpha change; the stagger ring is steady; the roar reuses the `boss.phase` effect, which the existing reduce-flash handling covers. No new flashing is introduced.
- A submerged boss is not drawn; the emerge telegraph still shows where it will appear.

## Validator codes
`BOSS_POOL_TOO_SMALL`, `BOSS_POOL_WEIGHT`, `BOSS_POOL_COMBO`, `BOSS_MOVE_MODE`, `BOSS_MOVE_PARAM`, `BOSS_MOVE_ANCHORS`, `BOSS_HAZARD_TYPE`, `BOSS_HAZARD_PARAM`, `BOSS_HAZARD_DEEP_WATER`, `BOSS_TRANSITION_PARAM`, `BOSS_STAGGER_PARAM`, `BOSS_POOL_RANGE`, `BOSS_WARDEN_PARAM`. The test also validates the live `run_v2.json` `boss` and `bosses` plus `combat_tuning_v1.json` `mini_bosses`: no issues.

## Example
```json
{"kind":"example_boss","hp":2000,"min_telegraph_ticks":36,"recovery_ticks":20,"anchors":[[300,450],[1100,200],[1100,700]],
 "stagger":{"ticks":90,"damage_taken_multiplier":1.5},
 "phases":[
  {"threshold":1.0,"windup_ticks":40,"movement":{"mode":"strafe","speed":80,"preferred_range":250,"margin":50},
   "pool":[{"pattern":"radial","weight":3},{"pattern":"fan"},{"pattern":"targeted"},{"combo":["fan","radial"],"gap_ticks":12},
           {"move":{"mode":"leap","target":"anchor","telegraph_ticks":50,"flight_ticks":24,"radius":110,"damage":8},"big":true}]},
  {"threshold":0.5,"windup_ticks":40,"transition":{"roar_ticks":90,"arena_change":{"clear_hazards":true}},
   "hazards":[{"type":"debris","count":3,"scatter":140,"radius":60,"damage":4,"first_ticks":200,"every_ticks":400,"warn_ticks":40}],
   "pool":[{"pattern":"radial","big":true},{"pattern":"fan"},{"pattern":"targeted"},
           {"move":{"mode":"submerge","telegraph_ticks":40,"submerged_ticks":60,"emerge_telegraph_ticks":50,"radius":110,"damage":8}}]}]}
```
(plus the usual boss keys: `radius`, shot and telegraph radii and damages.)

## Goldens
None updated. The framework is opt-in and no live boss data changed, so every golden (`tests/fixtures/*_traces_v1.json`, `m2_baseline_v1.json`, `balance_frozen/`) is unchanged and still passes; a failing golden would be a back-compat regression.

## Undead Warden v2 (AD-199)
Live data: `world/data/run_v2.json` `bosses.ruins_warden` (HP unchanged at 1800). Tests: `tests/test_ad_warden_v2.gd`. Bench: `tests/bench/warden_bench.gd` (`godot --headless --path . --script res://tests/bench/warden_bench.gd`), screenshots: `tests/capture_ad_warden_v2.gd`.

**Bot bench (INFO only, not a pass/fail gate).** 8 seeds (1423, 2718, 3141, 4242, 5150, 6174, 7331, 8086) x builds 0 and 2, scripted bot (perfect aim, always attacking). Every fight was a win through all 3 phases.

| build | fights | median seconds | median dashes | seconds range |
|---|---|---|---|---|
| 0 | 8 | 23.5 | 11.5 | 19.2-31.6 |
| 2 | 8 | 27.4 | 12.0 | 21.3-56.5 |

The human target is 60-120 s. The bot is well under it because it never misses and never stops damaging the boss, so the number is a lower bound, not a human estimate. No HP was raised and the numbers were not tuned to force the band. Per-fight `max_stationary_ticks` was at most 44 (limit 120, from the test).

**Shots (1280x720, live data, real `ruins_boss` room)** — the capture narrows the phase pool and sets HP/player position to reach each beat:
[phase1_combo_arc](warden_v2/phase1_combo_arc.png), [phase1_overhead_slam](warden_v2/phase1_overhead_slam.png), [phase1_spear_line](warden_v2/phase1_spear_line.png), [phase1_grave_rise](warden_v2/phase1_grave_rise.png), [phase2_leap_telegraph](warden_v2/phase2_leap_telegraph.png), [phase2_shockwave_ring](warden_v2/phase2_shockwave_ring.png), [phase2_pillars](warden_v2/phase2_pillars.png), [phase2_debris_stun](warden_v2/phase2_debris_stun.png), [phase3_enrage](warden_v2/phase3_enrage.png). In the pillar shots the two north pillars are partly behind the room's intro text panel.

**Art not wired in.** The approved art (AD-210, AD-211/r2, AD-217, AD-221/r2) is not wired in by this task. Pillars currently reuse the `cracked_wall` frames.

## Elite mini-boss kit (AD-200 step 1)
Code: `boss_moves/elite_patterns.gd`, `boss_moves/elite_minion.gd` (an `EliteMinion` entry in `session.enemies`, built from a `pending_spawns` spec with a `minion` key). Tests: `tests/test_ad_mini_bosses_v2.gd`; run one suite with `godot --headless --path . --script res://tests/run_suite.gd -- <file>`.
- `homing_skull` (top level) `{hp,radius,speed,turn_deg_per_tick,lifetime_ticks,damage,cap}`: pattern `homing_skull` (slam telegraph, phase windup) queues a skull unless the boss owns `cap` live or queued skulls. The skull turns toward the player, dies on a wall or at `lifetime_ticks`, hits once (it keeps flying through dash i-frames) and can be shot down. `damage` is scaled like other boss damage; hp is not.
- `decoy` (top level) `{hp,radius,damage_multiplier,copies:[patterns]}` + phase `spawn_decoy:true`: when that phase's roar begins one decoy appears at the anchor farthest from the boss (needs anchors). While it lives it shows the telegraph and casts the same fan/targeted/radial/skull from its own position at `damage_multiplier` x damage. hp is not difficulty scaled.
- Skulls and the decoy die with the boss. Validator code `BOSS_ELITE_PARAM`.

## Not done
`cistern_boss` is the other framework user; the mini-bosses still use the old data. `ruins_warden` now uses the framework (AD-199, above).
