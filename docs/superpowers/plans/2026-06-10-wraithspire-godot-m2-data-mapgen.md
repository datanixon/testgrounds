# Wraithspire Godot Port — Milestone 2: Data Tables + Deterministic Map Gen — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax.

**Goal:** Port the map-relevant data tables and the deterministic map generator from the JS reference into the Godot `core`/`data` layer, proven by cross-engine parity tests, and render the generated map as placeholder hex tiles on screen.

**Architecture:** Pure logic core (`rng.gd`, `map_gen.gd` — no nodes) + const-dict data (`terrain.gd`, `maps.gd`, `campaign.gd`) + a thin `Board` Node2D that draws colored hex polygons. The PRNG is a **bit-exact port of the JS `mulberry32`**, so fixed seeds reproduce the JS layouts exactly (this supersedes the spec's earlier "use Godot RNG" note — the campaign maps use curated fixed seeds worth preserving).

**Tech Stack:** GDScript, the M1 headless harness (`pwsh -ExecutionPolicy Bypass -File godot/tests/run_tests.ps1`). Reference: `game.js` — TERRAIN (147–155), MAPS (167–183), CAMPAIGN (189–239), generateMap/cellAt/clearAround (241–339), mulberry32 (341–349), PAL terrain colors (62–74).

**Scope note:** M2 ports only the map-relevant data (TERRAIN, MAPS, CAMPAIGN). The combat/ability/status/weather/AI tables port in their owning milestones (M4–M6) alongside their logic — data and the logic that reads it stay together.

---

## File structure (this milestone)

```
godot/core/rng.gd          Mulberry32 PRNG (bit-exact JS port)
godot/core/map_gen.gd      generate(seed, def) -> map dict (faithful generateMap port)
godot/data/terrain.gd      const TERRAIN (gameplay fields + placeholder color)
godot/data/maps.gd         const MAPS (4 skirmish defs)
godot/data/campaign.gd     const CAMPAIGN (4 missions)
godot/scenes/board/board.gd   Board (Node2D): draws hex polygons per terrain color
godot/scenes/main.gd          root: generate a map, show Board + Camera2D
godot/scenes/main.tscn        root scene (main.gd) — set as run/main_scene
godot/tests/run_tests.gd      + _test_rng, _test_data, _test_map_gen, _test_board
godot/project.godot           run/main_scene = res://scenes/main.tscn
ROADMAP_GODOT.md              check off M2
```

---

## Task 1: Mulberry32 RNG (TDD)

**Files:** Create `godot/core/rng.gd`; Modify `godot/tests/run_tests.gd`.

- [ ] **Step 1: Add failing RNG tests to `godot/tests/run_tests.gd`**

Add a preload under the existing `const HexLib = ...` line:
```gdscript
const Rng = preload("res://core/rng.gd")
```
Add a call in `_initialize`, after `_test_hex()`:
```gdscript
	_test_rng()
```
Append:
```gdscript
func _test_rng() -> void:
	# Bit-exact uint32 sequence for seed 12345, captured from the JS reference.
	var r := Rng.new(12345)
	var want := [4207900869, 1317490944, 2079646450, 3513001552, 2187978186]
	for i in range(want.size()):
		_eq(r.next_u32(), want[i], "rng: u32[%d] seed 12345" % i)
	# next() is the uint32 divided by 2^32 (same arithmetic as JS).
	_eq(Rng.new(12345).next(), 4207900869.0 / 4294967296.0, "rng: next() float")
	# below(n) = floor(next()*n); seed 0 first next()=0.2664... -> below(10)=2
	_eq(Rng.new(0).below(10), 2, "rng: below(10) seed 0")
```

- [ ] **Step 2: Run — verify it fails (rng.gd missing)**
```
pwsh -ExecutionPolicy Bypass -File godot/tests/run_tests.ps1; "EXIT=$LASTEXITCODE"
```
Expected: parse/load error about `res://core/rng.gd`, non-zero EXIT.

- [ ] **Step 3: Implement `godot/core/rng.gd`, verbatim:**
```gdscript
class_name Mulberry32
extends RefCounted
## Bit-exact port of the JS reference PRNG (game.js mulberry32). Fixed seeds
## reproduce the JS map layouts exactly. All state/arithmetic is masked to 32
## bits so GDScript's 64-bit ints match JS int32/uint32 bit patterns. (A 32-bit
## product overflows int64, but the low 32 bits after &U32 are still exact.)

const U32 := 0xFFFFFFFF

var _a: int

func _init(seed: int) -> void:
	_a = seed & U32

## Next raw uint32 — matches JS `(t ^ t >>> 14) >>> 0`.
func next_u32() -> int:
	_a = (_a + 0x6D2B79F5) & U32
	var t := _a
	t = _imul(t ^ (t >> 15), t | 1) & U32
	t = (t ^ (t + _imul(t ^ (t >> 7), t | 61))) & U32
	return (t ^ (t >> 14)) & U32

## Next float in [0, 1) — matches JS `... / 4294967296`.
func next() -> float:
	return float(next_u32()) / 4294967296.0

## Integer in [0, n) — matches JS `Math.floor(rng() * n)`.
func below(n: int) -> int:
	return int(floor(next() * n))

# 32-bit low-word multiply, matching JS Math.imul.
static func _imul(x: int, y: int) -> int:
	return (x * y) & U32
```

- [ ] **Step 4: Run — verify pass**
```
pwsh -ExecutionPolicy Bypass -File godot/tests/run_tests.ps1; "EXIT=$LASTEXITCODE"
```
Expected: `== 23 passed, 0 failed ==` (16 prior + 7 rng: 5 u32 + 1 float + 1 below) and `EXIT=0`.

- [ ] **Step 5: Commit**
```
git add godot/core/rng.gd godot/tests/run_tests.gd
git commit -m "[godot] M2: Mulberry32 PRNG (bit-exact JS port)"
```

---

## Task 2: Data tables (terrain, maps, campaign)

Port the three map-relevant tables. Read the exact JS source lines and translate to GDScript const dicts. Castle positions in defs are `Vector2i`. A `null` seed in JS becomes `-1` (sentinel = "roll a random seed at match start"; M2 always passes explicit seeds).

**Files:** Create `godot/data/terrain.gd`, `godot/data/maps.gd`, `godot/data/campaign.gd`; Modify `godot/tests/run_tests.gd`.

- [ ] **Step 1: Create `godot/data/terrain.gd`** — port `game.js` TERRAIN (lines 147–155). Keys: `plain, forest, hill, mountain, water, tower, castle`. Per entry include `name` (String), `move_cost` (int), `def` (int), `blocks` (bool), and where present `flyers_only` (bool, mountain+water), `capturable` (bool, tower). Add a `color` (hex String) per terrain from PAL (lines 62–74): plain `#3a5a3e`, forest `#1f3e25`, hill `#6a5a3a`, mountain `#4a4452`, water `#264a78`, tower `#6a5a72`, castle `#9a8a52`.
```gdscript
class_name Terrain
extends RefCounted

const TERRAIN := {
	"plain":    {"name": "Plain",    "move_cost": 1,  "def": 0, "blocks": false, "color": "#3a5a3e"},
	"forest":   {"name": "Forest",   "move_cost": 2,  "def": 2, "blocks": false, "color": "#1f3e25"},
	"hill":     {"name": "Hill",     "move_cost": 2,  "def": 2, "blocks": false, "color": "#6a5a3a"},
	"mountain": {"name": "Mountain", "move_cost": 4,  "def": 4, "blocks": false, "flyers_only": true, "color": "#4a4452"},
	"water":    {"name": "Tide",     "move_cost": 99, "def": 0, "blocks": true,  "flyers_only": true, "color": "#264a78"},
	"tower":    {"name": "Spire",    "move_cost": 1,  "def": 3, "blocks": false, "capturable": true, "color": "#6a5a72"},
	"castle":   {"name": "Citadel",  "move_cost": 1,  "def": 4, "blocks": false, "color": "#9a8a52"},
}
```

- [ ] **Step 2: Create `godot/data/maps.gd`** — port `game.js` MAPS (lines 167–183). 4 entries; `seed: null` → `-1`; `castles` (crags) as `[Vector2i(0,5), Vector2i(9,5)]`; preserve `weather_table` arrays.
```gdscript
class_name Maps
extends RefCounted

const MAPS := [
	{"key": "frontier", "name": "Wraithspire Frontier", "desc": "The classic borderland.",
	 "cols": 14, "rows": 12, "seed": -1, "mountains": 4, "lakes": 3, "forests": 22, "hills": 14, "towers": 5},
	{"key": "tides", "name": "Shattered Tides", "desc": "Drowned field — flyers rule.",
	 "cols": 14, "rows": 12, "seed": -1, "mountains": 1, "lakes": 8, "forests": 12, "hills": 6, "towers": 5,
	 "weather_table": ["rain", "rain", "clear", "gale"]},
	{"key": "crags", "name": "Emberfall Crags", "desc": "Walls of stone, tight passes.",
	 "cols": 15, "rows": 11, "seed": -1, "mountains": 9, "lakes": 1, "forests": 8, "hills": 22, "towers": 4,
	 "castles": [Vector2i(0, 5), Vector2i(9, 5)],
	 "weather_table": ["heat", "heat", "clear", "gale"]},
	{"key": "verdant", "name": "Verdant Expanse", "desc": "Wide greens, six spires.",
	 "cols": 16, "rows": 13, "seed": -1, "mountains": 2, "lakes": 2, "forests": 30, "hills": 10, "towers": 6},
]
```

- [ ] **Step 3: Create `godot/data/campaign.gd`** — port `game.js` CAMPAIGN (lines 189–239). 4 entries, each `{name, difficulty, map:{...}, ai_mp_bonus, ai_summons:[...], intro:[...]}`. Map sub-defs carry the fixed seeds (7041, 11317, 40923, 86011); c3 has `castles: [Vector2i(0,5), Vector2i(9,5)]`.
```gdscript
class_name Campaign
extends RefCounted

const CAMPAIGN := [
	{"name": "The Border Skirmish", "difficulty": "easy",
	 "map": {"key": "c1", "name": "Border Skirmish", "desc": "", "cols": 11, "rows": 9, "seed": 7041,
	         "mountains": 2, "lakes": 1, "forests": 12, "hills": 8, "towers": 3},
	 "ai_mp_bonus": -6, "ai_summons": [],
	 "intro": ["The old truce is ash. CRIMSON riders burn the", "border farms, and the Azure throne calls you —",
	           "its youngest archon — to answer.", "Drive them from the frontier."]},
	{"name": "The Drowned Marches", "difficulty": "normal",
	 "map": {"key": "c2", "name": "Drowned Marches", "desc": "", "cols": 14, "rows": 12, "seed": 11317,
	         "mountains": 1, "lakes": 8, "forests": 12, "hills": 6, "towers": 5},
	 "ai_mp_bonus": 0, "ai_summons": ["tidekin"],
	 "intro": ["You chased them into the marches, where the", "tide swallows roads whole. CRIMSON's leviathans",
	           "glide where your soldiers drown.", "Take wing, or take the long way around."]},
	{"name": "The Emberfall Passes", "difficulty": "normal",
	 "map": {"key": "c3", "name": "Emberfall Passes", "desc": "", "cols": 15, "rows": 11, "seed": 40923,
	         "mountains": 9, "lakes": 1, "forests": 8, "hills": 22, "towers": 4,
	         "castles": [Vector2i(0, 5), Vector2i(9, 5)]},
	 "ai_mp_bonus": 6, "ai_summons": ["stoneward", "cinderling"],
	 "intro": ["Only the high passes lead to the enemy's seat,", "and CRIMSON knows it. Stoneward garrisons hold",
	           "every defile, fed by the spires you must take.", "The mountains do not forgive haste."]},
	{"name": "The Wraithspire", "difficulty": "hard",
	 "map": {"key": "c4", "name": "The Wraithspire", "desc": "", "cols": 16, "rows": 13, "seed": 86011,
	         "mountains": 4, "lakes": 3, "forests": 24, "hills": 12, "towers": 6},
	 "ai_mp_bonus": 10, "ai_summons": ["geomaul", "skyharrow"],
	 "intro": ["The Wraithspire itself — the first spire, the", "one all others echo. The CRIMSON archon waits",
	           "beneath it with everything he has left.", "Cast him down. Inherit the realm."]},
]
```

- [ ] **Step 4: Add parity tests to `godot/tests/run_tests.gd`**

Add preloads under the others:
```gdscript
const Terrain = preload("res://data/terrain.gd")
const Maps = preload("res://data/maps.gd")
const Campaign = preload("res://data/campaign.gd")
```
Add the call after `_test_rng()`:
```gdscript
	_test_data()
```
Append:
```gdscript
func _test_data() -> void:
	# Terrain
	_eq(Terrain.TERRAIN.size(), 7, "terrain: 7 types")
	_eq(Terrain.TERRAIN["plain"]["move_cost"], 1, "terrain: plain move_cost")
	_eq(Terrain.TERRAIN["mountain"]["flyers_only"], true, "terrain: mountain flyers_only")
	_eq(Terrain.TERRAIN["water"]["blocks"], true, "terrain: water blocks")
	_eq(Terrain.TERRAIN["water"]["move_cost"], 99, "terrain: water move_cost")
	_eq(Terrain.TERRAIN["tower"]["capturable"], true, "terrain: tower capturable")
	_eq(Terrain.TERRAIN["castle"]["def"], 4, "terrain: castle def")
	# Maps
	_eq(Maps.MAPS.size(), 4, "maps: 4 skirmish")
	_eq(Maps.MAPS[0]["key"], "frontier", "maps: [0] key")
	_eq(Maps.MAPS[0]["cols"], 14, "maps: [0] cols")
	_eq(Maps.MAPS[2]["key"], "crags", "maps: [2] key")
	_eq(Maps.MAPS[2]["castles"], [Vector2i(0, 5), Vector2i(9, 5)], "maps: crags castles")
	_eq(Maps.MAPS[2]["weather_table"], ["heat", "heat", "clear", "gale"], "maps: crags weather")
	# Campaign
	_eq(Campaign.CAMPAIGN.size(), 4, "campaign: 4 missions")
	_eq(Campaign.CAMPAIGN[0]["map"]["seed"], 7041, "campaign: c1 seed")
	_eq(Campaign.CAMPAIGN[0]["map"]["cols"], 11, "campaign: c1 cols")
	_eq(Campaign.CAMPAIGN[3]["difficulty"], "hard", "campaign: c4 difficulty")
	_eq(Campaign.CAMPAIGN[3]["map"]["seed"], 86011, "campaign: c4 seed")
```

- [ ] **Step 5: Run — verify pass**
```
pwsh -ExecutionPolicy Bypass -File godot/tests/run_tests.ps1; "EXIT=$LASTEXITCODE"
```
Expected: `== 41 passed, 0 failed ==` (23 prior + 18 data) and `EXIT=0`.

- [ ] **Step 6: Commit**
```
git add godot/data/terrain.gd godot/data/maps.gd godot/data/campaign.gd godot/tests/run_tests.gd
git commit -m "[godot] M2: data tables (terrain, maps, campaign)"
```

---

## Task 3: Deterministic map generator (TDD)

Faithful port of `generateMap` (game.js 241–339). The RNG-consumption ORDER must match the JS exactly, or layouts diverge — the c1 parity test below is the proof.

**Files:** Create `godot/core/map_gen.gd`; Modify `godot/tests/run_tests.gd`.

- [ ] **Step 1: Add failing map-gen tests to `godot/tests/run_tests.gd`**

Add a preload:
```gdscript
const MapGen = preload("res://core/map_gen.gd")
```
Add the call after `_test_data()`:
```gdscript
	_test_map_gen()
```
Append (the expected values are captured from the JS reference `generateMap(7041, c1)`):
```gdscript
func _map_sig(m: Dictionary) -> String:
	var keys := m["cells"].keys()
	keys.sort()
	var parts := PackedStringArray()
	for k in keys:
		var c: Dictionary = m["cells"][k]
		parts.append("%s:%s:%d" % [k, c["terrain"], c["owner"]])
	return "|".join(parts)

func _terrain_counts(m: Dictionary) -> Dictionary:
	var counts := {}
	for k in m["cells"]:
		var t: String = m["cells"][k]["terrain"]
		counts[t] = counts.get(t, 0) + 1
	return counts

func _test_map_gen() -> void:
	var c1: Dictionary = Campaign.CAMPAIGN[0]["map"]
	# Determinism: same seed+def -> identical map.
	_eq(_map_sig(MapGen.generate(7041, c1)), _map_sig(MapGen.generate(7041, c1)), "mapgen: deterministic")
	# Cross-engine parity vs the JS reference for seed 7041 / c1.
	var m := MapGen.generate(7041, c1)
	_eq(m["cells"].size(), 99, "mapgen: c1 cell count")
	_eq(_terrain_counts(m), {"plain": 65, "forest": 12, "hill": 8, "water": 5, "mountain": 4, "castle": 2, "tower": 3}, "mapgen: c1 terrain counts")
	_eq(m["castles"], [Vector2i(0, 1), Vector2i(5, 7)], "mapgen: c1 castles")
	_eq(m["cells"]["0,1"]["owner"], 0, "mapgen: c1 castle A owner")
	_eq(m["cells"]["5,7"]["owner"], 1, "mapgen: c1 castle B owner")
	var towers := m["towers"].duplicate()
	towers.sort_custom(func(a, b): return a.x < b.x or (a.x == b.x and a.y < b.y))
	_eq(towers, [Vector2i(-3, 6), Vector2i(-1, 5), Vector2i(10, 1)], "mapgen: c1 towers")
	# Invariants on a skirmish def: 2 owned castles, tower spacing rules.
	var m2 := MapGen.generate(123, Maps.MAPS[0])
	_eq(m2["castles"].size(), 2, "mapgen: 2 castles")
	for t in m2["towers"]:
		_ok(Hex.distance(t, m2["castles"][0]) >= 3 and Hex.distance(t, m2["castles"][1]) >= 3, "mapgen: tower >=3 from castles")
	for i in range(m2["towers"].size()):
		for j in range(i + 1, m2["towers"].size()):
			_ok(Hex.distance(m2["towers"][i], m2["towers"][j]) >= 2, "mapgen: towers >=2 apart")
```

- [ ] **Step 2: Run — verify it fails (map_gen.gd missing)**
```
pwsh -ExecutionPolicy Bypass -File godot/tests/run_tests.ps1; "EXIT=$LASTEXITCODE"
```
Expected: parse/load error about `res://core/map_gen.gd`, non-zero EXIT.

- [ ] **Step 3: Implement `godot/core/map_gen.gd`, verbatim:**
```gdscript
class_name MapGen
extends RefCounted
## Deterministic map generation — faithful port of generateMap (game.js sec. 3),
## same algorithm AND same Mulberry32 RNG, so fixed seeds reproduce JS layouts
## exactly. Pure: returns a map dict; no globals, no nodes.
## Returned dict:
##   cols, rows: int
##   cells: { "q,r": {q, r, terrain: String, owner: int(-1 none / 0 / 1)} }
##   castles: Array[Vector2i]   (owner is on the cell)
##   towers:  Array[Vector2i]

const Hex = preload("res://core/hex.gd")
const Rng = preload("res://core/rng.gd")

static func generate(seed: int, def: Dictionary) -> Dictionary:
	var rng := Rng.new(seed)
	var cols: int = def["cols"]
	var rows: int = def["rows"]
	var cells := {}
	var order: Array[Vector2i] = []   # JS [...MAP.cells.values()] insertion order
	for r in range(rows):
		var offset := -(r >> 1)        # -floor(r/2)
		for q in range(offset, offset + cols):
			var v := Vector2i(q, r)
			cells[Hex.key(v)] = {"q": q, "r": r, "terrain": "plain", "owner": -1}
			order.append(v)

	# Mountains: random-walk ridges.
	for i in range(def["mountains"]):
		var c: Variant = _pick(cells, order, rng)
		var length := 2 + rng.below(3)
		for j in range(length):
			if c == null:
				break
			c["terrain"] = "mountain"
			var nbrs: Array[Vector2i] = []
			for n in Hex.neighbors(Vector2i(c["q"], c["r"])):
				if cells.has(Hex.key(n)):
					nbrs.append(n)
			c = cells.get(Hex.key(nbrs[rng.below(nbrs.size())])) if nbrs.size() > 0 else null

	# Lakes: plain-neighbor accretion.
	for i in range(def["lakes"]):
		var c: Variant = _pick(cells, order, rng)
		if c == null:
			continue
		var lake: Array = [c]
		while lake.size() < 4 + rng.below(3):
			var base: Dictionary = lake[rng.below(lake.size())]
			var nbrs: Array = []
			for n in Hex.neighbors(Vector2i(base["q"], base["r"])):
				var nc: Variant = cells.get(Hex.key(n))
				if nc != null and nc["terrain"] == "plain" and not lake.has(nc):
					nbrs.append(nc)
			if nbrs.is_empty():
				break
			lake.append(nbrs[rng.below(nbrs.size())])
		for c2 in lake:
			c2["terrain"] = "water"

	_scatter(cells, order, rng, "forest", def["forests"])
	_scatter(cells, order, rng, "hill", def["hills"])

	# Castles: handcrafted override or default opposite corners.
	var castles: Array[Vector2i] = []
	var start_a := Vector2i(0, 1)
	var start_b := Vector2i(cols - 3 - ((rows - 2) >> 1), rows - 2)
	if def.has("castles"):
		start_a = def["castles"][0]
		start_b = def["castles"][1]
	var castle_a: Variant = cells.get(Hex.key(start_a))
	if castle_a == null:
		castle_a = cells.get(Hex.key(Vector2i(1, 1)))
	var castle_b: Variant = cells.get(Hex.key(start_b))
	if castle_a != null:
		_clear_around(cells, castle_a)
		castle_a["terrain"] = "castle"
		castle_a["owner"] = 0
		castles.append(Vector2i(castle_a["q"], castle_a["r"]))
	if castle_b != null:
		_clear_around(cells, castle_b)
		castle_b["terrain"] = "castle"
		castle_b["owner"] = 1
		castles.append(Vector2i(castle_b["q"], castle_b["r"]))

	# Towers: plain cells, >=3 from each castle, >=2 from other towers.
	var towers: Array[Vector2i] = []
	var pa := Vector2i(castle_a["q"], castle_a["r"]) if castle_a != null else Vector2i.ZERO
	var pb := Vector2i(castle_b["q"], castle_b["r"]) if castle_b != null else Vector2i.ZERO
	var placed := 0
	var guard := 0
	while placed < def["towers"] and guard < 500:
		guard += 1
		var c: Variant = _pick(cells, order, rng)
		if c == null or c["terrain"] != "plain":
			continue
		var cp := Vector2i(c["q"], c["r"])
		if Hex.distance(cp, pa) < 3 or Hex.distance(cp, pb) < 3:
			continue
		var too_close := false
		for t in towers:
			if Hex.distance(t, cp) < 2:
				too_close = true
				break
		if too_close:
			continue
		c["terrain"] = "tower"
		c["owner"] = -1
		towers.append(cp)
		placed += 1

	return {"cols": cols, "rows": rows, "cells": cells, "castles": castles, "towers": towers}

static func _pick(cells: Dictionary, order: Array, rng: Rng) -> Variant:
	return cells.get(Hex.key(order[rng.below(order.size())]))

static func _scatter(cells: Dictionary, order: Array, rng: Rng, kind: String, count: int) -> void:
	var guard := 0
	var i := 0
	while i < count and guard < 1000:
		guard += 1
		var c: Dictionary = _pick(cells, order, rng)
		if c["terrain"] != "plain":
			continue
		c["terrain"] = kind
		i += 1

static func _clear_around(cells: Dictionary, c: Dictionary) -> void:
	c["terrain"] = "plain"
	for n in Hex.neighbors(Vector2i(c["q"], c["r"])):
		var nc: Variant = cells.get(Hex.key(n))
		if nc != null and (nc["terrain"] == "mountain" or nc["terrain"] == "water"):
			nc["terrain"] = "plain"
```

- [ ] **Step 4: Run — verify pass (incl. the cross-engine c1 parity)**
```
pwsh -ExecutionPolicy Bypass -File godot/tests/run_tests.ps1; "EXIT=$LASTEXITCODE"
```
Expected: green, `EXIT=0`. The passing `mapgen: c1 terrain counts` / `castles` / `towers` asserts prove the GDScript port consumes the RNG in the same order as the JS reference. If those three fail, the algorithm port has an RNG-order bug (re-check the lake while-condition and neighbor-pick order against `game.js`).

- [ ] **Step 5: Commit**
```
git add godot/core/map_gen.gd godot/tests/run_tests.gd
git commit -m "[godot] M2: deterministic map generator (faithful generateMap port + c1 parity)"
```

---

## Task 4: Placeholder render + first visual + close M2

Render the generated map as colored hex polygons; wire a root scene + camera so `godot godot` shows it. The terrain→color mapping is headless-tested; the on-screen result is confirmed visually.

**Files:** Create `godot/scenes/board/board.gd`, `godot/scenes/main.gd`, `godot/scenes/main.tscn`; Modify `godot/project.godot`, `godot/tests/run_tests.gd`, `ROADMAP_GODOT.md`.

- [ ] **Step 1: Create `godot/scenes/board/board.gd`, verbatim:**
```gdscript
class_name Board
extends Node2D
## Thin presentation: draws each map cell as a hex polygon colored by terrain.
## Color mapping + corner geometry are static so they are headless-testable.

const Hex = preload("res://core/hex.gd")
const Terrain = preload("res://data/terrain.gd")

var map: Dictionary = {}

func set_map(m: Dictionary) -> void:
	map = m
	queue_redraw()

static func terrain_color(terrain: String) -> Color:
	var t: Dictionary = Terrain.TERRAIN.get(terrain, {})
	return Color(t.get("color", "#ff00ff"))

static func hex_corners(center: Vector2) -> PackedVector2Array:
	var pts := PackedVector2Array()
	for i in range(6):
		var ang := deg_to_rad(60.0 * i - 30.0)
		pts.append(center + Vector2(cos(ang), sin(ang)) * Hex.SIZE)
	return pts

func _draw() -> void:
	if map.is_empty():
		return
	for key in map["cells"]:
		var cell: Dictionary = map["cells"][key]
		var center := Hex.axial_to_pixel(Vector2i(cell["q"], cell["r"]))
		var pts := hex_corners(center)
		draw_colored_polygon(pts, terrain_color(cell["terrain"]))
		var outline := pts.duplicate()
		outline.append(pts[0])
		draw_polyline(outline, Color(0, 0, 0, 0.35), 1.0)
```

- [ ] **Step 2: Create `godot/scenes/main.gd`, verbatim:**
```gdscript
extends Node2D
## Root: generate a skirmish map with a fixed seed and show it with a camera.

const MapGen = preload("res://core/map_gen.gd")
const Maps = preload("res://data/maps.gd")
const Hex = preload("res://core/hex.gd")
const BoardScript = preload("res://scenes/board/board.gd")

func _ready() -> void:
	var def: Dictionary = Maps.MAPS[0]
	var m := MapGen.generate(42, def)
	var board: Node2D = BoardScript.new()
	board.set_map(m)
	add_child(board)
	var cam := Camera2D.new()
	cam.position = Hex.axial_to_pixel(Vector2i(def["cols"] / 2, def["rows"] / 2))
	add_child(cam)
	cam.make_current()
```

- [ ] **Step 3: Create `godot/scenes/main.tscn`, verbatim:**
```
[gd_scene load_steps=2 format=3]

[ext_resource type="Script" path="res://scenes/main.gd" id="1"]

[node name="Main" type="Node2D"]
script = ExtResource("1")
```

- [ ] **Step 4: Set the main scene in `godot/project.godot`** — change `run/main_scene=""` to:
```
run/main_scene="res://scenes/main.tscn"
```

- [ ] **Step 5: Add the board color test to `godot/tests/run_tests.gd`**

Add a preload:
```gdscript
const BoardLib = preload("res://scenes/board/board.gd")
```
Add the call after `_test_map_gen()`:
```gdscript
	_test_board()
```
Append:
```gdscript
func _test_board() -> void:
	_eq(BoardLib.terrain_color("plain"), Color("#3a5a3e"), "board: plain color")
	_eq(BoardLib.terrain_color("water"), Color("#264a78"), "board: water color")
	_eq(BoardLib.terrain_color("castle"), Color("#9a8a52"), "board: castle color")
	_eq(BoardLib.hex_corners(Vector2.ZERO).size(), 6, "board: 6 corners")
```

- [ ] **Step 6: Run — verify pass**
```
pwsh -ExecutionPolicy Bypass -File godot/tests/run_tests.ps1; "EXIT=$LASTEXITCODE"
```
Expected: green, `EXIT=0` (4 board asserts added).

- [ ] **Step 7: Visual confirmation (windowed)** — run the project and confirm a hex map of colored tiles appears (greens/browns/blues with darker castle/tower/forest patches):
```
godot --path godot
```
Close the window when confirmed. (This opens a window; it is the manual visual check the spec calls for. A subagent without a display should report this step as "needs user visual confirmation" rather than guess.)

- [ ] **Step 8: Check off M2 in `ROADMAP_GODOT.md`** — change `- [ ] M2 — ...` to `- [x] M2 — ...`.

- [ ] **Step 9: Commit**
```
git add godot/scenes/board/board.gd godot/scenes/main.gd godot/scenes/main.tscn godot/project.godot godot/tests/run_tests.gd ROADMAP_GODOT.md
git commit -m "[godot] M2: placeholder hex render + root scene; close M2"
```

---

## Notes & risk callouts

- **RNG-order fidelity is the whole game in Task 3.** The c1 parity asserts (terrain counts / castles / towers) only pass if every `rng` call happens in the same order as the JS. The fragile spots: the lake `while` condition re-evaluates `4 + rng.below(3)` every iteration (consuming an rng each check — keep it in the condition, do not hoist it); the mountain/lake/tower neighbor picks use `rng.below(nbrs.size())` in JS order.
- **`-(r >> 1)` = `-floor(r/2)`** for `r >= 0` (all rows). Matches the JS `-Math.floor(r/2)`.
- **GDScript Dictionary cells are reference types** — `_pick` returns the actual cell dict, so `c["terrain"] = ...` mutates the stored map. `lake.has(nc)` works because the same dict reference is in both.
- **`seed: -1`** in map defs is the "roll a random seed at match start" sentinel; M2 always passes explicit seeds, so it never triggers here.
- **Board static funcs** (`terrain_color`, `hex_corners`) are tested headless without instantiating the Node; `_draw` is not exercised in tests (it needs a live CanvasItem).
- **Visual step opens a window** — only the user (at the machine) can confirm the look; the controller may also capture a screenshot. Don't block the milestone's logic gate on it.
- **Godot 4 `==` is deep for Array and Dictionary** (by value) — M1 already proved Array deep `==` (the `neighbors == DIRS` assert passed), so the `_terrain_counts(m) == {...}` and `castles`/`weather_table` literal comparisons work. If a future Godot build regresses this, fall back to per-key asserts.
```
