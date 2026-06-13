# Objective Framework Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add win conditions beyond killing the enemy archon — `survive(n)`, `seize(hex)`, `protect(unit_id)`, `rout` — checked alongside the always-on archon-kill, with a topbar objective line and a rush/defend AI shift.

**Architecture:** A pure `core/objectives.gd` evaluates the active objective into a winner verdict; `GameState` holds `objective`/`objective_progress` and calls it from `check_win_condition`; the AI post-processes its weight profile per objective; the topbar shows the objective; saves round-trip it. One demo objective rides on a campaign mission.

**Tech Stack:** Godot 4 / GDScript. Harness tests in `godot/tests/run_tests.gd` (`_test_*` registered in `_initialize()`; helpers `_eq`/`_ok`/`_approx`/`_flat_state`; `GameState.new_skirmish(Maps.MAPS[0], seed)`). Gates: `pwsh -File godot/tests/run_tests.ps1` (`== N passed, 0 failed ==`, EXIT 0) and, after any scene/`main`/autoload change, `godot --headless --path godot --quit-after 30 2>&1 | Select-String "SCRIPT ERROR|Parse Error|Failed to load"` (no matches). **Never** add `-ExecutionPolicy Bypass` (classifier-blocked). Indentation is TABS.

**Spec:** `docs/superpowers/specs/2026-06-13-wraithspire-objectives-design.md`

---

## File structure

| File | Responsibility | Task |
|---|---|---|
| `core/objectives.gd` (new) | Pure `evaluate` + `label` | 1 |
| `core/game_state.gd` | `objective`/`objective_progress` fields, `unit_by_id`, `enemy_non_masters`, `check_win_condition` hook, `new_skirmish` copy | 1,2 |
| `core/save_game.gd` | Round-trip objective | 3 |
| `core/ai.gd` | `weights` objective tweak; seize check in `_apply_action` | 4,5 |
| `scenes/match/match_scene.gd` | Seize check on human move | 5 |
| `scenes/hud/top_bar.gd` | Objective line | 6 |
| `data/campaign.gd` | Demo objective on mission 2 | 7 |
| `godot/tests/run_tests.gd` | New `_test_*` | 1–4, 7 |

Tasks 1–4, 7 are pure/TDD (harness-gated). Tasks 5–6 are node integration (headless-boot-gated; behavior verified in the final windowed pass).

---

### Task 1: `core/objectives.gd` + GameState fields/helpers

**Files:**
- Create: `godot/core/objectives.gd`
- Modify: `godot/core/game_state.gd` (fields + 2 helpers)
- Modify: `godot/tests/run_tests.gd` (preload const, `_test_objectives`, register)

- [ ] **Step 1: Register preload + test call**

In `godot/tests/run_tests.gd`, after `const Vision = preload("res://core/vision.gd")` add:
```gdscript
const Objectives = preload("res://core/objectives.gd")
```
In `_initialize()`, after `_test_ai_fog_approach()` add:
```gdscript
	_test_objectives()
```

- [ ] **Step 2: Add GameState fields + helpers**

In `godot/core/game_state.gd`, after the three P3 fog member vars (`var revealed: Dictionary = {}`) add:
```gdscript
	var objective: Dictionary = {}           # P4.2: win condition beyond archon-kill ({} = none); saved
	var objective_progress: Dictionary = {}  # P4.2: survive start turn; saved
```
After the `master_of` function add:
```gdscript
## unit_by_id — first living unit with `id`, or null.
func unit_by_id(id: int) -> Variant:
	for u in units:
		if u["id"] == id and u["hp"] > 0:
			return u
	return null

## enemy_non_masters — living non-master units belonging to 1 - owner (for rout).
func enemy_non_masters(owner: int) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for u in alive_units(1 - owner):
		if not u.get("is_master", false):
			out.append(u)
	return out
```

- [ ] **Step 3: Write the failing test**

