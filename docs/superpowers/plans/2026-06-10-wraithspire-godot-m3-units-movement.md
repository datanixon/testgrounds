# Wraithspire Godot Port — Milestone 3: Units + Movement/Pathfinding + Selection — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax.

**Goal:** Port the unit data table and unit-record factories from the JS reference, build a pure `GameState` + `Pathfinding` core (Dijkstra reachable, attack targets, path reconstruction), place both archons at match start, and render interactive placeholder unit tokens with click-to-select / click-to-move.

**Architecture:** Pure logic core stays node-free and headless-testable — `unit_types.gd` (const data), `units.gd` (record factories), `game_state.gd` (single source of truth + queries, owns the id counter), `pathfinding.gd` (movement/attack queries operating on a `GameState`). A thin presentation slice (`units_layer.gd` tokens, `overlay.gd` highlights, rewritten `main.gd` controller) reads the core and handles input. No combat, no turn machinery, no AI — those are M4+.

**Tech Stack:** GDScript, the M1/M2 headless harness (`pwsh -ExecutionPolicy Bypass -File godot/tests/run_tests.ps1`). Reference: `game.js` — UNIT_TYPES (392–419), SUMMON_LIST (421), MASTER_TEMPLATE (423–426), makeUnit (430–443), makeMaster (445–461), startNewGame placement (722–732), moveCostFor (827–834), computeReachable (836–866), computeAttackTargets (868–877), reconstructPath (897–909), effectiveMove (5606–5612), PLAYERS palette (76–88).

**Scope note:** M3 ports the unit DATA and the MOVEMENT/SELECTION logic only. XP/leveling (`gainXp`, `applyLevelGrowth`), evolution (`evolveUnit`), combat (`computeDamage`), statuses, and weather are deliberately deferred to M4–M5 alongside the systems that drive them — but the `evolves_to` / `evolved` / `ability` fields are carried verbatim in the data table now (whole-table port). `effective_move` ships a base-move stub; M4 layers in the slow/skitter/weather modifiers exactly as the JS reference does.

---

## File structure (this milestone)

```
godot/data/unit_types.gd          const UNIT_TYPES (20) + SUMMON_LIST (12) + MASTER_TEMPLATE
godot/core/units.gd               make_unit / make_master record factories (pure, id passed in)
godot/core/game_state.gd          GameState: map + units + turn; queries; spawn_*; new_skirmish()
godot/core/pathfinding.gd         effective_move, move_cost_for, compute_reachable,
                                  reconstruct_path, compute_attack_targets (pure, takes GameState)
godot/scenes/match/units_layer.gd UnitsLayer (Node2D): placeholder tokens + team rings
godot/scenes/match/overlay.gd     Overlay (Node2D): reachable highlights + selection outline
godot/scenes/main.gd              REWRITE: GameState + board + overlay + tokens + click input + camera
godot/tests/run_tests.gd          + _test_unit_types, _test_units_state, _test_pathfinding
ROADMAP_GODOT.md                  check off M3
```

**Draw-order contract:** in `main.gd`, children are added board → overlay → units_layer, so tokens paint above the move highlights, which paint above the terrain.

---

## Task 1: Unit data table (UNIT_TYPES / SUMMON_LIST / MASTER_TEMPLATE)

Port the three unit-data structures verbatim. JS camelCase keys become snake_case (`maxHp`→`max_hp`, `evolvesTo`→`evolves_to`, `mpRegen`→`mp_regen`). Numbers and string ids (`ability`, `sprite`, `evolves_to`, `evolved`) are copied exactly — this is a balance-locked table.

**Files:** Create `godot/data/unit_types.gd`; Modify `godot/tests/run_tests.gd`.

- [ ] **Step 1: Add failing unit-types tests to `godot/tests/run_tests.gd`**

Add a preload under the existing `const BoardLib = ...` line:
```gdscript
const UnitTypes = preload("res://data/unit_types.gd")
```
Add a call in `_initialize`, after `_test_board()`:
```gdscript
	_test_unit_types()
```
Append (the function):
```gdscript
func _test_unit_types() -> void:
	# 8 original base + 8 evolved + 4 new base = 20.
	_eq(UnitTypes.UNIT_TYPES.size(), 20, "unit_types: 20 entries")
	_eq(UnitTypes.SUMMON_LIST.size(), 12, "unit_types: 12 summonable")
	_eq(UnitTypes.SUMMON_LIST[0], "cinderling", "unit_types: summon[0]")
	# Representative balance-locked values.
	_eq(UnitTypes.UNIT_TYPES["cinderling"]["max_hp"], 12, "unit_types: cinderling max_hp")
	_eq(UnitTypes.UNIT_TYPES["cinderling"]["move"], 4, "unit_types: cinderling move")
	_eq(UnitTypes.UNIT_TYPES["cinderling"]["evolves_to"], "infernite", "unit_types: cinderling evolves_to")
	_eq(UnitTypes.UNIT_TYPES["geomaul"]["power"], 9, "unit_types: geomaul power")
	_eq(UnitTypes.UNIT_TYPES["skyharrow"]["flying"], true, "unit_types: skyharrow flying")
	_eq(UnitTypes.UNIT_TYPES["infernite"]["evolved"], true, "unit_types: infernite evolved")
	_eq(UnitTypes.UNIT_TYPES["hexwisp"]["element"], "arcane", "unit_types: hexwisp element")
	_eq(UnitTypes.UNIT_TYPES["duneskink"]["ability"], "skitter", "unit_types: duneskink ability")
	# Master template.
	_eq(UnitTypes.MASTER_TEMPLATE["max_hp"], 40, "unit_types: master max_hp")
	_eq(UnitTypes.MASTER_TEMPLATE["max_mp"], 30, "unit_types: master max_mp")
	_eq(UnitTypes.MASTER_TEMPLATE["mp_regen"], 4, "unit_types: master mp_regen")
	_eq(UnitTypes.MASTER_TEMPLATE["move"], 3, "unit_types: master move")
```

