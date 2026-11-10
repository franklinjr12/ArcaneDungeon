#!/usr/bin/env python3
"""Build the friends demo: headless Windows + Linux release exports, zipped with a README.

Usage: python3 scripts/export_demo.py --godot <godot> [--out <dir>]
"""
import argparse
import json
import os
import pathlib
import platform
import re
import shutil
import subprocess
import sys
import zipfile

sys.path.insert(0, str(pathlib.Path(__file__).resolve().parent))
from validate_godot import ensure_imported  # noqa: E402

PROJECT = pathlib.Path(__file__).resolve().parents[1]
TEMPLATES_HINT = "Export templates must be installed at ~/.local/share/godot/export_templates/4.7.1.stable/"
TARGETS = [
    # (preset, folder, binary name)
    ("Windows Desktop", "windows", "Sigilwright.exe"),
    ("Linux", "linux", "Sigilwright.x86_64"),
]


def read_version() -> str:
    try:
        data = json.loads((PROJECT / "game" / "data" / "demo_v1.json").read_text(encoding="utf-8"))
    except (OSError, ValueError) as exc:
        raise SystemExit(f"error: cannot read game/data/demo_v1.json: {exc}")
    version = data.get("version") if isinstance(data, dict) else None
    if not isinstance(version, str) or not version.strip():
        raise SystemExit("error: game/data/demo_v1.json has no non-empty 'version' string")
    return version.strip()


def export(godot: str, preset: str, folder: pathlib.Path, binary: str) -> None:
    if folder.exists():
        shutil.rmtree(folder)
    folder.mkdir(parents=True)
    target = folder / binary
    cmd = [godot, "--headless", "--path", str(PROJECT), "--export-release", preset, str(target)]
    print(f"\n--- Export {preset} ---", flush=True)
    proc = subprocess.run(cmd, cwd=PROJECT, capture_output=True, text=True, errors="replace", timeout=900)
    print(proc.stdout + "\n" + proc.stderr, flush=True)
    pck = target.with_suffix(".pck")
    problems = []
    if proc.returncode != 0:
        problems.append(f"exit code {proc.returncode}")
    for path in (target, pck):
        if not path.is_file() or path.stat().st_size == 0:
            problems.append(f"missing or empty {path.name}")
    if problems:
        raise SystemExit(f"error: {preset} export failed ({'; '.join(problems)}). {TEMPLATES_HINT}")


def write_readme(folder: pathlib.Path, version: str) -> None:
    friends = (PROJECT / "docs" / "demo" / "README_FRIENDS.md").read_text(encoding="utf-8").replace("@VERSION@", version)
    form = (PROJECT / "docs" / "demo" / "FEEDBACK_FORM.md").read_text(encoding="utf-8")
    (folder / "README_FRIENDS.txt").write_text(friends.rstrip("\n") + "\n\n" + form, encoding="utf-8")


def write_perf_bats(folder: pathlib.Path) -> None:
    """Double-click launchers for the reference-PC perf run (AD-187). CRLF so cmd.exe reads them cleanly."""
    for level in ("high", "low"):
        lines = [
            "@echo off",
            'cd /d "%~dp0"',
            "echo Performance test running, please wait...",
            f'start /wait "" Sigilwright.exe --resolution 1920x1080 -- --perf-run --perf-lighting={level}',
            'explorer "%APPDATA%\\Godot\\app_userdata\\Sigilwright\\perf"',
        ]
        (folder / f"perf_test_{level}.bat").write_bytes(("\r\n".join(lines) + "\r\n").encode("ascii"))


def make_zip(folder: pathlib.Path, zip_path: pathlib.Path, version: str) -> None:
    top = f"Sigilwright-{version}"
    with zipfile.ZipFile(zip_path, "w", zipfile.ZIP_DEFLATED) as zf:
        for path in sorted(folder.iterdir()):
            zf.write(path, f"{top}/{path.name}")


