# Wraithspire — Fog of War (ROADMAP2 Phase 3) — design

Date: 2026-06-13. Branch: `godot-p3-fog` (off `main`). Covers roadmap items
**3.1** (visibility engine) and **3.2** (fair-AI fog + Veilstone + flagged maps +
cutaway reveal) as one coupled spec. Godot port; the JS build at repo root is the
frozen reference and is **not** touched.

## Goal

Master-of-Monsters–style fog: **terrain is always visible**; enemy units are
hidden unless inside your vision. Vision is the union over your units (radius 3
ground, 4 flying) plus your owned spires/citadel (radius 2). The AI plays **fair**
— its threat map and target selection see only what it could see. Off by default
on skirmish (title toggle) and on the test/smoke path; opt-in per map def.

## Decisions (locked)

- **Live reveal during the AI turn** — the viewer's vision recomputes as the AI
  moves, so enemies pop in/out of fog in real time (consistent with cutaway reveal).
- **Veilstone spawns from the random relic POOL** like the Phase-2 relics (inert
  when fog is off).
- **Ambush reveal** — after an AI battle launched from a tile the viewer can't see,
  the attacker's tile is added to the viewer's visibility for the rest of the turn.

## Architecture

### 1. `core/vision.gd` — new pure module (`class_name Vision`)

Mirrors the `relics.gd` / `combat.gd` pure-helper pattern: no nodes, harness-testable.

```
const GROUND_SIGHT := 3
const FLY_SIGHT := 4
const SPIRE_SIGHT := 2

# Vision radius for one unit, including a Veilstone bonus.
static func unit_sight(unit) -> int:
    var base := FLY_SIGHT if unit["flying"] else GROUND_SIGHT
    return base + int(Relics.unit_bonus(unit, "vision"))

# Set of visible "q,r" keys for `owner`. Union of:
#   - every alive unit of `owner`: all in-bounds cells within unit_sight (Hex.distance)
#   - every tower/castle cell owned by `owner`: all in-bounds cells within SPIRE_SIGHT
# Returns Dictionary used as a set ({key: true}). Pure; reads state.map + state.units.
static func compute(state, owner: int) -> Dictionary
```

- Radius is plain `Hex.distance` — **no line-of-sight blocking** (matches MoM and
  the design doc). Only in-bounds cells (`state.in_bounds`) are added.
- "Owned spires/citadel" = cells whose `terrain` is `"tower"` or `"castle"` and
  whose `owner == owner` (same convention as `_owned_tower_count`).
- No radius-gather helper exists in `hex.gd`; `compute` iterates candidate cells
  via a bounded `Hex.distance` scan around each source (q±R, r±R box, distance ≤ R).

### 2. `GameState` state additions (`core/game_state.gd`)

- `var fog: bool = false` — whether this match uses fog. **Saved.**
- `var visibility: Dictionary = {}` — cached visible-key set for the current
  *viewer* (the human side). **Not saved** — recomputed on load and on each event.
- `func recompute_visibility(owner: int) -> void` — `visibility = Vision.compute(self, owner)` (no-op semantics are fine; callers decide owner). Called by the
  presentation layer, not by `end_turn` (keeps `end_turn` logic-pure).
- `new_skirmish` / `new_campaign` set `fog` from their caller (see §6). `fog` is
  passed into `new_skirmish` as a param defaulting `false` so existing call sites
  and tests stay fog-off.

### 3. Fair AI (`core/ai.gd`) — filter threaded through, seam intact

`ai.gd` stays pure and keeps `class_name AI` with **no** GameState preload.

- `take_turn(state, owner)`: at entry compute the AI's own view once —
  `var vis = Vision.compute(state, owner) if state.fog else {}` — and a sentinel
  meaning "see all" when fog is off. Pass `vis` (and a `fog` bool) down.
- `build_threat_map(state, owner, vis, fog)`: the enemy loop
  `for e in state.alive_units(1 - owner):` gains `if fog and not vis.has(Hex.key(Vector2i(e["q"], e["r"]))): continue`.
- `run_summons` enemy enumeration (`state.alive_units(1 - owner)` for composition
  scoring) gets the same guard — the AI can't scout your army through summon choice.
- `score_attacks` target resolution: filter resolved enemy tiles the same way
  (attack range ≤ 2 ≤ sight 3, so adjacent enemies are inherently visible; filter
  for correctness/symmetry anyway).
- When `fog` is off, every guard is skipped → byte-for-byte current behavior
  (determinism preserved; existing AI tests unchanged).

### 4. Rendering

- **`scenes/match/overlay.gd`**: add `var fogged: Dictionary` and a `_fill(fogged,
  <dark translucent>)` pass, drawn only when fog is active. `match_scene` sets it
  from `state` (in-bounds cells minus `state.visibility`). Drawn beneath the
  reachable/armed/selection fills so those stay legible.
- **`scenes/match/units_layer.gd` `_rebuild`**: before adding a `UnitNode`, if
  `state.fog` and the unit's `owner != viewer` and its tile key ∉ `state.visibility`,
  skip it. The viewer's own units always render. (Gating lives here; `unit_node.gd`
  unchanged.)
- The "viewer" is the human side — `viewer = state.is_ai.find(false)` (the
  non-AI player; player 0 in skirmish/campaign). Compute once in `match_scene`.

### 5. `match_scene.gd` — recompute timing + cutaway reveal

