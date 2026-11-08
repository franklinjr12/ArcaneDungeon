# AD demo pacing diagnosis (AD-168)

## Purpose

Explain why full runs end after about 2-5 min of sim time (AD-156 target: 30-40 min) and why about 56% of combat time is mana-starved. **Report only**: the only code change is extra reporting in `tests/bench/run_bench.gd`; no data or gameplay file was changed. Evidence sources: `docs/benchmarks/ad_demo_bench.md` (AD-156) and the Known issues in `docs/benchmarks/ad_demo_qa.md` (AD-158, issue 4).

## Command and seeds

```
godot --headless --path . --import
godot --headless --path . --script res://tests/bench/run_bench.gd -- --seeds=5 --builds=weak,typical,skilled
```

Seeds: the first 5 of `SEEDS` in `run_bench.gd`: 20261022 .. 20261026. Builds: weak, typical, skilled (15 runs, natural play with the scripted player). Tick rate is 60/s (checked against the regen figures below, estimate).

## Determinism

The command was run twice (exit 0 both times). The BENCH_MD and DIAG_MD blocks of the two outputs are byte-identical (`cmp`). Each run also passes the built-in re-run self-check of the first seed per build (`AD_DEMO_BENCH nondeterministic` did not fire).

## Bench output (BENCH_MD)

BENCH_MD_BEGIN
**weak**

| seed | outcome | died in | total min | max room s | starved % | rooms cleared |
|---|---|---|---|---|---|---|
| 20261022 | dead | stage2_boss | 3.764 | 91.567 | 56.327 | 12 |
| 20261023 | dead | stage2_boss | 2.626 | 35.633 | 56.085 | 11 |
| 20261024 | dead | stage2_boss | 2.052 | 25.333 | 59.841 | 12 |
| 20261025 | dead | stage2_boss | 3.143 | 52.883 | 58.226 | 13 |
| 20261026 | dead | stage2_boss | 3.588 | 85.25 | 59.371 | 12 |

**typical**

| seed | outcome | died in | total min | max room s | starved % | rooms cleared |
|---|---|---|---|---|---|---|
| 20261022 | dead | stage2_boss | 3.899 | 56.2 | 56.896 | 13 |
| 20261023 | dead | stage2_rooms | 3.174 | 52.567 | 65.238 | 11 |
| 20261024 | dead | stage2_rooms | 3.096 | 80.5 | 54.206 | 12 |
| 20261025 | dead | stage2_boss | 4.842 | 103.6 | 51.121 | 14 |
| 20261026 | dead | stage2_rooms | 3.801 | 96.033 | 55.812 | 12 |

**skilled**

| seed | outcome | died in | total min | max room s | starved % | rooms cleared |
|---|---|---|---|---|---|---|
| 20261022 | dead | stage2_rooms | 3.589 | 73.2 | 55.618 | 12 |
| 20261023 | dead | stage2_rooms | 2.934 | 55.783 | 54.435 | 11 |
| 20261024 | dead | stage2_rooms | 2.803 | 57.533 | 56.115 | 12 |
| 20261025 | dead | stage2_boss | 3.89 | 54.667 | 56.948 | 14 |
| 20261026 | dead | stage2_rooms | 3.625 | 102.717 | 54.642 | 12 |

| build | wins | win total min (median/min/max) | dies stage 1 or first boss | max room s | starved % median | starved % max |
|---|---|---|---|---|---|---|
| weak | 0/5 | - | 0/5 | 91.567 | 58.226 | 59.841 |
| typical | 0/5 | - | 0/5 | 103.6 | 55.812 | 65.238 |
| skilled | 0/5 | - | 0/5 | 102.717 | 55.618 | 56.948 |

| target | weak | typical | skilled |
|---|---|---|---|
| winning run 30-40 min sim | n/a | NO (median 0.0 min, 0 wins) | NO (median 0.0 min, 0 wins) |
| weak build dies in stage 1 or at the first boss on most seeds | NO (0/5 dead early, need 3) | n/a | n/a |
| no room > 4 min | PASS (max 91.567 s) | PASS (max 103.6 s) | PASS (max 102.717 s) |
| mana-starved < 20% | NO (median 58.226%) | NO (median 55.812%) | NO (median 55.618%) |

| room | n | median s | min s | max s | median HP lost | min HP lost | max HP lost |
|---|---|---|---|---|---|---|---|
| cistern_boss | 8 | 44.258 | 9.0 | 91.567 | 69.5 | 20.0 | 112.0 |
| cistern_challenge_v1 | 10 | 65.367 | 46.35 | 103.6 | 101.0 | 25.0 | 153.0 |
| cistern_p01 | 3 | 5.4 | 5.267 | 5.567 | 11.0 | 11.0 | 11.0 |
| cistern_p02 | 6 | 10.959 | 9.933 | 27.733 | 9.0 | 0.0 | 29.0 |
| cistern_p03 | 6 | 8.367 | 7.483 | 10.367 | 4.5 | 0.0 | 27.0 |
| cistern_p04 | 3 | 9.717 | 9.333 | 14.383 | 0.0 | 0.0 | 9.0 |
| cistern_p05 | 15 | 5.4 | 4.317 | 7.85 | 0.0 | 0.0 | 0.0 |
| cistern_p06 | 9 | 6.9 | 6.417 | 7.383 | 0.0 | 0.0 | 0.0 |
| cistern_p07 | 6 | 8.317 | 6.7 | 11.083 | 5.5 | 0.0 | 11.0 |
| cistern_p08 | 6 | 11.433 | 10.6 | 11.767 | 0.0 | 0.0 | 0.0 |
| cistern_p09 | 15 | 6.633 | 5.083 | 7.417 | 0.0 | 0.0 | 0.0 |
| cistern_p10 | 12 | 20.325 | 18.4 | 28.467 | 0.0 | 0.0 | 0.0 |
| ruins_boss | 15 | 23.55 | 12.217 | 29.15 | 16.0 | 0.0 | 64.0 |
| ruins_c01 | 6 | 0.5 | 0.5 | 0.5 | 0.0 | 0.0 | 0.0 |
| ruins_c02 | 9 | 2.583 | 2.567 | 2.583 | 0.0 | 0.0 | 0.0 |
| ruins_c03 | 9 | 2.4 | 2.383 | 2.433 | 0.0 | 0.0 | 0.0 |
| ruins_c04 | 12 | 4.709 | 3.2 | 6.35 | 11.0 | 0.0 | 22.0 |
| ruins_c05 | 9 | 5.533 | 4.867 | 8.467 | 9.0 | 9.0 | 9.0 |
| ruins_c06 | 12 | 8.283 | 6.833 | 9.717 | 0.0 | 0.0 | 22.0 |
| ruins_c07 | 15 | 5.967 | 5.367 | 7.017 | 11.0 | 0.0 | 11.0 |
| ruins_c08 | 12 | 8.166 | 5.783 | 10.617 | 4.5 | 0.0 | 29.0 |
BENCH_MD_END

