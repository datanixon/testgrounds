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
