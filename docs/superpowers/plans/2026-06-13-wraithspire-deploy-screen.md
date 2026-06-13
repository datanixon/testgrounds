# Phase 5.2 Deploy Screen + Survivors + AI Scaling Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add the campaign deploy loop — pick veterans from the 5.1 roster before a mission, place them, scale the AI to the army's value, and carry survivors back into the roster on a win (permadeath for the fallen).

**Architecture:** A new pure `core/deploy.gd` (reconstruct unit from entry / value army / scale AI / place) feeding a new `scenes/deploy/deploy_scene.gd` (Control picker, mirrors `campaign_scene`), wired into the router as a `story → deploy → play` step; `Session.on_match_won` reconciles survivors via the existing `RosterStore.reconcile`; `GameState.deployed_roster_ids` + per-unit `roster_id` persist through save. Campaign-only; skirmish untouched.

**Tech Stack:** Godot 4 / GDScript. Harness `godot/tests/run_tests.gd` (`_test_*` in `_initialize()`; `_eq`/`_ok`; preloads `RosterStore`, `GameState`, `Campaign`, `SaveGame`, `Session`, `AI`, `UnitTypes`). Gate: `pwsh -File godot/tests/run_tests.ps1` (`== N passed, 0 failed ==`, EXIT 0; never `-ExecutionPolicy Bypass`). Indentation TABS.

---

## File Structure

| File | Responsibility | Task |
|---|---|---|
| `godot/core/deploy.gd` | pure deploy ops (reconstruct/value/scale/slots/place) | 1,2 |
| `godot/core/game_state.gd` | `deployed_roster_ids` field | 2 |
| `godot/core/save_game.gd` | serialize `deployed_roster_ids` + `roster_id` coercion | 3 |
| `godot/scenes/deploy/deploy_scene.gd` | the veteran-picker Control | 4 |
| `godot/scenes/main.gd` | router `"deploy"` case + begin/back handlers + shots | 4 |
| `godot/core/session.gd` | `start_campaign` screen change; `on_match_won` reconcile | 4,5 |
| `godot/data/campaign.gd` | `deploy_slots` per scenario | 5 |
| `godot/tests/run_tests.gd` | `_test_deploy_*` | 1,2,3,5 |

Five tasks. Tasks 1–3 + 5 are TDD (stub → RED → GREEN). Task 4 is the render-layer scene + router wiring (no unit test; validated by headless boot + `--shot deploy`).

---

## Task 1: `core/deploy.gd` pure helpers

**Files:**
- Create: `godot/core/deploy.gd`
- Modify: `godot/tests/run_tests.gd`

- [ ] **Step 1: Create the module with class header + stubs (so the harness compiles)**

Create `godot/core/deploy.gd`:

```gdscript
class_name Deploy
extends RefCounted
## Phase 5.2 campaign deploy. Pure-ish helpers (harness-tested) for the pre-mission
## veteran picker: reconstruct a live unit from a roster entry, value the deployed
## army, scale AI opening strength, resolve the per-mission slot cap, and place the
## chosen veterans. Takes `state` as a param (no GameState preload cycle — mirrors
## core/ai.gd) and reuses the global AI class + RosterStore's carry-field contract.

const RosterStore = preload("res://core/roster_store.gd")
const UnitTypes = preload("res://data/unit_types.gd")

const AI_SCALE_DIVISOR := 10   # roster value per +1 AI MP
const AI_SCALE_CAP := 12       # max extra AI MP from scaling
const DEFAULT_SLOTS := 3       # deploy cap when a scenario omits deploy_slots

static func unit_from_entry(entry: Dictionary, id: int, owner: int, q: int, r: int) -> Dictionary:
	return {}

static func roster_value(entries: Array) -> int:
	return 0

static func ai_scale_mp(value: int) -> int:
	return 0

static func slots_for(scenario: Dictionary) -> int:
	return 0
```

- [ ] **Step 2: Wire preload + register + write the failing test**

In `godot/tests/run_tests.gd` preload block (after the `RosterStore` line):

```gdscript
const Deploy = preload("res://core/deploy.gd")
```

In `_initialize()`, after `_test_roster_roundtrip()`:

```gdscript
	_test_deploy_helpers()
```

Add the test function:

