# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## What this is

A single-page browser game: `index.html` + `game.js`. No build step, no dependencies, no package manager. Open `index.html` in a browser and it runs.

Internal canvas is 1280×800. CSS scales it responsively to fit the viewport while preserving 16:10 aspect ratio. Rendered with `image-rendering: pixelated` so the pixel grid stays crisp at any scale.

## Run it

```
start index.html      # Windows
```

URL hash hooks for verification (used by headless screenshot tests):
- `#autostart` — skip the title screen and start a fresh match.
- `#demo` — start a match, have AZURE pre-summon two creatures, then auto-end-turn so the AI plays.
- `#battle` — start a match and immediately trigger a battle cutaway (both archons within range of each other).
- `#gameover` — jump straight to the victory screen.

## Headless smoke test (Windows)

The headless capture viewport is much smaller than a typical monitor (Chrome eats ~95px for OS chrome). For useful screenshots use a window-size of at least 1600×1100:

```
"C:/Program Files/Google/Chrome/Application/chrome.exe" --headless=new --disable-gpu \
  --window-size=1600,1100 --force-device-scale-factor=1 --virtual-time-budget=1400 \
  --screenshot=%TEMP%/battle.png \
  "file:///C:/Users/jnixo/testgrounds/index.html#battle"
```

For pure syntax check: `node --check game.js`.

## Critical implementation note: canvas state reset

`render()` reassigns `canvas.width = CANVAS_W` as its first action. **Don't remove this.** It wipes any clip path that survived a prior frame. Without it, an exception during one render can leave a clip active, causing subsequent fillRect-clears to be confined to the old clip rect and frames stack visibly. Reassigning `canvas.width` is the only way to clear an active clip — `ctx.save/restore` doesn't help if the bug is on the *previous* frame.

## Architecture

`game.js` is sectioned by comment banners (1–16). Dependency-ordered:

1. **Constants & palette** — canvas dims (1280×800), hex sizing (HEX_SIZE=36), colors, `PLAYERS[]` with per-player `color`/`dark`/`trim` triples used for unit tinting.
2. **Hex math** — pointy-top axial coords (`axialToPixel`, `pixelToAxial`, `hexNeighbors`, `hexDistance`). Cells keyed by `"q,r"` via `hexKey`.
3. **Terrain & map** — `TERRAIN` table (move cost, defense, flyer-only). `generateMap(seed)` is deterministic via `mulberry32`.
4. **Unit & master definitions** — `UNIT_TYPES` (8 monsters), `MASTER_TEMPLATE`. Each type has an `attack` flavor (`melee`/`breath`/`spray`/`spark`/`dive`/`bolt`) that the battle scene reads to choose an attack animation.
5. **`STATE`** — single source of truth. `screen ∈ {"title","play","battle","gameover"}` drives which renderer runs. `STATE.battle` holds the active battle scene (pre-computed damage, phase, frame counter, shake/flash).
6. **Pathfinding & action queries** — `computeReachable` (Dijkstra), `computeAttackTargets`.
7. **Combat resolution** — `computeDamage` is pure (no side effects). `beginBattle` snapshots damage + counter-damage, sets `STATE.battle` and `STATE.screen='battle'`, hands off to the battle scene. Damage is only *applied* during the `aImpact`/`cImpact` frames so the visuals stay in sync with HP changes.
8. **AI** — `aiTakeTurn` dispatches one unit at a time via `setTimeout` chain. The step function checks `STATE.screen === 'battle'` and polls until the battle finishes before moving the next unit.
9. **Procedural sprites** — `drawMapSprite` (small map-scale, ~24px), `drawBattleSprite` (large 5×-scale battle portraits). Archons branch on `unit.owner` for distinct AZURE vs CRIMSON looks (round vs spiked hat, crescent vs flame staff).
10. **Battle scene state machine & renderer** — `updateBattle` advances phases: `intro → standoff → aCharge → aImpact → aRecover → cPause → cCharge → cImpact → cRecover → outro → done`. `renderBattle` is self-contained — it fills the canvas itself, so don't render the map underneath (that leaks through the parallax). Arena background varies by defender's terrain. Attack effects (`drawAttackEffect`) are keyed off `unit.attack`.
11. **Map rendering pipeline** — `render()` dispatches by `STATE.screen`. Map area uses save/clip/translate per pass with `STATE.cam` offset.
12. **Input & menus** — mouse → `pixelToAxial`. Post-move action menu is built dynamically from what's available at the new tile.
13. **Turn machinery** — `endTurn` switches players, applies MP regen (master base + tower count × 2), heals owned-tower/castle units, kicks off AI.
14. **Title / gameover screens** — synthwave sun + perspective grid on title, archon silhouette on gameover. Drawn entirely procedurally.
15. **Audio** — `beep()` for SFX. Music engine: `setInterval(musicTick, 170)` for ~88 BPM 16ths. Four-bar minor progression in A minor (i-VI-III-VII = Am-F-C-G). Each tick fires a square bass pluck, triangle arp note, sustained sawtooth pad on bar 1, and sparse lead notes. `musicDuck(level)` lowers volume during battle. Auto-starts on first user gesture (`startMusicOnGesture`) due to browser autoplay policy.
16. **Boot / resize / main loop** — `boot()` wires DOM events. `resizeCanvasCSS` runs on load and on `resize` event.

## Adding content

- **New monster**: add to `UNIT_TYPES` (give it a unique `sprite` id and an `attack` flavor matching one of the cases in `drawAttackEffect`), add to `SUMMON_LIST`, add a `case` in `drawMapSprite` and `drawBattleSprite`.
- **New terrain**: add to `TERRAIN`, optionally a `case` in `drawTerrainDetail`, reference in `generateMap`. Add to `drawArenaBackground` switch if you want it to influence battle scene visuals.
- **New element**: add to `ELEMENT` and a row + column to `ELEM_MATRIX` (every element must have an entry against every other element).
- **New battle phase**: add to the `B = { ... }` durations object and a `case` in `updateBattle`'s switch.

## Conventions worth knowing

- Hex addresses are axial `{q, r}` everywhere. Storage key is `"q,r"` via `hexKey`.
- `unit.acted` gates whether a unit can be selected on its owner's turn; reset in `endTurn` for the incoming player.
- Summoned units spawn with `acted: true` (can't move/attack the turn they appear).
- The battle scene blocks input — `onClick` and `onKey` early-return when `STATE.screen === "battle"`. The AI loop polls the same flag before advancing.
- Damage is computed up-front in `beginBattle` and applied later at `aImpact`/`cImpact` frames; the `applied1`/`applied2` flags prevent double-application.
- All canvas state must round-trip through `ctx.save()/ctx.restore()` pairs. If you add a new render function with `ctx.clip()`, wrap it.
