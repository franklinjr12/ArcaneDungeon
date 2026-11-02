#!/usr/bin/env python3
"""AD-030: copy published art exports into art/export/ and write manifest.json.

P0 (default rows): AD-024 AD-025 AD-029.
P1 (AD-039): python3 scripts/import_art_exports.py \\
    --rows AD-024 AD-025 AD-029 AD-032 AD-033 AD-034 AD-045 AD-035 AD-036 --supersede AD-045
P1 UI (AD-040): same plus "AD-037 AD-038" before --supersede (HUD parts, reward card). A json with no
card and no png (ad_ui_9slice_margins) is a side file; a card json without 'frames' uses <stem>_aseprite.json.
AD-045 status_* / extinguish_puff replace the AD-034 ones (--supersede). vfx/ico stems have no
pivot slice requirement (pivot = canvas centre); the AD-036 glyph atlas is kind 'glyph_atlas'.

Actors (AD-065): python3 scripts/import_art_exports.py --actors  copies the mage/enemy/warden animation sheets
(no cards, AD-063 nested) to art/export/actors/ and writes actors/actors_manifest.json only.
"""
import argparse
import json
import shutil
import sys
from pathlib import Path

REPO = Path(__file__).resolve().parent.parent
DRIVE = Path.home() / "Google Drive/Games/ArcaneDungeon/Art/Tasks"
FALLBACK = Path("/workspace/art/arcane_dungeon")
CATS = {"chr", "enm", "bos", "npc", "por", "til", "prp", "ui", "fnt", "vfx", "ico"}


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


def load_cards(rowdir):
    cards = {}
    for c in sorted((rowdir / "cards").glob("*.json")):
        cd = json.loads(c.read_text())
        cards[cd.get("name")] = cd
    return cards


def is_side_file(stem, cards, rowdir):
    if stem in cards:
        return False
    return any(stem.startswith(n + "_") for n in cards if n) or not (rowdir / "export" / (stem + ".png")).is_file()


