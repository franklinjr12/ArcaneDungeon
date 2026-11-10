# Audio priority: first 20 cues to replace (AD-192)

This list is derived from docs/demo/AUDIO_STATUS.md. The order below is the replacement order: work top to bottom.

## Before you start

- musicgen-small is built for music. It suits rows 12-16. For the short SFX Franklin may prefer recording or CC0 sounds (his choice), and the SFX prompts are only a starting point.
- musicgen-small outputs 32 kHz (accepted) and about 30 s per generation.
- Drop each file at the exact path in the row, then run `python3 scripts/audio_check.py`.
- QA limits (PROPOSED in AUDIO_STATUS):
  - .wav must be PCM. .ogg must be Vorbis, not Opus (e.g. `ffmpeg -i in.wav -c:a libvorbis out.ogg`).
  - Sample rate 32000, 44100 or 48000 Hz.
  - Peak <= -1 dBFS.
  - Length: music 15-300 s, ambience 5-120 s, SFX 0.03-5 s, telegraph 0.1-1.5 s.
  - Loop cues loop the whole file and the seam jump must be <= 0.1 of full scale.

## Batch 1: most heard

| # | cue id | file | format | length | loop | mood | musicgen-small prompt |
|---|---|---|---|---|---|---|---|
| 1 | sfx.tele.bone_thrall | `assets/audio/sfx/sfx_tele_bone_thrall.wav` | wav | about 0.4 s (0.1-1.5) | no | dry, bony, warning, rising | short rising bone rattle warning, dry percussion, no melody |
| 2 | sfx.boss.tele_a | `assets/audio/sfx/sfx_boss_tele_a.wav` | wav | about 0.45 s (0.1-1.5) | no | heavy, ominous, swelling | short deep ominous brass swell rising fast, dark fantasy stinger |
| 3 | sfx.boss.tele_b | `assets/audio/sfx/sfx_boss_tele_b.wav` | wav | about 0.45 s (0.1-1.5) | no | urgent, stepped, menacing | three quick rising low drum hits, menacing dark fantasy stinger |
| 4 | sfx.player.hurt | `assets/audio/sfx/sfx_player_hurt.wav` | wav | about 0.2 s (0.03-5) | no | sharp, painful, brief | very short sharp low impact with a falling tone, painful stinger |
| 5 | sfx.hit.generic | `assets/audio/sfx/sfx_hit_generic.wav` | wav | about 0.1 s (0.03-5) | no | dull, punchy, soft | very short soft dull thud, single muted drum hit |
| 6 | sfx.cast.neutral | `assets/audio/sfx/sfx_cast_neutral.wav` | wav | about 0.1 s (0.03-5) | no | clean, arcane, light | very short soft magical chime pluck, single note |
| 7 | sfx.cast.fire | `assets/audio/sfx/sfx_cast_fire.wav` | wav | about 0.2 s (0.03-5) | no | crackling, hot, quick | very short crackling fire whoosh percussion, single burst |
| 8 | sfx.cast.water | `assets/audio/sfx/sfx_cast_water.wav` | wav | about 0.2 s (0.03-5) | no | bubbling, wet, round | very short bubbling water pluck, round and soft |
| 9 | sfx.cast.lightning | `assets/audio/sfx/sfx_cast_lightning.wav` | wav | about 0.15 s (0.03-5) | no | electric, snapping, bright | very short electric zap synth, bright snapping burst |
| 10 | sfx.dash | `assets/audio/sfx/sfx_dash.wav` | wav | about 0.2 s (0.03-5) | no | airy, fast, falling | very short airy whoosh falling in pitch, no melody |
| 11 | sfx.room.cleared | `assets/audio/sfx/sfx_room_cleared.wav` | wav | about 0.6 s (0.03-5) | no | relieved, bright, resolved | short bright rising four-note harp arpeggio, victorious resolved fantasy jingle |

## Batch 2: mood

| # | cue id | file | format | length | loop | mood | musicgen-small prompt |
|---|---|---|---|---|---|---|---|
| 12 | music.ruins | `assets/audio/music/mus_ruins.ogg` | ogg | about 30 s (15-300) | yes | ancient, tense, dusty, driving | dark fantasy dungeon loop, low strings and frame drum, tense and ancient, steady pulse, instrumental |
| 13 | music.cistern | `assets/audio/music/mus_cistern.ogg` | ogg | about 30 s (15-300) | yes | drowned, cold, echoing, uneasy | submerged dark ambient loop, echoing bells and slow bass, cold and uneasy, instrumental |
| 14 | music.boss | `assets/audio/music/mus_boss.ogg` | ogg | about 30 s (15-300) | yes | urgent, heavy, relentless | intense dark fantasy boss battle loop, pounding war drums and low brass, fast and relentless, instrumental |
| 15 | music.workshop | `assets/audio/music/mus_workshop.ogg` | ogg | about 30 s (15-300) | yes | warm, safe, curious, calm | calm cozy fantasy workshop loop, warm plucked lute and soft flute, gentle and curious, instrumental |
| 16 | amb.ruins | `assets/audio/amb/amb_ruins.wav` | wav | about 30 s (5-120) | yes | hollow, dusty, distant | low hollow drone ambience, distant wind in stone halls, no melody, no drums |

## Batch 3: reactions, pickup, UI

| # | cue id | file | format | length | loop | mood | musicgen-small prompt |
|---|---|---|---|---|---|---|---|
| 17 | sfx.react.shatter | `assets/audio/sfx/sfx_react_shatter.ogg` | ogg | about 0.4 s (0.03-5) | no | icy, breaking, glassy | short glassy ice crash, bright shattering percussion, single hit |
| 18 | sfx.react.steam | `assets/audio/sfx/sfx_react_steam.ogg` | ogg | about 0.5 s (0.03-5) | no | hissing, hot, airy | short hissing white noise swell fading out, airy texture, no melody |
| 19 | sfx.react.arc | `assets/audio/sfx/sfx_react_arc.wav` | wav | about 0.25 s (0.03-5) | no | jumping, electric, chirping | short rapid rising electric chirps, crackling synth burst |
| 20 | sfx.pickup.rune | `assets/audio/sfx/sfx_pickup_rune.wav` | wav | about 0.35 s (0.03-5) | no | magical, rewarding, sparkling | short sparkling three-note rising celesta jingle, magical reward |

## Notes

- Row 19: the task's conduct reaction uses sfx.react.arc. There is no separate conduct cue.
- Rows 1, 2, 3 and 20 are shared fallbacks. Row 1 also covers the 10 enemy telegraphs that have no file of their own. Rows 2 and 3 also cover the drowned_archivist tele_a and tele_b. Row 20 also covers the 12 artifact cues.
- amb.ruins (row 16) is also the current fallback for music.ruins, music.cistern and music.boss, so replacing it first would change what those play until their own files exist.
- The task names 21 distinct cues but ACCEPT requires 20 rows, so the last one in the task's order is held back as next up: `ui.confirm`, file `assets/audio/ui/ui_confirm.wav`, wav, about 0.07 s (0.03-5), no loop, mood soft, clean, clicky, prompt: very short soft two-note wooden click, clean UI blip. It is the press sound for every button, so click and confirm are one cue. Franklin can swap it with any row.
