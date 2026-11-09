# Audio status (AD-188)

Regenerate: `python3 scripts/audio_check.py` (reads game/audio/audio_cues_v1.json and assets/audio/).

| group | total | placeholder or silent | dropped |
|---|---|---|---|
| Music | 4 | 4 | 0 |
| Ambience | 2 | 2 | 0 |
| SFX | 71 | 71 | 0 |
| Total | 77 | 77 | 0 |

## Missing: generate these

### Music

| id | file to create | current fallback | target |
|---|---|---|---|
| music.boss | assets/audio/music/mus_boss.ogg | assets/audio/amb/amb_ruins.wav | ogg, 15-300 s, loop |
| music.cistern | assets/audio/music/mus_cistern.ogg | assets/audio/amb/amb_ruins.wav | ogg, 15-300 s, loop |
| music.ruins | assets/audio/music/mus_ruins.ogg | assets/audio/amb/amb_ruins.wav | ogg, 15-300 s, loop |
| music.workshop | assets/audio/music/mus_workshop.ogg | assets/audio/amb/amb_workshop.wav | ogg, 15-300 s, loop |

### Ambience

| id | file to create | current fallback | target |
|---|---|---|---|
| amb.ruins | assets/audio/amb/amb_ruins.wav | generated placeholder (same file) | wav, 5-120 s, loop |
| amb.workshop | assets/audio/amb/amb_workshop.wav | generated placeholder (same file) | wav, 5-120 s, loop |

### SFX