Note: all 15 runs end in `dead` (stage2_rooms or stage2_boss). **No run is ever completed**, so "run length" here is "time until the scripted player dies", not the length of the content.

## Pacing diagnostics (DIAG_MD)

DIAG_MD_BEGIN
Cells show median / min / max over the seeds unless noted.

### weak

Per room:

| room | n | fight s | waves | enemies | enemy HP | player DPS | dmg taken | mana spent | mana regen | starved % |
|---|---|---|---|---|---|---|---|---|---|---|
| cistern_boss | 5 | 52.883 / 9.0 / 91.567 | 0.0 / 0.0 / 0.0 | 4.0 / 1.0 / 11.0 | 1085.0 / 950.0 / 1400.0 | 15.735 / 13.033 / 43.733 | 62.0 / 24.0 / 112.0 | 942.9 / 207.6 / 1585.2 | 824.1 / 90.9 / 1466.7 | 48.58 / 44.294 / 52.414 |
| cistern_p01 | 1 | 5.4 / 5.4 / 5.4 | 1.0 / 1.0 / 1.0 | 3.0 / 3.0 / 3.0 | 270.0 / 270.0 / 270.0 | 50.0 / 50.0 / 50.0 | 11.0 / 11.0 / 11.0 | 200.9 / 200.9 / 200.9 | 83.1 / 83.1 / 83.1 | 81.173 / 81.173 / 81.173 |
| cistern_p02 | 2 | 11.067 / 10.7 / 11.433 | 1.0 / 1.0 / 1.0 | 5.0 / 5.0 / 5.0 | 349.0 / 349.0 / 349.0 | 31.571 / 30.525 / 32.617 | 19.0 / 9.0 / 29.0 | 295.45 / 290.1 / 300.8 | 177.15 / 170.7 / 183.6 | 62.986 / 61.953 / 64.019 |
| cistern_p03 | 2 | 8.425 / 8.133 / 8.717 | 1.0 / 1.0 / 1.0 | 6.0 / 6.0 / 6.0 | 424.0 / 424.0 / 424.0 | 50.387 / 48.642 / 52.131 | 4.5 / 0.0 / 9.0 | 249.55 / 243.0 / 256.1 | 133.2 / 128.4 / 138.0 | 73.392 / 73.361 / 73.423 |
| cistern_p04 | 1 | 9.717 / 9.717 / 9.717 | 2.0 / 2.0 / 2.0 | 6.0 / 6.0 / 6.0 | 424.0 / 424.0 / 424.0 | 43.636 / 43.636 / 43.636 | 0.0 / 0.0 / 0.0 | 268.4 / 268.4 / 268.4 | 156.3 / 156.3 / 156.3 | 60.034 / 60.034 / 60.034 |
| cistern_p05 | 5 | 5.717 / 4.767 / 6.883 | 1.0 / 1.0 / 1.0 | 5.0 / 5.0 / 5.0 | 314.0 / 314.0 / 314.0 | 54.927 / 45.617 / 65.874 | 0.0 / 0.0 / 0.0 | 206.3 / 190.6 / 226.5 | 88.5 / 74.4 / 107.4 | 53.199 / 50.437 / 78.488 |
| cistern_p06 | 3 | 7.383 / 6.883 / 7.383 | 1.0 / 1.0 / 1.0 | 5.0 / 5.0 / 5.0 | 334.0 / 334.0 / 334.0 | 45.237 / 45.237 / 48.523 | 0.0 / 0.0 / 0.0 | 218.5 / 210.4 / 218.5 | 99.0 / 90.9 / 99.0 | 69.526 / 68.039 / 69.526 |
| cistern_p07 | 2 | 6.775 / 6.7 / 6.85 | 1.0 / 1.0 / 1.0 | 5.0 / 5.0 / 5.0 | 334.0 / 334.0 / 334.0 | 49.305 / 48.759 / 49.851 | 11.0 / 11.0 / 11.0 | 224.2 / 224.2 / 224.2 | 108.15 / 106.8 / 109.5 | 43.161 / 42.04 / 44.282 |
| cistern_p08 | 2 | 11.017 / 10.6 / 11.433 | 1.0 / 1.0 / 1.0 | 5.0 / 5.0 / 5.0 | 494.0 / 494.0 / 494.0 | 44.906 / 43.207 / 46.604 | 0.0 / 0.0 / 0.0 | 292.65 / 285.9 / 299.4 | 174.45 / 167.7 / 181.2 | 81.152 / 80.818 / 81.487 |
| cistern_p09 | 5 | 6.75 / 6.417 / 7.417 | 1.0 / 1.0 / 1.0 | 5.0 / 5.0 / 5.0 | 299.0 / 299.0 / 299.0 | 44.296 / 40.315 / 46.597 | 0.0 / 0.0 / 0.0 | 223.9 / 218.5 / 234.7 | 104.4 / 99.0 / 115.2 | 83.636 / 80.674 / 84.304 |
| cistern_p10 | 4 | 20.325 / 19.367 / 20.833 | 2.0 / 2.0 / 2.0 | 7.0 / 7.0 / 7.0 | 579.0 / 579.0 / 579.0 | 28.488 / 27.792 / 29.897 | 0.0 / 0.0 / 0.0 | 443.25 / 429.2 / 451.8 | 326.1 / 310.8 / 334.8 | 81.565 / 81.12 / 82.29 |
| ruins_boss | 5 | 24.333 / 22.583 / 25.333 | 0.0 / 0.0 / 0.0 | 1.0 / 1.0 / 1.0 | 590.0 / 590.0 / 590.0 | 24.247 / 23.289 / 26.125 | 41.0 / 0.0 / 64.0 | 466.9 / 437.7 / 481.2 | 349.2 / 319.5 / 361.5 | 41.993 / 39.521 / 55.132 |
| ruins_c01 | 2 | 0.5 / 0.5 / 0.5 | 1.0 / 1.0 / 1.0 | 1.0 / 1.0 / 1.0 | 95.0 / 95.0 / 95.0 | 190.0 / 190.0 / 190.0 | 0.0 / 0.0 / 0.0 | 121.3 / 121.3 / 121.3 | 3.3 / 3.3 / 3.3 | 36.667 / 36.667 / 36.667 |
| ruins_c02 | 3 | 2.583 / 2.583 / 2.583 | 1.0 / 1.0 / 1.0 | 2.0 / 2.0 / 2.0 | 190.0 / 190.0 / 190.0 | 73.548 / 73.548 / 73.548 | 0.0 / 0.0 / 0.0 | 156.4 / 156.4 / 156.4 | 36.9 / 36.9 / 36.9 | 79.355 / 79.355 / 79.355 |
| ruins_c03 | 3 | 2.4 / 2.383 / 2.417 | 1.0 / 1.0 / 1.0 | 1.0 / 1.0 / 1.0 | 80.0 / 80.0 / 80.0 | 33.333 / 33.103 / 33.566 | 0.0 / 0.0 / 0.0 | 122.7 / 122.7 / 124.0 | 12.3 / 12.0 / 13.5 | 13.194 / 13.103 / 16.783 |
| ruins_c04 | 4 | 4.925 / 4.233 / 6.317 | 1.0 / 1.0 / 1.0 | 2.0 / 2.0 / 2.0 | 175.0 / 175.0 / 175.0 | 35.541 / 27.704 / 41.339 | 11.0 / 11.0 / 22.0 | 194.15 / 180.7 / 217.0 | 75.3 / 63.9 / 98.7 | 69.708 / 67.81 / 77.559 |
| ruins_c05 | 3 | 5.967 / 5.383 / 8.467 | 1.0 / 1.0 / 1.0 | 2.0 / 2.0 / 2.0 | 180.0 / 180.0 / 180.0 | 30.168 / 21.26 / 33.437 | 9.0 / 9.0 / 9.0 | 206.7 / 203.9 / 253.8 | 95.1 / 85.8 / 136.2 | 44.134 / 32.508 / 47.441 |
| ruins_c06 | 4 | 8.159 / 6.833 / 9.717 | 2.0 / 2.0 / 2.0 | 3.0 / 3.0 / 3.0 | 260.0 / 260.0 / 260.0 | 32.269 / 26.758 / 38.049 | 5.5 / 0.0 / 11.0 | 247.75 / 226.9 / 275.4 | 131.1 / 108.9 / 156.3 | 51.683 / 41.609 / 52.659 |
| ruins_c07 | 5 | 6.317 / 5.367 / 6.967 | 2.0 / 2.0 / 2.0 | 3.0 / 3.0 / 3.0 | 255.0 / 255.0 / 255.0 | 40.369 / 36.603 / 47.516 | 0.0 / 0.0 / 11.0 | 217.3 / 202.2 / 229.4 | 99.0 / 82.8 / 109.8 | 66.404 / 63.061 / 75.073 |
| ruins_c08 | 4 | 9.325 / 7.833 / 10.3 | 1.0 / 1.0 / 1.0 | 3.0 / 3.0 / 3.0 | 260.0 / 260.0 / 260.0 | 27.965 / 25.243 / 33.191 | 13.5 / 0.0 / 20.0 | 264.6 / 240.1 / 283.3 | 148.95 / 125.1 / 164.7 | 60.609 / 54.253 / 66.271 |

