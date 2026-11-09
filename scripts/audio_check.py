#!/usr/bin/env python3
"""AD-188: audio drop check and missing-sound report (stdlib only).

Lists every sound id in game/audio/audio_cues_v1.json, marks which ones still use
a placeholder or are silent, checks dropped files, and writes docs/demo/AUDIO_STATUS.md.
Never generates audio. Usage: audio_check.py [--root DIR] [--cues FILE] [--output FILE]
"""
import argparse
import io
import json
import math
import re
import struct
import sys
import wave
from pathlib import Path, PurePosixPath

import gen_placeholder_audio as gen

ROOT = Path(__file__).resolve().parent.parent

# PROPOSED QA limits, not approved design (the Demo Plan gives no numbers).
ALLOWED_SUFFIXES = ('.wav', '.ogg')
# 32 kHz is musicgen-small's native rate; Godot resamples on import.
ALLOWED_RATES = (32000, 44100, 48000)
MAX_PEAK_DBFS = -1.0
LENGTH_SEC = {'music': (15.0, 300.0), 'ambience': (5.0, 120.0), 'sfx': (0.03, 5.0), 'telegraph': (0.1, 1.5)}
# Loop seam: |sample at loop end - sample at loop start| as a fraction of full scale.
LOOP_SEAM_MAX = 0.1
# The loop end may sit at most this many frames before the file end.
LOOP_END_TOLERANCE_FRAMES = 2048
PEAK_LIMIT = 32768 * 10 ** (MAX_PEAK_DBFS / 20)
UNMAPPED_SUFFIXES = ('.wav', '.ogg', '.mp3', '.flac', '.m4a', '.opus', '.aiff')
GROUP_ORDER = ('music', 'ambience', 'sfx')
GROUP_TITLE = {'music': 'Music', 'ambience': 'Ambience', 'sfx': 'SFX'}
MISSING = ('placeholder', 'silent')


def rel(res):
    """res:// path -> repo-relative posix path (res:// is the repo root)."""
    return res[len('res://'):] if res.startswith('res://') else res


def dbfs(peak):
    return 20 * math.log10(peak / 32768.0) if peak else float('-inf')


def length_key(entry):
    return 'telegraph' if entry['telegraph'] else entry['group']


def build_entries(data):
    unstealable = int(data.get('unstealable_priority', 3))
    entries = []
    for cue_id, cue in data['cues'].items():
        entries.append({
            'id': cue_id,
            'group': 'ambience' if cue.get('bus') == 'Ambience' else 'sfx',
            'stream': cue['stream'],
            'placeholder': cue.get('placeholder', ''),
            'loop': bool(cue.get('loop', False)),
            'telegraph': int(cue.get('priority', 1)) >= unstealable,
        })
    for ctx, cfg in data.get('music', {}).get('contexts', {}).items():
        entries.append({
            'id': 'music.' + ctx,
            'group': 'music',
            'stream': cfg['stream'],
            'placeholder': cfg.get('placeholder', ''),
            'loop': True,
            'telegraph': False,
        })
    return entries


def is_generated(cue_id, path, cache):
    """True if the file is the generator's output (samples may differ by 1 from float rounding)."""
    if cue_id not in gen.SYNTH:
        return False
    if cue_id not in cache:
        samples = gen.render(cue_id)
        cache[cue_id] = (gen.wav_bytes(samples, cue_id.startswith('amb.')), len(samples))
    expected, n = cache[cue_id]
    data = path.read_bytes()
    if data == expected:
        return True
    if len(data) != len(expected):
        return False
    got = struct.unpack_from('<%dh' % n, data, 44)
    want = struct.unpack_from('<%dh' % n, expected, 44)
    return max(abs(a - b) for a, b in zip(got, want)) <= 1


def classify(entry, root, cache):
    stream = root / rel(entry['stream'])
    ph = rel(entry['placeholder']) if entry['placeholder'] else ''
    ph_ok = bool(ph) and (root / ph).is_file()
    if not stream.is_file():
        entry['status'] = 'placeholder' if ph_ok else 'silent'
        entry['fallback'] = ph if ph_ok else 'none (silent)'
    elif is_generated(entry['id'], stream, cache):
        entry['status'] = 'placeholder'
        entry['fallback'] = 'generated placeholder (same file)'
    else:
        entry['status'] = 'dropped'
        entry['fallback'] = ''


def check_format_length(rate, n, entry, problems):
    if rate not in ALLOWED_RATES:
        problems.append('sample rate %d not in %s' % (rate, ALLOWED_RATES))
    secs = n / rate if rate else 0.0
    lo, hi = LENGTH_SEC[length_key(entry)]
    if not lo <= secs <= hi:
        problems.append('length %.2f s outside %g-%g s' % (secs, lo, hi))


