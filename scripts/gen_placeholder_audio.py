#!/usr/bin/env python3
"""AD-021: deterministic placeholder SFX/ambience generator (stdlib only).

Writes one 44.1 kHz mono 16-bit .wav per cue in game/audio/audio_cues_v1.json.
Usage: gen_placeholder_audio.py [--check]
"""
import argparse
import json
import math
import random
import struct
import sys
import zlib
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
CUES = ROOT / "game" / "audio" / "audio_cues_v1.json"
AUDIO = ROOT / "assets" / "audio"
SR = 44100
SFX_PEAK = 20673   # about -4 dBFS
AMB_PEAK = 3677    # about -19 dBFS
SFX_LIMIT = 23197  # -3 dBFS
AMB_LIMIT = 4125   # -18 dBFS
AMB_FRAMES = 20 * SR
MAX_TOTAL = 5 * 1000 * 1000
TAU = 2.0 * math.pi


def frames(sec):
    return max(1, int(round(sec * SR)))


def osc(n, freq, wave="sine", duty=0.5):
    """freq: float or callable(progress 0..1) -> Hz. Phase-accumulated."""
    out, ph = [], 0.0
    for i in range(n):
        f = freq(i / n) if callable(freq) else freq
        ph = (ph + f / SR) % 1.0
        if wave == "sine":
            v = math.sin(TAU * ph)
        elif wave == "square":
            v = 1.0 if ph < duty else -1.0
        elif wave == "saw":
            v = 2.0 * ph - 1.0
        else:
            v = 4.0 * abs(ph - 0.5) - 1.0
        out.append(v)
    return out


def noise(rng, n):
    return [rng.uniform(-1.0, 1.0) for _ in range(n)]


def lowpass(x, cutoff, state=0.0):
    """One-pole lowpass; cutoff float or callable(progress)."""
    out, n = [], len(x)
    for i, v in enumerate(x):
        c = cutoff(i / n) if callable(cutoff) else cutoff
        a = 1.0 - math.exp(-TAU * c / SR)
        state += a * (v - state)
        out.append(state)
    return out


def env_decay(n, rate):
    return [math.exp(-rate * i / n) for i in range(n)]


def mul(a, b):
    return [x * y for x, y in zip(a, b)]


def add(*sigs):
    n = max(len(s) for s in sigs)
    out = [0.0] * n
    for s in sigs:
        for i, v in enumerate(s):
            out[i] += v
    return out


def scale(x, k):
    return [v * k for v in x]


# ---- cue kinds: each returns a float list; seeded rng passed in -------------

def k_crackle(rng, dur, cutoff, pops):
    n = frames(dur)
    base = lowpass(noise(rng, n), cutoff)
    base = mul(base, env_decay(n, 2.5))
    sig = scale(base, 0.5)
    for _ in range(pops):
        at = rng.randrange(0, n - 40)
        amp = rng.uniform(0.5, 1.0)
        for j in range(min(n - at, 60)):
            sig[at + j] += amp * rng.uniform(-1, 1) * math.exp(-j / 10.0) * math.exp(-2.0 * at / n)
    return sig


def k_bubble(rng, dur, f0, f1, am_hz, am_depth):
    n = frames(dur)
    s = osc(n, lambda p: f0 + (f1 - f0) * p + 25 * math.sin(TAU * am_hz * p * dur))
    am = [1.0 - am_depth + am_depth * math.sin(TAU * am_hz * i / SR) ** 2 for i in range(n)]
    return mul(mul(s, am), env_decay(n, 1.5))


def k_zap(rng, dur, f0, f1):
    n = frames(dur)
    s = osc(n, lambda p: f0 * (f1 / f0) ** p, "square", 0.35)
    return mul(s, env_decay(n, 3.0))


def k_blip(rng, dur, f):
    n = frames(dur)
    return mul(osc(n, f), env_decay(n, 6.0))


