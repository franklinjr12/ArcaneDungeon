# Sigilwright (Arcane Dungeon) - Audio Prompt Pack for musicgen-small

Version 1 - 2026-11-10 - Game Design (Wren), for Franklin.
Sources: `game/audio/audio_cues_v1.json` (every cue id and file), `docs/demo/AUDIO_STATUS.md` and `docs/demo/AUDIO_PRIORITY.md` (AD-188/AD-192, PR #12), `assets/audio/README.md`, `scripts/audio_check.py` (file rules).

## How to use this pack

1. Work batch by batch (Batch 1 is what the player hears most). Each cue has one block: file, format, length, loop, then the prompt in a code block (copy only that), then generation settings and post-processing.
2. Generate the takes with the script below, listen, keep the best one, post-process it (trim, fades, loop, normalise), and save it under the exact file name shown in `assets/audio/...` of the repo.
3. Run `python3 scripts/audio_check.py` in the repo. It lists every cue as placeholder / dropped / failed, and checks rate, length, peak and loop seam. A cue counts as replaced only when its file is at the exact path shown here.
4. You can drop files in any order; missing files keep their placeholder.

### Notes before you start
1. Format for every file: 44.1 kHz, mono, 16-bit PCM WAV. (audio_check.py also accepts 32/48 kHz, but use 44.1 kHz everywhere for consistency.)
2. File names: today the cue list maps 47 cues (new runes, forms, triggers, artifacts, environment, new enemy telegraphs, music) to `.ogg` names. This pack uses `.wav` for all of them. The AD board row that commits this pack also switches those 47 paths in `audio_cues_v1.json` to `.wav`, so your WAV files are recognised. Until that row lands, audio_check.py will not see the `.wav` versions of those 47.
3. Two NEW telegraph ids are included (`sfx.tele.ghoul_stalker`, `sfx.tele.riptide_leaper`). Today these two enemies reuse the bone thrall and cistern slime telegraphs; the same board row adds their own cue ids.
4. Loudness rules from your feedback: enemy attack and hit sounds are SOFT (peaks -9 dBFS or lower); telegraphs (wind-up warnings) are CLEAR (peak -3 dBFS) but round, never shrill; UI is quiet (-12 dBFS). The game also limits repeats (max voices, 90-120 ms rate limit) and varies pitch by about +-6%, so you do not need many variants. audio_check.py rejects any peak above -1 dBFS.
5. Length limits checked by audio_check.py: telegraphs 0.1-1.5 s, other SFX 0.03-5 s, ambience 5-120 s, music 15-300 s.

## Running musicgen-small locally (GPU PC)

Install once (Python 3.10+):

```
pip install torch transformers scipy soundfile numpy
```

Script (`gen.py`), generates N takes of one prompt, resampled from MusicGen's 32 kHz to 44.1 kHz mono 16-bit WAV:

```python
import sys, numpy as np, soundfile as sf, torch
from scipy.signal import resample_poly
from transformers import AutoProcessor, MusicgenForConditionalGeneration

DEVICE = "cuda" if torch.cuda.is_available() else "cpu"
proc = AutoProcessor.from_pretrained("facebook/musicgen-small")
model = MusicgenForConditionalGeneration.from_pretrained("facebook/musicgen-small").to(DEVICE)
SR_IN = model.config.audio_encoder.sampling_rate   # 32000

def generate(prompt, seconds, guidance=3.0, takes=4, out_prefix="take"):
    tokens = int(seconds * 50) + 4                  # ~50 tokens per second of audio
    inputs = proc(text=[prompt] * takes, padding=True, return_tensors="pt").to(DEVICE)
    with torch.no_grad():
        audio = model.generate(**inputs, do_sample=True, guidance_scale=guidance,
                               max_new_tokens=tokens)
    for i, a in enumerate(audio.cpu().numpy()):
        x = a[0].astype(np.float32)                 # mono
        y = resample_poly(x, 441, 320)              # 32 kHz -> 44.1 kHz
        y = y / max(1e-9, np.abs(y).max()) * 0.5    # safe level before editing
        sf.write(f"{out_prefix}_{i+1}.wav", y, 44100, subtype="PCM_16")

if __name__ == "__main__":
    # python gen.py "prompt text" seconds guidance takes out_prefix
    generate(sys.argv[1], float(sys.argv[2]), float(sys.argv[3]), int(sys.argv[4]), sys.argv[5])
```

Example: `python gen.py "very short soft dull thud, single muted frame drum hit with felt mallet, dry, no ring" 2 4.0 6 hit_generic`

Token / duration formula: musicgen-small makes about 50 audio tokens per second (32 kHz audio, 640 samples per token). `max_new_tokens = 50 x seconds` (+4 for safety). 1 s = 54, 2 s = 104, 30 s = 1504. musicgen-small cannot go much beyond 30 s in one call; 30-32 s is enough for our loops.

Settings used in this pack:
- SFX, telegraphs, UI: generate 2 s (`max_new_tokens=104`), `guidance_scale=4.0`, 6 takes, then trim to the target length. MusicGen needs some room to "start" a sound; very short requests often come out empty or musical.
- Music and ambience: generate 32 s (`max_new_tokens=1604`), `guidance_scale=3.0`, 3 takes.

## Post-processing helpers

```python
import numpy as np, soundfile as sf

def trim(path_in, path_out, start_s, end_s, fade_in_ms=3, fade_out_ms=40):
    x, sr = sf.read(path_in)
    y = x[int(start_s*sr):int(end_s*sr)].copy()
    fi, fo = int(sr*fade_in_ms/1000), int(sr*fade_out_ms/1000)
    if fi: y[:fi] *= np.linspace(0, 1, fi)
    if fo: y[-fo:] *= np.linspace(1, 0, fo)
    sf.write(path_out, y, sr, subtype="PCM_16")

def normalise(path, peak_dbfs=-6.0):
    x, sr = sf.read(path)
    x = x / max(1e-9, np.abs(x).max()) * (10 ** (peak_dbfs / 20))
    sf.write(path, x, sr, subtype="PCM_16")

def make_loop(path_in, path_out, xfade_s=0.5):
    """Seamless whole-file loop: the end crossfades into the start, then the start is cut off.
    The game loops the WHOLE file, and audio_check.py checks the seam."""
    x, sr = sf.read(path_in)
    n = int(xfade_s * sr)
    head, body = x[:n], x[n:].copy()
    t = np.linspace(0, 1, n)
    body[-n:] = body[-n:] * np.cos(t * np.pi / 2) + head * np.sin(t * np.pi / 2)   # equal-power
    sf.write(path_out, body, sr, subtype="PCM_16")
```

Making music loop well:
1. Generate 32 s, pick the take with the steadiest tempo and no ending.
2. Cut to a whole number of bars: bar length = 4 x 60 / bpm seconds (100 bpm = 2.4 s, so 12 bars = 28.8 s; 80 bpm = 3.0 s, so 10 bars = 30.0 s; 140 bpm = 1.714 s, so 16 bars = 27.43 s; 85 bpm = 2.824 s, so 10 bars = 28.24 s). Start the cut on a downbeat a few seconds in, so you skip the intro.
3. Keep `xfade_s` extra seconds after the last bar, then run `make_loop()`; the result is exactly the bar length.
4. Normalise, then loop it 3 times in Audacity (or any player) and listen to the seam.

## musicgen-small is made for music: SFX warning

musicgen-small was trained on music, so short sound effects (hits, clicks, whooshes) often come out as a small musical phrase, a drum loop, or near silence. Expect several takes and trimming for Batch 1. If a cue does not work after 2 rounds of takes, use one of these fallbacks:
1. Ask for an instrument that makes the sound, then cut one hit: for example "solo taiko drum, single hits with long pauses" or "solo celesta, single notes with pauses", and slice the best single hit. This works well for hits, UI and telegraph swells.
2. Use Meta's sibling model for sound effects, `facebook/audiogen-medium` (AudioCraft library, also runs locally on your GPU): same prompts, it is trained on environmental sound and handles whooshes, splashes, crackles and impacts much better.
3. Build it in Audacity from a usable take: pitch-shift down for weight, reverse a cymbal or swell for a rising telegraph, layer two takes, or time-stretch; or record simple foley with a phone (cloth swish, coins, paper) and process it the same way.

---

## Batch 1 - most heard (telegraphs, casts, hits, dash, room clear, spell parts)
### 1. `sfx.tele.bone_thrall`
- File: `assets/audio/sfx/sfx_tele_bone_thrall.wav`
- Format: 44.1 kHz mono 16-bit WAV
- Type: telegraph (0.1-1.5 s allowed)
- Target duration: 0.4 s
- Loop: no

```
short rising dry bone rattle, wooden clacks speeding up, hollow and woody, warning gesture, no melody, no reverb tail
```

- Generate: 2 s -> `max_new_tokens=104`, `guidance_scale=4.0`, takes: 6
- Post: Trim to the clearest rising gesture; 5 ms fade-in, 30-60 ms fade-out; high-pass at 80 Hz; normalise peak to -3 dBFS (telegraphs carry gameplay information and must cut through, but keep them round, not shrill).
### 2. `sfx.boss.tele_a`
- File: `assets/audio/sfx/sfx_boss_tele_a.wav`
- Format: 44.1 kHz mono 16-bit WAV
- Type: telegraph (0.1-1.5 s allowed)
- Target duration: 0.5 s
- Loop: no

```
short deep ominous low brass swell rising fast, single dark horn note crescendo, dungeon boss warning, no drums
```

- Generate: 2 s -> `max_new_tokens=104`, `guidance_scale=4.0`, takes: 6
- Post: Trim to the clearest rising gesture; 5 ms fade-in, 30-60 ms fade-out; high-pass at 80 Hz; normalise peak to -3 dBFS (telegraphs carry gameplay information and must cut through, but keep them round, not shrill).
### 3. `sfx.boss.tele_b`
- File: `assets/audio/sfx/sfx_boss_tele_b.wav`
- Format: 44.1 kHz mono 16-bit WAV
- Type: telegraph (0.1-1.5 s allowed)
- Target duration: 0.5 s
- Loop: no

```
three quick rising low taiko drum hits, menacing and urgent, dry, ends abruptly, no melody
```

- Generate: 2 s -> `max_new_tokens=104`, `guidance_scale=4.0`, takes: 6
- Post: Trim to the clearest rising gesture; 5 ms fade-in, 30-60 ms fade-out; high-pass at 80 Hz; normalise peak to -3 dBFS (telegraphs carry gameplay information and must cut through, but keep them round, not shrill).
### 4. `sfx.player.hurt`
- File: `assets/audio/sfx/sfx_player_hurt.wav`
- Format: 44.1 kHz mono 16-bit WAV
- Type: sound effect
- Target duration: 0.2 s
- Loop: no

```
very short muted low impact thud with a quick falling tone, soft cloth and leather hit, no voice, no scream
```

- Generate: 2 s -> `max_new_tokens=104`, `guidance_scale=4.0`, takes: 6
- Post: Trim to the thud; 2 ms fade-in, 50 ms fade-out; normalise peak to -4 dBFS (must be noticed, but not painful to hear).
### 5. `sfx.hit.generic`
- File: `assets/audio/sfx/sfx_hit_generic.wav`
- Format: 44.1 kHz mono 16-bit WAV
- Type: sound effect
- Target duration: 0.1 s
- Loop: no

```
very short soft dull thud, single muted frame drum hit with felt mallet, dry, no ring
```

- Generate: 2 s -> `max_new_tokens=104`, `guidance_scale=4.0`, takes: 6
- Post: Trim to one transient; 2 ms fade-in, 40 ms fade-out; low-pass at 8 kHz to take the edge off; normalise peak to -9 dBFS (heard dozens of times per room: soft, never harsh).
### 6. `sfx.cast.neutral`
- File: `assets/audio/sfx/sfx_cast_neutral.wav`
- Format: 44.1 kHz mono 16-bit WAV
- Type: sound effect
- Target duration: 0.12 s
- Loop: no

```
very short soft magical chime pluck, single clean celesta note, gentle attack, quick decay, no reverb
```

- Generate: 2 s -> `max_new_tokens=104`, `guidance_scale=4.0`, takes: 6
- Post: Trim to one gesture; 3 ms fade-in, 30-50 ms fade-out; normalise peak to -6 dBFS. Make 3 slightly different takes if you like: the game already varies pitch by about +-6%.
### 7. `sfx.cast.fire`
- File: `assets/audio/sfx/sfx_cast_fire.wav`
- Format: 44.1 kHz mono 16-bit WAV
- Type: sound effect
- Target duration: 0.2 s
- Loop: no

```
very short crackling fire whoosh, quick flame burst with soft crackle, warm, fast attack and fast decay, no music
```

- Generate: 2 s -> `max_new_tokens=104`, `guidance_scale=4.0`, takes: 6
- Post: Trim to one gesture; 3 ms fade-in, 30-50 ms fade-out; normalise peak to -6 dBFS. Make 3 slightly different takes if you like: the game already varies pitch by about +-6%.
### 8. `sfx.cast.water`
- File: `assets/audio/sfx/sfx_cast_water.wav`
- Format: 44.1 kHz mono 16-bit WAV
- Type: sound effect
- Target duration: 0.2 s
- Loop: no

```
very short bubbling water pluck, single round water drop splash, soft and rounded, quick decay
```

- Generate: 2 s -> `max_new_tokens=104`, `guidance_scale=4.0`, takes: 6
- Post: Trim to one gesture; 3 ms fade-in, 30-50 ms fade-out; normalise peak to -6 dBFS. Make 3 slightly different takes if you like: the game already varies pitch by about +-6%.
### 9. `sfx.cast.lightning`
- File: `assets/audio/sfx/sfx_cast_lightning.wav`
- Format: 44.1 kHz mono 16-bit WAV
- Type: sound effect
- Target duration: 0.15 s
- Loop: no

```
very short electric zap, bright crackling spark snap, quick attack, tiny tail, no hum
```

- Generate: 2 s -> `max_new_tokens=104`, `guidance_scale=4.0`, takes: 6
- Post: Trim to one gesture; 3 ms fade-in, 30-50 ms fade-out; normalise peak to -6 dBFS. Make 3 slightly different takes if you like: the game already varies pitch by about +-6%.
### 10. `sfx.cast.cold`
- File: `assets/audio/sfx/sfx_cast_cold.wav`
- Format: 44.1 kHz mono 16-bit WAV
- Type: sound effect
- Target duration: 0.2 s
- Loop: no

```
very short icy crystal chime, frosty glassy shimmer with a soft crackle of ice, quick attack, short sparkle tail
```

- Generate: 2 s -> `max_new_tokens=104`, `guidance_scale=4.0`, takes: 6
- Post: Trim to one gesture; 3 ms fade-in, 30-50 ms fade-out; normalise peak to -6 dBFS. Make 3 slightly different takes if you like: the game already varies pitch by about +-6%.
### 11. `sfx.cast.force`
- File: `assets/audio/sfx/sfx_cast_force.wav`
- Format: 44.1 kHz mono 16-bit WAV
- Type: sound effect
- Target duration: 0.2 s
- Loop: no

```
very short deep air pulse, muffled whump of pressure, low thump with a short whoosh, no ring
```

- Generate: 2 s -> `max_new_tokens=104`, `guidance_scale=4.0`, takes: 6
- Post: Trim to one gesture; 3 ms fade-in, 30-50 ms fade-out; normalise peak to -6 dBFS. Make 3 slightly different takes if you like: the game already varies pitch by about +-6%.
### 12. `sfx.cast.rejected`
- File: `assets/audio/sfx/sfx_cast_rejected.wav`
- Format: 44.1 kHz mono 16-bit WAV
- Type: sound effect
- Target duration: 0.15 s
- Loop: no

```
very short soft dull fizzle, a muted wooden click followed by a tiny downward puff, out of energy, not annoying
```

- Generate: 2 s -> `max_new_tokens=104`, `guidance_scale=4.0`, takes: 6
- Post: Trim; 2 ms fade-in, 40 ms fade-out; normalise peak to -10 dBFS (it can repeat fast when the player spams with no mana, so keep it quiet and dull).
### 13. `sfx.dash`
- File: `assets/audio/sfx/sfx_dash.wav`
- Format: 44.1 kHz mono 16-bit WAV
- Type: sound effect
- Target duration: 0.2 s
- Loop: no

```
very short airy whoosh falling in pitch, cloth swish through air, fast, no melody, no tail
```

- Generate: 2 s -> `max_new_tokens=104`, `guidance_scale=4.0`, takes: 6
- Post: Trim; 2 ms fade-in, 40 ms fade-out; normalise peak to -8 dBFS.
### 14. `sfx.dash.iframe`
- File: `assets/audio/sfx/sfx_dash_iframe.wav`
- Format: 44.1 kHz mono 16-bit WAV
- Type: sound effect
- Target duration: 0.15 s
- Loop: no

```
very short faint shimmering glint, light glass chime sparkle, soft and high but gentle, quick decay
```

- Generate: 2 s -> `max_new_tokens=104`, `guidance_scale=4.0`, takes: 6
- Post: Trim; normalise peak to -12 dBFS; it layers on top of the dash and must stay subtle.
### 15. `sfx.room.cleared`
- File: `assets/audio/sfx/sfx_room_cleared.wav`
- Format: 44.1 kHz mono 16-bit WAV
- Type: sound effect
- Target duration: 0.7 s
- Loop: no

```
short bright rising four-note harp arpeggio, resolved and relieved, major key, gentle bell shimmer at the end
```

- Generate: 2 s -> `max_new_tokens=104`, `guidance_scale=4.0`, takes: 6
- Post: Trim to the arpeggio; 5 ms fade-in, 150 ms fade-out; normalise peak to -6 dBFS.
### 16. `sfx.player.death`
- File: `assets/audio/sfx/sfx_player_death.wav`
- Format: 44.1 kHz mono 16-bit WAV
- Type: sound effect
- Target duration: 1.5 s
- Loop: no

```
short sad falling low cello note with a soft cymbal swell fading out, defeat, dark fantasy, slow decay
```

- Generate: 2 s -> `max_new_tokens=104`, `guidance_scale=4.0`, takes: 6
- Post: Trim to about 1.5 s; 10 ms fade-in, 400 ms fade-out; normalise peak to -4 dBFS.
### 17. `sfx.tele.fallen_adept`
- File: `assets/audio/sfx/sfx_tele_fallen_adept.wav`
- Format: 44.1 kHz mono 16-bit WAV
- Type: telegraph (0.1-1.5 s allowed)
- Target duration: 0.45 s
- Loop: no

```
short rising whispery magical swell, ghostly breath with a thin glassy tone climbing up, warning, no melody
```

- Generate: 2 s -> `max_new_tokens=104`, `guidance_scale=4.0`, takes: 6
- Post: Trim to the clearest rising gesture; 5 ms fade-in, 30-60 ms fade-out; high-pass at 80 Hz; normalise peak to -3 dBFS (telegraphs carry gameplay information and must cut through, but keep them round, not shrill).
### 18. `sfx.tele.grave_hound`
- File: `assets/audio/sfx/sfx_tele_grave_hound.wav`
- Format: 44.1 kHz mono 16-bit WAV
- Type: telegraph (0.1-1.5 s allowed)
- Target duration: 0.35 s
- Loop: no

```
short low rising growl-like rumble made by a bowed double bass, rough texture, quick crescendo, no voice
```

- Generate: 2 s -> `max_new_tokens=104`, `guidance_scale=4.0`, takes: 6
- Post: Trim to the clearest rising gesture; 5 ms fade-in, 30-60 ms fade-out; high-pass at 80 Hz; normalise peak to -3 dBFS (telegraphs carry gameplay information and must cut through, but keep them round, not shrill).
### 19. `sfx.tele.ossuary_shieldbearer`
- File: `assets/audio/sfx/sfx_tele_ossuary_shieldbearer.wav`
- Format: 44.1 kHz mono 16-bit WAV
- Type: telegraph (0.1-1.5 s allowed)
- Target duration: 0.5 s
- Loop: no

```
short heavy metal shield scrape rising into a dull clank, armoured and slow, warning, dry
```

- Generate: 2 s -> `max_new_tokens=104`, `guidance_scale=4.0`, takes: 6
- Post: Trim to the clearest rising gesture; 5 ms fade-in, 30-60 ms fade-out; high-pass at 80 Hz; normalise peak to -3 dBFS (telegraphs carry gameplay information and must cut through, but keep them round, not shrill).
### 20. `sfx.tele.wailing_spirit`
- File: `assets/audio/sfx/sfx_tele_wailing_spirit.wav`
- Format: 44.1 kHz mono 16-bit WAV
- Type: telegraph (0.1-1.5 s allowed)
- Target duration: 0.6 s
- Loop: no

```
short eerie rising ghostly wail played on a theremin, soft and airy, not shrill, warning gesture
```

- Generate: 2 s -> `max_new_tokens=104`, `guidance_scale=4.0`, takes: 6
- Post: Trim to the clearest rising gesture; 5 ms fade-in, 30-60 ms fade-out; high-pass at 80 Hz; normalise peak to -3 dBFS (telegraphs carry gameplay information and must cut through, but keep them round, not shrill).
### 21. `sfx.tele.corpse_bloat`
- File: `assets/audio/sfx/sfx_tele_corpse_bloat.wav`
- Format: 44.1 kHz mono 16-bit WAV
- Type: telegraph (0.1-1.5 s allowed)
- Target duration: 0.6 s
- Loop: no

```
short low wet gurgling swell rising, bubbling tuba drone growing louder, gross but soft, warning
```

- Generate: 2 s -> `max_new_tokens=104`, `guidance_scale=4.0`, takes: 6
- Post: Trim to the clearest rising gesture; 5 ms fade-in, 30-60 ms fade-out; high-pass at 80 Hz; normalise peak to -3 dBFS (telegraphs carry gameplay information and must cut through, but keep them round, not shrill).
### 22. `sfx.tele.cistern_slime`
- File: `assets/audio/sfx/sfx_tele_cistern_slime.wav`
- Format: 44.1 kHz mono 16-bit WAV
- Type: telegraph (0.1-1.5 s allowed)
- Target duration: 0.45 s
- Loop: no

```
short rising squishy bubbling wobble, soft wet synth bass bending up, playful but clear warning
```

- Generate: 2 s -> `max_new_tokens=104`, `guidance_scale=4.0`, takes: 6
- Post: Trim to the clearest rising gesture; 5 ms fade-in, 30-60 ms fade-out; high-pass at 80 Hz; normalise peak to -3 dBFS (telegraphs carry gameplay information and must cut through, but keep them round, not shrill).
### 23. `sfx.tele.cistern_slimelet`
- File: `assets/audio/sfx/sfx_tele_cistern_slimelet.wav`
- Format: 44.1 kHz mono 16-bit WAV
- Type: telegraph (0.1-1.5 s allowed)
- Target duration: 0.3 s
- Loop: no

```
very short small high squishy bubble pop rising, tiny wet blip, soft
```

- Generate: 2 s -> `max_new_tokens=104`, `guidance_scale=4.0`, takes: 6
- Post: Trim to the clearest rising gesture; 5 ms fade-in, 30-60 ms fade-out; high-pass at 80 Hz; normalise peak to -3 dBFS (telegraphs carry gameplay information and must cut through, but keep them round, not shrill).
### 24. `sfx.tele.drowned_acolyte`
- File: `assets/audio/sfx/sfx_tele_drowned_acolyte.wav`
- Format: 44.1 kHz mono 16-bit WAV
- Type: telegraph (0.1-1.5 s allowed)
- Target duration: 0.6 s
- Loop: no

```
short rising underwater chant-like hum made by a low choir pad, muffled and watery, warning swell
```

- Generate: 2 s -> `max_new_tokens=104`, `guidance_scale=4.0`, takes: 6
- Post: Trim to the clearest rising gesture; 5 ms fade-in, 30-60 ms fade-out; high-pass at 80 Hz; normalise peak to -3 dBFS (telegraphs carry gameplay information and must cut through, but keep them round, not shrill).
### 25. `sfx.tele.deep_eel`
- File: `assets/audio/sfx/sfx_tele_deep_eel.wav`
- Format: 44.1 kHz mono 16-bit WAV
- Type: telegraph (0.1-1.5 s allowed)
- Target duration: 0.4 s
- Loop: no

```
short rising water churn and rush, quick swirling splash building up, ends with a sharp intake
```

- Generate: 2 s -> `max_new_tokens=104`, `guidance_scale=4.0`, takes: 6
- Post: Trim to the clearest rising gesture; 5 ms fade-in, 30-60 ms fade-out; high-pass at 80 Hz; normalise peak to -3 dBFS (telegraphs carry gameplay information and must cut through, but keep them round, not shrill).
### 26. `sfx.tele.rust_golem`
- File: `assets/audio/sfx/sfx_tele_rust_golem.wav`
- Format: 44.1 kHz mono 16-bit WAV
- Type: telegraph (0.1-1.5 s allowed)
- Target duration: 0.6 s
- Loop: no

```
short heavy rusty metal groan rising, creaking iron gears winding up, low and slow, dry
```

- Generate: 2 s -> `max_new_tokens=104`, `guidance_scale=4.0`, takes: 6
- Post: Trim to the clearest rising gesture; 5 ms fade-in, 30-60 ms fade-out; high-pass at 80 Hz; normalise peak to -3 dBFS (telegraphs carry gameplay information and must cut through, but keep them round, not shrill).
### 27. `sfx.tele.lantern_wisp`
- File: `assets/audio/sfx/sfx_tele_lantern_wisp.wav`
- Format: 44.1 kHz mono 16-bit WAV
- Type: telegraph (0.1-1.5 s allowed)
- Target duration: 0.45 s
- Loop: no

```
short soft rising glassy hum, gentle lantern chime swelling, warm and airy, not shrill
```

- Generate: 2 s -> `max_new_tokens=104`, `guidance_scale=4.0`, takes: 6
- Post: Trim to the clearest rising gesture; 5 ms fade-in, 30-60 ms fade-out; high-pass at 80 Hz; normalise peak to -3 dBFS (telegraphs carry gameplay information and must cut through, but keep them round, not shrill).
### 28. `sfx.tele.storm_crystal`
- File: `assets/audio/sfx/sfx_tele_storm_crystal.wav`
- Format: 44.1 kHz mono 16-bit WAV
- Type: telegraph (0.1-1.5 s allowed)
- Target duration: 0.6 s
- Loop: no

```
short rising electric hum building up with crackling static, charging crystal, clear warning, no loud zap at the end
```

- Generate: 2 s -> `max_new_tokens=104`, `guidance_scale=4.0`, takes: 6
- Post: Trim to the clearest rising gesture; 5 ms fade-in, 30-60 ms fade-out; high-pass at 80 Hz; normalise peak to -3 dBFS (telegraphs carry gameplay information and must cut through, but keep them round, not shrill).
### 29. `sfx.boss.drowned_archivist.tele_a`
- File: `assets/audio/sfx/sfx_boss_drowned_archivist_tele_a.wav`
- Format: 44.1 kHz mono 16-bit WAV
- Type: telegraph (0.1-1.5 s allowed)
- Target duration: 0.6 s
- Loop: no

```
short deep rising underwater bell toll with a watery swell, ominous, slow attack, boss warning
```

- Generate: 2 s -> `max_new_tokens=104`, `guidance_scale=4.0`, takes: 6
- Post: Trim to the clearest rising gesture; 5 ms fade-in, 30-60 ms fade-out; high-pass at 80 Hz; normalise peak to -3 dBFS (telegraphs carry gameplay information and must cut through, but keep them round, not shrill).
### 30. `sfx.boss.drowned_archivist.tele_b`
- File: `assets/audio/sfx/sfx_boss_drowned_archivist_tele_b.wav`
- Format: 44.1 kHz mono 16-bit WAV
- Type: telegraph (0.1-1.5 s allowed)
- Target duration: 0.5 s
- Loop: no

```
short urgent rising rush of water and pages fluttering, low drum under it, menacing
```

- Generate: 2 s -> `max_new_tokens=104`, `guidance_scale=4.0`, takes: 6
- Post: Trim to the clearest rising gesture; 5 ms fade-in, 30-60 ms fade-out; high-pass at 80 Hz; normalise peak to -3 dBFS (telegraphs carry gameplay information and must cut through, but keep them round, not shrill).
### 31. `sfx.tele.ghoul_stalker`  (NEW cue id, see note 3 in the intro)
- File: `assets/audio/sfx/sfx_tele_ghoul_stalker.wav`
- Format: 44.1 kHz mono 16-bit WAV
- Type: telegraph (0.1-1.5 s allowed)
- Target duration: 0.5 s
- Loop: no

```
short rising raspy scrape, claws dragging on stone then a sharp intake, tense, warning, no voice
```

- Generate: 2 s -> `max_new_tokens=104`, `guidance_scale=4.0`, takes: 6
- Post: Trim to the clearest rising gesture; 5 ms fade-in, 30-60 ms fade-out; high-pass at 80 Hz; normalise peak to -3 dBFS (telegraphs carry gameplay information and must cut through, but keep them round, not shrill).
### 32. `sfx.tele.riptide_leaper`  (NEW cue id, see note 3 in the intro)
- File: `assets/audio/sfx/sfx_tele_riptide_leaper.wav`
- Format: 44.1 kHz mono 16-bit WAV
- Type: telegraph (0.1-1.5 s allowed)
- Target duration: 0.55 s
- Loop: no

```
short rising wet crouch and spring, splashing water building into a whoosh upward, warning gesture
```

- Generate: 2 s -> `max_new_tokens=104`, `guidance_scale=4.0`, takes: 6
- Post: Trim to the clearest rising gesture; 5 ms fade-in, 30-60 ms fade-out; high-pass at 80 Hz; normalise peak to -3 dBFS (telegraphs carry gameplay information and must cut through, but keep them round, not shrill).
### 33. `sfx.form.beam`
- File: `assets/audio/sfx/sfx_form_beam.wav`
- Format: 44.1 kHz mono 16-bit WAV
- Type: sound effect
- Target duration: 0.8 s
- Loop: no

```
short steady magical beam hum, bright sustained synth tone with a soft shimmer, starts quickly, no melody
```

- Generate: 2 s -> `max_new_tokens=104`, `guidance_scale=4.0`, takes: 6
- Post: Trim to 0.8 s; 10 ms fade-in, 120 ms fade-out; normalise peak to -9 dBFS.
### 34. `sfx.form.field`
- File: `assets/audio/sfx/sfx_form_field.wav`
- Format: 44.1 kHz mono 16-bit WAV
- Type: sound effect
- Target duration: 0.6 s
- Loop: no

```
short soft magical ground pulse, low warm whoosh spreading outward with a gentle shimmer
```

- Generate: 2 s -> `max_new_tokens=104`, `guidance_scale=4.0`, takes: 6
- Post: Trim to one gesture; 3 ms fade-in, 50 ms fade-out; normalise peak to -9 dBFS (layered under the element cast).
### 35. `sfx.mod.chain`
- File: `assets/audio/sfx/sfx_mod_chain.wav`
- Format: 44.1 kHz mono 16-bit WAV
- Type: sound effect
- Target duration: 0.25 s
- Loop: no

```
very short quick ricochet zip, three tiny bright ticks jumping from left to right, light and clean
```

- Generate: 2 s -> `max_new_tokens=104`, `guidance_scale=4.0`, takes: 6
- Post: Trim to one gesture; 3 ms fade-in, 50 ms fade-out; normalise peak to -9 dBFS (layered under the element cast).
### 36. `sfx.mod.generic`
- File: `assets/audio/sfx/sfx_mod_generic.wav`
- Format: 44.1 kHz mono 16-bit WAV
- Type: sound effect
- Target duration: 0.2 s
- Loop: no

```
very short subtle magical tick, soft glass tap with a tiny sparkle, unobtrusive
```

- Generate: 2 s -> `max_new_tokens=104`, `guidance_scale=4.0`, takes: 6
- Post: Trim to one gesture; 3 ms fade-in, 50 ms fade-out; normalise peak to -9 dBFS (layered under the element cast).
### 37. `sfx.trigger.on_hit`
- File: `assets/audio/sfx/sfx_trigger_on_hit.wav`
- Format: 44.1 kHz mono 16-bit WAV
- Type: sound effect
- Target duration: 0.2 s
- Loop: no

```
very short soft magical pop, small bright bubble burst, quick and light
```

- Generate: 2 s -> `max_new_tokens=104`, `guidance_scale=4.0`, takes: 6
- Post: Trim to one gesture; 3 ms fade-in, 50 ms fade-out; normalise peak to -9 dBFS (layered under the element cast).
### 38. `sfx.trigger.on_kill`
- File: `assets/audio/sfx/sfx_trigger_on_kill.wav`
- Format: 44.1 kHz mono 16-bit WAV
- Type: sound effect
- Target duration: 0.3 s
- Loop: no

```
short soft magical burst, rising sparkle with a small airy puff, satisfying, not loud
```

- Generate: 2 s -> `max_new_tokens=104`, `guidance_scale=4.0`, takes: 6
- Post: Trim to one gesture; 3 ms fade-in, 50 ms fade-out; normalise peak to -9 dBFS (layered under the element cast).
### 39. `sfx.trigger.on_expire`
- File: `assets/audio/sfx/sfx_trigger_on_expire.wav`
- Format: 44.1 kHz mono 16-bit WAV
- Type: sound effect
- Target duration: 0.3 s
- Loop: no

```
short soft magical release, gentle downward shimmer ending in a tiny pop
```

- Generate: 2 s -> `max_new_tokens=104`, `guidance_scale=4.0`, takes: 6
- Post: Trim to one gesture; 3 ms fade-in, 50 ms fade-out; normalise peak to -9 dBFS (layered under the element cast).
### 40. `sfx.trigger.timer`
- File: `assets/audio/sfx/sfx_trigger_timer.wav`
- Format: 44.1 kHz mono 16-bit WAV
- Type: sound effect
- Target duration: 0.15 s
- Loop: no

```
very short soft clock-like magical tick, wooden tock with a faint chime, quiet
```

- Generate: 2 s -> `max_new_tokens=104`, `guidance_scale=4.0`, takes: 6
- Post: Trim to one gesture; 3 ms fade-in, 50 ms fade-out; normalise peak to -9 dBFS (layered under the element cast).

## Batch 2 - mood (music, ambience, boss and death moments)
### 41. `music.ruins`
- File: `assets/audio/music/mus_ruins.wav`
- Format: 44.1 kHz mono 16-bit WAV
- Type: music (15-300 s allowed)
- Target duration: 30 s
- Loop: yes

```
dark fantasy dungeon exploration loop, 100 bpm, low cello ostinato, soft frame drum, distant dulcimer melody, dusty ancient ruins, tense but not frantic, instrumental, steady tempo, no intro, no ending
```

- Generate: 32 s -> `max_new_tokens=1604`, `guidance_scale=3.0`, takes: 3
- Post: Generate 32 s; pick the best take; cut to a whole number of bars (see tempo) ending just before the next downbeat; make it loop with make_loop() (0.5 s crossfade); normalise peak to -3 dBFS (target about -16 LUFS if you have a meter); check the seam by looping it 3 times in Audacity.
### 42. `music.cistern`
- File: `assets/audio/music/mus_cistern.wav`
- Format: 44.1 kHz mono 16-bit WAV
- Type: music (15-300 s allowed)
- Target duration: 30 s
- Loop: yes

```
dark submerged ambient loop, 80 bpm, echoing bell tones, deep sub drone, slow plucked harp, dripping water textures, cold and uneasy, instrumental, steady, no intro, no ending
```

- Generate: 32 s -> `max_new_tokens=1604`, `guidance_scale=3.0`, takes: 3
- Post: Generate 32 s; pick the best take; cut to a whole number of bars (see tempo) ending just before the next downbeat; make it loop with make_loop() (0.5 s crossfade); normalise peak to -3 dBFS (target about -16 LUFS if you have a meter); check the seam by looping it 3 times in Audacity.
### 43. `music.boss`
- File: `assets/audio/music/mus_boss.wav`
- Format: 44.1 kHz mono 16-bit WAV
- Type: music (15-300 s allowed)
- Target duration: 30 s
- Loop: yes

```
intense dark fantasy boss battle loop, 140 bpm, pounding war drums, driving low strings ostinato, brass stabs, urgent and heavy, instrumental, constant energy, no intro, no ending
```

- Generate: 32 s -> `max_new_tokens=1604`, `guidance_scale=3.0`, takes: 3
- Post: Generate 32 s; pick the best take; cut to a whole number of bars (see tempo) ending just before the next downbeat; make it loop with make_loop() (0.5 s crossfade); normalise peak to -3 dBFS (target about -16 LUFS if you have a meter); check the seam by looping it 3 times in Audacity.
### 44. `music.workshop`
- File: `assets/audio/music/mus_workshop.wav`
- Format: 44.1 kHz mono 16-bit WAV
- Type: music (15-300 s allowed)
- Target duration: 30 s
- Loop: yes

```
calm cozy fantasy workshop loop, 85 bpm, warm plucked lute, soft music box, gentle bass, curious and safe, magical study room, instrumental, steady, no intro, no ending
```

- Generate: 32 s -> `max_new_tokens=1604`, `guidance_scale=3.0`, takes: 3
- Post: Generate 32 s; pick the best take; cut to a whole number of bars (see tempo) ending just before the next downbeat; make it loop with make_loop() (0.5 s crossfade); normalise peak to -3 dBFS (target about -16 LUFS if you have a meter); check the seam by looping it 3 times in Audacity.
### 45. `amb.ruins`
- File: `assets/audio/amb/amb_ruins.wav`
- Format: 44.1 kHz mono 16-bit WAV
- Type: ambience (5-120 s allowed)
- Target duration: 30 s
- Loop: yes

```
low hollow drone ambience, distant wind moving through stone halls, faint dust and pebbles falling, no melody, no rhythm, no drums
```

- Generate: 32 s -> `max_new_tokens=1604`, `guidance_scale=3.0`, takes: 3
- Post: Generate 30 s; pick a take with no melody or obvious rhythm; loop with make_loop() (1.0 s crossfade); normalise peak to -12 dBFS (ambience sits under everything).
### 46. `amb.workshop`
- File: `assets/audio/amb/amb_workshop.wav`
- Format: 44.1 kHz mono 16-bit WAV
- Type: ambience (5-120 s allowed)
- Target duration: 30 s
- Loop: yes

```
quiet cozy room ambience, soft crackling fireplace, faint ticking clock, gentle paper rustle, warm, no melody, no rhythm
```

- Generate: 32 s -> `max_new_tokens=1604`, `guidance_scale=3.0`, takes: 3
- Post: Generate 30 s; pick a take with no melody or obvious rhythm; loop with make_loop() (1.0 s crossfade); normalise peak to -12 dBFS (ambience sits under everything).
### 47. `sfx.boss.phase`
- File: `assets/audio/sfx/sfx_boss_phase.wav`
- Format: 44.1 kHz mono 16-bit WAV
- Type: sound effect
- Target duration: 1.5 s
- Loop: no

```
short dramatic low orchestral hit with a rising choir swell, dark fantasy boss rage, deep and powerful, fades out
```

- Generate: 2 s -> `max_new_tokens=104`, `guidance_scale=4.0`, takes: 6
- Post: Trim to about 1.5 s; 5 ms fade-in, 300 ms fade-out; normalise peak to -3 dBFS.
### 48. `sfx.boss.death`
- File: `assets/audio/sfx/sfx_boss_death.wav`
- Format: 44.1 kHz mono 16-bit WAV
- Type: sound effect
- Target duration: 2.5 s
- Loop: no

```
short epic falling orchestral chord with a crumbling stone rumble, victory over a dark boss, cymbal swell fading out
```

- Generate: 2 s -> `max_new_tokens=104`, `guidance_scale=4.0`, takes: 6
- Post: Trim to about 2.5 s; 10 ms fade-in, 600 ms fade-out; normalise peak to -3 dBFS.
### 49. `sfx.boss.drowned_archivist.phase`
- File: `assets/audio/sfx/sfx_boss_drowned_archivist_phase.wav`
- Format: 44.1 kHz mono 16-bit WAV
- Type: sound effect
- Target duration: 1.5 s
- Loop: no

```
short dramatic deep underwater orchestral hit, low choir and rushing water swell, ominous, fades out
```

- Generate: 2 s -> `max_new_tokens=104`, `guidance_scale=4.0`, takes: 6
- Post: Trim to about 1.5 s; 5 ms fade-in, 300 ms fade-out; normalise peak to -3 dBFS.

## Batch 3 - reactions, environment, pickups, artifacts, UI
### 50. `sfx.react.shatter`
- File: `assets/audio/sfx/sfx_react_shatter.wav`
- Format: 44.1 kHz mono 16-bit WAV
- Type: sound effect
- Target duration: 0.45 s
- Loop: no

```
short glassy ice crash, bright shattering crystal burst, satisfying, quick decay
```

- Generate: 2 s -> `max_new_tokens=104`, `guidance_scale=4.0`, takes: 6
- Post: Trim to one event; 3 ms fade-in, 80 ms fade-out; normalise peak to -6 dBFS (reactions are rewards: satisfying, slightly louder than a cast).
### 51. `sfx.react.steam`
- File: `assets/audio/sfx/sfx_react_steam.wav`
- Format: 44.1 kHz mono 16-bit WAV
- Type: sound effect
- Target duration: 0.5 s
- Loop: no

```
short hissing steam burst swelling and fading out, airy white hiss, soft, no tone
```

- Generate: 2 s -> `max_new_tokens=104`, `guidance_scale=4.0`, takes: 6
- Post: Trim to one event; 3 ms fade-in, 80 ms fade-out; normalise peak to -6 dBFS (reactions are rewards: satisfying, slightly louder than a cast).
### 52. `sfx.react.arc`
- File: `assets/audio/sfx/sfx_react_arc.wav`
- Format: 44.1 kHz mono 16-bit WAV
- Type: sound effect
- Target duration: 0.3 s
- Loop: no

```
short rapid rising electric chirps, crackling spark jumping three times, bright
```

- Generate: 2 s -> `max_new_tokens=104`, `guidance_scale=4.0`, takes: 6
- Post: Trim to one event; 3 ms fade-in, 80 ms fade-out; normalise peak to -6 dBFS (reactions are rewards: satisfying, slightly louder than a cast).
### 53. `sfx.react.freeze`
- File: `assets/audio/sfx/sfx_react_freeze.wav`
- Format: 44.1 kHz mono 16-bit WAV
- Type: sound effect
- Target duration: 0.4 s
- Loop: no

```
short crackling ice forming, quick freezing crunch with a glassy chime at the end
```

- Generate: 2 s -> `max_new_tokens=104`, `guidance_scale=4.0`, takes: 6
- Post: Trim to one event; 3 ms fade-in, 80 ms fade-out; normalise peak to -6 dBFS (reactions are rewards: satisfying, slightly louder than a cast).
### 54. `sfx.react.extinguish`
- File: `assets/audio/sfx/sfx_react_extinguish.wav`
- Format: 44.1 kHz mono 16-bit WAV
- Type: sound effect
- Target duration: 0.35 s
- Loop: no

```
short sizzle of a flame put out by water, quick hiss dropping to silence
```

- Generate: 2 s -> `max_new_tokens=104`, `guidance_scale=4.0`, takes: 6
- Post: Trim to one event; 3 ms fade-in, 80 ms fade-out; normalise peak to -6 dBFS (reactions are rewards: satisfying, slightly louder than a cast).
### 55. `sfx.env.ignite`
- File: `assets/audio/sfx/sfx_env_ignite.wav`
- Format: 44.1 kHz mono 16-bit WAV
- Type: sound effect
- Target duration: 0.5 s
- Loop: no

```
short whoosh of dry wood catching fire, crackle building quickly
```

- Generate: 2 s -> `max_new_tokens=104`, `guidance_scale=4.0`, takes: 6
- Post: Trim; 3 ms fade-in, 80-150 ms fade-out; normalise peak to -8 dBFS.
### 56. `sfx.env.freeze`
- File: `assets/audio/sfx/sfx_env_freeze.wav`
- Format: 44.1 kHz mono 16-bit WAV
- Type: sound effect
- Target duration: 0.5 s
- Loop: no

```
short creaking ice spreading over a puddle, crisp crackle
```

- Generate: 2 s -> `max_new_tokens=104`, `guidance_scale=4.0`, takes: 6
- Post: Trim; 3 ms fade-in, 80-150 ms fade-out; normalise peak to -8 dBFS.
### 57. `sfx.env.thaw`
- File: `assets/audio/sfx/sfx_env_thaw.wav`
- Format: 44.1 kHz mono 16-bit WAV
- Type: sound effect
- Target duration: 0.5 s
- Loop: no

```
short soft ice melting, gentle drip and crackle fading
```

- Generate: 2 s -> `max_new_tokens=104`, `guidance_scale=4.0`, takes: 6
- Post: Trim; 3 ms fade-in, 80-150 ms fade-out; normalise peak to -8 dBFS.
### 58. `sfx.env.break`
- File: `assets/audio/sfx/sfx_env_break.wav`
- Format: 44.1 kHz mono 16-bit WAV
- Type: sound effect
- Target duration: 0.5 s
- Loop: no

```
short clay pot and stone breaking, crumbling debris, dry, satisfying
```

- Generate: 2 s -> `max_new_tokens=104`, `guidance_scale=4.0`, takes: 6
- Post: Trim; 3 ms fade-in, 80-150 ms fade-out; normalise peak to -8 dBFS.
### 59. `sfx.env.burn_out`
- File: `assets/audio/sfx/sfx_env_burn_out.wav`
- Format: 44.1 kHz mono 16-bit WAV
- Type: sound effect
- Target duration: 0.6 s
- Loop: no

```
short dying fire, embers crackling down to a soft puff of smoke
```

- Generate: 2 s -> `max_new_tokens=104`, `guidance_scale=4.0`, takes: 6
- Post: Trim; 3 ms fade-in, 80-150 ms fade-out; normalise peak to -8 dBFS.
### 60. `sfx.pickup.rune`
- File: `assets/audio/sfx/sfx_pickup_rune.wav`
- Format: 44.1 kHz mono 16-bit WAV
- Type: sound effect
- Target duration: 0.4 s
- Loop: no

```
short sparkling three-note rising celesta, magical and rewarding, clean, bright shimmer
```

- Generate: 2 s -> `max_new_tokens=104`, `guidance_scale=4.0`, takes: 6
- Post: Trim; normalise peak to -6 dBFS.
### 61. `sfx.pickup.currency`
- File: `assets/audio/sfx/sfx_pickup_currency.wav`
- Format: 44.1 kHz mono 16-bit WAV
- Type: sound effect
- Target duration: 0.2 s
- Loop: no

```
very short soft coin clink, two small metal coins touching, bright but gentle
```

- Generate: 2 s -> `max_new_tokens=104`, `guidance_scale=4.0`, takes: 6
- Post: Trim; normalise peak to -10 dBFS (can repeat quickly when many coins drop).
### 62. `sfx.artifact.rebound_sigil`
- File: `assets/audio/sfx/sfx_artifact_rebound_sigil.wav`
- Format: 44.1 kHz mono 16-bit WAV
- Type: sound effect
- Target duration: 0.5 s
- Loop: no

```
short springy magical ricochet, bright twang bouncing back, magical, no melody, quick decay
```

- Generate: 2 s -> `max_new_tokens=104`, `guidance_scale=4.0`, takes: 6
- Post: Trim; 3 ms fade-in, 100 ms fade-out; normalise peak to -8 dBFS. These play when the artifact effect fires, so keep them short.
### 63. `sfx.artifact.residue_crystal`
- File: `assets/audio/sfx/sfx_artifact_residue_crystal.wav`
- Format: 44.1 kHz mono 16-bit WAV
- Type: sound effect
- Target duration: 0.5 s
- Loop: no

```
short soft crystal residue settling, gentle glass sparkle sinking down, magical, no melody, quick decay
```

- Generate: 2 s -> `max_new_tokens=104`, `guidance_scale=4.0`, takes: 6
- Post: Trim; 3 ms fade-in, 100 ms fade-out; normalise peak to -8 dBFS. These play when the artifact effect fires, so keep them short.
### 64. `sfx.artifact.shatterheart`
- File: `assets/audio/sfx/sfx_artifact_shatterheart.wav`
- Format: 44.1 kHz mono 16-bit WAV
- Type: sound effect
- Target duration: 0.5 s
- Loop: no

```
short icy heart burst, deep crystal crack followed by sparkle, magical, no melody, quick decay
```

- Generate: 2 s -> `max_new_tokens=104`, `guidance_scale=4.0`, takes: 6
- Post: Trim; 3 ms fade-in, 100 ms fade-out; normalise peak to -8 dBFS. These play when the artifact effect fires, so keep them short.
### 65. `sfx.artifact.momentum_rune`
- File: `assets/audio/sfx/sfx_artifact_momentum_rune.wav`
- Format: 44.1 kHz mono 16-bit WAV
- Type: sound effect
- Target duration: 0.5 s
- Loop: no

```
short quick rising whoosh with a tiny chime, energetic, magical, no melody, quick decay
```

- Generate: 2 s -> `max_new_tokens=104`, `guidance_scale=4.0`, takes: 6
- Post: Trim; 3 ms fade-in, 100 ms fade-out; normalise peak to -8 dBFS. These play when the artifact effect fires, so keep them short.
### 66. `sfx.artifact.echo_chamber`
- File: `assets/audio/sfx/sfx_artifact_echo_chamber.wav`
- Format: 44.1 kHz mono 16-bit WAV
- Type: sound effect
- Target duration: 0.5 s
- Loop: no

```
short magical echo, a soft bell note repeating once quieter, magical, no melody, quick decay
```

- Generate: 2 s -> `max_new_tokens=104`, `guidance_scale=4.0`, takes: 6
- Post: Trim; 3 ms fade-in, 100 ms fade-out; normalise peak to -8 dBFS. These play when the artifact effect fires, so keep them short.
### 67. `sfx.artifact.stormglass`
- File: `assets/audio/sfx/sfx_artifact_stormglass.wav`
- Format: 44.1 kHz mono 16-bit WAV
- Type: sound effect
- Target duration: 0.5 s
- Loop: no

```
short bright glassy electric ring, crackling crystal, magical, no melody, quick decay
```

- Generate: 2 s -> `max_new_tokens=104`, `guidance_scale=4.0`, takes: 6
- Post: Trim; 3 ms fade-in, 100 ms fade-out; normalise peak to -8 dBFS. These play when the artifact effect fires, so keep them short.
### 68. `sfx.artifact.tidewalkers_boots`
- File: `assets/audio/sfx/sfx_artifact_tidewalkers_boots.wav`
- Format: 44.1 kHz mono 16-bit WAV
- Type: sound effect
- Target duration: 0.5 s
- Loop: no

```
short soft water splash step, gentle wave lapping, magical, no melody, quick decay
```

- Generate: 2 s -> `max_new_tokens=104`, `guidance_scale=4.0`, takes: 6
- Post: Trim; 3 ms fade-in, 100 ms fade-out; normalise peak to -8 dBFS. These play when the artifact effect fires, so keep them short.
### 69. `sfx.artifact.ember_heart`
- File: `assets/audio/sfx/sfx_artifact_ember_heart.wav`
- Format: 44.1 kHz mono 16-bit WAV
- Type: sound effect
- Target duration: 0.5 s
- Loop: no

```
short warm ember flare, soft crackle and glow swell, magical, no melody, quick decay
```

- Generate: 2 s -> `max_new_tokens=104`, `guidance_scale=4.0`, takes: 6
- Post: Trim; 3 ms fade-in, 100 ms fade-out; normalise peak to -8 dBFS. These play when the artifact effect fires, so keep them short.
### 70. `sfx.artifact.gravity_lens`
- File: `assets/audio/sfx/sfx_artifact_gravity_lens.wav`
- Format: 44.1 kHz mono 16-bit WAV
- Type: sound effect
- Target duration: 0.5 s
- Loop: no

```
short low warped whoosh bending downward, gravity pull, magical, no melody, quick decay
```

- Generate: 2 s -> `max_new_tokens=104`, `guidance_scale=4.0`, takes: 6
- Post: Trim; 3 ms fade-in, 100 ms fade-out; normalise peak to -8 dBFS. These play when the artifact effect fires, so keep them short.
### 71. `sfx.artifact.split_prism`
- File: `assets/audio/sfx/sfx_artifact_split_prism.wav`
- Format: 44.1 kHz mono 16-bit WAV
- Type: sound effect
- Target duration: 0.5 s
- Loop: no

```
short prismatic shimmer splitting into two bright notes, magical, no melody, quick decay
```

- Generate: 2 s -> `max_new_tokens=104`, `guidance_scale=4.0`, takes: 6
- Post: Trim; 3 ms fade-in, 100 ms fade-out; normalise peak to -8 dBFS. These play when the artifact effect fires, so keep them short.
### 72. `sfx.artifact.archivists_quill`
- File: `assets/audio/sfx/sfx_artifact_archivists_quill.wav`
- Format: 44.1 kHz mono 16-bit WAV
- Type: sound effect
- Target duration: 0.5 s
- Loop: no

```
short quill scratch on parchment with a faint magical chime, magical, no melody, quick decay
```

- Generate: 2 s -> `max_new_tokens=104`, `guidance_scale=4.0`, takes: 6
- Post: Trim; 3 ms fade-in, 100 ms fade-out; normalise peak to -8 dBFS. These play when the artifact effect fires, so keep them short.
### 73. `sfx.artifact.warding_lantern`
- File: `assets/audio/sfx/sfx_artifact_warding_lantern.wav`
- Format: 44.1 kHz mono 16-bit WAV
- Type: sound effect
- Target duration: 0.5 s
- Loop: no

```
short warm protective hum swelling, soft bell, comforting, magical, no melody, quick decay
```

- Generate: 2 s -> `max_new_tokens=104`, `guidance_scale=4.0`, takes: 6
- Post: Trim; 3 ms fade-in, 100 ms fade-out; normalise peak to -8 dBFS. These play when the artifact effect fires, so keep them short.
### 74. `ui.hover`
- File: `assets/audio/ui/ui_hover.wav`
- Format: 44.1 kHz mono 16-bit WAV
- Type: UI
- Target duration: 0.06 s
- Loop: no

```
very short soft wooden tick, tiny and quiet, single click
```

- Generate: 2 s -> `max_new_tokens=104`, `guidance_scale=4.0`, takes: 6
- Post: Trim to the transient; 2 ms fade-in, 30 ms fade-out; normalise peak to -12 dBFS (UI must be quiet and never tiring).
### 75. `ui.confirm`
- File: `assets/audio/ui/ui_confirm.wav`
- Format: 44.1 kHz mono 16-bit WAV
- Type: UI
- Target duration: 0.15 s
- Loop: no

```
very short soft confirming two-note chime, warm, rising
```

- Generate: 2 s -> `max_new_tokens=104`, `guidance_scale=4.0`, takes: 6
- Post: Trim to the transient; 2 ms fade-in, 30 ms fade-out; normalise peak to -12 dBFS (UI must be quiet and never tiring).
### 76. `ui.cancel`
- File: `assets/audio/ui/ui_cancel.wav`
- Format: 44.1 kHz mono 16-bit WAV
- Type: UI
- Target duration: 0.12 s
- Loop: no

```
very short soft falling two-note wooden tock, gentle
```

- Generate: 2 s -> `max_new_tokens=104`, `guidance_scale=4.0`, takes: 6
- Post: Trim to the transient; 2 ms fade-in, 30 ms fade-out; normalise peak to -12 dBFS (UI must be quiet and never tiring).
### 77. `ui.editor_error`
- File: `assets/audio/ui/ui_editor_error.wav`
- Format: 44.1 kHz mono 16-bit WAV
- Type: UI
- Target duration: 0.2 s
- Loop: no

```
very short soft low muted buzz, gentle error, dull, not harsh
```

- Generate: 2 s -> `max_new_tokens=104`, `guidance_scale=4.0`, takes: 6
- Post: Trim to the transient; 2 ms fade-in, 30 ms fade-out; normalise peak to -12 dBFS (UI must be quiet and never tiring).
### 78. `ui.purchase`
- File: `assets/audio/ui/ui_purchase.wav`
- Format: 44.1 kHz mono 16-bit WAV
- Type: UI
- Target duration: 0.35 s
- Loop: no

```
short coin pouch jingle with a soft confirming chime
```

- Generate: 2 s -> `max_new_tokens=104`, `guidance_scale=4.0`, takes: 6
- Post: Trim to the transient; 2 ms fade-in, 30 ms fade-out; normalise peak to -12 dBFS (UI must be quiet and never tiring).
### 79. `ui.reward_pick`
- File: `assets/audio/ui/ui_reward_pick.wav`
- Format: 44.1 kHz mono 16-bit WAV
- Type: UI
- Target duration: 0.4 s
- Loop: no

```
short magical card flip with a soft sparkle, rewarding
```

- Generate: 2 s -> `max_new_tokens=104`, `guidance_scale=4.0`, takes: 6
- Post: Trim to the transient; 2 ms fade-in, 30 ms fade-out; normalise peak to -12 dBFS (UI must be quiet and never tiring).

---
Total: 79 cues (77 mapped today + 2 new telegraph ids).
