# Wraithspire — Objective Framework (ROADMAP2 Phase 4.2) — design

Date: 2026-06-13. Branch: `godot-p4-objectives` (off `main`). First slice of the
Phase 4 "content wave" (decomposed: 4.2 objectives is pure code; 4.1 evolutions and
4.3 bosses/maps carry a sprite-generation dependency and come later). Godot port; the
JS build at repo root is the frozen reference and is **not** touched.

## Goal

Win conditions beyond killing the enemy archon: `survive(n)`, `seize(hex)`,
`protect(unit_id)`, `rout`. The objective belongs to player 0 and is checked alongside
the always-on archon-kill condition; the topbar shows the active objective; the AI
shifts toward rush-or-defend per objective. This framework is the foundation Phases 5
(missions) and 7 (gauntlet) build on.

## Decisions (locked)

- **AI reaction = a bounded rush/defend weight tweak** (post-process on the difficulty
  profile), not per-target AI behavior.
- **`seize` triggers when any player-0 unit occupies the target hex** (not tower capture).
- **Scope = framework + one demo objective on a campaign mission**; skirmish maps stay
  archon-kill. Real objective content lands with Phase 5 missions.

## Architecture

### 1. `core/objectives.gd` — new pure module (`class_name Objectives`)

No node deps, no preloads from `game_state` (reads the `state` param dynamically — no
cycle). Mirrors the `vision.gd`/`relics.gd` pure-helper pattern.

```
## evaluate — the winner the objective implies: 0 (player 0 wins), 1 (player 0 loses),
## or -1 (no objective verdict — defer to the archon-kill check). Pure.
static func evaluate(state) -> int:
    var obj: Dictionary = state.objective
    if obj.is_empty():
        return -1
    match obj.get("kind", ""):
        "survive":
            var start := int(state.objective_progress.get("start_turn", state.turn))
            if state.turn - start >= int(obj["turns"]):
                return 0
        "seize":
            var u = state.unit_at(int(obj["q"]), int(obj["r"]))
            if u != null and u["owner"] == 0:
                return 0
        "protect":
            if state.unit_by_id(int(obj["unit_id"])) == null:
                return 1   # the protected unit died -> player 0 loses
        "rout":
            if state.turn >= 2 and state.enemy_non_masters(0).is_empty():
                return 0
    return -1

## label — the topbar string for the active objective (with survive/rout progress),
## or "" when there is none.
static func label(state) -> String
```

- `label` examples: `"Survive: 3/8"`, `"Seize the marked hex"`, `"Protect your ally"`,
  `"Rout the enemy (2 left)"`, `""` when no objective.
- **`rout` turn-2 guard**: at match start player 1 has only its master (no non-masters),
  which would trivially satisfy `rout`. The `turn >= 2` gate avoids the turn-1 win; rout
  missions pre-place an enemy army (via `ai_summons`), so by the time the count hits 0
  the match is well past turn 1. Documented simplification.

### 2. `GameState` additions (`core/game_state.gd`)

- `var objective: Dictionary = {}` — `{}` = none (pure archon-kill; current behavior).
  JSON-safe shapes: `{"kind":"survive","turns":int}`, `{"kind":"seize","q":int,"r":int}`,
  `{"kind":"protect","unit_id":int}`, `{"kind":"rout"}`.
- `var objective_progress: Dictionary = {}` — `survive` start turn (`{"start_turn": int}`).
- Two helpers:
  - `func unit_by_id(id: int) -> Variant` — first living unit with that id, else null.
  - `func enemy_non_masters(owner: int) -> Array[Dictionary]` — living non-master units of
    `1 - owner`.
- `check_win_condition` calls `Objectives.evaluate(self)` **after** the master-death check:

```
func check_win_condition() -> void:
    if winner != -1:
        return
    for owner in [0, 1]:
        if master_of(owner) == null:
            winner = 1 - owner
            return
    var ow := Objectives.evaluate(self)
    if ow != -1:
        winner = ow
```

- `new_skirmish` copies the def's objective onto the state and stamps the survive start
  turn — and it is the **single copy point**, since `new_campaign` builds its state by
  calling `new_skirmish(scenario["map"], …)`, so a campaign mission's objective rides on
  its **map def** and flows through automatically:

```
gs.objective = def.get("objective", {}).duplicate(true)
gs.objective_progress = {"start_turn": gs.turn}
```

  Skirmish map defs carry no objective, so skirmish stays archon-kill.

### 3. Evaluation timing — where `check_win_condition` runs

The existing call sites (`end_turn`, `combat.resolve_attack`, `ability_resolve` quake,
`status.tick_statuses`) already cover **survive** (turn end), **rout** and **protect**
(death events). Only **seize** is move-driven, so add a `check_win_condition()` call after
the two position-commit paths:

- AI: end of `AI._apply_action` for the `move`/`capture` cases (`state.check_win_condition()`).
- Human: after the move slide + relic pickup completes in `match_scene._on_click`, and after
  a capture in `_on_action_chosen`. If `state.winner != -1` there, route to `_end_match()`
  (idempotent via the existing `_match_over` guard).

### 4. Fair-ish AI shift (`core/ai.gd` `weights`)

`weights` currently returns the const profile dict directly. The objective tweak must
**duplicate before mutating** (never mutate `AI_PROFILES`), and must be a no-op when there
is no objective so non-objective matches stay byte-identical (determinism + existing AI
tests preserved):