Append to `godot/tests/run_tests.gd`:
```gdscript
func _test_objectives() -> void:
	# empty objective -> no verdict.
	var gs := _flat_state(9, 9)
	_eq(Objectives.evaluate(gs), -1, "obj: empty -> -1")
	# survive: met only at/after start + turns.
	gs.objective = {"kind": "survive", "turns": 3}
	gs.objective_progress = {"start_turn": 1}
	gs.turn = 3
	_eq(Objectives.evaluate(gs), -1, "obj: survive not yet (turn 3, need start+3=4)")
	gs.turn = 4
	_eq(Objectives.evaluate(gs), 0, "obj: survive met")
	# seize: a player-0 unit on the target hex wins.
	var gz := _flat_state(9, 9)
	gz.objective = {"kind": "seize", "q": 5, "r": 5}
	_eq(Objectives.evaluate(gz), -1, "obj: seize empty hex -> -1")
	gz.spawn_unit("cinderling", 1, 5, 5)
	_eq(Objectives.evaluate(gz), -1, "obj: seize enemy-occupied -> -1")
	gz.units.clear()
	gz.spawn_unit("cinderling", 0, 5, 5)
	_eq(Objectives.evaluate(gz), 0, "obj: seize player-occupied -> 0")
	# protect: lose when the unit id is gone.
	var gp := _flat_state(9, 9)
	var ally := gp.spawn_unit("cinderling", 0, 2, 2)
	gp.objective = {"kind": "protect", "unit_id": ally["id"]}
	_eq(Objectives.evaluate(gp), -1, "obj: protect alive -> -1")
	ally["hp"] = 0
	_eq(Objectives.evaluate(gp), 1, "obj: protect dead -> 1 (player loses)")
	# rout: turn-2 guard, then win when enemy non-masters are cleared.
	var gr := _flat_state(9, 9)
	gr.objective = {"kind": "rout"}
	gr.spawn_master(1, 0, 0)
	var foe := gr.spawn_unit("cinderling", 1, 3, 3)
	gr.turn = 1
	_eq(Objectives.evaluate(gr), -1, "obj: rout turn-1 guard")
	gr.turn = 2
	_eq(Objectives.evaluate(gr), -1, "obj: rout with a live enemy -> -1")
	foe["hp"] = 0
	_eq(Objectives.evaluate(gr), 0, "obj: rout cleared -> 0")
	# label.
	var gl := _flat_state(9, 9)
	gl.objective = {"kind": "survive", "turns": 8}
	gl.objective_progress = {"start_turn": 1}
	gl.turn = 4
	_eq(Objectives.label(gl), "Survive: 3/8", "obj: survive label")
	_eq(Objectives.label(_flat_state(3, 3)), "", "obj: no objective -> empty label")
```

- [ ] **Step 4: Run to verify FAIL**

Run: `pwsh -File godot/tests/run_tests.ps1`
Expected: FAIL — `Objectives` not found / asserts fail.

- [ ] **Step 5: Create `godot/core/objectives.gd`**

```gdscript
class_name Objectives
extends RefCounted
## ROADMAP2 Phase 4.2 — mission objectives. Pure: evaluates the active objective on a
## GameState into a winner verdict, beside the always-on archon-kill. No node deps; reads
## the `state` param dynamically (no preload of game_state -> no cycle). The objective
## belongs to player 0. Shapes (JSON-safe): {"kind":"survive","turns":int},
## {"kind":"seize","q":int,"r":int}, {"kind":"protect","unit_id":int}, {"kind":"rout"}.

## evaluate — winner the objective implies: 0 (player 0 wins), 1 (player 0 loses),
## or -1 (no verdict — defer to the archon-kill check).
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
				return 1
		"rout":
			if state.turn >= 2 and state.enemy_non_masters(0).is_empty():
				return 0
	return -1

## label — topbar string for the active objective (with survive/rout progress), or "".
static func label(state) -> String:
	var obj: Dictionary = state.objective
	if obj.is_empty():
		return ""
	match obj.get("kind", ""):
		"survive":
			var start := int(state.objective_progress.get("start_turn", state.turn))
			var done: int = maxi(0, state.turn - start)
			return "Survive: %d/%d" % [done, int(obj["turns"])]
		"seize":
			return "Seize the marked hex"
		"protect":
			return "Protect your ally"
		"rout":
			return "Rout the enemy (%d left)" % state.enemy_non_masters(0).size()
	return ""
```

- [ ] **Step 6: Run to verify PASS**

Run: `pwsh -File godot/tests/run_tests.ps1`
Expected: PASS — `== N passed, 0 failed ==` (N = 919 + ~17).

- [ ] **Step 7: Commit**

```bash
git add godot/core/objectives.gd godot/core/game_state.gd godot/tests/run_tests.gd
git commit -m "[godot] P4.2 objectives: pure evaluate/label + GameState helpers"
```

---

### Task 2: `check_win_condition` integration + `new_skirmish` copy

**Files:**
- Modify: `godot/core/game_state.gd`
- Modify: `godot/tests/run_tests.gd` (`_test_objective_win`, register)

- [ ] **Step 1: Register the test**