| id | file to create | current fallback | target |
|---|---|---|---|
| sfx.artifact.archivists_quill | assets/audio/sfx/sfx_artifact_archivists_quill.ogg | assets/audio/sfx/sfx_pickup_rune.wav | ogg, 0.03-5 s |
| sfx.artifact.echo_chamber | assets/audio/sfx/sfx_artifact_echo_chamber.ogg | assets/audio/sfx/sfx_pickup_rune.wav | ogg, 0.03-5 s |
| sfx.artifact.ember_heart | assets/audio/sfx/sfx_artifact_ember_heart.ogg | assets/audio/sfx/sfx_pickup_rune.wav | ogg, 0.03-5 s |
| sfx.artifact.gravity_lens | assets/audio/sfx/sfx_artifact_gravity_lens.ogg | assets/audio/sfx/sfx_pickup_rune.wav | ogg, 0.03-5 s |
| sfx.artifact.momentum_rune | assets/audio/sfx/sfx_artifact_momentum_rune.ogg | assets/audio/sfx/sfx_pickup_rune.wav | ogg, 0.03-5 s |
| sfx.artifact.rebound_sigil | assets/audio/sfx/sfx_artifact_rebound_sigil.ogg | assets/audio/sfx/sfx_pickup_rune.wav | ogg, 0.03-5 s |
| sfx.artifact.residue_crystal | assets/audio/sfx/sfx_artifact_residue_crystal.ogg | assets/audio/sfx/sfx_pickup_rune.wav | ogg, 0.03-5 s |
| sfx.artifact.shatterheart | assets/audio/sfx/sfx_artifact_shatterheart.ogg | assets/audio/sfx/sfx_pickup_rune.wav | ogg, 0.03-5 s |
| sfx.artifact.split_prism | assets/audio/sfx/sfx_artifact_split_prism.ogg | assets/audio/sfx/sfx_pickup_rune.wav | ogg, 0.03-5 s |
| sfx.artifact.stormglass | assets/audio/sfx/sfx_artifact_stormglass.ogg | assets/audio/sfx/sfx_pickup_rune.wav | ogg, 0.03-5 s |
| sfx.artifact.tidewalkers_boots | assets/audio/sfx/sfx_artifact_tidewalkers_boots.ogg | assets/audio/sfx/sfx_pickup_rune.wav | ogg, 0.03-5 s |
| sfx.artifact.warding_lantern | assets/audio/sfx/sfx_artifact_warding_lantern.ogg | assets/audio/sfx/sfx_pickup_rune.wav | ogg, 0.03-5 s |
| sfx.boss.death | assets/audio/sfx/sfx_boss_death.wav | generated placeholder (same file) | wav, 0.03-5 s |
| sfx.boss.drowned_archivist.phase | assets/audio/sfx/sfx_boss_drowned_archivist_phase.ogg | assets/audio/sfx/sfx_boss_phase.wav | ogg, 0.03-5 s |
| sfx.boss.drowned_archivist.tele_a | assets/audio/sfx/sfx_boss_drowned_archivist_tele_a.ogg | assets/audio/sfx/sfx_boss_tele_a.wav | ogg, 0.1-1.5 s |
| sfx.boss.drowned_archivist.tele_b | assets/audio/sfx/sfx_boss_drowned_archivist_tele_b.ogg | assets/audio/sfx/sfx_boss_tele_b.wav | ogg, 0.1-1.5 s |
| sfx.boss.phase | assets/audio/sfx/sfx_boss_phase.wav | generated placeholder (same file) | wav, 0.03-5 s |
| sfx.boss.tele_a | assets/audio/sfx/sfx_boss_tele_a.wav | generated placeholder (same file) | wav, 0.1-1.5 s |
| sfx.boss.tele_b | assets/audio/sfx/sfx_boss_tele_b.wav | generated placeholder (same file) | wav, 0.1-1.5 s |
| sfx.cast.cold | assets/audio/sfx/sfx_cast_cold.ogg | assets/audio/sfx/sfx_cast_neutral.wav | ogg, 0.03-5 s |
| sfx.cast.fire | assets/audio/sfx/sfx_cast_fire.wav | generated placeholder (same file) | wav, 0.03-5 s |
| sfx.cast.force | assets/audio/sfx/sfx_cast_force.ogg | assets/audio/sfx/sfx_cast_neutral.wav | ogg, 0.03-5 s |
| sfx.cast.lightning | assets/audio/sfx/sfx_cast_lightning.wav | generated placeholder (same file) | wav, 0.03-5 s |
| sfx.cast.neutral | assets/audio/sfx/sfx_cast_neutral.wav | generated placeholder (same file) | wav, 0.03-5 s |
| sfx.cast.rejected | assets/audio/sfx/sfx_cast_rejected.wav | generated placeholder (same file) | wav, 0.03-5 s |
| sfx.cast.water | assets/audio/sfx/sfx_cast_water.wav | generated placeholder (same file) | wav, 0.03-5 s |
| sfx.dash | assets/audio/sfx/sfx_dash.wav | generated placeholder (same file) | wav, 0.03-5 s |
| sfx.dash.iframe | assets/audio/sfx/sfx_dash_iframe.wav | generated placeholder (same file) | wav, 0.03-5 s |
| sfx.env.break | assets/audio/sfx/sfx_env_break.ogg | assets/audio/sfx/sfx_hit_generic.wav | ogg, 0.03-5 s |
| sfx.env.burn_out | assets/audio/sfx/sfx_env_burn_out.ogg | assets/audio/sfx/sfx_hit_generic.wav | ogg, 0.03-5 s |
| sfx.env.freeze | assets/audio/sfx/sfx_env_freeze.ogg | assets/audio/sfx/sfx_hit_generic.wav | ogg, 0.03-5 s |
| sfx.env.ignite | assets/audio/sfx/sfx_env_ignite.ogg | assets/audio/sfx/sfx_hit_generic.wav | ogg, 0.03-5 s |
| sfx.env.thaw | assets/audio/sfx/sfx_env_thaw.ogg | assets/audio/sfx/sfx_hit_generic.wav | ogg, 0.03-5 s |
| sfx.form.beam | assets/audio/sfx/sfx_form_beam.ogg | assets/audio/sfx/sfx_cast_neutral.wav | ogg, 0.03-5 s |
| sfx.form.field | assets/audio/sfx/sfx_form_field.ogg | assets/audio/sfx/sfx_cast_neutral.wav | ogg, 0.03-5 s |
| sfx.hit.generic | assets/audio/sfx/sfx_hit_generic.wav | generated placeholder (same file) | wav, 0.03-5 s |
| sfx.mod.chain | assets/audio/sfx/sfx_mod_chain.ogg | assets/audio/sfx/sfx_react_arc.wav | ogg, 0.03-5 s |
| sfx.mod.generic | assets/audio/sfx/sfx_mod_generic.ogg | assets/audio/sfx/sfx_cast_neutral.wav | ogg, 0.03-5 s |
| sfx.pickup.currency | assets/audio/sfx/sfx_pickup_currency.wav | generated placeholder (same file) | wav, 0.03-5 s |
| sfx.pickup.rune | assets/audio/sfx/sfx_pickup_rune.wav | generated placeholder (same file) | wav, 0.03-5 s |
| sfx.player.death | assets/audio/sfx/sfx_player_death.wav | generated placeholder (same file) | wav, 0.03-5 s |
| sfx.player.hurt | assets/audio/sfx/sfx_player_hurt.wav | generated placeholder (same file) | wav, 0.03-5 s |
| sfx.react.arc | assets/audio/sfx/sfx_react_arc.wav | generated placeholder (same file) | wav, 0.03-5 s |
| sfx.react.extinguish | assets/audio/sfx/sfx_react_extinguish.wav | generated placeholder (same file) | wav, 0.03-5 s |
| sfx.react.freeze | assets/audio/sfx/sfx_react_freeze.ogg | assets/audio/sfx/sfx_react_extinguish.wav | ogg, 0.03-5 s |
| sfx.react.shatter | assets/audio/sfx/sfx_react_shatter.ogg | assets/audio/sfx/sfx_react_arc.wav | ogg, 0.03-5 s |
| sfx.react.steam | assets/audio/sfx/sfx_react_steam.ogg | assets/audio/sfx/sfx_react_extinguish.wav | ogg, 0.03-5 s |
| sfx.room.cleared | assets/audio/sfx/sfx_room_cleared.wav | generated placeholder (same file) | wav, 0.03-5 s |
| sfx.tele.bone_thrall | assets/audio/sfx/sfx_tele_bone_thrall.wav | generated placeholder (same file) | wav, 0.1-1.5 s |
| sfx.tele.cistern_slime | assets/audio/sfx/sfx_tele_cistern_slime.ogg | assets/audio/sfx/sfx_tele_bone_thrall.wav | ogg, 0.1-1.5 s |
| sfx.tele.cistern_slimelet | assets/audio/sfx/sfx_tele_cistern_slimelet.ogg | assets/audio/sfx/sfx_tele_bone_thrall.wav | ogg, 0.1-1.5 s |
| sfx.tele.corpse_bloat | assets/audio/sfx/sfx_tele_corpse_bloat.ogg | assets/audio/sfx/sfx_tele_bone_thrall.wav | ogg, 0.1-1.5 s |
| sfx.tele.deep_eel | assets/audio/sfx/sfx_tele_deep_eel.ogg | assets/audio/sfx/sfx_tele_bone_thrall.wav | ogg, 0.1-1.5 s |
| sfx.tele.drowned_acolyte | assets/audio/sfx/sfx_tele_drowned_acolyte.ogg | assets/audio/sfx/sfx_tele_bone_thrall.wav | ogg, 0.1-1.5 s |
| sfx.tele.fallen_adept | assets/audio/sfx/sfx_tele_fallen_adept.wav | generated placeholder (same file) | wav, 0.1-1.5 s |
| sfx.tele.grave_hound | assets/audio/sfx/sfx_tele_grave_hound.wav | generated placeholder (same file) | wav, 0.1-1.5 s |
| sfx.tele.lantern_wisp | assets/audio/sfx/sfx_tele_lantern_wisp.ogg | assets/audio/sfx/sfx_tele_bone_thrall.wav | ogg, 0.1-1.5 s |
| sfx.tele.ossuary_shieldbearer | assets/audio/sfx/sfx_tele_ossuary_shieldbearer.ogg | assets/audio/sfx/sfx_tele_bone_thrall.wav | ogg, 0.1-1.5 s |
| sfx.tele.rust_golem | assets/audio/sfx/sfx_tele_rust_golem.ogg | assets/audio/sfx/sfx_tele_bone_thrall.wav | ogg, 0.1-1.5 s |
| sfx.tele.storm_crystal | assets/audio/sfx/sfx_tele_storm_crystal.ogg | assets/audio/sfx/sfx_tele_bone_thrall.wav | ogg, 0.1-1.5 s |
| sfx.tele.wailing_spirit | assets/audio/sfx/sfx_tele_wailing_spirit.ogg | assets/audio/sfx/sfx_tele_bone_thrall.wav | ogg, 0.1-1.5 s |
| sfx.trigger.on_expire | assets/audio/sfx/sfx_trigger_on_expire.ogg | assets/audio/sfx/sfx_hit_generic.wav | ogg, 0.03-5 s |
| sfx.trigger.on_hit | assets/audio/sfx/sfx_trigger_on_hit.ogg | assets/audio/sfx/sfx_hit_generic.wav | ogg, 0.03-5 s |
| sfx.trigger.on_kill | assets/audio/sfx/sfx_trigger_on_kill.ogg | assets/audio/sfx/sfx_hit_generic.wav | ogg, 0.03-5 s |
| sfx.trigger.timer | assets/audio/sfx/sfx_trigger_timer.ogg | assets/audio/sfx/sfx_hit_generic.wav | ogg, 0.03-5 s |
| ui.cancel | assets/audio/ui/ui_cancel.wav | generated placeholder (same file) | wav, 0.03-5 s |
| ui.confirm | assets/audio/ui/ui_confirm.wav | generated placeholder (same file) | wav, 0.03-5 s |
| ui.editor_error | assets/audio/ui/ui_editor_error.wav | generated placeholder (same file) | wav, 0.03-5 s |
| ui.hover | assets/audio/ui/ui_hover.wav | generated placeholder (same file) | wav, 0.03-5 s |
| ui.purchase | assets/audio/ui/ui_purchase.wav | generated placeholder (same file) | wav, 0.03-5 s |
| ui.reward_pick | assets/audio/ui/ui_reward_pick.wav | generated placeholder (same file) | wav, 0.03-5 s |

