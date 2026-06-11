# Wraithspire Godot Port — Milestone 7: HUD/UI + presentation refactor — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax.

**Goal:** Turn the placeholder match scene into the real presentation layer — per-unit nodes with HP/status indicators, a real pan/zoom Camera2D, and a `CanvasLayer` HUD of Control nodes (topbar, unit info card, anchored post-move action menu, summon sub-list) — and replace the temp debug keybinds with a real click → move → action-menu interaction flow (including Undo).

**Architecture:** Logic stays pure and presentation stays thin. A new pure `core/ui_queries.gd` (class `UiQueries`) decides *which* actions/summons are available (harness-tested); the Control nodes only render what it returns. The match scene keeps its code-built structure (no `.tscn`): `main.gd` instantiates each presentation node in `_ready` and is the only place that mutates `GameState` and re-syncs nodes. **Board terrain stays a custom-hex Node2D** (`board.gd`, drawn via `Hex.axial_to_pixel`) — NOT a Godot TileMapLayer (decision 2026-06-11: guarantees unit/terrain alignment, no TileSet plumbing; M10 reskins terrain when real art arrives). The M6 synchronous AI handoff is preserved; the move-slide animation + battle cutaway are M8.

**Tech Stack:** GDScript, Godot 4.6.3 standard build. Harness: `pwsh -File godot/tests/run_tests.ps1` (the `-ExecutionPolicy Bypass` form is BLOCKED by the Claude Code classifier — always use plain `pwsh -File`). Headless boot parse gate (scene scripts have no `class_name`, so the harness can't see their parse errors): `godot --headless --path godot --quit-after 30 2>&1 | Select-String "SCRIPT ERROR|Parse Error|Failed to load"` (clean = no matches).

**Reference:** `game.js` — `openPostMoveMenu` 4559–4588, `selectMenuItem` 4590–4660, `menuRect`/menu draw 3562–3599, topbar/info HUD draw (sec. 11/12).

---

## Verification model (read once)

- **Task 1** is pure logic → standard TDD (write failing asserts, implement, asserts pass).
- **Tasks 2–7** are presentation. They cannot be asserted headlessly, so each is gated by: (a) the **headless boot parse gate** stays clean, and (b) the **harness** stays green at its current count (no pure logic regressed). Behavioral/visual confirmation is the **user's** at the end (no display in-session). Every presentation task ships complete code so there is nothing to "figure out" at runtime.
- Baseline at M6 close (`02a4d4d` + session-state `9be4ce0`): **330 passed, 0 failed**. Task 1 adds asserts (→ ~345); Tasks 2–7 keep that count.

## File structure (this milestone)

```
godot/core/ui_queries.gd        NEW  class UiQueries — available_actions / summon_options / can_capture (pure)
godot/scenes/match/unit_node.gd NEW  class UnitNode — one node per unit: ring/body/pip + HP bar + status pips
godot/scenes/match/units_layer.gd MOD becomes a manager: spawns/refreshes one UnitNode per live unit
godot/scenes/match/overlay.gd   MOD  + attack-range ring, + armed-target highlight (blink/summon-slot/ability)
godot/scenes/hud/top_bar.gd     NEW  class TopBar (Control) — turn/player/weather/MP + End-Turn button
godot/scenes/hud/info_card.gd   NEW  class InfoCard (Control) — selected/hovered unit stats
godot/scenes/hud/action_menu.gd NEW  class ActionMenu (Control) — anchored VBox of Buttons; action_chosen signal
godot/scenes/hud/summon_list.gd NEW  class SummonList (Control) — anchored VBox; summon_chosen / back signals
godot/scenes/main.gd            MOD  Camera2D pan/zoom; instantiate HUD; interaction state machine; retire D/T/A
godot/tests/run_tests.gd        MOD  + _test_ui_queries
ROADMAP_GODOT.md                MOD  check off M7
```

Each HUD node owns its own rendering and exposes a narrow interface; `main.gd` wires their signals and pushes state in. `find_summon_slot` stays in `core/ai.gd` (the AI owns it); `main.gd` (already an `AI` consumer) calls `AI.find_summon_slot` at summon-commit time, so `ui_queries.gd` has **no** AI dependency.

---

## Task 1: Pure UI queries (`core/ui_queries.gd`) + tests

Port the action-availability + summon-list logic out of the JS `openPostMoveMenu` into a pure, testable helper. `available_actions` takes a `has_undo` bool (the undo snapshot is presentation state, passed in — keeps the function pure).

**Files:** Create `godot/core/ui_queries.gd`; Modify `godot/tests/run_tests.gd`.

- [ ] **Step 1: Add failing tests to `godot/tests/run_tests.gd`.** Add the preload with the other `core` preloads (after the `AI` preload line):
```gdscript
const UiQueries = preload("res://core/ui_queries.gd")
```
Add the call in `_initialize`, after `_test_ai_turn()`:
```gdscript
	_test_ui_queries()
```
Append this function at the end of the file:
```gdscript
func _test_ui_queries() -> void:
	# can_capture: tower-only (the capturable flag), and only when not already owned.
	var gs := _flat_state(7, 7)
	var u := gs.spawn_unit("cinderling", 0, 3, 3)
	_eq(UiQueries.can_capture(gs, u, gs.cell_at(3, 3)), false, "ui: plain tile not capturable")
	gs.cell_at(3, 3)["terrain"] = "tower"
	_eq(UiQueries.can_capture(gs, u, gs.cell_at(3, 3)), true, "ui: neutral tower capturable")
	gs.cell_at(3, 3)["owner"] = 0
	_eq(UiQueries.can_capture(gs, u, gs.cell_at(3, 3)), false, "ui: own tower not capturable")
	gs.cell_at(3, 3)["owner"] = 1
	_eq(UiQueries.can_capture(gs, u, gs.cell_at(3, 3)), true, "ui: enemy tower capturable")
	_eq(UiQueries.can_capture(gs, u, gs.cell_at(2, 2)), false, "ui: plain neighbor not capturable")

	# available_actions on an empty plain board: a lone grunt has only its ability + Wait
	# (every SUMMON_LIST unit has an ability; cinderling's is ignite — no attack/capture/summon).
	var ga := _flat_state(7, 7)
	var lone := ga.spawn_unit("cinderling", 0, 3, 3)
	var acts := UiQueries.available_actions(ga, lone, false)
	_eq(acts.size(), 2, "ui: lone grunt has ability + wait only")
	_eq(acts[0]["kind"], "ability", "ui: lone grunt first action is its ability")
	_eq(acts[acts.size() - 1]["kind"], "wait", "ui: lone grunt ends in wait")

	# with an adjacent enemy, Attack appears (before Wait).
	ga.spawn_unit("galewisp", 1, 4, 3)
	var acts2 := UiQueries.available_actions(ga, lone, false)
	_eq(acts2[0]["kind"], "attack", "ui: attack present with adjacent enemy")
	_eq(acts2[acts2.size() - 1]["kind"], "wait", "ui: wait is always last")

	# has_undo inserts Undo immediately before Wait.
	var acts3 := UiQueries.available_actions(ga, lone, true)
	_eq(acts3[acts3.size() - 2]["kind"], "undo", "ui: undo sits before wait")
	_eq(acts3[acts3.size() - 1]["kind"], "wait", "ui: wait still last with undo")

	# master with MP >= 6 gets Summon; ability gated by cooldown shows disabled + label.
	var gm := _flat_state(7, 7)
	var m := gm.spawn_master(0, 3, 3)
	m["mp"] = 6
	var ma := UiQueries.available_actions(gm, m, false)
	var has_summon := false
	for a in ma:
		if a["kind"] == "summon":
			has_summon = true
	_ok(has_summon, "ui: master with 6 MP can summon")
	m["mp"] = 5
	var ma2 := UiQueries.available_actions(gm, m, false)
	for a in ma2:
		_ok(a["kind"] != "summon", "ui: master under 6 MP cannot summon")

	# ability cooldown: a unit with an ability on cd shows it disabled with the count.
	var gb := _flat_state(7, 7)
	var ogre := gb.spawn_unit("geomaul", 0, 3, 3)   # quake ability
	ogre["cd"] = 2
	var ba := UiQueries.available_actions(gb, ogre, false)
	var ab_item: Variant = null
	for a in ba:
		if a["kind"] == "ability":
			ab_item = a
	_ok(ab_item != null and ab_item["disabled"], "ui: ability on cd is disabled")
	_ok(String(ab_item["label"]).ends_with("(2)"), "ui: disabled ability label carries the cd count")

	# second-move leg: only Capture (if applicable) + Wait — no Attack/Summon/Ability.
	var gs2 := _flat_state(7, 7)
	var sk := gs2.spawn_unit("galewisp", 0, 3, 3)
	gs2.spawn_unit("cinderling", 1, 4, 3)           # adjacent enemy would normally give Attack
	sk["second_move"] = true
	var sa := UiQueries.available_actions(gs2, sk, false)
	for a in sa:
		_ok(a["kind"] == "capture" or a["kind"] == "wait", "ui: second-move leg is capture/wait only")
	_eq(sa[sa.size() - 1]["kind"], "wait", "ui: second-move ends in wait")

	# summon_options: full SUMMON_LIST, costs correct, disabled flips at the MP boundary.
	var gso := _flat_state(7, 7)
	var sm := gso.spawn_master(1, 3, 3)
	sm["mp"] = 8
	var opts := UiQueries.summon_options(gso, sm)
	_eq(opts.size(), UnitTypes.SUMMON_LIST.size(), "ui: one summon option per SUMMON_LIST entry")
	for o in opts:
		_eq(o["disabled"], o["cost"] > 8, "ui: summon option disabled iff cost exceeds MP")
		_ok(String(o["label"]).ends_with("MP"), "ui: summon label ends in MP")
```

- [ ] **Step 2: Run — verify it fails (UiQueries missing).**
```
pwsh -File godot/tests/run_tests.ps1; "EXIT=$LASTEXITCODE"
```
Expected: load/parse error about `res://core/ui_queries.gd`, non-zero EXIT.

- [ ] **Step 3: Create `godot/core/ui_queries.gd`, verbatim:**
```gdscript
class_name UiQueries
extends RefCounted
## Pure, presentation-agnostic UI queries — the action-availability + summon-list logic
## lifted out of the JS openPostMoveMenu (game.js 4559+). The HUD Control nodes render
## exactly what these return; they hold no game logic. All functions are pure reads:
## they never mutate state or the unit/cell dicts passed in. `has_undo` is presentation
## state (a live pre-move snapshot) passed in as a bool so this stays pure + testable.

const Pathfinding = preload("res://core/pathfinding.gd")
const Abilities = preload("res://data/abilities.gd")
const Terrain = preload("res://data/terrain.gd")
const UnitTypes = preload("res://data/unit_types.gd")
const Elements = preload("res://data/elements.gd")

## can_capture — true if `unit` standing on `cell` could flip it: a capturable terrain
## (the `capturable` flag — towers only) not already owned by this unit.
static func can_capture(state, unit, cell) -> bool:
	if cell == null:
		return false
	if not Terrain.TERRAIN.get(cell["terrain"], {}).get("capturable", false):
		return false
	return cell.get("owner", -1) != unit["owner"]

## available_actions — the ordered post-move action list for `unit` at its current tile.
## Each item is {kind, label, disabled}. Mirrors openPostMoveMenu: second-move leg yields
## only Capture (if applicable) + Wait; otherwise Attack (with targets) / Capture / Summon
## (master, mp>=6) / Ability (disabled on cd, label carries the count) / Undo (if has_undo)
## / Wait. PURE.
static func available_actions(state, unit, has_undo := false) -> Array:
	var actions: Array = []
	var cell: Variant = state.cell_at(unit["q"], unit["r"])
	if unit.get("second_move", false):
		if can_capture(state, unit, cell):
			actions.append({"kind": "capture", "label": "Capture", "disabled": false})
		actions.append({"kind": "wait", "label": "Wait", "disabled": false})
		return actions
	var targets := Pathfinding.compute_attack_targets(state, unit, unit["q"], unit["r"])
	if not targets.is_empty():
		actions.append({"kind": "attack", "label": "Attack", "disabled": false})
	if can_capture(state, unit, cell):
		actions.append({"kind": "capture", "label": "Capture", "disabled": false})
	if unit["is_master"] and unit["mp"] >= 6:
		actions.append({"kind": "summon", "label": "Summon", "disabled": false})
	var ab: Variant = Abilities.ability_for(unit)
	if ab != null:
		var label: String = ab["name"] if unit["cd"] <= 0 else "%s (%d)" % [ab["name"], unit["cd"]]
		actions.append({"kind": "ability", "label": label, "disabled": unit["cd"] > 0})
	if has_undo:
		actions.append({"kind": "undo", "label": "Undo", "disabled": false})
	actions.append({"kind": "wait", "label": "Wait", "disabled": false})
	return actions

## summon_options — the summon picker list for `master`: every SUMMON_LIST type with a
## "Name  ELT  NNMP" label, its cost, and disabled when the master can't afford it. PURE.
static func summon_options(state, master) -> Array:
	var opts: Array = []
	for k in UnitTypes.SUMMON_LIST:
		var t: Dictionary = UnitTypes.UNIT_TYPES[k]
		var el: String = Elements.ELEMENT[t["element"]]["short"]
		var cost: int = t["cost"]
		opts.append({
			"key": k,
			"label": "%s  %s  %dMP" % [t["name"], el, cost],
			"cost": cost,
			"disabled": cost > master["mp"],
		})
	return opts
```

- [ ] **Step 4: Run — verify pass.**
```
pwsh -File godot/tests/run_tests.ps1; "EXIT=$LASTEXITCODE"
```
Expected: green, `EXIT=0` (~15 new asserts). `0 failed` is the gate.

- [ ] **Step 5: Commit.**
```
git add godot/core/ui_queries.gd godot/tests/run_tests.gd
git commit -m "[godot] M7: pure UI queries (available_actions / summon_options / can_capture) + tests"
```

---

## Task 2: Camera2D pan + zoom

`main.gd` already creates a `Camera2D` centered on the active master. Add right/middle-drag panning and scroll-wheel zoom (clamped). No new files.

**Files:** Modify `godot/scenes/main.gd`.

- [ ] **Step 1: Add camera tuning constants + a pan-state var.** Near the top of `main.gd`, after the existing `var armed = null` line, add:
```gdscript
const ZOOM_MIN := 0.5
const ZOOM_MAX := 2.5
const ZOOM_STEP := 1.1
var _panning := false
```

- [ ] **Step 2: Handle pan/zoom in `_unhandled_input`.** At the TOP of `_unhandled_input` (before the existing left-click branch), add the camera input handling:
```gdscript
	# --- Camera: middle/right-drag pans, wheel zooms (about the cursor). ---
	if event is InputEventMouseButton:
		if event.button_index == MOUSE_BUTTON_MIDDLE or event.button_index == MOUSE_BUTTON_RIGHT:
			_panning = event.pressed
			return
		elif event.button_index == MOUSE_BUTTON_WHEEL_UP and event.pressed:
			cam.zoom = (cam.zoom * ZOOM_STEP).clamp(Vector2(ZOOM_MIN, ZOOM_MIN), Vector2(ZOOM_MAX, ZOOM_MAX))
			return
		elif event.button_index == MOUSE_BUTTON_WHEEL_DOWN and event.pressed:
			cam.zoom = (cam.zoom / ZOOM_STEP).clamp(Vector2(ZOOM_MIN, ZOOM_MIN), Vector2(ZOOM_MAX, ZOOM_MAX))
			return
	if event is InputEventMouseMotion and _panning:
		cam.position -= event.relative / cam.zoom
		return
```

- [ ] **Step 3: Headless boot parse gate.**
```
godot --headless --path godot --quit-after 30 2>&1 | Select-String -Pattern "SCRIPT ERROR|Parse Error|Failed to load"
```
Expected: NO output.

- [ ] **Step 4: Harness still green.**
```
pwsh -File godot/tests/run_tests.ps1; "EXIT=$LASTEXITCODE"
```
Expected: same count as Task 1, `0 failed`, EXIT 0.

- [ ] **Step 5: Commit.**
```
git add godot/scenes/main.gd
git commit -m "[godot] M7: Camera2D drag-pan + scroll-zoom"
```

---

## Task 3: Per-unit nodes with HP bar + status pips

Replace the single `_draw`-everything `units_layer.gd` with a manager that owns one `UnitNode` per live unit. Each `UnitNode` draws its own token (team ring + element body + master pip), an HP bar, and a row of status pips. This is the per-unit-node architecture the design calls for; real `Sprite2D`/`AnimatedSprite2D` art swaps into `UnitNode` at M10 with no change to the manager or `main.gd`.

**Files:** Create `godot/scenes/match/unit_node.gd`; Modify `godot/scenes/match/units_layer.gd`.

- [ ] **Step 1: Create `godot/scenes/match/unit_node.gd`, verbatim:**
```gdscript
class_name UnitNode
extends Node2D
## One node per live unit (placeholder art): team-colored ring, element body, master
## pip, an HP bar, and a row of status pips. Bound to a GameState unit record via
## bind(); call refresh() after the record changes. Real sprites replace the _draw
## body at M10 — the node interface stays the same.

const Hex = preload("res://core/hex.gd")

## Team ring colors — AZURE / CRIMSON (JS PLAYERS palette p0/p1).
const TEAM_COLORS := [Color("#5aa8d8"), Color("#cc6a4a")]
const ELEMENT_COLORS := {
	"pyro": Color("#d8662e"), "hydro": Color("#3a7ad8"), "terra": Color("#9a8a52"),
	"zephyr": Color("#7fd0c0"), "arcane": Color("#a06ad8"),
}
## Status pip colors (keys from data/statuses.gd).
const STATUS_COLORS := {
	"burn": Color("#e0662e"), "slow": Color("#6aa0e0"), "mark": Color("#e0d050"),
	"bulwark": Color("#9aa0b0"), "ward": Color("#d0d0f0"), "regen": Color("#70d070"),
}

var unit   # GameState unit record (untyped — node<->RefCounted preload cycle avoidance)

func bind(u) -> void:
	unit = u
	refresh()

func refresh() -> void:
	if unit != null:
		position = Hex.axial_to_pixel(Vector2i(unit["q"], unit["r"]))
	queue_redraw()

func _draw() -> void:
	if unit == null:
		return
	var radius := Hex.SIZE * 0.62
	var ring: Color = TEAM_COLORS[unit["owner"]]
	var fill: Color = ELEMENT_COLORS.get(unit["element"], Color("#cccccc"))
	draw_circle(Vector2.ZERO, radius, ring)
	draw_circle(Vector2.ZERO, radius * 0.74, fill)
	if unit["is_master"]:
		draw_circle(Vector2.ZERO, radius * 0.30, Color(1, 1, 1, 0.9))
	_draw_hp_bar(radius)
	_draw_status_pips(radius)

func _draw_hp_bar(radius: float) -> void:
	var w := radius * 1.6
	var h := 4.0
	var top_left := Vector2(-w / 2.0, -radius - 8.0)
	draw_rect(Rect2(top_left, Vector2(w, h)), Color(0, 0, 0, 0.6))
	var frac := clampf(float(unit["hp"]) / float(unit["max_hp"]), 0.0, 1.0)
	var col := Color("#5ad06a") if frac > 0.5 else (Color("#e0d050") if frac > 0.25 else Color("#e05050"))
	draw_rect(Rect2(top_left, Vector2(w * frac, h)), col)

func _draw_status_pips(radius: float) -> void:
	if unit == null or not unit.has("status"):
		return
	var i := 0
	for k in unit["status"]:
		if unit["status"][k] <= 0:
			continue
		var c: Color = STATUS_COLORS.get(k, Color(1, 1, 1))
		draw_circle(Vector2(-radius + i * 7.0, radius + 6.0), 3.0, c)
		i += 1
```

- [ ] **Step 2: Rewrite `godot/scenes/match/units_layer.gd` as a manager, verbatim:**
```gdscript
class_name UnitsLayer
extends Node2D
## Manages one UnitNode per live unit. set_state() rebuilds the node set from the
## GameState (cheap — armies are small), so spawns/deaths/moves all reflect on the
## next call. Reads unit records straight from the GameState.

const UnitNodeScript = preload("res://scenes/match/unit_node.gd")

var state   # GameState (untyped — node<->RefCounted preload cycle avoidance)

func set_state(s) -> void:
	state = s
	_rebuild()

func _rebuild() -> void:
	for child in get_children():
		child.queue_free()
	if state == null:
		return
	for u in state.units:
		if u["hp"] <= 0:
			continue
		var node: UnitNode = UnitNodeScript.new()
		add_child(node)
		node.bind(u)
```
NOTE: `main.gd` already calls `units_layer.set_state(state)` after every mutation, so no `main.gd` change is needed for units to refresh. Rebuilding all nodes per call is fine at this scale (≤ a couple dozen units) and keeps the manager trivially correct.

- [ ] **Step 3: Headless boot parse gate.**
```
godot --headless --path godot --quit-after 30 2>&1 | Select-String -Pattern "SCRIPT ERROR|Parse Error|Failed to load"
```
Expected: NO output.

- [ ] **Step 4: Harness still green.**
```
pwsh -File godot/tests/run_tests.ps1; "EXIT=$LASTEXITCODE"
```
Expected: same count, `0 failed`, EXIT 0.

- [ ] **Step 5: Commit.**
```
git add godot/scenes/match/unit_node.gd godot/scenes/match/units_layer.gd
git commit -m "[godot] M7: per-unit nodes with HP bar + status pips (UnitNode + UnitsLayer manager)"
```

---

## Task 4: Overlay — attack ring + armed-target highlight

Extend `overlay.gd` to also draw the attack-range tiles (red) and, when an ability/attack is armed, the armed target tiles (gold). Reachable + selection are already drawn. `main.gd` will feed the extra sets in Task 7; for now the new fields default empty so the overlay renders unchanged until wired.

**Files:** Modify `godot/scenes/match/overlay.gd`.

- [ ] **Step 1: Rewrite `godot/scenes/match/overlay.gd`, verbatim:**
```gdscript
class_name Overlay
extends Node2D
## Board highlights, drawn above the board and below the unit nodes:
##  - reachable tiles  -> translucent blue fill
##  - attack-range tiles -> translucent red fill
##  - armed-target tiles (ability/blink/summon-slot) -> translucent gold fill
##  - the selected unit's tile -> bright yellow outline
## Fed by main.gd. All sets are { "q,r": <any> } dictionaries (compute_* results or
## plain key sets); only their keys are read.

const Hex = preload("res://core/hex.gd")
const BoardLib = preload("res://scenes/board/board.gd")

var reachable: Dictionary = {}
var attack: Dictionary = {}
var armed: Dictionary = {}
var selected: Variant = null

func set_highlights(reach: Dictionary, sel) -> void:
	reachable = reach
	selected = sel
	queue_redraw()

func set_attack(tiles: Dictionary) -> void:
	attack = tiles
	queue_redraw()

func set_armed(tiles: Dictionary) -> void:
	armed = tiles
	queue_redraw()

func clear_all() -> void:
	reachable = {}
	attack = {}
	armed = {}
	selected = null
	queue_redraw()

func _fill(tiles: Dictionary, col: Color) -> void:
	for key in tiles:
		var parts := key.split(",")
		var p := Vector2i(int(parts[0]), int(parts[1]))
		draw_colored_polygon(BoardLib.hex_corners(Hex.axial_to_pixel(p)), col)

func _draw() -> void:
	_fill(reachable, Color(0.4, 0.7, 1.0, 0.28))
	_fill(attack, Color(1.0, 0.35, 0.35, 0.30))
	_fill(armed, Color(1.0, 0.82, 0.30, 0.42))
	if selected != null:
		var outline := BoardLib.hex_corners(Hex.axial_to_pixel(Vector2i(selected["q"], selected["r"])))
		outline.append(outline[0])
		draw_polyline(outline, Color(1.0, 1.0, 0.4, 0.95), 3.0)
```
NOTE: keys are parsed straight from the `"q,r"` dict keys, so this works whether fed a `compute_reachable`/`compute_attack_targets` result or a plain key-set. The existing `set_highlights(reach, sel)` signature is preserved, so the current `main.gd` calls keep compiling.

- [ ] **Step 2: Headless boot parse gate.**
```
godot --headless --path godot --quit-after 30 2>&1 | Select-String -Pattern "SCRIPT ERROR|Parse Error|Failed to load"
```
Expected: NO output.

- [ ] **Step 3: Harness still green.**
```
pwsh -File godot/tests/run_tests.ps1; "EXIT=$LASTEXITCODE"
```
Expected: same count, `0 failed`, EXIT 0.

- [ ] **Step 4: Commit.**
```
git add godot/scenes/match/overlay.gd
git commit -m "[godot] M7: overlay gains attack-range + armed-target highlight layers"
```

---

## Task 5: HUD topbar + unit info card

Create the two always-on HUD Control nodes. `TopBar` shows turn/player/weather/active-master MP and an End-Turn button (emits a signal). `InfoCard` shows the selected/hovered unit's stats. `main.gd` instantiates both under a new `CanvasLayer` and refreshes them; the End-Turn button routes to the same path as the Enter key.

**Files:** Create `godot/scenes/hud/top_bar.gd`, `godot/scenes/hud/info_card.gd`; Modify `godot/scenes/main.gd`.

- [ ] **Step 1: Create `godot/scenes/hud/top_bar.gd`, verbatim:**
```gdscript
class_name TopBar
extends Control
## Top HUD strip: turn #, active player, weather, active master MP, End-Turn button.
## Built in code (no .tscn). Emits end_turn_pressed; main.gd refreshes via refresh(state).

signal end_turn_pressed

const PLAYER_NAMES := ["AZURE", "CRIMSON"]

var _label: Label
var _button: Button

func _ready() -> void:
	set_anchors_preset(Control.PRESET_TOP_WIDE)
	custom_minimum_size = Vector2(0, 36)
	var bg := ColorRect.new()
	bg.color = Color(0.06, 0.07, 0.10, 0.85)
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(bg)
	_label = Label.new()
	_label.position = Vector2(12, 8)
	add_child(_label)
	_button = Button.new()
	_button.text = "End Turn"
	_button.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	_button.position = Vector2(-110, 4)
	_button.pressed.connect(func(): end_turn_pressed.emit())
	add_child(_button)

func refresh(state) -> void:
	if state == null or _label == null:
		return
	var who: String = PLAYER_NAMES[state.current_player] if state.current_player < PLAYER_NAMES.size() else str(state.current_player)
	var weather_key: String = state.weather.get("key", "clear") if state.weather != null else "clear"
	var m = state.master_of(state.current_player)
	var mp: int = m["mp"] if m != null else 0
	_label.text = "Turn %d   %s   Weather: %s   MP: %d" % [state.turn, who, weather_key, mp]
```

- [ ] **Step 2: Create `godot/scenes/hud/info_card.gd`, verbatim:**
```gdscript
class_name InfoCard
extends Control
## Bottom-left unit info card: stats for the selected/hovered unit. show_unit(unit)
## fills it and makes it visible; clear() hides it. Built in code (no .tscn).

const Hex = preload("res://core/hex.gd")

var _label: Label

func _ready() -> void:
	set_anchors_preset(Control.PRESET_BOTTOM_LEFT)
	position = Vector2(12, -150)
	custom_minimum_size = Vector2(240, 138)
	var bg := ColorRect.new()
	bg.color = Color(0.06, 0.07, 0.10, 0.85)
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(bg)
	_label = Label.new()
	_label.position = Vector2(10, 8)
	add_child(_label)
	visible = false

func show_unit(unit) -> void:
	if unit == null:
		clear()
		return
	var statuses := ""
	if unit.has("status") and not unit["status"].is_empty():
		statuses = "  [" + ", ".join(PackedStringArray(unit["status"].keys())) + "]"
	var cd_txt: String = ("  CD %d" % unit["cd"]) if unit.get("cd", 0) > 0 else ""
	_label.text = "%s  (%s)\nHP %d/%d   ATK %d   DEF %d\nMOV %d   RNG %d   LV %d%s%s" % [
		unit["name"], unit["element"],
		unit["hp"], unit["max_hp"], unit["power"], unit["def"],
		unit["move"], unit["range"], unit["level"], cd_txt, statuses,
	]
	visible = true

func clear() -> void:
	visible = false
```

- [ ] **Step 3: Wire the HUD into `main.gd`.** Add the preloads with the other scene preloads (after the `OverlayScript` line):
```gdscript
const TopBarScript = preload("res://scenes/hud/top_bar.gd")
const InfoCardScript = preload("res://scenes/hud/info_card.gd")
```
Add the member vars near `var units_layer: UnitsLayer`:
```gdscript
var hud: CanvasLayer
var top_bar: TopBar
var info_card: InfoCard
```
At the END of `_ready()` (after `cam.make_current()`), build the HUD:
```gdscript
	hud = CanvasLayer.new()
	add_child(hud)
	top_bar = TopBarScript.new()
	top_bar.end_turn_pressed.connect(_on_end_turn)
	hud.add_child(top_bar)
	info_card = InfoCardScript.new()
	hud.add_child(info_card)
	top_bar.refresh(state)
```

- [ ] **Step 4: Add the shared end-turn path + refresh hook.** Add a new `_on_end_turn` method (the End-Turn button and the Enter key both call it), and refresh the topbar after every action. Add this method:
```gdscript
func _on_end_turn() -> void:
	state.end_turn()
	# M6: player 1 is the AI. Run its whole turn synchronously, then hand back.
	if state.winner == -1 and state.current_player == 1:
		AI.take_turn(state)
		if state.winner == -1:
			state.end_turn()
	_center_on_master()
	_finish_action()
```
Then REPLACE the existing Enter branch body in `_unhandled_input` (the `state.end_turn()` … block) with a single call:
```gdscript
	elif event is InputEventKey and event.pressed and event.keycode == KEY_ENTER:
		_on_end_turn()
```
Finally, in `_finish_action()`, refresh the topbar — change it to:
```gdscript
func _finish_action() -> void:
	_clear_selection()
	units_layer.set_state(state)
	if top_bar != null:
		top_bar.refresh(state)
	if state.winner != -1:
		print("WINNER: player %d" % state.winner)
```

- [ ] **Step 5: Headless boot parse gate.**
```
godot --headless --path godot --quit-after 30 2>&1 | Select-String -Pattern "SCRIPT ERROR|Parse Error|Failed to load"
```
Expected: NO output. (This change adds Control nodes + signal wiring to the no-`class_name` `main.gd` — the boot gate is the only automated check.)

- [ ] **Step 6: Harness still green.**
```
pwsh -File godot/tests/run_tests.ps1; "EXIT=$LASTEXITCODE"
```
Expected: same count, `0 failed`, EXIT 0.

- [ ] **Step 7: Commit.**
```
git add godot/scenes/hud/top_bar.gd godot/scenes/hud/info_card.gd godot/scenes/main.gd
git commit -m "[godot] M7: HUD topbar (turn/weather/MP + End-Turn) + unit info card"
```

---

## Task 6: Action menu + summon sub-list Control nodes

Create the two anchored popup menus, driven by `UiQueries`. `ActionMenu.open(actions, screen_pos)` builds a button per item (disabled items greyed) and emits `action_chosen(kind)`. `SummonList.open(options, screen_pos)` builds a button per summon option plus a Back button, emitting `summon_chosen(key)` / `back`. Keyboard nav comes free from Godot's focus system (the first enabled button grabs focus; arrow keys move focus; Enter activates). `main.gd` instantiates both under the HUD but leaves them hidden; Task 7 opens them.

**Files:** Create `godot/scenes/hud/action_menu.gd`, `godot/scenes/hud/summon_list.gd`; Modify `godot/scenes/main.gd`.

- [ ] **Step 1: Create `godot/scenes/hud/action_menu.gd`, verbatim:**
```gdscript
class_name ActionMenu
extends Control
## Anchored post-move action menu: a vertical stack of Buttons built from a
## UiQueries.available_actions() list. open(actions, screen_pos) shows it at a screen
## position (clamped on-screen); a click (or focus+Enter) emits action_chosen(kind).
## Disabled items render as disabled buttons and cannot be chosen.

signal action_chosen(kind: String)

var _vbox: VBoxContainer
var _panel: PanelContainer

func _ready() -> void:
	_panel = PanelContainer.new()
	add_child(_panel)
	_vbox = VBoxContainer.new()
	_panel.add_child(_vbox)
	visible = false

func open(actions: Array, screen_pos: Vector2) -> void:
	for c in _vbox.get_children():
		c.queue_free()
	var first_enabled: Button = null
	for a in actions:
		var b := Button.new()
		b.text = a["label"]
		b.disabled = a["disabled"]
		var kind: String = a["kind"]
		b.pressed.connect(func(): action_chosen.emit(kind))
		_vbox.add_child(b)
		if not a["disabled"] and first_enabled == null:
			first_enabled = b
	_panel.position = _clamp_on_screen(screen_pos)
	visible = true
	if first_enabled != null:
		first_enabled.call_deferred("grab_focus")

func close() -> void:
	visible = false

func _clamp_on_screen(p: Vector2) -> Vector2:
	var vp := get_viewport_rect().size
	var sz := Vector2(120, 28 * maxi(1, _vbox.get_child_count()))
	return Vector2(clampf(p.x, 0, vp.x - sz.x), clampf(p.y, 36, vp.y - sz.y))
```

- [ ] **Step 2: Create `godot/scenes/hud/summon_list.gd`, verbatim:**
```gdscript
class_name SummonList
extends Control
## Anchored summon picker: a Button per UiQueries.summon_options() entry (unaffordable
## ones disabled) plus a Back button. Emits summon_chosen(key) or back.

signal summon_chosen(key: String)
signal back

var _vbox: VBoxContainer
var _panel: PanelContainer

func _ready() -> void:
	_panel = PanelContainer.new()
	add_child(_panel)
	_vbox = VBoxContainer.new()
	_panel.add_child(_vbox)
	visible = false

func open(options: Array, screen_pos: Vector2) -> void:
	for c in _vbox.get_children():
		c.queue_free()
	var first_enabled: Button = null
	for o in options:
		var b := Button.new()
		b.text = o["label"]
		b.disabled = o["disabled"]
		var key: String = o["key"]
		b.pressed.connect(func(): summon_chosen.emit(key))
		_vbox.add_child(b)
		if not o["disabled"] and first_enabled == null:
			first_enabled = b
	var back_btn := Button.new()
	back_btn.text = "Back"
	back_btn.pressed.connect(func(): back.emit())
	_vbox.add_child(back_btn)
	_panel.position = _clamp_on_screen(screen_pos)
	visible = true
	if first_enabled != null:
		first_enabled.call_deferred("grab_focus")
	else:
		back_btn.call_deferred("grab_focus")

func close() -> void:
	visible = false

func _clamp_on_screen(p: Vector2) -> Vector2:
	var vp := get_viewport_rect().size
	var sz := Vector2(180, 28 * maxi(1, _vbox.get_child_count()))
	return Vector2(clampf(p.x, 0, vp.x - sz.x), clampf(p.y, 36, vp.y - sz.y))
```

- [ ] **Step 3: Instantiate (hidden) in `main.gd`.** Add the preloads after `InfoCardScript`:
```gdscript
const ActionMenuScript = preload("res://scenes/hud/action_menu.gd")
const SummonListScript = preload("res://scenes/hud/summon_list.gd")
```
Add member vars:
```gdscript
var action_menu: ActionMenu
var summon_list: SummonList
```
In `_ready()`, after `info_card` is added to the HUD, add:
```gdscript
	action_menu = ActionMenuScript.new()
	hud.add_child(action_menu)
	summon_list = SummonListScript.new()
	hud.add_child(summon_list)
```

- [ ] **Step 4: Headless boot parse gate.**
```
godot --headless --path godot --quit-after 30 2>&1 | Select-String -Pattern "SCRIPT ERROR|Parse Error|Failed to load"
```
Expected: NO output.

- [ ] **Step 5: Harness still green.**
```
pwsh -File godot/tests/run_tests.ps1; "EXIT=$LASTEXITCODE"
```
Expected: same count, `0 failed`, EXIT 0.

- [ ] **Step 6: Commit.**
```
git add godot/scenes/hud/action_menu.gd godot/scenes/hud/summon_list.gd godot/scenes/main.gd
git commit -m "[godot] M7: anchored action menu + summon sub-list Control nodes"
```

---

## Task 7: Interaction flow + Undo; retire debug keys; close M7

Rewrite `main.gd`'s click handling into the real flow: select → move (snap, record undo snapshot) → open the action menu from `UiQueries.available_actions` → menu drives Attack/Ability/Capture/Summon/Undo/Wait. Reuse the M5 `armed` machine for Attack/Ability targeting (a mis-click re-opens the menu rather than freeing the unit). Enforce `acted`. Remove the temp `D`/`T`/`A` keys and their helpers.

**Files:** Modify `godot/scenes/main.gd`.

- [ ] **Step 1: Add interaction state + connect the menus.** Add member vars near `var armed = null`:
```gdscript
var undo_snapshot = null   # {unit, q, r} — the pre-move position, live until the action commits
```
In `_ready()`, after `summon_list` is added, connect the menu signals:
```gdscript
	action_menu.action_chosen.connect(_on_action_chosen)
	summon_list.summon_chosen.connect(_on_summon_chosen)
	summon_list.back.connect(_on_summon_back)
```

- [ ] **Step 2: Add a screen-position helper + the menu opener.** Add these methods:
```gdscript
## World hex -> screen position for anchoring a HUD popup at a unit (CanvasLayer is not
## affected by the camera, so convert through the canvas transform).
func _hex_screen_pos(q: int, r: int) -> Vector2:
	return get_viewport().get_canvas_transform() * Hex.axial_to_pixel(Vector2i(q, r))

func _open_menu_for(unit) -> void:
	var has_undo: bool = undo_snapshot != null and undo_snapshot["unit"] == unit
	var actions := UiQueries.available_actions(state, unit, has_undo)
	selected = unit
	action_menu.open(actions, _hex_screen_pos(unit["q"], unit["r"]))
```

- [ ] **Step 3: Replace `_on_click` with the real flow.** REPLACE the entire existing `_on_click` function with:
```gdscript
func _on_click(a: Vector2i) -> void:
	# An armed ability/attack is waiting for a target click.
	if armed != null:
		_resolve_armed(a)
		return
	# The action menu is open — clicks on the board are ignored (use the menu).
	if action_menu.visible or summon_list.visible:
		return
	# With a unit selected (and not yet moved this action): move onto a reachable tile.
	if selected != null and not selected["acted"]:
		var reach := Pathfinding.compute_reachable(state, selected)
		var is_own_tile: bool = (a.x == selected["q"] and a.y == selected["r"])
		if reach.has(Hex.key(a)) and not is_own_tile:
			undo_snapshot = {"unit": selected, "q": selected["q"], "r": selected["r"]}
			selected["q"] = a.x
			selected["r"] = a.y
			units_layer.set_state(state)
			overlay.set_highlights({}, selected)
			_open_menu_for(selected)
			return
		if is_own_tile:
			# Re-open the menu in place (act without moving).
			_open_menu_for(selected)
			return
	# Otherwise (re)select the current player's un-acted unit under the cursor.
	var u = state.unit_at(a.x, a.y)
	if u != null and u["owner"] == state.current_player and not u["acted"]:
		selected = u
		undo_snapshot = null
		overlay.set_highlights(Pathfinding.compute_reachable(state, u), u)
		info_card.show_unit(u)
	else:
		_clear_selection()
```

- [ ] **Step 4: Add the menu-choice handlers.** Add these methods:
```gdscript
func _on_action_chosen(kind: String) -> void:
	action_menu.close()
	var unit = selected
	if unit == null:
		return
	match kind:
		"attack":
			var targets := Pathfinding.compute_attack_targets(state, unit, unit["q"], unit["r"])
			if targets.is_empty():
				_open_menu_for(unit)   # nothing in range after all — back to the menu
				return
			armed = {"ab": null, "kind": "enemy", "targets": targets}
			overlay.set_armed(targets)
		"ability":
			_arm_ability(unit)
		"capture":
			var cell = state.cell_at(unit["q"], unit["r"])
			if cell != null and UiQueries.can_capture(state, unit, cell):
				state.capture_tower(unit, cell)
			_commit(unit)
		"summon":
			summon_list.open(UiQueries.summon_options(state, unit), _hex_screen_pos(unit["q"], unit["r"]))
		"undo":
			if undo_snapshot != null and undo_snapshot["unit"] == unit:
				unit["q"] = undo_snapshot["q"]
				unit["r"] = undo_snapshot["r"]
				undo_snapshot = null
				units_layer.set_state(state)
				# Re-select so the reachable overlay returns (mirrors a fresh click).
				selected = unit
				overlay.set_highlights(Pathfinding.compute_reachable(state, unit), unit)
				info_card.show_unit(unit)
		"wait":
			_commit(unit)

func _arm_ability(unit) -> void:
	var ab = Abilities.ability_for(unit)
	if ab == null or unit["cd"] > 0:
		_open_menu_for(unit)
		return
	match ab["target"]:
		"none":
			AbilityResolve.resolve_instant(state, unit, ab)
			unit["cd"] = ab["cd"]
			_commit(unit)
		"enemy":
			var targets := Pathfinding.compute_attack_targets(state, unit, unit["q"], unit["r"])
			if targets.is_empty():
				_open_menu_for(unit)
				return
			armed = {"ab": ab, "kind": "enemy", "targets": targets}
			overlay.set_armed(targets)
		"tile":
			var tiles := AbilityResolve.blink_targets(state, unit)
			if tiles.is_empty():
				_open_menu_for(unit)
				return
			armed = {"ab": ab, "kind": "tile", "targets": tiles}
			overlay.set_armed(tiles)

func _on_summon_chosen(key: String) -> void:
	var unit = selected
	if unit == null:
		return
	var slot = AI.find_summon_slot(state, unit)
	if slot == null:
		return   # no open hex; leave the list open for another pick or Back
	unit["mp"] -= UnitTypes.UNIT_TYPES[key]["cost"]
	var u := state.spawn_unit(key, unit["owner"], slot.x, slot.y)
	u["acted"] = true
	summon_list.close()
	_commit(unit)

func _on_summon_back() -> void:
	summon_list.close()
	if selected != null:
		_open_menu_for(selected)
```

- [ ] **Step 5: Update `_resolve_armed`, `_commit`, `_clear_selection`.** REPLACE `_resolve_armed` with a version that backs out to the menu on a miss (the exploit-fix) and commits on a hit:
```gdscript
func _resolve_armed(a: Vector2i) -> void:
	var unit = selected
	if armed["targets"].has(Hex.key(a)):
		if armed["kind"] == "enemy":
			var foe = state.unit_at(a.x, a.y)
			if foe != null:
				var ab = armed["ab"]
				if ab != null:
					Combat.resolve_attack(state, unit, foe, ab.get("status", ""), ab.get("status_turns", 0))
					unit["cd"] = ab["cd"]
				else:
					Combat.resolve_attack(state, unit, foe)
		else:   # tile (blink)
			AbilityResolve.do_blink(unit, a.x, a.y)
			unit["cd"] = armed["ab"]["cd"]
		armed = null
		overlay.set_armed({})
		_commit(unit)
		return
	# Miss: cancel the arm and RE-OPEN the menu without freeing the unit (exploit-fix).
	armed = null
	overlay.set_armed({})
	if unit != null:
		_open_menu_for(unit)
```
Add a `_commit` helper (marks the unit acted, clears undo + selection, refreshes), and update `_clear_selection`:
```gdscript
func _commit(unit) -> void:
	if unit != null:
		unit["acted"] = true
	undo_snapshot = null
	armed = null
	action_menu.close()
	summon_list.close()
	overlay.clear_all()
	_finish_action()

func _clear_selection() -> void:
	selected = null
	undo_snapshot = null
	armed = null
	if action_menu != null:
		action_menu.close()
	if summon_list != null:
		summon_list.close()
	if overlay != null:
		overlay.clear_all()
	if info_card != null:
		info_card.clear()
```
NOTE: `_finish_action()` (from Task 5) clears selection, rebuilds units, refreshes the topbar, and prints the winner — `_commit` calls it, so committing fully resets the per-action UI.

- [ ] **Step 6: Remove the temp debug keys + helpers.** In `_unhandled_input`, DELETE the three `elif … KEY_D / KEY_T / KEY_A` branches (and their leading `# --- TEMP M4 verification keys … ---` comment). DELETE the now-unused functions `_debug_spawn_combat`, `_debug_goto_tower`, and `_cast_ability` entirely. (The Enter branch — now `_on_end_turn()` — and the left-click branch remain.)

- [ ] **Step 7: Update the `main.gd` header comment** to reflect the real flow — REPLACE the top doc comment (lines 2–7) with:
```gdscript
## Root match controller (M7): owns a GameState; renders the board + overlay + per-unit
## nodes + a CanvasLayer HUD (topbar / info card / action menu / summon list); a real
## pan/zoom Camera2D. Interaction: click select -> click reachable tile to move -> the
## post-move action menu (Attack / Ability / Capture / Summon / Undo / Wait, built from
## UiQueries.available_actions) drives the rest; Attack/enemy-ability/blink arm then
## resolve on click (a mis-click backs out to the menu). Enter / End-Turn runs the enemy
## AI (player 1) synchronously then hands back. The battle cutaway + move-slide animation
## are M8; title / gameover / save / difficulty-select are M9; real art is M10.
```

- [ ] **Step 8: Headless boot parse gate (the only automated check for this large `main.gd` rewrite).**
```
godot --headless --path godot --quit-after 30 2>&1 | Select-String -Pattern "SCRIPT ERROR|Parse Error|Failed to load"
```
Expected: NO output. If anything matches, fix the parse/load error before continuing.

- [ ] **Step 9: Harness still green.**
```
pwsh -File godot/tests/run_tests.ps1; "EXIT=$LASTEXITCODE"
```
Expected: same count as Task 1, `0 failed`, EXIT 0.

- [ ] **Step 10: SKIP the windowed visual check — no display in-session.** Report it as "NEEDS USER VISUAL CONFIRMATION": user runs `godot --path godot`, selects a unit (reachable tiles highlight, info card fills), clicks a reachable tile (unit moves, action menu pops at the unit), exercises Attack/Ability/Capture/Summon/Undo/Wait, then presses Enter / clicks End-Turn (the CRIMSON AI takes its turn and hands back). Do NOT run the windowed command.

- [ ] **Step 11: Check off M7 in `ROADMAP_GODOT.md`** — change `- [ ] M7 — HUD/UI as Control nodes` to `- [x] M7 — HUD/UI as Control nodes`.

- [ ] **Step 12: Commit.**
```
git add godot/scenes/main.gd ROADMAP_GODOT.md
git commit -m "[godot] M7: real interaction flow (select/move/action-menu/summon/undo) + retire debug keys; close M7"
```

---

## Notes & risk callouts

- **Most of M7 is presentation, so the headless-boot parse gate is the primary automated check** for Tasks 2–7 (scene scripts have no `class_name`). Run it after every task that touches `main.gd` or a scene script, plus the harness to prove no pure logic regressed. Final behavior is the user's visual confirmation.
- **Pure/thin split:** `UiQueries` (Task 1) is the only new logic, and it is fully asserted. The HUD nodes render exactly what it returns and hold no rules — a future C#/redesign of the UI doesn't touch game behavior.
- **Undo is presentation state.** `undo_snapshot` lives in `main.gd`; `available_actions` takes a `has_undo` bool so it stays pure. Undo only appears while the snapshot is live (post-move, pre-commit) and clears on any commit.
- **Mis-click backout (exploit-fix):** arming Attack/Ability then clicking a non-target re-opens the action menu instead of silently deselecting — the JS 6.x fix the M5 port had simplified away. `_resolve_armed`'s miss path now calls `_open_menu_for`.
- **`acted` enforcement is now real:** `_on_click` won't move or re-select an acted unit; `_commit` sets `acted = true`. Summoned units stay `acted = true` (set in `_on_summon_chosen`). The incoming player's units reset in `end_turn` (already implemented in M4).
- **find_summon_slot stays in `ai.gd`;** `main.gd` (already an AI consumer for `take_turn`) calls `AI.find_summon_slot` at summon-commit. `ui_queries.gd` has no AI dependency — no presentation→AI coupling, and the M6 `AI.find_summon_slot` tests are untouched.
- **Deferred to M8 (unchanged by M7):** the move-slide animation (unit snaps to its destination in M7) and the battle cutaway; the AI turn-runner becomes a coroutine there. **M9:** title / gameover / save / difficulty-select / campaign. **M10:** real generated art swaps into `UnitNode._draw` and the terrain `board.gd`.
- **Board stays custom-hex Node2D** (decision 2026-06-11) — no TileMapLayer. Unit nodes and terrain both position via `Hex.axial_to_pixel`, so they stay aligned for free.

## Self-review

- **Spec coverage** (the M7 design doc): pure `available_actions`/`summon_options`/`can_capture` (Task 1); Camera2D pan/zoom (Task 2); per-unit Sprite-style nodes + HP/status indicators (Task 3); highlight overlay reachable/attack/armed/selection (Task 4); topbar + info card (Task 5); anchored action menu + summon sub-list from the pure helpers (Task 6); interaction flow + Undo + mis-click backout + retire debug keys + `acted` gating + close (Task 7). The spec's TileMapLayer item is intentionally superseded by the custom-hex board decision (recorded here and in the deviation note); the board-refactor *intent* (real per-unit nodes, real camera, Control HUD) is delivered. ✅
- **Placeholder scan:** every step ships complete code or an exact command + expected output. ✅
- **Type/signature consistency:** `UiQueries.available_actions(state, unit, has_undo)` / `summon_options(state, master)` / `can_capture(state, unit, cell)` are used consistently in tests, the menus, and `main.gd`. Action-dict keys `kind`/`label`/`disabled` match between `available_actions` and `ActionMenu.open`. `_open_menu_for` / `_on_action_chosen` / `_arm_ability` / `_resolve_armed` / `_commit` / `_on_summon_chosen` / `_on_summon_back` / `_on_end_turn` / `_hex_screen_pos` are all defined in Task 5/7. Overlay's preserved `set_highlights(reach, sel)` + new `set_attack`/`set_armed`/`clear_all` match the `main.gd` calls. `AI.find_summon_slot` (M6) is reused unchanged. ✅