In `_initialize()`, after `_test_objectives()` add:
```gdscript
	_test_objective_win()
```

- [ ] **Step 2: Write the failing test**

Append to `godot/tests/run_tests.gd`:
```gdscript
func _test_objective_win() -> void:
	# An objective win sets winner=0 with both masters alive.
	var gs := GameState.new_skirmish(Maps.MAPS[0], 42)
	gs.objective = {"kind": "rout"}
	gs.turn = 2   # enemy has no non-masters yet -> rout met (past the turn-1 guard)
	gs.check_win_condition()
	_eq(gs.winner, 0, "obj-win: rout sets winner 0")
	# Archon-kill still takes precedence and still works with no objective.
	var g2 := GameState.new_skirmish(Maps.MAPS[0], 42)
	g2.master_of(1)["hp"] = 0
	g2.check_win_condition()
	_eq(g2.winner, 0, "obj-win: archon-kill still wins")
	# protect-fail sets winner=1.
	var g3 := GameState.new_skirmish(Maps.MAPS[0], 42)
	var ally := g3.spawn_unit("cinderling", 0, 3, 3)
	g3.objective = {"kind": "protect", "unit_id": ally["id"]}
	g3.check_win_condition()
	_eq(g3.winner, -1, "obj-win: protect alive -> no winner")
	ally["hp"] = 0
	g3.check_win_condition()
	_eq(g3.winner, 1, "obj-win: protect dead -> player loses")
	# new_skirmish copies the def objective + stamps start_turn.
	var def := (Maps.MAPS[0] as Dictionary).duplicate(true)
	def["objective"] = {"kind": "survive", "turns": 5}
	var g4 := GameState.new_skirmish(def, 42)
	_eq(g4.objective.get("kind"), "survive", "obj-win: new_skirmish copies objective")
	_eq(int(g4.objective_progress.get("start_turn", -1)), 1, "obj-win: start_turn stamped")
	# A def with no objective -> empty (skirmish stays archon-kill).
	var g5 := GameState.new_skirmish(Maps.MAPS[0], 42)
	_eq(g5.objective, {}, "obj-win: no def objective -> empty")
```

- [ ] **Step 3: Run to verify FAIL**

Run: `pwsh -File godot/tests/run_tests.ps1`
Expected: FAIL — `obj-win: rout sets winner 0` (objective not yet wired into `check_win_condition`).

- [ ] **Step 4: Wire it**

In `godot/core/game_state.gd`, after the last `const` (`const Vision = preload("res://core/vision.gd")`) add:
```gdscript
const Objectives = preload("res://core/objectives.gd")
```
Replace `check_win_condition` with:
```gdscript
func check_win_condition() -> void:
	if winner != -1:
		return   # already decided
	for owner in [0, 1]:
		if master_of(owner) == null:
			winner = 1 - owner
			return
	var ow := Objectives.evaluate(self)
	if ow != -1:
		winner = ow
```
In `new_skirmish`, after the line `gs.stats = {"summoned": [0, 0], "lost": [0, 0], "battles": 0}` add:
```gdscript
	gs.objective = def.get("objective", {}).duplicate(true)
	gs.objective_progress = {"start_turn": gs.turn}
```

- [ ] **Step 5: Run to verify PASS**

Run: `pwsh -File godot/tests/run_tests.ps1`
Expected: PASS — `== N passed, 0 failed ==` (+7). Existing `_test_turn` win-condition asserts still pass (no objective on those states → `Objectives.evaluate` returns -1).

Run: `godot --headless --path godot --quit-after 30 2>&1 | Select-String "SCRIPT ERROR|Parse Error|Failed to load"` → no matches.

- [ ] **Step 6: Commit**

```bash
git add godot/core/game_state.gd godot/tests/run_tests.gd
git commit -m "[godot] P4.2 objectives: check_win_condition hook + new_skirmish copy"
```

---

### Task 3: Save round-trip

**Files:**
- Modify: `godot/core/save_game.gd`
- Modify: `godot/tests/run_tests.gd` (`_test_objective_save`, register)

- [ ] **Step 1: Register the test**

In `_initialize()`, after `_test_objective_win()` add:
```gdscript
	_test_objective_save()
```

- [ ] **Step 2: Write the failing test**