def _run_verify(label: str, cmd: list, env: dict, must_contain: str = "") -> str:
    try:
        proc = subprocess.run(cmd, cwd=PROJECT, env=env, capture_output=True, text=True, errors="replace", timeout=120)
    except subprocess.TimeoutExpired as exc:
        raise SystemExit(f"error: verify {label} timed out\n{exc.stdout or ''}")
    output = (proc.stdout or "") + "\n" + (proc.stderr or "")
    bad = []
    if proc.returncode != 0:
        bad.append(f"exit code {proc.returncode}")
    for marker in ("SCRIPT ERROR", "Parse Error"):
        if marker in output:
            bad.append(f"output contains '{marker}'")
    if must_contain and must_contain not in output:
        bad.append(f"output lacks '{must_contain}'")
    if bad:
        print(output)
        raise SystemExit(f"error: verify {label} failed ({'; '.join(bad)})")
    return output


TEMPLATE_DIR = pathlib.Path.home() / ".local/share/godot/export_templates/4.7.1.stable"
PACK_EXCLUDED = (b"tests/run_tests", b"docs/demo/", b"art/source/", b"art/aseprite/")


def check_pack_bytes(pck: pathlib.Path) -> None:
    data = pck.read_bytes()
    for needle in PACK_EXCLUDED:
        if needle in data:
            raise SystemExit(f"error: {pck.name} contains {needle.decode()}")


def build_probe_binary(verify: pathlib.Path, godot: str) -> tuple:
    """Export a throwaway copy of the project whose main scene hosts tests/release_probe.gd.

    Release templates refuse --script/--path/--main-pack, so the probe has to live inside a
    real release export. The copy drops docs/ and art sources; the shipped pack is checked
    separately (check_pack_bytes). Uses the host-architecture Linux template.
    """
    arch = "arm64" if platform.machine() in ("aarch64", "arm64") else "x86_64"
    proj = verify / "probe_project"
    shutil.copytree(PROJECT, proj, ignore=shutil.ignore_patterns(
        ".git", "build", "docs", ".indiegameharness", "source", "aseprite", "previews", "_inputs"))
    # Release templates ignore --script, so host the probe in a Node scene (SceneTree members -> get_tree()).
    src = (proj / "tests" / "release_probe.gd").read_text(encoding="utf-8")
    src = src.replace("extends SceneTree", "extends Node").replace("func _initialize()", "func _ready()")
    src = re.sub(r"\b(?<!\.)(root|process_frame|quit)\b(?=[.(\s)])", r"get_tree().\1", src)
    (proj / "tests" / "release_probe_host.gd").write_text(src, encoding="utf-8")
    (proj / "tests" / "release_probe_host.tscn").write_text(
        '[gd_scene load_steps=2 format=3]\n\n[ext_resource type="Script" path="res://tests/release_probe_host.gd" id="1"]\n\n'
        '[node name="Probe" type="Node"]\nscript = ExtResource("1")\n', encoding="utf-8")
    cfg = (proj / "project.godot").read_text(encoding="utf-8")
    real_main = re.search(r'run/main_scene="([^"]*)"', cfg).group(1)
    cfg, n = re.subn(r'run/main_scene="[^"]*"', 'run/main_scene="res://tests/release_probe_host.tscn"', cfg)
    if n != 1:
        raise SystemExit("error: project.godot main_scene not found")
    (proj / "project.godot").write_text(cfg, encoding="utf-8")
    probe_args = ["--skip-pack", f"--main-scene={real_main}"]
    presets = (proj / "export_presets.cfg").read_text(encoding="utf-8")
    presets = presets.replace("tests/*, ", "").replace(
        'binary_format/architecture="x86_64"', f'binary_format/architecture="{arch}"')
    (proj / "export_presets.cfg").write_text(presets, encoding="utf-8")
    target = verify / "probe" / "probe.x86_64"
    target.parent.mkdir()
    proc = subprocess.run([godot, "--headless", "--path", str(proj), "--export-release", "Linux", str(target)],
                          capture_output=True, text=True, errors="replace", timeout=900)
    if proc.returncode != 0 or not target.is_file():
        print(proc.stdout + proc.stderr)
        raise SystemExit("error: probe export failed")
    return target, probe_args


