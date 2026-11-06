# Artifacts (AD-143)

Run-long passive items (Demo Plan section 11). **All numbers are PROPOSED** and get tuned after a full-run pass; none is approved design.

## Data
`world/data/artifacts_v1.json` holds `max_held` (6), the three source knobs (`reward_artifact_chance`, `treasure_artifact_cards`, `merchant_artifact_price`) and the 12 artifacts. Each has `name_key`/`desc_key` (text goes through `tr()`), `rarity`, `hooks` and `params`. Effects read every number through `Artifacts.param(id, key)`; nothing is hard-coded.

`world/artifacts.gd` is the runtime holder (`has`, `param`, `add`, per-room `state`). It is saved in `RunState` (optional field, old saves still load) and rebuilt for each room sim by `RunFlow._attach_artifacts`.

## Hooks
With no holder (null) or an empty one the simulation takes no artifact branch: traces, id allocation and RNG are identical.

| Hook | Artifacts | Where |
|---|---|---|
| on cast | Momentum Rune, Echo Chamber, Split Prism, Residue Crystal | `SpellRunner.try_cast`, `_spawn_root`, `_spawn_burst` |
| on hit | Rebound Sigil, Stormglass, Gravity Lens | projectile bounce, arcs (`_react`), orb hits |
| on kill | Shatterheart, Ember Heart | `SpellRunner._on_target_died` (once per target, before status is cleared; called from direct hits, DOT and arcs). Shatterheart's blast is a depth-1 burst flagged `artifact_kill`, so it cannot trigger more on-kill artifacts |
| on HP threshold | Archivist's Quill | `_quill_crossed`: each `threshold` fraction of a boss/mini-boss max HP lost fires the hit's On Kill trigger once, without a kill |
| on dash | Momentum Rune, Tidewalker's Boots | `PlayerCombat` calls `artifact_dash` / `artifact_dash_step`; trail points make enemies Wet in `advance_one_tick`; the `wet_trail` visual is draw-only |
| on room clear | Warding Lantern | `RunFlow._finish_combat` sets `player.shield`; `CombatSession.damage_player` returns `SHIELDED` and consumes one charge; the charge carries into the next room |

## Sources
- Reward cards: a card may be an artifact (`reward_artifact_chance`).
- Merchant: one artifact for `merchant_artifact_price`.
- Treasure room: `treasure_artifact_cards` artifact cards.
Held artifacts are never offered again; nothing is offered once `max_held` is reached.

## Tests
`tests/test_ad_artifacts.gd` has at least one test per artifact and a check that its hard-coded id list matches the data keys, so a new artifact fails the suite until it gets a test.

## AD-144 merchant v2
- Stock order: 1-2 runes (`rune_count_min/max`), upgrades `upgrade.hp`, `upgrade.mana`, `upgrade.dash` (stat `max_hp` / `max_mana` / `dash_charge`), then one artifact.
- Data (`world/data/run_v2.json` `merchant`): `rune_price`, `max_hp_upgrade_price/amount`, `max_mana_upgrade_price/amount`, `dash_charge_upgrade_price/amount`, `merchant_artifact_price`, `rune_count_min/max`, `rune_count_salt`, `seed_salt`, `reroll_price`, `reroll_salt`.
- Reroll: once per visit; the marker `reroll@<sequence_index>` is stored in `RunState.purchases`, so a restore rebuilds the same rerolled stock.
- All prices and amounts are proposed placeholders pending playtesting.