Append to `godot/tests/run_tests.gd`:
```gdscript
func _test_objective_save() -> void:
	var gs := GameState.new_skirmish(Maps.MAPS[0], 42)
	gs.objective = {"kind": "seize", "q": 3, "r": 4}
	gs.objective_progress = {"start_turn": 2}
	var blob := SaveGame.to_dict(gs)
	_eq(blob["objective"].get("kind"), "seize", "obj-save: objective serialized")
	var r := SaveGame.from_dict(blob)
	_eq(r.objective.get("kind"), "seize", "obj-save: objective restored")
	_eq(int(r.objective_progress.get("start_turn", -1)), 2, "obj-save: progress restored")
	# old blob without objective -> {}.
	blob.erase("objective")
	blob.erase("objective_progress")
	var r2 := SaveGame.from_dict(blob)
	_eq(r2.objective, {}, "obj-save: missing objective -> empty")
```

- [ ] **Step 3: Run to verify FAIL**

Run: `pwsh -File godot/tests/run_tests.ps1`
Expected: FAIL — `blob["objective"]` missing.

- [ ] **Step 4: Serialize**

In `godot/core/save_game.gd` `to_dict`, in the returned dict, after the `"fog": state.fog,` line add:
```gdscript
		"objective": state.objective.duplicate(true),
		"objective_progress": state.objective_progress.duplicate(true),
```
In `from_dict`, immediately before `return gs` (right after `gs.fog = bool(blob.get("fog", false))`) add:
```gdscript
	gs.objective = blob.get("objective", {})
	gs.objective_progress = blob.get("objective_progress", {})
```

- [ ] **Step 5: Run to verify PASS**

Run: `pwsh -File godot/tests/run_tests.ps1`
Expected: PASS (+4).

- [ ] **Step 6: Commit**

```bash
git add godot/core/save_game.gd godot/tests/run_tests.gd
git commit -m "[godot] P4.2 objectives: save round-trip"
```

---

### Task 4: AI rush/defend weight tweak

**Files:**
- Modify: `godot/core/ai.gd`
- Modify: `godot/tests/run_tests.gd` (`_test_objective_ai_weights`, register)

- [ ] **Step 1: Register the test**

In `_initialize()`, after `_test_objective_save()` add:
```gdscript
	_test_objective_ai_weights()
```

- [ ] **Step 2: Write the failing test**

Append to `godot/tests/run_tests.gd`:
```gdscript
func _test_objective_ai_weights() -> void:
	var gs := _flat_state(9, 9)
	gs.difficulty = "normal"
	# No objective -> identical to the profile.
	_eq(AI.weights(gs), AiProfiles.AI_PROFILES["normal"], "obj-ai: no objective -> profile unchanged")
	# survive -> approach * 1.5, atk_floor 0.
	var base_approach: float = float(AiProfiles.AI_PROFILES["normal"]["approach"])
	gs.objective = {"kind": "survive", "turns": 5}
	var w := AI.weights(gs)
	_approx(float(w["approach"]), base_approach * 1.5, "obj-ai: survive raises approach")
	_eq(int(w["atk_floor"]), 0, "obj-ai: survive zeroes atk_floor")
	# The const profile must NOT be mutated.
	_approx(float(AiProfiles.AI_PROFILES["normal"]["approach"]), base_approach, "obj-ai: profile not mutated")
```

- [ ] **Step 3: Run to verify FAIL**

Run: `pwsh -File godot/tests/run_tests.ps1`
Expected: FAIL — `obj-ai: survive raises approach` (approach unchanged).

- [ ] **Step 4: Implement the tweak**

In `godot/core/ai.gd`, replace `weights`:
```gdscript
static func weights(state) -> Dictionary:
	var base: Dictionary = AiProfiles.AI_PROFILES.get(state.difficulty, AiProfiles.AI_PROFILES["normal"])
	var obj: Dictionary = state.objective
	if obj.is_empty():
		return base
	var W := base.duplicate(true)
	match obj.get("kind", ""):
		"survive":              # player turtles a timer -> AI rushes
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

- [ ] **Step 5: Run to verify PASS**

Run: `pwsh -File godot/tests/run_tests.ps1`
Expected: PASS (+4). All existing `_test_ai_*` tests still pass (their states have empty `objective` → `weights` returns the base profile, byte-identical).

- [ ] **Step 6: Commit**

```bash
git add godot/core/ai.gd godot/tests/run_tests.gd
git commit -m "[godot] P4.2 objectives: rush/defend AI weight tweak"
```

---

### Task 5: Seize evaluation on move (AI + human)

**Files:**
- Modify: `godot/core/ai.gd` (`_apply_action`)
- Modify: `godot/scenes/match/match_scene.gd` (`_on_click` move branch)

No new harness test (the move runner / node path is boot-gated + verified in the windowed pass; `check_win_condition` itself is tested in Task 2).

- [ ] **Step 1: AI move triggers a seize check**

In `godot/core/ai.gd` `_apply_action`, the function ends with the `match action["kind"]: ... "wait": pass`. Immediately after the `match` block (as the function's last statement) add:
```gdscript
	state.check_win_condition()
