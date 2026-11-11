# v1.1 difficulty diagnosis (AD-229)

Date 2026-11-11. Commit `3794e5b` (branch task/AD-229-hermes-software-exec-ad). Godot 4.7.1.stable.official.a13da4feb. Host: shared VM, 1-min load at the start 3.10 (not idle). Outputs in `/workspace/tmp/ad229`.

Report only. Bot numbers are INFO. No data or game file changed. Every number below comes from the printed `AD_DIAG_RUN` lines of the two chunks (60 natural runs: 20 seeds 20261022-20261041 x weak/typical/skilled), merged with a throwaway script kept outside the repo.

Commands (G=/usr/local/bin/godot):

- `$G --headless --path . --import`
- `$G --headless --path . --script res://tests/qa/demo_smoke.gd -- --natural=1 --seeds=10 --first=0 --det-seeds=0 --trace=0 --diag=1` and the same with `--first=10` (two parallel chunks). Both exit 0. 60 `AD_DIAG_RUN` lines in total (30 per chunk).

## Outcome per build, compared with earlier runs

| build | AD-190 (v1) won/dead | AD-204 (v1.1) won/dead | AD-229 won/dead | rooms cleared median (min-max) |
|---|---|---|---|---|
| weak | 17 / 3 | 1 / 19 | 3 / 17 | 7 (3-7) |
| typical | 18 / 2 | 0 / 20 | 3 / 17 | 8 (3-8) |
| skilled | 6 / 14 | 0 / 20 | 1 / 19 | 7 (3-8) |

AD-204 gave 1 win in 60 (weak 1, typical 0, skilled 0). AD-229 gives 7 in 60 (the AD-228 bot dodges new attacks and mixes elements). AD-190 had 41 in 60. Rooms cleared counts rooms with outcome `cleared` in the diag, so it can be lower than the room index of the death. I did not compare against the AD-228 bench tables: they are a different harness (`ad_demo_bench.md`) and I did not re-read them for this report.

## Where runs end (dead runs, room id / index / boss phase)

| build | cistern_boss (idx 11) | ruins_boss (idx 5) | cistern_challenge_v1 (idx 9) | plain combat room |
|---|---|---|---|---|
| weak (17 dead) | 14 (phase 1: 1, phase 2: 7, phase 3: 6) | 1 (phase 3) | 0 | 2 (cistern_p02 at idx 7 and 8) |
| typical (17 dead) | 8 (phase 1: 1, phase 2: 4, phase 3: 3) | 4 (phase 2: 1, phase 3: 3) | 3 (phase 1: 2, phase 2: 1) | 2 (cistern_p01, cistern_p04) |
| skilled (19 dead) | 5 (phase 2: 4, phase 3: 1) | 2 (phase 3) | 9 (phase 1: 6, phase 2: 3) | 3 (cistern_p01 x2, cistern_p03) |

## Killing enemy and attack (dead runs)

| build | kills (kind:attack x count) |
|---|---|
| weak | drowned_archivist:water_bolt 9, drowned_archivist:emerge 2, grave_hound:recover 2, undead_warden:leap 1, drowned_archivist:page_throw 1, :submerge 1, :storm_pulse 1 |
| typical | drowned_archivist:water_bolt 4, drowned_archivist:emerge 4, storm_crystal:beam_sweep 2, undead_warden:sweep_1 / sweep_2 / leap / overhead_slam 1 each, fallen_adept:recover 1, grave_hound:recover 1, storm_crystal:recover 1 |
| skilled | storm_crystal:beam_sweep 5, drowned_archivist:water_bolt 4, fallen_adept:recover 2, storm_crystal electrify / roar / radial / recover 1 each, undead_warden:sweep_1 and spear_line 1 each, grave_hound:recover 1, drowned_archivist:emerge 1 |

`recover` is the enemy state name at the moment of death (the killing hit landed in the recovery of an earlier attack), not an attack of its own.

## Damage taken by source (sum over all runs of a build)

| source | weak | typical | skilled |
|---|---|---|---|
| undead_warden:physical | 795 | 1079 | 1240 |
| drowned_archivist:physical | 865 | 549.5 | 365.5 |
| fallen_adept:physical | 660 | 529 | 470 |
| storm_crystal:lightning | 0 | 359.5 | 310.5 |
| grave_hound:physical | 283 | 260 | 285 |
| bone_thrall:physical | 196 | 252 | 308 |
| drowned_archivist:lightning / water | 103 / 56 | 65 / 0 | 0 / 20 |
| total | 2958 | 3210 | 3085 |

Damage per room entry (mean over the runs that entered the room, HP):

| room | weak | typical | skilled |
|---|---|---|---|
| ruins_c01 / c02 / c03 / c04 | 0 / 14.0 / 33.0 / 16.9 | 0 / 17.1 / 47.7 / 7.6 | 3.5 / 17.1 / 33.0 / 11.8 |
| ruins_c05 / c06 / c07 / c08 | 12.0 / 18.2 / 2.2 / 0 | 6.0 / 10.4 / 4.4 / 3.7 | 13.0 / 15.2 / 0 / 0 |
| ruins_boss | 43.2 | 58.9 | 69.0 |
| cistern_p01 / p02 / p03 / p04 | 11.0 / 14.7 / 12.6 / 7.7 | 9.3 / 27.0 / 12.0 / 17.4 | 2.4 / 9.0 / 8.4 / 14.0 |
| cistern_p05 to p10 | 0 / 0 / 7.3 / 0 / 0 / 0 | 0 / 2.5 / 11.0 / 0 / 0 / 6.7 | 0 / 0 / 7.3 / 0 / 0 / 0 |
| cistern_challenge_v1 | not entered | 28.5 | 25.4 |
| cistern_boss | 60.2 | 58.6 | 64.2 |