## Dropped files

None.

## Unmapped files

None.

## All sound ids

| id | group | status |
|---|---|---|
| music.boss | music | placeholder |
| music.cistern | music | placeholder |
| music.ruins | music | placeholder |
| music.workshop | music | placeholder |
| amb.ruins | ambience | placeholder |
| amb.workshop | ambience | placeholder |
| sfx.artifact.archivists_quill | sfx | placeholder |
| sfx.artifact.echo_chamber | sfx | placeholder |
| sfx.artifact.ember_heart | sfx | placeholder |
| sfx.artifact.gravity_lens | sfx | placeholder |
| sfx.artifact.momentum_rune | sfx | placeholder |
| sfx.artifact.rebound_sigil | sfx | placeholder |
| sfx.artifact.residue_crystal | sfx | placeholder |
| sfx.artifact.shatterheart | sfx | placeholder |
| sfx.artifact.split_prism | sfx | placeholder |
| sfx.artifact.stormglass | sfx | placeholder |
| sfx.artifact.tidewalkers_boots | sfx | placeholder |
| sfx.artifact.warding_lantern | sfx | placeholder |
| sfx.boss.death | sfx | placeholder |
| sfx.boss.drowned_archivist.phase | sfx | placeholder |
| sfx.boss.drowned_archivist.tele_a | sfx | placeholder |
| sfx.boss.drowned_archivist.tele_b | sfx | placeholder |
| sfx.boss.phase | sfx | placeholder |
| sfx.boss.tele_a | sfx | placeholder |
| sfx.boss.tele_b | sfx | placeholder |
| sfx.cast.cold | sfx | placeholder |
| sfx.cast.fire | sfx | placeholder |
| sfx.cast.force | sfx | placeholder |
| sfx.cast.lightning | sfx | placeholder |
| sfx.cast.neutral | sfx | placeholder |
| sfx.cast.rejected | sfx | placeholder |
| sfx.cast.water | sfx | placeholder |
| sfx.dash | sfx | placeholder |
| sfx.dash.iframe | sfx | placeholder |
| sfx.env.break | sfx | placeholder |
| sfx.env.burn_out | sfx | placeholder |
| sfx.env.freeze | sfx | placeholder |
| sfx.env.ignite | sfx | placeholder |
| sfx.env.thaw | sfx | placeholder |
| sfx.form.beam | sfx | placeholder |
| sfx.form.field | sfx | placeholder |
| sfx.hit.generic | sfx | placeholder |
| sfx.mod.chain | sfx | placeholder |
| sfx.mod.generic | sfx | placeholder |
| sfx.pickup.currency | sfx | placeholder |
| sfx.pickup.rune | sfx | placeholder |
| sfx.player.death | sfx | placeholder |
| sfx.player.hurt | sfx | placeholder |
| sfx.react.arc | sfx | placeholder |
| sfx.react.extinguish | sfx | placeholder |
| sfx.react.freeze | sfx | placeholder |
| sfx.react.shatter | sfx | placeholder |
| sfx.react.steam | sfx | placeholder |
| sfx.room.cleared | sfx | placeholder |
| sfx.tele.bone_thrall | sfx | placeholder |
| sfx.tele.cistern_slime | sfx | placeholder |
| sfx.tele.cistern_slimelet | sfx | placeholder |
| sfx.tele.corpse_bloat | sfx | placeholder |
| sfx.tele.deep_eel | sfx | placeholder |
| sfx.tele.drowned_acolyte | sfx | placeholder |
| sfx.tele.fallen_adept | sfx | placeholder |
| sfx.tele.grave_hound | sfx | placeholder |
| sfx.tele.lantern_wisp | sfx | placeholder |
| sfx.tele.ossuary_shieldbearer | sfx | placeholder |
| sfx.tele.rust_golem | sfx | placeholder |
| sfx.tele.storm_crystal | sfx | placeholder |
| sfx.tele.wailing_spirit | sfx | placeholder |
| sfx.trigger.on_expire | sfx | placeholder |
| sfx.trigger.on_hit | sfx | placeholder |
| sfx.trigger.on_kill | sfx | placeholder |
| sfx.trigger.timer | sfx | placeholder |
| ui.cancel | sfx | placeholder |
| ui.confirm | sfx | placeholder |
| ui.editor_error | sfx | placeholder |
| ui.hover | sfx | placeholder |
| ui.purchase | sfx | placeholder |
| ui.reward_pick | sfx | placeholder |

## Proposed QA limits (PROPOSED, not approved design)

- Formats: .wav, .ogg
- Sample rates: 32000, 44100, 48000 Hz (32 kHz is musicgen-small native; Godot resamples)
- Loudness peak: <= -1 dBFS
- Length: music 15-300 s; ambience 5-120 s; sfx 0.03-5 s; telegraph 0.1-1.5 s
- Loop (music, loop cues): seam jump <= 0.1 of full scale; loop end within 2048 frames of file end
- Ogg: peak and loop seam are not checked (no stdlib decoder)