```gdscript
func _test_deploy_helpers() -> void:
	# unit_from_entry rebuilds a ready live unit from a snapshot entry.
	var entry := {
		"roster_id": 5, "type_key": "earthbreaker", "name": "Earthbreaker", "element": "terra",
		"sprite": "earthbreaker", "attack": "melee", "relic": "vital",
		"flying": false, "evolved": true,
		"level": 4, "xp": 0, "max_hp": 54, "power": 17, "def": 9, "move": 2, "range": 1,
	}
	var u := Deploy.unit_from_entry(entry, 1001, 0, 3, 4)
	_eq(u["id"], 1001, "deploy: unit id set")
	_eq(u["owner"], 0, "deploy: owner set")
	_eq(u["q"], 3, "deploy: q set")
	_eq(u["r"], 4, "deploy: r set")
	_eq(u["roster_id"], 5, "deploy: roster_id stamped")
	_eq(u["type_key"], "earthbreaker", "deploy: type_key restored")
	_eq(u["level"], 4, "deploy: level restored")
	_eq(u["max_hp"], 54, "deploy: max_hp restored")
	_eq(u["hp"], 54, "deploy: hp restored to full")
	_eq(u["power"], 17, "deploy: power restored")
	_eq(u["relic"], "vital", "deploy: relic restored")
	_eq(u["evolved"], true, "deploy: evolved restored")
	_eq(u["is_master"], false, "deploy: not a master")
	_eq(u["acted"], false, "deploy: ready to act turn 1")
	_eq(u["cd"], 0, "deploy: cd reset")
	_eq(u["second_move"], false, "deploy: second_move reset")
	# roster_value sums type costs (earthbreaker 30 + cinderling 6 = 36).
	_eq(Deploy.roster_value([entry, {"type_key": "cinderling"}]), 36, "deploy: roster_value sums costs")
	_eq(Deploy.roster_value([]), 0, "deploy: empty army worth 0")
	# ai_scale_mp: zero, linear under cap, clamped.
	_eq(Deploy.ai_scale_mp(0), 0, "deploy: scale at 0")
	_eq(Deploy.ai_scale_mp(36), 3, "deploy: scale 36/10 = 3")
	_eq(Deploy.ai_scale_mp(1000), 12, "deploy: scale capped at 12")
	# slots_for: explicit vs default.
	_eq(Deploy.slots_for({"deploy_slots": 5}), 5, "deploy: explicit slots")
	_eq(Deploy.slots_for({}), 3, "deploy: default slots 3")
```

- [ ] **Step 3: Run, verify FAIL**

Run: `pwsh -File godot/tests/run_tests.ps1`
Expected: FAIL — stubs return `{}` / `0`; the deploy asserts fail, EXIT 1.

- [ ] **Step 4: Implement the four helpers for real**

Replace the four stub bodies in `godot/core/deploy.gd`:

```gdscript
static func unit_from_entry(entry: Dictionary, id: int, owner: int, q: int, r: int) -> Dictionary:
	var u := {
		"id": id, "owner": owner, "q": q, "r": r,
		"is_master": false, "acted": false, "cd": 0, "second_move": false,
		"roster_id": int(entry["roster_id"]),
	}
	for k in RosterStore._CARRY_STR:
		u[k] = String(entry.get(k, ""))
	for k in RosterStore._CARRY_INT:
		u[k] = int(entry.get(k, 0))
	for k in RosterStore._CARRY_BOOL:
		u[k] = bool(entry.get(k, false))
	u["hp"] = u["max_hp"]
	return u

static func roster_value(entries: Array) -> int:
	var total := 0
	for e in entries:
		total += int(UnitTypes.UNIT_TYPES.get(e["type_key"], {}).get("cost", 0))
	return total

static func ai_scale_mp(value: int) -> int:
	return clampi(value / AI_SCALE_DIVISOR, 0, AI_SCALE_CAP)

static func slots_for(scenario: Dictionary) -> int:
	return int(scenario.get("deploy_slots", DEFAULT_SLOTS))
```

- [ ] **Step 5: Run, verify PASS**

Run: `pwsh -File godot/tests/run_tests.ps1`
Expected: PASS — `== N passed, 0 failed ==`, EXIT 0 (N ≈ +22 vs the 1067 baseline).

- [ ] **Step 6: Commit**

```bash
git add godot/core/deploy.gd godot/tests/run_tests.gd
git commit -m "[godot] P5.2 deploy: unit_from_entry + roster_value + ai_scale_mp + slots_for"
```

---

## Task 2: `Deploy.commit` + `GameState.deployed_roster_ids`

**Files:**
- Modify: `godot/core/game_state.gd`
- Modify: `godot/core/deploy.gd`
- Modify: `godot/tests/run_tests.gd`