```

- [ ] **Step 2: Human move triggers a seize check**

In `godot/scenes/match/match_scene.gd` `_on_click`, find the move block that ends with the pickup handling, currently:
```gdscript
				var got := state.pick_up_relic(selected)
				if got != "":
					Audio.beep(720.0, 0.08, "triangle", 0.2)
					_refresh_fog()
					board.queue_redraw()
					info_card.show_unit(selected)
				_open_menu_for(selected)
				return
```
Replace it with:
```gdscript
				var got := state.pick_up_relic(selected)
				if got != "":
					Audio.beep(720.0, 0.08, "triangle", 0.2)
					_refresh_fog()
					board.queue_redraw()
					info_card.show_unit(selected)
				state.check_win_condition()
				if state.winner != -1:
					_finish_action()
					_end_match()
					return
				_open_menu_for(selected)
				return
```

- [ ] **Step 3: Run the gates**

Run: `godot --headless --path godot --quit-after 30 2>&1 | Select-String "SCRIPT ERROR|Parse Error|Failed to load"` → no matches.
Run: `pwsh -File godot/tests/run_tests.ps1` → `== N passed, 0 failed ==` (unchanged; existing AI-turn tests still pass — `check_win_condition` with no objective only checks masters, same as before).

- [ ] **Step 4: Commit**

```bash
git add godot/core/ai.gd godot/scenes/match/match_scene.gd
git commit -m "[godot] P4.2 objectives: evaluate seize immediately on move"
```

---

### Task 6: Topbar objective line

**Files:**
- Modify: `godot/scenes/hud/top_bar.gd`

Verified by the headless boot + windowed pass (`Objectives.label` itself is unit-tested in Task 1).

- [ ] **Step 1: Preload Objectives**

In `godot/scenes/hud/top_bar.gd`, after the `const PLAYER_NAMES := [...]` line add:
```gdscript
const Objectives = preload("res://core/objectives.gd")
```

- [ ] **Step 2: Append the objective to the label**

In `refresh`, replace the final line:
```gdscript
	_label.text = "Turn %d   %s   Weather: %s   MP: %d" % [state.turn, who, weather_key, mp]
```
with:
```gdscript
	var base := "Turn %d   %s   Weather: %s   MP: %d" % [state.turn, who, weather_key, mp]
	var obj := Objectives.label(state)
	_label.text = base if obj == "" else base + "   |   " + obj
```

- [ ] **Step 3: Run the gates**

Run: `godot --headless --path godot --quit-after 30 2>&1 | Select-String "SCRIPT ERROR|Parse Error|Failed to load"` → no matches.
Run: `pwsh -File godot/tests/run_tests.ps1` → unchanged green.

- [ ] **Step 4: Commit**

```bash
git add godot/scenes/hud/top_bar.gd
git commit -m "[godot] P4.2 objectives: topbar objective line"
```

---

### Task 7: Demo objective on campaign mission 2

**Files:**
- Modify: `godot/data/campaign.gd`
- Modify: `godot/tests/run_tests.gd` (`_test_objective_campaign`, register)

- [ ] **Step 1: Register the test**

In `_initialize()`, after `_test_objective_ai_weights()` add:
```gdscript
	_test_objective_campaign()
```

- [ ] **Step 2: Write the failing test**

Append to `godot/tests/run_tests.gd`:
```gdscript
func _test_objective_campaign() -> void:
	var gs := GameState.new_campaign(Campaign.CAMPAIGN[1], 1)
	_eq(gs.objective.get("kind"), "survive", "obj-campaign: mission 2 has a survive objective")
	_eq(int(gs.objective["turns"]), 8, "obj-campaign: survive 8 turns")
	_eq(int(gs.objective_progress.get("start_turn", -1)), 1, "obj-campaign: start_turn stamped")
```

- [ ] **Step 3: Run to verify FAIL**

Run: `pwsh -File godot/tests/run_tests.ps1`
Expected: FAIL — `obj-campaign: mission 2 has a survive objective` (objective absent).

- [ ] **Step 4: Add the demo objective**

In `godot/data/campaign.gd`, mission index 1 ("The Drowned Marches"), its `"map"` dict line currently ends:
```gdscript
	         "mountains": 1, "lakes": 8, "forests": 12, "hills": 6, "towers": 5, "relics": 2},
