# Closed demo build (AD-157)

For Franklin. Windows + Linux export of the closed demo, with opt-in local feedback logs. No upload, no network.

## 1. Prerequisites
- Godot 4.7.1 stable plus the matching export templates (Editor > Manage Export Templates).
- Presets live in `export_presets.cfg`: `Windows Desktop` and `Linux`. `export_path` is empty; you pick it.
- `tests/` stays in the pack on purpose (the headless route check needs `tests/bench/run_bench.gd`).

## 2. Before exporting
In `project.godot` bump `application/config/version` and set `application/config/build_stamp`
(for example `2026-11-07-<short sha>`). Both show on the title screen and are written into every log.

## 3. Windows export (on your Windows machine)
Use the console exe so errors print:

    Godot_v4.7.1-stable_win64_console.exe --headless --path <repo> --export-release "Windows Desktop" <out>\ArcaneDungeon.exe

Or in the editor: Project > Export > Windows Desktop > Export Project. Zip the `.exe` and the `.pck` together
(`embed_pck=false`).

## 4. Linux export
    godot --headless --path <repo> --export-release "Linux" <out>/ArcaneDungeon.x86_64

Route check from a pack (no templates needed for `--export-pack`; outputs go outside the repo, never commit a `.pck`):

    mkdir -p /tmp/ad157_export
    godot --headless --path <repo> --export-pack "Linux" /tmp/ad157_export/ArcaneDungeon.pck
    godot --headless --main-pack /tmp/ad157_export/ArcaneDungeon.pck --script res://tests/bench/run_bench.gd -- --seeds=1 --builds=typical

Expected: exit 0, bench tables printed, no `SCRIPT ERROR`.
Verified on 2026-11-07 with Godot 4.7.1 (no export templates installed on that machine, so the full
`--export-release` binary was not produced there; only the pack).

## 5. What testers do
Full checklist: [FRANKLIN_TEST.md](FRANKLIN_TEST.md).

1. Settings > Accessibility > turn on **Local telemetry (opt-in)**.
2. Play.
3. Settings > Accessibility > **Open log folder**.
4. Send back every `session_*.json` and `crash_*.txt`.

Log folder (project name `ArcaneDungeon`; `config/use_custom_user_dir` is not set):
- Windows: `%APPDATA%\Godot\app_userdata\ArcaneDungeon\logs`
- Linux: `~/.local/share/godot/app_userdata/ArcaneDungeon/logs`

A `crash_*.txt` appears on the next opted-in launch after an unclean exit.

Friends feedback form and F8 reports: [FEEDBACK_FORM.md](FEEDBACK_FORM.md).
Onboarding audit, tip ids and triggers (Gate G2): [ONBOARDING.md](ONBOARDING.md).

## 6. Privacy
Nothing is uploaded; there is no network code. Logs are written only when the tester opts in. They hold anonymous
counts and timings plus the build stamp: no names, no free text.
F8 reports are saved only when the player presses F8 and do include a screenshot and the typed note.

## 7. Summarising
`scripts/summarize_m4_playtest.py --observations <obs.json> --log <session_x.json> [--log ...] --output <out>`
reads the session JSON (`--observations` is required: a manually anonymised observation file, see
`docs/playtests/M4_playtest_protocol.md`). There is no log-only summary tool yet.

## 8. Validate before shipping
    python3 scripts/validate_godot.py --godot /usr/local/bin/godot

QA sweep results and known issues: [docs/benchmarks/ad_demo_qa.md](../benchmarks/ad_demo_qa.md) (scripts: `tests/qa/demo_smoke.gd`, `tests/qa/demo_perf_probe.gd`).