- [ ] **Step 1: Add the `deployed_roster_ids` field to GameState**

In `godot/core/game_state.gd`, find the instance-variable block near the top (where `var units`, `var turn`, `var objective` etc. are declared) and add:

```gdscript
var deployed_roster_ids: Array[int] = []   # roster_ids of veterans deployed this match (Phase 5.2); SAVED
```

In `new_skirmish` (after `gs.objective_progress = {"start_turn": gs.turn}`), add:

```gdscript
	gs.deployed_roster_ids = []
```

- [ ] **Step 2: Add a stub `commit` to deploy.gd (so the harness compiles)**

Append to `godot/core/deploy.gd`:

```gdscript
# Place the chosen veterans on the board near the player master, record their
# roster_ids on the state, and bump the AI master's MP by the scaled army value.
static func commit(state, entries: Array) -> void:
	pass
```

- [ ] **Step 3: Register + write the failing test**

In `_initialize()`, after `_test_deploy_helpers()`:

```gdscript
	_test_deploy_commit()
```

Add the test function:

```gdscript
func _test_deploy_commit() -> void:
	var def: Dictionary = Campaign.CAMPAIGN[0]["map"]
	var gs := GameState.new_skirmish(def, def["seed"])
	var m1_mp0: int = gs.master_of(1)["mp"]
	var m1_maxmp: int = gs.master_of(1)["max_mp"]
	var n0: int = gs.units.size()
	var entries := [
		{"roster_id": 1, "type_key": "stoneward", "name": "Stoneward", "element": "terra", "sprite": "golem", "attack": "melee", "relic": "", "flying": false, "evolved": false, "level": 2, "xp": 0, "max_hp": 30, "power": 7, "def": 6, "move": 2, "range": 1},
		{"roster_id": 2, "type_key": "tidekin", "name": "Tidekin", "element": "hydro", "sprite": "merfolk", "attack": "melee", "relic": "", "flying": false, "evolved": false, "level": 3, "xp": 0, "max_hp": 26, "power": 8, "def": 4, "move": 4, "range": 1},
	]
	Deploy.commit(gs, entries)
	_eq(gs.units.size(), n0 + 2, "deploy commit: 2 veterans placed")
	_eq(gs.deployed_roster_ids, [1, 2], "deploy commit: deployed ids recorded")
	var found := 0
	for u in gs.alive_units(0):
		if int(u.get("roster_id", -1)) in [1, 2]:
			found += 1
			_eq(u["owner"], 0, "deploy commit: veteran owner 0")
			_eq(u["hp"], u["max_hp"], "deploy commit: veteran at full hp")
			_eq(u["acted"], false, "deploy commit: veteran ready turn 1")
	_eq(found, 2, "deploy commit: both veterans alive on player 0")
	_eq(gs.stats["summoned"][0], 0, "deploy commit: summoned stat NOT bumped")
	# AI mp bumped by ai_scale_mp(roster_value): stoneward 8 + tidekin 7 = 15 -> 15/10 = 1.
	_eq(gs.master_of(1)["mp"], clampi(m1_mp0 + 1, mini(4, m1_maxmp), m1_maxmp), "deploy commit: AI mp scaled +1")
```

- [ ] **Step 4: Run, verify FAIL**

Run: `pwsh -File godot/tests/run_tests.ps1`
Expected: FAIL — the `commit` stub does nothing; `units.size()`, `deployed_roster_ids`, and the AI-mp asserts fail, EXIT 1.

- [ ] **Step 5: Implement `commit` for real**

Replace the `commit` stub body in `godot/core/deploy.gd`:

```gdscript
static func commit(state, entries: Array) -> void:
	var m0 = state.master_of(0)
	for e in entries:
		if m0 == null:
			break
		var slot = AI.find_summon_slot(state, m0)
		if slot == null:
			break   # board full near the master; place what fits
		var u := unit_from_entry(e, state._new_id(), 0, slot.x, slot.y)
		state.units.append(u)
		state.deployed_roster_ids.append(int(e["roster_id"]))
	var m1 = state.master_of(1)
	if m1 != null:
		var extra := ai_scale_mp(roster_value(entries))
		m1["mp"] = clampi(m1["mp"] + extra, mini(4, m1["max_mp"]), m1["max_mp"])
```

(`AI` is the global class from `core/ai.gd` — `Deploy` has a `class_name`, so the bare `AI.find_summon_slot` reference resolves. `find_summon_slot(state, master)` returns a `Vector2i` open hex near `master`, or `null`.)

- [ ] **Step 6: Run, verify PASS**