- [ ] **Step 2: Run — verify it fails (unit_types.gd missing)**
```
pwsh -ExecutionPolicy Bypass -File godot/tests/run_tests.ps1; "EXIT=$LASTEXITCODE"
```
Expected: parse/load error about `res://data/unit_types.gd`, non-zero EXIT.

- [ ] **Step 3: Create `godot/data/unit_types.gd`, verbatim:**
```gdscript
class_name UnitTypes
extends RefCounted
## Faithful port of game.js UNIT_TYPES / SUMMON_LIST / MASTER_TEMPLATE (sec. 4).
## Balance-locked numbers — verified against the reference. `evolves_to` /
## `evolved` / `ability` are carried as DATA now; the leveling, evolution, and
## ability LOGIC land in M4/M5 alongside the systems that read them.

const UNIT_TYPES := {
	# Base monsters (original 8)
	"cinderling":  {"name": "Cinderling",  "element": "pyro",   "max_hp": 12, "move": 4, "range": 1, "power": 5,  "def": 1, "cost": 6,  "flying": false, "sprite": "imp",      "attack": "melee",  "evolves_to": "infernite",    "ability": "ignite"},
	"pyrowyrm":    {"name": "Pyrowyrm",    "element": "pyro",   "max_hp": 18, "move": 3, "range": 2, "power": 7,  "def": 2, "cost": 12, "flying": false, "sprite": "wyrm",     "attack": "breath", "evolves_to": "emberdrake",   "ability": "cinderBreath"},
	"tidekin":     {"name": "Tidekin",     "element": "hydro",  "max_hp": 14, "move": 4, "range": 1, "power": 5,  "def": 2, "cost": 7,  "flying": false, "sprite": "merfolk",  "attack": "melee",  "evolves_to": "tidelord",     "ability": "healPulse"},
	"mistleviath": {"name": "Mistlevy",    "element": "hydro",  "max_hp": 20, "move": 3, "range": 2, "power": 6,  "def": 3, "cost": 14, "flying": false, "sprite": "serpent",  "attack": "spray",  "evolves_to": "leviathan",    "ability": "undertow"},
	"stoneward":   {"name": "Stoneward",   "element": "terra",  "max_hp": 22, "move": 2, "range": 1, "power": 5,  "def": 4, "cost": 8,  "flying": false, "sprite": "golem",    "attack": "melee",  "evolves_to": "colossus",     "ability": "bulwark"},
	"geomaul":     {"name": "Geomaul",     "element": "terra",  "max_hp": 26, "move": 2, "range": 1, "power": 9,  "def": 4, "cost": 16, "flying": false, "sprite": "ogre",     "attack": "melee",  "evolves_to": "earthbreaker", "ability": "quake"},
	"galewisp":    {"name": "Galewisp",    "element": "zephyr", "max_hp": 10, "move": 5, "range": 2, "power": 4,  "def": 1, "cost": 7,  "flying": true,  "sprite": "wisp",     "attack": "spark",  "evolves_to": "stormwisp",    "ability": "galeRush"},
	"skyharrow":   {"name": "Skyharrow",   "element": "zephyr", "max_hp": 16, "move": 4, "range": 2, "power": 7,  "def": 2, "cost": 13, "flying": true,  "sprite": "raptor",   "attack": "dive",   "evolves_to": "skytyrant",    "ability": "diveMark"},
	# Evolved forms (terminal tier; not directly summonable)
	"infernite":    {"name": "Infernite",    "element": "pyro",   "max_hp": 22, "move": 4, "range": 1, "power": 9,  "def": 3, "cost": 18, "flying": false, "sprite": "infernite",    "attack": "melee",  "evolved": true, "ability": "ignite"},
	"emberdrake":   {"name": "Emberdrake",   "element": "pyro",   "max_hp": 30, "move": 3, "range": 2, "power": 11, "def": 4, "cost": 26, "flying": false, "sprite": "emberdrake",   "attack": "breath", "evolved": true, "ability": "cinderBreath"},
	"tidelord":     {"name": "Tidelord",     "element": "hydro",  "max_hp": 24, "move": 4, "range": 1, "power": 9,  "def": 4, "cost": 18, "flying": false, "sprite": "tidelord",     "attack": "melee",  "evolved": true, "ability": "healPulse"},
	"leviathan":    {"name": "Leviathan",    "element": "hydro",  "max_hp": 32, "move": 3, "range": 2, "power": 10, "def": 5, "cost": 28, "flying": false, "sprite": "leviathan",    "attack": "spray",  "evolved": true, "ability": "undertow"},
	"colossus":     {"name": "Colossus",     "element": "terra",  "max_hp": 36, "move": 2, "range": 1, "power": 9,  "def": 6, "cost": 20, "flying": false, "sprite": "colossus",     "attack": "melee",  "evolved": true, "ability": "bulwark"},
	"earthbreaker": {"name": "Earthbreaker", "element": "terra",  "max_hp": 42, "move": 2, "range": 1, "power": 14, "def": 6, "cost": 30, "flying": false, "sprite": "earthbreaker", "attack": "melee",  "evolved": true, "ability": "quake"},
	"stormwisp":    {"name": "Stormwisp",    "element": "zephyr", "max_hp": 18, "move": 5, "range": 2, "power": 8,  "def": 2, "cost": 18, "flying": true,  "sprite": "stormwisp",    "attack": "spark",  "evolved": true, "ability": "galeRush"},
	"skytyrant":    {"name": "Skytyrant",    "element": "zephyr", "max_hp": 26, "move": 4, "range": 2, "power": 11, "def": 3, "cost": 24, "flying": true,  "sprite": "skytyrant",    "attack": "dive",   "evolved": true, "ability": "diveMark"},
	# New base monsters (arcane coverage + roster depth)
	"hexwisp":   {"name": "Hexwisp",   "element": "arcane", "max_hp": 11, "move": 5, "range": 2, "power": 5,  "def": 1, "cost": 8,  "flying": true,  "sprite": "hexwisp",   "attack": "bolt",  "ability": "blink"},
	"runeward":  {"name": "Runeward",  "element": "arcane", "max_hp": 24, "move": 2, "range": 1, "power": 7,  "def": 5, "cost": 15, "flying": false, "sprite": "runeward",  "attack": "melee", "ability": "ward"},
	"frostmaw":  {"name": "Frostmaw",  "element": "hydro",  "max_hp": 28, "move": 3, "range": 1, "power": 10, "def": 3, "cost": 18, "flying": false, "sprite": "frostmaw",  "attack": "melee", "ability": "frostBite"},
	"duneskink": {"name": "Duneskink", "element": "terra",  "max_hp": 13, "move": 5, "range": 1, "power": 6,  "def": 1, "cost": 6,  "flying": false, "sprite": "duneskink", "attack": "melee", "ability": "skitter"},
}

const SUMMON_LIST := ["cinderling", "tidekin", "stoneward", "galewisp", "duneskink", "pyrowyrm", "hexwisp", "mistleviath", "runeward", "geomaul", "frostmaw", "skyharrow"]

const MASTER_TEMPLATE := {
	"name": "Archon", "element": "arcane", "max_hp": 40, "max_mp": 30, "move": 3, "range": 1,
	"power": 7, "def": 3, "mp_regen": 4, "flying": false, "sprite": "archon", "attack": "bolt",
}
```