def k_buzz(rng, dur, f):
    n = frames(dur)
    return lowpass(osc(n, f, "saw"), 400)


def k_thump(rng, dur, f):
    n = frames(dur)
    body = osc(n, lambda p: f * (1 - 0.5 * p))
    nz = lowpass(noise(rng, n), 1800)
    return mul(add(body, scale(nz, 0.8)), env_decay(n, 5.0))


def k_rise(rng, dur, f0, f1, wave="triangle"):
    n = frames(dur)
    s = osc(n, lambda p: f0 + (f1 - f0) * p, wave)
    return mul(s, [0.5 + 0.5 * i / n for i in range(n)])


def k_steps(rng, dur, f0, steps, ratio):
    """Stepped rising pulses with gaps."""
    n = frames(dur)
    seg = n // steps
    out = []
    for k in range(steps):
        m = seg if k < steps - 1 else n - seg * (steps - 1)
        s = osc(m, f0 * ratio ** k, "square", 0.5)
        gate = [1.0 if i < m * 0.7 else 0.0 for i in range(m)]
        out += mul(s, gate)
    return out


def k_chirps(rng, dur, f0, f1, count):
    n = frames(dur)
    seg = n // count
    out = []
    for k in range(count):
        m = seg if k < count - 1 else n - seg * (count - 1)
        s = osc(m, lambda p, k=k: (f0 + 300 * k) * (f1 / f0) ** p, "square", 0.3)
        out += mul(s, env_decay(m, 4.0))
    return out


def k_hiss(rng, dur):
    n = frames(dur)
    nz = lowpass(noise(rng, n), lambda p: 9000 - 8200 * p)
    return mul(nz, env_decay(n, 2.0))


def k_arp(rng, dur, notes, wave="triangle", decay=4.0):
    """notes: list of Hz played equally spaced."""
    n = frames(dur)
    seg = n // len(notes)
    out = []
    for k, f in enumerate(notes):
        m = seg if k < len(notes) - 1 else n - seg * (len(notes) - 1)
        out += mul(osc(m, f, wave), env_decay(m, decay))
    return out


def k_fall(rng, dur, f0, f1, wave="saw", cutoff=2500):
    n = frames(dur)
    s = lowpass(osc(n, lambda p: f0 + (f1 - f0) * p, wave), cutoff)
    return mul(s, env_decay(n, 2.0))


def k_boom(rng, dur, f0, f1):
    n = frames(dur)
    s = osc(n, lambda p: f0 + (f1 - f0) * p)
    nz = lowpass(noise(rng, n), 600)
    return mul(add(s, scale(nz, 0.7)), env_decay(n, 3.0))


def k_tick(rng, dur, f):
    n = frames(dur)
    return mul(osc(n, f, "square"), env_decay(n, 8.0))


# ---- ambience (whole cycles over loop; filters run twice to wrap) -----------

def wrap_lowpass(x, cutoff):
    state = lowpass(x, cutoff)[-1]       # warm-up pass
    return lowpass(x, cutoff, state)


def k_amb(rng, drones, wind_cut, wind_gain, wind_lfo, ticks):
    n = AMB_FRAMES
    sig = [0.0] * n
    for hz, amp in drones:  # hz multiples of 0.05 -> whole cycles in 20 s
        for i in range(n):
            sig[i] += amp * math.sin(TAU * hz * i / SR)
    wind = wrap_lowpass(wrap_lowpass(noise(rng, n), wind_cut), wind_cut)
    peak = max(abs(v) for v in wind) or 1.0
    for i in range(n):
        lfo = 0.6 + 0.4 * math.sin(TAU * wind_lfo * i / SR)  # wind_lfo multiple of 0.05
        sig[i] += wind_gain * lfo * wind[i] / peak
    if ticks:
        period, freq, amp = ticks
        m = frames(0.03)
        for k in range(int(20 / period)):
            at = frames(period * k + 0.4)
            for j in range(m):
                sig[at + j] += amp * math.sin(TAU * freq * j / SR) * math.exp(-j / (m / 5.0))
    return sig