Run: `pwsh -File godot/tests/run_tests.ps1`
Expected: PASS — `== N passed, 0 failed ==`, EXIT 0 (N ≈ +8 vs Task 1).

- [ ] **Step 7: Headless boot (GameState changed)**

Run: `godot --headless --path godot --quit-after 30 2>&1 | Select-String "SCRIPT ERROR|Parse Error|Failed to load"`
Expected: no matches.

- [ ] **Step 8: Commit**

```bash
git add godot/core/deploy.gd godot/core/game_state.gd godot/tests/run_tests.gd
git commit -m "[godot] P5.2 deploy: commit (place veterans + AI scaling) + deployed_roster_ids"
```

---

## Task 3: Save round-trip for `deployed_roster_ids` + `roster_id`

**Files:**
- Modify: `godot/core/save_game.gd`
- Modify: `godot/tests/run_tests.gd`

- [ ] **Step 1: Serialize `deployed_roster_ids` in `to_dict`**

In `godot/core/save_game.gd` `to_dict`, add a line to the returned dictionary (after the `"relics"` line):

```gdscript
		"deployed_roster_ids": state.deployed_roster_ids.duplicate(),
```

- [ ] **Step 2: Restore `deployed_roster_ids` + coerce `roster_id` in `from_dict`**

In `from_dict`, add `"roster_id"` to the per-unit numeric-field coercion loop. The loop currently reads:

```gdscript
	for ud in units:
		for k in ["id", "owner", "q", "r", "hp", "max_hp", "move", "range", "power", "def", "level", "xp", "cd", "mp", "max_mp", "mp_regen"]:
			if ud.has(k):
				ud[k] = int(ud[k])
```

Change the key list to include `"roster_id"`:

```gdscript
	for ud in units:
		for k in ["id", "owner", "q", "r", "hp", "max_hp", "move", "range", "power", "def", "level", "xp", "cd", "mp", "max_mp", "mp_regen", "roster_id"]:
			if ud.has(k):
				ud[k] = int(ud[k])
```

Then, just before `return gs` at the end of `from_dict`, add:

```gdscript
	var dids: Array[int] = []
	for x in blob.get("deployed_roster_ids", []):
		dids.append(int(x))
	gs.deployed_roster_ids = dids
```

- [ ] **Step 3: Register + write the failing test**

In `_initialize()`, after `_test_deploy_commit()`:

```gdscript
	_test_deploy_save()
```

Add the test function:

```gdscript
func _test_deploy_save() -> void:
	var def: Dictionary = Campaign.CAMPAIGN[0]["map"]
	var gs := GameState.new_skirmish(def, def["seed"])
	Deploy.commit(gs, [{"roster_id": 7, "type_key": "stoneward", "name": "Stoneward", "element": "terra", "sprite": "golem", "attack": "melee", "relic": "", "flying": false, "evolved": false, "level": 2, "xp": 0, "max_hp": 30, "power": 7, "def": 6, "move": 2, "range": 1}])
	var parsed = JSON.parse_string(JSON.stringify(SaveGame.to_dict(gs)))
	var gs2 := SaveGame.from_dict(parsed)
	_ok(gs2 != null, "deploy save: round-trips")
	_eq(gs2.deployed_roster_ids, [7], "deploy save: deployed_roster_ids preserved")
	var vet = null
	for u in gs2.units:
		if int(u.get("roster_id", -1)) == 7:
			vet = u
	_ok(vet != null, "deploy save: deployed unit kept its roster_id")
	_eq(typeof(vet["roster_id"]), TYPE_INT, "deploy save: roster_id re-coerced to int")
```

- [ ] **Step 4: Run, verify FAIL**

Run: `pwsh -File godot/tests/run_tests.ps1`
Expected: FAIL — without Step 1/2 the round-trip drops `deployed_roster_ids` (asserts `[7]` fails) or the test compiles against the already-applied impl; if Steps 1–2 are done before this step, instead temporarily confirm the test exercises the path. (If you implemented Steps 1–2 first, this test PASSES immediately — that is acceptable for a serialization round-trip; the key requirement is that the assert exists and passes.)

- [ ] **Step 5: Run, verify PASS**

Run: `pwsh -File godot/tests/run_tests.ps1`
Expected: PASS — `== N passed, 0 failed ==`, EXIT 0 (N ≈ +4 vs Task 2).

- [ ] **Step 6: Commit**

```bash
git add godot/core/save_game.gd godot/tests/run_tests.gd
git commit -m "[godot] P5.2 deploy: persist deployed_roster_ids + roster_id through save"
```