Time to kill per enemy kind (seconds from first sight to death):

| kind | killed | TTK s (median / min / max) |
|---|---|---|
| bone_thrall | 33 | 0.633 / 0.5 / 3.25 |
| cistern_slime | 26 | 0.942 / 0.533 / 6.05 |
| cistern_slimelet | 52 | 0.667 / 0.033 / 2.083 |
| deep_eel | 16 | 1.942 / 0.917 / 6.85 |
| drowned_acolyte | 15 | 5.733 / 3.1 / 18.333 |
| fallen_adept | 30 | 3.934 / 0.7 / 9.617 |
| grave_hound | 16 | 7.983 / 2.367 / 11.433 |
| lantern_wisp | 28 | 2.45 / 0.733 / 23.517 |
| rust_golem | 6 | 13.85 / 3.417 / 15.267 |
| storm_crystal | 5 | 1.617 / 1.617 / 11.433 |
| undead_warden | 5 | 24.333 / 22.583 / 25.333 |

Boss seconds per phase (rooms with a phased enemy; mini-bosses included):

| room | phase | n | s (median / min / max) |
|---|---|---|---|
| cistern_boss | 1 | 5 | 6.017 / 5.65 / 6.517 |
| cistern_boss | 2 | 5 | 35.4 / 2.983 / 51.817 |
| cistern_boss | 3 | 3 | 33.233 / 9.317 / 43.5 |
| ruins_boss | 1 | 5 | 4.35 / 4.033 / 4.583 |
| ruins_boss | 2 | 5 | 20.133 / 17.983 / 20.983 |

Scripted player sanity (hits = enemy-lost-HP events per tick, so a pierce/burst can exceed 1 per cast):

| hit rate median | idle % median (foe alive, no cast, no dash, mana ok) | no-sight % median | casts per combat minute |
|---|---|---|---|
| 0.569 | 30.667 | 34.12 | 361.176 |

Run totals:

| total min | combat min | walk min | mana spent | mana regen | enemy HP faced | overall DPS |
|---|---|---|---|---|---|---|
| 3.143 / 2.052 / 3.764 | 2.744 / 1.744 / 3.363 | 0.374 / 0.259 / 0.402 | 4156.3 / 3070.4 / 4665.6 | 2508.0 / 1539.6 / 3149.1 | 5089.0 / 4411.0 / 5324.0 | 29.025 / 25.809 / 36.827 |

### typical

Per room:

