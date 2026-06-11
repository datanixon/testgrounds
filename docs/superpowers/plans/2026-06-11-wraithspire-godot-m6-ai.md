# Wraithspire Godot Port — Milestone 6: AI (threat map + decision tree + summon economy) — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax.

**Goal:** Port the enemy AI — a per-turn threat map, a scored decision tree (kill → retreat → instant ability → capture → attack → move), the summon economy, and a synchronous turn-runner — into the pure Godot core, then wire it so the AI plays player 1's turn when the human ends theirs.

**Architecture:** All AI lives in one new `core/ai.gd` (class `AI`) — the designated **C#-swap seam**, kept behind a clean interface that only reads a `GameState` + the pure query/combat modules. The SCORING/DECISION functions (`build_threat_map`, `score_attacks`, `decide_unit_action`, `score_instant_ability`) are pure reads (a candidate end-tile is scored via a duplicated probe unit, NOT by mutating the real unit). A thin `take_turn(state)` runner applies the decided actions by mutating state. Because M4 resolved combat INLINE (no cutaway until M8), the JS `setTimeout`-step-chain + battle-flag polling collapses into a plain synchronous loop — this is the one control-flow simplification the design spec anticipated.

**Tech Stack:** GDScript, the headless harness (`pwsh -ExecutionPolicy Bypass -File godot/tests/run_tests.ps1`). Reference: `game.js` — AI_PROFILES (1100–1131), aiW (1135–1137), buildThreatMap (1143–1162), aiRetreatNode (1176–1189), aiTakeTurn (1191–1215), aiActUnit decision tree (1217–1349), aiTrySummons (1357–1421), findSummonSlot (1423–1434), aiScoreInstantAbility (5822–5849).

