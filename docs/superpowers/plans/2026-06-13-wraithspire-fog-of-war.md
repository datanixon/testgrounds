# Fog of War Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add Master-of-Monsters–style fog of war to the Godot port — terrain always visible, enemy units hidden outside a per-side vision set — with a fair AI, a Veilstone (+1 vision) relic, a title toggle, and cutaway ambush reveals.

**Architecture:** A pure `core/vision.gd` computes the visible `"q,r"` set as the union of a side's unit sight discs (r3 ground / r4 fly / +Veilstone) and owned spires/citadel (r2). `GameState` caches the viewer's `visibility` (recomputed by the presentation layer on every move/summon/death/turn) and a transient `revealed` set for ambush reveals; `fog` is a saved per-match flag. The AI filters its threat map and summon logic to what it can see. Render gating dims out-of-vision tiles and skips hidden enemy nodes.

**Tech Stack:** Godot 4 / GDScript. Harness tests in `godot/tests/run_tests.gd` (`_test_*` functions registered in `_initialize()`; helpers `_eq`/`_ok`/`_flat_state`). Gates: `pwsh -File godot/tests/run_tests.ps1` (`== N passed, 0 failed ==`, EXIT 0) and, after any scene/`main`/autoload change, the headless boot `godot --headless --path godot --quit-after 30 2>&1 | Select-String "SCRIPT ERROR|Parse Error|Failed to load"` (no matches).

**Spec:** `docs/superpowers/specs/2026-06-13-wraithspire-fog-of-war-design.md`

---

## File structure

| File | Responsibility | Task |
|---|---|---|
| `core/vision.gd` (new) | Pure visibility computation | 1 |
| `data/relics.gd` | Veilstone relic | 2 |
| `core/game_state.gd` | `fog` / `visibility` / `revealed` + `recompute_visibility` | 3 |
| `core/save_game.gd` | Round-trip `fog` | 3 |
| `core/ai.gd` | Fair-AI vision filter | 4 |
| `core/settings_store.gd` | `fog` default + merge validation | 5 |
| `core/combat.gd` | `attacker_pos` in battle record | 6 |
| `core/session.gd`, `data/campaign.gd` | Wire `fog` at match start; flag mission 4 | 7 |
| `scenes/title/title_scene.gd` | Skirmish fog toggle | 8 |
| `scenes/match/overlay.gd`, `scenes/match/units_layer.gd` | Dim overlay + enemy hiding | 9 |
| `scenes/match/match_scene.gd` | Recompute timing + ambush reveal | 10 |
| `godot/tests/run_tests.gd` | New `_test_*` functions | 1–6 |

Tasks 1–6 are pure logic (TDD, harness-gated). Tasks 7–10 are flow/render (harness regression + headless-boot gate; final behavior verified in the manual windowed pass, Task 11).

---

### Task 1: `core/vision.gd` — pure visibility engine

**Files:**
- Create: `godot/core/vision.gd`
- Modify: `godot/tests/run_tests.gd` (add preload const; add `_test_vision`; register it)

- [ ] **Step 1: Register the preload and the test call**

In `godot/tests/run_tests.gd`, after the line `const Relics = preload("res://data/relics.gd")` (the last const, ~line 34) add:

```gdscript
const Vision = preload("res://core/vision.gd")
```

In `_initialize()`, after the line `_test_ai_relic_nudge()` add:

```gdscript
	_test_vision()
```

- [ ] **Step 2: Write the failing test**

Add this function at the end of `godot/tests/run_tests.gd` (before nothing in particular — append after the last `_test_*`):

```gdscript
func _test_vision() -> void:
	# Ground unit sees radius 3, not 4.
	var gs := _flat_state(11, 11)
	var g := gs.spawn_unit("cinderling", 0, 5, 5)   # grounded, move 4
	_eq(Vision.unit_sight(g), 3, "vision: ground sight 3")
	var vg := Vision.compute(gs, 0)
	_ok(vg.has("5,5"), "vision: own tile visible")
	_ok(vg.has("8,5"), "vision: ground sees distance 3")          # dist 3
	_ok(not vg.has("9,5"), "vision: ground blind at distance 4")  # dist 4
	# Flyer sees radius 4.
	var gf := _flat_state(11, 11)
	var f := gf.spawn_unit("galewisp", 0, 5, 5)      # flying, move 5
	_eq(Vision.unit_sight(f), 4, "vision: flyer sight 4")
	var vf := Vision.compute(gf, 0)
	_ok(vf.has("9,5"), "vision: flyer sees distance 4")
	_ok(not vf.has("10,5"), "vision: flyer blind at distance 5")
	# Veilstone adds +1.
	var gv := _flat_state(11, 11)
	var v := gv.spawn_unit("cinderling", 0, 5, 5)
	v["relic"] = "veilstone"
	_eq(Vision.unit_sight(v), 4, "vision: veilstone +1 sight")
	_ok(Vision.compute(gv, 0).has("9,5"), "vision: veilstone ground sees distance 4")
	# Owned spire contributes radius 2; an unowned one contributes nothing.
	var gt := _flat_state(11, 11)
	gt.spawn_unit("cinderling", 0, 0, 0)             # far unit; its disc never reaches (8,8)
	gt.cell_at(8, 8)["terrain"] = "tower"
	gt.cell_at(8, 8)["owner"] = 0
	var vt := Vision.compute(gt, 0)
	_ok(vt.has("8,8"), "vision: owned tower visible")
	_ok(vt.has("8,6"), "vision: owned tower radius 2")             # dist 2
	_ok(not vt.has("8,5"), "vision: owned tower not radius 3")     # dist 3
	gt.cell_at(8, 8)["owner"] = 1
	_ok(not Vision.compute(gt, 0).has("8,8"), "vision: enemy tower grants no vision")
```

