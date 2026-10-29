# ArcaneDungeon — Documentation Index

Godot 4.7.1 stable (pinned) GL Compatibility M0–M3 playable prototypes are implemented for review: magic sandbox, combat arena, and linear dungeon → mini-boss → workshop → stage-two vertical slice. M4 TASK-049–053 automated validation/telemetry/onboarding is implemented; a first reference-inspired sprite, effects, environment and UI art pass is implemented; human playtesting and owner go/no-go remain absent.

| File | Purpose |
| --- | --- |
| [../AGENTS.md](../AGENTS.md) | Root instructions for coding, testing, changes, and visual work |
| [backlog_v1.md](backlog_v1.md) | Gameplay implementation proposal, TASK-001 through TASK-061, with dependencies and acceptance criteria |
| [art_direction.md](art_direction.md) | Mandatory process for reviewing the visual reference and generating future assets |
| [assets/art_style_reference.png](assets/art_style_reference.png) | Canonical local visual reference image; do not overwrite |
| [architecture/magic_contract_v1.md](architecture/magic_contract_v1.md) | Versioned prototype spell schema, interfaces, execution phases and owner decisions |
| [DEV.md](DEV.md) | Godot launch, engine pin, local validation and test commands |
| [M1_magic_sandbox.md](M1_magic_sandbox.md) | M1 controls, magic runtime architecture, reproduction recipes, rules, acceptance testing |
| [M2_combat.md](M2_combat.md) | M2 combat input, enemy behaviors, HUD, fixed scenarios, replay seed/metrics and open decisions |
| [M3_vertical_slice.md](M3_vertical_slice.md) | M3 run walkthrough, seeded rewards/rooms, mini-boss, shop, spell editor, safe testing, full-route regression |
| [M4_validation.md](M4_validation.md) | M4 code, regression/stress/telemetry commands, observability boundaries and deferred acceptance |
| [GDD_v1_conformance.md](GDD_v1_conformance.md) | GDD v1.0 rule → status (OK/GAP) → board row tracker for Round AD-R1 |
| [ART_IMPLEMENTATION.md](ART_IMPLEMENTATION.md) | First owner-reference-inspired pixel art pass: PNG sprites, Aseprite timelines, VFX and Godot integration. Contact sheet in art/previews/art_overview.png. |
| [playtests/M4_playtest_protocol.md](playtests/M4_playtest_protocol.md) | Human testing checklist, anonymous observation schema and offline report generation; **not performed** |
| [playtests/M4_decision_record.md](playtests/M4_decision_record.md) | Unresolved owner review/go-no-go and v2/POST gate; **pending** |

## External design documents

- [ArcaneDungeon living GDD](https://docs.google.com/document/d/1fYI_7zgrL-xbm4WV52z6mimLcU6s_N8HKZKPppVY6_0/edit) — authoritative owner design decisions.
- [Arcane World — Magic and World Interactions](https://docs.google.com/document/d/13l4Aqtsrp0f47Uuj-7BatHlrwJv7RlUCY2HO92KQCng/edit) — conceptual inspiration for elemental/semantic interactions.
- [Arcane World — World Knowledge](https://docs.google.com/document/d/1PSme3lsfFgC6T2nVckuKikEATj0A-CcFZodu8q1Ae4U/edit) — background/reference, not automatic feature scope.

## Current document rules

- The gameplay backlog is a proposal, not a record of all approved design decisions. Preserve its DECIDED/DIRECTION/PROPOSED/OPEN/OUT OF SCOPE distinctions.
- The first asset workstream is now implemented under art/source and assets/pixel; future art tasks must consult `assets/art_style_reference.png` and `art_direction.md`. Placeholder visuals are permitted for gameplay prototypes.
- Follow the milestone gates and task dependency graph in `backlog_v1.md`. M0 TASK-001–010 and the M1 TASK-011–025 sandbox prototype are now implemented for review. M2 TASK-026–035 is also implemented for review; M3 TASK-036–048 is implemented for technical review. M4 TASK-049–053 code and automation now exist, with owner-reference FPS signoff still open; M4 TASK-054 human sessions are deferred until sprites, TASK-055 approval pending. POST remains gated.
- Update this index as authoritative documentation is added; avoid listing proposed folders as though they exist.