- [ ] **Step 4: Run — verify pass**
```
pwsh -ExecutionPolicy Bypass -File godot/tests/run_tests.ps1; "EXIT=$LASTEXITCODE"
```
Expected: green, `EXIT=0` (15 new asserts). `0 failed` is the gate.

- [ ] **Step 5: Commit**
```
git add godot/data/unit_types.gd godot/tests/run_tests.gd
git commit -m "[godot] M3: unit data table (UNIT_TYPES + SUMMON_LIST + MASTER_TEMPLATE)"
```

---

## Task 2: Unit factories + GameState (TDD)

Port `makeUnit`/`makeMaster` as pure factories returning plain Dictionaries (units serialize directly for save/load later). The `id` is passed IN so the factories stay pure; `GameState` owns the counter and wraps them via `spawn_*`. `GameState` is the single source of truth (the logic-only slice of the JS `STATE`): it holds the generated map + the unit list + turn bookkeeping and provides the query helpers pathfinding needs (`cell_at`, `in_bounds`, `unit_at`, `alive_units`, `master_of`).

**Note on the master name:** the JS reference names the master `"Archon of AZURE"`. The faction/player name table is a presentation concern that arrives with the HUD (M7); M3 uses the bare `MASTER_TEMPLATE.name` (`"Archon"`). The `" of <player>"` suffix is added when the players table lands. Master `mp` starts at `14` (not `max_mp`), faithful to JS line 452.

**Files:** Create `godot/core/units.gd`, `godot/core/game_state.gd`; Modify `godot/tests/run_tests.gd`.

- [ ] **Step 1: Add failing unit/state tests to `godot/tests/run_tests.gd`**

Add preloads under the others:
```gdscript
const Units = preload("res://core/units.gd")
const GameState = preload("res://core/game_state.gd")
```
Add the call after `_test_unit_types()`:
```gdscript
	_test_units_state()
```
Append:
```gdscript
func _test_units_state() -> void:
	# --- factories ---
	var m := Units.make_master(1, 0, 3, 4)
	_eq(m["id"], 1, "units: master id")
	_eq(m["type_key"], "master", "units: master type_key")
	_eq(m["hp"], 40, "units: master hp")
	_eq(m["max_mp"], 30, "units: master max_mp")
	_eq(m["mp"], 14, "units: master starting mp")
	_eq(m["move"], 3, "units: master move")
	_eq(m["is_master"], true, "units: master is_master")
	_eq(m["q"], 3, "units: master q")
	var u := Units.make_unit(2, "cinderling", 1, 5, 6)
	_eq(u["type_key"], "cinderling", "units: unit type_key")
	_eq(u["max_hp"], 12, "units: unit max_hp")
	_eq(u["hp"], 12, "units: unit hp == max_hp")
	_eq(u["move"], 4, "units: unit move")
	_eq(u["owner"], 1, "units: unit owner")
	_eq(u["is_master"], false, "units: unit is_master")
	_eq(u["level"], 1, "units: unit level")
	_eq(u["acted"], false, "units: unit acted")
	# --- GameState queries ---
	var gs := GameState.new_skirmish(Maps.MAPS[0], 42)
	_eq(gs.units.size(), 2, "state: two archons placed")
	_eq(gs.current_player, 0, "state: starts player 0")
	var m0 := gs.master_of(0)
	var m1 := gs.master_of(1)
	_ok(m0 != null and m1 != null, "state: both masters found")
	_eq(m0["owner"], 0, "state: master_of(0) owner")
	_eq(m1["owner"], 1, "state: master_of(1) owner")
	_ok(m0["id"] != m1["id"], "state: distinct ids")
	# masters sit on the two castles
	var castles: Array = gs.map["castles"]
	_eq(Vector2i(m0["q"], m0["r"]), castles[0], "state: master 0 on castle 0")
	_eq(Vector2i(m1["q"], m1["r"]), castles[1], "state: master 1 on castle 1")
	# unit_at / alive_units / bounds / cell_at
	_eq(gs.unit_at(m0["q"], m0["r"])["id"], m0["id"], "state: unit_at finds master")
	_eq(gs.unit_at(9999, 9999), null, "state: unit_at empty -> null")
	_eq(gs.alive_units(0).size(), 1, "state: alive_units(0)")
	_ok(gs.in_bounds(castles[0].x, castles[0].y), "state: castle in bounds")
	_ok(not gs.in_bounds(9999, 9999), "state: off-board not in bounds")
	_eq(gs.cell_at(castles[0].x, castles[0].y)["terrain"], "castle", "state: cell_at castle terrain")
	_eq(gs.cell_at(9999, 9999), null, "state: cell_at off-board -> null")
```