| room | n | fight s | waves | enemies | enemy HP | player DPS | dmg taken | mana spent | mana regen | starved % |
|---|---|---|---|---|---|---|---|---|---|---|
| cistern_boss | 2 | 30.109 / 27.767 / 32.45 | 0.0 / 0.0 / 0.0 | 1.0 / 1.0 / 1.0 | 950.0 / 950.0 / 950.0 | 17.851 / 15.864 / 19.837 | 48.5 / 20.0 / 77.0 | 564.45 / 525.1 / 603.8 | 445.05 / 405.9 / 484.2 | 43.464 / 40.036 / 46.893 |
| cistern_challenge_v1 | 5 | 80.5 / 52.567 / 103.6 | 2.0 / 2.0 / 2.0 | 9.0 / 9.0 / 9.0 | 1117.0 / 1117.0 / 1117.0 | 10.782 / 10.028 / 19.875 | 115.0 / 35.0 / 126.0 | 1456.2 / 976.9 / 1845.3 | 1339.2 / 860.1 / 1730.1 | 49.879 / 43.404 / 65.916 |
| cistern_p01 | 1 | 5.267 / 5.267 / 5.267 | 1.0 / 1.0 / 1.0 | 3.0 / 3.0 / 3.0 | 270.0 / 270.0 / 270.0 | 51.266 / 51.266 / 51.266 | 11.0 / 11.0 / 11.0 | 198.9 / 198.9 / 198.9 | 80.7 / 80.7 / 80.7 | 80.38 / 80.38 / 80.38 |
| cistern_p02 | 2 | 19.183 / 10.633 / 27.733 | 1.0 / 1.0 / 1.0 | 5.0 / 5.0 / 5.0 | 349.0 / 349.0 / 349.0 | 22.703 / 12.584 / 32.821 | 4.5 / 0.0 / 9.0 | 431.45 / 289.3 / 573.6 | 312.75 / 170.7 / 454.8 | 54.036 / 51.803 / 56.27 |
| cistern_p03 | 2 | 9.125 / 7.883 / 10.367 | 1.0 / 1.0 / 1.0 | 6.0 / 6.0 / 6.0 | 424.0 / 424.0 / 424.0 | 47.342 / 40.9 / 53.784 | 9.0 / 0.0 / 18.0 | 262.55 / 241.1 / 284.0 | 144.3 / 123.0 / 165.6 | 73.763 / 69.936 / 77.59 |
| cistern_p04 | 1 | 14.383 / 14.383 / 14.383 | 2.0 / 2.0 / 2.0 | 6.0 / 6.0 / 6.0 | 424.0 / 424.0 / 424.0 | 29.479 / 29.479 / 29.479 | 9.0 / 9.0 / 9.0 | 349.8 / 349.8 / 349.8 | 230.7 / 230.7 / 230.7 | 72.074 / 72.074 / 72.074 |
| cistern_p05 | 5 | 7.033 / 5.4 / 7.85 | 1.0 / 1.0 / 1.0 | 5.0 / 5.0 / 5.0 | 314.0 / 314.0 / 314.0 | 44.645 / 40.0 / 58.148 | 0.0 / 0.0 / 0.0 | 228.1 / 202.0 / 241.3 | 110.7 / 85.2 / 123.6 | 76.008 / 53.395 / 84.181 |
| cistern_p06 | 3 | 7.3 / 6.9 / 7.333 | 1.0 / 1.0 / 1.0 | 5.0 / 5.0 / 5.0 | 334.0 / 334.0 / 334.0 | 45.753 / 45.545 / 48.406 | 0.0 / 0.0 / 0.0 | 216.8 / 210.4 / 217.8 | 98.1 / 90.9 / 98.4 | 68.95 / 65.217 / 73.182 |
| cistern_p07 | 2 | 9.6 / 9.15 / 10.05 | 1.0 / 1.0 / 1.0 | 5.0 / 5.0 / 5.0 | 334.0 / 334.0 / 334.0 | 34.869 / 33.234 / 36.503 | 0.0 / 0.0 / 0.0 | 272.2 / 266.0 / 278.4 | 154.5 / 146.7 / 162.3 | 59.583 / 49.585 / 69.581 |
| cistern_p08 | 2 | 11.567 / 11.367 / 11.767 | 1.0 / 1.0 / 1.0 | 5.0 / 5.0 / 5.0 | 494.0 / 494.0 / 494.0 | 42.722 / 41.983 / 43.46 | 0.0 / 0.0 / 0.0 | 301.9 / 298.4 / 305.4 | 183.6 / 180.0 / 187.2 | 80.268 / 79.745 / 80.792 |
| cistern_p09 | 5 | 6.75 / 6.633 / 7.033 | 1.0 / 1.0 / 1.0 | 5.0 / 5.0 / 5.0 | 299.0 / 299.0 / 299.0 | 44.296 / 42.512 / 45.075 | 0.0 / 0.0 / 0.0 | 225.4 / 222.2 / 228.6 | 105.9 / 102.6 / 109.2 | 81.28 / 79.899 / 82.963 |
| cistern_p10 | 4 | 21.283 / 19.617 / 28.467 | 2.0 / 2.0 / 2.0 | 7.0 / 7.0 / 7.0 | 579.0 / 579.0 / 579.0 | 27.214 / 20.34 / 29.516 | 0.0 / 0.0 / 0.0 | 459.9 / 431.7 / 579.1 | 342.0 / 313.8 / 460.5 | 78.785 / 78.292 / 80.562 |
| ruins_boss | 5 | 21.85 / 12.217 / 29.15 | 0.0 / 0.0 / 0.0 | 1.0 / 1.0 / 1.0 | 590.0 / 590.0 / 590.0 | 27.002 / 20.24 / 48.295 | 16.0 / 9.0 / 57.0 | 425.0 / 263.6 / 551.0 | 309.6 / 145.5 / 432.0 | 36.426 / 34.096 / 49.59 |
| ruins_c01 | 2 | 0.5 / 0.5 / 0.5 | 1.0 / 1.0 / 1.0 | 1.0 / 1.0 / 1.0 | 95.0 / 95.0 / 95.0 | 190.0 / 190.0 / 190.0 | 0.0 / 0.0 / 0.0 | 121.3 / 121.3 / 121.3 | 3.3 / 3.3 / 3.3 | 36.667 / 36.667 / 36.667 |
| ruins_c02 | 3 | 2.583 / 2.567 / 2.583 | 1.0 / 1.0 / 1.0 | 2.0 / 2.0 / 2.0 | 190.0 / 190.0 / 190.0 | 73.548 / 73.548 / 74.026 | 0.0 / 0.0 / 0.0 | 156.4 / 153.7 / 156.4 | 36.9 / 36.9 / 36.9 | 79.355 / 79.355 / 79.87 |
| ruins_c03 | 3 | 2.4 / 2.383 / 2.4 | 1.0 / 1.0 / 1.0 | 1.0 / 1.0 / 1.0 | 80.0 / 80.0 / 80.0 | 33.333 / 33.333 / 33.566 | 0.0 / 0.0 / 0.0 | 122.7 / 122.7 / 124.0 | 11.4 / 11.4 / 13.5 | 13.194 / 13.194 / 16.783 |
| ruins_c04 | 4 | 5.175 / 3.2 / 6.167 | 1.0 / 1.0 / 1.0 | 2.0 / 2.0 / 2.0 | 175.0 / 175.0 / 175.0 | 34.29 / 28.378 / 54.688 | 11.0 / 0.0 / 22.0 | 198.15 / 164.5 / 214.4 | 79.8 / 47.1 / 95.4 | 69.546 / 66.058 / 75.0 |
| ruins_c05 | 3 | 5.433 / 4.867 / 5.533 | 1.0 / 1.0 / 1.0 | 2.0 / 2.0 / 2.0 | 180.0 / 180.0 / 180.0 | 33.129 / 32.53 / 36.986 | 9.0 / 9.0 / 9.0 | 203.7 / 195.8 / 205.4 | 85.5 / 77.4 / 87.0 | 46.012 / 26.37 / 49.398 |
| ruins_c06 | 4 | 8.392 / 8.233 / 8.65 | 2.0 / 2.0 / 2.0 | 3.0 / 3.0 / 3.0 | 260.0 / 260.0 / 260.0 | 30.985 / 30.058 / 31.579 | 0.0 / 0.0 / 11.0 | 252.05 / 245.8 / 254.0 | 135.45 / 132.6 / 140.4 | 46.67 / 44.509 / 55.8 |
| ruins_c07 | 5 | 5.967 / 5.45 / 7.017 | 2.0 / 2.0 / 2.0 | 3.0 / 3.0 / 3.0 | 255.0 / 255.0 / 255.0 | 42.737 / 36.342 / 46.789 | 11.0 / 0.0 / 11.0 | 211.9 / 201.2 / 228.0 | 93.6 / 84.0 / 111.3 | 70.33 / 61.52 / 73.7 |
| ruins_c08 | 4 | 7.425 / 6.283 / 8.833 | 1.0 / 1.0 / 1.0 | 3.0 / 3.0 / 3.0 | 260.0 / 260.0 / 260.0 | 35.767 / 29.434 / 41.379 | 4.5 / 0.0 / 9.0 | 236.7 / 213.1 / 259.0 | 118.35 / 100.2 / 141.0 | 53.504 / 51.444 / 58.235 |

