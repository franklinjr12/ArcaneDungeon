#!/usr/bin/env python3
"""AD-188: audio drop check and missing-sound report (stdlib only).

Lists every sound id in game/audio/audio_cues_v1.json, marks which ones still use
a placeholder or are silent, checks dropped files, and writes docs/demo/AUDIO_STATUS.md.
Never generates audio. Usage: audio_check.py [--root DIR] [--cues FILE] [--output FILE]
"""
import argparse
import json
import math
import shutil
import struct
import subprocess
import sys
from array import array
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
UNMAPPED_SUFFIXES = ('.wav', '.ogg', '.mp3', '.flac', '.m4a', '.opus', '.aiff')
GROUP_ORDER = ('music', 'ambience', 'sfx')
GROUP_TITLE = {'music': 'Music', 'ambience': 'Ambience', 'sfx': 'SFX'}
MISSING = ('placeholder', 'silent')
# Hand-written block kept across regeneration (AD-191 cue tuning notes).
CUE_CHANGES_START = '<!-- cue-changes:start -->'
CUE_CHANGES_END = '<!-- cue-changes:end -->'


def rel(res):
    """res:// path -> repo-relative posix path (res:// is the repo root)."""
    return res[len('res://'):] if res.startswith('res://') else res


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


def le_array(code, raw):
    """array from little-endian bytes (whole items only)."""
    a = array(code)
    a.frombytes(raw[:len(raw) - len(raw) % a.itemsize])
    if sys.byteorder == 'big':
        a.byteswap()
    return a


def read_wav(path):
    """Parse a WAV: dict(rate, channels, frames, samples (full scale = 1.0), loop (start, end inclusive) or None).
    Raises ValueError with a message for anything unreadable."""
    data = Path(path).read_bytes()
    if len(data) < 12 or data[:4] != b'RIFF' or data[8:12] != b'WAVE':
        raise ValueError('not a RIFF/WAVE file')
    fmt = pcm = loop = None
    pos = 12
    while pos + 8 <= len(data):
        cid = data[pos:pos + 4]
        size = struct.unpack_from('<I', data, pos + 4)[0]
        body = pos + 8
        chunk = data[body:body + size]
        if cid == b'fmt ':
            if len(chunk) < 16:
                raise ValueError('truncated fmt chunk')
            tag, ch, rate, _, _, bits = struct.unpack_from('<HHIIHH', chunk, 0)
            if tag == 0xFFFE:
                if len(chunk) < 26:
                    raise ValueError('truncated WAVE_FORMAT_EXTENSIBLE fmt chunk')
                tag = struct.unpack_from('<H', chunk, 24)[0]
            fmt = (tag, ch, rate, bits)
        elif cid == b'data' and pcm is None:
            pcm = chunk
        elif cid == b'smpl' and len(chunk) >= 52 and struct.unpack_from('<I', chunk, 28)[0] >= 1:
            loop = struct.unpack_from('<II', chunk, 44)
        pos = body + size + (size & 1)
    if fmt is None:
        raise ValueError('missing fmt chunk')
    if pcm is None:
        raise ValueError('missing data chunk')
    tag, ch, rate, bits = fmt
    if ch < 1 or rate < 1:
        raise ValueError('invalid channels or rate in fmt chunk')
    if tag == 1 and bits in (8, 16, 24, 32):
        if bits == 8:
            samples = array('f', ((b - 128) / 128.0 for b in pcm))
        elif bits == 16:
            samples = array('f', (v / 32768.0 for v in le_array('h', pcm)))
        elif bits == 24:
            samples = array('f', (int.from_bytes(pcm[i:i + 3], 'little', signed=True) / 8388608.0
                                  for i in range(0, len(pcm) - 2, 3)))
        else:
            samples = array('f', (v / 2147483648.0 for v in le_array('i', pcm)))
    elif tag == 3 and bits == 32:
        samples = le_array('f', pcm)
    else:
        raise ValueError('unsupported WAV format (tag %d, %d-bit); need PCM 8/16/24/32-bit or float32' % (tag, bits))
    frames = len(samples) // ch
    return {'rate': rate, 'channels': ch, 'frames': frames, 'samples': samples[:frames * ch], 'loop': loop}