- [ ] **Step 2: Run — verify it fails (units.gd / game_state.gd missing)**
```
pwsh -ExecutionPolicy Bypass -File godot/tests/run_tests.ps1; "EXIT=$LASTEXITCODE"
```
Expected: parse/load error about `res://core/units.gd`, non-zero EXIT.

- [ ] **Step 3: Create `godot/core/units.gd`, verbatim:**
```gdscript
class_name Units
extends RefCounted
## Pure unit-record factories — port of game.js makeUnit / makeMaster (sec. 4).
## A unit is a plain Dictionary so the logic core stays node-free and records
## serialize directly for save/load. `id` is supplied by the caller (GameState
## owns the counter) so the factories stay pure and testable in isolation.

const UnitTypes = preload("res://data/unit_types.gd")

static func make_unit(id: int, type_key: String, owner: int, q: int, r: int) -> Dictionary:
	var t: Dictionary = UnitTypes.UNIT_TYPES[type_key]
	return {
		"id": id, "type_key": type_key, "name": t["name"], "element": t["element"],
		"owner": owner, "q": q, "r": r,
		"hp": t["max_hp"], "max_hp": t["max_hp"],
		"move": t["move"], "range": t["range"], "power": t["power"], "def": t["def"],
		"flying": t["flying"], "sprite": t["sprite"], "attack": t["attack"],
		"level": 1, "xp": 0,
		"acted": false, "is_master": false,
		"cd": 0, "second_move": false,
	}

static func make_master(id: int, owner: int, q: int, r: int) -> Dictionary:
	var t := UnitTypes.MASTER_TEMPLATE
	return {
		"id": id, "type_key": "master", "name": t["name"], "element": t["element"],
		"owner": owner, "q": q, "r": r,
		"hp": t["max_hp"], "max_hp": t["max_hp"],
		"mp": 14, "max_mp": t["max_mp"],
		"move": t["move"], "range": t["range"], "power": t["power"], "def": t["def"],
		"mp_regen": t["mp_regen"],
		"flying": false, "sprite": "archon", "attack": "bolt",
		"level": 1, "xp": 0,
		"acted": false, "is_master": true,
		"cd": 0, "second_move": false,
	}
```

- [ ] **Step 4: Create `godot/core/game_state.gd`, verbatim:**
```gdscript
class_name GameState
extends RefCounted
## Single source of truth for a match — the logic-only slice of the JS STATE.
## Holds the generated map + the unit list + turn bookkeeping, owns the unit id
## counter, and exposes the query helpers pathfinding reads. Pure: no nodes,
## instantiable in isolation for headless tests.

const Units = preload("res://core/units.gd")
const MapGen = preload("res://core/map_gen.gd")

var map: Dictionary = {}              # the generate() result: cols, rows, cells, castles, towers
var units: Array[Dictionary] = []
var current_player: int = 0
var turn: int = 1
var _next_id: int = 1

func _new_id() -> int:
	var n := _next_id
	_next_id += 1
	return n

## cellAt — the terrain cell at (q,r), or null off-board. Returns the live dict
## (reference), so callers may mutate the stored map.
func cell_at(q: int, r: int) -> Variant:
	return map.get("cells", {}).get("%d,%d" % [q, r])

## inBounds — whether (q,r) is a real cell on this map.
func in_bounds(q: int, r: int) -> bool:
	return map.get("cells", {}).has("%d,%d" % [q, r])

## unitAt — first living unit on (q,r), or null.
func unit_at(q: int, r: int) -> Variant:
	for u in units:
		if u["q"] == q and u["r"] == r and u["hp"] > 0:
			return u
	return null

func alive_units(owner: int) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for u in units:
		if u["hp"] > 0 and u["owner"] == owner:
			out.append(u)
	return out

func master_of(owner: int) -> Variant:
	for u in units:
		if u["is_master"] and u["owner"] == owner and u["hp"] > 0:
			return u
	return null

func spawn_unit(type_key: String, owner: int, q: int, r: int) -> Dictionary:
	var u := Units.make_unit(_new_id(), type_key, owner, q, r)
	units.append(u)
	return u

func spawn_master(owner: int, q: int, r: int) -> Dictionary:
	var u := Units.make_master(_new_id(), owner, q, r)
	units.append(u)
	return u

## new_skirmish — port of startNewGame's match setup (sec. 13): generate the map,
## place both archons on their castles, start at turn 1 / player 0. Campaign AI
## summons + weather init land in their owning milestones.
static func new_skirmish(def: Dictionary, seed: int) -> GameState:
	var gs := GameState.new()
	gs.map = MapGen.generate(seed, def)
	var castles: Array = gs.map["castles"]
	gs.spawn_master(0, castles[0].x, castles[0].y)
	gs.spawn_master(1, castles[1].x, castles[1].y)
	gs.current_player = 0
	gs.turn = 1
	return gs
```

- [ ] **Step 5: Run — verify pass**
```
pwsh -ExecutionPolicy Bypass -File godot/tests/run_tests.ps1; "EXIT=$LASTEXITCODE"
```
Expected: green, `EXIT=0` (28 new asserts). `0 failed` is the gate.

- [ ] **Step 6: Commit**
```
git add godot/core/units.gd godot/core/game_state.gd godot/tests/run_tests.gd
git commit -m "[godot] M3: unit factories + GameState (single source of truth + queries)"
```

---

## Task 3: Pathfinding — reachable, attack targets, path (TDD)

Faithful port of `moveCostFor` / `computeReachable` / `reconstructPath` / `computeAttackTargets` (game.js sec. 6) + `effectiveMove` (sec. 16). All pure, all take a `GameState` instead of the JS globals (`STATE`/`MAP`). Movement rules: enemy-occupied tiles block pathing; a tile that ENDS on any other unit is dropped from the reachable set (the start tile is kept); flyers cost 1 everywhere and ignore the mountain/water bans; non-flyers can't enter `blocks` terrain (water) or mountains.