- [ ] **Step 3: Run the test to verify it fails**

Run: `pwsh -File godot/tests/run_tests.ps1`
Expected: FAIL — `Vision` preload errors / `Vision.compute` not found (parse error or failed asserts).

- [ ] **Step 4: Create the implementation**

Create `godot/core/vision.gd`:

```gdscript
class_name Vision
extends RefCounted
## ROADMAP2 Phase 3 — fog-of-war visibility. Pure: computes the set of visible
## "q,r" keys for one side as the union of its units' sight discs (radius 3 ground,
## 4 flying, +Veilstone) and its owned spires/citadel (radius 2). No LOS blocking —
## plain hex distance, Master-of-Monsters style. Reads GameState; mutates nothing.

const Hex = preload("res://core/hex.gd")
const Relics = preload("res://data/relics.gd")

const GROUND_SIGHT := 3
const FLY_SIGHT := 4
const SPIRE_SIGHT := 2

## unit_sight — a unit's vision radius: 4 if flying else 3, plus a Veilstone bonus.
static func unit_sight(unit: Dictionary) -> int:
	var base: int = FLY_SIGHT if unit["flying"] else GROUND_SIGHT
	return base + int(Relics.unit_bonus(unit, "vision"))

## compute — the set of visible "q,r" keys for `owner` (a Dictionary used as a set).
## Union over every alive unit of `owner` (unit_sight disc) and every tower/castle
## cell owned by `owner` (SPIRE_SIGHT disc). Only in-bounds cells are included.
static func compute(state, owner: int) -> Dictionary:
	var sources: Array = []   # [{pos: Vector2i, r: int}]
	for u in state.alive_units(owner):
		sources.append({"pos": Vector2i(u["q"], u["r"]), "r": unit_sight(u)})
	for k in state.map.get("cells", {}):
		var c: Dictionary = state.map["cells"][k]
		if (c["terrain"] == "tower" or c["terrain"] == "castle") and c.get("owner", -1) == owner:
			sources.append({"pos": Vector2i(c["q"], c["r"]), "r": SPIRE_SIGHT})
	var vis := {}
	for k in state.map.get("cells", {}):
		var c: Dictionary = state.map["cells"][k]
		var p := Vector2i(c["q"], c["r"])
		for s in sources:
			if Hex.distance(p, s["pos"]) <= s["r"]:
				vis[k] = true
				break
	return vis
```

- [ ] **Step 5: Run the test to verify it passes**

Run: `pwsh -File godot/tests/run_tests.ps1`
Expected: PASS — `== N passed, 0 failed ==`, EXIT 0 (N = previous total + 14).

- [ ] **Step 6: Commit**

```bash
git add godot/core/vision.gd godot/tests/run_tests.gd
git commit -m "[godot] P3 fog: pure vision engine (core/vision.gd) + tests"
```

---

### Task 2: Veilstone relic

**Files:**
- Modify: `godot/data/relics.gd`
- Modify: `godot/tests/run_tests.gd` (add `_test_veilstone`; register it)

- [ ] **Step 1: Register the test call**

In `_initialize()`, after `_test_vision()` add:

```gdscript
	_test_veilstone()
```

- [ ] **Step 2: Write the failing test**

Append to `godot/tests/run_tests.gd`:

```gdscript
func _test_veilstone() -> void:
	_ok(Relics.RELICS.has("veilstone"), "veilstone: defined")
	_eq(Relics.RELICS["veilstone"]["kind"], "passive", "veilstone: passive")
	_eq(Relics.bonus("veilstone", "vision"), 1, "veilstone: +1 vision")
	_ok("veilstone" in Relics.POOL, "veilstone: in spawn pool")
	var u := Units.make_unit(1, "cinderling", 0, 0, 0)
	_eq(Relics.unit_bonus(u, "vision"), 0, "veilstone: no relic -> 0 vision bonus")
	u["relic"] = "veilstone"
	_eq(Relics.unit_bonus(u, "vision"), 1, "veilstone: equipped -> +1")
```

