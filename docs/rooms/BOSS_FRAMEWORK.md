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

### `hazards` (per phase list)
Common keys: `type`, `first_ticks` (>= 0, first start after the phase starts), `every_ticks` (>= 1), `warn_ticks` (>= 1, raised to `min_telegraph_ticks`), `damage` (scaled like boss damage), `channel` (default `physical`). Hazard damage goes through `damage_player`, so dash i-frames apply.
- `zone`: `at` (`player` locks on the player when the warning starts, or `points` `[[x,y],...]` used in turn), `radius`, `active_ticks`, `damage_interval_ticks`, optional `status`. Damages on its first active tick, then each interval.
- `debris`: `count`, `scatter`, `radius`, `damage`. Impacts land within `scatter` of the player (clamped to the arena), positions locked for the warning, one hit at the end. The only hazard that rolls RNG.
- `rising_water`: `duration_ticks`, `sets` (array of entry arrays used in turn, each entry `{"kind":"shallow","rect":[x,y,w,h]}`). Shallow only: `BOSS_HAZARD_DEEP_WATER`. Uses its own water tag and recedes after `duration_ticks`; other water is untouched.
- Errors: `BOSS_HAZARD_TYPE`, `BOSS_HAZARD_PARAM`.

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
`BOSS_POOL_TOO_SMALL`, `BOSS_POOL_WEIGHT`, `BOSS_POOL_COMBO`, `BOSS_MOVE_MODE`, `BOSS_MOVE_PARAM`, `BOSS_MOVE_ANCHORS`, `BOSS_HAZARD_TYPE`, `BOSS_HAZARD_PARAM`, `BOSS_HAZARD_DEEP_WATER`, `BOSS_TRANSITION_PARAM`, `BOSS_STAGGER_PARAM`. The test also validates the live `run_v2.json` `boss` and `bosses` plus `combat_tuning_v1.json` `mini_bosses`: no issues.

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

## Not done
The live bosses (`ruins_warden`, `cistern_boss`, mini-bosses) still use the old data. Applying pools, movement, hazards, roars and stagger to them is follow-up content work.
