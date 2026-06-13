# Session Handoff — Wraithspire Godot port

Last session end: 2026-06-11. Read this, then `SESSION_STATE.md` (full running
handoff) for depth. Caveman chat mode was active last session (cosmetic; toggle
with "stop caveman" / "normal mode").

## Where things stand

- **Canonical branch:** `main` — has the COMPLETE Godot port (M1–M10), ROADMAP2 Phase 2
  (Relics), Phase 3 (Fog), Phase 4.2 (Objectives), **Phase 4.1 (Evolutions — DATA)**, and
  a family of screenshot-found visual fixes (display/stretch; procedural-screen + top_bar +
  settings + battle-cutaway size-0 Control bugs; camera board-bounds clamping) — all merged.
  978 tests green.
- **In flight:** **Phase 4.3 (Bosses + maps) — DATA DONE on branch `godot-p4-3-bosses-maps`**
  (off main, NOT merged): 2 new skirmish maps (Mistveil Hollow fog-default + Ashfall Basin),
  2 bosses (Pyre Colossus, Storm Tyrant — non-summonable, reuse abilities), Pyre Colossus
  demo'd in mission 4. 998 tests. **Boss art (4 PNGs) PENDING.**
- **ART PENDING** — Phase 4.1: 8 PNGs (Hexlord/Sigilwarden/Glaciamaw/Dunestalker); Phase 4.3:
  4 PNGs (Pyre Colossus/Storm Tyrant). Generation prompts in the respective spec appendices
  (`docs/superpowers/specs/2026-06-13-wraithspire-{evolutions,bosses-maps}-design.md`). Loader
  degrades gracefully (engine disc) until they land. Drop-in steps in `docs/PROGRESS.md`.
- **Visual validation tool:** `--shot <target>` hook in `scenes/main.gd` captures a screen
  to `godot/tools/shots/<target>.png` (windowed). Targets: title/skirmish/fog/mission2/
  battle/campaign/story/gameover/settings. `godot --path godot -- --shot fog`.
- **Done & on main:** the COMPLETE Godot port (M1–M10 — full JS-reference parity
  + real art + audio) **plus ROADMAP2 Phase 2 (Relics) + Phase 3 (Fog) + Phase 4.2
  (Objectives)**.
- The JS build at repo root (`index.html` + `game.js`) is the FROZEN reference —
  do not add features to it.

### Phase 3 (Fog of war) — what landed on `godot-p3-fog`
- Pure `core/vision.gd` (`Vision.compute(state, owner)` → visible "q,r" set; r3 ground
  / r4 fly / +Veilstone; owned tower/castle r2; no LOS blocking).
- `GameState.fog` (saved) / `visibility` (render cache) / `revealed` (per-turn ambush
  reveals) + `recompute_visibility`. Save round-trips `fog`; visibility recomputed.
- Fair AI: `build_threat_map` + `run_summons` filter enemies to the AI's own vision
  when `fog`; **fog-off path is byte-identical** (determinism intact). `approach_target`
  routes a non-master to the enemy *castle* (always-visible terrain) when the enemy
  master is hidden, so the AI never beelines a fogged master.
- Render: `overlay.gd` dim fog fill, `units_layer.gd` hides enemies outside vision,
  `match_scene._refresh_fog` recomputes on every move/summon/death/turn + reveals
  ambush attackers after their cutaway (`combat.gd` records `attacker_pos`).
- Veilstone relic (+1 vision) in `relics.gd` POOL; title-screen FOG toggle (default
  off, persisted); mission 4 "The Wraithspire" fog-flagged.
- **PENDING manual windowed check** (`godot --path godot`, needs a display): fog dims
  out-of-vision tiles; enemies hidden until in sight; vision lifts as you move; AI
  ambush reveals the attacker; Veilstone +1; FOG OFF = no dimming; mission 4 forced fog;
  resumed save stays fogged.
- Docs: spec `docs/superpowers/specs/2026-06-13-wraithspire-fog-of-war-design.md`,
  plan `docs/superpowers/plans/2026-06-13-wraithspire-fog-of-war.md`.

## Branches

- `main` — canonical, has everything above.
- Merged feature branches (safe to delete; all FF-merged into main): `godot-port`,
  `godot-m10-art-audio`, `godot-m10-art`, `godot-p2-relics`. Earlier ones too.
  Cleanup optional: `git branch -d <name>`.

## Next work: merge Phase 4.1 data, then its art + Phase 4.3

**First:** once the user OKs, FF-merge `godot-p4-1-evolutions` → `main` and push.

**Phase 4 is decomposed into 3 slices** (each its own spec→plan→subagent build):
- **4.2 Objective framework — DONE + merged.** The foundation Phases 5 & 7 reuse.
- **4.1 Evolutions — DATA DONE** on `godot-p4-1-evolutions` (Hexlord/Sigilwarden/Glaciamaw/
  Dunestalker entries + `evolves_to`; UNIT_TYPES 20→24; `_test_sprites` PENDING_ART skip;
  978 tests). **ART follow-up pending:** user generates 8 PNGs (prompt in
  `docs/superpowers/specs/2026-06-13-wraithspire-evolutions-design.md` appendix) → drop in
  `godot/assets/sprites/` → `godot --headless --import --path godot` → remove the 4 ids from
  `pending_art` in `_test_sprites` → commit PNGs+.import+test.
