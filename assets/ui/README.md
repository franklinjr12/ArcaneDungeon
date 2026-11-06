# Skin A UI assets (AD-152)

- Provenance: `ad_ui_kit*` = AD-095 kit (118 sprites); `layouts/` = AD-096 layout JSON as re-rendered by AD-159; `title/` = AD-098 title illustration (ruins set, parallax layers); `title/ad_key_logo.png` = AD-077 logo. Mock PNGs live in `docs/ui/matrix/mocks/`.
- All are game-art APPROVE FINAL. Palette: `arcane_palette_v02`.
- `*_glow.png` are additive (draw with additive blend over the base).
- The pause layout still names `ad_ui_modal_backdrop_25`; code must use `ad_ui_modal_backdrop_50` (game-art note). `SkinA.SPRITE_REMAP` does this.
- The title water strip is an AD-160 placeholder; AD-160 swaps it without any layout change.
- Loader: `ui/skin_a.gd`; Theme: `ui/pixel_theme.gd`.
