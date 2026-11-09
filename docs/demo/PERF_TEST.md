# Reference-PC performance test (AD-187, Gate G4)

For Franklin. Gate G4: **60 FPS at 1080p on the reference PC** (i5 11th gen / GTX 1660). This kit measures it; it does not optimise anything.

## How to run
1. Unzip the Windows package (`Sigilwright-<version>-windows.zip`).
2. Close other programs.
3. Double-click `perf_test_high.bat`.
4. Do not touch the game window. No input is needed. It plays four rooms of 600 frames each (plus a short warmup) and takes roughly a minute or less.
5. When it ends, a folder opens with the result.

Result file: `%APPDATA%\Godot\app_userdata\Sigilwright\perf\<timestamp>.json`

## What PASS means
Every room has `frame_ms.p95 <= 16.7` at lighting `"high"`.

If any room fails, double-click `perf_test_low.bat` and record that result too. Low is a retest, not a pass at High.

## Reading the JSON
- `lighting`: `high` or `low` (the level used).
- `window_size`: must be `[1920, 1080]`.
- `headless`: must be `false`. If `true`, the numbers are not valid.
- `rooms[]`: `ruins_c07`, `cistern_p10`, `ruins_boss`, `cistern_boss`. Each has `frame_ms` and `sim_ms`, each with `p50`, `p95`, `max`, plus `pass` (true when `frame_ms.p95` is within the target).

Vsync is disabled during the run, so the numbers show the true cost of a frame.

## Notes
- The runs use a fixed seed and a fixed script, and do not touch saves or settings.
- No optimisation is part of this kit.
- Live overlay: Settings > Video > Show FPS.
- Linux / headless, for reference: `./Sigilwright.x86_64 --headless -- --perf-run`. Headless frame numbers are not valid for the gate.
