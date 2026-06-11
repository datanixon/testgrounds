# Wraithspire Godot Port — Milestone 7: HUD/UI + board-rendering refactor — Design

**Status:** approved (2026-06-11). Branch `godot-port`. Base: M6 complete (`02a4d4d` AI; session-state `9be4ce0`). Next step after this spec: `superpowers:writing-plans`.

## Goal

Replace the placeholder match scene with the real presentation layer: a hex `TileMapLayer` board, `Sprite2D` unit tokens (team identity + HP/status indicators), a real `Camera2D`, and a `CanvasLayer` HUD of Control nodes (topbar, unit info card, anchored post-move action menu, summon sub-list). Retire the temp debug keybinds (`D`/`T`/`A`) in `main.gd` in favor of a real click → move → action-menu interaction flow. Still on placeholder art — real sprites/audio are M10.

This is the single biggest player-facing quality jump of the port: hand-laid canvas text becomes laid-out Control nodes, and the manual camera offset becomes a real camera.

## Scope

**In M7:**
- Hex `TileMapLayer` terrain rendering (replaces `scenes/board/board.gd` custom `_draw`).
- `Sprite2D` unit nodes bound to `GameState` records (replaces `scenes/match/units_layer.gd` tokens): team-colored base-ring, HP pip/bar, status-icon row.
- Highlight overlay layer (reachable / attack ring / blink + summon-slot / selected outline).
- Real `Camera2D`: center-on-active-master (current behavior) + drag-pan + scroll-zoom.
- HUD `CanvasLayer` of Control nodes: topbar, unit info card, post-move action menu (anchored popup), summon sub-list.
- Interaction flow replacing the debug keybinds, including **Undo** (pre-commit move reversal) and the "ability mis-click backs out to the menu without freeing the unit" fix.
- A pure, testable core helper (`available_actions`) + summon-list builder, so menu contents are harness-asserted while the Control nodes stay logic-free.

**Out (deferred, with owning milestone):**
- Battle cutaway scene + the AI turn-runner becoming a coroutine — **M8**. M7 keeps the M6 synchronous AI handoff.
- **Move-slide animation** (unit slides hex-to-hex along its Dijkstra path before the menu opens) — **M8**, built with the same `Tween`/`AnimationPlayer` work as the cutaway. M7 snaps the unit to its destination (as the current placeholder does). *Decision (2026-06-11): defer to keep M7 focused on layout/interaction; animation plumbing lands once in M8.*
- Title / gameover / save-load / difficulty-select UI / campaign — **M9**.
- Real generated art + audio engine — **M10**.

## Architecture

### Pure logic / thin presentation split

The JS `openPostMoveMenu` (game.js 4559–4588) mixes two concerns: deciding which actions are available, and drawing the menu. M7 splits them so the decision is testable:

