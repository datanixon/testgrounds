# Wraithspire — Godot 4 Port Design

Date: 2026-06-10 · Branch: `godot-port` · Status: approved by user (design); spec under review

## Context & goal

Wraithspire is a complete, validated single-player hex-tactics game (Master of
Monsters lineage), built in two-file zero-dependency JS (`index.html` +
`game.js`, ~5500 lines) and frozen as the **reference implementation** at the
end of v2 Phase 1. Every combat rule, data table, and AI behavior is balanced
and playable there.

The user has decided to **port the proven game to Godot 4** ("path B"). The
motivation is visual: procedural canvas art is the ceiling, and the port exists
to replace it with real sprite art. The JS build stays as the playable
reference; **design carries over, code does not.**

This spec covers **port-to-parity only**: reproduce the current playable JS game
(v1 feature set + v2 Phase 1 — abilities, statuses, weather) in Godot 4 with real
art. ROADMAP2 Phases 2–8 (relics, fog, content wave, persistent campaign,
unlocks/records, roguelite gauntlet) are explicitly **out of scope here** and get
their own specs once parity lands and plays clean.

## Locked decisions

- **Engine:** Godot 4, latest stable 4.x, **.NET (Mono) build** from day one so
  C# is available the moment a hotspot appears.
- **Language:** **GDScript-first.** Write everything in GDScript. Zero C# until a
  profiler justifies it. The only plausible hotspot in turn-based tactics is AI
  move-scoring, so the AI scorer is isolated behind a clean interface as the
  designated C#-swap seam. No `.csproj` / C# code is created until then.
- **Art:** **AI-generated, hand-cleaned.** Monster art is faction-NEUTRAL,
  colored by element; the engine supplies team identity (a colored base-ring on
  the board token, a colored frame in the battle scene). The two Archons are
  bespoke per-faction (AZURE round-hat/crescent-staff vs CRIMSON
  spiked-hat/flame-staff, as in the JS reference). Two scales per creature: small
  board token + large battle portrait. The art brief lives alongside this spec;
  generation happens at the art milestone, placeholders until then.
- **Testing:** **`godot --headless` assert scripts.** Lightweight GDScript test
  scenes assert on the pure logic core. No third-party test framework. Mirrors
  the JS `smoke-test.sh` philosophy; green required before every commit.

## Keystone architecture — pure logic core + thin presentation

Game rules live in plain GDScript classes (`RefCounted`) with **zero `Node` /
render dependencies**. Combat resolution, pathfinding, and AI are pure (mirrors
how the JS `computeDamage` is already side-effect-free). Nodes read from the
logic core and render; they never own rules.

This single principle delivers three things at once:
- **Headless testability** — the core runs and asserts with no display.
- **C#-hotspot swap** — an isolated pure module can be reimplemented behind the
  same interface.
- **Art-layer swap** — placeholders → real sprites touches only the presentation
  layer, never the rules.

## Project structure

```
project.godot                 (.NET build)
/core        pure logic, no nodes — headless-testable
  hex.gd            axial math: neighbors, distance, axial<->pixel, rounding
  game_state.gd     single source of truth (mirrors JS STATE): board, units,
                    players, weather, turn, screen
  map_gen.gd        deterministic generation (seeded RNG)
  pathfinding.gd    computeReachable (Dijkstra), computeAttackTargets
  combat.gd         computeDamage (pure), beginBattle snapshot
  ai.gd             threat map + scored decision tree + summon economy
                    (C#-swap seam)
/data        balance-locked const-dict scripts — faithful ports of the JS tables
  elements.gd       ELEMENT, ELEM_MATRIX, ELEM_AFFINITY, AFFINITY_MULT
  unit_types.gd     UNIT_TYPES, SUMMON_LIST, MASTER_TEMPLATE, level/evolve rules
  abilities.gd      ABILITIES (all 12)
  statuses.gd       STATUS_META
  weather.gd        WEATHERS
  terrain.gd        TERRAIN
  maps.gd           MAPS (4 skirmish defs)
  campaign.gd       CAMPAIGN (4 missions)
  ai_profiles.gd    AI_PROFILES (difficulty knobs)
/scenes
  main.tscn/.gd     root router on GameState.screen
  title/            title screen
  match/            board (TileMapLayer) + units + overlays + camera + HUD
  battle/           cutaway cinematic scene
  gameover/         victory screen
/autoload
  audio.gd          SFX + music engine
/assets             generated sprites + audio — populated at the art milestone
/tests
  run_tests.gd      SceneTree entrypoint (godot --headless -s)
  test_*.gd         per-system assert scenes
```

## Logic core modules

- **hex.gd** — pointy-top axial coords `{q, r}`. Direct port of the JS hex math
  (`axialToPixel`, `pixelToAxial`, `roundAxial`, `hexNeighbors`, `hexDistance`).
  Storage key `"q,r"`.
