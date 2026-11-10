# Closed demo build (AD-157)

For Franklin. Windows + Linux export of the closed demo, with opt-in local feedback logs. No upload, no network.

## 1. Prerequisites
- Godot 4.7.1 stable plus the matching export templates (Editor > Manage Export Templates).
- Presets live in `export_presets.cfg`: `Windows Desktop` and `Linux`. `export_path` is empty; you pick it.
- `tests/`, `docs/` and art sources are excluded from the export (see `exclude_filter` in the presets). Runtime JSON is included (`include_filter="*.json"`).

## 2. Before exporting
Set `version` in `game/data/demo_v1.json` (for example `0.1.0-demo`). It shows on the title screen and is written into every log.

## 3. Export and zip
    python3 scripts/export_demo.py --godot <godot>

Optional `--out <dir>` (default `build/demo/<version>/`, git-ignored). The script then verifies the Linux zip (extract to `<out>/_verify`, headless start, `AD_UI_SHOT_STATE` hook inert, `tests/release_probe.gd` debug-key probe in a release build, pack contents); skip with `--no-verify`. On a non-x86_64 host the exported `.pck` runs under the arm64 release template. The Windows zip is exported but not run by the script. Output layout:

    <out>/Sigilwright-<version>-windows.zip
    <out>/Sigilwright-<version>-linux.zip
    <out>/windows/  Sigilwright.exe, Sigilwright.pck, README_FRIENDS.txt
    <out>/linux/    Sigilwright.x86_64, Sigilwright.pck, README_FRIENDS.txt

Each zip holds one folder `Sigilwright-<version>/`. `README_FRIENDS.txt` is `docs/demo/README_FRIENDS.md` plus `docs/demo/FEEDBACK_FORM.md`.
Release exports are not debug builds, so debug keys and menus are unreachable.

## 5. What testers do
Full checklist: [FRANKLIN_TEST.md](FRANKLIN_TEST.md).

1. Settings > Accessibility > turn on **Local telemetry (opt-in)**.
2. Play.
3. Settings > Accessibility > **Open log folder**.
4. Send back every `session_*.json` and `crash_*.txt`.

Log folder (project name `Sigilwright`; `config/use_custom_user_dir` is not set):
- Windows: `%APPDATA%\Godot\app_userdata\Sigilwright\logs`
- Linux: `~/.local/share/godot/app_userdata/Sigilwright/logs`

A `crash_*.txt` appears on the next opted-in launch after an unclean exit.

Reference-PC performance test (Gate G4): [PERF_TEST.md](PERF_TEST.md).
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
