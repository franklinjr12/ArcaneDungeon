#!/usr/bin/env python3
"""AD-030: copy published P0 art exports into art/export/ and write manifest.json."""
import argparse
import json
import shutil
import sys
from pathlib import Path

REPO = Path(__file__).resolve().parent.parent
DRIVE = Path.home() / "Google Drive/Games/ArcaneDungeon/Art/Tasks"
FALLBACK = Path("/workspace/art/arcane_dungeon")
CATS = {"chr", "enm", "bos", "npc", "por", "til", "prp", "ui", "fnt"}


def category(stem):
    parts = stem.split("_")
    cat = parts[1] if len(parts) > 1 else ""
    if parts[0] == "arc" and cat == "fnt":
        return "fnt"
    if "ui" in parts[:2]:
        return "ui"
    return cat if cat in CATS else ""


def find_row(sources, row):
    for s in sources:
        if (s / row / "export").is_dir():
            return s / row
    return None


def build_entry(stem, row, rowdir, errors):
    jpath = rowdir / "export" / (stem + ".json")
    ppath = rowdir / "export" / (stem + ".png")
    data = json.loads(jpath.read_text())
    card = None
    for c in sorted((rowdir / "cards").glob("*.json")):
        cd = json.loads(c.read_text())
        if cd.get("name") == stem:
            card = cd
            break
    if card is None:
        errors.append(f"{stem}: no card with name == stem in {row}/cards")
        return None
    cat = category(stem)
    if not cat:
        errors.append(f"{stem}: cannot derive category")
        return None
    frames = data.get("frames", [])
    meta = data.get("meta", {})
    entry = {"id": card["id"], "row": row, "category": cat,
             "png": f"res://art/export/{cat}/{stem}.png" if frames else None,
             "json": f"res://art/export/{cat}/{stem}.json",
             "canvas": None, "tags": {}, "slices": {}, "pivot": None}
    if not frames:
        entry["kind"] = "swap_table"
        return entry
    if not ppath.is_file():
        errors.append(f"{stem}: missing png")
    sz = frames[0]["sourceSize"]
    entry["canvas"] = [sz["w"], sz["h"]]
    for t in meta.get("frameTags", []):
        a, b = t["from"], t["to"]
        if not (0 <= a <= b < len(frames)):
            errors.append(f"{stem}: tag {t['name']} indices {a}..{b} out of range ({len(frames)} frames)")
            continue
        entry["tags"][t["name"]] = {"from": a, "to": b, "frames": b - a + 1,
                                    "ms": [frames[i]["duration"] for i in range(a, b + 1)]}
    for s in meta.get("slices", []):
        bd = s["keys"][0]["bounds"]
        entry["slices"][s["name"]] = {k: bd[k] for k in ("x", "y", "w", "h")}
    if "pivot" in entry["slices"]:
        p = entry["slices"]["pivot"]
        entry["pivot"] = [p["x"], p["y"]]
    else:
        errors.append(f"{stem}: missing pivot slice")
    return entry


def main():
    ap = argparse.ArgumentParser(description=__doc__)
    ap.add_argument("--source", action="append", type=Path)
    ap.add_argument("--rows", nargs="+", default=["AD-024", "AD-025", "AD-029"])
    ap.add_argument("--dest", type=Path, default=REPO / "art/export")
    ap.add_argument("--check", action="store_true")
    a = ap.parse_args()
    sources = a.source or [DRIVE if DRIVE.is_dir() else FALLBACK]
    errors, assets, copies = [], {}, []
    for row in a.rows:
        rowdir = find_row(sources, row)
        if rowdir is None:
            errors.append(f"{row}: export dir not found in {[str(s) for s in sources]}")
            continue
        for j in sorted((rowdir / "export").glob("*.json")):
            e = build_entry(j.stem, row, rowdir, errors)
            if e is None:
                continue
            if j.stem in assets:
                errors.append(f"{j.stem}: duplicate stem")
            assets[j.stem] = e
            copies.append((j, a.dest / e["category"] / j.name))
            if e["png"]:
                copies.append((j.with_suffix(".png"), a.dest / e["category"] / (j.stem + ".png")))
    if errors:
        print("import_art_exports: FAILED\n  " + "\n  ".join(errors), file=sys.stderr)
        return 1
    manifest = json.dumps({"version": 1, "source_rows": list(a.rows), "assets": assets},
                          sort_keys=True, indent=1) + "\n"
    if a.check:
        print(f"OK: {len(assets)} assets")
        return 0
    for src, dst in copies:
        dst.parent.mkdir(parents=True, exist_ok=True)
        shutil.copyfile(src, dst)
    (a.dest / "manifest.json").write_text(manifest)
    print(f"wrote {len(assets)} assets to {a.dest}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
