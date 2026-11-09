#!/usr/bin/env python3
"""Build the friends demo: headless Windows + Linux release exports, zipped with a README.

Usage: python3 scripts/export_demo.py --godot <godot> [--out <dir>]
"""
import argparse
import json
import pathlib
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


def make_zip(folder: pathlib.Path, zip_path: pathlib.Path, version: str) -> None:
    top = f"Sigilwright-{version}"
    with zipfile.ZipFile(zip_path, "w", zipfile.ZIP_DEFLATED) as zf:
        for path in sorted(folder.iterdir()):
            zf.write(path, f"{top}/{path.name}")


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--godot", default="godot", help="Godot executable")
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
        zip_path = out / f"Sigilwright-{version}-{name}.zip"
        make_zip(folder, zip_path, version)
        zips.append(zip_path)
    print()
    for z in zips:
        print(f"{z} ({z.stat().st_size / 1048576:.1f} MB)")
    return 0


if __name__ == "__main__":
    sys.exit(main())
