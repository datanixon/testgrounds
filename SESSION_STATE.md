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

**UPDATE (2026-06-11): Port is UNDERWAY on branch `godot-port`. M1–M8 COMPLETE**
— M1 skeleton + headless harness + hex; M2 Mulberry32 RNG + data + deterministic
`generateMap` (seed 7041 = JS c1) + render; M3 unit data + `GameState` + `pathfinding.gd`
(Dijkstra reachable/attack/path) + interactive tokens; M4 combat+status+weather INLINE
(`data/{elements,statuses,weather}.gd`, `core/{status,weather,combat}.gd` — pure deterministic
`compute_damage` + inline `resolve_attack`, leveling+evolution, turn machinery `end_turn`/
`check_win_condition`/`capture_tower`, `effective_move` modifiers); M5 ALL 12 ABILITIES:
`data/abilities.gd` (ABILITIES + `ability_for`, evolved cd-1 via `t.evolved`), `core/combat.gd`
`resolve_attack` gained optional `apply_status`/`status_turns` (the 5 enemy abilities —
ignite/cinderBreath/frostBite/undertow/diveMark, applied on surviving primary swing only),
`core/ability_resolve.gd` (`resolve_instant` for the 6 instants — heal/quake/skitter/galeRush/
bulwark/ward; `blink_targets`+`do_blink` for the 1 tile ability), `main.gd` wired (A = cast;
instant fires now, enemy/tile arm→click; `armed` state machine + `_finish_action`); M6 ENEMY AI
in new `core/ai.gd` (class AI — the C#-swap seam): `data/ai_profiles.gd` (AI_PROFILES + DIFFICULTIES)
+ `GameState.difficulty`, `weights`/`build_threat_map`/`find_summon_slot`/`score_instant_ability`/
`score_attacks` (PURE, probe-copy) / `decide_unit_action` (kill→retreat→instant→capture→attack→move)
/ `run_summons` (element/terrain/value scoring, bank vs flood) / `take_turn` (SYNCHRONOUS runner,
masters last), `main.gd` Enter wired to run the AI for player 1 then hand back.
AI hardcoded to player 1 (player/isAI table + difficulty-select UI = M9); M7 HUD/UI + presentation
refactor: pure `core/ui_queries.gd` (class UiQueries — `available_actions`/`summon_options`/
`can_capture`, harness-tested; HUD renders only what it returns), per-unit `UnitNode` (HP bar +
status pips) via a `UnitsLayer` manager, enhanced `overlay.gd` (reachable/attack/armed/selection),
Camera2D pan+zoom, a `CanvasLayer` HUD (`top_bar`/`info_card`/`action_menu`/`summon_list`), and the
real interaction state machine in `main.gd` (select→move→post-move action menu→Attack/Ability/
Capture/Summon/Undo/Wait; armed mis-click backs out to the menu; second-move skitter/galeRush leg;
`acted` enforcement); temp `D`/`T`/`A` debug keys retired. Board terrain stays a custom-hex Node2D
(NOT TileMapLayer — deliberate; M10 reskins). M8 BATTLE CUTAWAY, **resolve-then-replay** (NOT the
JS apply-at-impact, and NOT a coroutine in core — user chose this): `Combat.resolve_attack` keeps its
exact resolution + RNG order and APPENDS a plain-data snapshot to `GameState.battle_log` (harness-
asserted record); `main.gd` drains the log and `await`s a self-contained `BattleScene` cutaway per
record after a human attack (`_resolve_armed`) and after the AI turn (`_on_end_turn`→`AI.take_turn`,
which stays SYNCHRONOUS — `core/ai.gd` untouched, seam intact). `scenes/battle/{battle_scene,
battle_sprites,battle_fx}.gd`: phase machine (pure `next_phase`, tested) + ported `drawBattleSprite`
portraits + `drawAttackEffect`(6 flavors)/`drawArenaBackground`(7 terrains) + damage popups + HP bars
+ letterbox/shake/flash. Human-only move-slide (tween before menu); `_busy` blocks board input AND
`_on_end_turn` during cutaways/slides. M7 polish folded in (dead `overlay.set_attack` removed; info_card
self-buff refresh; menu clamp uses real panel size). **396 tests green; both gates verified; final opus
review = SHIP** (one re-entrancy fix: `_busy` guard on `_on_end_turn`).
Determinism unchanged (normal/hard zero-RNG; only easy draws `state.rng`; `compute_damage` pure).
**Accepted M8 divergences:** board updates under the cutaway (not at impact frames); AI movement not
animated (only battles replay).

**UPDATE (2026-06-11): M9 COMPLETE — PARITY REACHED.** The Godot port now matches the JS reference.
M9 = Router + Session split: thin `scenes/main.gd` router swaps screen scenes on `session.screen`
(title/campaign/story/play/gameover); the old match controller moved verbatim to `scenes/match/
match_scene.gd` (class MatchScene; `init(state,session)`; AI branch reads `state.is_ai[current_player]`
not the old `==1` hardcode; autosave at end-of-turn; battle-scene toggle skips the cutaway; one-shot
`_end_match` emits `match_ended`). New `core/session.gd` (class Session) = app state (screen/settings/
difficulty/map_index/campaign_progress/story_index/has_save) + `start_skirmish`/`start_campaign`/
`on_match_won`(progression, capped non-regressing, persists+deletes save)/`return_to_title`. New
`core/save_game.gd` (pure `to_dict`/`from_dict` round-trip harness-tested + `user://wraithspire_save.json`
I/O; **map_def serialized** — closes the JS resumed-campaign-weather gap; **JSON int→float re-coercion**
in from_dict is load-bearing — without it `stats["lost"][owner]` crashes on first resumed battle).
New `core/settings_store.gd` (`user://wraithspire_settings.json`; merge type/range-validates; campaign_progress
clamped). New `data/palette.gd` (Pal chrome colors). Five procedural screens ported 1:1 from the JS render
fns (`scenes/{title,campaign,story,gameover}/*.gd`): synthwave title w/ map+difficulty+campaign+continue,
campaign mission list (unlock by progress), story intro (fade-in), gameover (winner banner + stats summary
+ campaign verdict). Settings overlay (`scenes/hud/settings_panel.gd`) + gear button in top_bar (music/sfx
vol persisted but INERT until M10 audio; battle-scene toggle LIVE). Match stats (`summoned`/`lost`/`battles`)
added to GameState for the gameover summary. **453 tests green; both gates verified per task; whole-milestone
opus review = end-to-end SOUND.** KEY GOTCHA learned: Control screens need keyboard (Enter/ESC) handled in
`_unhandled_input`, NOT `_gui_input` (which only fires keys when the Control has focus); mouse stays in
`_gui_input`. **Accepted M9 divergences:** music/sfx sliders inert until M10; `lost` stat counts combat
deaths only (AoE-ability kills uncounted); `map_def` serialized (improvement over JS); resume-mid-AI-turn
re-kick (JS loadGame) intentionally omitted — autosave only fires after the AI's synchronous turn hands
back, so saves always capture the human's turn.
**REMAINING MANUAL STEP:** windowed full-loop visual verification (`godot --path godot`) — headless can't
render. Checklist: title→pick map/difficulty→skirmish→win→gameover→title (no CONTINUE); end a turn→quit→
relaunch→CONTINUE resumes; CAMPAIGN→mission 1→story→play→win→mission 2 unlocked; gear→toggle BATTLE SCENE
OFF→battle resolves instantly. **Next: M10 (art + audio — real sprites swap in; wire music/sfx settings).**
After M10, ROADMAP2 Phases 2–8 get their own post-parity specs.

**UPDATE (2026-06-11): M10 split into AUDIO + ART. AUDIO COMPLETE** on branch
`godot-m10-art-audio` (off main @ df06f61). Decomposed because art needs 44 generated sprite
PNGs (asset dependency, unlike any code milestone) while audio is pure code. M10 Audio = port of
the JS Web-Audio synth (game.js sec.15) using generated waveform streams + native Godot bus FX:
pure `data/tracks.gd` (6 TRACKS verbatim) + `core/music_seq.gd` (`events_for_step` reproducing
`musicTick`'s note selection + `gen_wave`, harness-tested), `autoload/audio.gd` (Audio singleton:
Music/SFX buses w/ AudioEffectReverb+LowPass, generated AudioStreamWAV waveforms, 24+8
AudioStreamPlayer voice pool w/ Tween envelopes + per-player kill-before-reuse, Timer(0.17s)
sequencer, beep/fanfare/duck/cycle_track/set_*_vol/apply_settings), registered in project.godot.
Wired the inert M9 vol settings + added MUSIC ON/OFF + TRACK cycler to the settings overlay;
battle cutaway ducks music; per-event SFX (summon/attack/capture/ability/win-fanfare/menu).
`SettingsStore` gained `music_on`/`track_index`. **761 tests green; both gates per task;
whole-milestone opus review = end-to-end SOUND.** KEY GOTCHA: a harness `--script` run does NOT
load autoloads, so any script FORCE-PRELOADED by run_tests.gd (only `board.gd` + `battle_scene.gd`)
must reach the autoload via `get_node_or_null("/root/Audio")`, NOT bare `Audio.` (which fails parse);
class_name scenes that are only lazily registered (match/title/settings) use bare `Audio.` fine.
Accepted divergences: native reverb (not the JS delay network); single-bus reverb send; approximated
bass filter-sweep + drums; seeded noise; desktop autostart (no browser gesture gate); UI-click SFX
unified to 0.06/0.15 (JS settings click was 0.12/0.18); level-up/evolve chime DEFERRED (no level-up
signal exists yet — carry-forward). **REMAINING:** windowed AUDIBLE verification (`godot --path godot`)
— headless has only a dummy audio driver. Then the only remaining port work is **M10 ART** (generate
44 sprites from `docs/superpowers/specs/2026-06-10-wraithspire-art-brief.md`, then a short engine
integration behind the fixed `battle_sprites`/board-token signatures + team ring/frame + faction-ID
method) — its own spec+plan when assets exist. After that, ROADMAP2 Phases 2–8 get post-parity specs.

>>> PICK UP HERE (M10 windowed audible check, then M10 ART — needs sprite assets first) <<<
Previous handoff (M9, historical):
- **Tracker:** `ROADMAP_GODOT.md` — M1–M8 ✅; next `- [ ] M9 — ...`. M9 needs its own spec (brainstorming) + plan (writing-plans). M9 is the PARITY-completing milestone (after it the port matches the JS reference; ROADMAP2 Phases 2–8 then get their own specs).
- **M9 scope (port the JS sec. 5/13/14 + save blob):** the `screen` router (title/play/battle/gameover — `GameState` is currently always in "play"); title screen (synthwave sun + perspective grid, "new game"/difficulty pick) + gameover screen (archon silhouette, victory); the **difficulty-select UI** + the **player/isAI table** (M6 hardcoded AI to player 1 — generalize here: `GameState.difficulty` already exists; add per-player isAI so `_on_end_turn` reads the table instead of `current_player == 1`); **save/load** to `user://wraithspire_save.json` (versioned blob: units incl. cd/status/level/xp/evolved, weather, board/seed, turn, players, captured towers — design spec "Save / load"; optionally serialize `map_def` to fix the JS resumed-campaign-weather gap); **campaign** (CAMPAIGN data already ported in `data/campaign.gd`; scenario list + progression). Also the **battle-scene on/off setting** (JS `STATE.settings.battleScene`) deferred from M8 — a settings toggle that skips the cutaway.
- **Carry-forwards/notes:** M6 AI is hardcoded to player 1 in `main.gd` `_on_end_turn` — M9 replaces that with the player/isAI table. `GameState.difficulty` defaults "normal"; the title difficulty pick sets it. M8 left no polish debt (the 3 M7 items were folded in).
- **Execution mode (proven across M3–M8):** subagent-driven — per task: `grinder` implementer (model sonnet) with verbatim steps; then a spec reviewer (`general-purpose`) + a quality reviewer (`feature-dev:code-reviewer`, or `caveman:cavecrew-reviewer` for tiny diffs). Apply fixes via the SAME implementer (SendMessage to its agentId) + `git commit --amend`. After all tasks, one final whole-milestone review (opus over `git diff <base> <final>`). Invoke `superpowers:subagent-driven-development`.
- **Gates:** harness `pwsh -File godot/tests/run_tests.ps1` (`== N passed, 0 failed ==`, EXIT 0) after every task; `-ExecutionPolicy Bypass` is BLOCKED by the classifier — use plain `pwsh -File`. AND the headless boot after ANY scene/`main.gd` change: `godot --headless --path godot --quit-after 30 2>&1 | Select-String "SCRIPT ERROR|Parse Error|Failed to load"` (clean = no matches). Save/load logic (pure-ish) is harness-testable — assert round-trip serialize/deserialize.

Original resume steps (still valid):
- `git checkout godot-port`
- Tests: `pwsh -ExecutionPolicy Bypass -File godot/tests/run_tests.ps1` (green = `== N passed, 0 failed ==`, EXIT 0). Windowed run of the actual game: `godot --path godot` (NOT `godot godot` — that opens the editor/project-manager, gray viewport, nothing playing).
- **HARNESS BLIND SPOT (cost an M3 bug):** `run_tests.gd` only loads scripts that declare `class_name` (global registry). Entry-point scene scripts like `scenes/main.gd` have NO `class_name`, so a parse error there passes the headless suite yet breaks the running game (gray screen). Catch it cheaply with a headless boot: `godot --headless --path godot --quit-after 30 2>&1 | Select-String "SCRIPT ERROR|Parse Error|Failed to load"` (clean = no matches, EXIT 0). Run this in addition to the suite whenever a no-`class_name` scene script changes. Consider folding it into `run_tests.ps1` in M4.
- Tracker: `ROADMAP_GODOT.md`. Docs: `docs/superpowers/specs/2026-06-10-wraithspire-godot-port-design.md` (+ `-art-brief.md`); plans `docs/superpowers/plans/2026-06-1{0,1}-wraithspire-godot-m{1..6}-*.md` (M6 = the 2026-06-11 file).
- Engine: standard Godot 4.6.3 build for the GDScript phase; Mono build + .NET 9 SDK retained for the C# hotspot (AI scorer — M6 is where it may finally matter). `godot`/`godot_console` PATH aliases point at the standard build.
- M6 plan is DONE (see the EXECUTE block above); execution mode subagent-driven (grinder implementer + general-purpose spec review + code-reviewer quality review per task) worked very well across M3 (4 tasks), M4 (8 tasks), M5 (5 tasks). ALWAYS run BOTH gates after a `main.gd` change: the harness AND the headless boot (see blind-spot note above). After M6: M7 (HUD/menu + summoning UI), M8 (battle cutaway — the AI runner becomes a coroutine here), M9 (title+gameover+save+campaign = parity), M10 (art+audio).
- **M5 → M6 handoff:** all 12 abilities resolve (`ability_for` + `resolve_instant`/`resolve_attack`-status/`blink`). M6 ports `aiTakeTurn` + the scored decision tree (kill → retreat → instant ability → capture → attack → move) + threat map + summon economy + `aiScoreInstantAbility` (game.js ~1140–1410, 5822). The AI is the designated **C#-swap seam** — keep it behind a clean pure interface (it already can be: it reads `GameState` + the pure queries). The JS `setTimeout`-chain + battle-flag polling becomes a coroutine/turn-runner in the presentation layer (the one control-flow REWRITE, not a straight port — design spec "Risks"). `ai_profiles.gd` (AI_PROFILES difficulty knobs) ports here too. `unit["cd"]` is set by abilities (M5) and decremented in `end_turn`; the AI must respect `cd > 0` (the `aiScoreInstantAbility` guard already does).
- **M4 accepted divergence from JS (still open — record in design-doc parity gaps):** a WARDED defender whose primary swing is absorbed still COUNTERS if in range — `resolve_attack` checks post-swing `hp > 0`, whereas JS `beginBattle` pre-computes `willDie1` ignoring ward and suppresses the counter. Godot behavior is more intuitive; locked by a `_test_resolve` assert.
- **M7 carry-forwards (from M5):** (1) the M4 temp debug keys in `main.gd` (`D`=spawn combat, `T`=goto tower) + the minimal `A`=cast keybind are placeholders — replace with the action menu + summon list. (2) Re-introduce the JS "ability mis-click backs out to the post-move menu without freeing the unit" exploit-fix (game.js 4276–4283) — M5 simplified it to a plain deselect (`main.gd _resolve_armed` miss path). (3) Add `acted`/second-move-leg gating: `second_move` is set by skitter/galeRush but only consumed via `effective_move`'s `skitterBoost +2` today; the "take a second move-only action" UX is M7.
- **Test coverage TODOs (carried + new from M5 review):** end-to-end "enemy-ability status through a board cast" (the `ability_for→main.gd→resolve_attack` seam is only read-verified — `main.gd` has no class_name so it's harness-invisible; add once M7 gives a testable cast entry point); evolved-cd behaviorally through a cast; the other 4 enemy abilities individually (only ignite→burn is asserted, same code path). Older still-open: compound-modifier combat (mark+bulwark+weather); `forecast_battle` counter band (`c_lo`/`c_hi`, M6 AI consumes it); `resolve_attack`→master-kill→`winner` integrated; capture→`end_turn`→MP +2/tower regen; `reconstruct_path` destination-not-in-reach → `[]`; `compute_attack_targets` from a projected post-move tile; 0-HP blocker doesn't block pathing.

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