---

## Task 4: Deploy scene + router wiring + shots

**Files:**
- Create: `godot/scenes/deploy/deploy_scene.gd`
- Modify: `godot/core/session.gd` (`start_campaign` screen)
- Modify: `godot/scenes/main.gd` (preloads, `"deploy"` route, handlers, shots)

- [ ] **Step 1: Create the deploy scene**

Create `godot/scenes/deploy/deploy_scene.gd`:

```gdscript
class_name DeployScene
extends Control
## Phase 5.2 pre-mission veteran picker. Lists the campaign roster, lets the player
## select up to the mission's deploy-slot cap, then emits the chosen entry dicts to
## begin. Mirrors campaign_scene's procedural row-list. ESC -> back to campaign list.

const Pal = preload("res://data/palette.gd")
const RosterStore = preload("res://core/roster_store.gd")
const Deploy = preload("res://core/deploy.gd")

signal begin_mission(picked_entries: Array)
signal back

const CW := 1280.0
const CH := 800.0
const ROW_BG := Color(0.09, 0.08, 0.14)

var session = null
var scenario: Dictionary = {}
var roster: Array = []
var picked := {}            # roster_id -> true
var _reset_armed := false

func _ready() -> void:
	set_anchors_preset(Control.PRESET_TOP_LEFT)
	size = Vector2(CW, CH)
	if session != null:
		roster = RosterStore.load_or_init(session.campaign_progress).get("roster", [])

func _cap() -> int:
	return Deploy.slots_for(scenario)

func _row_rects() -> Array:
	var w := 720.0; var h := 56.0; var gap := 10.0
	var x := (CW - w) / 2.0
	var out: Array = []
	for i in range(roster.size()):
		out.append({"index": i, "r": Rect2(x, 190 + i * (h + gap), w, h)})
	return out

func _begin_rect() -> Rect2:
	return Rect2(CW / 2.0 - 110, CH - 70, 220, 40)

func _reset_rect() -> Rect2:
	return Rect2(CW - 240, 150, 200, 26)

func _draw() -> void:
	var fnt := ThemeDB.fallback_font
	draw_rect(Rect2(0, 0, CW, CH), Pal.BG)
	var title: String = scenario.get("name", "Mission")
	draw_string(fnt, Vector2(CW / 2.0 - 300, 90), "DEPLOY — %s" % title, HORIZONTAL_ALIGNMENT_CENTER, 600, 26, Pal.GOLD)
	draw_string(fnt, Vector2(CW / 2.0 - 300, 124), "choose up to %d veteran(s)  ·  %d / %d selected" % [_cap(), picked.size(), _cap()], HORIZONTAL_ALIGNMENT_CENTER, 600, 12, Pal.INK_DIM)
	if roster.is_empty():
		draw_string(fnt, Vector2(CW / 2.0 - 250, 240), "no veterans yet — summon fresh in battle", HORIZONTAL_ALIGNMENT_CENTER, 500, 14, Pal.INK_DIM)
	else:
		for row in _row_rects():
			var e: Dictionary = roster[row["index"]]
			var r: Rect2 = row["r"]
			var sel: bool = picked.has(int(e["roster_id"]))
			draw_rect(r, Pal.PANEL_LIGHT if sel else ROW_BG)
			draw_rect(r, Pal.GOLD if sel else Pal.INK_FAINT, false, 1.0)
			draw_string(fnt, Vector2(r.position.x + 16, r.position.y + 24), "%s    L%d    %s" % [e.get("name", "?"), int(e.get("level", 1)), String(e.get("element", "")).to_upper()], HORIZONTAL_ALIGNMENT_LEFT, -1, 15, Pal.GOLD if sel else Pal.INK)
			var relic: String = String(e.get("relic", ""))
			var line2: String = "HP %d   PWR %d   DEF %d%s" % [int(e.get("max_hp", 0)), int(e.get("power", 0)), int(e.get("def", 0)), ("    ·  relic: " + relic) if relic != "" else ""]
			draw_string(fnt, Vector2(r.position.x + 16, r.position.y + 44), line2, HORIZONTAL_ALIGNMENT_LEFT, -1, 11, Pal.INK_DIM)
	var br := _begin_rect()
	draw_rect(br, Pal.PANEL_LIGHT)
	draw_rect(br, Pal.GOLD, false, 1.0)
	draw_string(fnt, Vector2(br.position.x, br.position.y + 26), "BEGIN MISSION", HORIZONTAL_ALIGNMENT_CENTER, br.size.x, 15, Pal.GOLD)
	var rr := _reset_rect()
	draw_string(fnt, Vector2(rr.position.x, rr.position.y + 18), "click again to confirm reset" if _reset_armed else "↻ reset roster", HORIZONTAL_ALIGNMENT_LEFT, rr.size.x, 11, Pal.RED if _reset_armed else Pal.INK_FAINT)
	draw_string(fnt, Vector2(CW / 2.0 - 250, CH - 18), "click a veteran to toggle  ·  ESC to go back", HORIZONTAL_ALIGNMENT_CENTER, 500, 11, Pal.INK_DIM)

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and event.keycode == KEY_ESCAPE:
		back.emit()

func _gui_input(event: InputEvent) -> void:
	if not (event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT):
		return
	var pos: Vector2 = event.position
	if _begin_rect().has_point(pos):
		var out: Array = []
		for e in roster:
			if picked.has(int(e["roster_id"])):
				out.append(e)
		begin_mission.emit(out)
		return
	if _reset_rect().has_point(pos):
		if _reset_armed:
			RosterStore.reset()
			roster = RosterStore.load_or_init(session.campaign_progress).get("roster", [])
			picked.clear()
			_reset_armed = false
		else:
			_reset_armed = true
		queue_redraw()
		return
	_reset_armed = false
	for row in _row_rects():
		if (row["r"] as Rect2).has_point(pos):
			var rid: int = int(roster[row["index"]]["roster_id"])
			if picked.has(rid):
				picked.erase(rid)
			elif picked.size() < _cap():
				picked[rid] = true
			queue_redraw()
			return
```