Time to kill per enemy kind (seconds from first sight to death):

| kind | killed | TTK s (median / min / max) |
|---|---|---|
| bone_thrall | 33 | 0.633 / 0.5 / 3.617 |
| cistern_slime | 31 | 0.95 / 0.567 / 6.633 |
| cistern_slimelet | 62 | 0.667 / 0.017 / 2.767 |
| deep_eel | 19 | 2.15 / 0.983 / 88.767 |
| drowned_acolyte | 20 | 8.209 / 3.25 / 25.65 |
| fallen_adept | 30 | 4.184 / 0.7 / 10.633 |
| grave_hound | 16 | 6.317 / 2.533 / 27.733 |
| lantern_wisp | 14 | 7.009 / 2.567 / 24.467 |
| rust_golem | 11 | 8.3 / 4.133 / 21.3 |
| storm_crystal | 12 | 5.742 / 1.617 / 87.133 |
| undead_warden | 5 | 21.85 / 12.217 / 29.15 |

Boss seconds per phase (rooms with a phased enemy; mini-bosses included):

| room | phase | n | s (median / min / max) |
|---|---|---|---|
| cistern_boss | 1 | 2 | 5.225 / 5.033 / 5.417 |
| cistern_boss | 2 | 2 | 24.883 / 22.733 / 27.033 |
| cistern_challenge_v1 | 1 | 5 | 46.933 / 11.0 / 65.083 |
| cistern_challenge_v1 | 2 | 5 | 23.033 / 8.217 / 40.2 |
| ruins_boss | 1 | 5 | 4.35 / 4.033 / 4.683 |
| ruins_boss | 2 | 5 | 17.8 / 7.717 / 24.783 |

Scripted player sanity (hits = enemy-lost-HP events per tick, so a pierce/burst can exceed 1 per cast):

| hit rate median | idle % median (foe alive, no cast, no dash, mana ok) | no-sight % median | casts per combat minute |
|---|---|---|---|
| 0.477 | 33.399 | 38.496 | 344.759 |

Run totals:

| total min | combat min | walk min | mana spent | mana regen | enemy HP faced | overall DPS |
|---|---|---|---|---|---|---|
| 3.801 / 3.096 / 4.842 | 3.362 / 2.734 / 4.35 | 0.438 / 0.362 / 0.492 | 4745.1 / 4057.1 / 5877.4 | 3208.8 / 2588.7 / 4117.2 | 4892.0 / 4578.0 / 6081.0 | 26.197 / 21.732 / 27.354 |

### skilled

Per room:

