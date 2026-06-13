# Wraithspire — Progress Snapshot

Last updated: 2026-06-13. High-level status board. Deep detail lives in
`SESSION_STATE.md` (running handoff), `HANDOFF.md` (fresh-session quickstart), and
`ROADMAP2.md` (milestone tracker). Per-feature design + plans in
`docs/superpowers/{specs,plans}/`.

## What this project is

Two builds:
- **JS reference** (`index.html` + `game.js`) — v1 + v2-Phase-1, **FROZEN**. The
  balance-validated source of truth. Do not add features here.
- **Godot 4 port** (`godot/`) — the live development target. Real sprites + audio
  replace the procedural canvas art. All new content lands here.

## Status at a glance

| Milestone | State | Where |
|---|---|---|
| Port M1–M10 (full JS parity + art + audio) | ✅ done, on `main` | — |
| ROADMAP2 Phase 2 — Relics | ✅ done, on `main` | — |
| ROADMAP2 Phase 3 — Fog of war | ✅ done, on `main` | — |
| Phase 4.2 — Objective framework | ✅ done, on `main` | — |
| Phase 4.1 — Evolutions (**data**) | ✅ data done, **unmerged** | branch `godot-p4-1-evolutions` |
| Phase 4.1 — Evolutions (**art**) | ⏳ pending 8 sprite PNGs | needs user-generated art |
| Phase 4.3 — Bosses + maps | ⬜ not started (needs sprites) | — |
| Phases 5–8 (campaign, unlocks/records, gauntlet, balance) | ⬜ not started | `ROADMAP2.md` |

Two windowed-test bug fixes also merged to `main`: a `[display]` window/stretch config
(the game ran in a too-small default window, cropping menu controls) and a
procedural-screen click hit-area fix (title/campaign/story/gameover Controls had size
(0,0), so menu clicks never registered).

Test suite: **978 harness asserts green** on `godot-p4-1-evolutions` (950 on `main`).

## Current branch: `godot-p4-1-evolutions` (off `main`, NOT merged)

Phase 4.1 **data**: four evolved forms — `Hexlord` (Hexwisp+), `Sigilwarden`
(Runeward+), `Glaciamaw` (Frostmaw+), `Dunestalker` (Duneskink+) — added to
`data/unit_types.gd` with `evolves_to` wiring. Evolution mechanic unchanged; evolved
forms are non-summonable (evolution-only). `UNIT_TYPES` 20→24.

Awaiting: user OK to FF-merge.

## Pending art (blocks 4.1 visuals + all of 4.3)

The port uses real sprite PNGs (no procedural fallback). New monsters need generated
art before they look right. I have **no image-generation tool**, so these are on the
user:
- **4.1 evolutions — 8 PNGs**: `hexlord` / `sigilwarden` / `glaciamaw` / `dunestalker`,
  each `_token.png` (512²) + `_battle.png` (1024²). Generation prompt:
  `docs/superpowers/specs/2026-06-13-wraithspire-evolutions-design.md` (appendix).
- **4.3 bosses — 4 PNGs** (2 bosses × token+battle), whenever 4.3 is specced.

The `Sprites` loader degrades gracefully on a missing PNG (engine disc + HP bar, no
crash), so the data ships and plays now; art is a drop-in later.

### Art drop-in procedure (when PNGs exist)
1. Put the PNGs in `godot/assets/sprites/`.
2. `godot --headless --import --path godot` (generates `.import` sidecars — `load()`
   won't resolve a PNG without them).
3. Remove the stems from the `pending_art` skip-set in `_test_sprites` (run_tests.gd).
4. Commit PNGs + `.import` sidecars + the test change; windowed-verify.

## How to work / verify

- **Tests:** `pwsh -File godot/tests/run_tests.ps1` → `== N passed, 0 failed ==`, EXIT 0.
  (Never `-ExecutionPolicy Bypass` — classifier-blocked.)
- **Headless boot** (after any scene/`main`/autoload change):
  `godot --headless --path godot --quit-after 30 2>&1 | Select-String "SCRIPT ERROR|Parse Error|Failed to load"`
  → no matches.
- **Windowed run:** `godot --path godot` (opens maximized; needs a display).
- **Automated screenshots** (visual validation; headless can't render, so this runs
  windowed — needs a display): a `--shot <target>` dev hook in `scenes/main.gd`
  (`_maybe_shot`/`_run_shot`, gated on the flag — zero effect on normal runs, like the
  JS build's `#autostart`/`#fog` hash hooks). It drives to a target screen, captures the
  window to `godot/tools/shots/<target>.png`, and quits. Targets: `title`, `fog`
  (fog-on skirmish), `mission2` (objective campaign mission). Run:
  `godot --path godot -- --shot fog` then read the PNG. Add a target by extending the
  `match` in `_run_shot`. (Shots are git-ignored via the blanket `*.png` rule.)

## Process (proven across the port + Phases 2–4.2)

Per milestone: brainstorm → spec (`docs/superpowers/specs/`) → plan
(`docs/superpowers/plans/`) → subagent-driven execution (grinder implementer per task +
spec/quality review) → whole-milestone review → roadmap check-off + handoff →
FF-merge on user OK. Large phases get decomposed into independent slices first.

## Pending manual checks (need a display)

Accumulated windowed visual passes, low-risk (logic is harness-covered): M10 art,
Phase 2 relics, Phase 3 fog, Phase 4.2 objectives (mission-2 "Survive: x/8"), Phase 4.1
evolutions (evolve a unit → type/stats change, engine disc until art). The screenshot
harness can now automate most of these.
