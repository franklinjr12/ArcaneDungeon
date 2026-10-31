#!/usr/bin/env python3
"""Verify Godot M0-M4 from a clean checkout and fail on engine errors.

Godot's CLI can exit 0 even when a GDScript dependency emits SCRIPT ERROR.
Use this wrapper in CI and locally; do not trust the process code alone.
"""
import argparse
import os
import pathlib
import re
import subprocess
import sys
import time

PROJECT = pathlib.Path(__file__).resolve().parents[1]
ENGINE_FAILURE = re.compile(r"(?m)^(?:SCRIPT ERROR:|ERROR:|WARNING:)")
SUCCESS_SUMMARY = re.compile(r"TEST SUMMARY: [0-9]+ passed / 0 failed / [1-9][0-9]* suites")


def _text(value: bytes | str | None) -> str:
    if value is None:
        return ""
    if isinstance(value, bytes):
        return value.decode("utf-8", errors="replace")
    return value


def check(godot: str, label: str, args: list[str], timeout: float, should_fail: bool = False) -> bool:
    cmd = [godot, "--headless", "--path", str(PROJECT), *args]
    print(f"\n--- {label} ---", flush=True)
    start = time.monotonic()
    try:
        proc = subprocess.run(cmd, cwd=PROJECT, capture_output=True, text=True, errors="replace", timeout=timeout)
    except subprocess.TimeoutExpired as exc:
        elapsed = time.monotonic() - start
        print(_text(exc.stdout) + "\n" + _text(exc.stderr), flush=True)
        print(f"{label}: FAIL (timeout after {timeout:g}s, elapsed={elapsed:.1f}s)", flush=True)
        return False
    elapsed = time.monotonic() - start
    combined = proc.stdout + "\n" + proc.stderr
    print(combined, flush=True)
    engine_errors = ENGINE_FAILURE.findall(combined)
    if should_fail:
        okay = proc.returncode != 0 and "intentional failure probe" in combined
    else:
        okay = proc.returncode == 0 and not engine_errors
        if "run_tests.gd" in " ".join(args):
            okay = okay and bool(SUCCESS_SUMMARY.search(combined))
        if "m4_stress_probe.gd" in " ".join(args):
            okay = okay and "M4_STRESS:" in combined
        if "sandbox_ui_smoke.gd" in " ".join(args):
            okay = okay and combined.count("M1 UI PASS:") >= 12
        if "run_ui_smoke.gd" in " ".join(args):
            okay = okay and combined.count("M3 UI PASS:") >= 26
        if "combat_ui_smoke.gd" in " ".join(args):
            okay = okay and combined.count("M2 UI PASS:") >= 17
        if "navigation_smoke.gd" in " ".join(args):
            okay = okay and combined.count("NAVIGATION PASS:") == 4
    print(f"{label}: {'PASS' if okay else 'FAIL'} (exit={proc.returncode}, engine_errors={len(engine_errors)}, elapsed={elapsed:.1f}s)", flush=True)
    return okay


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--godot", default="godot", help="Godot console binary/executable")
    parser.add_argument(
        "--timeout",
        type=float,
        default=None,
        help="per-stage timeout in seconds for every stage; overrides env AD_VALIDATE_TIMEOUT "
        "(default: 600 for editor import, 300 for other stages)",
    )
    args = parser.parse_args()
    override = args.timeout
    if override is None and os.environ.get("AD_VALIDATE_TIMEOUT"):
        try:
            override = float(os.environ["AD_VALIDATE_TIMEOUT"])
        except ValueError:
            print(f"error: AD_VALIDATE_TIMEOUT must be a number of seconds, got {os.environ['AD_VALIDATE_TIMEOUT']!r}", flush=True)
            return 2
    stages = [
        ("Editor import / parser", ["--editor", "--quit"], False, 600),
        ("Gameplay entry navigation", ["--script", "res://tests/navigation_smoke.gd"], False, 300),
        ("M1 sandbox UI smoke", ["--script", "res://tests/sandbox_ui_smoke.gd"], False, 300),
        ("M2 combat UI smoke", ["--script", "res://tests/combat_ui_smoke.gd"], False, 300),
        ("M3 vertical slice UI smoke", ["--script", "res://tests/run_ui_smoke.gd"], False, 300),
        ("Deterministic test suite", ["--script", "res://tests/run_tests.gd"], False, 300),
        ("M4 40-target stress profile", ["--script", "res://tests/m4_stress_probe.gd"], False, 300),
        ("Negative failure probe", ["--script", "res://tests/run_tests.gd", "--", "--self-test-failure"], True, 300),
    ]
    failed = False
    for label, argv, negative, stage_timeout in stages:
        timeout = override if override is not None else stage_timeout
        if not check(args.godot, label, argv, timeout, negative):
            failed = True
    return 1 if failed else 0


if __name__ == "__main__":
    sys.exit(main())