```
Change it to (add the objective key before the closing brace):
```gdscript
	         "mountains": 1, "lakes": 8, "forests": 12, "hills": 6, "towers": 5, "relics": 2,
	         "objective": {"kind": "survive", "turns": 8}},
```

- [ ] **Step 5: Run to verify PASS**

Run: `pwsh -File godot/tests/run_tests.ps1`
Expected: PASS (+3). `_test_data` / `_test_new_campaign` still pass (the objective key is additive; `CAMPAIGN.size()` is unchanged at 4).

Run: `godot --headless --path godot --quit-after 30 2>&1 | Select-String "SCRIPT ERROR|Parse Error|Failed to load"` → no matches.

- [ ] **Step 6: Commit**

```bash
git add godot/data/campaign.gd godot/tests/run_tests.gd
git commit -m "[godot] P4.2 objectives: demo survive objective on mission 2"
```

---

### Task 8: Whole-milestone review + manual windowed pass

**Files:** none (review only).

- [ ] **Step 1: Whole-milestone code review**

Dispatch an opus review over `git diff main...godot-p4-objectives -- godot/`. Focus: objectives purity (no state mutation); determinism (no-objective paths byte-identical — AI weights identity + existing win-condition tests prove it); `check_win_condition` ordering (archon-kill precedence preserved); the `rout` turn-2 guard; no `AI_PROFILES` mutation; save round-trip; seize-on-move not double-ending the match (`_match_over` guard).

- [ ] **Step 2: Both gates one final time**

Run: `pwsh -File godot/tests/run_tests.ps1` → `== N passed, 0 failed ==`, EXIT 0.
Run: `godot --headless --path godot --quit-after 30 2>&1 | Select-String "SCRIPT ERROR|Parse Error|Failed to load"` → no matches.

- [ ] **Step 3: Manual windowed pass** (`godot --path godot`, needs a display)

- Campaign → mission 2 "The Drowned Marches" → topbar shows "Survive: x/8"; survive 8 rounds → you win (gameover, AZURE) even without killing the enemy archon.
- Killing the enemy archon still wins immediately (any match).
- A no-objective skirmish behaves exactly as before (no objective line).
- (If a seize/protect/rout test mission is added later, verify those; not in this slice.)

- [ ] **Step 4: Roadmap check-off + handoff**

Tick ROADMAP2 item 4.2 in `ROADMAP2.md`; update `SESSION_STATE.md` + `HANDOFF.md` (Phase 4.2 done; next = 4.1 evolutions, which needs sprite generation, or 4.3). Update auto-memory. Commit:
```bash
git add ROADMAP2.md SESSION_STATE.md HANDOFF.md
git commit -m "[godot] P4.2 objectives complete: roadmap check-off + handoff"
```
FF-merge to `main` + push only after the user approves.

---

## Self-review

**Spec coverage:**
- Pure `objectives.gd` evaluate+label → Task 1. ✓
- 4 kinds (survive/seize/protect/rout) + rout turn-2 guard → Task 1 (tested). ✓
- GameState fields + helpers + `check_win_condition` hook + `new_skirmish` copy → Tasks 1–2. ✓
- Archon-kill precedence preserved → Task 2 (tested). ✓
- Save round-trip → Task 3. ✓
- AI rush/defend tweak (duplicate-before-mutate, no-objective identity) → Task 4. ✓
- Seize immediate trigger on move → Task 5. ✓
- Topbar objective line → Task 6. ✓
- Demo objective on campaign mission 2; skirmish stays archon-kill → Tasks 2 (no-def-objective test) + 7. ✓
- Gameover unchanged → no task needed (winner stays a player id). ✓

**Placeholder scan:** none — every code step is complete. Multiplier values are concrete (1.5 / +0.3 / 1.3).

**Type consistency:** `Objectives.evaluate(state) -> int` (0/1/-1) and `Objectives.label(state) -> String` used consistently in `check_win_condition` (Task 2) and `top_bar` (Task 6). `state.objective: Dictionary`, `state.objective_progress: Dictionary`, `unit_by_id(int) -> Variant`, `enemy_non_masters(int) -> Array[Dictionary]`. Objective dict keys (`kind`/`turns`/`q`/`r`/`unit_id`) consistent across evaluate, label, tests, save, and the campaign def. AI `weights` duplicates before mutating. All aligned.