- **New pure core helper** `available_actions(state, unit) -> Array[Dictionary]` (location: a new `core/ui_queries.gd`, class `UiQueries` — keeps `game_state.gd` focused and gives the helper a `class_name` so the harness sees it). Returns an ordered list of action descriptors, each `{ "kind": String, "label": String, "disabled": bool }`, mirroring `openPostMoveMenu`'s item construction:
  - second-move leg (`unit["second_move"]`): only `capture` (if on a capturable tower) and `wait`; clears the flag. No attack/summon/ability/undo.
  - normal: `attack` (only if `compute_attack_targets` from the unit's tile is non-empty), `capture` (only on an unowned tower/castle the unit stands on), `summon` (only `is_master` and `mp >= 6`), `ability` (only if `ability_for(unit) != null`; `disabled` when `cd > 0`, label carries the cooldown number), `undo` (only when an undo snapshot exists for this unit), `wait` (always).
- **New pure core helper** `summon_options(state, master) -> Array[Dictionary]`: `SUMMON_LIST` mapped to `{ "key", "label" (name · element · NN MP), "cost", "disabled" (cost > mp) }`. Mirrors game.js 4620–4628.
- The Control-node menu renders exactly what these return; it holds no availability logic. `find_summon_slot` (already in `core/ai.gd`) is reused for the spawn position — or, to avoid a UI→AI dependency, a copy/move of `find_summon_slot` into a shared location is decided at plan time (it is presentation-agnostic and is also used by the AI; the clean option is to host it in `core/ui_queries.gd` or a shared queries module and have `ai.gd` call it). The plan picks the exact home; the constraint is **no new presentation→AI coupling**.

Capture eligibility (`can_capture` in the JS) is a small predicate used by both `available_actions` and the commit path; it lives alongside `available_actions` in `core/ui_queries.gd`.

### Scene tree (MatchScene under `scenes/main.gd`)

```
Main (Node2D)                  owns GameState; routes input; wires HUD ↔ board ↔ state
├─ BoardTileMap (TileMapLayer)  terrain; one tile id per terrain type
├─ HighlightLayer (Node2D)      _draw: reachable / attack / blink+summon-slot / selection
├─ UnitsLayer (Node2D)          one UnitNode (Sprite2D + ring + HP + status) per live unit
├─ Camera2D                     center-on-master + drag-pan + scroll-zoom
└─ HUD (CanvasLayer)
   ├─ TopBar (Control)          turn # · player · weather · master MP · End-Turn button
   ├─ InfoCard (Control)        hovered/selected unit stats
   ├─ ActionMenu (Control)      anchored VBox of Buttons; from available_actions
   └─ SummonList (Control)      anchored VBox; from summon_options; + Back
```

Each UI node has one responsibility and a narrow interface (e.g. `InfoCard.show_unit(unit)` / `InfoCard.clear()`; `ActionMenu.open(actions, screen_pos)` emitting a `chosen(kind)` signal). `main.gd` is the only place that mutates `GameState` and re-syncs nodes after a state change — it stays the controller, the UI nodes stay dumb.

### Camera

`Camera2D` replaces the manual `cam.position` assignment. Center-on-active-master is preserved (`_center_on_master`). Added: right/middle-drag pans; scroll wheel zooms within clamped limits. Hex pixel hit-testing uses `get_global_mouse_position()` → `pixel_to_axial` (already correct against a real camera, since the current code already reads global mouse pos).

## Interaction flow

Replaces `_unhandled_input`'s debug branches. State machine in `main.gd`:

1. **Idle** → click own unit ⇒ **Selected**: highlight reachable + attack tiles, `InfoCard.show_unit`.
2. **Selected** → click reachable tile ⇒ move unit (snap), record an **undo snapshot** `{unit, q, r}`, open the post-move menu via `available_actions`. Click own unit's own tile or another own unit ⇒ open menu in place / reselect. Click elsewhere ⇒ deselect.
3. **Menu open** → choose:
   - `attack` → arm a plain attack (reuse the M5 `armed` machine, `ab = null`); click a target resolves it, commits (`acted = true`, clear undo).
   - `ability` → instant fires immediately + commits; enemy/tile arms then resolves on click (M5 path). Mis-click on arm **re-opens the menu** (does not free the unit) — the SESSION_STATE-flagged fix.
   - `capture` / `wait` → commit (`acted = true`, clear undo, close menu).
   - `summon` → open `SummonList`; a choice spawns into `find_summon_slot`, spends MP, commits; **Back** returns to the action menu.
   - `undo` → move the unit back to the snapshot hex, clear `acted`, close menu, re-select (overlays return). Only present while the snapshot is live (pre-commit).
4. **Enter** (or End-Turn button) → `end_turn()`; if it becomes player 1's turn and no winner, `AI.take_turn` then `end_turn` again; recenter (the M6 handoff, unchanged).

`acted` gating becomes real: an acted unit cannot be re-selected for a new action (matches the JS `unit.acted` gate). Summoned units keep `acted = true`.

## Testing & gates

Harness coverage targets the new pure helpers (UI nodes are presentation, covered only by the headless-boot parse gate):
- `available_actions`: attack present only with in-range targets; capture only on a capturable unowned tower/castle the unit occupies; summon only for a master with `mp >= 6`; ability present always when the type has one, `disabled` iff `cd > 0` with the cooldown in the label; second-move leg yields exactly `capture?`+`wait`; undo present only when a snapshot exists; wait always last.
- `summon_options`: full `SUMMON_LIST`, costs correct, `disabled` flips at the master's MP boundary, labels formatted.
- `can_capture` predicate edge cases (own tower → false; enemy/neutral tower/castle under the unit → true; non-tower → false).

Gates per task: harness `pwsh -File godot/tests/run_tests.ps1` (`== N passed, 0 failed ==`, EXIT 0; the `-ExecutionPolicy Bypass` form is blocked by the Claude Code classifier — use plain `pwsh -File`). After **any** scene/`main.gd` change (which is most of M7), also run the headless boot parse gate: `godot --headless --path godot --quit-after 30 2>&1 | Select-String "SCRIPT ERROR|Parse Error|Failed to load"` (clean = no matches). Final windowed visual confirmation is the user's (no display in-session).

## Decomposition (the plan will order these)

Large milestone → ordered, independently-gated tasks, each via the proven loop (grinder implementer → general-purpose spec review → feature-dev:code-reviewer quality review; fixes amended in place):

1. `core/ui_queries.gd`: `available_actions` + `summon_options` + `can_capture` (pure) + tests. Decide `find_summon_slot` home (no presentation→AI coupling).
2. `Camera2D`: center-on-master + drag-pan + scroll-zoom (replaces the manual cam node).
3. `TileMapLayer` hex board (replaces `board.gd` custom draw).
4. `Sprite2D` unit nodes + team ring + HP/status indicators (replaces `units_layer` tokens).
5. Highlight overlay (reachable / attack / blink+summon-slot / selection).
6. Topbar + unit info card.
7. Action menu + summon sub-list Control nodes, wired to the pure helpers.
8. Interaction flow + Undo + mis-click backout; retire debug keys; close M7.

Task order keeps a runnable game at every step: helpers first (pure, no scene risk), then camera, then board/units/overlay (each swappable behind the existing placeholder), then HUD, then the interaction rewrite last (it depends on all the prior pieces).

## Carry-over fidelity & accepted gaps

- Faithful to the JS interaction model (anchored post-move popup, dynamic items, summon sub-list, Undo, keyboard+mouse nav). No new mechanics.
- Placeholder art throughout — base-rings/HP/status are simple shapes; real sprites are M10. Architecture (engine-side team identity via base-ring/frame) is unchanged by art choice.
- The M6 synchronous AI handoff is preserved; the coroutine rewrite is M8's job and does not touch the M7 UI or the decision functions.
