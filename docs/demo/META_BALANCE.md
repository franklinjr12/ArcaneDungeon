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

# AD-243 tuning pass: 20-seed whole-run bench, fresh vs full meta

## Reproduce
`tests/bench/run_bench.gd` got a `--meta=fresh|full` switch (default fresh, behaviour unchanged; `full` = every Scriptorium upgrade at max tier, applied through `RunFlow.set_meta_bonuses` + `start_new` like the game does). Use a separate `--results` folder per profile.
```
G="godot --headless --path . --script res://tests/bench/run_bench.gd --"
for r in 0..4 5..9 10..14 15..19; do $G --seeds=$r --jobs=2 --meta=fresh --results=$TMPDIR/ad243_fresh; done
for r in 0..4 5..9 10..14 15..19; do $G --seeds=$r --jobs=2 --meta=full  --results=$TMPDIR/ad243_full;  done
godot --headless --path . --script res://tests/bench/warden_bench.gd -- --meta=fresh   # and --meta=full
```
20 seeds (20261022..20261041) x 3 builds (weak / typical / skilled) = 60 runs per profile.

## Numbers
| profile | build | won / dead (of 20) | run minutes, won runs (min / median / max) | all runs (min / median / max) |
|---|---|---|---|---|
| fresh | weak | 8 / 12 | 2.8 / 3.1 / 3.3 | 2.7 / 3.1 / 3.3 |
| fresh | typical | 3 / 17 | 3.6 / 3.7 / 4.0 | 1.0 / 3.6 / 4.4 |
| fresh | skilled | 3 / 17 | 3.6 / 3.7 / 4.0 | 1.2 / 3.7 / 4.3 |
| fresh | all | 14 / 46 (23% won) | 2.8 / 3.3 / 4.0 | |
| full | weak | 18 / 2 | 2.7 / 2.9 / 3.6 | 2.7 / 2.9 / 3.6 |
| full | typical | 12 / 8 | 3.3 / 3.7 / 4.0 | 1.9 / 3.7 / 4.0 |
| full | skilled | 15 / 5 | 3.4 / 3.6 / 3.9 | 3.4 / 3.6 / 3.9 |
| full | all | 45 / 15 (75% won) | 2.7 / 3.5 / 4.0 | |

Where runs end (death room, all builds):

| profile | ruins rooms before boss 1 | boss 1 (`ruins_boss`) | cistern rooms before boss 2 | boss 2 (`cistern_boss`) |
|---|---|---|---|---|
| fresh (46 deaths) | 0 | 2 | 3 (`cistern_challenge_v1`) | 41 |
| full (15 deaths) | 0 | 0 | 1 (`cistern_challenge_v1`) | 14 |

Warden bench (boss 1 alone, 8 seeds): fresh build 0 8/0, median damage taken 31.0; fresh build 2 8/0, 49.0; full build 0 8/0, 33.0; full build 2 8/0, 33.0. Identical to the AD-236 table above (boss 1 and meta unchanged).

## Changed numbers
None. No data file was changed in this step (before = after for `combat_tuning_v1.json`, `run_v2.json`, `rooms_cistern_v1.json`, `affixes_v1.json`, `artifacts_v1.json`, `meta_v1.json`; `tests/fixtures/balance_frozen/` untouched). Only the bench gained the `--meta` switch.

## Targets
- Boss 1 numbers and behaviour frozen: MET (`test_ad_boss1_frozen.gd` green, nothing in boss 1 data touched).
- Feel bands green, fresh and full: MET (`test_ad_feel_bands.gd` green; the bands read live data, meta never touches enemy HP).
- Full meta reaches boss 2 and is not a free win: MET for the bot. Full meta wins 75% (vs 23% fresh); 14 of 15 full-meta deaths are at boss 2.
- Run length 18-25 min for a full successful run: NOT DONE. The bot's won runs take 2.7-4.0 min (median 3.5 full, 3.3 fresh). The scripted player clears each room in seconds, so no density, affix or artifact number moves it into 18-25 min without HP sponges (forbidden by the plan and the feel bands). This needs a human playtest for the real figure (same conclusion as AD-241).
- Fresh profile likely dies on or before boss 1: NOT DONE. Fresh bots die in 46 of 60 runs, but only 2 of those on or before boss 1; 41 die at boss 2. The bot wins boss 1 8/8 even on a fresh profile (warden bench), because it dodges every telegraph 70% of the time, which a first-run human does not. Boss 1 cannot change, and raising Ruins room lethality until this bot dies there would overshoot badly for humans (Franklin's playtest already reports dying to bosses), so no number was tuned to the bot. Re-check with human fresh-profile runs.