| room | n | fight s | waves | enemies | enemy HP | player DPS | dmg taken | mana spent | mana regen | starved % |
|---|---|---|---|---|---|---|---|---|---|---|
| cistern_boss | 1 | 54.667 / 54.667 / 54.667 | 0.0 / 0.0 / 0.0 | 1.0 / 1.0 / 1.0 | 950.0 / 950.0 / 950.0 | 10.037 / 10.037 / 10.037 | 99.0 / 99.0 / 99.0 | 976.7 / 976.7 / 976.7 | 858.0 / 858.0 / 858.0 | 47.317 / 47.317 / 47.317 |
| cistern_challenge_v1 | 5 | 57.533 / 46.35 / 102.717 | 2.0 / 2.0 / 2.0 | 9.0 / 9.0 / 9.0 | 1117.0 / 1117.0 / 1117.0 | 13.517 / 9.688 / 24.099 | 99.0 / 25.0 / 153.0 | 1046.0 / 863.5 / 1834.4 | 951.0 / 760.8 / 1716.3 | 49.499 / 46.714 / 62.208 |
| cistern_p01 | 1 | 5.567 / 5.567 / 5.567 | 1.0 / 1.0 / 1.0 | 3.0 / 3.0 / 3.0 | 270.0 / 270.0 / 270.0 | 48.503 / 48.503 / 48.503 | 11.0 / 11.0 / 11.0 | 204.5 / 204.5 / 204.5 | 86.7 / 86.7 / 86.7 | 82.635 / 82.635 / 82.635 |
| cistern_p02 | 2 | 10.575 / 9.933 / 11.217 | 1.0 / 1.0 / 1.0 | 5.0 / 5.0 / 5.0 | 349.0 / 349.0 / 349.0 | 33.124 / 31.114 / 35.134 | 10.0 / 9.0 / 11.0 | 288.5 / 279.6 / 297.4 | 170.85 / 161.4 / 180.3 | 54.056 / 48.826 / 59.287 |
| cistern_p03 | 2 | 8.041 / 7.483 / 8.6 | 1.0 / 1.0 / 1.0 | 6.0 / 6.0 / 6.0 | 424.0 / 424.0 / 424.0 | 52.981 / 49.302 / 56.659 | 13.5 / 0.0 / 27.0 | 242.25 / 230.7 / 253.8 | 127.5 / 119.4 / 135.6 | 67.334 / 61.024 / 73.643 |
| cistern_p04 | 1 | 9.333 / 9.333 / 9.333 | 2.0 / 2.0 / 2.0 | 6.0 / 6.0 / 6.0 | 424.0 / 424.0 / 424.0 | 45.429 / 45.429 / 45.429 | 0.0 / 0.0 / 0.0 | 265.8 / 265.8 / 265.8 | 148.8 / 148.8 / 148.8 | 67.679 / 67.679 / 67.679 |
| cistern_p05 | 5 | 4.35 / 4.317 / 4.617 | 1.0 / 1.0 / 1.0 | 5.0 / 5.0 / 5.0 | 314.0 / 314.0 / 314.0 | 72.184 / 68.014 / 72.741 | 0.0 / 0.0 / 0.0 | 185.5 / 184.8 / 190.2 | 67.8 / 67.5 / 72.3 | 40.433 / 37.548 / 43.243 |
| cistern_p06 | 3 | 6.55 / 6.417 / 6.55 | 1.0 / 1.0 / 1.0 | 5.0 / 5.0 / 5.0 | 334.0 / 334.0 / 334.0 | 50.992 / 50.992 / 52.052 | 0.0 / 0.0 / 0.0 | 205.3 / 204.5 / 205.3 | 85.8 / 84.9 / 85.8 | 67.532 / 66.667 / 71.756 |
| cistern_p07 | 2 | 9.283 / 7.483 / 11.083 | 1.0 / 1.0 / 1.0 | 5.0 / 5.0 / 5.0 | 334.0 / 334.0 / 334.0 | 37.384 / 30.135 / 44.633 | 5.5 / 0.0 / 11.0 | 268.05 / 240.5 / 295.6 | 150.15 / 121.2 / 179.1 | 50.074 / 47.216 / 52.932 |
| cistern_p08 | 2 | 11.517 / 11.433 / 11.6 | 1.0 / 1.0 / 1.0 | 5.0 / 5.0 / 5.0 | 494.0 / 494.0 / 494.0 | 42.897 / 42.586 / 43.207 | 0.0 / 0.0 / 0.0 | 302.25 / 300.9 / 303.6 | 184.05 / 182.7 / 185.4 | 83.21 / 82.799 / 83.621 |
| cistern_p09 | 5 | 5.917 / 5.083 / 6.083 | 1.0 / 1.0 / 1.0 | 5.0 / 5.0 / 5.0 | 299.0 / 299.0 / 299.0 | 50.535 / 49.151 / 58.82 | 0.0 / 0.0 / 0.0 | 210.4 / 196.9 / 213.1 | 90.9 / 77.4 / 93.6 | 78.592 / 76.721 / 81.37 |
| cistern_p10 | 4 | 18.959 / 18.4 / 26.117 | 2.0 / 2.0 / 2.0 | 7.0 / 7.0 / 7.0 | 579.0 / 579.0 / 579.0 | 30.542 / 22.17 / 31.467 | 0.0 / 0.0 / 0.0 | 421.55 / 412.1 / 536.3 | 303.3 / 294.3 / 419.4 | 79.568 / 77.808 / 81.366 |
| ruins_boss | 5 | 22.9 / 13.983 / 26.817 | 0.0 / 0.0 / 0.0 | 1.0 / 1.0 / 1.0 | 590.0 / 590.0 / 590.0 | 25.764 / 22.001 / 42.193 | 16.0 / 0.0 / 41.0 | 441.7 / 292.9 / 510.0 | 324.9 / 174.9 / 393.0 | 36.76 / 32.155 / 41.359 |
| ruins_c01 | 2 | 0.5 / 0.5 / 0.5 | 1.0 / 1.0 / 1.0 | 1.0 / 1.0 / 1.0 | 95.0 / 95.0 / 95.0 | 190.0 / 190.0 / 190.0 | 0.0 / 0.0 / 0.0 | 121.3 / 121.3 / 121.3 | 3.3 / 3.3 / 3.3 | 36.667 / 36.667 / 36.667 |
| ruins_c02 | 3 | 2.583 / 2.567 / 2.583 | 1.0 / 1.0 / 1.0 | 2.0 / 2.0 / 2.0 | 190.0 / 190.0 / 190.0 | 73.548 / 73.548 / 74.026 | 0.0 / 0.0 / 0.0 | 156.4 / 153.7 / 156.4 | 36.9 / 36.9 / 36.9 | 79.355 / 79.355 / 79.87 |
| ruins_c03 | 3 | 2.417 / 2.417 / 2.433 | 1.0 / 1.0 / 1.0 | 1.0 / 1.0 / 1.0 | 80.0 / 80.0 / 80.0 | 33.103 / 32.877 / 33.103 | 0.0 / 0.0 / 0.0 | 128.1 / 122.7 / 129.4 | 12.3 / 11.1 / 13.5 | 24.828 / 13.103 / 28.082 |
| ruins_c04 | 4 | 3.858 / 3.333 / 6.35 | 1.0 / 1.0 / 1.0 | 2.0 / 2.0 / 2.0 | 175.0 / 175.0 / 175.0 | 45.68 / 27.559 / 52.5 | 11.0 / 11.0 / 11.0 | 175.3 / 167.2 / 214.4 | 57.75 / 49.2 / 98.7 | 76.595 / 70.866 / 81.132 |
| ruins_c05 | 3 | 5.533 / 5.3 / 5.533 | 1.0 / 1.0 / 1.0 | 2.0 / 2.0 / 2.0 | 180.0 / 180.0 / 180.0 | 32.53 / 32.53 / 33.962 | 9.0 / 9.0 / 9.0 | 206.6 / 201.0 / 206.6 | 88.2 / 83.4 / 88.2 | 34.036 / 34.036 / 43.396 |
| ruins_c06 | 4 | 7.5 / 7.05 / 8.467 | 2.0 / 2.0 / 2.0 | 3.0 / 3.0 / 3.0 | 260.0 / 260.0 / 260.0 | 34.701 / 30.709 / 36.879 | 5.5 / 0.0 / 22.0 | 236.95 / 229.6 / 249.8 | 120.45 / 112.5 / 136.2 | 49.763 / 39.908 / 53.233 |
| ruins_c07 | 5 | 5.8 / 5.533 / 6.733 | 2.0 / 2.0 / 2.0 | 3.0 / 3.0 / 3.0 | 255.0 / 255.0 / 255.0 | 43.966 / 37.871 / 46.084 | 11.0 / 0.0 / 11.0 | 209.3 / 204.9 / 222.6 | 89.7 / 85.5 / 105.6 | 71.687 / 63.91 / 74.425 |
| ruins_c08 | 4 | 6.859 / 5.783 / 10.617 | 1.0 / 1.0 / 1.0 | 3.0 / 3.0 / 3.0 | 260.0 / 260.0 / 260.0 | 38.148 / 24.49 / 44.957 | 0.0 / 0.0 / 29.0 | 224.0 / 210.4 / 283.3 | 108.45 / 91.5 / 170.4 | 57.528 / 52.161 / 64.678 |