def check_loop_bounds(start, end, n, problems):
    if not 0 <= start < end <= n - 1:
        problems.append('loop %d-%d outside the file' % (start, end))
        return False
    if n - 1 - end > LOOP_END_TOLERANCE_FRAMES:
        problems.append('loop end %d is more than %d frames before the file end' % (end, LOOP_END_TOLERANCE_FRAMES))
        return False
    return True


def find_smpl_loop(data):
    """First loop in the WAV smpl chunk as (start, end) frames, or None."""
    pos = 12
    while pos + 8 <= len(data):
        cid = data[pos:pos + 4]
        size = struct.unpack_from('<I', data, pos + 4)[0]
        body = pos + 8
        if cid == b'smpl' and size >= 60 and struct.unpack_from('<I', data, body + 28)[0] >= 1:
            return struct.unpack_from('<II', data, body + 44)
        pos = body + size + (size & 1)
    return None


def check_wav(path, entry, problems):
    data = path.read_bytes()
    try:
        with wave.open(io.BytesIO(data), 'rb') as w:
            ch, width, rate, n = w.getnchannels(), w.getsampwidth(), w.getframerate(), w.getnframes()
            raw = w.readframes(n)
    except (wave.Error, EOFError) as err:
        problems.append('not a readable PCM WAV (%s)' % err)
        return
    if width != 2:
        problems.append('%d-bit samples, need 16-bit' % (8 * width))
        return
    check_format_length(rate, n, entry, problems)
    samples = struct.unpack_from('<%dh' % (len(raw) // 2), raw)
    peak = max((abs(v) for v in samples), default=0)
    if peak > PEAK_LIMIT:
        problems.append('peak %.1f dBFS above %g dBFS' % (dbfs(peak), MAX_PEAK_DBFS))
    if entry['loop']:
        loop = find_smpl_loop(data)
        if loop is None:
            problems.append('loop points missing (smpl chunk)')
        elif check_loop_bounds(loop[0], loop[1], n, problems):
            jump = abs(samples[loop[1] * ch] - samples[loop[0] * ch]) / 32768.0
            if jump > LOOP_SEAM_MAX:
                problems.append('loop seam jump %.3f above %g' % (jump, LOOP_SEAM_MAX))


def check_ogg(path, entry, problems, notes):
    data = path.read_bytes()
    ident = data.find(b'\x01vorbis', 0, 4096)
    if data[:4] != b'OggS' or ident < 0:
        problems.append('not a readable Ogg Vorbis file')
        return
    rate = struct.unpack_from('<I', data, ident + 12)[0]
    last = data.rfind(b'OggS')
    n = struct.unpack_from('<q', data, last + 6)[0] if last >= 0 else 0
    check_format_length(rate, max(n, 0), entry, problems)
    notes.append('peak and loop seam not checked for ogg (no stdlib decoder)')
    if entry['loop']:
        head = data[:65536]
        start = re.search(rb'LOOPSTART=(\d+)', head, re.IGNORECASE)
        length = re.search(rb'LOOPLENGTH=(\d+)', head, re.IGNORECASE)
        if not start or not length:
            problems.append('loop points missing (LOOPSTART/LOOPLENGTH comments)')
        else:
            s = int(start.group(1))
            check_loop_bounds(s, s + int(length.group(1)), n, problems)


def check_file(path, entry):
    """Returns (problems, notes) for a dropped file; empty problems means it passes."""
    problems, notes = [], []
    suffix = path.suffix.lower()
    if suffix not in ALLOWED_SUFFIXES:
        problems.append('format %s is not wav or ogg' % suffix)
    elif suffix == '.wav':
        check_wav(path, entry, problems)
    else:
        check_ogg(path, entry, problems, notes)
    return problems, notes


def find_unmapped(root, entries):
    """Audio files under assets/audio that no cue uses as stream or placeholder: [(path, hint)]."""
    mapped = set()
    streams = []
    for e in entries:
        mapped.add(rel(e['stream']))
        streams.append(rel(e['stream']))
        if e['placeholder']:
            mapped.add(rel(e['placeholder']))
    audio = root / 'assets' / 'audio'
    found = []
    if not audio.is_dir():
        return found
    for f in sorted(audio.rglob('*')):
        if not f.is_file() or f.suffix.lower() not in UNMAPPED_SUFFIXES:
            continue
        r = f.relative_to(root).as_posix()
        if r in mapped:
            continue
        hint = ''
        rp = PurePosixPath(r)
        for s in sorted(streams):
            sp = PurePosixPath(s)
            if sp.parent == rp.parent and sp.stem == rp.stem:
                hint = 'runtime loads only %s' % s
                break
        found.append((r, hint))
    return found


def md_table(headers, rows):
    lines = ['| ' + ' | '.join(headers) + ' |', '|' + '---|' * len(headers)]
    lines += ['| ' + ' | '.join(r) + ' |' for r in rows]
    return lines


def target_text(entry):
    lo, hi = LENGTH_SEC[length_key(entry)]
    text = '%s, %g-%g s' % (PurePosixPath(entry['stream']).suffix.lstrip('.'), lo, hi)
    return text + (', loop' if entry['loop'] else '')


def section_lines(rows, headers, empty='None.'):
    return md_table(headers, rows) if rows else [empty]


def render_report(entries, unmapped):
    ordered = sorted(entries, key=lambda e: (GROUP_ORDER.index(e['group']), e['id']))
    out = ['# Audio status (AD-188)', '',
           'Regenerate: `python3 scripts/audio_check.py` (reads game/audio/audio_cues_v1.json and assets/audio/).', '']

    summary = []
    for g in GROUP_ORDER:
        items = [e for e in entries if e['group'] == g]
        summary.append((GROUP_TITLE[g], len(items),
                        sum(e['status'] in MISSING for e in items),
                        sum(e['status'] == 'dropped' for e in items)))
    summary.append(('Total', len(entries), sum(e['status'] in MISSING for e in entries),
                    sum(e['status'] == 'dropped' for e in entries)))
    out += md_table(['group', 'total', 'placeholder or silent', 'dropped'],
                    [[str(c) if isinstance(c, int) else c for c in row] for row in summary])
    out.append('')

    out += ['## Missing: generate these', '']
    for g in GROUP_ORDER:
        rows = [[e['id'], rel(e['stream']), e['fallback'], target_text(e)]
                for e in ordered if e['group'] == g and e['status'] in MISSING]
        out += ['### ' + GROUP_TITLE[g], '']
        out += section_lines(rows, ['id', 'file to create', 'current fallback', 'target']) + ['']

    out += ['## Dropped files', '']
    out += section_lines([[e['id'], rel(e['stream'])] for e in ordered if e['status'] == 'dropped'],
                         ['id', 'file']) + ['']

    out += ['## Unmapped files', '']
    out += section_lines([[r, hint] for r, hint in unmapped], ['file', 'hint']) + ['']

    out += ['## All sound ids', '']
    out += md_table(['id', 'group', 'status'], [[e['id'], e['group'], e['status']] for e in ordered]) + ['']

    out += ['## Proposed QA limits (PROPOSED, not approved design)', '',
            '- Formats: %s' % ', '.join(ALLOWED_SUFFIXES),
            '- Sample rates: %s Hz (32 kHz is musicgen-small native; Godot resamples)' % ', '.join(map(str, ALLOWED_RATES)),
            '- Loudness peak: <= %g dBFS' % MAX_PEAK_DBFS]
    out += ['- Length: %s' % '; '.join('%s %g-%g s' % (k, lo, hi) for k, (lo, hi) in LENGTH_SEC.items())]
    out += ['- Loop (music, loop cues): seam jump <= %g of full scale; loop end within %d frames of file end'
            % (LOOP_SEAM_MAX, LOOP_END_TOLERANCE_FRAMES),
            '- Ogg: peak and loop seam are not checked (no stdlib decoder)', '']
    return '\n'.join(out) + '\n'


def main(argv=None):
    ap = argparse.ArgumentParser(description='AD-188 audio drop check')
    ap.add_argument('--root', type=Path, default=ROOT)
    ap.add_argument('--cues', type=Path, default=None)
    ap.add_argument('--output', type=Path, default=None)
    args = ap.parse_args(argv)
    root = args.root.resolve()
    cues = args.cues or root / 'game' / 'audio' / 'audio_cues_v1.json'
    output = args.output or root / 'docs' / 'demo' / 'AUDIO_STATUS.md'

    entries = build_entries(json.loads(cues.read_text(encoding='utf-8')))
    cache = {}
    for e in entries:
        classify(e, root, cache)
        if e['status'] == 'dropped':
            e['problems'], e['notes'] = check_file(root / rel(e['stream']), e)
        else:
            e['problems'], e['notes'] = [], []
    unmapped = find_unmapped(root, entries)

    ordered = sorted(entries, key=lambda e: (GROUP_ORDER.index(e['group']), e['id']))
    for e in ordered:
        print('%s %s %s' % (e['id'], e['group'], e['status']))
        for p in e['problems']:
            print('  problem %s: %s' % (e['id'], p))
        for n in e['notes']:
            print('  note %s: %s' % (e['id'], n))
    for g in GROUP_ORDER:
        items = [e for e in entries if e['group'] == g]
        print('%s: total %d, placeholder or silent %d, dropped %d' % (
            GROUP_TITLE[g], len(items), sum(e['status'] in MISSING for e in items),
            sum(e['status'] == 'dropped' for e in items)))
    for r, hint in unmapped:
        print('unmapped %s%s' % (r, ' (%s)' % hint if hint else ''))

    output.parent.mkdir(parents=True, exist_ok=True)
    with open(output, 'w', encoding='utf-8', newline='\n') as f:
        f.write(render_report(entries, unmapped))
    print('wrote %s' % output)
    return 1 if unmapped else 0


if __name__ == '__main__':
    sys.exit(main())