**Scope note:** M6 ports the AI LOGIC + a synchronous runner + minimal wiring (AI plays player 1 on the human's end-turn). The DIFFICULTY-SELECT UI (title screen) is **M9**; M6 adds a `GameState.difficulty` field defaulting to `"normal"` and the AI reads it. The battle CUTAWAY is **M8** — M6 combat resolves inline (so the runner needs no coroutine yet; the JS animation-awaiting is the only thing deferred). The action MENU + summon-list UI is **M7** — M6 keeps the temp debug keys. Determinism: the `normal`/`hard` profiles use NO randomness (scoreJitter 0, randomSummons false); the `easy` profile's jitter/random-summon route through `state.rng`, so a seeded match is reproducible. Tests use `normal` (deterministic).

---

## File structure (this milestone)

```
godot/data/ai_profiles.gd     const AI_PROFILES (easy/normal/hard) + DIFFICULTIES   [class AiProfiles]
godot/core/ai.gd              the whole AI: weights, threat map, scoring, decision   [class AI]
                              tree, summon economy, find_summon_slot, take_turn runner
godot/core/game_state.gd      + var difficulty := "normal"                           [MODIFY]
godot/scenes/main.gd          Enter → end_turn; if AI's turn (player 1) run AI.take_turn then end_turn  [MODIFY]
godot/tests/run_tests.gd      + _test_ai_profiles, _test_threat_map, _test_ai_helpers,
                              _test_ai_attack, _test_ai_decision, _test_ai_summons, _test_ai_turn  [MODIFY]
ROADMAP_GODOT.md              check off M6
```

**Action dict shape** (what `decide_unit_action` returns; what `take_turn` applies):
- `{"kind": "attack", "dest": Vector2i, "target_id": int, "ab": Variant}` — move to dest, then `resolve_attack` vs the unit with `target_id`; if `ab` is non-null, set cd + pass its status (already downgraded to null on a predicted kill).
- `{"kind": "instant", "ab": Dictionary}` — `resolve_instant` at the current hex, set cd.
- `{"kind": "capture", "dest": Vector2i}` — move to dest, capture the tower there.
- `{"kind": "move", "dest": Vector2i}` — move-only to dest.
- `{"kind": "wait"}` — do nothing.

---

## Task 1: AI_PROFILES data + GameState.difficulty + weights()

Port the three difficulty profiles and the selector. Add a `difficulty` field to `GameState` (default `"normal"`).

**Files:** Create `godot/data/ai_profiles.gd`; Modify `godot/core/game_state.gd`, `godot/tests/run_tests.gd`.

- [ ] **Step 1: Add failing tests to `godot/tests/run_tests.gd`**

Add a preload (with the data preloads):
```gdscript
const AiProfiles = preload("res://data/ai_profiles.gd")
const AI = preload("res://core/ai.gd")
```
Add the call in `_initialize`, after `_test_blink()`:
```gdscript
	_test_ai_profiles()
```
Append:
```gdscript
func _test_ai_profiles() -> void:
	_eq(AiProfiles.AI_PROFILES.size(), 3, "ai_profiles: 3 difficulties")
	_eq(AiProfiles.DIFFICULTIES, ["easy", "normal", "hard"], "ai_profiles: difficulty order")
	_eq(AiProfiles.AI_PROFILES["normal"]["kill_bonus"], 30, "ai_profiles: normal kill_bonus")
	_eq(AiProfiles.AI_PROFILES["hard"]["master_bonus"], 26, "ai_profiles: hard master_bonus")
	_eq(AiProfiles.AI_PROFILES["easy"]["random_summons"], true, "ai_profiles: easy random summons")
	_eq(AiProfiles.AI_PROFILES["normal"]["random_summons"], false, "ai_profiles: normal not random")
	# GameState defaults to normal; weights() reads it.
	var gs := GameState.new_skirmish(Maps.MAPS[0], 42)
	_eq(gs.difficulty, "normal", "ai_profiles: state defaults normal")
	_eq(AI.weights(gs)["kill_bonus"], 30, "ai_profiles: weights() picks the state profile")
	gs.difficulty = "hard"
	_eq(AI.weights(gs)["kill_bonus"], 40, "ai_profiles: weights() follows difficulty")
```

- [ ] **Step 2: Run — verify it fails (ai_profiles.gd / ai.gd missing)**
```
pwsh -ExecutionPolicy Bypass -File godot/tests/run_tests.ps1; "EXIT=$LASTEXITCODE"
```
Expected: load error about `res://data/ai_profiles.gd` (or `res://core/ai.gd`), non-zero EXIT.

- [ ] **Step 3: Create `godot/data/ai_profiles.gd`, verbatim** (port of game.js 1100–1131; JS camelCase → snake_case):
```gdscript
class_name AiProfiles
extends RefCounted
## Port of game.js AI_PROFILES (sec. 8). Difficulty swaps the weight profile without
## touching the AI logic. easy = threat-blind, no retreat, jittered, random summons (v1
## feel); normal = the tuned brain; hard = accepts trades, hunts kills/archon, retreats
## earlier. JS camelCase keys -> snake_case.

const AI_PROFILES := {
	"easy": {
		"kill_bonus": 18, "master_bonus": 10, "focus_fire": 3,
		"counter_risk": 0.3, "counter_death": 5, "terrain_def": 0.5,
		"threat_safe": 0.0, "threat_hurt": 0.0, "approach": 1.0,
		"capture_bonus": 18, "retreat_hp_frac": 0.0, "atk_floor": 0,
		"score_jitter": 6, "random_summons": true,
	},
	"normal": {
		"kill_bonus": 30, "master_bonus": 18, "focus_fire": 10,
		"counter_risk": 0.8, "counter_death": 25, "terrain_def": 2.0,
		"threat_safe": 0.35, "threat_hurt": 1.1, "approach": 1.2,
		"capture_bonus": 26, "retreat_hp_frac": 0.35, "atk_floor": 0,
		"score_jitter": 0, "random_summons": false,
	},
	"hard": {
		"kill_bonus": 40, "master_bonus": 26, "focus_fire": 16,
		"counter_risk": 0.45, "counter_death": 12, "terrain_def": 2.0,
		"threat_safe": 0.3, "threat_hurt": 0.9, "approach": 1.7,
		"capture_bonus": 26, "retreat_hp_frac": 0.28, "atk_floor": -3,
		"score_jitter": 0, "random_summons": false,
	},
}

const DIFFICULTIES := ["easy", "normal", "hard"]
```

- [ ] **Step 4: Add `difficulty` to `godot/core/game_state.gd`** — add this var with the other vars (near `var winner`):
```gdscript
var difficulty := "normal"    # AI weight profile (easy/normal/hard); difficulty-select UI is M9
```

- [ ] **Step 5: Create `godot/core/ai.gd` with JUST the `weights` function (the rest lands in later tasks), verbatim:**
```gdscript
class_name AI
extends RefCounted
## Enemy AI — threat map + scored decision tree + summon economy (port of game.js
## sec. 8). The designated C#-swap seam: every function reads a GameState plus the
## pure query/combat modules and returns intended actions; take_turn() is the thin
## runner that applies them. Scoring is side-effect-free (candidate tiles are scored
## via a duplicated probe unit, never by mutating the real unit).

const AiProfiles = preload("res://data/ai_profiles.gd")

## weights — the active difficulty's weight profile (defaults to normal).
static func weights(state) -> Dictionary:
	return AiProfiles.AI_PROFILES.get(state.difficulty, AiProfiles.AI_PROFILES["normal"])
```

- [ ] **Step 6: Run — verify pass**
```
pwsh -ExecutionPolicy Bypass -File godot/tests/run_tests.ps1; "EXIT=$LASTEXITCODE"
```
Expected: green, `EXIT=0`. Baseline `279 passed`; ~10 new → ~289. `0 failed` is the gate.

- [ ] **Step 7: Commit**
```
git add godot/data/ai_profiles.gd godot/core/ai.gd godot/core/game_state.gd godot/tests/run_tests.gd
git commit -m "[godot] M6: AI_PROFILES data + GameState.difficulty + AI.weights"
```

---

## Task 2: Threat map + AI helpers (summon slot, retreat node, instant scoring)

Port the pure read-only helpers: `build_threat_map`, `find_summon_slot`, `_retreat_node`, `score_instant_ability`. None mutate state.

**Files:** Modify `godot/core/ai.gd`, `godot/tests/run_tests.gd`.

- [ ] **Step 1: Add failing tests to `godot/tests/run_tests.gd`**

Add the call after `_test_ai_profiles()`:
```gdscript
	_test_ai_helpers()
```
Append:
```gdscript
func _test_ai_helpers() -> void:
	# threat map: a lone enemy contributes its power to every tile it could attack.
	var gs := _flat_state(9, 9)
	var foe := gs.spawn_unit("cinderling", 1, 4, 4)   # power 5, move 4, range 1
	var threat := AI.build_threat_map(gs, 0)           # threat to player 0 from player 1
	# the foe's own tile is reachable; a tile adjacent to it is threatened (>=5).
	_ok(threat.get("5,4", 0) >= 5, "threat: adjacent tile threatened by foe power")
	# a far tile (distance > move+range) is unthreatened.
	_eq(threat.get("0,0", 0), 0, "threat: far tile not threatened")
	# two enemies stack on a shared tile.
	gs.spawn_unit("cinderling", 1, 6, 4)
	var threat2 := AI.build_threat_map(gs, 0)
	_ok(threat2.get("5,4", 0) >= 10, "threat: two foes stack")
	# find_summon_slot: first free non-blocking neighbor of the master.
	var gs2 := GameState.new_skirmish(Maps.MAPS[0], 42)
	var m := gs2.master_of(0)
	var slot = AI.find_summon_slot(gs2, m)
	_ok(slot != null, "summon-slot: found a free neighbor")
	_eq(Hex.distance(slot, Vector2i(m["q"], m["r"])), 1, "summon-slot: adjacent to master")
	_ok(gs2.unit_at(slot.x, slot.y) == null, "summon-slot: empty")
	# score_instant_ability: a quaker with two adjacent enemies wants to quake.
	var gq := _flat_state(7, 7)
	var ogre := gq.spawn_unit("geomaul", 0, 3, 3)       # quake (target none)
	gq.spawn_unit("cinderling", 1, 4, 3)
	gq.spawn_unit("galewisp", 1, 3, 4)
	var inst = AI.score_instant_ability(gq, ogre)
	_ok(inst != null and inst["score"] > 0, "instant-score: quake scored with 2 adjacent enemies")
	# a quaker with no adjacent enemy scores nothing.
	var gq2 := _flat_state(7, 7)
	var lone := gq2.spawn_unit("geomaul", 0, 3, 3)
	_eq(AI.score_instant_ability(gq2, lone), null, "instant-score: no targets -> null")
	# an enemy-target ability (cinderling/ignite) is NOT an instant -> null.
	_eq(AI.score_instant_ability(gq2, gq2.spawn_unit("cinderling", 0, 1, 1)), null, "instant-score: enemy-target ability not instant")
```

- [ ] **Step 2: Run — verify it fails (build_threat_map missing)**
```
pwsh -ExecutionPolicy Bypass -File godot/tests/run_tests.ps1; "EXIT=$LASTEXITCODE"
```
Expected: error about `AI.build_threat_map`, non-zero EXIT.

- [ ] **Step 3: Add preloads + the four helpers to `godot/core/ai.gd`.** Add these preloads under `const AiProfiles = ...`:
```gdscript
const Hex = preload("res://core/hex.gd")
const Terrain = preload("res://data/terrain.gd")
const Pathfinding = preload("res://core/pathfinding.gd")
const Abilities = preload("res://data/abilities.gd")
const Status = preload("res://core/status.gd")
```
Then append (port of buildThreatMap 1143–1162, findSummonSlot 1423–1434, aiRetreatNode 1176–1189, aiScoreInstantAbility 5822–5849):
```gdscript

## build_threat_map — total potential enemy damage onto every tile: each enemy of the
## OTHER player expands its reachable tiles by its attack range; one enemy contributes
## its power at most once per tile, separate enemies stack. Returns { "q,r": int }.
static func build_threat_map(state, owner: int) -> Dictionary:
	var threat := {}
	for e in state.alive_units(1 - owner):
		var seen := {}
		var reach := Pathfinding.compute_reachable(state, e)
		for k in reach:
			var node: Dictionary = reach[k]
			for n1 in Hex.neighbors(Vector2i(node["q"], node["r"])):
				_threat_mark(threat, seen, n1, e["power"])
				if e["range"] >= 2:
					for n2 in Hex.neighbors(n1):
						_threat_mark(threat, seen, n2, e["power"])
	return threat

static func _threat_mark(threat: Dictionary, seen: Dictionary, p: Vector2i, power: int) -> void:
	var k := Hex.key(p)
	if seen.has(k):
		return
	seen[k] = true
	threat[k] = threat.get(k, 0) + power

static func threat_at(threat: Dictionary, q: int, r: int) -> int:
	return threat.get(Hex.key(Vector2i(q, r)), 0)

## find_summon_slot — first free, non-blocking, non-mountain neighbor of the master.
static func find_summon_slot(state, master: Dictionary) -> Variant:
	for n in Hex.neighbors(Vector2i(master["q"], master["r"])):
		if not state.in_bounds(n.x, n.y):
			continue
		var cell: Variant = state.cell_at(n.x, n.y)
		if cell == null:
			continue
		if Terrain.TERRAIN[cell["terrain"]].get("blocks", false):
			continue
		if cell["terrain"] == "mountain":
			continue
		if state.unit_at(n.x, n.y) != null:
			continue
		return n
	return null

## _retreat_node — best reachable tile for a wounded unit: near an owned heal tile
## (tower/castle), low threat, decent cover. Returns the reach node dict, or null.
static func _retreat_node(state, unit: Dictionary, reach: Dictionary, threat: Dictionary) -> Variant:
	var heals: Array[Vector2i] = []
	for k in state.map["cells"]:
		var c: Dictionary = state.map["cells"][k]
		if (c["terrain"] == "tower" or c["terrain"] == "castle") and c.get("owner", -1) == unit["owner"]:
			heals.append(Vector2i(c["q"], c["r"]))
	var best: Variant = null
	var best_score := INF
	for k in reach:
		var node: Dictionary = reach[k]
		var np := Vector2i(node["q"], node["r"])
		var d_heal := 0
		if not heals.is_empty():
			d_heal = 9999
			for h in heals:
				d_heal = mini(d_heal, Hex.distance(np, h))
		var tdef: int = Terrain.TERRAIN[state.cell_at(np.x, np.y)["terrain"]]["def"]
		var s: float = d_heal * 2 + threat_at(threat, np.x, np.y) * 1.5 - tdef * 1.5
		if s < best_score:
			best_score = s
			best = node
	return best

## score_instant_ability — score firing the unit's instant (target:"none") ability from
## where it stands. Returns {score} or null. Tuned vs attack scores (kill ~30+, decent
## attack ~8-15). heal/quake/bulwark/ward only; skitter/galeRush are movement value
## (out of scope for AI v1, as in the JS).
static func score_instant_ability(state, unit: Dictionary) -> Variant:
	var ab: Variant = Abilities.ability_for(unit)
	if ab == null or unit["cd"] > 0 or ab["target"] != "none":
		return null
	var s := 0.0
	match ab["key"]:
		"healPulse":
			for n in Hex.neighbors(Vector2i(unit["q"], unit["r"])):
				var a: Variant = state.unit_at(n.x, n.y)
				if a != null and a["owner"] == unit["owner"] and a["hp"] < a["max_hp"] * 0.6:
					s += 12
		"quake":
			for n in Hex.neighbors(Vector2i(unit["q"], unit["r"])):
				var e: Variant = state.unit_at(n.x, n.y)
				if e != null and e["owner"] != unit["owner"]:
					s += 20 if e["hp"] <= 4 else 9
			if s < 18:
				s = 0.0
		"bulwark", "ward":
			if Status.has_status(unit, ab["key"]):
				return null
			var allies := 0
			for n in Hex.neighbors(Vector2i(unit["q"], unit["r"])):
				var a: Variant = state.unit_at(n.x, n.y)
				if a != null and a["owner"] == unit["owner"]:
					allies += 1
			s = allies * 5 + 4
			if s < 12:
				s = 0.0
	return {"score": s} if s > 0 else null
```

- [ ] **Step 4: Run — verify pass**
```
pwsh -ExecutionPolicy Bypass -File godot/tests/run_tests.ps1; "EXIT=$LASTEXITCODE"
```
Expected: green, `EXIT=0` (~10 new asserts). `0 failed` is the gate.

- [ ] **Step 5: Commit**
```
git add godot/core/ai.gd godot/tests/run_tests.gd
git commit -m "[godot] M6: AI threat map + summon-slot + retreat-node + instant-ability scoring"
```

---

## Task 3: Attack scoring (score_attacks)

Port the `(end tile, target)` attack-scoring loop (game.js 1224–1258). PURE: each candidate end tile is scored with `forecast_battle` on a DUPLICATED probe unit positioned at that tile (so terrain/affinity are right) — the real unit is never mutated. Returns the best attack candidate or null.

**Files:** Modify `godot/core/ai.gd`, `godot/tests/run_tests.gd`.

- [ ] **Step 1: Add failing tests to `godot/tests/run_tests.gd`**

Add the call after `_test_ai_helpers()`:
```gdscript
	_test_ai_attack()
```
Append:
```gdscript
func _test_ai_attack() -> void:
	var gs := _combat_state()                          # 7x7 plain, clear weather, rng default
	var atk := gs.spawn_unit("cinderling", 1, 2, 3)    # AI unit (player 1), pyro
	var foe := gs.spawn_unit("galewisp", 0, 4, 3)       # human unit, zephyr (pyro>zephyr), 2 tiles away
	var reach := Pathfinding.compute_reachable(gs, atk)
	var threat := {}                                    # ignore threat for this scoring test
	var W: Dictionary = AI.weights(gs)
	var best = AI.score_attacks(gs, atk, reach, threat, W)
	_ok(best != null, "ai-attack: found an attack")
	_eq(best["target_id"], foe["id"], "ai-attack: targets the reachable foe")
	# the chosen end tile is adjacent to the foe (cinderling range 1) and reachable.
	_eq(Hex.distance(best["dest"], Vector2i(foe["q"], foe["r"])), 1, "ai-attack: ends in range")
	# a confirmed kill is flagged and scores above a non-kill.
	var gk := _combat_state()
	var killer := gk.spawn_unit("geomaul", 1, 2, 3)     # power 9
	var prey := gk.spawn_unit("galewisp", 0, 3, 3)       # adjacent, low hp
	prey["hp"] = 2
	var bk = AI.score_attacks(gk, killer, Pathfinding.compute_reachable(gk, killer), {}, AI.weights(gk))
	_ok(bk != null and bk["kills"], "ai-attack: lethal hit flagged as kill")
	# no enemy in reach -> null.
	var gn := _combat_state()
	var lonely := gn.spawn_unit("cinderling", 1, 2, 3)
	_eq(AI.score_attacks(gn, lonely, Pathfinding.compute_reachable(gn, lonely), {}, AI.weights(gn)), null, "ai-attack: no targets -> null")
	# scoring did NOT mutate the attacker's position.
	_eq(Vector2i(atk["q"], atk["r"]), Vector2i(2, 3), "ai-attack: attacker position unchanged by scoring")
```

- [ ] **Step 2: Run — verify it fails (score_attacks missing)**
```
pwsh -ExecutionPolicy Bypass -File godot/tests/run_tests.ps1; "EXIT=$LASTEXITCODE"
```
Expected: error about `AI.score_attacks`, non-zero EXIT.

- [ ] **Step 3: Add preloads + `score_attacks` to `godot/core/ai.gd`.** Add these preloads under the existing ones:
```gdscript
const Combat = preload("res://core/combat.gd")
```
Then append (port of aiActUnit's scoring loop 1224–1258, made pure with a probe copy):
```gdscript

## score_attacks — best (end tile, target) attack for `unit` over its reachable tiles,
## scored with forecast_battle. PURE: a candidate end tile is evaluated on a duplicated
## probe unit moved to that tile (so attacker terrain/affinity are correct) — the real
## unit is never moved. Returns {score, dest:Vector2i, target_id:int, kills:bool, ab:Variant}
## or null. `ab` is the enemy-target ability to use (null on a plain attack / a kill, which
## takes the plain swing to keep the cooldown ready). Mirrors game.js 1224–1258.
static func score_attacks(state, unit: Dictionary, reach: Dictionary, threat: Dictionary, W: Dictionary) -> Variant:
	var atk_ab: Variant = null
	var ability: Variant = Abilities.ability_for(unit)
	if ability != null and ability["target"] == "enemy" and unit["cd"] <= 0:
		atk_ab = ability
	var low_hp: bool = unit["hp"] < unit["max_hp"] * W["retreat_hp_frac"]
	var best: Variant = null
	for k in reach:
		var node: Dictionary = reach[k]
		var targets := Pathfinding.compute_attack_targets(state, unit, node["q"], node["r"])
		if targets.is_empty():
			continue
		var probe := unit.duplicate()
		probe["q"] = node["q"]
		probe["r"] = node["r"]
		var tdef: int = Terrain.TERRAIN[state.cell_at(node["q"], node["r"])["terrain"]]["def"]
		for tk in targets:
			var enemy: Variant = _unit_at_key(state, tk)
			if enemy == null:
				continue
			var f: Dictionary = Combat.forecast_battle(state, probe, enemy)
			var kills: bool = enemy["hp"] <= f["lo"]   # worst roll still lethal -> no counter
			var score: float = (f["lo"] + f["hi"]) / 2.0
			if kills:
				score += W["kill_bonus"]
			if enemy["is_master"]:
				score += W["master_bonus"]
			score += W["focus_fire"] * (1.0 - float(enemy["hp"]) / float(enemy["max_hp"]))
			if not kills and f["can_counter"]:
				score -= f["c_hi"] * W["counter_risk"]
				if unit["hp"] <= f["c_hi"]:
					score -= W["counter_death"]
			score += tdef * W["terrain_def"] * 0.5
			score -= threat_at(threat, node["q"], node["r"]) * (W["threat_hurt"] if low_hp else W["threat_safe"]) * 0.5
			if W["score_jitter"] != 0:
				score += (state.rng.next() * 2.0 - 1.0) * W["score_jitter"]
			if atk_ab != null:
				score += 6
			if best == null or score > best["score"]:
				best = {"score": score, "dest": Vector2i(node["q"], node["r"]), "target_id": enemy["id"], "kills": kills, "ab": atk_ab}
	# On a predicted kill, take the plain swing (no status on a corpse) — drop the ability.
	if best != null and best["kills"]:
		best["ab"] = null
	return best

static func _unit_at_key(state, key: String):
	for u in state.units:
		if u["hp"] > 0 and Hex.key(Vector2i(u["q"], u["r"])) == key:
			return u
	return null
```

NOTE: `state.rng.next()` returns a float in [0,1) (the easy-profile jitter path; `normal`/`hard` have `score_jitter == 0` so it's never drawn). The JS `Math.random()*2-1` maps to `state.rng.next()*2.0-1.0`.

- [ ] **Step 4: Run — verify pass**
```
pwsh -ExecutionPolicy Bypass -File godot/tests/run_tests.ps1; "EXIT=$LASTEXITCODE"
```
Expected: green, `EXIT=0` (~5 new asserts). The "attacker position unchanged" assert proves the probe-copy keeps scoring pure. `0 failed` is the gate.

- [ ] **Step 5: Commit**
```
git add godot/core/ai.gd godot/tests/run_tests.gd
git commit -m "[godot] M6: AI attack scoring (pure probe-based (tile,target) forecast loop)"
```

---

## Task 4: Decision tree (decide_unit_action)

Port the 5-branch decision tree (game.js 1272–1349): confirmed kill → retreat (wounded) → instant ability → capture → plain attack → move-only. Returns an action dict. PURE (reads state + the Task 2/3 helpers).

**Files:** Modify `godot/core/ai.gd`, `godot/tests/run_tests.gd`.

- [ ] **Step 1: Add failing tests to `godot/tests/run_tests.gd`**

Add the call after `_test_ai_attack()`:
```gdscript
	_test_ai_decision()
```
Append:
```gdscript
func _test_ai_decision() -> void:
	# Confirmed kill is taken (kind "attack", flagged kill via ab==null + lethal).
	var gk := _combat_state()
	var killer := gk.spawn_unit("geomaul", 1, 2, 3)
	var prey := gk.spawn_unit("galewisp", 0, 3, 3)
	prey["hp"] = 2
	var enemy_master := gk.spawn_master(0, 6, 6)
	var threat := AI.build_threat_map(gk, 1)
	var act := AI.decide_unit_action(gk, killer, threat, enemy_master)
	_eq(act["kind"], "attack", "decide: takes the confirmed kill")
	_eq(act["target_id"], prey["id"], "decide: kill targets the prey")
	# A lone unit with nothing in reach moves toward the enemy master (move-only).
	var gm := _flat_state(13, 13)
	var em2 := gm.spawn_master(0, 11, 11)
	var grunt := gm.spawn_unit("cinderling", 1, 2, 2)
	var t2 := AI.build_threat_map(gm, 1)
	var act2 := AI.decide_unit_action(gm, grunt, t2, em2)
	_eq(act2["kind"], "move", "decide: lone grunt moves")
	# the move steps CLOSER to the enemy master.
	_ok(Hex.distance(act2["dest"], Vector2i(11, 11)) < Hex.distance(Vector2i(2, 2), Vector2i(11, 11)), "decide: move approaches the master")
	# A quaker surrounded by enemies prefers its instant ability over a weak attack.
	var gi := _flat_state(7, 7)
	var emi := gi.spawn_master(0, 0, 0)
	var ogre := gi.spawn_unit("geomaul", 1, 3, 3)
	gi.spawn_unit("stoneward", 0, 4, 3)    # tanky adjacent enemies — attack is weak, quake hits both
	gi.spawn_unit("stoneward", 0, 3, 4)
	var ti := AI.build_threat_map(gi, 1)
	var acti := AI.decide_unit_action(gi, ogre, ti, emi)
	_ok(acti["kind"] == "instant" or acti["kind"] == "attack", "decide: quaker acts (instant or attack)")
	# A unit adjacent to an unowned tower it can reach, with no better attack, captures.
	var gc := _flat_state(7, 7)
	gc.cell_at(3, 4)["terrain"] = "tower"   # neutral tower next to the unit
	var emc := gc.spawn_master(0, 0, 0)
	var grabber := gc.spawn_unit("cinderling", 1, 3, 3)
	var tc := AI.build_threat_map(gc, 1)
	var actc := AI.decide_unit_action(gc, grabber, tc, emc)
	_eq(actc["kind"], "capture", "decide: captures a reachable neutral tower")
	_eq(actc["dest"], Vector2i(3, 4), "decide: capture dest is the tower")
```

- [ ] **Step 2: Run — verify it fails (decide_unit_action missing)**
```
pwsh -ExecutionPolicy Bypass -File godot/tests/run_tests.ps1; "EXIT=$LASTEXITCODE"
```
Expected: error about `AI.decide_unit_action`, non-zero EXIT.

- [ ] **Step 3: Append `decide_unit_action` to `godot/core/ai.gd`, verbatim** (port of aiActUnit's tree 1217–1349, returning actions instead of executing):
```gdscript

## decide_unit_action — the scored decision tree for one unit. Returns an action dict
## (see the plan header for shapes). Pure: reads state + helpers, mutates nothing.
## Order: confirmed kill -> wounded retreat -> instant ability -> capture -> plain
## attack -> move-only. Mirrors game.js aiActUnit 1217–1349.
static func decide_unit_action(state, unit: Dictionary, threat: Dictionary, enemy_master: Dictionary) -> Dictionary:
	var W: Dictionary = weights(state)
	var reach := Pathfinding.compute_reachable(state, unit)
	var low_hp: bool = unit["hp"] < unit["max_hp"] * W["retreat_hp_frac"]
	var best_atk: Variant = score_attacks(state, unit, reach, threat, W)

	# 1. Confirmed kills are always worth taking (no counter comes back). The master
	#    still refuses if the end tile is hot enough to kill it next turn.
	if best_atk != null and best_atk["kills"] and not (unit["is_master"] and threat_at(threat, best_atk["dest"].x, best_atk["dest"].y) >= unit["hp"]):
		return {"kind": "attack", "dest": best_atk["dest"], "target_id": best_atk["target_id"], "ab": best_atk["ab"]}

	# 2. Wounded units fall back toward owned heal tiles.
	if low_hp:
		var node: Variant = _retreat_node(state, unit, reach, threat)
		if node != null:
			return {"kind": "move", "dest": Vector2i(node["q"], node["r"])}

	# 3. Instant ability when its heuristic beats the best attack on offer.
	var best_inst: Variant = score_instant_ability(state, unit)
	if best_inst != null and (best_atk == null or best_inst["score"] > best_atk["score"]):
		return {"kind": "instant", "ab": Abilities.ability_for(unit)}

	# 4. Capture: any unit can flip a spire; scored against the best attack.
	var best_cap: Variant = null
	for t in state.map["towers"]:
		var cell: Variant = state.cell_at(t.x, t.y)
		if cell == null or cell.get("owner", -1) == unit["owner"]:
			continue
		var node: Variant = reach.get(Hex.key(t))
		if node == null:
			continue
		var heat := threat_at(threat, t.x, t.y)
		if heat >= unit["hp"]:
			continue   # don't capture into certain death
		var cap_score: float = W["capture_bonus"] - heat * 0.5 - node["cost"]
		if best_cap == null or cap_score > best_cap["score"]:
			best_cap = {"score": cap_score, "dest": t}
	if best_cap != null and (best_atk == null or best_cap["score"] > best_atk["score"]):
		return {"kind": "capture", "dest": best_cap["dest"]}

	# 5. Plain attack: clear the floor; the master is choosier (never trades into a
	#    tile where the standing threat outweighs it).
	if best_atk != null and best_atk["score"] > W["atk_floor"] \
			and not (unit["is_master"] and (best_atk["score"] < 8 or threat_at(threat, best_atk["dest"].x, best_atk["dest"].y) > unit["hp"] * 0.6)):
		return {"kind": "attack", "dest": best_atk["dest"], "target_id": best_atk["target_id"], "ab": best_atk["ab"]}

	# 6. Move-only. Non-masters advance on the enemy master (shaped by cover/threat);
	#    the master drifts toward the nearest unowned spire, else holds safe ground.
	var best_step: Variant = null
	var best_score := -INF
	var unowned: Array[Vector2i] = []
	for t in state.map["towers"]:
		var c: Variant = state.cell_at(t.x, t.y)
		if c == null or c.get("owner", -1) != unit["owner"]:
			unowned.append(t)
	for k in reach:
		var node: Dictionary = reach[k]
		var np := Vector2i(node["q"], node["r"])
		var tdef: int = Terrain.TERRAIN[state.cell_at(np.x, np.y)["terrain"]]["def"]
		var s: float = tdef * W["terrain_def"] - threat_at(threat, np.x, np.y) * (W["threat_hurt"] if unit["is_master"] else W["threat_safe"])
		if unit["is_master"]:
			if not unowned.is_empty():
				var d_tower := 9999
				for t in unowned:
					d_tower = mini(d_tower, Hex.distance(np, t))
				s -= d_tower * 0.8
		else:
			s -= Hex.distance(np, Vector2i(enemy_master["q"], enemy_master["r"])) * W["approach"]
		if s > best_score:
			best_score = s
			best_step = np
	if best_step != null:
		return {"kind": "move", "dest": best_step}
	return {"kind": "wait"}
```

- [ ] **Step 4: Run — verify pass**
```
pwsh -ExecutionPolicy Bypass -File godot/tests/run_tests.ps1; "EXIT=$LASTEXITCODE"
```
Expected: green, `EXIT=0` (~7 new asserts). `0 failed` is the gate. If "decide: captures a reachable neutral tower" fails, check the capture branch reads `cell.get("owner", -1)` (neutral towers are owner -1) and that the move-only branch isn't winning first (it shouldn't — capture is scored before move).

- [ ] **Step 5: Commit**
```
git add godot/core/ai.gd godot/tests/run_tests.gd
git commit -m "[godot] M6: AI decision tree (kill/retreat/instant/capture/attack/move)"
```

---

## Task 5: Summon economy (run_summons)

Port `aiTrySummons` (game.js 1357–1421): score summon types by element matchup vs the enemy army, terrain resonance, stat-value-per-MP, and a variety nudge; bank MP when ahead, flood cheap bodies when the master is threatened. This one MUTATES (spawns + spends MP) — it's part of the runner. `normal` is deterministic (no random).

**Files:** Modify `godot/core/ai.gd`, `godot/tests/run_tests.gd`.

- [ ] **Step 1: Add failing tests to `godot/tests/run_tests.gd`**

Add the call after `_test_ai_decision()`:
```gdscript
	_test_ai_summons()
```
Append:
```gdscript
func _test_ai_summons() -> void:
	# A master with plenty of MP and an enemy army summons at least one unit, adjacent.
	var gs := GameState.new_skirmish(Maps.MAPS[0], 42)
	var m1 := gs.master_of(1)
	m1["mp"] = 30
	gs.spawn_unit("cinderling", 0, 3, 3)   # an enemy to score matchups against
	var before := gs.alive_units(1).size()
	AI.run_summons(gs, m1)
	_ok(gs.alive_units(1).size() > before, "summons: AI summoned at least one unit")
	_ok(m1["mp"] < 30, "summons: MP was spent")
	# summoned units belong to the master's owner, are adjacent, and are flagged acted.
	for u in gs.alive_units(1):
		if not u["is_master"]:
			_ok(Hex.distance(Vector2i(u["q"], u["r"]), Vector2i(m1["q"], m1["r"])) == 1, "summons: spawned adjacent to master")
			_ok(u["acted"], "summons: summoned unit is acted")
	# Deterministic on normal: same seed + same setup -> same summoned roster.
	var ga := GameState.new_skirmish(Maps.MAPS[0], 77)
	var gb := GameState.new_skirmish(Maps.MAPS[0], 77)
	ga.master_of(1)["mp"] = 24
	gb.master_of(1)["mp"] = 24
	ga.spawn_unit("galewisp", 0, 3, 3); gb.spawn_unit("galewisp", 0, 3, 3)
	AI.run_summons(ga, ga.master_of(1))
	AI.run_summons(gb, gb.master_of(1))
	var types_a := PackedStringArray()
	for u in ga.alive_units(1): if not u["is_master"]: types_a.append(u["type_key"])
	var types_b := PackedStringArray()
	for u in gb.alive_units(1): if not u["is_master"]: types_b.append(u["type_key"])
	_eq(types_a, types_b, "summons: deterministic roster on normal")
	# Too little MP (<6) summons nothing.
	var gp := GameState.new_skirmish(Maps.MAPS[0], 42)
	gp.master_of(1)["mp"] = 5
	var n0 := gp.alive_units(1).size()
	AI.run_summons(gp, gp.master_of(1))
	_eq(gp.alive_units(1).size(), n0, "summons: <6 MP summons nothing")
```

- [ ] **Step 2: Run — verify it fails (run_summons missing)**
```
pwsh -ExecutionPolicy Bypass -File godot/tests/run_tests.ps1; "EXIT=$LASTEXITCODE"
```
Expected: error about `AI.run_summons`, non-zero EXIT.

- [ ] **Step 3: Add preloads + `run_summons` to `godot/core/ai.gd`.** Add these preloads:
```gdscript
const Elements = preload("res://data/elements.gd")
const UnitTypes = preload("res://data/unit_types.gd")
```
Then append (port of aiTrySummons 1357–1421, logic only — no logs/anims/beeps; spawns via `state.spawn_unit`):
```gdscript

## run_summons — the AI summon economy (MUTATES state: spawns units, spends master MP).
## Scores types by element matchup vs the enemy army, terrain resonance, stat-value-per-MP,
## and a variety nudge; banks MP when clearly ahead, floods cheap bodies when the master is
## threatened. `normal`/`hard` are deterministic; `easy` picks randomly via state.rng.
static func run_summons(state, master: Dictionary) -> void:
	var owner: int = master["owner"]
	var W := weights(state)
	var enemies := state.alive_units(1 - owner)
	var my_army: Array[Dictionary] = []
	for u in state.alive_units(owner):
		if not u["is_master"]:
			my_army.append(u)

	# Fraction of the map that empowers each element (+20% terrain).
	var terr_frac := {}
	for el in Elements.ELEMENT:
		var n := 0
		var tot := 0
		for k in state.map["cells"]:
			tot += 1
			if Elements.affinity_for(el, state.map["cells"][k]["terrain"]) != null:
				n += 1
		terr_frac[el] = float(n) / float(tot) if tot > 0 else 0.0

	var ahead: bool = _army_value(my_army) > _army_value(_non_masters(enemies)) * 1.25
	var emergency := false
	for e in enemies:
		if Hex.distance(Vector2i(e["q"], e["r"]), Vector2i(master["q"], master["r"])) <= e["move"] + e["range"]:
			emergency = true
			break

	var attempts := 4
	while attempts > 0 and master["mp"] >= 6:
		attempts -= 1
		var pool: Array = []
		for k in UnitTypes.SUMMON_LIST:
			if UnitTypes.UNIT_TYPES[k]["cost"] <= master["mp"]:
				pool.append(k)
		if pool.is_empty():
			break
		if W["random_summons"]:
			pool = [pool[state.rng.below(pool.size())]]
		elif emergency:
			pool.sort_custom(func(a, b): return UnitTypes.UNIT_TYPES[a]["cost"] < UnitTypes.UNIT_TYPES[b]["cost"])
			pool = pool.slice(0, maxi(1, int(ceil(pool.size() / 2.0))))
		elif ahead:
			var bigs: Array = []
			for k in pool:
				if UnitTypes.UNIT_TYPES[k]["cost"] >= 12:
					bigs.append(k)
			var regen: int = master["mp_regen"] + _owned_tower_count(state, owner) * 2
			if bigs.is_empty() and master["mp"] + regen <= master["max_mp"]:
				break
			if not bigs.is_empty():
				pool = bigs
		pool.sort_custom(func(a, b): return _score_type(b, enemies, terr_frac, my_army) > _score_type(a, enemies, terr_frac, my_army))
		var choice: String = pool[0]
		var slot: Variant = find_summon_slot(state, master)
		if slot == null:
			break
		master["mp"] -= UnitTypes.UNIT_TYPES[choice]["cost"]
		var u := state.spawn_unit(choice, owner, slot.x, slot.y)
		u["acted"] = true
		my_army.append(u)   # keep the variety penalty honest across the loop

static func _army_value(list: Array) -> float:
	var v := 0.0
	for u in list:
		v += u["power"] + u["max_hp"] * 0.25
	return v

static func _non_masters(list: Array) -> Array:
	var out: Array = []
	for u in list:
		if not u["is_master"]:
			out.append(u)
	return out

static func _owned_tower_count(state, owner: int) -> int:
	var n := 0
	for t in state.map.get("towers", []):
		var c: Variant = state.cell_at(t.x, t.y)
		if c != null and c.get("owner", -1) == owner:
			n += 1
	return n

## _score_type — summon desirability: element edge vs the enemy army (offense minus how
## hard they counter-hit), terrain resonance, stat value per MP, minus a variety penalty.
static func _score_type(k: String, enemies: Array, terr_frac: Dictionary, my_army: Array) -> float:
	var t: Dictionary = UnitTypes.UNIT_TYPES[k]
	var s := 0.0
	if not enemies.is_empty():
		var off := 0.0
		var deff := 0.0
		for e in enemies:
			off += Elements.ELEM_MATRIX[t["element"]][e["element"]] - 1.0
			deff += Elements.ELEM_MATRIX[e["element"]][t["element"]] - 1.0
		s += off / enemies.size() * 20.0
		s -= deff / enemies.size() * 10.0
	s += terr_frac.get(t["element"], 0.0) * 12.0
	s += (t["max_hp"] * 0.25 + t["power"]) / float(t["cost"]) * 6.0
	var same := 0
	for m in my_army:
		if m["type_key"] == k:
			same += 1
	s -= same * 4.0
	return s
```

NOTE: `state.spawn_unit` already exists (M3). The summoned unit is flagged `acted = true` (can't act the turn it appears). `_owned_tower_count` is local to `ai.gd` (GameState has a private `_owned_tower_count` it can't call from outside, so AI keeps its own copy reading cell ownership).

- [ ] **Step 4: Run — verify pass**
```
pwsh -ExecutionPolicy Bypass -File godot/tests/run_tests.ps1; "EXIT=$LASTEXITCODE"
```
Expected: green, `EXIT=0` (~7 new asserts). `0 failed` is the gate. If "deterministic roster" fails on `normal`, something is drawing from `state.rng` on the normal path (it shouldn't — `random_summons` is false and `score_jitter` isn't used here).

- [ ] **Step 5: Commit**
```
git add godot/core/ai.gd godot/tests/run_tests.gd
git commit -m "[godot] M6: AI summon economy (element/terrain/value scoring, bank vs flood)"
```

---

## Task 6: Turn runner (take_turn) + wire AI into the board + close M6

Port `aiTakeTurn` as a SYNCHRONOUS runner (combat is inline in M6 — no battle-scene awaiting until M8). `take_turn` decides + applies an action per unit (masters last), then runs summons. Wire `main.gd` so that when the human ends their turn and it becomes player 1's turn, the AI plays and the turn returns to the human.

**Files:** Modify `godot/core/ai.gd`, `godot/scenes/main.gd`, `godot/tests/run_tests.gd`, `ROADMAP_GODOT.md`.

- [ ] **Step 1: Add failing tests to `godot/tests/run_tests.gd`**

Add the call after `_test_ai_summons()`:
```gdscript
	_test_ai_turn()
```
Append:
```gdscript
func _test_ai_turn() -> void:
	# A full AI turn: every AI unit ends up acted; a guaranteed kill is executed.
	var gs := _combat_state()
	gs.current_player = 1                      # AI's turn
	var killer := gs.spawn_unit("geomaul", 1, 2, 3)
	var prey := gs.spawn_unit("galewisp", 0, 3, 3)
	prey["hp"] = 2
	gs.spawn_master(0, 6, 6)                    # enemy master (so take_turn has a target)
	gs.spawn_master(1, 0, 0)                    # AI master
	AI.take_turn(gs)
	_ok(prey["hp"] <= 0, "ai-turn: AI executed the guaranteed kill")
	for u in gs.alive_units(1):
		_ok(u["acted"], "ai-turn: every AI unit acted")
	# No enemy master -> take_turn is a no-op (and does not crash).
	var gn := _combat_state()
	gn.current_player = 1
	gn.spawn_unit("cinderling", 1, 2, 3)
	AI.take_turn(gn)
	_ok(true, "ai-turn: no enemy master -> safe no-op")
	# A move-toward-master turn for a lone grunt actually moves it.
	var gm := _flat_state(13, 13)
	gm.current_player = 1
	gm.spawn_master(0, 11, 11)
	gm.spawn_master(1, 0, 0)
	var grunt := gm.spawn_unit("cinderling", 1, 2, 2)
	AI.take_turn(gm)
	_ok(Hex.distance(Vector2i(grunt["q"], grunt["r"]), Vector2i(11, 11)) < Hex.distance(Vector2i(2, 2), Vector2i(11, 11)), "ai-turn: grunt advanced on the master")
```

- [ ] **Step 2: Run — verify it fails (take_turn missing)**
```
pwsh -ExecutionPolicy Bypass -File godot/tests/run_tests.ps1; "EXIT=$LASTEXITCODE"
```
Expected: error about `AI.take_turn`, non-zero EXIT.

- [ ] **Step 3: Append `take_turn` to `godot/core/ai.gd`, verbatim** (port of aiTakeTurn 1191–1215 + the action-application from aiActUnit, synchronous):
```gdscript

## take_turn — run the current player's entire AI turn synchronously (combat is inline
## in M6; the battle-scene awaiting returns at M8 as a coroutine). For each non-acted unit
## (masters last), decide and apply an action; then run the summon economy. Does NOT call
## end_turn — the caller does. MUTATES state.
static func take_turn(state) -> void:
	var owner: int = state.current_player
	var enemy_master: Variant = state.master_of(1 - owner)
	if enemy_master == null:
		return
	var queue: Array[Dictionary] = []
	for u in state.alive_units(owner):
		if not u["acted"]:
			queue.append(u)
	queue.sort_custom(func(a, b): return (0 if a["is_master"] else -1) < (0 if b["is_master"] else -1))  # masters last
	var threat := build_threat_map(state, owner)
	for u in queue:
		if u["hp"] <= 0:
			continue
		_apply_action(state, u, decide_unit_action(state, u, threat, enemy_master))
		u["acted"] = true
		if state.winner != -1:
			return
	var master: Variant = state.master_of(owner)
	if master != null and master["mp"] >= 6:
		run_summons(state, master)

## _apply_action — execute one decided action (MUTATES state). Move/attack/capture/instant.
static func _apply_action(state, unit: Dictionary, action: Dictionary) -> void:
	match action["kind"]:
		"attack":
			unit["q"] = action["dest"].x
			unit["r"] = action["dest"].y
			var target: Variant = _unit_by_id(state, action["target_id"])
			if target == null:
				return
			if action["ab"] != null:
				unit["cd"] = action["ab"]["cd"]
				Combat.resolve_attack(state, unit, target, action["ab"]["status"], action["ab"]["status_turns"])
			else:
				Combat.resolve_attack(state, unit, target)
		"instant":
			AbilityResolve.resolve_instant(state, unit, action["ab"])
			unit["cd"] = action["ab"]["cd"]
		"capture":
			unit["q"] = action["dest"].x
			unit["r"] = action["dest"].y
			var cell: Variant = state.cell_at(action["dest"].x, action["dest"].y)
			if cell != null and cell["terrain"] == "tower" and cell.get("owner", -1) != unit["owner"]:
				state.capture_tower(unit, cell)
		"move":
			unit["q"] = action["dest"].x
			unit["r"] = action["dest"].y
		"wait":
			pass

static func _unit_by_id(state, id: int):
	for u in state.units:
		if u["id"] == id and u["hp"] > 0:
			return u
	return null
```
Add the `AbilityResolve` preload at the top of `ai.gd` (it's used by `_apply_action`'s instant branch):
```gdscript
const AbilityResolve = preload("res://core/ability_resolve.gd")
```

- [ ] **Step 4: Wire the AI into `godot/scenes/main.gd`.** Add the `AI` preload with the others:
```gdscript
const AI = preload("res://core/ai.gd")
```
Then REPLACE the Enter branch in `_unhandled_input` (currently `state.end_turn(); _center_on_master(); _finish_action()`) with a version that runs the AI when it becomes player 1's turn:
```gdscript
	elif event is InputEventKey and event.pressed and event.keycode == KEY_ENTER:
		state.end_turn()
		# M6: player 1 is the AI. Run its whole turn synchronously, then hand back.
		# (The difficulty-select UI is M9; player-table/isAI lands then too.)
		if state.winner == -1 and state.current_player == 1:
			AI.take_turn(state)
			if state.winner == -1:
				state.end_turn()
		_center_on_master()
		_finish_action()
```

- [ ] **Step 5: Headless boot check (main.gd has no class_name — only parse gate).**
```
godot --headless --path godot --quit-after 30 2>&1 | Select-String -Pattern "SCRIPT ERROR|Parse Error|Failed to load"
```
Run via the PowerShell tool. Expected: NO output. REQUIRED GATE.

- [ ] **Step 6: Run the harness.**
```
pwsh -ExecutionPolicy Bypass -File godot/tests/run_tests.ps1; "EXIT=$LASTEXITCODE"
```
Expected: green, `EXIT=0` (~6 new asserts from `_test_ai_turn`).

- [ ] **Step 7: Visual confirmation (windowed) — YOU CANNOT DO THIS (no display).**
Manual check (USER): `godot --path godot`, press **D** to spawn an ally + adjacent enemy near your archon, move/attack with your units, then press **Enter** — the AI (player 1, CRIMSON) now takes a full turn: its units move toward you / attack / capture, its master summons, and control returns to you. Report this step as "NEEDS USER VISUAL CONFIRMATION". Do NOT run the windowed command.

- [ ] **Step 8: Check off M6 in `ROADMAP_GODOT.md`** — change `- [ ] M6 — AI (threat map + decision tree + summon economy)` to `- [x] M6 — ...`.

- [ ] **Step 9: Commit**
```
git add godot/core/ai.gd godot/scenes/main.gd ROADMAP_GODOT.md
git commit -m "[godot] M6: synchronous AI turn-runner + wire AI into board; close M6"
```

---

## Notes & risk callouts

- **The synchronous runner is the design's anticipated simplification.** The JS `aiTakeTurn` is a `setTimeout`-step chain that awaits the battle SCENE between units (polling `STATE.screen === 'battle'`). M6 has no cutaway (M8), so combat resolves inline in `Combat.resolve_attack` and the runner is a plain `for` loop. When M8 adds the cutaway, `take_turn` becomes a coroutine in the presentation layer that `await`s each battle — the decision functions don't change (they're the C#-swap seam). Keep the decision/runner split.
- **Scoring is pure via a probe copy.** `score_attacks` evaluates a candidate end tile by `unit.duplicate()` + setting the probe's q/r, NOT by mutating the real unit (the JS mutate-and-restore hack). The "attacker position unchanged" test guards this. This matters for the C# swap and for re-entrancy.
- **Determinism:** `normal`/`hard` use NO randomness — `score_jitter == 0` (so `state.rng.next()` is never called in `score_attacks`) and `random_summons == false`. Only `easy` draws from `state.rng` (jitter + random summon pick). Tests use `normal` and assert reproducibility.
- **Masters act last** (`queue.sort_custom` puts `is_master` units at the end), matching the JS `myUnits.sort((a,b) => (a.isMaster?1:0)-(b.isMaster?1:0))` — grunts create threat/space before the archon commits.
- **Confirmed-kill ability downgrade:** on a predicted kill, `score_attacks` nulls `ab` so the attack takes the plain swing (no wasted cooldown statusing a corpse) — faithful to the JS `!bestAtk.kills` guard.
- **Target identity by id, not position.** Actions carry `target_id`; the runner re-resolves the live unit by id at apply time (a unit's position is stable between decide and apply within one unit's action, but using id is robust and matches "find the unit" semantics).
- **AI is hardcoded to player 1 in `main.gd`** for M6 (no players/isAI table until M9). `take_turn` itself is owner-agnostic (uses `state.current_player`).
- **`run_summons` mutates** (spawns + spends MP) — it's the one AI function that isn't a pure read, by nature. The summoned unit is `acted = true` (can't move the turn it appears), faithful to JS.
- **`main.gd` is not headless-tested** (no class_name). Step 5's headless boot is the only automated parse check for the AI wiring — run it.
- **AI is the C#-swap seam:** `core/ai.gd` reads only `GameState` + the pure modules (Pathfinding/Combat/Abilities/AbilityResolve) and the data tables. If a profiler ever flags AI scoring, this whole file can be reimplemented in C# behind the same `weights`/`build_threat_map`/`decide_unit_action`/`run_summons`/`take_turn` interface.

---

## Self-review

- **Spec coverage** (design spec milestone 6 — "threat map + decision tree + summon economy; headless decision asserts + live AI turns"): AI_PROFILES (Task 1); threat map + helpers (Task 2); attack scoring (Task 3); the kill→retreat→instant→capture→attack→move decision tree (Task 4); summon economy (Task 5); turn-runner + live wiring (Task 6). Headless decision asserts: every task tests decisions on constructed boards; live AI turns: Task 6 wires it + visual check. ✅
- **Deferred with intent:** difficulty-select UI (M9), action menu/summon UI (M7), battle cutaway + coroutine runner (M8). Noted.
- **Type/signature consistency:** `weights(state)` / `build_threat_map(state, owner)` / `threat_at(threat, q, r)` / `score_attacks(state, unit, reach, threat, W)` / `score_instant_ability(state, unit)` / `decide_unit_action(state, unit, threat, enemy_master)` / `find_summon_slot(state, master)` / `run_summons(state, master)` / `take_turn(state)` — consistent across tasks and the `main.gd` call. Profile keys (`kill_bonus`/`master_bonus`/`focus_fire`/`counter_risk`/`counter_death`/`terrain_def`/`threat_safe`/`threat_hurt`/`approach`/`capture_bonus`/`retreat_hp_frac`/`atk_floor`/`score_jitter`/`random_summons`) consistent between `ai_profiles.gd` and every reader. Action dict shapes (`kind`/`dest`/`target_id`/`ab`) consistent between `decide_unit_action` and `_apply_action`. ✅
- **No placeholders:** every step ships complete code or an exact command + expected output. ✅