```
static func weights(state) -> Dictionary:
    var base: Dictionary = AiProfiles.AI_PROFILES.get(state.difficulty, AiProfiles.AI_PROFILES["normal"])
    var obj: Dictionary = state.objective
    if obj.is_empty():
        return base
    var W := base.duplicate(true)
    match obj.get("kind", ""):
        "survive":              # player is turtling out a timer -> AI rushes
            W["approach"] = float(W["approach"]) * 1.5
            W["atk_floor"] = 0
        "seize":                # player rushes a hex -> AI holds ground
            W["threat_safe"] = float(W["threat_safe"]) + 0.3
            W["threat_hurt"] = float(W["threat_hurt"]) + 0.3
        "protect":              # AI pressures
            W["approach"] = float(W["approach"]) * 1.3
        "rout":
            pass
    return W
```

(Multiplier values are reasonable defaults, tunable during implementation.)

### 5. Topbar (`scenes/hud/top_bar.gd`)

`refresh(state)` appends the objective to the single status label on the same line when
`Objectives.label(state)` is non-empty:
`"Turn N   FACTION   Weather: k   MP: X   |   <objective label>"`. No layout change.

### 6. Save (`core/save_game.gd`)

`to_dict` writes `"objective": state.objective` and `"objective_progress":
state.objective_progress` (both plain JSON-safe dicts). `from_dict` restores them with
`{}` defaults for old blobs. Re-coerce numeric fields where needed (JSON ints→floats):
`turns`/`q`/`r`/`unit_id`/`start_turn` read through `int(...)` at use sites already, so no
special coercion beyond reading them as `int`.

### 7. Demo + defs (`data/campaign.gd`, optional `data/maps.gd`)

- Add an optional `objective` to map/campaign defs (plain dict).
- **Demo**: attach `{"kind":"survive","turns":8}` to campaign mission 2 ("The Drowned
  Marches") as an **additional** win path — you can still win by archon-kill; holding out
  8 rounds is an alternate victory. Non-invasive (additive key), exercises the framework
  end-to-end in-game. Phase 5 reworks campaign content properly.
- Skirmish defs unchanged (archon-kill).

### 8. Gameover

Unchanged — `state.winner` is still a player id, so the existing gameover screen and the
`match_ended`/`on_match_won` chain work as-is. (A "win reason" line is a later nicety, not
in this slice.)

## Data-model deltas

| Where | Field | Notes |
|---|---|---|
| `GameState` | `objective: Dictionary` | saved; `{}` = none |
| `GameState` | `objective_progress: Dictionary` | saved; survive start turn |
| map/campaign defs | `"objective"` (optional) | per-mission goal |

## Testing (harness-first, TDD)

`core/objectives.gd` + `GameState` helpers are fully harness-testable
(`pwsh -File godot/tests/run_tests.ps1`):

- `Objectives.evaluate`:
  - survive: not met before `start+turns`; met at/after; uses `objective_progress.start_turn`.
  - seize: met when a player-0 unit sits on (q,r); not met when empty or enemy-occupied.
  - protect: returns 1 once the unit id is gone; -1 while it lives.
  - rout: -1 on turn 1 even with no enemy non-masters (guard); 0 once the enemy army is
    cleared on turn ≥ 2; -1 while an enemy non-master lives.
  - empty objective → -1.
- `check_win_condition` integration: an objective win sets `winner = 0`; a protect-fail
  sets `winner = 1`; **archon-death still takes precedence / still works**; with no
  objective, behavior is unchanged.
- Helpers: `unit_by_id` (hit/miss/dead), `enemy_non_masters` (excludes master + dead).
- AI `weights`: with no objective, returns the profile **unchanged** (identity — guards the
  existing AI determinism); with an objective, returns a duplicated, tweaked dict and the
  const `AI_PROFILES` is **not** mutated.
- Save round-trip: `objective` + `objective_progress` survive `to_dict`/`from_dict`; old
  blob without them loads as `{}`.

Headless boot gate after any scene/`main`/autoload change:
`godot --headless --path godot --quit-after 30 2>&1 | Select-String
"SCRIPT ERROR|Parse Error|Failed to load"` → no matches. Topbar/match_scene wiring verified
by the final windowed pass.

## Out of scope / accepted divergences

- AI reaction is a weight tweak only — no per-target hunting/garrisoning (a later polish).
- `rout` uses a turn-2 guard rather than tracking "enemy ever had units."
- `protect` resolves its `unit_id` from the def/match-setup; the demo uses `survive`, so
  protect's mission placement is exercised only by harness tests in this slice.
- One demo objective on an existing campaign mission (additive alternate win); full
  objective-driven missions are Phase 5.
- No gameover "win reason" line yet.

## Build order (for the plan)

1. `core/objectives.gd` (`evaluate` + `label`) + `GameState` helpers (`unit_by_id`,
   `enemy_non_masters`) + tests.
2. `GameState.objective`/`objective_progress` + `check_win_condition` integration +
   `new_skirmish`/`new_campaign` copy + tests.
3. Save round-trip + tests.
4. AI `weights` objective tweak + tests (incl. no-objective identity + no-mutation).
5. Seize evaluation timing: `check_win_condition` after AI `_apply_action` move/capture and
   after human move/capture commit (+ `_end_match` routing).
6. Topbar objective line.
7. Demo objective on campaign mission 2 + def plumbing.
8. Whole-milestone review + manual windowed pass.