- On match start, on `_on_end_turn` (after `state.end_turn()`, before the AI runs),
  and after every human move / summon / death: call
  `state.recompute_visibility(viewer)`, then refresh the fog overlay + rebuild the
  units layer. This is the "recomputed on move/summon/death" requirement and the
  **live reveal**: during `AI.take_turn` the synchronous runner already mutates
  `state`; after it returns (and at each cutaway) we recompute so enemies that
  ended inside your vision appear.
- **Hover / info-card / forecast gating**: when resolving the unit under the cursor
  for the hover card or forecast, if `state.fog` and that unit is an enemy whose
  tile ∉ `state.visibility`, treat the tile as empty (no card, no forecast).
  Applies at the `match_scene` hover site and any `ui_queries` target lookup that
  feeds player-facing forecast (not the AI path).
- **Cutaway reveal (ambush)**: in the `_play_battles` drain, for each battle record
  whose attacker tile ∉ the viewer's pre-battle visibility, after `await
  battle_scene.finished` add that attacker tile key to `state.visibility` (persists
  until the next recompute, i.e. rest of the turn) and refresh units/overlay so the
  attacker stays shown.

### 6. Toggle, map defs, save

- **Title toggle** (`scenes/title/title_scene.gd`): a FOG `ON/OFF` control beside
  the map/difficulty pick, wired to `session.settings["fog"]`. `start_skirmish`
  reads it into `GameState.fog`. Default **off**.
- **`core/settings_store.gd`**: `defaults()` gains `"fog": false`; `merge()` gains a
  `TYPE_BOOL` validation block (same shape as `battle_scene`).
- **Map defs** (`data/maps.gd`, `data/campaign.gd`): optional `"fog": true`. Skirmish
  `fog` = title toggle OR `map_def.fog`; campaign `fog` = `scenario.map.fog`. At
  least one campaign mission gets flagged to exercise the path; new fog-default
  skirmish maps are Phase 4 scope, not here.
- **`core/save_game.gd`**: `to_dict` writes `"fog": state.fog`; `from_dict` reads it
  (default `false` for old saves). `visibility` is **not** saved — `match_scene`
  recomputes it when the resumed match mounts.

### 7. Veilstone relic (`data/relics.gd`)

- Add `"veilstone": {"name": "Veilstone", "kind": "passive", "glyph": "E",
  "color": <dim blue>, "vision": 1}` (glyph/color final-picked during impl; avoid
  clashing with existing glyphs A/V/S/F/R/T/P/W/L).
- Add `"veilstone"` to `POOL`.
- Move the "(Veilstone -> Phase 3.)" header comment — it now lives here.
- `Vision.unit_sight` already reads `Relics.unit_bonus(unit, "vision")`; no other
  combat/stat seam changes (vision is not a combat stat).

## Data-model deltas

| Where | Field | Notes |
|---|---|---|
| `GameState` | `fog: bool` | saved; default false |
| `GameState` | `visibility: Dictionary` | render cache; not saved |
| `Session.settings` | `"fog": bool` | persisted; default false |
| map/campaign defs | `"fog": true` (optional) | per-map opt-in |
| `unit.relic` | `"veilstone"` | +1 vision via existing relic seam |

## Testing (harness-first, TDD)

Pure logic is fully harness-testable (`pwsh -File godot/tests/run_tests.ps1`):

- `Vision.compute`: a lone ground unit sees radius 3 and not 4; a flyer sees 4; a
  Veilstone holder sees +1; an owned tower contributes radius 2; an **unowned**
  tower contributes nothing; the set is a union (overlaps don't double-count);
  off-board cells excluded.
- `Vision.unit_sight`: ground 3 / fly 4 / +Veilstone.
- Fair AI: with `fog` on, `build_threat_map` ignores an enemy outside the AI's
  vision and counts one just inside it; with `fog` off, output identical to a
  pre-fog baseline (regression guard for determinism).
- Save round-trip: `to_dict`/`from_dict` preserves `fog`; an old blob without
  `fog` loads as `false`.
- Relics: `unit_bonus(veilstone_unit, "vision") == 1`; `POOL` contains it.

Headless boot gate after any scene / `main` / autoload change:
`godot --headless --path godot --quit-after 30 2>&1 | Select-String
"SCRIPT ERROR|Parse Error|Failed to load"` → no matches.

Render/UI gating (units_layer skip, overlay fog fill, hover/forecast refusal,
cutaway reveal) verified by the final windowed manual pass (headless can't render)
— listed in the handoff's pending-manual-checks.

## Out of scope / accepted divergences

- No line-of-sight occlusion — pure radius (matches MoM + design doc).
- No "explored/remembered terrain" layer — terrain is always fully visible, so none
  is needed.
- `visibility` is single-viewer (the human side). The game is human-vs-AI; no
  hotseat two-human fog. If hotseat ever lands it recomputes per active human.
- New fog-default **skirmish** maps are Phase 4 content, not Phase 3.
- Fog overlay is a flat dark translucent fill (no per-tile edge feathering) — a
  polish candidate, not required for parity.

## Build order (for the plan)

1. `core/vision.gd` + tests (pure; nothing depends on render yet).
2. `relics.gd` Veilstone + tests (unblocks `unit_sight` bonus test).
3. `GameState.fog` + `visibility` + `recompute_visibility`; `new_skirmish` param;
   save round-trip + tests.
4. Fair-AI filter in `ai.gd` + tests (fog-on filters, fog-off regression).
5. Settings + title toggle + map-def `fog` plumbing.
6. Render: overlay fog fill + units_layer enemy gating.
7. `match_scene` recompute timing + hover/forecast gating.
8. Cutaway ambush reveal.
9. Whole-milestone review + manual windowed pass.