The two bosses plus ruins_c03 take most damage.

## Mana (time out of mana)

Mana-starved % of fight ticks, all rooms pooled: weak 53.7, typical 57.6, skilled 57.7. Per-chunk medians per run were 52.9, 57.1, 58.5 (chunk 0). By room, starved % is highest in the late combat rooms (cistern_p07 to p10: 62-68 in typical/skilled) and the challenge room (63-64), lowest in ruins_c04/c07 (31-44).

## Dodges (succeeded / attempted, all runs of a build)

| threat | weak | typical | skilled |
|---|---|---|---|
| melee | 341/350 | 317/326 | 317/327 |
| shot | 221/252 (88%) | 207/237 (87%) | 176/198 (89%) |
| boss_slam | 82/82 | 80/80 | 58/58 |
| boss_zone | 20/20 | 28/28 | 35/35 |
| swipe_arc | 37/37 | 59/59 | 59/59 |
| boss_beam | 0 attempts | 12/21 (57%) | 15/22 (68%) |
| tide_wave | 4/5 | 4/4 | 3/3 |
| lunge / slam | 2/2 / 4/4 | 10/10 / 4/5 | 7/7 / 9/9 |

Perfect dodges: weak 112 (5.6 per run), typical 130 (6.5), skilled 118 (5.9). In ruins_boss alone: weak 27, typical 30, skilled 30.

## Reactions per room

Mean reactions per room entry: weak 2.2-7.3 in every room, boss rooms 11.6 (ruins_boss) and 14.3 (cistern_boss). Typical and skilled have about 0 in both boss rooms (0.1-0.3, cistern_boss 0.2 and 0.0) and in most cistern rooms. Reaction ids seen: `water_extinguish` and `wet_lightning_arc` only (typical 163 and 17 in chunk 0 sample, skilled 157 and 15). The weak build mostly casts water.

## HP at each boss (flask: n/a, there is no flask mechanic)

| build | ruins_boss: entered, median HP at entry (player max 150) | ruins_boss outcome | cistern_boss: entered, median HP at entry | cistern_boss outcome |
|---|---|---|---|---|
| weak | 20, 118.5 | cleared 19, dead 1 | 17, 62.0 (max 150) | won 3, dead 14 |
| typical | 20, 122.0 | cleared 16, dead 4 | 11, 50.0 (max 175) | won 3, dead 8 |
| skilled | 20, 121.5 | cleared 18, dead 2 | 6, 68.25 (max 175) | won 1, dead 5 |

Runs reach cistern_boss with a median of 50 to 68 HP of 150-175, and there is no way to heal there in these bots.

## Top 3 causes (INFO, bot numbers)

All levers below are not changed; input for the tuning row after Franklin's feel test.

1. **Drowned Archivist (cistern_boss) is where most runs end, and it is entered at about a third of HP.** 27 of 53 dead runs ended there (weak 14, typical 8, skilled 5); water_bolt is the top killer (17 kills in 53) with emerge next (7). Boss damage per entry is 58.6-64.2 HP while entry HP is 50-68. Levers: `world/data/run_v2.json` `stages[1]`-boss entry `cistern_boss.water_bolt_damage` (8), `water_bolt_shots` (5), `water_bolt_arc_degrees` (40), `cistern_boss.hp` (2400), `recovery_ticks` (50). HP at entry is moved by the ruins damage in cause 3 and by `game/data/difficulty_v1.json` `presets.default.enemy_damage`.
2. **Mana is empty more than half of fight time, so the bots cannot kill fast or use reactions at the bosses.** Starved 53.7 / 57.6 / 57.7 % of fight ticks, 62-68 % in late cistern rooms and 63 % in the ruins boss; typical and skilled get about 0 reactions in the boss rooms. Levers: `magic/data/magic_balance_v1.json` `combat.regen_mana_per_tick` (0.6), `combat.player_max_mana` (120), `combat.perfect_dodge_mana_refund` (15; 112-130 perfect dodges per 20 runs). Overall `game/data/difficulty_v1.json` `presets.default.player_mana`.
3. **Ruins boss (Undead Warden) and ruins_c03 / challenge room drain HP before the cistern, and storm_crystal beam_sweep kills the skilled bot.** undead_warden is the top damage source for typical (1079) and skilled (1240); ruins_boss costs 43-69 HP per entry and ruins_c03 33-48. Skilled dies 9 times in `cistern_challenge_v1`, 5 of the kills by `storm_crystal:beam_sweep`; boss_beam dodges succeed only 57-68 %. Levers: `world/data/run_v2.json` `boss.hp` (590) and the stage-0 boss entry `hp` (1800), `radial_damage` (9), `shot_damage` (16), `windup_ticks` (48), `recovery_ticks` (44); `world/data/rooms_ruins_v1.json` wave lists of `ruins_c03`; `world/data/rooms_cistern_v1.json` `cistern_challenge_v1` waves. The beam_sweep / electrify tuning is read as a `tuning` dict in `combat/boss_combat.gd` (lines 134, 196, 351); I did not find its JSON key by grep in `world/data`, so that lever is not located.

Not measured: why the AD-190 bots won much more often (these runs did not repeat AD-190 on the old build), and the flask (no such mechanic).