- [ ] **Step 2: Switch the campaign start to land on the deploy screen**

In `godot/core/session.gd` `start_campaign`, change the final line from `screen = "play"` to `screen = "deploy"`:

```gdscript
func start_campaign(index: int) -> void:
	state = GameStateLib.new_campaign(Campaign.CAMPAIGN[index], index)
	state.fog = bool(Campaign.CAMPAIGN[index]["map"].get("fog", false))
	screen = "deploy"
```

- [ ] **Step 3: Wire the router**

In `godot/scenes/main.gd`, add to the preload block (after the `MatchScene` line):

```gdscript
const DeployScene = preload("res://scenes/deploy/deploy_scene.gd")
const DeployLib = preload("res://core/deploy.gd")
const Campaign = preload("res://data/campaign.gd")
const RosterStore = preload("res://core/roster_store.gd")
```

In `_route()`, add a `"deploy"` case (after the `"story"` case):

```gdscript
		"deploy":
			var d := DeployScene.new()
			d.session = session
			d.scenario = Campaign.CAMPAIGN[session.story_index]
			d.begin_mission.connect(_on_deploy_begin)
			d.back.connect(_on_deploy_back)
			_mount(d)
```

Add the two handlers (near `_on_begin_mission`):

```gdscript
func _on_deploy_begin(picked_entries: Array) -> void:
	DeployLib.commit(session.state, picked_entries)
	_go("play")

func _on_deploy_back() -> void:
	_go("campaign")
```

- [ ] **Step 4: Fix the `mission2` shot + add a `deploy` shot**

In `godot/scenes/main.gd` `_run_shot`, the `"mission2"` case currently expects `start_campaign` to land on play. Since it now lands on deploy, replace that case so it commits an empty deploy and proceeds to play:

```gdscript
			"mission2":
				session.start_campaign(1)
				DeployLib.commit(session.state, [])
				session.screen = "play"
				_route()
```

Add a new `"deploy"` case (seeds a 4-veteran roster so the rows render):

```gdscript
			"deploy":
				RosterStore.save(RosterStore.migrate(4))
				session.start_campaign(0)
				_route()
```

- [ ] **Step 5: Headless boot (new scene + main.gd + session changed)**

Run: `godot --headless --path godot --quit-after 30 2>&1 | Select-String "SCRIPT ERROR|Parse Error|Failed to load"`
Expected: no matches.

- [ ] **Step 6: Run the harness (no new tests, but must stay green)**

Run: `pwsh -File godot/tests/run_tests.ps1`
Expected: PASS — `== N passed, 0 failed ==`, EXIT 0 (unchanged count from Task 3).

- [ ] **Step 7: Visual check — capture the deploy screen**

Run: `godot --path godot -- --shot deploy`
Then read `godot/tools/shots/deploy.png`: confirm the "DEPLOY — The Border Skirmish" header, four veteran rows (Stoneward / Tidekin / Earthbreaker / Hexlord), the slot counter, BEGIN MISSION, and the reset hotspot all render on-screen.

