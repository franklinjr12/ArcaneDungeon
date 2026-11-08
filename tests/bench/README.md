# Demo full-run bench

`run_bench.gd` plays the whole `world/data/run_v2.json` run with a scripted player for the `weak`, `typical` and `skilled` builds over 20 seeds (`SEEDS`, 20261022..20261041) and prints the BENCH_MD tables used by `docs/benchmarks/ad_demo_bench.md`. No gameplay change; sims run with `record_trace=false`.

G = `/usr/local/bin/godot --headless --path . --script res://tests/bench/run_bench.gd --`

## Options

| flag | meaning |
|---|---|
| `--seeds=N` | legacy: first N seeds, all in one process, prints the tables, replays the first seed per build as a determinism check |
| `--seeds=A..B` | chunk mode: 0-based inclusive indices into `SEEDS`; one result file per seed+build; existing results are skipped; no determinism replay |
| `--builds=a,b` | subset of builds (default all three) |
| `--results=DIR` | result folder (default `user://bench_results`) |
| `--jobs=N` | run N headless child processes in parallel (use 2 on the 2-core host) |
| `--summarize` | build the BENCH_MD tables from the result files; runs nothing |
| `--trace` | record sim traces (slower; for debugging only) |

## Full 20 seed x 3 build workflow

```
G --seeds=0..4 --jobs=2
G --seeds=5..9 --jobs=2
G --seeds=10..14 --jobs=2
G --seeds=15..19 --jobs=2
G --summarize
```

Each chunk prints `AD_DEMO_BENCH_WALL seed=... build=... wall_s=...` per pair. If a step is interrupted, re-run the same chunk command: finished pairs print `AD_DEMO_BENCH_SKIP` and only the rest are played. `--summarize` over an incomplete set still exits 0 but prints `AD_DEMO_BENCH_PARTIAL have=.. want=.. missing=..`.

## Result files

`DIR/<seed>_<build>.json` holds `{fingerprint, trace, wall_seconds, run}`. The fingerprint covers the bench script and the files it depends on; if it differs, the pair is re-played. Code changes outside the fingerprinted files are not detected: use a fresh `--results` folder after them. Do not commit result folders.

## Related

`tests/bench/boss_pacing_bench.gd` checks the final-boss window 150-210 s and may exit 1 on the current balance.
