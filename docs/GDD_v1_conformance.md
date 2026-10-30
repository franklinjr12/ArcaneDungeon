# ArcaneDungeon — GDD v1.0 Conformance

This page tracks GDD v1.0 rules ([GDD v1.0](https://docs.google.com/document/d/1avYe5p8EdrisgYhG9JJ9yOqVBuDeO8SnYY-ea-9r4Bk)) and Tech Outline v1.0 ([Tech Outline v1.0](https://docs.google.com/document/d/1Wm-X9MuPwhjCWnSZWJe4ildROKbTXavh6EWgLgbafag)) against the current prototype for Round AD-R1 "Conform the prototype to GDD v1.0". The round AD-R1 conformance run (AD-031) closed the table: every row is OK or an owned GAP.


| GDD v1.0 rule | Current status | Board row |
| --- | --- | --- |
| 4 spell slots, slot 1 locked to a neutral basic bolt, starter presets in slots 2-3, slot 4 empty; input LMB/RMB/Q/E = slots 1-4 | OK | AD-011, AD-012, AD-013 |
| Dash replaces dodge (i-frames, wall-blocked); input map LMB/RMB/Q/E/Space/F/Esc | OK | AD-013 |
| HUD shows 4 slots + dash + mana | OK | AD-014 |
| Damage numbers white + element symbol | OK | AD-015 |
| Enemy roster names: bone thrall / fallen adept / grave hound / Undead warden | OK | AD-016 |
| 3 reward cards, each stating the new behavior | OK | AD-017 |
| Run summary + retry with same seed / new seed; no run resume | OK | AD-018 |
| Settings + local stats save | OK | AD-019 |
| AudioDirector + audio cues | OK | AD-020, AD-021 |
| Pangea flavour | OK | AD-022 |
| Workshop editor uses a 4-slot list | OK | AD-023 |
| Engine pinned to Godot 4.7.1 stable; checks run locally (no CI) | OK | AD-010 |
| Headless scripted route, seed 20261022, 4-slot starter loadout reaches slice complete (tests/test_ad_conformance.gd) | OK | AD-031 |
| Undead warden beatable by 2 builds (Fire; Water+Lightning), no single element required (GDD §4 step 4) (tests/test_ad_conformance.gd) | OK | AD-031 |