Time to kill per enemy kind (seconds from first sight to death):

| kind | killed | TTK s (median / min / max) |
|---|---|---|
| bone_thrall | 33 | 0.633 / 0.5 / 2.8 |
| cistern_slime | 31 | 0.917 / 0.617 / 6.967 |
| cistern_slimelet | 62 | 0.034 / 0.017 / 2.0 |
| deep_eel | 17 | 1.083 / 0.883 / 35.433 |
| drowned_acolyte | 20 | 6.566 / 3.35 / 23.183 |
| fallen_adept | 30 | 3.525 / 0.7 / 10.283 |
| grave_hound | 16 | 5.658 / 2.367 / 11.217 |
| lantern_wisp | 14 | 4.258 / 1.65 / 22.033 |
| rust_golem | 11 | 7.467 / 4.3 / 18.9 |
| storm_crystal | 11 | 3.617 / 1.617 / 34.017 |
| undead_warden | 5 | 22.9 / 13.983 / 26.817 |

Boss seconds per phase (rooms with a phased enemy; mini-bosses included):

| room | phase | n | s (median / min / max) |
|---|---|---|---|
| cistern_boss | 1 | 1 | 12.967 / 12.967 / 12.967 |
| cistern_boss | 2 | 1 | 41.7 / 41.7 / 41.7 |
| cistern_challenge_v1 | 1 | 5 | 45.867 / 12.433 / 70.7 |
| cistern_challenge_v1 | 2 | 3 | 20.5 / 11.083 / 21.583 |
| ruins_boss | 1 | 5 | 4.35 / 4.0 / 4.483 |
| ruins_boss | 2 | 5 | 18.4 / 9.617 / 22.45 |

Scripted player sanity (hits = enemy-lost-HP events per tick, so a pierce/burst can exceed 1 per cast):

| hit rate median | idle % median (foe alive, no cast, no dash, mana ok) | no-sight % median | casts per combat minute |
|---|---|---|---|
| 0.535 | 33.718 | 37.291 | 346.013 |

Run totals:

| total min | combat min | walk min | mana spent | mana regen | enemy HP faced | overall DPS |
|---|---|---|---|---|---|---|
| 3.589 / 2.803 / 3.89 | 3.152 / 2.405 / 3.434 | 0.421 / 0.344 / 0.456 | 4530.9 / 3772.6 / 4952.3 | 3002.4 / 2263.2 / 3195.9 | 4892.0 / 4578.0 / 6071.0 | 27.514 / 24.812 / 29.429 |

DIAG_MD_END

## Scripted player sanity

Medians over the 5 seeds: hit rate 0.569 / 0.477 / 0.535 (weak / typical / skilled), idle 30.7 / 33.4 / 33.7 % (foe alive, no cast, no dash, mana available), no-sight 34.1 / 38.5 / 37.3 %, about 345-361 casts per combat minute (about 6 casts/s).

- The bot fires continuously (6 casts/s) and about half of the ticks that carry a cast produce an enemy-lost-HP event. Hit rate is therefore not low enough to blame the bot for fights being too long; pierce/burst can inflate it above 1 per cast, so treat it as an upper-ish figure.
- About a third of foe-alive ticks are idle and a third have no line of sight (kiting, navigating, dodging). That makes bot fights somewhat slower than a focused human, not faster. I estimate a human could cut fight time by perhaps 20-35%, which does not close a 6-10x gap.
- The bot's 0.7 dodge chance plausibly makes it die earlier than a good human in the cistern challenge and boss (damage taken there is 100-150 HP of a 150 HP bar). So the bot is a plausible contributor to cause 2 (early death), but not to cause 1 (too little content HP). The bot is not the main reason runs are short.

## 3 biggest causes (ranked by impact on run length)

### 1. Too little enemy HP and too few rooms/waves per run (content volume)