- [ ] **Step 3: Run the test to verify it fails**

Run: `pwsh -File godot/tests/run_tests.ps1`
Expected: FAIL — `veilstone: defined` and others (key absent).

- [ ] **Step 4: Add the relic**

In `godot/data/relics.gd`, change the header line 5 from:

```gdscript
## forecast + AI inherit them. 6 passive + 3 consumable. (Veilstone -> Phase 3.)
```
to:
```gdscript
## forecast + AI inherit them. 7 passive + 3 consumable. (Veilstone: +1 vision under fog.)
```

In the `RELICS` dict, after the `"thorncharm":` line (line 13) add:

```gdscript
	"veilstone":   {"name": "Veilstone",     "kind": "passive",    "glyph": "E", "color": Color("#6a8ec0"), "vision": 1},
```

Change the `POOL` line (line 20) from:

```gdscript
const POOL := ["atk_charm", "vital", "swift", "farsight", "regenring", "thorncharm", "phoenix", "warhorn", "ley_crystal"]
```
to:
```gdscript
const POOL := ["atk_charm", "vital", "swift", "farsight", "regenring", "thorncharm", "veilstone", "phoenix", "warhorn", "ley_crystal"]
```

- [ ] **Step 5: Run the test to verify it passes**

Run: `pwsh -File godot/tests/run_tests.ps1`
Expected: PASS — N = previous + 6.

- [ ] **Step 6: Commit**

```bash
git add godot/data/relics.gd godot/tests/run_tests.gd
git commit -m "[godot] P3 fog: Veilstone relic (+1 vision) + tests"
```

---

### Task 3: `GameState` fog/visibility/revealed + save round-trip

**Files:**
- Modify: `godot/core/game_state.gd`
- Modify: `godot/core/save_game.gd`
- Modify: `godot/tests/run_tests.gd` (add `_test_fog_state`; register it)

- [ ] **Step 1: Register the test call**

In `_initialize()`, after `_test_veilstone()` add:

```gdscript
	_test_fog_state()
```

- [ ] **Step 2: Write the failing test**

Append to `godot/tests/run_tests.gd`:

```gdscript
func _test_fog_state() -> void:
	# recompute_visibility fills the cache for the viewer; revealed tiles union in.
	var gs := _flat_state(9, 9)
	gs.spawn_unit("cinderling", 0, 4, 4)   # owner-0 vision source
	gs.recompute_visibility(0)
	_ok(gs.visibility.has("4,4"), "fog state: recompute fills viewer vision")
	_ok(not gs.visibility.has("0,0"), "fog state: far tile not visible")
	gs.revealed["0,0"] = true
	gs.recompute_visibility(0)
	_ok(gs.visibility.has("0,0"), "fog state: revealed tiles union into visibility")
	# fog flag round-trips through save; visibility/revealed are NOT saved.
	var g2 := GameState.new_skirmish(Maps.MAPS[0], 42)
	g2.fog = true
	var blob := SaveGame.to_dict(g2)
	_eq(blob["fog"], true, "fog state: to_dict serializes fog")
	_eq(blob.has("visibility"), false, "fog state: visibility not serialized")
	var restored := SaveGame.from_dict(blob)
	_eq(restored.fog, true, "fog state: from_dict restores fog")
	# old blob without fog defaults to false.
	blob.erase("fog")
	_eq(SaveGame.from_dict(blob).fog, false, "fog state: missing fog defaults false")
```

- [ ] **Step 3: Run the test to verify it fails**

Run: `pwsh -File godot/tests/run_tests.ps1`
Expected: FAIL — `recompute_visibility` not found / `blob["fog"]` missing.

- [ ] **Step 4a: Add fields + method to `game_state.gd`**

In `godot/core/game_state.gd`, after the const block add a preload (after line 14 `const Relics = preload("res://data/relics.gd")`):

```gdscript
const Vision = preload("res://core/vision.gd")
```

After the `var battle_log: Array = []` line (line 26) add:

```gdscript
	var fog: bool = false              # P3: this match uses fog of war (saved)
	var visibility: Dictionary = {}    # P3: cached visible "q,r" set for the viewer (NOT saved)
	var revealed: Dictionary = {}      # P3: extra reveals this turn (ambush cutaways); NOT saved
```

