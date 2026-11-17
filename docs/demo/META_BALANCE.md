# Meta balance guard (AD-236)

## Purpose
Boss 1 (`ruins_warden`) is the difficulty reference. Full Scriptorium meta (all 15 tiers) must not make it trivial. Boss numbers are frozen by `tests/test_ad_boss1_frozen.gd`; meta never touches enemy/boss HP (checked in `tests/test_ad_feel_bands.gd`).

## Reproduce
```
godot --headless --path . --script res://tests/bench/warden_bench.gd -- --meta=fresh
godot --headless --path . --script res://tests/bench/warden_bench.gd -- --meta=full
godot --headless --path . --script res://tests/test_ad_boss1_frozen.gd
godot --headless --path . --script res://tests/test_ad_feel_bands.gd
```
8 fixed seeds per build; build 0 = bot profile, build 2 = skilled.

## Numbers (8 fights per cell, 0 losses in every cell)
| build | meta | wins/losses | median s | median dmg taken | mean dmg taken | median dmg delta vs fresh | mean dmg delta |
|---|---|---|---|---|---|---|---|
| 0 | fresh | 8/0 | 23.5 | 31.0 | 30.1 | | |
| 0 | full, before (6 / 6 / 0.04) | 8/0 | 20.9 | 24.0 | 27.0 | -22.6% | -10% |
| 0 | full, after (6 / 4 / 0.02) | 8/0 | 22.6 | 33.0 | 32.3 | +6% | +7% |
| 2 | fresh | 8/0 | 27.4 | 49.0 | 48.5 | | |
| 2 | full, before | 8/0 | 22.8 | 33.0 | 28.3 | -32.7% | -42% |
| 2 | full, intermediate (6 / 5 / 0.03) | 8/0 | 22.9 | 28.5 | 27.0 | -42% | -44% |
| 2 | full, after (6 / 4 / 0.02) | 8/0 | 24.9 | 33.0 | 35.6 | -32.7% | -26.5% |

`per_tier` before -> after: max_hp 6 -> 6, max_mana 6 -> 4, mana_regen 0.04 -> 0.02. Costs, ink, milestones, boss HP unchanged.
Damage taken per fight is very noisy (single fights range 0..89); medians of 8 can swing by 10+ points between near-identical configs.

## Verdict
- Boss 1 frozen: met (`test_ad_boss1_frozen.gd`).
- Feel bands green with fresh and full meta: met (`test_ad_feel_bands.gd`).
- Full meta drops boss 1 damage by <= ~25%: bot profile (build 0) met (no drop). Build 2 is -26.5% mean / -32.7% median, borderline, within bench noise; not tuned lower (further cuts make the meta pointless).
- Boss 1 not trivial with full meta: met only partly. The bot wins 8/8 with 100-180 HP left, but still takes 0-66 damage per fight and never trivially (median 33).

## NOT DONE
- Fresh profile "boss 1 still a likely death for the bot": NOT MET. Warden bench build 0 wins 8/8 on fresh profile (this is master's behaviour, unrelated to meta; meta cannot fix it and boss numbers must not change). Whole-run `run_bench.gd` was not run for an INFO row.