- [ ] **Step 8: Commit**

```bash
git add godot/scenes/deploy/deploy_scene.gd godot/scenes/main.gd godot/core/session.gd
git commit -m "[godot] P5.2 deploy: picker scene + router story->deploy->play + shots"
```

---

## Task 5: Reconcile survivors on win + per-mission slot caps

**Files:**
- Modify: `godot/core/session.gd` (`on_match_won`)
- Modify: `godot/data/campaign.gd` (`deploy_slots`)
- Modify: `godot/tests/run_tests.gd`

- [ ] **Step 1: Add the `RosterStore` preload to session.gd**

In `godot/core/session.gd`, add to the const block (after the `SaveGame` line):

```gdscript
const RosterStore = preload("res://core/roster_store.gd")
```

- [ ] **Step 2: Reconcile survivors into the roster on a campaign win**

In `godot/core/session.gd`, replace `on_match_won` with:

```gdscript
func on_match_won(winner: int) -> void:
	if state != null and state.campaign_index >= 0 and winner == 0:
		# survivors carry into the roster; deployed veterans that died are gone (permadeath)
		var survivors: Array = []
		for u in state.alive_units(0):
			if not u.get("is_master", false):
				survivors.append(u)
		var blob := RosterStore.load_or_init(campaign_progress)
		blob = RosterStore.reconcile(blob, survivors, state.deployed_roster_ids)
		RosterStore.save(blob)
		campaign_progress = mini(Campaign.CAMPAIGN.size() - 1, maxi(campaign_progress, state.campaign_index + 1))
		persist_prefs()
	SaveGame.delete()
	has_save = false
```

- [ ] **Step 3: Add `deploy_slots` to the campaign scenarios**

In `godot/data/campaign.gd`, add `"deploy_slots": N` to each scenario's top-level dict (alongside `"ai_mp_bonus"`). Mission 1: `3`; mission 2: `3`; mission 3: `4`; mission 4: `4`. For example, mission 1's entry header becomes:

```gdscript
	{"name": "The Border Skirmish", "difficulty": "easy", "deploy_slots": 3,
```

and mission 3:

```gdscript
	{"name": "The Emberfall Passes", "difficulty": "normal", "deploy_slots": 4,
```

(Add the key to all four scenario dicts: 3, 3, 4, 4 in order.)

- [ ] **Step 4: Register + write the failing test**

In `_initialize()`, after `_test_deploy_save()`:

```gdscript
	_test_deploy_reconcile_on_win()
```

Add the test function:

```gdscript
func _test_deploy_reconcile_on_win() -> void:
	RosterStore.reset()   # start from a clean campaign.v2 slot
	# Seed a roster with two deployed veterans (ids assigned 1, 2).
	var seed_blob := RosterStore.new_roster()
	var vet := {"type_key": "stoneward", "name": "Stoneward", "element": "terra", "sprite": "golem", "attack": "melee", "relic": "", "flying": false, "evolved": false, "max_hp": 30, "power": 7, "def": 6, "move": 2, "range": 1, "level": 2, "xp": 0}
	var rid1 := RosterStore.add_entry(seed_blob, vet)   # 1
	var rid2 := RosterStore.add_entry(seed_blob, vet)   # 2
	RosterStore.save(seed_blob)
	# A finished campaign match: vet 1 survived (leveled to 3 + grabbed a relic), vet 2 died.
	var s := Session.new()
	s.campaign_progress = 0
	s.state = GameState.new_campaign(Campaign.CAMPAIGN[0], 0)
	s.state.deployed_roster_ids = [rid1, rid2]
	var alive_vet := Deploy.unit_from_entry({"roster_id": rid1, "type_key": "stoneward", "name": "Stoneward", "element": "terra", "sprite": "golem", "attack": "melee", "relic": "vital", "flying": false, "evolved": false, "max_hp": 34, "power": 8, "def": 7, "move": 2, "range": 1, "level": 3, "xp": 1}, s.state._new_id(), 0, 0, 0)
	s.state.units.append(alive_vet)
	s.state.winner = 0
	s.on_match_won(0)
	var arr: Array = RosterStore.load_or_init(0)["roster"]
	var e1 := {}
	var has2 := false
	var master_in_roster := false
	for e in arr:
		if int(e["roster_id"]) == rid1:
			e1 = e
		elif int(e["roster_id"]) == rid2:
			has2 = true
		if e.get("type_key") == "master":
			master_in_roster = true
	_eq(e1.is_empty(), false, "reconcile-win: surviving vet retained")
	_eq(e1.get("level"), 3, "reconcile-win: surviving vet leveled to 3")
	_eq(e1.get("relic"), "vital", "reconcile-win: surviving vet relic carried")
	_eq(has2, false, "reconcile-win: dead vet culled (permadeath)")
	_eq(master_in_roster, false, "reconcile-win: master never joins the roster")
	# Slot caps come from the scenario defs.
	_eq(Deploy.slots_for(Campaign.CAMPAIGN[0]), 3, "deploy: mission 1 cap 3")
	_eq(Deploy.slots_for(Campaign.CAMPAIGN[2]), 4, "deploy: mission 3 cap 4")
	RosterStore.reset()   # cleanup the slot file
```