def ogg_packets(data):
    """(first two packets, last non-negative granule) of the first logical stream; ValueError if malformed."""
    pos, serial, packets, cur, granule = 0, None, [], b'', None
    while pos < len(data):
        if data[pos:pos + 4] != b'OggS' or pos + 27 > len(data):
            raise ValueError('malformed or truncated Ogg page at byte %d' % pos)
        gran = struct.unpack_from('<q', data, pos + 6)[0]
        ser = struct.unpack_from('<I', data, pos + 14)[0]
        nseg = data[pos + 26]
        if pos + 27 + nseg > len(data):
            raise ValueError('truncated Ogg page header')
        lacing = data[pos + 27:pos + 27 + nseg]
        body = pos + 27 + nseg
        end = body + sum(lacing)
        if end > len(data):
            raise ValueError('truncated Ogg page data')
        if serial is None:
            serial = ser
        if ser == serial:
            if gran >= 0:
                granule = gran
            for lace in lacing:
                cur += data[body:body + lace]
                body += lace
                if lace < 255:
                    if len(packets) < 2:
                        packets.append(cur)
                    cur = b''
        pos = end
    return packets, granule


def read_ogg(path):
    """Parse an Ogg Vorbis file: dict(rate, channels, frames, tags (upper-case name -> value)).
    Raises ValueError with a message for anything unreadable."""
    data = Path(path).read_bytes()
    if data[:4] != b'OggS':
        raise ValueError('not an Ogg file')
    packets, granule = ogg_packets(data)
    if not packets:
        raise ValueError('no Ogg packets')
    head = packets[0]
    if head.startswith(b'OpusHead'):
        raise ValueError("Ogg Opus stream; Godot's AudioStreamOggVorbis needs Vorbis, not Opus")
    if not head.startswith(b'\x01vorbis') or len(head) < 16:
        raise ValueError('first packet is not a Vorbis identification header')
    channels = head[11]
    rate = struct.unpack_from('<I', head, 12)[0]
    if len(packets) < 2 or not packets[1].startswith(b'\x03vorbis'):
        raise ValueError('missing Vorbis comment header')
    com = packets[1]
    tags = {}
    try:
        vlen = struct.unpack_from('<I', com, 7)[0]
        pos = 11 + vlen
        count = struct.unpack_from('<I', com, pos)[0]
        pos += 4
        for _ in range(count):
            n = struct.unpack_from('<I', com, pos)[0]
            item = com[pos + 4:pos + 4 + n]
            if len(item) < n:
                raise ValueError('truncated Vorbis comment')
            pos += 4 + n
            name, sep, value = item.decode('utf-8', 'replace').partition('=')
            if sep:
                tags[name.upper()] = value
    except struct.error:
        raise ValueError('truncated Vorbis comment header')
    if granule is None or channels < 1 or rate < 1:
        raise ValueError('no valid granule position, channels or rate')
    return {'rate': rate, 'channels': channels, 'frames': granule, 'tags': tags}


def decode_ogg(path):
    """Normalised float samples via ffmpeg, or None when ffmpeg is not on PATH. ValueError if decoding fails."""
    ffmpeg = shutil.which('ffmpeg')
    if ffmpeg is None:
        return None
    try:
        proc = subprocess.run([ffmpeg, '-v', 'error', '-i', str(path), '-f', 'f32le', '-acodec', 'pcm_f32le', '-'],
                              capture_output=True, timeout=120)
    except (OSError, subprocess.SubprocessError) as err:
        raise ValueError('ffmpeg could not run (%s)' % err)
    if proc.returncode != 0:
        raise ValueError('ffmpeg decode failed')
    return le_array('f', proc.stdout)


def loop_from_tags(tags, frames):
    """(start, end exclusive) from LOOPSTART and LOOPEND/LOOPLENGTH tags, or None; ValueError if non-numeric."""
    if not any(k in tags for k in ('LOOPSTART', 'LOOPEND', 'LOOPLENGTH')):
        return None
    try:
        start = int(tags.get('LOOPSTART', '0'))
        if 'LOOPEND' in tags:
            end = int(tags['LOOPEND'])
        elif 'LOOPLENGTH' in tags:
            end = start + int(tags['LOOPLENGTH'])
        else:
            end = frames
    except ValueError:
        raise ValueError('loop tags are not numeric')
    return start, end