- **4.3 Bosses + maps** — 2 boss monsters (**4 more sprites**, non-summonable) + 2 new
  skirmish maps (one fog-default — the first fog-default *skirmish* map). Pairs with 4.2
  objectives. Needs its own spec/plan.
- **4.3 Bosses + maps** — 2 boss monsters (**4 more sprites**, non-summonable) + 2 new
  skirmish maps (one fog-default — the first fog-default *skirmish* map). Pairs with 4.2
  objectives.

### Phase 4.2 (Objectives) — what landed on `godot-p4-objectives`
- Pure `core/objectives.gd` — `evaluate(state)->int` (0 player-0 wins / 1 player-0 loses /
  -1 none) + `label(state)->String`; kinds `survive(n)` / `seize(hex)` / `protect(unit_id)`
  / `rout`, beside the always-on archon-kill.
- `GameState.objective` + `objective_progress` (both saved) + `unit_by_id` /
  `enemy_non_masters`; `check_win_condition` calls `Objectives.evaluate` **after** the
  master-death check (archon-kill precedence kept); `new_skirmish` copies the def objective.
- Fair-ish AI: `weights()` post-processes per objective (rush/defend) — **duplicates before
  mutating** the const profile, and a **no-op when there's no objective** (determinism
  preserved). Seize evaluated immediately on move (human + AI). Topbar objective line.
  Save round-trips it. Demo `survive(8)` on campaign mission 2.
- **PENDING windowed check** (`godot --path godot`): Campaign → mission 2 → topbar
  "Survive: x/8"; hold 8 rounds → win without killing the archon; archon-kill still wins;
  no-objective skirmish unchanged.
- Docs: `docs/superpowers/{specs,plans}/2026-06-13-wraithspire-objectives*`.

## Process (proven across M1–M10 + Phase 2)

1. `git checkout -b <branch> main` for the milestone.
2. **Brainstorm** (`superpowers:brainstorming`) → spec in `docs/superpowers/specs/`.
3. **Plan** (`superpowers:writing-plans`) → `docs/superpowers/plans/` (TDD tasks).
4. **Execute** (`superpowers:subagent-driven-development`): per task — `grinder`
   implementer (model sonnet, verbatim plan steps) → spec review (`general-purpose`)
   + code review (`feature-dev:code-reviewer`, or `caveman:cavecrew-reviewer` for
   tiny diffs) → fixes via same/new grinder + `git commit --amend` → next task.
   Final whole-milestone review (opus) over the full diff.
5. FF-merge to main + push when the user approves.

## Gates (run after every task)

- Harness: `pwsh -File godot/tests/run_tests.ps1` → last line `== N passed, 0 failed ==`,
  EXIT 0. **NEVER** add `-ExecutionPolicy Bypass` (classifier blocks it).
- Headless boot (after ANY scene/`main`/autoload/`project.godot`/`map_gen` change):
  PowerShell — `godot --headless --path godot --quit-after 30 2>&1 | Select-String
  "SCRIPT ERROR|Parse Error|Failed to load"` → no matches = clean.
- Windowed run (visual/audible, needs a display): `godot --path godot`.

## Key gotchas (cost real debugging time)

- **Harness `--script` runs do NOT load autoloads** — scripts force-preloaded by
  `run_tests.gd` (only `board.gd` + `battle_scene.gd`) must reach the Audio autoload
  via `get_node_or_null("/root/Audio")`, NOT bare `Audio.`. class_name scripts
  (lazy-registered) use bare `Audio.` fine.
- **Map q is NEGATIVE on lower rows** (`offset = -(r>>1)`): pick cells with
  `_pick(cells, order, rng)`, never raw `rng.below(cols)/below(rows)` as q/r.
- **Sprite PNGs need a Godot import pass** (`godot --headless --import --path godot`,
  or `--editor --quit`) to generate `.import` sidecars before `load()` resolves them;
  `.godot/imported/` cache is git-ignored; root `.gitignore` blanket `*.png` is
  whitelisted for `godot/assets/sprites/` in `godot/.gitignore`.
- **`Relics.bonus(id, key)` takes a relic-ID string**, not a unit dict.
- **Hard-index unit stats** (`unit["max_hp"]`) — the codebase norm; don't
  `.get(...,0)` (a 0 max_hp → divide-by-zero in compute_damage).
- `.uid` files (Godot editor artifacts) stay untracked — ignore them in `git status`.

## Pending manual checks (need a display)

- M10 art windowed visual (board tokens / battle portraits / archons).
- Phase 2 relics windowed (glyphs show, equip/swap, Phoenix revive, AI grabs relics).
- M10 audio audible (music loops, settings, duck, SFX).

## Map of docs

- `SESSION_STATE.md` — full running handoff (most detail).
- `ROADMAP_GODOT.md` — port milestones M1–M10 (all ✅).
- `ROADMAP2.md` — content phases; Phase 1 ✅ (JS), Phase 2 ✅ (Godot), Phases 3–8 pending.
- `docs/superpowers/specs/` + `plans/` — per-milestone design + TDD plans.
- Auto-memory: `~/.claude/projects/C--Users-jnixo-testgrounds/memory/` (MEMORY.md index
  + `wraithspire-godot-port.md`).
