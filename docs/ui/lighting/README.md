# AD-165 — Lighting readability fix

Task AD-165, 2026-11-06. Base: `63b3faa` (origin/master, PR #9 merged). Franklin's playtest: the game was too dark; spell effects were excellent and are unchanged.

All values below are **[PROPOSED FOR PROTOTYPE]**, awaiting Franklin approval. They live in `world/data/lighting_v1.json` and are read by `ui/lighting.gd`.

## Files
- `before/`, `after/` — 1280x720 captures, `*_high.png` (Lighting: High) and `*_off.png` (Off), plus `matrix_combat.png` / `matrix_workshop_editor.png` from `tools/ui_matrix.sh`.
- `before_after_sheet.png` — before | after (High), one row per shot: 3 rooms per stage, both boss arenas, workshop, telegraph + spells.
- `off_sheet.png` — after, Lighting: Off (full-bright).

## Reproduce
```
xvfb-run -a -s '-screen 0 1280x720x24' /usr/local/bin/godot --path . --script res://tests/capture_ad165_lighting.gd -- docs/ui/lighting/after .
bash tools/ui_matrix.sh --godot /usr/local/bin/godot --sizes 1280x720 --states 'combat workshop_editor' --out "$TMPDIR/ad165_matrix_after"
python3 scripts/validate_godot.py --godot /usr/local/bin/godot
```

## Final values (ambient factor = 1 - energy*(1-colour))
| Stage | Ambient colour / energy | Torch (energy / tex scale) | Player light (energy / scale) | Extra |
|---|---|---|---|---|
| ruins | #e0d6c8 / 1.0 | 0.8 / 3.3 | 0.35 / 3.0 | — |
| ruins_boss | #ece4d8 / 1.0 | 0.8 / 3.3 | 0.35 / 3.0 | fill light 0.45 / 9.0 |
| cistern | #c8d6e4 / 1.0 | 0.8 / 3.3 | 0.35 / 3.0 | 4 fixed #7fd0ff lights 0.7 / 3.5 |
| cistern_boss | #dce6ee / 1.0 | 0.8 / 3.3 | 0.35 / 3.0 | fill light 0.45 / 9.0, 4 fixed lights |
| workshop | #ffffff / 0.0 | — | — | none |

Spell lights (all stages, unchanged from AD-148): projectile 0.9/0.8, orb 0.8/0.9, field 0.6/1.6, burst 1.2/1.6 (energy / scale).

## Readability rule
Floor tiles and enemy sprites must keep at least `readability.min_fraction` = **0.35** of their unlit brightness at the darkest sampled point of each room (sampled every `sample_step_px` = 32). The threshold is read from data and enforced by `tests/test_ad_lighting.gd`.

## Notes
- Spell VFX (`vfx_v1`) and spell-light values are unchanged; spell glow adds on top of a readable base.
- Settings Lighting: High / Low / Off still works; **Off is full-bright** (no ambient, no prop/player/spell lights).
- The workshop has no lighting: it is a full-bright sandbox canvas, so before and after are identical.
