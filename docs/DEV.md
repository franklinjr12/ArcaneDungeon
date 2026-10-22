# ArcaneDungeon — M0 Developer Guide

- **Tested local engine:** Godot 4.7.2.stable (official), GL Compatibility renderer; this pin is an M0 working choice pending owner approval.
- **Entry scene:** `res://scenes/main.tscn`; launcher buttons open `res://scenes/sandbox.tscn` (interactive M1 prototype) and `res://scenes/arena.tscn` (M2 placeholder).
- **Input actions:** WASD/arrows, Space dodge, left/right mouse cast. M1 Sandbox uses WASD only as a debug caster-positioning aid, with left/right mouse casting two spell slots. Production player combat belongs to M2.
- **Art:** primitive UI elements only; follow `docs/art_direction.md` and the PNG reference before any explicitly assigned asset generation.

## Local commands

Run from repository root with `godot` on PATH or full path to the installed Godot binary.

```sh
godot --headless --path . --editor --quit
godot --headless --path . --script res://tests/run_tests.gd
godot --headless --path . --script res://tests/run_tests.gd -- --self-test-failure
godot --path . --scene res://scenes/main.tscn
```

The intentional-failure command **must exit nonzero**, proving the test runner detects a failure. The Python validation wrapper also scans Godot output for parser/runtime errors (because Godot may exit zero despite script errors), checks launcher navigation and verifies the negative test. The deterministic suite includes M1 target, status, manifestation, event, trigger, loadout and edge-case tests. The scene smoke also exercises Water → Wet → Lightning through actual sandbox controls. Full workflow: `docs/M1_magic_sandbox.md`. The M0 suite deterministically discovers `res://tests/test_*.gd` and validates bundled JSON fixtures. GitHub Actions executes the same two validation steps.

Exports (after user configures and installs suitable export templates/presets; none required for M0):

```sh
godot --headless --path . --export-debug "Windows Desktop" build/ArcaneDungeon.exe
godot --headless --path . --export-release "Linux/X11" build/ArcaneDungeon.x86_64
```

These export commands require corresponding presets and templates and are examples only; do **not** claim exports currently pass.

## Code directories

`scenes/` entry/placeholder scenes; `ui/` launcher plus M1 sandbox controls and primitive debug canvas; `game/core/` clock and diagnostics; `magic/data/` immutable rune data + budget knobs; `magic/compile/` codec, registry, validation and compilation; `magic/runtime/` events and bounded queues; `debug/` opt-in trace; `tests/` headless runner, test scripts and golden fixtures. `combat/` now holds shared M1 target, health, status, and interaction logic; `world/` remains reserved for later dungeon gameplay.

## Debugging

Runtime navigation failures are appended to `user://arcane_errors.log` and printed to stderr. `DebugTrace` stores normalized typed events and can export JSON; disable it without modifying simulation.

Refer to `docs/architecture/magic_contract_v1.md` and `docs/backlog_v1.md` for shared semantics and acceptance tests.