def verify_linux(zip_path: pathlib.Path, out: pathlib.Path, godot: str) -> None:
    """Extract the Linux zip and run it: clean headless start, no shot hook, release probe."""
    verify = out / "_verify"
    if verify.exists():
        shutil.rmtree(verify)
    verify.mkdir(parents=True)
    with zipfile.ZipFile(zip_path) as zf:
        zf.extractall(verify)
    shipped = next(verify.glob("*/Sigilwright.x86_64"))
    shipped.chmod(0o755)
    binary = shipped
    native = platform.machine() in ("x86_64", "AMD64")
    if not native:
        # x86_64 binary cannot execute here: run the shipped .pck under the host-arch release template.
        binary = shipped.with_name("Sigilwright")
        shutil.copy(TEMPLATE_DIR / "linux_release.arm64", binary)
        binary.chmod(0o755)
        print(f"note: host is {platform.machine()}; running the exported pack with the arm64 release template")
    env = dict(os.environ, XDG_DATA_HOME=str(verify / "xdg"))
    shot = verify / "shot.png"
    _run_verify("headless start", [str(binary), "--headless", "--quit-after", "120"], env)
    print("PASS: linux export starts headless and quits cleanly")
    _run_verify("AD_UI_SHOT_STATE", [str(binary), "--headless", "--quit-after", "120"],
                dict(env, AD_UI_SHOT_STATE="title", AD_UI_SHOT_OUT=str(shot)))
    if shot.exists():
        raise SystemExit("error: verify AD_UI_SHOT_STATE: shot.png was written by the release build")
    print("PASS: AD_UI_SHOT_STATE hook inert in release build")
    check_pack_bytes(shipped.with_suffix(".pck"))
    probe_bin, probe_args = build_probe_binary(verify, godot)
    # The probe pack deliberately contains tests/, so its pack-contents check is skipped; the shipped pck was checked above.
    _run_verify("release probe", [str(probe_bin), "--headless", "--"] + probe_args, env, "RELEASE_PROBE OK")
    print("PASS: release probe (debug keys, title, arena, run) + shipped pck contents")
    _run_verify("perf run", [str(binary), "--headless", "--", "--perf-run", "--perf-ticks=30"], env, "PERF_RUN_OK")
    reports = sorted((verify / "xdg" / "godot" / "app_userdata" / "Sigilwright" / "perf").glob("*.json"),
                     key=lambda p: p.stat().st_mtime)
    if not reports:
        raise SystemExit("error: verify perf run: no report json written")
    report = json.loads(reports[-1].read_text(encoding="utf-8"))
    rooms = report.get("rooms", [])
    want = ["ruins_c07", "cistern_p10", "ruins_boss", "cistern_boss"]
    ok = isinstance(report.get("lighting"), str) and [r.get("room_id") for r in rooms] == want
    ok = ok and all(isinstance(r.get(k), dict) and all(m in r[k] for m in ("p50", "p95", "max"))
                    for r in rooms for k in ("frame_ms", "sim_ms"))
    if not ok:
        raise SystemExit(f"error: verify perf run: bad report schema in {reports[-1].name}")
    print("PASS: perf run on shipped binary writes a valid report (4 rooms)")


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--godot", default="godot", help="Godot executable")
    parser.add_argument("--no-verify", action="store_true", help="skip running the Linux zip")
    parser.add_argument("--out", default=None, help="output dir (default <repo>/build/demo/<version>)")
    args = parser.parse_args()
    version = read_version()
    out = pathlib.Path(args.out).resolve() if args.out else PROJECT / "build" / "demo" / version
    if not ensure_imported(args.godot, 600):
        return 1
    build_root = PROJECT / "build"
    if out == build_root or build_root in out.parents:
        build_root.mkdir(parents=True, exist_ok=True)
        (build_root / ".gdignore").touch()
    out.mkdir(parents=True, exist_ok=True)
    zips = []
    for preset, name, binary in TARGETS:
        folder = out / name
        export(args.godot, preset, folder, binary)
        write_readme(folder, version)
        if name == "windows":
            write_perf_bats(folder)
        zip_path = out / f"Sigilwright-{version}-{name}.zip"
        make_zip(folder, zip_path, version)
        zips.append(zip_path)
    print()
    for z in zips:
        print(f"{z} ({z.stat().st_size / 1048576:.1f} MB)")
    if not args.no_verify:
        print("\n--- Verify Linux zip ---", flush=True)
        verify_linux(zips[-1], out, args.godot)
    return 0


if __name__ == "__main__":
    sys.exit(main())