# cue id -> (kind fn, args). Every cue in the table needs exactly one entry.
SYNTH = {
    "sfx.cast.neutral": (k_blip, (0.09, 700)),
    "sfx.cast.fire": (k_crackle, (0.18, 3500, 14)),
    "sfx.cast.water": (k_bubble, (0.19, 300, 130, 40, 0.8)),
    "sfx.cast.lightning": (k_zap, (0.14, 2400, 900)),
    "sfx.hit.generic": (k_thump, (0.09, 150)),
    "sfx.react.arc": (k_chirps, (0.25, 1800, 3600, 5)),
    "sfx.react.extinguish": (k_hiss, (0.3,)),
    "sfx.dash": (k_fall, (0.18, 1400, 400, "saw", 1800)),
    "sfx.dash.iframe": (k_arp, (0.14, [1200, 1800], "sine", 3.0)),
    "sfx.cast.rejected": (k_buzz, (0.12, 85)),
    "sfx.tele.bone_thrall": (k_rise, (0.4, 220, 330)),
    "sfx.tele.fallen_adept": (k_rise, (0.3, 440, 660)),
    "sfx.tele.grave_hound": (k_rise, (0.35, 330, 495, "saw")),
    "sfx.boss.tele_a": (k_rise, (0.45, 90, 360, "saw")),
    "sfx.boss.tele_b": (k_steps, (0.45, 200, 3, 1.4)),
    "sfx.boss.phase": (k_boom, (0.8, 70, 160)),
    "sfx.boss.death": (k_boom, (1.0, 160, 40)),
    "sfx.player.hurt": (k_fall, (0.22, 300, 150, "square", 1200)),
    "sfx.player.death": (k_fall, (0.9, 400, 60, "triangle", 2000)),
    "sfx.room.cleared": (k_arp, (0.6, [523, 659, 784, 1047], "triangle", 3.0)),
    "sfx.pickup.rune": (k_arp, (0.35, [660, 990, 1320], "sine", 3.0)),
    "sfx.pickup.currency": (k_arp, (0.18, [1568, 2093], "square", 5.0)),
    "ui.hover": (k_tick, (0.03, 1500)),
    "ui.confirm": (k_arp, (0.07, [900, 1350], "sine", 4.0)),
    "ui.cancel": (k_arp, (0.07, [700, 450], "sine", 4.0)),
    "ui.editor_error": (k_buzz, (0.075, 150)),
    "ui.purchase": (k_arp, (0.08, [1200, 1600, 2000], "triangle", 4.0)),
    "ui.reward_pick": (k_arp, (0.08, [800, 1200, 1600], "sine", 3.0)),
    "amb.ruins": (k_amb, ([(55.0, 0.5), (82.5, 0.25), (110.05, 0.1)], 500, 0.8, 0.1, None)),
    "amb.workshop": (k_amb, ([(73.0, 0.5), (146.0, 0.3), (219.0, 0.15)], 300, 0.25, 0.15, (2.5, 1200, 0.3))),
}


def limits(cue_id):
    """(min_frames, max_frames, peak_limit) per cue category."""
    if cue_id.startswith("amb."):
        return AMB_FRAMES, AMB_FRAMES, AMB_LIMIT
    if cue_id.startswith("ui."):
        return 1, frames(0.08), SFX_LIMIT
    if cue_id in ("sfx.cast.neutral", "sfx.cast.fire", "sfx.cast.water", "sfx.cast.lightning"):
        return frames(0.08), frames(0.2), SFX_LIMIT
    if cue_id.startswith("sfx.tele.") or cue_id.startswith("sfx.boss.tele_"):
        return frames(0.25), frames(0.5), SFX_LIMIT
    return frames(0.06), frames(1.0), SFX_LIMIT


