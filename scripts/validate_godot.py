#!/usr/bin/env python3
"""Verify Godot M0-M3 from a clean checkout and fail on engine errors.

Godot's CLI can exit 0 even when a GDScript dependency emits SCRIPT ERROR.
Use this wrapper in CI and locally; do not trust the process code alone.
"""
import argparse
import pathlib
import re
import subprocess
import sys

PROJECT = pathlib.Path(__file__).resolve().parents[1]
ENGINE_FAILURE = re.compile(r"(?m)^(?:SCRIPT ERROR:|ERROR:|WARNING:)")
SUCCESS_SUMMARY = re.compile(r"TEST SUMMARY: [0-9]+ passed / 0 failed / [1-9][0-9]* suites")


def check(godot: str, label: str, args: list[str], should_fail: bool = False) -> bool:
    cmd = [godot, "--headless", "--path", str(PROJECT), *args]
    print(f"\n--- {label} ---", flush=True)
    proc = subprocess.run(cmd, cwd=PROJECT, capture_output=True, text=True, errors="replace", timeout=180)
    combined = proc.stdout + "\n" + proc.stderr
    print(combined, flush=True)
    engine_errors = ENGINE_FAILURE.findall(combined)
    if should_fail:
        okay = proc.returncode != 0 and "intentional failure probe" in combined
    else:
        okay = proc.returncode == 0 and not engine_errors
        if "run_tests.gd" in " ".join(args):
            okay = okay and bool(SUCCESS_SUMMARY.search(combined))
        if "sandbox_ui_smoke.gd" in " ".join(args):
            okay = okay and combined.count("M1 UI PASS:") >= 12
        if "run_ui_smoke.gd" in " ".join(args):
            okay = okay and combined.count("M3 UI PASS:") >= 26
        if "combat_ui_smoke.gd" in " ".join(args):
            okay = okay and combined.count("M2 UI PASS:") >= 17
        if "navigation_smoke.gd" in " ".join(args):
            okay = okay and combined.count("NAVIGATION PASS:") == 4
    print(f"{label}: {'PASS' if okay else 'FAIL'} (exit={proc.returncode}, engine_errors={len(engine_errors)})", flush=True)
    return okay


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--godot", default="godot", help="Godot console binary/executable")
    args = parser.parse_args()
    stages = [
        ("Editor import / parser", ["--editor", "--quit"], False),
        ("Gameplay entry navigation", ["--script", "res://tests/navigation_smoke.gd"], False),
        ("M1 sandbox UI smoke", ["--script", "res://tests/sandbox_ui_smoke.gd"], False),
        ("M2 combat UI smoke", ["--script", "res://tests/combat_ui_smoke.gd"], False),
        ("M3 vertical slice UI smoke", ["--script", "res://tests/run_ui_smoke.gd"], False),
        ("Deterministic test suite", ["--script", "res://tests/run_tests.gd"], False),
        ("Negative failure probe", ["--script", "res://tests/run_tests.gd", "--", "--self-test-failure"], True),
    ]
    failed = False
    for label, argv, negative in stages:
        if not check(args.godot, label, argv, negative):
            failed = True
    return 1 if failed else 0


if __name__ == "__main__":
    sys.exit(main())
