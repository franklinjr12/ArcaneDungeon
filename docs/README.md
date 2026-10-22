# ArcaneDungeon — Documentation Index

Godot 4.7.2 GL Compatibility M0–M3 playable prototypes are implemented for review: magic sandbox, combat arena, and linear dungeon → mini-boss → workshop → stage-two vertical slice. Final art, production progression and M4 player validation remain absent.

| File | Purpose |
| --- | --- |
| [../AGENTS.md](../AGENTS.md) | Root instructions for coding, testing, changes, and visual work |
| [backlog_v1.md](backlog_v1.md) | Gameplay implementation proposal, TASK-001 through TASK-061, with dependencies and acceptance criteria |
| [art_direction.md](art_direction.md) | Mandatory process for reviewing the visual reference and generating future assets |
| [assets/art_style_reference.png](assets/art_style_reference.png) | Canonical local visual reference image; do not overwrite |
| [architecture/magic_contract_v1.md](architecture/magic_contract_v1.md) | Versioned prototype spell schema, interfaces, execution phases and owner decisions |
| [DEV.md](DEV.md) | Godot launch, clean validation, tests, and CI commands |
| [M1_magic_sandbox.md](M1_magic_sandbox.md) | M1 controls, magic runtime architecture, reproduction recipes, rules, acceptance testing |
| [M2_combat.md](M2_combat.md) | M2 combat input, enemy behaviors, HUD, fixed scenarios, replay seed/metrics and open decisions |
| [M3_vertical_slice.md](M3_vertical_slice.md) | M3 run walkthrough, seeded rewards/rooms, mini-boss, shop, spell editor, safe testing, full-route regression |

## External design documents

- [ArcaneDungeon living GDD](https://docs.google.com/document/d/1fYI_7zgrL-xbm4WV52z6mimLcU6s_N8HKZKPppVY6_0/edit) — authoritative owner design decisions.
- [Arcane World — Magic and World Interactions](https://docs.google.com/document/d/13l4Aqtsrp0f47Uuj-7BatHlrwJv7RlUCY2HO92KQCng/edit) — conceptual inspiration for elemental/semantic interactions.
- [Arcane World — World Knowledge](https://docs.google.com/document/d/1PSme3lsfFgC6T2nVckuKikEATj0A-CcFZodu8q1Ae4U/edit) — background/reference, not automatic feature scope.

## Current document rules

- The gameplay backlog is a proposal, not a record of all approved design decisions. Preserve its DECIDED/DIRECTION/PROPOSED/OPEN/OUT OF SCOPE distinctions.
- Final art production is a separate workstream; future art tasks must consult `assets/art_style_reference.png` and `art_direction.md`. Placeholder visuals are permitted for gameplay prototypes.
- Follow the milestone gates and task dependency graph in `backlog_v1.md`. M0 TASK-001–010 and the M1 TASK-011–025 sandbox prototype are now implemented for review. M2 TASK-026–035 is also implemented for review; M3 TASK-036–048 is implemented for technical review. M4 begins at TASK-049; real human playtests and gameplay go/no-go are still outstanding.
- Update this index as authoritative documentation is added; avoid listing proposed folders as though they exist.