- **game_state.gd** — holds the board (cells keyed by `"q,r"`), unit list,
  players, `weather`, `turn`, `current_player`, `screen`. Plain object owned by
  the root `Main` controller (NOT an autoload — so tests can instantiate isolated
  states). `screen ∈ {title, play, battle, gameover}` drives the router.
- **map_gen.gd** — ports `generateMap`: terrain mix, tower/castle placement,
  symmetry. Determinism via Godot's seeded `RandomNumberGenerator` (we need
  *Godot* reproducibility for tests, not byte-identical maps to JS, so we do not
  port `mulberry32`).
- **pathfinding.gd** — `computeReachable` (Dijkstra over move cost, reads
  `effectiveMove` so slow/weather apply), `computeAttackTargets`. Pure.
- **combat.gd** — `computeDamage` is pure (element matrix, terrain affinity,
  level growth, weather multiplier, ability modifiers — mark/bulwark/ward).
  `beginBattle` snapshots damage + counter-damage up front; HP is applied only at
  the battle scene's impact frames (the JS `applied1/applied2` sync discipline
  carries over verbatim). Damage-forecast reuses `computeDamage`, so the hover
  preview and AI inherit every modifier for free.
- **ai.gd** — buildThreatMap + scored decision tree
  (kill → retreat → instant ability → capture → attack → move) + summon-economy
  scoring + ability scoring (`aiScoreInstantAbility`). Returns intended actions;
  a turn-runner in the presentation layer executes them, awaiting battle
  animations between units (replaces the JS `setTimeout`-chain + battle-flag
  polling with a proper coroutine). This module is the designated C#-swap seam.

## Data layer

Tables port as **const dictionaries** — a faithful, diff-able translation of the
JS objects, so the balance-locked numbers can be verified line-for-line. A
per-table parity test asserts key sets and representative values match the
reference. Migration to `.tres` Resources (for editor tooling) is a possible
post-parity move, not part of this spec.

Carry-over set (verbatim numbers): `ELEMENT`/`ELEM_MATRIX`/`ELEM_AFFINITY`,
`UNIT_TYPES` (12 base + 8 evolved + archon template), `SUMMON_LIST`, level/XP
curve (`xpToNext`, `applyLevelGrowth`, `MAX_LEVEL=5`, `KILL_XP_BONUS=10`),
evolution rules (`EVOLVE_LEVEL=4`, tower/castle gate, level-bonus absorption),
`ABILITIES` (all 12), `STATUS_META`, `WEATHERS`, `TERRAIN`, `MAPS`, `CAMPAIGN`,
`AI_PROFILES`, faction palettes (AZURE/CRIMSON color/dark/trim).

## Presentation layer

- **Main (root router)** — swaps screen scenes on `GameState.screen`, same
  dispatch as the JS `render()` switch.
