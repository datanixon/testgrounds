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
| Phase 4.1 — Evolutions (**data**) | ✅ done, on `main` | — |
| Phase 4.1 — Evolutions (**art**) | ⏳ pending 8 sprite PNGs | needs user-generated art |
| Phase 4.3 — Bosses + maps (**data**) | ✅ done, on `main` | — |
| Phase 4.3 — Bosses (**art**) | ⏳ pending 4 sprite PNGs | needs user-generated art |
| Phase 5.1 — Campaign roster layer | ✅ done, on `godot-p5-1-roster` (awaiting merge) | `core/roster_store.gd` |
| Phase 5.2–5.3, 6–8 | ⬜ not started | `ROADMAP2.md` |

Test suite: **1067 harness asserts green** on `godot-p5-1-roster` (998 on `main`).

## Visual bug fixes merged to `main` (found via screenshots)

A `--shot` screenshot sweep of every screen surfaced a family of latent render bugs —
a `Control` parented to a non-Control (the Node2D router or a HUD CanvasLayer) gets
size (0,0) from `FULL_RECT`/`TOP_WIDE`, so anything drawn at its own scale collapsed.
All fixed + verified:
- `[display]` window/stretch config (default window too small, cropping controls).
- Procedural screens (title/campaign/story/gameover): clicks dead (size 0) → sized to canvas.
- Battle cutaway: rendered in the top-left corner → draws against the viewport rect.
- Top bar: bg strip gone, End Turn + gear buttons collapsed to x=0 → sized to viewport.
- Settings: full-screen dim backdrop covered nothing → sized to viewport.
- Camera: centered on the master (board corner) → ~half-empty view; added board-bounds
  clamping so the board fills/centers in the view.

None were in harness tests (render-layer) — the screenshot hook caught them all.

## Phase 4.1 — Evolutions (data, merged)

Four evolved forms — `Hexlord` (Hexwisp+), `Sigilwarden` (Runeward+), `Glaciamaw`
(Frostmaw+), `Dunestalker` (Duneskink+) — in `data/unit_types.gd` with `evolves_to`
wiring. Evolution mechanic unchanged; evolved forms non-summonable (evolution-only).
`UNIT_TYPES` 20→24. **Art still pending** (8 PNGs — see below).

## Phase 5.1 — Campaign roster layer (on `godot-p5-1-roster`, awaiting merge)

Pure `core/roster_store.gd` (`class_name RosterStore`) — the persistence layer for
the Fire-Emblem-style persistent campaign. Data-only: no live game wiring yet
(deploy screen, win-reconcile call sites, AI scaling = Phase 5.2).
- **Storage:** `user://wraithspire_campaign.json` (the `campaign.v2` slot), blob
  `{v:2, roster:[...], next_roster_id}`. Roster only — mission-unlock progress stays
  in `settings.campaign_progress` (single source of truth; deliberate divergence from
  the spec's "one slot").
- **Full-snapshot entries:** `roster_id` (permanent monotonic UID), `type_key`,
  name/element/sprite/attack, `flying`+`evolved` (bool), `level`/`xp`, grown
  `max_hp/power/def/move/range`, `relic`. Transient fields stripped.
- **`reconcile(blob, living_units, deployed_ids)`** — post-win carry + permadeath:
  deployed survivor → update entry; deployed dead → cull; fresh summon survivor →
  add. Pure (deep-copies the blob). *5.2 must stamp `roster_id` on deployed units.*
- **`migrate(progress)`** — 1 starter veteran per cleared act, built via the real
  `Units` progression path: stoneward L2 / tidekin L3 / geomaul→earthbreaker L4 /
  hexwisp→hexlord L5 (the L≥4 grants evolve). New v2 players start empty.
- **I/O:** `load_or_init`/`save`/`reset`/`probe` + `_validate` (JSON int/bool
  re-coercion; rejects non-dict / wrong-version / missing required keys → falls back
  to `migrate`). 1067 tests; headless boot clean. Spec/plan:
  `docs/superpowers/{specs,plans}/2026-06-13-wraithspire-roster-layer*`.

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
