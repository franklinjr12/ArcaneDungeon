# ArcaneDungeon — M0–M3 Developer Guide

- **Tested local engine:** Godot 4.7.2.stable (official), GL Compatibility renderer; this pin is an M0 working choice pending owner approval.
- **Entry scene:** `res://scenes/main.tscn`; launcher buttons open `res://scenes/sandbox.tscn` (interactive M1 prototype) and `res://scenes/arena.tscn` (M2 playable combat arena) and `res://scenes/run.tscn` (M3 short vertical slice).
- **Input actions:** WASD/arrows, Space dodge, left/right mouse cast. M1 Sandbox uses WASD only as a debug caster-positioning aid, with left/right mouse casting two spell slots. M2 Combat Arena uses the shared M1 runner plus directional dodge, HUD and three enemy archetypes. See `docs/M2_combat.md` and `docs/M3_vertical_slice.md`.
- **Art:** primitive UI elements only; follow `docs/art_direction.md` and the PNG reference before any explicitly assigned asset generation.

## Local commands

Run from repository root with `godot` on PATH or full path to the installed Godot binary.

```sh
godot --headless --path . --editor --quit
godot --headless --path . --script res://tests/run_tests.gd
godot --headless --path . --script res://tests/run_tests.gd -- --self-test-failure
godot --path . --scene res://scenes/main.tscn
```

The intentional-failure command **must exit nonzero**, proving the test runner detects a failure. The Python validation wrapper also scans Godot output for parser/runtime errors (because Godot may exit zero despite script errors), checks launcher navigation and verifies the negative test. The deterministic suite also includes M3 room sequencing, save validation, reward/shop/editor semantics, boss telegraphs, real-command full-route replay and UI scene smoke. The full M3 route uses `tests/m3_run_driver.gd` under seed `20261022`. The deterministic suite includes M1 target, status, manifestation, event, trigger, loadout and edge-case tests. The scene smokes exercise Water → Wet → Lightning through the M1 sandbox and casting/dodge/pause/retry through M2 combat. The M2 deterministic baseline is fixed in `tests/fixtures/m2_baseline_v1.json`. Full workflow: `docs/M1_magic_sandbox.md`. The M0 suite deterministically discovers `res://tests/test_*.gd` and validates bundled JSON fixtures. GitHub Actions executes the same two validation steps.

Exports (after user configures and installs suitable export templates/presets; none required for M0):

```sh
godot --headless --path . --export-debug "Windows Desktop" build/ArcaneDungeon.exe
godot --headless --path . --export-release "Linux/X11" build/ArcaneDungeon.x86_64
```

These export commands require corresponding presets and templates and are examples only; do **not** claim exports currently pass.

## Code directories

`scenes/` launcher, M1 sandbox, M2 arena and M0 placeholder legacy scenes; `ui/` launcher plus M1 sandbox controls and primitive debug canvas; `game/core/` clock and diagnostics; `magic/data/` immutable rune data + budget knobs; `magic/compile/` codec, registry, validation and compilation; `magic/runtime/` events and bounded queues; `debug/` opt-in trace; `tests/` headless runner, test scripts and golden fixtures. `combat/` now holds shared M1 target, health, status, and interaction logic; `world/` now contains M2 obstacle geometry; it does not implement M3 room progression.

## Debugging

Runtime navigation failures are appended to `user://arcane_errors.log` and printed to stderr. `DebugTrace` stores normalized typed events and can export JSON; disable it without modifying simulation.

Refer to `docs/architecture/magic_contract_v1.md` and `docs/backlog_v1.md` for shared semantics and acceptance tests.
