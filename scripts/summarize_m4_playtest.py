#!/usr/bin/env python3
"""M4 offline playtest synthesis. No network, accounts, recordings or PII collection.
Only opt-in local logs plus manually anonymized observation JSON supplied by tester.
Never label unperformed playtests as successful.
"""
from __future__ import annotations
import argparse
import json
import pathlib
import statistics

TARGETS = [
    ("Two distinct spells unaided", "two_distinct_spells_unaided", 5),
    ("Predicts Wet→Lightning", "predicts_wet_lightning", 4),
    ("Voluntarily edits after new rune", "voluntary_edit", 4),
]
def read_json(path: pathlib.Path) -> dict:
    data = json.loads(path.read_text(encoding="utf-8"))
    if not isinstance(data, dict):
        raise ValueError(f"Not JSON object: {path}")
    return data

def summarize(log_files: list[pathlib.Path], observations: dict) -> str:
    rows = observations.get("sessions", [])
    if not isinstance(rows, list):
        raise ValueError("observations.sessions must be an array")
    unique_ids = [str(r.get("anonymous_id","")) for r in rows]
    if len(set(unique_ids)) != len(unique_ids):
        raise ValueError("Duplicate anonymous session IDs")
    if any(not item or not item.startswith("T-") for item in unique_ids):
        raise ValueError("Use anonymous IDs like T-001; no participant names")
    valid_logs = []
    for path in log_files:
        data = read_json(path)
        if data.get("anonymous") is not True or data.get("external_upload") is not False:
            raise ValueError(f"Not a M4 local opt-in anonymous log: {path}")
        valid_logs.append(data)
    times = []
    counts = {}
    signatures = set()
    for log in valid_logs:
        for event in log.get("events", []):
            kind = event.get("type")
            if kind:
                counts[kind] = counts.get(kind, 0) + 1
            fields = event.get("fields", {})
            if "edit_to_test_ms" in fields:
                times.append(float(fields["edit_to_test_ms"]) / 1000)
            if "formula_signature" in fields:
                signatures.add(str(fields["formula_signature"]))
    total = len(rows)
    complete = total >= 6 and all(r.get("completed") is True for r in rows)
    lines = [
        "# ArcaneDungeon M4 — First Human Playtest Findings",
        "",
        f"**Evidence status:** {'SIX+ SESSIONS RECORDED — OWNER REVIEW STILL REQUIRED' if complete else 'PENDING human sessions; no go/no-go possible'}",
        f"**Anonymized session count:** {total}; **opt-in local logs:** {len(valid_logs)}",
        "No participant identities or external analytics are included.",
        "",
        "## Proposed thresholds vs observed data",
        "",
        "| Hypothesis (not approved KPI) | Proposed target | Observed | Status |",
        "| --- | --- | --- | --- |",
    ]
    for label, key, threshold in TARGETS:
        yes = sum(r.get(key) is True for r in rows)
        known = sum(isinstance(r.get(key), bool) for r in rows)
        status = "PENDING" if not complete or known < 6 else ("MEETS" if yes >= threshold else "BELOW")
        lines.append(f"| {label} | {threshold}/6 | {yes}/{known} recorded | {status} |")
    median = statistics.median(times) if times else None
    edit_status = "PENDING" if not complete or median is None else ("MEETS" if median < 45 else "BELOW")
    lines.append(f"| Median edit-to-test | <45 s | {f'{median:.2f}s' if median is not None else 'no opt-in samples'} | {edit_status} |")
    failures = sum(r.get("crash_or_softlock") is True for r in rows)
    lines.append(f"| Crashes / softlocks | 0 | {failures} reported | {'PENDING' if not complete else 'MEETS' if failures == 0 else 'BELOW'} |")
    fps = [float(r["normal_room_fps"]) for r in rows if isinstance(r.get("normal_room_fps"), (int, float))]
    lines.append(f"| Reference normal-room FPS | 60 FPS | {f'{min(fps):.1f} lowest documented sample' if fps else 'hardware/FPS not recorded'} | {'PENDING' if not complete or not fps else 'MEETS' if min(fps)>=60 else 'BELOW'} |")
    lines += ["","## Local opt-in experiment summary","",
        f"- Event counts: `{json.dumps(counts,sort_keys=True)}`",
        f"- Distinct mechanical formula signatures: {len(signatures)} (not a substitute for human-observed spell diversity)",
        f"- Edit-to-test samples: {len(times)}; median: {f'{median:.2f}s' if median is not None else 'pending'}",
        "",
        "## Qualitative observations (anonymous, provided by testers)",
        ""]
    for row in rows:
        label = row["anonymous_id"]
        lines.append(f"### {label}")
        for key, prompt in [
            ("expected_spell_behavior","Predicted formula behavior"),
            ("unexpected_behavior","What surprised them"),
            ("wanted_to_try","What they wanted to experiment with"),
            ("editor_usability","Editor usability"),
            ("magic_depth","Magic system depth"),
            ("combat_feel","Combat readability / feel"),
            ("failure_clip_or_steps","Failure clip reference or reproduction steps")]:
            value = str(row.get(key,"")).strip()
            lines.append(f"- **{prompt}:** {value if value else 'Not recorded'}")
        lines.append("")
    lines += ["## Five changes prioritized by observed evidence", "",
        "1. PENDING — observation, evidence and owner decision required",
        "2. PENDING — observation, evidence and owner decision required",
        "3. PENDING — observation, evidence and owner decision required",
        "4. PENDING — observation, evidence and owner decision required",
        "5. PENDING — observation, evidence and owner decision required",
        "",
        "## Go / revise grammar / revise combat / pause",
        "",
        "**Decision: PENDING explicit owner approval.** No v2 schema migration or POST scope authorized.",
        ""]
    return "\n".join(lines)

def main() -> int:
    parser=argparse.ArgumentParser()
    parser.add_argument("--observations",type=pathlib.Path,required=True)
    parser.add_argument("--log",type=pathlib.Path,action="append",default=[])
    parser.add_argument("--output",type=pathlib.Path,required=True)
    args=parser.parse_args()
    report=summarize(args.log,read_json(args.observations))
    args.output.parent.mkdir(parents=True,exist_ok=True)
    args.output.write_text(report,encoding="utf-8")
    print("Created local findings draft:",args.output)
    return 0

if __name__ == "__main__":
    raise SystemExit(main())
