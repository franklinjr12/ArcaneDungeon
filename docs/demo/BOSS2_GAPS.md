# Boss 2 (cistern_boss, Drowned Archivist) vs boss 1 (ruins_warden): gaps (AD-243)

Reference = boss 1, frozen (`tests/test_ad_boss1_frozen.gd`). All line refs are `world/data/run_v2.json`. Boss 2 has no entry in `combat/combat_tuning_v1.json` (only the cistern *mini*-boss does), so all its numbers live in run_v2.json.
Bot pacing, from `tests/bench/boss_pacing_bench.gd` (INFO only): 16 fights, 15 wins, median 58 s, `max_stationary_ticks` 9-32 (<= 0.53 s).

## 1. Telegraph clarity
| | boss 1 | boss 2 | gap |
|---|---|---|---|
| Phase windup (ticks) | 48 / 44 / 40 (`:307,357,455`) | 48 / 44 / 40 (`:678,755,849`) | none |
| `min_telegraph_ticks` | 30 (`:229`) | 36 (`:537`) | boss 2 longer = clearer; no gap |
| Move telegraphs | leap 48-50 (`:343,407`) | submerge 40 + emerge 40 (`:733`), tide wave warn 60 (`:800`) | none (80 ticks total for dive+emerge) |
| `recovery_ticks` | 44 (`:220`) | 50 (`:536`) | boss 2 gives a slightly longer breather; harmless, left alone |
| Visuals | arc/slam/line/circle telegraphs, one per attack | wet zone, tide wave gap, page throw, wisp shield | Tide-wave gap and shielded state read only by a text/shape cue; no distinct "shield is up, kill the wisps" tint on the boss. Needs art/code (below). |

## 2. Phase change
| | boss 1 | boss 2 | gap |
|---|---|---|---|
| Thresholds | 1.0 / 0.6 / 0.25 (`:306,356,454`) | 1.0 / 0.66 / 0.33 (`:677,754,848`) | none; both three phases |
| Roar | 90 then 60 ticks (`:359,458`) | 90 then 90 (`:757,851`) | none |
| What changes | new movement mode (walk -> strafe -> faster walk), new pool, pillars appear (`:362`), timed summon (`:465`), `windup_scale` 0.85 (`:456`) | float speed 50 -> 60 -> 70, pool swap, tide wave hazard (`:800`), page speed x1.5 (`:853`), wisps + storm pulse | Phase 2 and 3 change *attacks* but not *space*: no arena change, no `clear_hazards`/props at a transition. Phase 1->2 feels like a re-roll of weights. Planner note below. |

## 3. Arena use
| | boss 1 | boss 2 | gap |
|---|---|---|---|
| Anchors | 4 (`:236-251`) | 6 (`:538-555`) | none |
| Hazards | 4 pillars (cover, `pillar_debris` stun, `:362`) | 3 pools (`:556`), 4 `flood_sets` cycled (`:620`), tide wave 260 px/s with 96 px gap (`:800`) | good: boss 2 uses more of the room |
| Arena change on phase | pillars at 0.6 | none | gap, see section 2 |
| Boss start | (1030,450) | (1030,450) | none |

## 4. Always moving
| | boss 1 | boss 2 | gap |
|---|---|---|---|
| Movement | `walk_to_player` 120 / strafe 120 / walk 144 (`:309,399,461`) | `float_path` 50 / 60 / 70 (`:680,760,855`) | boss 2 drifts at under half the speed. |
| Measured stationary time | n/a | max 9-32 ticks per fight (bench) | no idle problem: submerge/emerge fills the gaps |

## Gap list
- Telegraph windups, min telegraph, recovery: no gap, **no change**.
- Phase thresholds and roars: no gap, **no change**.
- Float speed 50-70 vs warden 120-144: **planner note: data-only speed bump is possible (e.g. 70/85/100), but it changes the bot pacing and mixes with the 58 s vs 90-150 s INFO target; decide with the HP/pacing question below.** Left unchanged so the Boss 2 fight is not retuned blind.
- Fight length 58 s median vs 90-150 s human target: **planner note: HP stays 2400 (no sponges, AD-201); more length needs another mechanic (code), e.g. a second vulnerable window, not data.**
- No arena change at phase transitions: **planner note: needs code/scene work. `arena_change` is supported in the warden phases (`:359`); cistern could reuse it with new props or flood sets, but the props/art do not exist yet.**
- Shield/wisp state readability: **planner note: needs art (boss tint or shield overlay) and a VFX hook.**

No data files were changed in this step; boss 1 data untouched. No sound work.
