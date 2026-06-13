# Session Handoff — Wraithspire Godot port

Last session end: 2026-06-11. Read this, then `SESSION_STATE.md` (full running
handoff) for depth. Caveman chat mode was active last session (cosmetic; toggle
with "stop caveman" / "normal mode").

## Where things stand

- **Canonical branch:** `main` @ `d17ab2f` (pushed to `origin`, in sync).
- **Done & on main:** the COMPLETE Godot port (M1–M10 — full JS-reference parity
  + real art + audio) **plus ROADMAP2 Phase 2 (Relics)**. 882 harness tests green.
- The JS build at repo root (`index.html` + `game.js`) is the FROZEN reference —
  do not add features to it.

## Branches

- `main` — canonical, has everything above.
- Merged feature branches (safe to delete; all FF-merged into main): `godot-port`,
  `godot-m10-art-audio`, `godot-m10-art`, `godot-p2-relics`. Earlier ones too.
  Cleanup optional: `git branch -d <name>`.

## Next work: ROADMAP2 Phase 3 — Fog of war

Per `ROADMAP2.md` (3.1 + 3.2): per-turn cached vision set (r3 ground / r4 fly +
r2 owned spires), dim overlay, hidden enemies, hover/forecast gating, skirmish
title toggle (default off); fair-AI fog (threat map / targeting filtered to
visible), the **Veilstone relic (+1 vision** — deferred from Phase 2, lands here),
fog-flagged map defs, cutaway reveals. Needs its OWN spec (brainstorm) → plan
(writing-plans) → subagent execution. Start a FRESH session for full context.

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
