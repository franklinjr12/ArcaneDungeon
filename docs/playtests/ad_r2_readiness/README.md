# AD-041 playtest-readiness screenshots (ad_r2_readiness)

Developer capture, not a test. Regenerate the whole set (about 80 s, needs a display):

```
xvfb-run -a /usr/local/bin/godot --path . --script res://tests/capture_ad_r2_readiness.gd -- docs/playtests/ad_r2_readiness
```

- Script: `tests/capture_ad_r2_readiness.gd` (prints `CAPTURED:` / `MISSING:`; the last run had nothing missing).
- Seed: `20261022` (the scripted route seed; `run.tscn` starts on it, `tests/m3_run_driver.gd` plays the route shots).
- Godot: 4.7.1.stable.official.a13da4feb, 1280x720 window, compatibility renderer under xvfb (llvmpipe).
- Visuals: P1 default (`Art.use_art_export = false`) in every shot except `p0_f6_comparison.png`.
- Staging: element, arc, telegraph, phase and hitbox shots use an isolated room with the encounter removed and one or two enemies spawned on purpose (enemy HP raised to 9999, mage health refilled each tick so the shot is not cut short). `hud`, `reward_pick` and `run_summary` come from the unmodified scripted route.
- Hitbox shots are a 2x nearest-neighbour crop of the 1x frame with the F3 debug overlay on (magenta circle = sim hurtbox radius). Taken in a non-windup frame so the telegraph disc does not cover the body.

## Shots

| PNG | Shows |
|---|---|
| `hud.png` | Room 1 mid-fight on the P1 HUD: portrait/HP/MP, slot bar with icons and cooldowns, enemy on the field. |
| `p0_f6_comparison.png` | Same frame as `hud.png` with `Art.use_art_export` on (the F6 comparison view, P0 floor/sprites). |
| `fire_cast.png` | Fire projectile in flight toward a bone thrall. |
| `fire_status.png` | Fire on-hit burst on the thrall, then Burning icon/overlay. |
| `water_cast.png` | Water projectile in flight. |
| `water_status.png` | Water burst, Wet status on the thrall. |
| `lightning_cast.png` | Lightning projectile in flight. |
| `lightning_status.png` | Lightning burst, Charged status on the thrall. |
| `wet_lightning_arc.png` | Two Wet bone thralls; lightning hit arcs to the second (reaction.arc FX and `ARC!` label). |
| `telegraph_bone_thrall.png` | Thrall windup, circle telegraph, countdown label, captured at half the window. |
| `telegraph_fallen_adept.png` | Adept windup line telegraph (half window). |
| `telegraph_grave_hound.png` | Hound windup line telegraph (half window). |
| `telegraph_undead_warden.png` | Warden radial windup telegraph, `! BOSS RADIAL` label (half window). |
| `warden_phase_cue.png` | Warden health set to 40% (threshold 50%); `boss.phase` ring FX on the warden two ticks after the phase flips. |
| `reward_pick.png` | Room 1 cleared by the scripted policy: three reward cards (Homing, Orb, On Hit) in the sidebar. |
| `editor_rejection.png` | Workshop spell editor on slot 4 with the locked Orb form chosen: `INVALID — cannot apply: RUNE_LOCKED: Rune not unlocked: form.orb`, Apply disabled. |
| `run_summary.png` | Scripted slice win: RUN SUMMARY — VICTORY with rooms, kills, time, spells, seed 20261022. |
| `hitbox_mage.png` | Mage with hurtbox circle (2x crop). |
| `hitbox_bone_thrall.png` | Bone thrall with hurtbox circle (2x crop). |
| `hitbox_fallen_adept.png` | Fallen adept with hurtbox circle (2x crop). |
| `hitbox_grave_hound.png` | Grave hound with hurtbox circle (2x crop). |
| `hitbox_undead_warden.png` | Undead warden with hurtbox circle (2x crop). |

## Hitbox verdicts (GDD pillar 3: enemy circles cover most of the body, player may be smaller)

No radius was changed in this step.

| Actor | Radius | Verdict | Change |
|---|---|---|---|
| Mage | 17 | smaller than the sprite (allowed for the player) | unchanged since AD-065 |
| Bone thrall | 23 | covers the torso and legs; the raised spear sticks out | unchanged since AD-065 |
| Fallen adept | 23 | covers body and head | unchanged since AD-065 |
| Grave hound | 23 | covers body and head, tail sticks out | unchanged since AD-065 |
| Undead warden | 49 | covers torso, head and shield; cape hem sticks out | unchanged since AD-065 |

## Notes for reviewers

- In `telegraph_undead_warden.png` the radial disc is drawn over the warden, so the warden sprite is hidden for most of the windup. This is how the current P1 telegraph renders; it was not changed here. Please judge it in the readability review.
- The Burning/Wet/Charged statuses and the arc come from the real burst on-hit pipeline, not from applying statuses by hand (the script only forces Wet on the two arc targets, as the in-game workshop button does).
- Cast shots are 1x, so the projectile sprites are small by design.

## Reviewer verdicts

Not filled in. To be completed by the reviewers, not by the capture author.

**Game design: readability** (PASS / DEGRADED / FAIL per shot)

| Shot | Verdict | Notes |
|---|---|---|
| hud | | |
| fire_cast / fire_status | | |
| water_cast / water_status | | |
| lightning_cast / lightning_status | | |
| wet_lightning_arc | | |
| telegraph_bone_thrall | | |
| telegraph_fallen_adept | | |
| telegraph_grave_hound | | |
| telegraph_undead_warden | | |
| warden_phase_cue | | |
| reward_pick | | |
| editor_rejection | | |
| run_summary | | |
| hitbox_* (5) | | |

**Game art: confirmation** (art matches `docs/assets/art_style_reference.png` and `docs/art_direction.md`)

| Reviewer | Verdict | Notes |
|---|---|---|
| | | |