- [ ] **Step 5: Run, verify FAIL (then PASS after Steps 2–3)**

Run: `pwsh -File godot/tests/run_tests.ps1`
Expected: if Step 2 (reconcile) and Step 3 (deploy_slots) are NOT yet applied, FAIL (the roster has no survivor / the slot-cap asserts fail). With Steps 2–3 applied, PASS — `== N passed, 0 failed ==`, EXIT 0 (N ≈ +7 vs Task 3 total). Apply Steps 2–3 then re-run to confirm PASS.

- [ ] **Step 6: Headless boot (session.gd + campaign.gd changed)**

Run: `godot --headless --path godot --quit-after 30 2>&1 | Select-String "SCRIPT ERROR|Parse Error|Failed to load"`
Expected: no matches.

- [ ] **Step 7: Commit**

```bash
git add godot/core/session.gd godot/data/campaign.gd godot/tests/run_tests.gd
git commit -m "[godot] P5.2 deploy: reconcile survivors on campaign win + per-mission slot caps"
```

---

## Self-Review

**Spec coverage:**
- `core/deploy.gd` pure ops (`unit_from_entry`/`roster_value`/`ai_scale_mp`/`slots_for`) → Task 1. ✓
- `Deploy.commit` (place near master, record ids, AI mp bump, no `summoned` bump) → Task 2. ✓
- `GameState.deployed_roster_ids` (saved) → Task 2 (field) + Task 3 (save). ✓
- `roster_id` rides the unit through save (int coercion) → Task 3. ✓
- Deploy scene (roster list, slot cap, empty-roster note, begin, reset two-click) → Task 4. ✓
- Flow `story → deploy → play` (start_campaign screen + router case + handlers) → Task 4. ✓
- `--shot deploy` + `mission2` shot fix → Task 4. ✓
- Reconcile survivors on campaign win only (exclude master; loss/skirmish untouched) → Task 5. ✓
- `deploy_slots` per scenario (3/3/4/4, default 3) → Task 5 (+ `slots_for` default in Task 1). ✓
- Campaign-only (skirmish path unchanged) → confirmed: only `start_campaign` changes screen; `start_skirmish` untouched. ✓
- Gates (harness + headless + shot) → Tasks 2/4/5. ✓

**Placeholder scan:** none — complete code + exact commands in every step. (Task 3 Step 4 / Task 5 Step 5 note that a serialization/data task may pass immediately if the impl step precedes the test run — the requirement is the assert exists and passes; this is intentional, not a placeholder.)

**Type consistency:** `Deploy.unit_from_entry(entry, id, owner, q, r)`, `roster_value(entries)`, `ai_scale_mp(value)`, `slots_for(scenario)`, `commit(state, entries)` — identical across module, tests, and `main.gd` call (`DeployLib.commit`). `RosterStore._CARRY_STR/_CARRY_INT/_CARRY_BOOL` reused for the entry↔unit field contract (no drift). `GameState.deployed_roster_ids` consistent across game_state/save_game/deploy/session/tests. `AI.find_summon_slot(state, master)`, `state.master_of`, `state._new_id`, `state.alive_units` match `core/{ai,game_state}.gd`. Scenario key `deploy_slots` consistent in campaign.gd + `slots_for`. `RosterStore.reconcile(blob, living_units, deployed_ids)` matches the 5.1 signature.

**Build-order note:** Task 1/2 use stub-first TDD (the harness analyze-time checks static calls, so the symbol must exist to compile). Tasks 3 and 5 mix a data/serialization change with its assert; if the impl lands before the test run the assert passes immediately — acceptable for round-trip/data asserts (the value is the regression guard, not the red-first ritual).
