# Wraithspire Godot Port — Milestone 8: Battle cutaway scene — Design

**Status:** approved (2026-06-11). Branch `godot-port`. Base: M7 complete (`6b394b9`). Next step after this spec: `superpowers:writing-plans`.

## Goal

Add the full-screen battle cutaway — a richer procedural combatant scene that plays a phased animation (charge / impact / recoil, damage numbers, screen shake, hit-flash) for each battle — driven by a **resolve-then-replay** model. Combat keeps resolving synchronously in the pure core (determinism and the C#-swap seam untouched); each resolved battle records a snapshot, and the presentation layer drains that queue and plays a cutaway per record. Also adds a human-only move-slide animation (deferred from M7).

This restores the visual centerpiece the procedural-canvas reference had, on placeholder-quality procedural art (real battle portraits are still M10 — but M8 ports the *structure* of the JS procedural sprites, which the user chose over flat boxes).

## Scope

**In M8:**
- `GameState.battle_log` + `Combat.resolve_attack` recording a per-battle snapshot (pure data; harness-asserted). Resolution behavior and RNG draws are unchanged.
- A self-contained `BattleScene` cutaway: phase machine (`intro → standoff → aCharge → aImpact → aRecover → cPause → cCharge → cImpact → cRecover → outro → done`), letterbox, damage numbers, screen shake, hit-flash, draining HP bars, arena background by defender terrain. Emits `finished`.
- Richer procedural visuals (user's choice): port `drawBattleSprite` per-type portraits, `drawAttackEffect` (6 attack flavors: melee / breath / spray / spark / dive / bolt), `drawArenaBackground` (per terrain).
- A replay driver in `main.gd`: drains `battle_log` and `await`s each cutaway, after a human attack and after the AI turn. Input is blocked while battles play.
- Human-only move-slide animation (unit tweens hex-to-hex along its Dijkstra path before the action menu opens).

**Out (deferred, with owning milestone):**
- Real generated art + audio — **M10**. M8 procedural sprites are placeholder-quality (structure ported, art replaced later).
- The battle-scene on/off setting + difficulty-select + title/gameover/save/campaign — **M9**.
- **AI move animation** — out by design (the resolve-then-replay model snaps AI units to final positions and replays only battles).

## Architecture

### Resolve-then-replay (the chosen model)

The JS reference resolves a battle *during* the cutaway (apply HP at impact frames). M8 instead **resolves synchronously, then replays**:

1. `Combat.resolve_attack` runs exactly as today (same `compute_damage`, same `state.rng` jitter/counter draws — bit-for-bit determinism preserved). It additionally **appends one record** to `GameState.battle_log` capturing what happened.
2. The presentation layer (`main.gd`) drains `battle_log` at defined points and plays a cutaway per record. Because resolution already happened, the cutaway is **pure animation** — it never mutates game state; it animates from the recorded numbers.

Consequences (accepted): the board reflects final state before/under the cutaway (a human attack's cutaway covers the board, so the pre-update is imperceptible; the AI turn resolves fully, then its battles replay, so AI **movements are not animated** — units appear in final positions). This is the simplification the user chose over a coroutine-in-core driver.

### Battle record (the snapshot)

`Combat.resolve_attack` captures HP *before* applying, then records (after resolving):

```gdscript
{
  "attacker": { "type_key", "name", "element", "sprite", "owner", "attack" },
  "defender": { "type_key", "name", "element", "sprite", "owner", "attack" },
  "atk_hp_before": int, "atk_max_hp": int,
  "def_hp_before": int, "def_max_hp": int,
  "primary": { "dmg": int, "absorbed": bool, "killed": bool },   # absorbed = ward ate the swing
  "counter": { "happened": bool, "dmg": int, "absorbed": bool, "killed": bool },
  "status": { "key": String, "turns": int } | null,             # status applied to the defender, if any
  "terrain": String,                                            # defender's tile terrain → arena bg
}
```

This is plain serializable data with no node references, so it is harness-assertable (a new testability win the inline M4 version lacked). `battle_log` is appended by `resolve_attack` and **drained + cleared** by the presentation; headless tests either ignore it or assert on it.

### Components & file layout

```
godot/core/game_state.gd        + var battle_log: Array = []                         [MODIFY]
godot/core/combat.gd            resolve_attack records a battle snapshot (capture pre-HP)  [MODIFY]
godot/scenes/battle/battle_scene.gd    BattleScene — phase machine + play(record)+finished  [NEW]
godot/scenes/battle/battle_sprites.gd  port of drawBattleSprite (per-type portraits)        [NEW]
godot/scenes/battle/battle_fx.gd       port of drawAttackEffect (6 flavors) + drawArenaBackground  [NEW]
godot/scenes/main.gd            replay driver (_play_battles coroutine + _busy block); human move-slide  [MODIFY]
godot/tests/run_tests.gd        + _test_battle_record                                 [MODIFY]
ROADMAP_GODOT.md                check off M8
```

- **BattleScene** is self-contained: it fills the screen and does not render the map underneath (the JS rule — avoids parallax leak). It takes a record via `play(record)`, runs the phase machine, and emits `finished` when the `done` phase is reached. Phase durations port from the JS `B` table (frames at 60 fps → seconds). It owns its own draw of: arena background (`battle_fx`), two combatant portraits (`battle_sprites`, attacker faces right, defender mirrored), attack effects keyed off `unit.attack` (`battle_fx`), damage popups, HP bars (animated from `*_hp_before` toward the post-swing value), letterbox bars, shake/flash.
- **battle_sprites.gd / battle_fx.gd** are static draw helpers (headless-parseable; no game logic). They are the bulk of the milestone and are mechanical ports of the JS procedural draw code; M10 replaces their bodies with real sprite/effect assets behind the same call signatures.
- **main.gd** gains: `_busy: bool` (blocks `_on_click` / board input while battles or a move-slide play); `_play_battles()` (an `async`/`await` coroutine that, while `battle_log` is non-empty, instantiates/show s the BattleScene, `await`s its `finished`, and pops the record; clears the log and refreshes the board + HUD at the end); calls to `_play_battles()` after the human attack path (`_resolve_armed` / the menu attack) and at the end of `_on_end_turn` (after `AI.take_turn`). The existing synchronous `take_turn` and all of `core/ai.gd` are unchanged.

### Move-slide (human only)

On a human move (`_on_click`'s reachable-tile branch), instead of snapping, set `_busy`, tween the moving unit's `UnitNode` hex-to-hex along the reconstructed Dijkstra path, then clear `_busy` and open the action menu. AI moves and the undo restore stay instant. Path comes from `Pathfinding` (reconstruct the route to the destination); if no path helper exists yet, a straight tween to the destination is the fallback (decided at plan time — a per-hex slide is preferred).

## Data flow

- **Human attack:** menu/armed → `Combat.resolve_attack` (resolves + records 1 battle) → `_play_battles()` (await cutaway) → `_commit` / refresh.
- **AI turn:** Enter/End-Turn → `AI.take_turn` (resolves the whole turn synchronously, recording N battles) → `_play_battles()` (await N cutaways in order) → refresh + hand back.
- **No battle (move/capture/summon/instant):** no record; no cutaway.

## Testing & gates

- **Harness (pure):** `_test_battle_record` on constructed boards — a known attack records the expected `primary.dmg` / `killed` / `counter.happened` / `status` / `terrain`; a ward-absorbed primary records `absorbed: true` (and no status); a lethal primary records `counter.happened: false`; the log length matches the number of battles. These assert the **record**, which is deterministic pure data. Confirm existing 374 asserts still pass (resolution behavior unchanged).
- **Presentation (BattleScene + sprites + fx):** harness can't assert visuals → the headless-boot parse gate is the automated check (run after any scene/`main.gd` change), plus the user's windowed visual confirmation. A lightweight structural check (the scene reaches `done` and emits `finished` for a sample record) may be added if feasible headlessly.
- **Gates:** harness `pwsh -File godot/tests/run_tests.ps1` (`== N passed, 0 failed ==`, EXIT 0; NOT `-ExecutionPolicy Bypass` — classifier-blocked) after every task; headless boot `godot --headless --path godot --quit-after 30 2>&1 | Select-String "SCRIPT ERROR|Parse Error|Failed to load"` (clean) after any scene/`main.gd` change.

## Decomposition (the plan will order these)

1. `GameState.battle_log` + `Combat.resolve_attack` records the snapshot (capture pre-HP) + `_test_battle_record` (pure, TDD).
2. `BattleScene` skeleton: phase machine + durations + letterbox + `play(record)` / `finished` signal, with placeholder combatant boxes (no portraits yet). Boot gate + structural reach-`done` check.
3. `battle_sprites.gd` — port `drawBattleSprite` per-type portraits; wire into BattleScene (the bulk; mechanical).
4. `battle_fx.gd` — port `drawAttackEffect` (6 flavors) + `drawArenaBackground` (per terrain); wire in. Damage numbers + shake/flash + HP bars finalized.
5. Replay driver in `main.gd`: `_play_battles()` + `_busy` input block; human attack routes through the cutaway.
6. AI turn replay (drain `battle_log` after `take_turn`) + human move-slide; fold in the three M7 polish carry-forwards; close M8.

Order keeps a runnable game at each step: the record + scene skeleton first (no behavior change to the board), then the visuals, then wiring the human path, then the AI path + move-slide last.

## Carry-over fidelity & accepted gaps

- **Determinism preserved:** `resolve_attack` keeps its exact `compute_damage` + `state.rng` draw order; recording is a side-write of already-computed data.
- **Accepted divergences from the JS cutaway (from the resolve-then-replay choice):** the board updates before/under the cutaway rather than at impact frames; AI unit movement is not animated (only battles replay). Both were chosen for a simpler core with no coroutine in `core/ai.gd`.
- **C#-swap seam intact:** `core/ai.gd` is untouched; `take_turn` stays synchronous. The cutaway and driver live entirely in the presentation layer.
- **Battle-scene on/off setting** (JS `STATE.settings.battleScene`) is deferred to M9 (settings UI); M8 always plays the cutaway.
- **M7 minor polish folded into Task 6:** dead `overlay.set_attack()`; `info_card` mid-action staleness; menu `_clamp_on_screen` hardcoded widths.