**Files:** Create `godot/core/pathfinding.gd`; Modify `godot/tests/run_tests.gd`.

- [ ] **Step 1: Add failing pathfinding tests to `godot/tests/run_tests.gd`**

Add a preload:
```gdscript
const Pathfinding = preload("res://core/pathfinding.gd")
```
Add the call after `_test_units_state()`:
```gdscript
	_test_pathfinding()
```
Append (a constructed-board helper + the test — no JS capture needed; these assert the algorithm's properties directly):
```gdscript
# A rectangular all-`terrain` board (axial q,r in [0,cols)x[0,rows)). in_bounds is
# a plain dict lookup, so the un-offset rectangle is fine for movement asserts.
func _flat_state(cols: int, rows: int, terrain := "plain") -> GameState:
	var gs := GameState.new()
	var cells := {}
	for r in range(rows):
		for q in range(cols):
			cells["%d,%d" % [q, r]] = {"q": q, "r": r, "terrain": terrain, "owner": -1}
	gs.map = {"cols": cols, "rows": rows, "cells": cells, "castles": [], "towers": []}
	return gs

func _test_pathfinding() -> void:
	# --- move_cost_for: terrain + flying matrix ---
	var ground := {"flying": false}
	var flyer := {"flying": true}
	_eq(Pathfinding.move_cost_for(ground, {"terrain": "plain"}), 1.0, "cost: plain ground")
	_eq(Pathfinding.move_cost_for(ground, {"terrain": "forest"}), 2.0, "cost: forest ground")
	_ok(not is_finite(Pathfinding.move_cost_for(ground, {"terrain": "water"})), "cost: water ground INF")
	_eq(Pathfinding.move_cost_for(flyer, {"terrain": "water"}), 1.0, "cost: water flyer")
	_ok(not is_finite(Pathfinding.move_cost_for(ground, {"terrain": "mountain"})), "cost: mountain ground INF")
	_eq(Pathfinding.move_cost_for(flyer, {"terrain": "mountain"}), 1.0, "cost: mountain flyer")
	_ok(not is_finite(Pathfinding.move_cost_for(ground, null)), "cost: off-board INF")

	# --- reachable on an open plain field ---
	var gs := _flat_state(9, 9)
	var mover := gs.spawn_unit("stoneward", 0, 4, 4)   # move 2... use a 3-mover instead:
	mover["move"] = 3
	var reach := Pathfinding.compute_reachable(gs, mover)
	_ok(reach.has("4,4"), "reach: start present")
	_ok(reach.has("7,4"), "reach: distance-3 reachable")        # hex_distance((4,4),(7,4)) == 3
	_ok(not reach.has("8,4"), "reach: distance-4 unreachable")  # cost 4 > move 3
	# On uniform plain, every reachable tile's cost equals its hex distance and is <= move.
	var all_ok := true
	for k in reach:
		var v: Dictionary = reach[k]
		var d := HexLib.distance(Vector2i(4, 4), Vector2i(v["q"], v["r"]))
		if v["cost"] != d or v["cost"] > 3:
			all_ok = false
	_ok(all_ok, "reach: cost == hex distance, <= move")

	# --- enemy blocks, friendly is passable ---
	var gs2 := _flat_state(9, 9)
	var u2 := gs2.spawn_unit("cinderling", 0, 4, 4)   # move 4
	gs2.spawn_unit("cinderling", 1, 5, 4)             # ENEMY directly east (4,4)->(5,4)
	var reach2 := Pathfinding.compute_reachable(gs2, u2)
	_ok(not reach2.has("5,4"), "reach: enemy tile excluded")
	_ok(reach2.has("6,4"), "reach: tile past enemy still reachable around")
	var gs3 := _flat_state(9, 9)
	var u3 := gs3.spawn_unit("cinderling", 0, 4, 4)   # move 4
	gs3.spawn_unit("cinderling", 0, 5, 4)             # FRIENDLY east — passable, but a dead end
	var reach3 := Pathfinding.compute_reachable(gs3, u3)
	_ok(not reach3.has("5,4"), "reach: friendly-occupied tile dropped as a destination")
	_eq(reach3["6,4"]["cost"], 2, "reach: path passes THROUGH friendly (cost 2)")

	# --- flyer crosses water; grounded unit is stuck ---
	var gw := _flat_state(9, 9, "water")
	var fly := gw.spawn_unit("galewisp", 0, 4, 4)     # flying, move 5
	var reach_fly := Pathfinding.compute_reachable(gw, fly)
	_ok(reach_fly.size() > 1, "reach: flyer moves over water")
	var gg := _flat_state(9, 9, "water")
	var grd := gg.spawn_unit("cinderling", 0, 4, 4)   # grounded
	var reach_grd := Pathfinding.compute_reachable(gg, grd)
	_eq(reach_grd.size(), 1, "reach: grounded unit landlocked (start only)")

	# --- attack targets by range ---
	var ga := _flat_state(9, 9)
	var melee := ga.spawn_unit("cinderling", 0, 4, 4) # range 1
	var foe := ga.spawn_unit("cinderling", 1, 5, 4)   # distance 1
	var ally := ga.spawn_unit("cinderling", 0, 3, 4)  # friendly, never a target
	var t1 := Pathfinding.compute_attack_targets(ga, melee, melee["q"], melee["r"])
	_eq(t1.size(), 1, "attack: melee hits adjacent foe")
	_ok(t1.has("5,4"), "attack: foe key present")
	foe["q"] = 6   # move foe to distance 2
	var t2 := Pathfinding.compute_attack_targets(ga, melee, melee["q"], melee["r"])
	_eq(t2.size(), 0, "attack: melee can't reach distance 2")
	var ranged := ga.spawn_unit("pyrowyrm", 0, 4, 4)  # range 2, same tile as melee for the query
	var t3 := Pathfinding.compute_attack_targets(ga, ranged, 4, 4)
	_ok(t3.has("6,4"), "attack: range-2 reaches distance-2 foe")
	_ok(not t3.has("3,4"), "attack: friendly excluded")

	# --- reconstruct_path: contiguous, start-first ---
	var gp := _flat_state(9, 9)
	var pm := gp.spawn_unit("cinderling", 0, 4, 4)
	var rp := Pathfinding.compute_reachable(gp, pm)
	var path := Pathfinding.reconstruct_path(rp, 7, 4)
	_eq(path[0], Vector2i(4, 4), "path: starts at the unit")
	_eq(path[path.size() - 1], Vector2i(7, 4), "path: ends at the destination")
	var contiguous := true
	for i in range(1, path.size()):
		if HexLib.distance(path[i - 1], path[i]) != 1:
			contiguous = false
	_ok(contiguous, "path: each step is one hex")
```

- [ ] **Step 2: Run — verify it fails (pathfinding.gd missing)**
```
pwsh -ExecutionPolicy Bypass -File godot/tests/run_tests.ps1; "EXIT=$LASTEXITCODE"
```
Expected: parse/load error about `res://core/pathfinding.gd`, non-zero EXIT.

- [ ] **Step 3: Create `godot/core/pathfinding.gd`, verbatim:**
```gdscript
class_name Pathfinding
extends RefCounted
## Pure movement/attack queries — port of game.js sec. 6 (computeReachable,
## reconstructPath, computeAttackTargets) + effectiveMove (sec. 16). Operates on a
## GameState; no globals, no nodes. The reachable search is the AI's hot path and
## the most likely future C#-swap candidate, so it stays clean and side-effect-free.

const Hex = preload("res://core/hex.gd")
const Terrain = preload("res://data/terrain.gd")

## effectiveMove — a unit's move allowance. M3 returns base move; the status
## (slow / skitterBoost) and weather (flyBonus) modifiers layer in at M4 when
## those systems exist, exactly as in the JS reference (effectiveMove).
static func effective_move(unit: Dictionary) -> int:
	return unit["move"]

## moveCostFor — cost to ENTER `cell`, or INF if impassable for this unit. `cell`
## may be null (off-board). Flyers pay 1 everywhere and ignore the mountain/water
## bans; grounded units can't enter `blocks` terrain (water) or mountains.
static func move_cost_for(unit: Dictionary, cell: Variant) -> float:
	if cell == null:
		return INF
	var t: Dictionary = Terrain.TERRAIN[cell["terrain"]]
	if t.get("blocks", false) and not unit["flying"]:
		return INF
	if cell["terrain"] == "mountain" and not unit["flying"]:
		return INF
	if unit["flying"]:
		return 1.0
	return float(t["move_cost"])

## computeReachable — Dijkstra over move cost from the unit's tile. Returns
##   { "q,r": {cost:int, prev:String|null, q:int, r:int} }
## Enemy-occupied tiles block movement (never entered); the final pass drops any
## tile that ends on another unit (the start tile is kept, so the menu/anim have
## an anchor). Friendly units are passable but not valid destinations.
static func compute_reachable(state, unit: Dictionary) -> Dictionary:
	var out := {}
	var start := Hex.key(Vector2i(unit["q"], unit["r"]))
	out[start] = {"cost": 0, "prev": null, "q": unit["q"], "r": unit["r"]}
	var frontier: Array = [{"q": unit["q"], "r": unit["r"], "cost": 0}]
	var limit := effective_move(unit)
	while not frontier.is_empty():
		frontier.sort_custom(func(a, b): return a["cost"] < b["cost"])
		var cur: Dictionary = frontier.pop_front()
		for n in Hex.neighbors(Vector2i(cur["q"], cur["r"])):
			if not state.in_bounds(n.x, n.y):
				continue
			var cell: Variant = state.cell_at(n.x, n.y)
			var blocker: Variant = state.unit_at(n.x, n.y)
			if blocker != null and blocker["owner"] != unit["owner"]:
				continue
			var step := move_cost_for(unit, cell)
			if not is_finite(step):
				continue
			var new_cost: int = cur["cost"] + int(step)
			if new_cost > limit:
				continue
			var key := Hex.key(n)
			var existing: Variant = out.get(key)
			if existing == null or existing["cost"] > new_cost:
				out[key] = {"cost": new_cost, "prev": Hex.key(Vector2i(cur["q"], cur["r"])), "q": n.x, "r": n.y}
				frontier.append({"q": n.x, "r": n.y, "cost": new_cost})
	# Drop tiles that end on a unit (keep the start tile).
	for k in out.keys():
		var v: Dictionary = out[k]
		var u: Variant = state.unit_at(v["q"], v["r"])
		if u != null and not (v["q"] == unit["q"] and v["r"] == unit["r"]):
			out.erase(k)
	return out

## reconstructPath — walk prev links back from (q,r) to the start, start-first.
## Returns Array[Vector2i]. Guarded against cycles (4096 cap, as in the JS).
static func reconstruct_path(reach: Dictionary, q: int, r: int) -> Array:
	var path: Array = []
	var key: Variant = Hex.key(Vector2i(q, r))
	var guard := 0
	while key != null and guard < 4096:
		guard += 1
		var node: Variant = reach.get(key)
		if node == null:
			break
		path.append(Vector2i(node["q"], node["r"]))
		key = node["prev"]
	path.reverse()
	return path

## computeAttackTargets — set of "q,r" keys of enemies within `unit.range` of
## (from_q, from_r). Returned as a Dictionary used as a set (key -> true).
static func compute_attack_targets(state, unit: Dictionary, from_q: int, from_r: int) -> Dictionary:
	var targets := {}
	for u in state.units:
		if u["hp"] <= 0:
			continue
		if u["owner"] == unit["owner"]:
			continue
		var d := Hex.distance(Vector2i(from_q, from_r), Vector2i(u["q"], u["r"]))
		if d <= unit["range"] and d >= 1:
			targets[Hex.key(Vector2i(u["q"], u["r"]))] = true
	return targets
```

- [ ] **Step 4: Run — verify pass**
```
pwsh -ExecutionPolicy Bypass -File godot/tests/run_tests.ps1; "EXIT=$LASTEXITCODE"
```
Expected: green, `EXIT=0` (~25 new asserts). If `reach: cost == hex distance` fails, the Dijkstra frontier ordering diverged (check the `sort_custom` ascending-by-cost + `pop_front`). If `reach: path passes THROUGH friendly (cost 2)` fails, the blocker check is wrongly skipping friendly units (it must skip ONLY enemies). `0 failed` is the gate.

- [ ] **Step 5: Commit**
```
git add godot/core/pathfinding.gd godot/tests/run_tests.gd
git commit -m "[godot] M3: pathfinding (reachable Dijkstra + attack targets + path)"
```

---

## Task 4: Interactive tokens + selection + close M3

Render placeholder unit tokens (team ring + element body) over the board, draw the move overlay, and wire click-to-select / click-to-move via the pure core. The terrain→color, token geometry, and pathfinding are headless-tested; the on-screen interaction is confirmed visually. **No turn flow** — M3 lets you freely reselect and re-move any unit so movement is easy to eyeball (the `acted`/turn gate arrives in M4).

**Files:** Create `godot/scenes/match/units_layer.gd`, `godot/scenes/match/overlay.gd`; Modify `godot/scenes/main.gd`, `ROADMAP_GODOT.md`. (`main.tscn` is unchanged — it still loads `main.gd`.)

- [ ] **Step 1: Create `godot/scenes/match/units_layer.gd`, verbatim:**
```gdscript
class_name UnitsLayer
extends Node2D
## Placeholder unit tokens: an element-colored body inside a team-colored ring,
## with a white pip on archons. Real sprites swap in at the art milestone (M10);
## only this layer changes. Reads unit records straight from the GameState.

const Hex = preload("res://core/hex.gd")

## Team ring colors — AZURE / CRIMSON, from the JS PLAYERS palette (PAL.p0 / p1).
const TEAM_COLORS := [Color("#5aa8d8"), Color("#cc6a4a")]
## Placeholder element fills for board readability until real art lands.
const ELEMENT_COLORS := {
	"pyro": Color("#d8662e"), "hydro": Color("#3a7ad8"), "terra": Color("#9a8a52"),
	"zephyr": Color("#7fd0c0"), "arcane": Color("#a06ad8"),
}

var state   # GameState (untyped to avoid a node<->RefCounted preload cycle)

func set_state(s) -> void:
	state = s
	queue_redraw()

func _draw() -> void:
	if state == null:
		return
	for u in state.units:
		if u["hp"] <= 0:
			continue
		var c := Hex.axial_to_pixel(Vector2i(u["q"], u["r"]))
		var ring: Color = TEAM_COLORS[u["owner"]]
		var fill: Color = ELEMENT_COLORS.get(u["element"], Color("#cccccc"))
		var radius := Hex.SIZE * 0.62
		draw_circle(c, radius, ring)               # team ring
		draw_circle(c, radius * 0.74, fill)        # element body
		if u["is_master"]:
			draw_circle(c, radius * 0.30, Color(1, 1, 1, 0.9))  # master pip
```

- [ ] **Step 2: Create `godot/scenes/match/overlay.gd`, verbatim:**
```gdscript
class_name Overlay
extends Node2D
## Move/selection highlights, drawn above the board and below the tokens.
## Reachable tiles get a translucent blue fill; the selected unit's tile gets a
## bright yellow outline. Fed by main.gd from Pathfinding.compute_reachable.

const Hex = preload("res://core/hex.gd")
const BoardLib = preload("res://scenes/board/board.gd")

var reachable: Dictionary = {}    # compute_reachable() result
var selected: Variant = null      # the selected unit record, or null

func set_highlights(reach: Dictionary, sel) -> void:
	reachable = reach
	selected = sel
	queue_redraw()

func _draw() -> void:
	for key in reachable:
		var v: Dictionary = reachable[key]
		var pts := BoardLib.hex_corners(Hex.axial_to_pixel(Vector2i(v["q"], v["r"])))
		draw_colored_polygon(pts, Color(0.4, 0.7, 1.0, 0.28))
	if selected != null:
		var outline := BoardLib.hex_corners(Hex.axial_to_pixel(Vector2i(selected["q"], selected["r"])))
		outline.append(outline[0])
		draw_polyline(outline, Color(1.0, 1.0, 0.4, 0.95), 3.0)
```

- [ ] **Step 3: Replace `godot/scenes/main.gd` entirely, verbatim:**
```gdscript
extends Node2D
## Root match controller (M3): owns a GameState, renders the board + move overlay
## + unit tokens, and handles click-to-select / click-to-move through the pure
## core. A placeholder interactive slice — turn flow, combat, and AI arrive in
## later milestones, so any unit may be reselected and re-moved freely here.

const Hex = preload("res://core/hex.gd")
const Maps = preload("res://data/maps.gd")
const GameState = preload("res://core/game_state.gd")
const Pathfinding = preload("res://core/pathfinding.gd")
const BoardScript = preload("res://scenes/board/board.gd")
const UnitsLayerScript = preload("res://scenes/match/units_layer.gd")
const OverlayScript = preload("res://scenes/match/overlay.gd")

var state
var overlay
var units_layer
var selected = null

func _ready() -> void:
	state = GameState.new_skirmish(Maps.MAPS[0], 42)
	# Draw order: board (bottom) -> overlay -> tokens (top).
	var board := BoardScript.new()
	board.set_map(state.map)
	add_child(board)
	overlay = OverlayScript.new()
	add_child(overlay)
	units_layer = UnitsLayerScript.new()
	units_layer.set_state(state)
	add_child(units_layer)
	var cam := Camera2D.new()
	var m = state.master_of(0)
	cam.position = Hex.axial_to_pixel(Vector2i(m["q"], m["r"]))
	add_child(cam)
	cam.make_current()

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		_on_click(Hex.pixel_to_axial(get_global_mouse_position()))

func _on_click(a: Vector2i) -> void:
	# With a unit selected, a click on a reachable tile moves it there.
	if selected != null:
		var reach := Pathfinding.compute_reachable(state, selected)
		if reach.has(Hex.key(a)):
			selected["q"] = a.x
			selected["r"] = a.y
			_clear_selection()
			units_layer.set_state(state)   # redraw tokens at the new position
			return
	# Otherwise (re)select the current player's unit under the cursor.
	var u = state.unit_at(a.x, a.y)
	if u != null and u["owner"] == state.current_player:
		selected = u
		overlay.set_highlights(Pathfinding.compute_reachable(state, u), u)
	else:
		_clear_selection()

func _clear_selection() -> void:
	selected = null
	overlay.set_highlights({}, null)
```

- [ ] **Step 4: Run the harness — confirm no regression**
```
pwsh -ExecutionPolicy Bypass -File godot/tests/run_tests.ps1; "EXIT=$LASTEXITCODE"
```
Expected: green, `EXIT=0` (no new asserts in this task — presentation is visual-confirmed; this run guards against a parse error in the new scripts breaking the project load).

- [ ] **Step 5: Visual confirmation (windowed)** — run the project and confirm: the hex map renders with two round tokens on the castles (one blue-ringed AZURE, one red-ringed CRIMSON, each with a white master pip); clicking an archon outlines its tile yellow and tints its reachable tiles blue; clicking a blue tile slides... (no slide yet — it jumps) the token there and clears the highlight; clicking empty/own-unit re-selects or deselects.
```
godot --path godot
```
Close the window when confirmed. (Opens a window — the manual visual check the spec calls for. A subagent without a display reports this step as "needs user visual confirmation" rather than guessing.)

- [ ] **Step 6: Check off M3 in `ROADMAP_GODOT.md`** — change `- [ ] M3 — ...` to `- [x] M3 — ...`.

- [ ] **Step 7: Commit**
```
git add godot/scenes/match/units_layer.gd godot/scenes/match/overlay.gd godot/scenes/main.gd ROADMAP_GODOT.md
git commit -m "[godot] M3: interactive unit tokens + selection/movement; close M3"
```

---

## Notes & risk callouts

- **Pure core takes a `GameState`, not globals.** The JS `computeReachable`/`computeAttackTargets` read module globals (`STATE`, `MAP`, `unitAt`, `cellAt`, `inBounds`). The port threads a `GameState` through instead, keeping the search side-effect-free and the C#-swap seam clean. The query helpers (`cell_at`/`in_bounds`/`unit_at`) live on `GameState` so pathfinding never touches a node.
- **`effective_move` is a stub on purpose.** M3 returns `unit["move"]`. M4 extends it with slow/skitter status and weather fly-bonus — the single function is the seam, so reachable/AI inherit the modifiers for free, exactly as the JS reference comments note.
- **Friendly passable vs enemy blocking is the load-bearing rule.** The blocker check skips ONLY enemy-owned tiles; friendly units are walked through but dropped from the final destination set. The `cost 2 through a friendly` vs `enemy excluded` asserts in Task 3 are the proof — if both regress together, the blocker `owner` comparison is inverted.
- **Constructed boards, not JS capture.** Unlike M2's map-gen parity (which needed byte-identical RNG order), pathfinding parity is tested by asserting algorithm PROPERTIES on hand-built boards (cost == hex distance on uniform plain, range gating, flyer-over-water). This is more robust than golden values and needs no JS-side capture run.
- **`_flat_state` uses an un-offset rectangle.** Real maps use the `-floor(r/2)` row offset; the test board doesn't. That's fine: `in_bounds` is a dict lookup, so neighbors that fall outside the rectangle are simply filtered, and the distance/cost properties still hold.
- **No turn machinery in M3.** Units don't set `acted` and there's no end-turn, so the visual test lets you move any unit repeatedly — intentional, to make movement easy to eyeball. The `acted` gate + `endTurn` (MP regen, heals, AI handoff) port in M4.
- **Master name is `"Archon"` (no faction suffix) in M3.** The `" of AZURE/CRIMSON"` suffix needs the players/palette table, which lands with the HUD (M7). Token team color is inlined from `PAL.p0`/`p1` in `units_layer.gd` until then.
- **GDScript `range` as a dict key is fine** — it's a global function name, not a reserved word, so `unit["range"]` and the literal key `"range"` work. Kept to mirror the JS field exactly.
- **Draw order is set by child order**, not z-index: board added first, overlay second, tokens third. If highlights paint over tokens, the `add_child` order in `main._ready` was swapped.
- **`seed: -1` sentinel** in `Maps.MAPS[0]` never triggers — `main.gd` and the tests pass an explicit seed (42), as in M2.

---

## Self-review

- **Spec coverage (port-order item 3 "Units + movement"):** placement → `GameState.new_skirmish` (Task 2); `pathfinding.gd` reachable → Task 3; selection → Task 4 `_on_click`; placeholder unit tokens with team rings → Task 4 `units_layer.gd`. `computeAttackTargets` is ported in Task 3 (query, not resolution) so M4 combat has its target set ready. ✅
- **Deferred with intent:** XP/level/evolve, combat, statuses, weather, turn flow, AI — each noted against its owning milestone. Data fields they need (`evolves_to`/`evolved`/`ability`) are carried now. ✅
- **Type consistency:** `make_unit`/`make_master` signatures (`id` first) match `GameState.spawn_*`; `compute_reachable(state, unit)` / `compute_attack_targets(state, unit, q, r)` / `reconstruct_path(reach, q, r)` signatures match every call site in tests and `main.gd`; unit dict keys (`max_hp`, `is_master`, `type_key`, `range`) are identical across factory, tests, and presentation. ✅
- **No placeholders:** every step ships complete code or an exact command + expected result. ✅
