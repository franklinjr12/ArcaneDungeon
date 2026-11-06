# Skin A UI assets (AD-152)

- Provenance: `ad_ui_kit*` = AD-095 kit (118 sprites); `layouts/` = AD-096 layout JSON as re-rendered by AD-159; `title/` = AD-098 title illustration (ruins set, parallax layers); `title/ad_key_logo.png` = AD-077 logo. Mock PNGs live in `docs/ui/matrix/mocks/`.
- All are game-art APPROVE FINAL. Palette: `arcane_palette_v02`.
- `*_glow.png` are additive (draw with additive blend over the base).
- The pause layout still names `ad_ui_modal_backdrop_25`; code must use `ad_ui_modal_backdrop_50` (game-art note). `SkinA.SPRITE_REMAP` does this.
- The title water strip is an AD-160 placeholder; AD-160 swaps it without any layout change.
- Loader: `ui/skin_a.gd`; Theme: `ui/pixel_theme.gd`.

## AD-153 additions
- `layouts/` in-run screens (hud, loadout = AD-096; reward, merchant, editor, compendium_*, summary_* = AD-097), copied from AD-159 export (layouts unchanged by AD-159). Mocks `_1x/_2x` in `docs/ui/matrix/mocks/`.
- `icons/` = AD-123 demo atlas (AD-110 rune/status atlas + reroll, hp_up, mana_up, dash_up, undiscovered, merchant glow) plus AD-110 glow. Index: `ad_ico_atlas_demo_index.json`; helpers `SkinA.icon/has_icon`.
