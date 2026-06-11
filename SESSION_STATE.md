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

**UPDATE (2026-06-10): Port is UNDERWAY on branch `godot-port`. M1 + M2 + M3 + M4 COMPLETE**
— M1 skeleton + headless harness + hex; M2 bit-exact Mulberry32 RNG + data tables
+ deterministic `generateMap` (seed 7041 = JS c1) + placeholder render; M3 unit data
(`unit_types.gd`), factories + `GameState` + `pathfinding.gd` (Dijkstra reachable/attack/path)
+ interactive tokens (click-select/move); M4 combat+status+weather, resolved INLINE
(no cutaway): `data/{elements,statuses,weather}.gd`; `core/status.gd` (add/has/tick),
`core/weather.gd` (now/roll, RNG-order faithful), `core/combat.gd` (pure deterministic
`compute_damage` base + `forecast_battle` + inline `resolve_attack` with counter/ward/jitter),
leveling+evolution in `core/units.gd`, turn machinery in `game_state.gd` (`end_turn`:
MP regen + status tick + tower/castle heals + evolve + weather roll; `check_win_condition`;
`capture_tower`), `effective_move` extended with slow/skitter/weather, and `main.gd` wired
(click-to-attack, capture-on-move, Enter→end_turn). **236 tests green; board verified by user.**
Determinism: ALL runtime randomness (combat ±1 jitter, weather roll) routes through
`GameState.rng` (seeded Mulberry32); `compute_damage` is pure (no rng).
**Next: M5 (all 12 abilities — wire into combat/status/weather).** Resume with:
- `git checkout godot-port`
- Tests: `pwsh -ExecutionPolicy Bypass -File godot/tests/run_tests.ps1` (green = `== N passed, 0 failed ==`, EXIT 0). Windowed run of the actual game: `godot --path godot` (NOT `godot godot` — that opens the editor/project-manager, gray viewport, nothing playing).
- **HARNESS BLIND SPOT (cost an M3 bug):** `run_tests.gd` only loads scripts that declare `class_name` (global registry). Entry-point scene scripts like `scenes/main.gd` have NO `class_name`, so a parse error there passes the headless suite yet breaks the running game (gray screen). Catch it cheaply with a headless boot: `godot --headless --path godot --quit-after 30 2>&1 | Select-String "SCRIPT ERROR|Parse Error|Failed to load"` (clean = no matches, EXIT 0). Run this in addition to the suite whenever a no-`class_name` scene script changes. Consider folding it into `run_tests.ps1` in M4.
- Tracker: `ROADMAP_GODOT.md`. Docs: `docs/superpowers/specs/2026-06-10-wraithspire-godot-port-design.md` (+ `-art-brief.md`); plans `docs/superpowers/plans/2026-06-10-wraithspire-godot-m{1,2,3,4}-*.md`.
- Engine: standard Godot 4.6.3 build for the GDScript phase; Mono build + .NET 9 SDK retained for the C# hotspot (AI scorer). `godot`/`godot_console` PATH aliases point at the standard build.
- M5 needs its own plan (writing-plans, one per milestone); execution mode subagent-driven (grinder implementer + general-purpose spec review + code-reviewer quality review per task) worked very well across M3 (4 tasks) and M4 (8 tasks). ALWAYS run BOTH gates after a `main.gd` change: the harness AND the headless boot (see blind-spot note above).
- **M4 → M5 handoff:** the status ENGINE (add/has/tick) + combat READS of mark/bulwark/ward/slow/skitter are done, but statuses have NO in-game WRITER yet — M5 abilities are the writers. `resolve_attack(state, attacker, defender)` has NO status-apply param yet; M5 adds the optional `apply_status`/`status_turns` path (JS `applySwing` `b.applyStatus`, game.js:2385). `ABILITIES` table + `STATUS_META` consumers, `aiScoreInstantAbility` (M6). `unit["cd"]` (cooldown) is decremented in `end_turn` but nothing sets it yet — abilities set it.
- **M4 accepted divergence from JS (record in design-doc parity gaps):** a WARDED defender whose primary swing is absorbed still COUNTERS if in range — `resolve_attack` checks post-swing `hp > 0`, whereas JS `beginBattle` pre-computes `willDie1` from raw damage ignoring ward and suppresses the counter. The Godot behavior is more intuitive; locked in by a `_test_resolve` assert. Only differs in the rare ward+would-die+in-range case.
- **M5/M6 coverage TODOs (flagged by the M4 final review):** add a compound-modifier combat assert (mark+bulwark+weather together) when abilities first stack statuses; assert `forecast_battle` counter band (`c_lo`/`c_hi`) when M6 AI consumes it; test `resolve_attack`→master-kill→`winner` as one integrated path; test the capture→`end_turn`→MP +2/tower regen interaction (only the 0-tower baseline is covered). Older still-open: `reconstruct_path` destination-not-in-reach → `[]`; `compute_attack_targets` from a projected post-move tile; 0-HP blocker doesn't block pathing.

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