- Enemy HP faced per run: 4411-6081 (median 5089 weak, 4892 typical, 4892 skilled). Overall player DPS: 25-37 (median 29.0 / 26.2 / 27.5). That gives about 180 s of fighting, which matches the measured combat time (2.7 / 3.4 / 3.2 min median).
- Ruins combat rooms (`ruins_c01..c08`) hold 1-3 enemies and 80-260 HP in 1-2 waves; fights last 0.5-9 s (median). Cistern pool rooms hold 5-7 enemies, 270-579 HP, 1-2 waves, 4-21 s. Per-enemy TTK is short: bone thrall 0.63 s, slimelet about 0.03-0.67 s, slime about 0.9 s, fallen adept 3.5-4.2 s, rust golem 7.5-13.9 s.
- Rooms per run: 11-14 cleared before death; each stage uses 5-6 combat rooms (route mode in AD-158 shows 15-17 rooms and still only 4.1-6.4 min). Walking is only 0.26-0.49 min per run.
- Estimate: to fill 30-40 min at the current ~27 DPS and about 88% combat share, a run needs roughly 45,000-55,000 enemy HP, about 10x the current 4,900.

Data knobs:
- `game/data/difficulty_v1.json:presets.default.enemy_hp` (1.0): global multiplier, the cheapest lever. 2.0 doubles every fight (about +3 min per run, estimate); a 10x change is not sensible, so combine with the rows below. (Check that the bench applies the preset; not verified here.)
- `combat/combat_tuning_v1.json:enemies.<kind>.hp` (bone_thrall 95, fallen_adept 80, grave_hound 85, cistern_slime 120, rust_golem 220, ...): raise per kind.
- `world/data/run_v2.json:stages[].combat_rooms.min/max` (5 / 6 in both stages): raising to 10 / 12 doubles the rooms (about 2x run length, estimate). Adding stages adds more.
- `world/data/run_v2.json:room_templates.<room>.waves[].enemies` and `waves[]` count, plus `max_active_enemies` (8): more or larger waves per room (currently median 1-2 waves).
- `world/data/run_v2.json:bosses.ruins_warden.hp` (590) and `bosses.cistern_boss.hp` (950): bosses fight 22-24 s and 30-55 s now; doubling them adds about 1 min per run (estimate).

### 2. The run ends by death, not completion (150 HP, little recovery)

- 15 of 15 runs die, all in stage 2 (7 in `stage2_rooms`, 8 in `stage2_boss`). Cistern challenge room: median 101 / 115 / 99 HP lost (weak / typical / skilled), max 153; cistern boss median 69.5 HP lost per fight (weak), max 112; ruins boss up to 64.
- Player `max_hp` is 150; the workshop restores HP once (after ruins). Most ruins rooms cost 0-22 HP, so the damage is concentrated in the cistern challenge and boss.
- Effect: even with more content, the run would end at the first lethal cistern encounter (about 11-14 rooms, 3-4 min). Estimate: ending by death costs the 1-3 rooms and the final boss each run, and hides how long a full clear would take.

Data knobs:
- `combat/combat_tuning_v1.json:player.max_hp` (150) and `world/data/run_v2.json:merchant.max_hp_upgrade_amount` (25, price 35): more HP per upgrade or a larger base.
- `world/data/run_v2.json:workshop_restore_hp` (150) and `stages[1].workshop_after` (false in cistern): setting it true gives a second full heal before the cistern boss (estimate: removes most boss-death cases).
- `world/data/run_v2.json:bosses.cistern_boss.water_bolt_damage` (10), `storm_pulse_damage` (14); `bosses.ruins_warden.shot_damage` (16), `radial_damage` (9); lower these to survive longer.
- `game/data/difficulty_v1.json:presets.default.enemy_damage` (1.0) and `player_hp` (1.0).

### 3. High burst kill speed from a mana pool that is drained, then throttled (mana economy)

- Mana spent per run: median 4156 / 4745 / 4531; mana regenerated: 2508 / 3209 / 3002. Spent per combat second is about 25-26 mana/s, regen about 15 mana/s (0.3/tick = 18/s cap). The difference is the 120 starting pool plus workshop restores, so every fight ends up regen-limited: starved 55.6-58.2 % median (target < 20 %).
- Damage per mana is about 1.0 (enemy HP faced / mana spent: 5089/4156, 4892/4745, 4892/4531), so sustained DPS is bounded by regen at roughly 15-18 HP/s plus the pool burst; the measured run DPS (26-29) is about that.
- Starvation is worst in short, dense rooms (cistern_p01/p08/p09/p10 at 78-83 %) and low in bosses (36-49 %), where the bot dodges instead of casting.
- This conflicts with the other two causes: raising fight length by raising enemy HP also raises starvation unless regen/pool/costs move too. A 2x enemy HP with unchanged mana economy would push starvation above 57 % (estimate).

Data knobs:
- `magic/data/magic_balance_v1.json:combat.regen_mana_per_tick` (0.3): doubling to 0.6 halves starved time roughly and lets DPS rise about 1.5-2x (estimate), which shortens fights; so move it together with enemy HP.
- `magic/data/magic_balance_v1.json:combat.player_max_mana` (120): bigger pool delays starvation; merchant `world/data/run_v2.json:merchant.max_mana_upgrade_amount` (20, price 35).
- `magic/data/runes_v2.json:runes[].mana_cost` (fire 5, water 4, lightning 6, cold 5, force 6, projectile 2, burst 8, orb 9, beam 6, field 9, split 4, homing 3, ...) and `magic/data/basic_bolt_v1.json:mana_cost` (3): lower costs reduce starvation; `workshop_restore_mana` (120).
- `game/data/difficulty_v1.json:presets.default.player_mana` (1.0).

## Not changed

No data or gameplay file was touched. `git diff --name-only ad-hermes-2026-11-06` lists only `tests/bench/run_bench.gd` (reporting, from the previous step) and this document. The AD-156 targets stay unmet; all numbers above are measured on the current data.

## Open questions for the owner

1. Should a "winning run" be measured over a full clear (needs the player to survive), or is dying at 11-14 rooms an accepted outcome for the weak build only? The current data kills even skilled/typical builds in stage 2.
2. Preferred way to reach 30-40 min: more rooms/stages, more enemy HP per room, or both? Each interacts with mana starvation (cause 3).
3. Is the starvation target (< 20 %) still wanted if fights get longer, or should it apply to a different measure (for example per boss)?
4. Does the bench apply `game/data/difficulty_v1.json` presets? If so, is `enemy_hp` the intended global pacing lever?