def render(cue_id):
    fn, args = SYNTH[cue_id]
    rng = random.Random(zlib.crc32(cue_id.encode()))
    sig = fn(rng, *args)
    amb = cue_id.startswith("amb.")
    if not amb:  # short attack/release so cues never click
        n = len(sig)
        a, r = min(int(0.002 * SR), n // 4), min(int(0.008 * SR), n // 4)
        for i in range(a):
            sig[i] *= i / a
        for i in range(r):
            sig[n - 1 - i] *= i / r
    peak = max(abs(v) for v in sig) or 1.0
    k = (AMB_PEAK if amb else SFX_PEAK) / peak
    return [max(-32768, min(32767, int(round(v * k)))) for v in sig]


def wav_bytes(samples, loop):
    n = len(samples)
    fmt = struct.pack("<HHIIHH", 1, 1, SR, SR * 2, 2, 16)
    data = struct.pack("<%dh" % n, *samples)
    chunks = b"fmt " + struct.pack("<I", 16) + fmt + b"data" + struct.pack("<I", len(data)) + data
    if loop:
        smpl = struct.pack("<9I", 0, 0, 1000000000 // SR, 60, 0, 0, 0, 1, 0)
        smpl += struct.pack("<6I", 0, 0, 0, n - 1, 0, 0)
        chunks += b"smpl" + struct.pack("<I", len(smpl)) + smpl
    return b"RIFF" + struct.pack("<I", 4 + len(chunks)) + b"WAVE" + chunks


def load_cues():
    cues = json.loads(CUES.read_text())["cues"]
    missing = sorted(set(cues) - set(SYNTH))
    extra = sorted(set(SYNTH) - set(cues))
    if missing or extra:
        sys.exit("spec/cue mismatch: no spec for %s; no cue for %s" % (missing, extra))
    return cues


def path_for(cue_id):
    sub = cue_id.split(".")[0]
    sub = {"sfx": "sfx", "ui": "ui", "amb": "amb"}[sub]
    return "res://assets/audio/%s/%s.wav" % (sub, cue_id.replace(".", "_"))


def disk(res):
    return ROOT / res[len("res://"):]


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--check", action="store_true")
    args = ap.parse_args()
    cues = load_cues()
    errors = []
    print("| cue | file | ms | peak dBFS |\n|---|---|---|---|")
    for cue_id in cues:
        res = path_for(cue_id)
        samples = render(cue_id)
        data = wav_bytes(samples, cue_id.startswith("amb."))
        peak = max(abs(v) for v in samples)
        db = 20 * math.log10(peak / 32768.0)
        print("| %s | %s | %.0f | %.1f |" % (cue_id, res, len(samples) * 1000.0 / SR, db))
        lo, hi, lim = limits(cue_id)
        if not lo <= len(samples) <= hi:
            errors.append("%s: duration %d frames out of range" % (cue_id, len(samples)))
        if peak > lim:
            errors.append("%s: peak %d > %d" % (cue_id, peak, lim))
        f = disk(res)
        if args.check:
            if cues[cue_id]["stream"] != res:
                errors.append("%s: cue table stream %s != %s" % (cue_id, cues[cue_id]["stream"], res))
            if not f.exists():
                errors.append("%s: missing %s" % (cue_id, res))
            elif f.read_bytes() != data:
                errors.append("%s: on-disk bytes differ" % cue_id)
        else:
            f.parent.mkdir(parents=True, exist_ok=True)
            f.write_bytes(data)
    total = sum(p.stat().st_size for p in AUDIO.rglob("*.wav"))
    print("\ntotal wav bytes: %d" % total)
    if total >= MAX_TOTAL:
        errors.append("total size %d >= %d" % (total, MAX_TOTAL))
    for e in errors:
        print("FAIL:", e, file=sys.stderr)
    return 1 if errors else 0


if __name__ == "__main__":
    sys.exit(main())