def check_entry(entry, path):
    """Check one dropped file. Returns dict with format, rate, channels, length, peak, loop (measured, may be None),
    failures and unverified (lists of strings)."""
    res = {'format': '', 'rate': None, 'channels': None, 'length': None, 'peak': None, 'loop': None,
           'failures': [], 'unverified': []}
    fails = res['failures']
    path = Path(path)
    suffix = path.suffix.lower()
    res['format'] = suffix.lstrip('.')
    if suffix not in ALLOWED_SUFFIXES:
        fails.append('format %s is not wav or ogg' % (suffix or 'none'))
        return res
    try:
        head = path.read_bytes()[:12]
    except OSError as err:
        fails.append('cannot read file (%s)' % err)
        return res
    if suffix == '.wav' and not (head[:4] == b'RIFF' and head[8:12] == b'WAVE'):
        fails.append('content is not WAV (.wav suffix)')
        return res
    if suffix == '.ogg' and head[:4] != b'OggS':
        fails.append('content is not Ogg (.ogg suffix)')
        return res
    samples = None
    try:
        if suffix == '.wav':
            info = read_wav(path)
            samples = info['samples']
            loop = (info['loop'][0], info['loop'][1] + 1) if info['loop'] else None
        else:
            info = read_ogg(path)
            loop = None
            if entry['loop']:
                loop = loop_from_tags(info['tags'], info['frames'])
            samples = decode_ogg(path)
            if samples is None:
                res['unverified'].append('peak and loop seam not checked, install ffmpeg on PATH')
    except ValueError as err:
        fails.append(str(err))
        return res
    rate, ch, frames = info['rate'], info['channels'], info['frames']
    res.update(rate=rate, channels=ch, length=frames / rate, loop=loop)
    if rate not in ALLOWED_RATES:
        fails.append('sample rate %d not in %s' % (rate, ALLOWED_RATES))
    lo, hi = LENGTH_SEC[length_key(entry)]
    if not lo <= res['length'] <= hi:
        fails.append('length %.2f s outside %g-%g s' % (res['length'], lo, hi))
    if samples is not None:
        peak = max((abs(v) for v in samples), default=0.0)
        res['peak'] = 20 * math.log10(peak) if peak > 0 else float('-inf')
        if peak <= 0:
            fails.append('silent (all samples zero)')
        elif res['peak'] > MAX_PEAK_DBFS + 1e-6:
            fails.append('peak %.2f dBFS above %g dBFS' % (res['peak'], MAX_PEAK_DBFS))
    if entry['loop']:
        if loop is not None:
            # AudioDirector loops the whole file (loop_offset unused), so explicit points must span it.
            if loop[0] != 0:
                fails.append('loop start %d must be 0 (the whole file loops)' % loop[0])
            if not 0 <= frames - loop[1] <= LOOP_END_TOLERANCE_FRAMES:
                fails.append('loop end %d must be within %d frames of the file end (%d frames)'
                             % (loop[1], LOOP_END_TOLERANCE_FRAMES, frames))
        if samples is not None and len(samples) >= ch:
            last = (len(samples) // ch - 1) * ch
            jump = max(abs(samples[c] - samples[last + c]) for c in range(ch))
            if jump > LOOP_SEAM_MAX:
                fails.append('loop seam jump %.3f above %g' % (jump, LOOP_SEAM_MAX))
    return res


def result_text(res):
    if res['failures']:
        return 'FAIL: ' + '; '.join(res['failures'])
    if res['unverified']:
        return 'UNVERIFIED: ' + '; '.join(res['unverified'])
    return 'OK'


def dropped_row(e):
    r = e['check']
    peak = '' if r['peak'] is None else ('-inf' if r['peak'] == float('-inf') else '%.2f' % r['peak'])
    loop = 'whole file' if not r['loop'] else '%d-%d' % r['loop']
    if not e['loop']:
        loop = 'n/a'
    return [e['id'], rel(e['stream']), r['format'],
            '' if r['rate'] is None else str(r['rate']),
            '' if r['channels'] is None else str(r['channels']),
            '' if r['length'] is None else '%.2f' % r['length'], peak, loop, result_text(r)]


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


def failed(e):
    return bool(e.get('check') and e['check']['failures'])


def unverified(e):
    return bool(e.get('check') and e['check']['unverified']) and not failed(e)


def section_lines(rows, headers, empty='None.'):
    return md_table(headers, rows) if rows else [empty]


def render_report(entries, unmapped):
    ordered = sorted(entries, key=lambda e: (GROUP_ORDER.index(e['group']), e['id']))
    out = ['# Audio status (AD-188)', '',
           'Regenerate: `python3 scripts/audio_check.py` (reads game/audio/audio_cues_v1.json and assets/audio/).', '']

    summary = []
    for title, items in [(GROUP_TITLE[g], [e for e in entries if e['group'] == g]) for g in GROUP_ORDER] + [('Total', entries)]:
        summary.append([title, str(len(items)), str(sum(e['status'] in MISSING for e in items)),
                        str(sum(e['status'] == 'dropped' for e in items)),
                        str(sum(failed(e) for e in items)), str(sum(unverified(e) for e in items))])
    out += md_table(['group', 'total', 'placeholder or silent', 'dropped', 'failed', 'unverified'], summary)
    out.append('')

    out += ['## Missing: generate these', '']
    for g in GROUP_ORDER:
        rows = [[e['id'], rel(e['stream']),
                 'dropped file failed: ' + '; '.join(e['check']['failures']) if failed(e) else e['fallback'],
                 target_text(e)]
                for e in ordered if e['group'] == g and (e['status'] in MISSING or failed(e))]
        out += ['### ' + GROUP_TITLE[g], '']
        out += section_lines(rows, ['id', 'file to create', 'current fallback', 'target']) + ['']

    out += ['## Dropped files', '']
    out += section_lines([dropped_row(e) for e in ordered if e['status'] == 'dropped'],
                         ['id', 'file', 'format', 'rate Hz', 'channels', 'length s', 'peak dBFS', 'loop', 'result']) + ['']

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
            '- Loop: explicit loop points must start at 0 and end within the tolerance (the whole file loops); '
            'no loop points means a whole-file loop',
            '- Ogg: must be Vorbis; peak and loop seam need ffmpeg on PATH, otherwise UNVERIFIED (not a failure)', '']
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
            e['check'] = check_entry(e, root / rel(e['stream']))
    unmapped = find_unmapped(root, entries)

    ordered = sorted(entries, key=lambda e: (GROUP_ORDER.index(e['group']), e['id']))
    for e in ordered:
        print('%s %s %s' % (e['id'], e['group'], e['status']))
        if e.get('check'):
            for p in e['check']['failures']:
                print('  problem %s: %s' % (e['id'], p))
            for n in e['check']['unverified']:
                print('  unverified %s: %s' % (e['id'], n))
    for g in GROUP_ORDER:
        items = [e for e in entries if e['group'] == g]
        print('%s: total %d, placeholder or silent %d, dropped %d, failed %d, unverified %d' % (
            GROUP_TITLE[g], len(items), sum(e['status'] in MISSING for e in items),
            sum(e['status'] == 'dropped' for e in items), sum(failed(e) for e in items),
            sum(unverified(e) for e in items)))
    for r, hint in unmapped:
        print('unmapped %s%s' % (r, ' (%s)' % hint if hint else ''))

    text = render_report(entries, unmapped)
    if output.exists():
        old = output.read_text(encoding='utf-8')
        i = old.find(CUE_CHANGES_START)
        j = old.find(CUE_CHANGES_END, i) if i >= 0 else -1
        if j >= 0:
            text += '\n' + old[i:j + len(CUE_CHANGES_END)] + '\n'
    output.parent.mkdir(parents=True, exist_ok=True)
    with open(output, 'w', encoding='utf-8', newline='\n') as f:
        f.write(text)
    print('wrote %s' % output)
    return 1 if unmapped or any(failed(e) for e in entries) else 0


if __name__ == '__main__':
    sys.exit(main())