(Match the file's tab indentation for member vars — they are indented one tab like the others.)

After the `recompute`/`pick_up_relic` region — specifically right after the `effective_max_hp` function (ends line 93) — add:

```gdscript
## recompute_visibility — refresh the cached visible-key set for `owner` (the viewer),
## unioning in any per-turn revealed tiles. Presentation calls this on match start and
## after each move/summon/death/turn. Pure read of unit positions + owned spires.
func recompute_visibility(owner: int) -> void:
	visibility = Vision.compute(self, owner)
	for k in revealed:
		visibility[k] = true
```

- [ ] **Step 4b: Round-trip `fog` in `save_game.gd`**

In `godot/core/save_game.gd` `to_dict`, in the returned dictionary (the `return { ... }` block), add after the `"v": 1,` line:

```gdscript
		"fog": state.fog,
```

In `from_dict`, immediately before `return gs` (line 107) add:

```gdscript
	gs.fog = bool(blob.get("fog", false))
```

- [ ] **Step 5: Run the test to verify it passes**

Run: `pwsh -File godot/tests/run_tests.ps1`
Expected: PASS — N = previous + 7.

Also run the headless boot (game_state/save are class_name so harness-covered, but cheap insurance):
Run: `godot --headless --path godot --quit-after 30 2>&1 | Select-String "SCRIPT ERROR|Parse Error|Failed to load"`
Expected: no matches.

- [ ] **Step 6: Commit**

```bash
git add godot/core/game_state.gd godot/core/save_game.gd godot/tests/run_tests.gd
git commit -m "[godot] P3 fog: GameState fog/visibility/revealed + save round-trip"
```

---

### Task 4: Fair-AI vision filter

**Files:**
- Modify: `godot/core/ai.gd`
- Modify: `godot/tests/run_tests.gd` (add `_test_ai_fog`; register it)

- [ ] **Step 1: Register the test call**

In `_initialize()`, after `_test_fog_state()` add:

```gdscript
	_test_ai_fog()
```

- [ ] **Step 2: Write the failing test**

Append to `godot/tests/run_tests.gd`:

```gdscript
func _test_ai_fog() -> void:
	# With fog on, build_threat_map ignores enemies the owner cannot see.
	var gs := _flat_state(9, 9)
	gs.spawn_unit("cinderling", 0, 4, 4)        # owner-0 vision source (sight 3)
	gs.spawn_unit("cinderling", 1, 6, 4)        # visible enemy (dist 2 from the source)
	gs.spawn_unit("cinderling", 1, 0, 0)        # hidden enemy (dist 8 — out of vision)
	gs.fog = true
	var tf := AI.build_threat_map(gs, 0)
	_ok(tf.get("6,5", 0) > 0, "ai fog: visible enemy still threatens")
	_eq(tf.get("0,1", 0), 0, "ai fog: hidden enemy contributes no threat")
	# With fog off, the same hidden enemy IS counted (regression / determinism).
	gs.fog = false
	var tn := AI.build_threat_map(gs, 0)
	_ok(tn.get("0,1", 0) > 0, "ai fog off: all enemies threaten (baseline)")
```

- [ ] **Step 3: Run the test to verify it fails**

Run: `pwsh -File godot/tests/run_tests.ps1`
Expected: FAIL — `ai fog: hidden enemy contributes no threat` (currently the hidden enemy is counted, so the value is > 0).

- [ ] **Step 4: Add the filter**

In `godot/core/ai.gd`, after the const block add a preload (after line 18 `const UnitTypes = preload("res://data/unit_types.gd")`):

```gdscript
const Vision = preload("res://core/vision.gd")
```

Replace `build_threat_map` (lines 27–39) with:

```gdscript
static func build_threat_map(state, owner: int) -> Dictionary:
	var threat := {}
	var vis: Dictionary = Vision.compute(state, owner) if state.fog else {}
	for e in state.alive_units(1 - owner):
		if state.fog and not vis.has(Hex.key(Vector2i(e["q"], e["r"]))):
			continue
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
```

In `run_summons`, replace the line (line 272):

```gdscript
	var enemies: Array = state.alive_units(1 - owner)
```
with:
```gdscript
	var enemies: Array = []
	var vis_s: Dictionary = Vision.compute(state, owner) if state.fog else {}
	for e in state.alive_units(1 - owner):
		if state.fog and not vis_s.has(Hex.key(Vector2i(e["q"], e["r"]))):
			continue
		enemies.append(e)
```

(Attack-target resolution in `score_attacks` is intentionally NOT filtered: an enemy within attack range — at most 2 — is always inside a sight radius of ≥3, so it is necessarily visible. See the spec's "Fair AI" note.)

- [ ] **Step 5: Run the test to verify it passes**

Run: `pwsh -File godot/tests/run_tests.ps1`
Expected: PASS — N = previous + 3. All existing `_test_ai_*` tests still pass (they use fog-off `_flat_state`/skirmish states, so the new branches are skipped → identical behavior).

- [ ] **Step 6: Commit**

```bash
git add godot/core/ai.gd godot/tests/run_tests.gd
git commit -m "[godot] P3 fog: fair-AI vision filter (threat map + summons)"
```

---

### Task 5: Settings store — fog default + merge validation

**Files:**
- Modify: `godot/core/settings_store.gd`
- Modify: `godot/tests/run_tests.gd` (add `_test_fog_settings`; register it)

- [ ] **Step 1: Register the test call**

In `_initialize()`, after `_test_ai_fog()` add:

```gdscript
	_test_fog_settings()
```

- [ ] **Step 2: Write the failing test**

Append to `godot/tests/run_tests.gd`:

```gdscript
func _test_fog_settings() -> void:
	_eq(SettingsStore.defaults()["fog"], false, "settings: fog defaults off")
	var merged := SettingsStore.merge(SettingsStore.defaults(), {"fog": true})
	_eq(merged["fog"], true, "settings: fog merges from a valid blob")
	var bad := SettingsStore.merge(SettingsStore.defaults(), {"fog": "yes"})
	_eq(bad["fog"], false, "settings: non-bool fog rejected")
```

- [ ] **Step 3: Run the test to verify it fails**

Run: `pwsh -File godot/tests/run_tests.ps1`
Expected: FAIL — `settings: fog defaults off` (key absent → `null`).

- [ ] **Step 4: Add the setting**

In `godot/core/settings_store.gd` `defaults()`, change the returned dict — add `"fog": false,` to the third line so it reads:

```gdscript
		"difficulty": "normal", "map_index": 0, "campaign_progress": 0,
		"music_on": true, "track_index": 0, "fog": false,
```

In `merge()`, after the `battle_scene` block (lines 29–30):

```gdscript
	if typeof(saved.get("battle_scene")) == TYPE_BOOL:
		out["battle_scene"] = saved["battle_scene"]
```
add:
```gdscript
	if typeof(saved.get("fog")) == TYPE_BOOL:
		out["fog"] = saved["fog"]
```

- [ ] **Step 5: Run the test to verify it passes**

Run: `pwsh -File godot/tests/run_tests.ps1`
Expected: PASS — N = previous + 3.

- [ ] **Step 6: Commit**

```bash
git add godot/core/settings_store.gd godot/tests/run_tests.gd
git commit -m "[godot] P3 fog: fog setting default + merge validation"
```

---

### Task 6: Battle record — `attacker_pos`

**Files:**
- Modify: `godot/core/combat.gd`
- Modify: `godot/tests/run_tests.gd` (one assert inside `_test_battle_record`)

- [ ] **Step 1: Write the failing assert**

In `godot/tests/run_tests.gd` `_test_battle_record`, right after the line `var rec: Dictionary = gs.battle_log[0]` (line 1052) add:

```gdscript
	_eq(rec["attacker_pos"], Vector2i(2, 3), "record: attacker position captured")
```

(The attacker `atk` was spawned at `(2, 3)` on the line above.)

- [ ] **Step 2: Run the test to verify it fails**

Run: `pwsh -File godot/tests/run_tests.ps1`
Expected: FAIL — `record: attacker position captured` (key absent → `null` ≠ `Vector2i(2,3)`).

- [ ] **Step 3: Add the field**

In `godot/core/combat.gd`, in the `state.battle_log.append({ ... })` block (starts line 86), add a line after `"attacker": _combatant_view(attacker), "defender": _combatant_view(defender),`:

```gdscript
		"attacker_pos": Vector2i(attacker["q"], attacker["r"]),
```

(The attacker has already moved to its attack tile before `resolve_attack` runs, so `attacker["q"]/["r"]` is the attack origin. `battle_log` is transient — drained immediately, never serialized — so a `Vector2i` value is fine.)

- [ ] **Step 4: Run the test to verify it passes**

Run: `pwsh -File godot/tests/run_tests.ps1`
Expected: PASS — N = previous + 1.

- [ ] **Step 5: Commit**

```bash
git add godot/core/combat.gd godot/tests/run_tests.gd
git commit -m "[godot] P3 fog: record attacker_pos for cutaway ambush reveal"
```

---

### Task 7: Wire `fog` at match start + flag mission 4

**Files:**
- Modify: `godot/core/session.gd`
- Modify: `godot/data/campaign.gd`

No new harness test (Session match-start is node-free but exercised by the headless boot + manual pass). The `_test_new_campaign`/`_test_session` suites must still pass.

- [ ] **Step 1: Wire skirmish fog**

In `godot/core/session.gd` `start_skirmish()`, after the line `state.campaign_index = -1` (line 44) add:

```gdscript
	state.fog = bool(settings.get("fog", false)) or bool(def.get("fog", false))
```

- [ ] **Step 2: Wire campaign fog**

Replace `start_campaign()` (lines 47–49) with:

```gdscript
func start_campaign(index: int) -> void:
	state = GameStateLib.new_campaign(Campaign.CAMPAIGN[index], index)
	state.fog = bool(Campaign.CAMPAIGN[index]["map"].get("fog", false))
	screen = "play"
```

- [ ] **Step 3: Flag mission 4 with fog**

In `godot/data/campaign.gd`, in the fourth mission ("The Wraithspire", index 3), change its `"map"` dict line (line 26) from:

```gdscript
	         "mountains": 4, "lakes": 3, "forests": 24, "hills": 12, "towers": 6, "relics": 2},
```
to:
```gdscript
	         "mountains": 4, "lakes": 3, "forests": 24, "hills": 12, "towers": 6, "relics": 2, "fog": true},
```

- [ ] **Step 4: Run gates**

Run: `pwsh -File godot/tests/run_tests.ps1`
Expected: PASS — N unchanged from Task 6 (existing campaign/session tests still green; the added `fog` key on the def is ignored by map-gen).

Run: `godot --headless --path godot --quit-after 30 2>&1 | Select-String "SCRIPT ERROR|Parse Error|Failed to load"`
Expected: no matches.

- [ ] **Step 5: Commit**

```bash
git add godot/core/session.gd godot/data/campaign.gd
git commit -m "[godot] P3 fog: wire fog at match start; flag mission 4 (Wraithspire)"
```

---

### Task 8: Title screen skirmish fog toggle

**Files:**
- Modify: `godot/scenes/title/title_scene.gd`

Verified by the headless boot + manual pass (procedural Control, harness-invisible).

- [ ] **Step 1: Add the rect helper**

In `godot/scenes/title/title_scene.gd`, after `_continue_rect()` (ends line 55) add:

```gdscript
func _fog_rect() -> Rect2:
	return Rect2(CW / 2 - 70, 668, 140, 22)
```

- [ ] **Step 2: Draw the toggle**

In `_draw()`, immediately before the `# map selector` comment (line 95), add:

```gdscript
	# fog toggle (skirmish)
	var fr := _fog_rect()
	var fog_on: bool = session.settings.get("fog", false)
	draw_rect(fr, Pal.PURPLE if fog_on else Color(0.12, 0.11, 0.19, 0.85))
	draw_rect(fr, Pal.PURPLE if fog_on else Pal.INK_FAINT, false, 1.0)
	draw_string(fnt, Vector2(fr.position.x, fr.position.y + 15), "FOG: ON" if fog_on else "FOG: OFF", HORIZONTAL_ALIGNMENT_CENTER, fr.size.x, 12, Pal.BG if fog_on else Pal.INK_DIM)
```

- [ ] **Step 3: Handle the click**

In `_gui_input()`, before the final `begin_skirmish.emit()` (line 136) add:

```gdscript
	if _fog_rect().has_point(p):
		session.settings["fog"] = not session.settings.get("fog", false)
		session.persist_prefs(); return
```

(`persist_prefs()` writes the whole `settings` blob via `SettingsStore.save_blob`, so `fog` persists across sessions.)

- [ ] **Step 4: Run the headless boot**

Run: `godot --headless --path godot --quit-after 30 2>&1 | Select-String "SCRIPT ERROR|Parse Error|Failed to load"`
Expected: no matches.

Run: `pwsh -File godot/tests/run_tests.ps1`
Expected: PASS — N unchanged.

- [ ] **Step 5: Commit**

```bash
git add godot/scenes/title/title_scene.gd
git commit -m "[godot] P3 fog: title-screen skirmish fog toggle (default off)"
```

---

### Task 9: Render gating — dim overlay + enemy hiding

**Files:**
- Modify: `godot/scenes/match/overlay.gd`
- Modify: `godot/scenes/match/units_layer.gd`

- [ ] **Step 1: Add the fog fill to the overlay**

In `godot/scenes/match/overlay.gd`, after the `var selected: Variant = null` line (line 16) add:

```gdscript
var fogged: Dictionary = {}
```

After `set_armed()` (ends line 25) add:

```gdscript
func set_fog(tiles: Dictionary) -> void:
	fogged = tiles
	queue_redraw()
```

In `_draw()` (line 39), add as the FIRST fill (before the `reachable` fill on line 40):

```gdscript
	_fill(fogged, Color(0.02, 0.02, 0.06, 0.55))
```

(Do NOT clear `fogged` in `clear_all()` — fog is managed independently by `match_scene._refresh_fog`, not tied to unit selection.)

- [ ] **Step 2: Gate enemy nodes in the units layer**

In `godot/scenes/match/units_layer.gd`, after the `const UnitNodeScript = preload(...)` line (line 7) add:

```gdscript
const Hex = preload("res://core/hex.gd")
```

After `var state` (line 9) add:

```gdscript
var viewer: int = 0   # the human side; enemies outside its vision are not drawn under fog
```

Replace the loop body of `_rebuild()` (lines 20–26) with:

```gdscript
	for u in state.units:
		if u["hp"] <= 0:
			continue
		if state.fog and u["owner"] != viewer and not state.visibility.has(Hex.key(Vector2i(u["q"], u["r"]))):
			continue
		var node: Node2D = UnitNodeScript.new()
		add_child(node)
		node.bind(u)
```

- [ ] **Step 3: Run the headless boot**

Run: `godot --headless --path godot --quit-after 30 2>&1 | Select-String "SCRIPT ERROR|Parse Error|Failed to load"`
Expected: no matches.

Run: `pwsh -File godot/tests/run_tests.ps1`
Expected: PASS — N unchanged (overlay/units_layer are node scripts; `board.gd`/`battle_scene.gd` are the only force-preloaded ones, so these don't affect the suite — but confirm green).

- [ ] **Step 4: Commit**

```bash
git add godot/scenes/match/overlay.gd godot/scenes/match/units_layer.gd
git commit -m "[godot] P3 fog: dim overlay + hide enemies outside vision"
```

---

### Task 10: `match_scene` — recompute timing + ambush reveal

**Files:**
- Modify: `godot/scenes/match/match_scene.gd`

This is the integration task: compute the viewer, refresh fog on every vision-changing event, and reveal ambush attackers after their cutaway. Verified by the headless boot + the manual windowed pass (Task 11).

- [ ] **Step 1: Add the `_viewer` field**

In `godot/scenes/match/match_scene.gd`, after `var _match_over := false` (line 48) add:

```gdscript
	var _viewer := 0   # the human side (non-AI); the board renders from its vision under fog
```

(Member vars in this file are indented one tab.)

- [ ] **Step 2: Add the `_refresh_fog` helper**

After `_finish_action()` (ends line 396) add:

```gdscript
## _refresh_fog — recompute the viewer's vision (when fog is on), push the dim overlay, and
## rebuild the unit nodes (hiding enemies outside vision). Called on match start and after
## every move/summon/death/turn. A no-op overlay when fog is off.
func _refresh_fog() -> void:
	units_layer.viewer = _viewer
	if state.fog:
		state.recompute_visibility(_viewer)
		var fogged := {}
		for k in state.map.get("cells", {}):
			if not state.visibility.has(k):
				fogged[k] = true
		overlay.set_fog(fogged)
	else:
		overlay.set_fog({})
	units_layer.set_state(state)
```

- [ ] **Step 3: Compute the viewer and seed fog on match start**

In `_ready()`, replace the block (lines 67–69):

```gdscript
	units_layer = UnitsLayerScript.new()
	units_layer.set_state(state)
	add_child(units_layer)
```
with:
```gdscript
	units_layer = UnitsLayerScript.new()
	_viewer = state.is_ai.find(false)
	if _viewer < 0:
		_viewer = 0
	units_layer.viewer = _viewer
	units_layer.set_state(state)
	add_child(units_layer)
```

At the end of `_ready()` (after the last line, `top_bar.settings_pressed.connect(...)`, line 94) add:

```gdscript
	_refresh_fog()
```

- [ ] **Step 4: Route vision-changing refreshes through `_refresh_fog`**

Make these replacements (each is a `units_layer.set_state(state)` that follows a position/turn change):

In `_on_click`, the post-pickup refresh (line 179) — change:
```gdscript
				units_layer.set_state(state)
```
to:
```gdscript
				_refresh_fog()
```

In `_on_action_chosen` "undo" branch (line 225) — change:
```gdscript
					units_layer.set_state(state)
```
to:
```gdscript
					_refresh_fog()
```

In `_arm_ability` second-move branch (line 248) — change:
```gdscript
					units_layer.set_state(state)
```
to:
```gdscript
					_refresh_fog()
```

In `_slide_unit`, the FINAL snap (line 329) — change:
```gdscript
	units_layer.set_state(state)
```
to:
```gdscript
	_refresh_fog()
```
(Leave the mid-slide `units_layer.set_state(state)` on line 321 unchanged — it positions the node for the tween; the post-tween `_refresh_fog()` recomputes once the move lands.)

In `_finish_action()` (line 394) — change:
```gdscript
	units_layer.set_state(state)
```
to:
```gdscript
	_refresh_fog()
```

- [ ] **Step 5: Clear stale reveals + ambush reveal in the turn/battle flow**

In `_on_end_turn()`, after the guard lines and before `state.end_turn()` (line 123) add `state.revealed.clear()` so it reads:

```gdscript
func _on_end_turn() -> void:
	if _busy:
		return
	if state.winner != -1:
		return
	state.revealed.clear()
	state.end_turn()
```

In `_play_battles()`, replace the whole function body (lines 293–315) with the version below — it (a) reveals ambush attackers in the silent path, (b) reveals + refreshes per cutaway in the animated path:

```gdscript
func _play_battles() -> void:
	if state.battle_log.is_empty():
		return
	var show: bool = session == null or session.settings.get("battle_scene", true)
	if not show:
		for rec in state.battle_log:
			if state.fog and rec.has("attacker_pos"):
				state.revealed[Hex.key(rec["attacker_pos"])] = true
		state.battle_log.clear()   # combat already resolved; skip the animation
		_refresh_fog()
		if top_bar != null:
			top_bar.refresh(state)
		if state.winner != -1:
			_end_match()
		return
	_busy = true
	while not state.battle_log.is_empty():
		var rec: Dictionary = state.battle_log.pop_front()
		battle_scene.play(rec)
		await battle_scene.finished
		if state.fog and rec.has("attacker_pos"):
			state.revealed[Hex.key(rec["attacker_pos"])] = true
		_refresh_fog()
	_busy = false
	if top_bar != null:
		top_bar.refresh(state)
	if state.winner != -1:
		_end_match()
```

(`_refresh_fog()` recomputes from unit positions and unions in `state.revealed`, so each ambushed attacker stays visible for the rest of the AI turn. `state.revealed.clear()` at the top of the human's next `_on_end_turn` drops them.)

- [ ] **Step 6: Run the gates**

Run: `godot --headless --path godot --quit-after 30 2>&1 | Select-String "SCRIPT ERROR|Parse Error|Failed to load"`
Expected: no matches.

Run: `pwsh -File godot/tests/run_tests.ps1`
Expected: PASS — N unchanged.

- [ ] **Step 7: Commit**

```bash
git add godot/scenes/match/match_scene.gd
git commit -m "[godot] P3 fog: recompute timing + cutaway ambush reveal"
```

---

### Task 11: Whole-milestone review + manual windowed pass

**Files:** none (review only).

- [ ] **Step 1: Whole-milestone code review**

Dispatch an opus review over `git diff main...godot-p3-fog`. Focus: vision purity (no state mutation), determinism (fog-off paths byte-identical — AI tests prove it), no leak of hidden enemies via any player-facing query, save round-trip, no transform/clip leaks in the overlay fill.

- [ ] **Step 2: Run both gates one final time**

Run: `pwsh -File godot/tests/run_tests.ps1` → `== N passed, 0 failed ==`, EXIT 0.
Run: `godot --headless --path godot --quit-after 30 2>&1 | Select-String "SCRIPT ERROR|Parse Error|Failed to load"` → no matches.

- [ ] **Step 3: Manual windowed pass** (`godot --path godot`, needs a display)

Checklist:
- Title → toggle **FOG: ON** → start skirmish → out-of-vision tiles are dimmed; enemy units beyond your vision are not drawn.
- Move a unit toward the enemy → fog lifts around it as it advances (live reveal); enemies pop into view at range 3 (4 for flyers).
- End your turn → the AI plays from fog (it doesn't path toward units it can't see); when an AI unit attacks you from the dark, the battle cutaway plays and the attacker's tile stays revealed for the rest of the turn; your next end-turn re-hides it.
- Pick up a **Veilstone** (glyph **E**) → that unit's vision radius grows by 1.
- Title → **FOG: OFF** → start skirmish → no dimming, all enemies drawn (baseline behavior).
- Settings → **BATTLE SCENE OFF** with fog on → AI ambushes still reveal the attacker tile (silent-drain path).
- Campaign → mission 4 "The Wraithspire" starts with fog on regardless of the title toggle.
- Save under fog (end a turn, quit, relaunch, CONTINUE) → the resumed match is still fogged.

- [ ] **Step 4: Roadmap check-off + handoff**

Check off ROADMAP2 items 3.1 and 3.2 in `ROADMAP2.md`. Update `SESSION_STATE.md` + `HANDOFF.md` with the Phase-3 completion block. Update auto-memory (`wraithspire-godot-port.md`). Commit:

```bash
git add ROADMAP2.md SESSION_STATE.md HANDOFF.md
git commit -m "[godot] P3 fog complete: roadmap check-off + session handoff"
```

Then FF-merge to `main` + push **only after the user approves**.

---

## Self-review

**Spec coverage:**
- Visibility engine (r3/r4/r2, Veilstone) → Tasks 1, 2. ✓
- `GameState` fog/visibility cache + recompute-on-event → Tasks 3, 10. ✓
- Fair AI (threat map + summons filtered to visible) → Task 4. ✓
- Dim overlay + hidden enemies → Task 9. ✓
- Hover/forecast refuse hidden → covered structurally: no player-facing enemy card/forecast exists (clicking an enemy clears selection; in-range enemies are always within sight). Documented in spec §5; no task needed. ✓
- Title toggle (default off) + settings persistence → Tasks 5, 8. ✓
- Map-def fog flag → Task 7 (mission 4). ✓
- Save round-trip of `fog` → Task 3. ✓
- Cutaway ambush reveal → Tasks 6, 10. ✓
- Smoke/test path stays fog-off → all `_flat_state`/skirmish test states default `fog=false`; AI regression assert in Task 4. ✓

**Placeholder scan:** none — every code step shows full code.

**Type consistency:** `Vision.compute(state, owner) -> Dictionary` (set of keys) used consistently in `recompute_visibility`, `build_threat_map`, `run_summons`. `unit_sight(unit) -> int`. `state.fog: bool`, `state.visibility: Dictionary`, `state.revealed: Dictionary`. `units_layer.viewer: int`, `overlay.set_fog(Dictionary)`, `_refresh_fog()`. Battle record key `attacker_pos: Vector2i`, read via `Hex.key(...)`. Relic key `"vision"` read by `Relics.unit_bonus`/`Relics.bonus`. All consistent across tasks.