- **MatchScene**
  - Terrain via a hex **`TileMapLayer`** (Godot-native pointy-top), one tile per
    terrain type; the logical grid stays in `GameState`.
  - Units as `Sprite2D` nodes positioned by `hex.axial_to_pixel`, each reading
    its `GameState` unit record. Team identity via a colored base-ring node.
  - Highlights (reachable, attack rings, blink overlay) as a dedicated `_draw()`
    Node2D layer.
  - Real `Camera2D` (replaces the JS manual `STATE.cam` offset).
  - **HUD** as a `CanvasLayer` of **Control nodes**: topbar (turn / weather / MP),
    unit info card, post-move action menu (Attack / Ability / Capture / Wait,
    built dynamically from what's available at the tile), summon list. This
    replaces hand-laid-out canvas text — the single biggest quality win.
- **BattleScene** — the cutaway state machine
  (`intro → standoff → aCharge → aImpact → aRecover → cPause → cCharge →
  cImpact → cRecover → outro → done`) rebuilt with `Tween` / `AnimationPlayer`
  coroutines instead of a manual frame counter. Reads the `combat.begin_battle`
  snapshot; applies HP at impact frames only. Arena backdrop varies by the
  defender's terrain. Attack effects keyed off the unit's `attack` flavor
  (`melee` / `breath` / `spray` / `spark` / `dive` / `bolt`). Self-contained —
  fills the screen, does not render the map underneath.
- **Audio (autoload)** — ports the JS `beep()` SFX and the `musicTick` music
  engine (four-bar A-minor progression, square bass / triangle arp / sawtooth pad
  / sparse lead) to `AudioStreamPlayer` + a generated stream, with `musicDuck`
  during battle. **Open item:** real audio files are an optional post-parity
  polish pass; parity uses the ported procedural engine.

## Art pipeline

- Generate faction-NEUTRAL, element-colored art per creature (see the art
  brief). Team identity is engine-side: a team-colored base-ring on the board
  token and a team-colored frame in the battle scene. Archons are bespoke
  per-faction.
- Two scales: small board token, large battle portrait (the JS `drawMapSprite`
  vs `drawBattleSprite` split).
- Battle portraits face right; the engine mirrors for the defender.
- Pipeline: generate → hand-clean → slice → import (`Sprite2D`/`AnimatedSprite2D`)
  → assign per `typeKey`. This is its own late milestone; everything before it
  uses simple placeholder shapes so logic milestones never block on art.
- **Final faction-ID method** (engine base-ring/frame as specced vs an optional
  palette-swap shader) is confirmed at the art milestone once real sprites exist;
  neutral element-true art supports either, so the architecture is not blocked.

## Save / load

Port the JS versioned save blob to a JSON file at
`user://wraithspire_save.json` (versioned `v` field; loader defaults missing
fields). Parity blob carries: units (incl. `cd`, `status`, level/xp/evolved),
`weather`, board/seed, turn, players, captured towers. Campaign/records/gauntlet
get their own keyed files when those phases arrive.

Known JS save gap to optionally fix during this milestone (cheap improvement, not
required for parity): the JS reference does not serialize `STATE.mapDef`, so
resumed campaign saves fall back to the skirmish weather table — serializing the
map def fixes resumed-campaign weather.

## Carry-over fidelity & accepted gaps

The port preserves reference behavior. Combat-math parity is asserted in tests
(same inputs → same damage). The AI decision tree and summon economy port as
designed. Known accepted gaps in the reference, carried into the Godot design:
- Forecast/AI treat warded targets as killable (symmetric blindness) — preserved.
- `regen` status has no writer until relics (ROADMAP2 Phase 2, Godot side) —
  the mechanism exists, no source yet, as in the reference.

## Testing

`/tests/run_tests.gd` is a `SceneTree` script run via `godot --headless -s
tests/run_tests.gd`, with assert helpers. Coverage targets the pure core:
- combat damage parity (element matrix, affinity, level, weather, ability mods)
- pathfinding / reachable (move cost, slow, flyers, weather)
- AI decision outputs on constructed boards (kill > retreat > ability > capture
  > attack > move ordering; summon scoring)
- map-gen determinism (same seed → same layout; terrain-count and symmetry
  invariants)
- status/weather application and tick (burn, slow, mark/bulwark/ward ttl)

Visual verification stays manual/windowed (headless cannot render). Green
required before every commit, same protocol as the JS reference.

## Port order (milestones)

Each milestone is a verifiable, committable slice. Tag `[v2-godot] N: summary`,
verify (`node --check` equivalent: `godot --check-only` on changed scripts +
`godot --headless -s tests/run_tests.gd` green), commit, check off in a Godot
roadmap file.

1. **Skeleton + test harness + hex core** — project (.NET build), folder
   structure, `run_tests.gd` harness, `hex.gd` with passing asserts.
2. **Data tables + map gen** — port all `/data` const dicts + parity tests;
   `map_gen.gd` deterministic; render placeholder tiles on screen.
3. **Units + movement** — placement, `pathfinding.gd` reachable, selection,
   placeholder unit tokens with team rings.
4. **Combat + status + weather** — `combat.gd` with parity tests, attack flow,
   status engine, weather (logic + forecast). No cutaway yet (resolve inline).
5. **Abilities** — all 12, wired into combat/status/weather.
6. **AI** — `ai.gd` threat map + decision tree + summon economy; headless
   decision asserts + live AI turns.
7. **HUD / UI** — topbar, info card, post-move action menu, summon list as
   Control nodes.
8. **Battle cutaway** — `BattleScene` state machine via Tween/AnimationPlayer,
   reading combat snapshots; attack-flavor effects; terrain-varied arenas.
9. **Title + gameover + save/load + maps + campaign** — full loop closes;
   **parity reached.**
10. **Art + audio pass** — AI-gen sprite pipeline, swap placeholders → real art
    (board + battle), team-ID method finalized; audio pass.

Then ROADMAP2 Phases 2–8 are re-planned as Godot work, each with its own spec.

## Risks & open items

- **Godot install / version** — verify the .NET build of latest stable Godot 4.x
  is installed (or install) at milestone 1; pin the version in the roadmap.
- **Audio direction** — procedural-port now, real audio optional later (flagged
  above).
- **Faction-ID final method** — engine ring/frame vs palette-swap shader,
  decided at milestone 10 (architecture supports either).
- **Data as const-dict vs `.tres`** — const-dict for parity; Resource migration
  is a later, optional refactor.
- **AI turn-runner** — replacing the JS `setTimeout`-poll loop with coroutines is
  the one control-flow rewrite (not a straight port); covered by milestone 6
  with live AI-turn verification.

## Success criteria

A full skirmish and a campaign mission play with the same *feel* as the JS
reference: identical combat outcomes (parity tests green), the AI plays a
competent full turn, abilities/statuses/weather shift forecasts the same way,
battles cut away cinematically, and a match saves and resumes. Headless tests
green at every commit. Real generated art is swapped in over placeholders, no
regression in board/battle readability. No runtime errors.
```