def build_entry(stem, row, rowdir, cards, errors):
    jpath = rowdir / "export" / (stem + ".json")
    ppath = rowdir / "export" / (stem + ".png")
    data = json.loads(jpath.read_text())
    card = cards.get(stem)
    if card is None:
        errors.append(f"{stem}: no card with name == stem in {row}/cards")
        return None
    cat = category(stem)
    if not cat:
        errors.append(f"{stem}: cannot derive category")
        return None
    if "frames" not in data and "glyphs" in data and "atlas_png" in data:
        if not ppath.is_file():
            errors.append(f"{stem}: missing png")
        return {"id": card["id"], "row": row, "category": cat, "kind": "glyph_atlas",
                "png": f"res://art/export/{cat}/{stem}.png",
                "json": f"res://art/export/{cat}/{stem}.json",
                "canvas": data["canvas"], "tags": {}, "slices": {}, "pivot": None}
    aseprite = jpath.with_name(stem + "_aseprite.json")
    if "frames" not in data and aseprite.is_file():
        data = json.loads(aseprite.read_text())
        jname = aseprite.name
    else:
        jname = jpath.name
    frames = data.get("frames", [])
    meta = data.get("meta", {})
    entry = {"id": card["id"], "row": row, "category": cat,
             "png": f"res://art/export/{cat}/{stem}.png" if frames else None,
             "json": f"res://art/export/{cat}/{jname}",
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
    elif cat in ("vfx", "ico"):
        entry["pivot"] = [sz["w"] / 2, sz["h"] / 2]
    else:
        errors.append(f"{stem}: missing pivot slice")
    return entry


A = "res://art/export/actors/"
WARDEN_MAIN = ["idle_side", "move_side", "telegraph_burst_side", "burst_side", "telegraph_dash_side", "dash_side"]
WARDEN_LATE = ["phase_side", "hit_side", "death_side"]
# kind: rows, sheets{key: (src stem path, dest stem, has_left)}, tag filter per sheet (None = all)
ACTORS = {
    "mage": {"rows": ["AD-061", "AD-062", "AD-064"], "sheets": {"main": ("AD-064/export/ad_chr_mage", "ad_chr_mage", False, None)}},
    "bone_thrall": {"rows": ["AD-052"], "sheets": {"main": ("AD-052/export/ad_enm_bone_thrall", "ad_enm_bone_thrall", False, None)}},
    "fallen_adept": {"rows": ["AD-053", "AD-063"], "sheets": {"main": ("AD-063/adept/export/ad_enm_fallen_adept", "ad_enm_fallen_adept", True, None)}},
    "grave_hound": {"rows": ["AD-054", "AD-063"], "sheets": {"main": ("AD-063/hound/export/ad_enm_grave_hound", "ad_enm_grave_hound", True, None)}},
    "undead_warden": {"rows": ["AD-055", "AD-056", "AD-063", "AD-064"], "sheets": {
        "main": ("AD-063/warden/export/ad_bos_ossuary_warden", "ad_bos_ossuary_warden", True, WARDEN_MAIN),
        "late": ("AD-064/export/ad_bos_ossuary_warden", "ad_bos_ossuary_warden_late", True, WARDEN_LATE)}},
}


def slice_bounds(data, name):
    for sl in data["meta"].get("slices", []):
        if sl["name"] == name:
            bd = sl["keys"][0]["bounds"]
            return {k: bd[k] for k in ("x", "y", "w", "h")}
    return None


def tag_table(data):
    frames = data["frames"]
    out = {}
    for t in data["meta"].get("frameTags", []):
        out[t["name"]] = (t["from"], t["to"], [frames[i]["duration"] for i in range(t["from"], min(t["to"], len(frames) - 1) + 1)])
    return out


def import_actors(a):
    root = (a.source or [DRIVE if DRIVE.is_dir() else FALLBACK])[0]
    errors, copies, actors = [], [], {}
    for kind, spec in ACTORS.items():
        ent = {"rows": spec["rows"], "mirror": not any(v[2] for v in spec["sheets"].values()),
               "sheets": {}, "tags": {}}
        for key, (src, dstem, left, want) in spec["sheets"].items():
            jp, pp = root / (src + ".json"), root / (src + ".png")
            if not jp.is_file() or not pp.is_file():
                errors.append(f"{kind}/{key}: missing {src}.json/.png")
                continue
            data = json.loads(jp.read_text())
            frames = data["frames"]
            tags = tag_table(data)
            for n, (f, t, _) in tags.items():
                if not (0 <= f <= t < len(frames)):
                    errors.append(f"{kind}/{key}: tag {n} indices {f}..{t} out of range ({len(frames)} frames)")
            pivot, hb = slice_bounds(data, "pivot"), slice_bounds(data, "hurtbox")
            if pivot is None:
                errors.append(f"{kind}/{key}: missing pivot slice")
            if hb is None:
                errors.append(f"{kind}/{key}: missing hurtbox slice")
            sz = frames[0]["sourceSize"]
            sh = {"png": A + dstem + ".png", "json": A + dstem + ".json", "left_png": None, "left_json": None,
                  "canvas": [sz["w"], sz["h"]], "pivot": pivot and [pivot["x"], pivot["y"]], "hurtbox": hb,
                  "left_pivot": None, "left_hurtbox": None}
            copies += [(jp, a.dest / "actors" / (dstem + ".json")), (pp, a.dest / "actors" / (dstem + ".png"))]
            if left:
                lj, lp = root / (src + "_left.json"), root / (src + "_left.png")
                if not lj.is_file() or not lp.is_file():
                    errors.append(f"{kind}/{key}: missing {src}_left.json/.png")
                else:
                    ld = json.loads(lj.read_text())
                    if tag_table(ld) != tags:
                        errors.append(f"{kind}/{key}: _left tags differ from main sheet")
                    lpv, lhb = slice_bounds(ld, "pivot"), slice_bounds(ld, "hurtbox")
                    if lpv is None or lhb is None:
                        errors.append(f"{kind}/{key}: _left missing pivot/hurtbox slice")
                    else:
                        sh.update({"left_png": A + dstem + "_left.png", "left_json": A + dstem + "_left.json",
                                   "left_pivot": [lpv["x"], lpv["y"]], "left_hurtbox": lhb})
                    copies += [(lj, a.dest / "actors" / (dstem + "_left.json")), (lp, a.dest / "actors" / (dstem + "_left.png"))]
            ent["sheets"][key] = sh
            for n in (want if want is not None else list(tags)):
                if n not in tags:
                    errors.append(f"{kind}/{key}: tag {n} not in json")
                    continue
                f, t, ms = tags[n]
                ent["tags"][n] = {"sheet": key, "from": f, "to": t, "frames": t - f + 1, "ms": ms}
        actors[kind] = ent
    if errors:
        print("import_art_exports --actors: FAILED\n  " + "\n  ".join(errors), file=sys.stderr)
        return 1
    if a.check:
        print(f"OK: {len(actors)} actors")
        return 0
    for src, dst in copies:
        dst.parent.mkdir(parents=True, exist_ok=True)
        shutil.copyfile(src, dst)
    (a.dest / "actors" / "actors_manifest.json").write_text(
        json.dumps({"version": 1, "scale": 2, "actors": actors}, sort_keys=True, indent=1) + "\n")
    print(f"wrote {len(actors)} actors to {a.dest / 'actors'}")
    return 0


def main():
    ap = argparse.ArgumentParser(description=__doc__)
    ap.add_argument("--source", action="append", type=Path)
    ap.add_argument("--rows", nargs="+", default=["AD-024", "AD-025", "AD-029"])
    ap.add_argument("--dest", type=Path, default=REPO / "art/export")
    ap.add_argument("--supersede", action="append", default=[], metavar="ROW",
                    help="on a duplicate stem the entry from this row replaces the earlier one")
    ap.add_argument("--check", action="store_true")
    ap.add_argument("--actors", action="store_true", help="import actor animation sheets only (AD-065)")
    a = ap.parse_args()
    if a.actors:
        return import_actors(a)
    sources = a.source or [DRIVE if DRIVE.is_dir() else FALLBACK]
    errors, assets, copies = [], {}, []
    for row in a.rows:
        rowdir = find_row(sources, row)
        if rowdir is None:
            errors.append(f"{row}: export dir not found in {[str(s) for s in sources]}")
            continue
        cards = load_cards(rowdir)
        for j in sorted((rowdir / "export").glob("*.json")):
            if is_side_file(j.stem, cards, rowdir):
                side = a.dest / category(j.stem) / j.name
                copies.append((j, side))
                continue
            e = build_entry(j.stem, row, rowdir, cards, errors)
            if e is None:
                continue
            if j.stem in assets:
                if row in a.supersede:
                    dst = a.dest / e["category"] / j.stem
                    copies = [c for c in copies if c[1].with_suffix("") != dst]
                else:
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
