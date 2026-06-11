# SESSION STATE — pick up here

Last updated: 2026-06-10 (end of v2 Phase 1 session). Read this first in a
new session, then the linked docs as needed.

## Where the project stands

- **Wraithspire v1**: complete, merged, shippable (`ROADMAP.md` — all phases
  checked). Two-file zero-dep canvas game: `index.html` + `game.js`.
- **Wraithspire v2 Phase 1**: COMPLETE on `main` (this merge) — status
  effects, 12 unit abilities, ability-aware AI, weather. The JS build is now
  the **frozen reference implementation**: every combat rule, data table, and
  AI behavior is validated and playable here. Do NOT add JS features.
- **Engine decision (user, 2026-06-10)**: port to **Godot 4** ("path B").
  v2 Phases 2–8 (`ROADMAP2.md`) are NOT built in JS — they get re-planned
  as Godot work after the port reaches parity.

## Next session — start here

**UPDATE (2026-06-10): Port is UNDERWAY on branch `godot-port`. M1 + M2 + M3 COMPLETE**
— M1 skeleton + headless test harness + hex math core; M2 bit-exact Mulberry32 RNG
+ data tables (terrain/maps/campaign) + deterministic `generateMap` port (seed 7041
reproduces the JS c1 layout exactly) + placeholder hex render; M3 unit data table
(`unit_types.gd`: 20 types + SUMMON_LIST + MASTER_TEMPLATE), unit factories +
`GameState` (single source of truth + queries + `new_skirmish`), `pathfinding.gd`
(Dijkstra reachable + attack targets + path; pure, takes GameState; float costs for
the M4 modifier seam), and interactive placeholder tokens + click-to-select/move
(`scenes/match/units_layer.gd`, `overlay.gd`, rewritten `main.gd`). **139 tests green.**
Board interaction needs windowed visual confirmation (headless can't render).
**Next: M4 (combat resolution + status engine + weather — logic + forecast).** Resume with:
- `git checkout godot-port`
- Tests: `pwsh -ExecutionPolicy Bypass -File godot/tests/run_tests.ps1` (green = `== N passed, 0 failed ==`, EXIT 0). Windowed run of the actual game: `godot --path godot` (NOT `godot godot` — that opens the editor/project-manager, gray viewport, nothing playing).
- **HARNESS BLIND SPOT (cost an M3 bug):** `run_tests.gd` only loads scripts that declare `class_name` (global registry). Entry-point scene scripts like `scenes/main.gd` have NO `class_name`, so a parse error there passes the headless suite yet breaks the running game (gray screen). Catch it cheaply with a headless boot: `godot --headless --path godot --quit-after 30 2>&1 | Select-String "SCRIPT ERROR|Parse Error|Failed to load"` (clean = no matches, EXIT 0). Run this in addition to the suite whenever a no-`class_name` scene script changes. Consider folding it into `run_tests.ps1` in M4.
- Tracker: `ROADMAP_GODOT.md`. Docs: `docs/superpowers/specs/2026-06-10-wraithspire-godot-port-design.md` (+ `-art-brief.md`); plans `docs/superpowers/plans/2026-06-10-wraithspire-godot-m{1,2,3}-*.md`.
- Engine: standard Godot 4.6.3 build for the GDScript phase; Mono build + .NET 9 SDK retained for the C# hotspot (AI scorer). `godot`/`godot_console` PATH aliases point at the standard build.
- M4 needs its own plan (writing-plans, one per milestone); execution mode subagent-driven (implementer + spec + quality review per task) worked well for M3.
- M3 deferred to M4+ (data fields already carried): XP/level/evolve, combat (`computeDamage`), statuses, weather, turn flow (`endTurn` + MP regen + heals), AI. `effective_move` in `pathfinding.gd` is the documented seam where M4 adds slow/skitter/weather move modifiers. M3 has no `acted`/turn gate yet — any current-player unit can be reselected/re-moved freely.
- M4 coverage TODOs flagged by the M3 final review: test `reconstruct_path` for a destination NOT in reach (expect `[]`); test `compute_attack_targets` from a projected (post-move) tile ≠ the unit's own; add a direct `effective_move` test once it has modifier branches; test that a 0-HP blocker does not block pathing.

The original port-planning steps below are now historical (kept for reference):

1. `git checkout -b godot-port` (new branch off main, per user instruction).
2. Plan the Godot 4 port. Carry over DESIGN, not code:
   - `docs/superpowers/specs/2026-06-10-wraithspire-v2-design.md` — v2 spec
   - `ROADMAP2.md` — Phases 2–8 (deferred), Phase-1 milestone notes, decision
     log (engine decision), Session-1 handoff block
   - `game.js` data tables: `UNIT_TYPES`, `ELEM_MATRIX`, `ELEM_AFFINITY`,
     `ABILITIES`, `STATUS_META`, `WEATHERS`, `TERRAIN`, `MAPS`, `CAMPAIGN`,
     `AI_PROFILES` — these are the balance-validated numbers
   - AI architecture: threat map + scored decision tree (kill → retreat →
     instant ability → capture → attack → move), summon economy scoring
   - Port-order suggestion: hex core → map gen → units/combat → AI → UI →
     battle scenes → campaign → then ROADMAP2 Phases 2–8
3. Decisions to make early in port planning: GDScript vs C#; scene
   architecture; art direction (real sprites replace procedural — this was
   the motivation for the port); headless test strategy (`godot --headless`
   + GUT or custom asserts to replace `smoke-test.sh`).

## How to verify the JS reference (unchanged)

- Run: `start index.html`. Smoke: `bash smoke-test.sh` (mandatory green
  before any JS commit, should any maintenance be needed).
- Playwright probes: `python -m http.server 8765`, navigate with cache-bust
  `?v=N`, evaluate with BARE lexical names (`STATE`, not `window.STATE`).
  Hash hooks: `#autostart` `#demo` `#battle` `#gameover` `#smoke`.

## Known accepted gaps in the JS reference (carry into Godot design)

- Forecast/AI treat warded targets as killable (symmetric blindness).
- `regen` status has no writer until relics (v2 Phase 2 — Godot side now).
- Resumed campaign saves fall back to the skirmish weather table
  (`STATE.mapDef` not serialized).

## Process conventions that worked (keep for Godot)

- One milestone → verify → commit `[tag] N.N: summary` → check off in the
  roadmap file; handoff block at session end. Roadmap file = persistent state.
- Subagent loop for execution: implementer → spec-compliance review →
  code-quality review, with live behavioral probes for player-facing changes.
- User prefs: no API-key headless runs (subscription only, interactive
  sessions); overnight.sh is retired.
