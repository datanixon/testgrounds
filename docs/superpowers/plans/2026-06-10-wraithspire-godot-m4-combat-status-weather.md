# Wraithspire Godot Port — Milestone 4: Combat + Status + Weather (logic + forecast) — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax.

**Goal:** Port the combat resolution math, the status engine, the weather engine, unit leveling/evolution, and the turn machinery from the JS reference into the pure Godot logic core — resolving battles INLINE (no cutaway until M8) — and wire attack / capture / end-turn into the interactive board.

**Architecture:** All rules stay in the node-free pure core. `data/` gains element/status/weather const tables. `core/combat.gd` holds `compute_damage` (pure — deterministic `base`), `forecast_battle`, and `resolve_attack` (inline: jitter via a seeded RNG, ward/counter/XP/death). `core/status.gd` and `core/weather.gd` are stateless helpers operating on a `GameState`. `GameState` gains a runtime RNG, weather state, the active map def, a winner field, and the `end_turn` machinery (MP regen, status tick, heals, evolution, weather roll, win check). Determinism: ALL combat jitter and weather rolls go through `GameState.rng` (a `Mulberry32`), so tests are reproducible.

**Tech Stack:** GDScript, the headless harness (`pwsh -ExecutionPolicy Bypass -File godot/tests/run_tests.ps1`). Reference: `game.js` — ELEMENT/ELEM_MATRIX/AFFINITY (355–390), gainXp/leveling (468–497), evolveUnit/tryEvolve (505–541), computeDamage (965–985), forecastBattle (990–1001), beginBattle swing setup (1005–1017), checkWinCondition (1066–1077), captureTower (1166–1172), applySwing (2360–2386), STATUS_META/addStatus/hasStatus (5586–5612), tickStatuses (5616–5637), WEATHERS/rollWeather/weatherNow (5858–5879), endTurn (4719–4761).

**Scope note:** M4 builds the status ENGINE (add/has/tick) and makes combat READ mark/bulwark/ward/slow/skitter, but the in-game WRITERS of those statuses are the abilities in M5 (basic attacks inflict no status — `resolve_attack` has no status param yet; M5 adds it). This mirrors the JS reference's own "regen has no writer until relics" gap. Battle CUTAWAY visuals are M8 — M4 resolves combat instantly. The full gameover SCREEN is M9 — M4 only sets `GameState.winner` and logs it. AI is M6 — `end_turn` in M4 just flips to the other player so you can drive both sides manually.

---

## File structure (this milestone)

```
godot/data/elements.gd        const ELEMENT, ELEM_MATRIX, AFFINITY_MULT, ELEM_AFFINITY + affinity_for()
godot/data/statuses.gd        const STATUS_META
godot/data/weather.gd         const WEATHERS, DEFAULT_WEATHER_TABLE
godot/core/status.gd          add_status / has_status / tick_statuses (stateless; take a unit or GameState)
godot/core/weather.gd         weather_now(state) / roll_weather(state, initial)
godot/core/combat.gd          compute_damage / forecast_battle / resolve_attack (+ private _jitter/_apply_hit)
godot/core/units.gd           + xp_to_next / apply_level_growth / gain_xp / evolve_unit / try_evolve (MODIFY)
godot/core/game_state.gd      + rng / weather / map_def / winner; end_turn / check_win_condition / capture_tower (MODIFY)
godot/core/pathfinding.gd     effective_move gains status+weather modifiers (MODIFY — signature now takes state)
godot/scenes/main.gd          + click-enemy-in-range -> attack, move-onto-tower -> capture, Enter -> end_turn (MODIFY)
godot/tests/run_tests.gd      + _test_elements, _test_status, _test_weather, _test_leveling, _test_combat,
                              _test_resolve, _test_turn (MODIFY)
ROADMAP_GODOT.md              check off M4
```

**Determinism contract:** `compute_damage` returns a deterministic `base` (no RNG). The ±1 jitter and the weather roll are the ONLY randomness, both drawn from `GameState.rng`. Tests assert on `base` and on seeded-RNG reproducibility, never on a single jittered roll.

---

## Task 1: Element tables (data)

Port the element identity table, the rock-paper-scissors damage matrix, and the element↔terrain affinity table. Add the `affinity_for` helper.

**Files:** Create `godot/data/elements.gd`; Modify `godot/tests/run_tests.gd`.

- [ ] **Step 1: Add failing element tests to `godot/tests/run_tests.gd`**

Add a preload under the existing data preloads (after `const Campaign = ...`):
```gdscript
const Elements = preload("res://data/elements.gd")
```
Add the call in `_initialize`, after `_test_pathfinding()`:
```gdscript
	_test_elements()
```
Append:
```gdscript
func _test_elements() -> void:
	_eq(Elements.ELEMENT.size(), 5, "elements: 5 elements")
	_eq(Elements.ELEMENT["pyro"]["short"], "PYR", "elements: pyro short")
	# Matrix: pyro strong vs zephyr (1.3), weak vs hydro (0.7), neutral vs self (1.0).
	_eq(Elements.ELEM_MATRIX["pyro"]["zephyr"], 1.3, "elements: pyro>zephyr")
	_eq(Elements.ELEM_MATRIX["pyro"]["hydro"], 0.7, "elements: pyro<hydro")
	_eq(Elements.ELEM_MATRIX["pyro"]["pyro"], 1.0, "elements: pyro=pyro")
	_eq(Elements.ELEM_MATRIX["arcane"]["pyro"], 1.1, "elements: arcane>all 1.1")
	_eq(Elements.ELEM_MATRIX["arcane"]["arcane"], 1.0, "elements: arcane=arcane")
	# Every element has a row and column against every element.
	for a in Elements.ELEMENT:
		_eq(Elements.ELEM_MATRIX[a].size(), 5, "elements: %s full row" % a)
	# Affinity
	_eq(Elements.AFFINITY_MULT, 1.2, "elements: affinity mult")
	_ok(Elements.affinity_for("pyro", "hill") != null, "elements: pyro empowered on hill")
	_eq(Elements.affinity_for("pyro", "water"), null, "elements: pyro not on water")
	_ok(Elements.affinity_for("arcane", "tower") != null, "elements: arcane on tower")
```

- [ ] **Step 2: Run — verify it fails (elements.gd missing)**
```
pwsh -ExecutionPolicy Bypass -File godot/tests/run_tests.ps1; "EXIT=$LASTEXITCODE"
```
Expected: parse/load error about `res://data/elements.gd`, non-zero EXIT.

- [ ] **Step 3: Create `godot/data/elements.gd`, verbatim** (port of `game.js` 355–386):
```gdscript
class_name Elements
extends RefCounted
## Faithful port of game.js ELEMENT / ELEM_MATRIX / AFFINITY (sec. 4). Balance-
## locked. ELEM_MATRIX[attacker][defender] is the damage multiplier; arcane is the
## flat 1.1 "anti-everything" row. Affinity: attacking FROM an empowering terrain
## adds AFFINITY_MULT (+20%).

const ELEMENT := {
	"pyro":   {"name": "Pyro",   "color": "#e07050", "short": "PYR"},
	"hydro":  {"name": "Hydro",  "color": "#5aa8d8", "short": "HYD"},
	"terra":  {"name": "Terra",  "color": "#9a7a4a", "short": "TER"},
	"zephyr": {"name": "Zephyr", "color": "#c8c8d8", "short": "ZEP"},
	"arcane": {"name": "Arcane", "color": "#b078c8", "short": "ARC"},
}

const ELEM_MATRIX := {
	"pyro":   {"pyro": 1.0, "hydro": 0.7, "terra": 1.0, "zephyr": 1.3, "arcane": 1.0},
	"hydro":  {"pyro": 1.3, "hydro": 1.0, "terra": 0.7, "zephyr": 1.0, "arcane": 1.0},
	"terra":  {"pyro": 1.0, "hydro": 1.3, "terra": 1.0, "zephyr": 0.7, "arcane": 1.0},
	"zephyr": {"pyro": 0.7, "hydro": 1.0, "terra": 1.3, "zephyr": 1.0, "arcane": 1.0},
	"arcane": {"pyro": 1.1, "hydro": 1.1, "terra": 1.1, "zephyr": 1.1, "arcane": 1.0},
}

const AFFINITY_MULT := 1.2

const ELEM_AFFINITY := {
	"pyro":   {"terrains": ["hill", "mountain"], "label": "scorching heights"},
	"hydro":  {"terrains": ["water", "forest"],  "label": "drenched ground"},
	"terra":  {"terrains": ["mountain", "hill"], "label": "raw bedrock"},
	"zephyr": {"terrains": ["plain", "mountain"], "label": "open skies"},
	"arcane": {"terrains": ["tower", "castle"],  "label": "ley nexus"},
}

## Returns the affinity record if `element` is empowered on `terrain`, else null.
static func affinity_for(element: String, terrain: String) -> Variant:
	var a: Dictionary = ELEM_AFFINITY.get(element, {})
	if a.is_empty():
		return null
	return a if a["terrains"].has(terrain) else null
```

- [ ] **Step 4: Run — verify pass**
```
pwsh -ExecutionPolicy Bypass -File godot/tests/run_tests.ps1; "EXIT=$LASTEXITCODE"
```
Expected: green, `EXIT=0` (~17 new asserts). Baseline 139; `0 failed` is the gate.

- [ ] **Step 5: Commit**
```
git add godot/data/elements.gd godot/tests/run_tests.gd
git commit -m "[godot] M4: element tables (ELEMENT + ELEM_MATRIX + affinity)"
```

---

## Task 2: Status engine (data + logic)

Port `STATUS_META` (data) and the status engine: `add_status` / `has_status` / `tick_statuses`. Statuses live on `unit["status"]` as `{key: turns_remaining}` (the dict is created lazily). `tick_statuses` applies burn (-3 HP), regen (+2 HP capped), then decrements every status and removes expired ones. **No in-game writers yet** — abilities (M5) write statuses; M4 ships the engine + tests.

**Files:** Create `godot/data/statuses.gd`, `godot/core/status.gd`; Modify `godot/tests/run_tests.gd`.

- [ ] **Step 1: Add failing status tests to `godot/tests/run_tests.gd`**

Add preloads:
```gdscript
const Statuses = preload("res://data/statuses.gd")
const Status = preload("res://core/status.gd")
```
Add the call after `_test_elements()`:
```gdscript
	_test_status()
```
Append:
```gdscript
func _test_status() -> void:
	_eq(Statuses.STATUS_META.size(), 7, "status: 7 meta entries")
	_eq(Statuses.STATUS_META["burn"]["label"], "burning", "status: burn label")
	# add/has
	var u := {"hp": 20, "max_hp": 20, "owner": 0, "q": 0, "r": 0}
	_ok(not Status.has_status(u, "slow"), "status: none initially")
	Status.add_status(u, "slow", 2)
	_ok(Status.has_status(u, "slow"), "status: slow added")
	# add_status keeps the MAX of existing vs new turns (never shortens)
	Status.add_status(u, "slow", 1)
	_eq(u["status"]["slow"], 2, "status: add keeps max turns")
	# tick: burn deals 3, regen heals 2, all statuses decrement, expired drop
	var gs := _flat_state(5, 5)
	var b := gs.spawn_unit("stoneward", 0, 1, 1)   # hp 22
	Status.add_status(b, "burn", 2)
	Status.add_status(b, "regen", 1)
	Status.tick_statuses(gs, 0)
	_eq(b["hp"], 22 - 3 + 2, "status: burn -3 then regen +2")   # 21
	_eq(b["status"]["burn"], 1, "status: burn decremented")
	_ok(not Status.has_status(b, "regen"), "status: regen expired (1->0 dropped)")
	# burn can kill (hp floored at 0)
	var c := gs.spawn_unit("galewisp", 0, 2, 2)   # hp 10
	c["hp"] = 2
	Status.add_status(c, "burn", 1)
	Status.tick_statuses(gs, 0)
	_eq(c["hp"], 0, "status: burn floors at 0 (kill)")
```

- [ ] **Step 2: Run — verify it fails**
```
pwsh -ExecutionPolicy Bypass -File godot/tests/run_tests.ps1; "EXIT=$LASTEXITCODE"
```
Expected: load error about `res://data/statuses.gd` or `res://core/status.gd`, non-zero EXIT.

- [ ] **Step 3: Create `godot/data/statuses.gd`, verbatim** (port of `game.js` 5586–5594):
```gdscript
class_name Statuses
extends RefCounted
## Port of game.js STATUS_META (sec. 16). Presentation metadata for the 7 statuses;
## the engine (core/status.gd) reads only the keys. Writers are the M5 abilities.

const STATUS_META := {
	"burn":         {"color": "#e07050", "label": "burning"},
	"slow":         {"color": "#5aa8d8", "label": "slowed"},
	"regen":        {"color": "#7ac075", "label": "regenerating"},
	"bulwark":      {"color": "#f0c674", "label": "bulwark +2 DEF"},
	"ward":         {"color": "#b078c8", "label": "warded"},
	"mark":         {"color": "#ff8888", "label": "marked +20% dmg taken"},
	"skitterBoost": {"color": "#c8c8d8", "label": "skittering"},
}
```

- [ ] **Step 4: Create `godot/core/status.gd`, verbatim** (port of `game.js` 5596–5637):
```gdscript
class_name Status
extends RefCounted
## Status engine — port of game.js addStatus/hasStatus/tickStatuses (sec. 16).
## Statuses live on unit["status"] = {key: turns_left}; the dict is created lazily.
## Stateless: operates on the unit dict (or a GameState for the per-turn tick).

## addStatus — set `key` to max(existing, turns); never shortens an active status.
static func add_status(unit: Dictionary, key: String, turns: int) -> void:
	if not unit.has("status"):
		unit["status"] = {}
	unit["status"][key] = maxi(unit["status"].get(key, 0), turns)

## hasStatus — true if `key` is present with > 0 turns.
static func has_status(unit: Dictionary, key: String) -> bool:
	return unit.has("status") and unit["status"].get(key, 0) > 0

## tickStatuses — start-of-turn tick for `owner`'s living units: burn -3 (floored
## at 0, can kill), regen +2 (capped at max_hp), then decrement all and drop expired.
## Pure logic — no floats/logs (those are presentation, added at the HUD/battle layer).
static func tick_statuses(state, owner: int) -> void:
	for u in state.alive_units(owner):
		if not u.has("status"):
			continue
		if u["status"].get("burn", 0) > 0:
			u["hp"] = maxi(0, u["hp"] - 3)
		if u["status"].get("regen", 0) > 0 and u["hp"] > 0 and u["hp"] < u["max_hp"]:
			u["hp"] += mini(2, u["max_hp"] - u["hp"])
		for k in u["status"].keys():
			u["status"][k] -= 1
			if u["status"][k] <= 0:
				u["status"].erase(k)
	state.check_win_condition()
```

NOTE: `tick_statuses` calls `state.check_win_condition()` — that method is added in Task 7. Until then this test path doesn't trigger a win (no master dies in the Task 2 tests), but the call must resolve. To keep Task 2 self-contained and green BEFORE Task 7, add a minimal stub now and flesh it out in Task 7. In `godot/core/game_state.gd`, add this stub method (Task 7 replaces the body):
```gdscript
## check_win_condition — set winner if a master is dead. Full body in Task 7.
func check_win_condition() -> void:
	pass
```

- [ ] **Step 5: Run — verify pass**
```
pwsh -ExecutionPolicy Bypass -File godot/tests/run_tests.ps1; "EXIT=$LASTEXITCODE"
```
Expected: green, `EXIT=0` (~10 new asserts). `0 failed` is the gate.

- [ ] **Step 6: Commit**
```
git add godot/data/statuses.gd godot/core/status.gd godot/core/game_state.gd godot/tests/run_tests.gd
git commit -m "[godot] M4: status engine (STATUS_META + add/has/tick)"
```

---

## Task 3: Weather engine (data + logic) + GameState runtime fields

Port `WEATHERS` (data) and the weather engine: `weather_now(state)` / `roll_weather(state, initial)`. Add the runtime fields `GameState` needs for combat and weather: `rng` (a `Mulberry32` seeded at match start — the runtime randomness stream, separate from map-gen's), `weather` (`{key, turns_left}`), `map_def` (the active def, for its `weather_table`). Initialize them in `new_skirmish`.

**RNG-order fidelity:** `roll_weather` mirrors the JS draw order exactly — on `initial`, the key is `"clear"` WITHOUT drawing from the table (no RNG), then `turns_left = 4 + rng.below(3)` ALWAYS draws one. Non-initial draws the table index first, then `turns_left`. Preserve this or seeded reproductions diverge.

**Files:** Create `godot/data/weather.gd`, `godot/core/weather.gd`; Modify `godot/core/game_state.gd`, `godot/tests/run_tests.gd`.

- [ ] **Step 1: Add failing weather tests to `godot/tests/run_tests.gd`**

Add preloads:
```gdscript
const WeatherData = preload("res://data/weather.gd")
const Weather = preload("res://core/weather.gd")
```
Add the call after `_test_status()`:
```gdscript
	_test_weather()
```
Append:
```gdscript
func _test_weather() -> void:
	_eq(WeatherData.WEATHERS.size(), 4, "weather: 4 types")
	_eq(WeatherData.WEATHERS["rain"]["atk_mul"]["hydro"], 1.15, "weather: rain boosts hydro")
	_eq(WeatherData.WEATHERS["gale"]["ranged_mul"], 0.8, "weather: gale dampens ranged")
	_eq(WeatherData.WEATHERS["gale"]["fly_bonus"], 1, "weather: gale fly bonus")
	# weather_now defaults to clear when unset.
	var bare := GameState.new()
	_eq(Weather.weather_now(bare)["name"], "Clear", "weather: defaults to clear")
	# new_skirmish initialises weather to clear (initial roll).
	var gs := GameState.new_skirmish(Maps.MAPS[0], 42)
	_eq(gs.weather["key"], "clear", "weather: match starts clear")
	_ok(gs.weather["turns_left"] >= 4 and gs.weather["turns_left"] <= 6, "weather: turns_left 4..6")
	# roll_weather determinism: same seed -> same roll. crags has a custom table.
	var crags: Dictionary = Maps.MAPS[2]
	var a := GameState.new_skirmish(crags, 99)
	var b := GameState.new_skirmish(crags, 99)
	Weather.roll_weather(a, false)
	Weather.roll_weather(b, false)
	_eq(a.weather["key"], b.weather["key"], "weather: roll deterministic (key)")
	_eq(a.weather["turns_left"], b.weather["turns_left"], "weather: roll deterministic (turns)")
	_ok(crags["weather_table"].has(a.weather["key"]), "weather: rolled key from map table")
```

- [ ] **Step 2: Run — verify it fails**
```
pwsh -ExecutionPolicy Bypass -File godot/tests/run_tests.ps1; "EXIT=$LASTEXITCODE"
```
Expected: load error about `res://data/weather.gd` (or `core/weather.gd`, or `gs.weather` missing), non-zero EXIT.

- [ ] **Step 3: Create `godot/data/weather.gd`, verbatim** (port of `game.js` 5858–5864):
```gdscript
class_name WeatherData
extends RefCounted
## Port of game.js WEATHERS + DEFAULT_WEATHER_TABLE (sec. 19). One global modifier,
## re-rolled ~every 5 turns from the map's table. Read inside combat (atk_mul,
## ranged_mul) and movement (fly_bonus) so forecast and AI inherit it for free.

const WEATHERS := {
	"clear": {"name": "Clear",    "color": "#8a85a2"},
	"rain":  {"name": "Rain",     "color": "#5aa8d8", "atk_mul": {"hydro": 1.15, "pyro": 0.85}},
	"heat":  {"name": "Heatwave", "color": "#e07050", "atk_mul": {"pyro": 1.15, "hydro": 0.85}},
	"gale":  {"name": "Gale",     "color": "#c8c8d8", "ranged_mul": 0.8, "fly_bonus": 1},
}

const DEFAULT_WEATHER_TABLE := ["clear", "clear", "rain", "heat", "gale"]
```

- [ ] **Step 4: Create `godot/core/weather.gd`, verbatim** (port of `game.js` 5866–5879):
```gdscript
class_name Weather
extends RefCounted
## Weather engine — port of game.js rollWeather/weatherNow (sec. 19). Stateless;
## reads/writes state.weather, draws from state.rng. The JS banner/log are dropped
## (presentation, added at the HUD layer in M7).

const WeatherData = preload("res://data/weather.gd")

## weatherNow — the active weather record, defaulting to Clear when unset.
static func weather_now(state) -> Dictionary:
	var key: String = state.weather.get("key", "clear")
	return WeatherData.WEATHERS.get(key, WeatherData.WEATHERS["clear"])

## rollWeather — pick the next weather. `initial` forces "clear" (no table draw);
## turns_left always draws once. Draw ORDER matches the JS reference exactly.
static func roll_weather(state, initial: bool) -> void:
	var table: Array = state.map_def.get("weather_table", WeatherData.DEFAULT_WEATHER_TABLE)
	var key: String = "clear" if initial else table[state.rng.below(table.size())]
	state.weather = {"key": key, "turns_left": 4 + state.rng.below(3)}
```

- [ ] **Step 5: Add the runtime fields to `godot/core/game_state.gd`**

Add a preload near the top (with the existing `const Units`/`const MapGen`):
```gdscript
const Rng = preload("res://core/rng.gd")
const Weather = preload("res://core/weather.gd")
```
Add these vars (with the existing `var map` / `var units` block):
```gdscript
var rng: Mulberry32           # runtime RNG (combat jitter + weather); separate from map-gen
var weather: Dictionary = {}  # {key, turns_left}
var map_def: Dictionary = {}  # the active map def (for its weather_table)
var winner: int = -1          # -1 none; else the winning owner
```
In `new_skirmish`, after `gs.map = MapGen.generate(seed, def)`, add:
```gdscript
	gs.map_def = def
	gs.rng = Rng.new(seed)
	Weather.roll_weather(gs, true)
```

- [ ] **Step 6: Run — verify pass**
```
pwsh -ExecutionPolicy Bypass -File godot/tests/run_tests.ps1; "EXIT=$LASTEXITCODE"
```
Expected: green, `EXIT=0` (~10 new asserts). `0 failed` is the gate. The M3 pathfinding tests use `_flat_state` (a `GameState` with no `rng`/`weather`/`map_def` set) — those still pass because `weather_now` defaults to clear on an empty `weather` dict and nothing in M3's tests draws from `rng`.

- [ ] **Step 7: Commit**
```
git add godot/data/weather.gd godot/core/weather.gd godot/core/game_state.gd godot/tests/run_tests.gd
git commit -m "[godot] M4: weather engine (WEATHERS + roll/now) + GameState runtime rng/weather"
```

---

## Task 4: Leveling + evolution (extend units.gd)

Port the XP curve, level growth, multi-level XP award, and evolution into `core/units.gd` (it already owns unit records and preloads `UnitTypes`). Combat (Task 6) awards XP; the turn loop (Task 7) triggers evolution.

**Files:** Modify `godot/core/units.gd`, `godot/tests/run_tests.gd`.

- [ ] **Step 1: Add failing leveling tests to `godot/tests/run_tests.gd`**

Add the call after `_test_weather()`:
```gdscript
	_test_leveling()
```
Append:
```gdscript
func _test_leveling() -> void:
	# XP curve: 12, 20, 28, 36 to advance FROM levels 1..4; huge at max.
	_eq(Units.xp_to_next(1), 12, "level: xp_to_next(1)")
	_eq(Units.xp_to_next(2), 20, "level: xp_to_next(2)")
	_eq(Units.xp_to_next(4), 36, "level: xp_to_next(4)")
	_ok(Units.xp_to_next(5) > 100000, "level: max level no advance")
	# gain_xp: a single level-up bumps stats and full-heals.
	var u := Units.make_unit(1, "cinderling", 0, 0, 0)  # hp 12, power 5, def 1
	u["hp"] = 3
	var gained := Units.gain_xp(u, 12)
	_eq(gained, 1, "level: gained one level")
	_eq(u["level"], 2, "level: now level 2")
	_eq(u["max_hp"], 16, "level: +4 max_hp")        # 12 + 4
	_eq(u["power"], 6, "level: +1 power")
	_eq(u["def"], 2, "level: +1 def")
	_eq(u["hp"], 16, "level: full heal on level up")
	# multi-level in one award; xp carries the remainder.
	var v := Units.make_unit(2, "cinderling", 0, 0, 0)
	var g2 := Units.gain_xp(v, 12 + 20 + 5)   # level 1->3, 5 xp into level 3
	_eq(g2, 2, "level: two levels at once")
	_eq(v["level"], 3, "level: reached level 3")
	_eq(v["xp"], 5, "level: remainder xp carried")
	# master grows +6 max_hp per level.
	var m := Units.make_master(3, 0, 0, 0)   # max_hp 40
	Units.gain_xp(m, 12)
	_eq(m["max_hp"], 46, "level: master +6 max_hp")
	# evolution: a level-4 cinderling on an owned tower -> infernite, absorbing growth.
	var e := Units.make_unit(4, "cinderling", 0, 0, 0)
	Units.gain_xp(e, 12 + 20 + 28)   # level 1->4 (lvlBonus 3)
	_eq(e["level"], 4, "level: at evolve level")
	var tower_cell := {"terrain": "tower", "owner": 0}
	_ok(Units.try_evolve(e, tower_cell), "evolve: fires on owned tower at L4")
	_eq(e["type_key"], "infernite", "evolve: became infernite")
	_eq(e["evolved"], true, "evolve: evolved flag")
	# infernite base max_hp 22 + lvlBonus(3)*4 = 34; power 9 + 3 = 12; def 3 + 3 = 6.
	_eq(e["max_hp"], 22 + 3 * 4, "evolve: absorbs level max_hp")
	_eq(e["power"], 9 + 3, "evolve: absorbs level power")
	_eq(e["hp"], e["max_hp"], "evolve: full restore")
	# gating: not at level, not owned, wrong terrain, already evolved.
	var low := Units.make_unit(5, "cinderling", 0, 0, 0)  # level 1
	_ok(not Units.try_evolve(low, tower_cell), "evolve: blocked below level 4")
	_ok(not Units.try_evolve(e, tower_cell), "evolve: blocked when already evolved")
```

- [ ] **Step 2: Run — verify it fails (functions missing)**
```
pwsh -ExecutionPolicy Bypass -File godot/tests/run_tests.ps1; "EXIT=$LASTEXITCODE"
```
Expected: error about `Units.xp_to_next` (or similar) not found, non-zero EXIT.

- [ ] **Step 3: Append to `godot/core/units.gd`, verbatim** (port of `game.js` 468–541). Add these constants and static functions at the END of the file:
```gdscript

# ---- XP, leveling, evolution (port of game.js sec. 4 cont.) ----
const MAX_LEVEL := 5
const KILL_XP_BONUS := 10
const EVOLVE_LEVEL := 4

## XP required to advance FROM `level` (12, 20, 28, 36); effectively infinite at max.
static func xp_to_next(level: int) -> int:
	return 1_000_000_000 if level >= MAX_LEVEL else 12 + (level - 1) * 8

## One level-up: bump maxHp/power/def and full-restore HP (classic MoM behaviour).
static func apply_level_growth(unit: Dictionary) -> void:
	unit["max_hp"] += 6 if unit["is_master"] else 4
	unit["power"] += 1
	unit["def"] += 1
	unit["hp"] = unit["max_hp"]

## Award XP, resolving multi-level-ups. Returns levels gained this call.
static func gain_xp(unit: Dictionary, amount: int) -> int:
	if unit == null:
		return 0
	if amount <= 0 or unit["level"] >= MAX_LEVEL:
		return 0
	unit["xp"] += amount
	var gained := 0
	while unit["level"] < MAX_LEVEL and unit["xp"] >= xp_to_next(unit["level"]):
		unit["xp"] -= xp_to_next(unit["level"])
		unit["level"] += 1
		apply_level_growth(unit)
		gained += 1
	if unit["level"] >= MAX_LEVEL:
		unit["xp"] = 0
	return gained

## Evolve a unit into its terminal form, absorbing accumulated level growth.
static func evolve_unit(unit: Dictionary) -> bool:
	var base: Dictionary = UnitTypes.UNIT_TYPES.get(unit["type_key"], {})
	if base.is_empty() or not base.has("evolves_to"):
		return false
	var evo: Dictionary = UnitTypes.UNIT_TYPES.get(base["evolves_to"], {})
	if evo.is_empty():
		return false
	var lvl_bonus: int = unit["level"] - 1
	unit["type_key"] = base["evolves_to"]
	unit["name"] = evo["name"]
	unit["element"] = evo["element"]
	unit["move"] = evo["move"]
	unit["range"] = evo["range"]
	unit["flying"] = evo["flying"]
	unit["sprite"] = evo["sprite"]
	unit["attack"] = evo["attack"]
	unit["max_hp"] = evo["max_hp"] + lvl_bonus * 4
	unit["power"] = evo["power"] + lvl_bonus
	unit["def"] = evo["def"] + lvl_bonus
	unit["hp"] = unit["max_hp"]
	unit["evolved"] = true
	return true

## Try to evolve `unit` standing on `cell`: level 4+, not master, not already
## evolved, on an OWNED tower/castle, and has an evolution path. Returns success.
static func try_evolve(unit: Dictionary, cell: Variant) -> bool:
	if unit["is_master"] or unit.get("evolved", false):
		return false
	if unit["level"] < EVOLVE_LEVEL:
		return false
	if cell == null or cell["owner"] != unit["owner"]:
		return false
	if cell["terrain"] != "tower" and cell["terrain"] != "castle":
		return false
	if not UnitTypes.UNIT_TYPES.get(unit["type_key"], {}).has("evolves_to"):
		return false
	return evolve_unit(unit)
```

NOTE: a freshly made unit from `make_unit` has no `evolved` key; `unit.get("evolved", false)` handles that. `evolve_unit` sets `evolved = true`. Master records have `is_master = true`.

- [ ] **Step 4: Run — verify pass**
```
pwsh -ExecutionPolicy Bypass -File godot/tests/run_tests.ps1; "EXIT=$LASTEXITCODE"
```
Expected: green, `EXIT=0` (~19 new asserts). `0 failed` is the gate.

- [ ] **Step 5: Commit**
```
git add godot/core/units.gd godot/tests/run_tests.gd
git commit -m "[godot] M4: unit leveling + evolution (xp curve, growth, evolve)"
```

---

## Task 5: Damage math + forecast (compute_damage / forecast_battle)

Port `computeDamage` and `forecastBattle` into a new `core/combat.gd`. `compute_damage` is PURE and DETERMINISTIC — it returns `base` (no jitter); the ±1 roll is applied later in `resolve_attack` (Task 6). It reads terrain defense, the element matrix, affinity, mark/bulwark statuses, and the weather multiplier off the `GameState`.

**Files:** Create `godot/core/combat.gd`; Modify `godot/tests/run_tests.gd`.

- [ ] **Step 1: Add failing combat-math tests to `godot/tests/run_tests.gd`**

Add a preload:
```gdscript
const Combat = preload("res://core/combat.gd")
```
Add the call after `_test_leveling()`:
```gdscript
	_test_combat()
```
Append (a helper that builds a known plain board with two units, then asserts on the deterministic `base`):
```gdscript
func _combat_state() -> GameState:
	var gs := _flat_state(7, 7)
	gs.map_def = {}            # default weather table; weather stays clear
	gs.weather = {"key": "clear", "turns_left": 5}
	return gs

func _test_combat() -> void:
	# cinderling (pyro, power 5, hp 12/12) vs galewisp (zephyr, def 1). pyro>zephyr 1.3.
	# raw = 5 * (12/12*0.5+0.5) = 5; mit = def1 + 0 + plainDef0*0.5 = 1.
	# base = max(1, round(5 * 1.3 * 1.0(aff) * 1.0(mark) * 1.0(weather) - 1*0.6))
	#      = round(6.5 - 0.6) = round(5.9) = 6.
	var gs := _combat_state()
	var atk := gs.spawn_unit("cinderling", 0, 2, 3)   # pyro
	var dfn := gs.spawn_unit("galewisp", 1, 3, 3)      # zephyr, def 1
	var r := Combat.compute_damage(gs, atk, dfn)
	_eq(r["elem_mul"], 1.3, "combat: pyro>zephyr mult")
	_eq(r["base"], 6, "combat: base damage on plain")
	# wounded attacker scales down: hp 6/12 -> raw = 5*(0.25+0.5)=3.75.
	atk["hp"] = 6
	# base = max(1, round(3.75 * 1.3 - 0.6)) = round(4.875 - 0.6) = round(4.275) = 4.
	_eq(Combat.compute_damage(gs, atk, dfn)["base"], 4, "combat: wounded scales damage")
	atk["hp"] = 12
	# mark on defender -> *1.2 ; bulwark -> +2 mitigation.
	Status.add_status(dfn, "mark", 2)
	# base = round(5*1.3*1.2 - 0.6) = round(7.8 - 0.6) = round(7.2) = 7.
	_eq(Combat.compute_damage(gs, atk, dfn)["base"], 7, "combat: mark amplifies")
	dfn["status"].erase("mark")
	Status.add_status(dfn, "bulwark", 2)
	# mit = 1 + 2 = 3; base = round(6.5 - 3*0.6) = round(6.5 - 1.8) = round(4.7) = 5.
	_eq(Combat.compute_damage(gs, atk, dfn)["base"], 5, "combat: bulwark mitigates")
	dfn["status"].erase("bulwark")
	# weather: heat boosts pyro 1.15. base = round(5*1.3*1.15 - 0.6) = round(7.475-0.6)=round(6.875)=7.
	gs.weather = {"key": "heat", "turns_left": 5}
	_eq(Combat.compute_damage(gs, atk, dfn)["base"], 7, "combat: heat boosts pyro")
	gs.weather = {"key": "clear", "turns_left": 5}
	# affinity: pyro attacking FROM a hill -> +20%. Put attacker on a hill tile.
	gs.cell_at(2, 3)["terrain"] = "hill"
	var rh := Combat.compute_damage(gs, atk, dfn)
	_ok(rh["has_affinity"], "combat: pyro has hill affinity")
	# base = round(5*1.3*1.2(aff) - mit). mit = def1 + hillDef2*0.5 = 1 + 1 = 2.
	#      = round(7.8 - 1.2) = round(6.6) = 7.
	_eq(rh["base"], 7, "combat: affinity + terrain def")
	gs.cell_at(2, 3)["terrain"] = "plain"
	# forecast: lo/hi straddle base, counter detected when defender in range.
	var f := Combat.forecast_battle(gs, atk, dfn)
	_eq(f["lo"], 5, "forecast: lo = base-1")
	_eq(f["hi"], 7, "forecast: hi = base+1")
	_ok(f["can_counter"], "forecast: adjacent ranged defender counters")  # galewisp range 2, dist 1
	# sure_kill when defender hp <= base-1.
	dfn["hp"] = 3
	_ok(Combat.forecast_battle(gs, atk, dfn)["sure_kill"], "forecast: sure kill flagged")
```

- [ ] **Step 2: Run — verify it fails (combat.gd missing)**
```
pwsh -ExecutionPolicy Bypass -File godot/tests/run_tests.ps1; "EXIT=$LASTEXITCODE"
```
Expected: load error about `res://core/combat.gd`, non-zero EXIT.

- [ ] **Step 3: Create `godot/core/combat.gd`, verbatim** (port of `game.js` 965–1001). `resolve_attack` is added in Task 6:
```gdscript
class_name Combat
extends RefCounted
## Combat math — port of game.js computeDamage/forecastBattle (sec. 7). compute_damage
## is PURE and DETERMINISTIC (returns `base`, no jitter), so forecast and AI reuse it.
## The ±1 jitter lives in resolve_attack (Task 6), drawn from state.rng. Reads terrain
## defense, the element matrix, affinity, mark/bulwark statuses, and weather.

const Elements = preload("res://data/elements.gd")
const Terrain = preload("res://data/terrain.gd")
const Status = preload("res://core/status.gd")
const Weather = preload("res://core/weather.gd")

## computeDamage — the deterministic `base` swing of `attacker` vs `defender`, plus
## the multiplier breakdown the forecast/UI need. No RNG.
static func compute_damage(state, attacker: Dictionary, defender: Dictionary) -> Dictionary:
	var a_cell: Dictionary = state.cell_at(attacker["q"], attacker["r"])
	var d_cell: Dictionary = state.cell_at(defender["q"], defender["r"])
	var d_terrain_def: int = Terrain.TERRAIN[d_cell["terrain"]]["def"]
	var elem_mul: float = Elements.ELEM_MATRIX[attacker["element"]][defender["element"]]
	var aff: Variant = Elements.affinity_for(attacker["element"], a_cell["terrain"])
	var aff_mul: float = Elements.AFFINITY_MULT if aff != null else 1.0
	var mark_mul: float = 1.2 if Status.has_status(defender, "mark") else 1.0
	var bulwark_def: int = 2 if Status.has_status(defender, "bulwark") else 0
	var w: Dictionary = Weather.weather_now(state)
	var w_atk: float = w.get("atk_mul", {}).get(attacker["element"], 1.0)
	var w_ranged: float = w["ranged_mul"] if (w.has("ranged_mul") and attacker["range"] >= 2) else 1.0
	var w_mul: float = w_atk * w_ranged
	var raw: float = attacker["power"] * (float(attacker["hp"]) / float(attacker["max_hp"]) * 0.5 + 0.5)
	var mit: float = defender["def"] + bulwark_def + d_terrain_def * 0.5
	var base: int = maxi(1, roundi(raw * elem_mul * aff_mul * mark_mul * w_mul - mit * 0.6))
	return {"base": base, "elem_mul": elem_mul, "aff_mul": aff_mul, "has_affinity": aff != null, "d_terrain_def": d_terrain_def}

## forecastBattle — two-way pre-jitter forecast for the UI/AI. Mirrors resolve_attack's
## counter rule (defender in range -> 0.8x swing) and reports a stable lo..hi range.
static func forecast_battle(state, attacker: Dictionary, defender: Dictionary) -> Dictionary:
	var a: Dictionary = compute_damage(state, attacker, defender)
	var dist: int = state_distance(attacker, defender)
	var can_counter: bool = dist >= 1 and dist <= defender["range"]
	var c_base: int = 0
	if can_counter:
		c_base = maxi(1, roundi(compute_damage(state, defender, attacker)["base"] * 0.8))
	return {
		"lo": maxi(1, a["base"] - 1), "hi": a["base"] + 1,
		"elem_mul": a["elem_mul"], "has_affinity": a["has_affinity"],
		"can_counter": can_counter,
		"c_lo": maxi(1, c_base - 1) if can_counter else 0,
		"c_hi": c_base + 1 if can_counter else 0,
		"sure_kill": defender["hp"] <= maxi(1, a["base"] - 1),
	}

# Hex distance between two unit records (kept local so combat doesn't preload Hex
# under a different alias — but Hex is the canonical source; this just forwards).
static func state_distance(a: Dictionary, b: Dictionary) -> int:
	return Hex.distance(Vector2i(a["q"], a["r"]), Vector2i(b["q"], b["r"]))
```

NOTE: `Hex` is referenced in `state_distance` — add the preload `const Hex = preload("res://core/hex.gd")` with the other preloads at the top of `combat.gd`. (Listed separately here so it isn't missed: the top of the file must include all five preloads — Elements, Terrain, Status, Weather, Hex.)

- [ ] **Step 4: Run — verify pass**
```
pwsh -ExecutionPolicy Bypass -File godot/tests/run_tests.ps1; "EXIT=$LASTEXITCODE"
```
Expected: green, `EXIT=0` (~13 new asserts). If a `base` value is off by one, re-check the `roundi`/`mit * 0.6` order against the JS `Math.round(raw * ... - mit * 0.6)` — the subtraction is INSIDE the round. `0 failed` is the gate.

- [ ] **Step 5: Commit**
```
git add godot/core/combat.gd godot/tests/run_tests.gd
git commit -m "[godot] M4: damage math + forecast (compute_damage, forecast_battle)"
```

---

## Task 6: Inline combat resolution (resolve_attack)

Port the inline resolution — the JS `beginBattle` swing setup + `applySwing` impact logic, collapsed into one synchronous `resolve_attack` (no cutaway, no floats/logs). It applies the primary swing, then a counter if the defender survives and the attacker is in the defender's range, with the ±1 jitter and counter 0.8× drawn deterministically from `state.rng`. Ward absorbs one hit. XP (damage + kill bonus) is awarded to the striker.

**Files:** Modify `godot/core/combat.gd`, `godot/tests/run_tests.gd`.

- [ ] **Step 1: Add failing resolution tests to `godot/tests/run_tests.gd`**

Add the call after `_test_combat()`:
```gdscript
	_test_resolve()
```
Append:
```gdscript
func _test_resolve() -> void:
	# Attacker kills a low-HP defender; no counter; attacker gains dmg+kill xp.
	var gs := _combat_state()
	gs.rng = Rng.new(7)
	var atk := gs.spawn_unit("cinderling", 0, 2, 3)   # pyro power 5
	var dfn := gs.spawn_unit("galewisp", 1, 3, 3)      # zephyr hp 10
	dfn["hp"] = 4
	Combat.resolve_attack(gs, atk, dfn)
	_ok(dfn["hp"] <= 0, "resolve: lethal hit kills defender")
	_ok(atk["xp"] > 0, "resolve: attacker gained xp")
	# A kill earns dmg+10 XP -> the L1 cinderling levels up (full-heals to new max_hp),
	# so assert "no counter" as "attacker at full hp" rather than the literal 12.
	_eq(atk["hp"], atk["max_hp"], "resolve: no counter from a dead defender (attacker at full hp)")
	# Two healthy units trade: defender survives and counters (galewisp range 2).
	var gs2 := _combat_state()
	gs2.rng = Rng.new(7)
	var a2 := gs2.spawn_unit("stoneward", 0, 2, 3)   # terra hp 22
	var d2 := gs2.spawn_unit("galewisp", 1, 3, 3)     # zephyr hp 10, range 2
	var a_hp0: int = a2["hp"]
	var d_hp0: int = d2["hp"]
	Combat.resolve_attack(gs2, a2, d2)
	_ok(d2["hp"] < d_hp0, "resolve: defender took the primary hit")
	_ok(a2["hp"] < a_hp0, "resolve: attacker took a counter")
	# Ward absorbs the primary hit (no damage, ward consumed).
	var gs3 := _combat_state()
	gs3.rng = Rng.new(1)
	var a3 := gs3.spawn_unit("cinderling", 0, 2, 3)
	var d3 := gs3.spawn_unit("stoneward", 1, 3, 3)
	var d3_hp0: int = d3["hp"]
	Status.add_status(d3, "ward", 1)
	Combat.resolve_attack(gs3, a3, d3)
	_eq(d3["hp"], d3_hp0, "resolve: ward absorbs the hit")
	_ok(not Status.has_status(d3, "ward"), "resolve: ward consumed")
	# Out-of-range counter: a melee defender can't counter a range-2 attacker at dist 2.
	var gs4 := _combat_state()
	gs4.rng = Rng.new(3)
	var a4 := gs4.spawn_unit("pyrowyrm", 0, 1, 3)    # range 2
	var d4 := gs4.spawn_unit("stoneward", 1, 3, 3)    # range 1, distance 2 away
	var a4_hp0: int = a4["hp"]
	Combat.resolve_attack(gs4, a4, d4)
	_ok(d4["hp"] < d4["max_hp"], "resolve: ranged attacker hits")
	_eq(a4["hp"], a4_hp0, "resolve: melee defender out of range cannot counter")
```

- [ ] **Step 2: Run — verify it fails (resolve_attack missing)**
```
pwsh -ExecutionPolicy Bypass -File godot/tests/run_tests.ps1; "EXIT=$LASTEXITCODE"
```
Expected: error about `Combat.resolve_attack` not found, non-zero EXIT.

- [ ] **Step 3: Append to `godot/core/combat.gd`, verbatim** (port of `game.js` beginBattle 1005–1017 + applySwing 2360–2386, inline). Add a preload for the leveling helpers and the three functions:

First add this preload at the top of `combat.gd` with the others:
```gdscript
const Units = preload("res://core/units.gd")
```
Then append at the end of the file:
```gdscript

## resolve_attack — INLINE battle (no cutaway). Primary swing, then a counter if the
## defender survives and the attacker is within the defender's range. Jitter and the
## counter 0.8x are drawn from state.rng. Mirrors beginBattle + applySwing, minus the
## animation/float/log side effects (those return with the M8 battle scene + M7 HUD).
static func resolve_attack(state, attacker: Dictionary, defender: Dictionary) -> void:
	var a1: Dictionary = compute_damage(state, attacker, defender)
	_apply_hit(state, attacker, defender, _jitter(state, a1["base"]))
	if defender["hp"] > 0:
		var d: int = state_distance(attacker, defender)
		if d >= 1 and d <= defender["range"]:
			var a2: Dictionary = compute_damage(state, defender, attacker)
			var counter_dmg: int = maxi(1, roundi(_jitter(state, a2["base"]) * 0.8))
			_apply_hit(state, defender, attacker, counter_dmg)
	state.check_win_condition()

## _jitter — apply the JS ±1 spread (base-1 / base / base+1), floored at 1, via state.rng.
static func _jitter(state, base: int) -> int:
	return maxi(1, base + state.rng.below(3) - 1)

## _apply_hit — one swing: ward absorbs (consumed, no damage/xp); else deal `dmg`,
## award `dmg` (+kill bonus) XP to `src`, leave death detection to hp <= 0.
static func _apply_hit(state, src: Dictionary, dst: Dictionary, dmg: int) -> void:
	if Status.has_status(dst, "ward"):
		dst["status"].erase("ward")
		return
	dst["hp"] -= dmg
	var killed: bool = dst["hp"] <= 0
	var xp_amt: int = dmg + (Units.KILL_XP_BONUS if killed else 0)
	Units.gain_xp(src, xp_amt)
```

- [ ] **Step 4: Run — verify pass**
```
pwsh -ExecutionPolicy Bypass -File godot/tests/run_tests.ps1; "EXIT=$LASTEXITCODE"
```
Expected: green, `EXIT=0` (~9 new asserts). `state.check_win_condition()` is the Task-2 stub (still a no-op until Task 7) — these tests don't kill a master, so no win triggers. `0 failed` is the gate.

- [ ] **Step 5: Commit**
```
git add godot/core/combat.gd godot/tests/run_tests.gd
git commit -m "[godot] M4: inline combat resolution (resolve_attack + counter + ward + xp)"
```

---

## Task 7: Turn machinery + capture + win condition + effective_move

Port `endTurn`, `checkWinCondition`, and `captureTower` onto `GameState`, and extend `effective_move` (pathfinding) with the status + weather modifiers it was stubbed for in M3. `end_turn` is the per-turn engine: lock the current player's units, switch player, advance the turn counter on a full round, regen the new player's master MP (base + 2/owned-tower), tick statuses, heal units on owned towers/castles, evolve eligible units, and roll weather once per full round.

**Files:** Modify `godot/core/game_state.gd`, `godot/core/pathfinding.gd`, `godot/tests/run_tests.gd`.

- [ ] **Step 1: Add failing turn-machinery tests to `godot/tests/run_tests.gd`**

Add the call after `_test_resolve()`:
```gdscript
	_test_turn()
```
Append:
```gdscript
func _test_turn() -> void:
	var gs := GameState.new_skirmish(Maps.MAPS[0], 42)
	var m0: Variant = gs.master_of(0)
	var m1: Variant = gs.master_of(1)
	# Capture player 1's master MP BEFORE it is brought in (starts at 14).
	var m1_mp0: int = m1["mp"]
	# end_turn flips the player, locks the outgoing side, regens the incoming master.
	gs.end_turn()
	_eq(gs.current_player, 1, "turn: switched to player 1")
	_ok(m0["acted"], "turn: outgoing units locked (acted)")
	# Incoming master regenerates MP (base mp_regen 4, +2/owned-tower = 0 at start).
	_eq(m1["mp"], mini(m1["max_mp"], m1_mp0 + 4), "turn: incoming master regained base MP")
	gs.end_turn()   # back to player 0
	_eq(gs.current_player, 0, "turn: back to player 0")
	_eq(gs.turn, 2, "turn: counter advances on player-0 round")
	# Incoming units are unlocked for the new turn.
	_ok(not m0["acted"], "turn: incoming units unlocked")
	# Heal on owned castle: wound master, end a full round, it heals +4 (castle).
	m0["hp"] = m0["max_hp"] - 10
	var hp_before: int = m0["hp"]
	gs.end_turn(); gs.end_turn()   # back to player 0, on its castle
	_ok(m0["hp"] > hp_before, "turn: unit on owned castle heals")
	# Win condition: kill a master, end_turn detects it.
	var gs2 := GameState.new_skirmish(Maps.MAPS[0], 42)
	gs2.master_of(1)["hp"] = 0
	gs2.check_win_condition()
	_eq(gs2.winner, 0, "win: surviving owner wins")
	# capture_tower flips ownership.
	var gs3 := GameState.new_skirmish(Maps.MAPS[0], 42)
	var tower_pos: Vector2i = gs3.map["towers"][0]
	var tcell: Dictionary = gs3.cell_at(tower_pos.x, tower_pos.y)
	var u := gs3.spawn_unit("cinderling", 0, tower_pos.x, tower_pos.y)
	gs3.capture_tower(u, tcell)
	_eq(tcell["owner"], 0, "capture: tower owner flipped")
	# effective_move now honours slow / skitter / weather fly bonus.
	var gw := _flat_state(5, 5)
	gw.weather = {"key": "clear", "turns_left": 5}
	var s := gw.spawn_unit("cinderling", 0, 2, 2)   # move 4
	_eq(Pathfinding.effective_move(s, gw), 4, "move: base move")
	Status.add_status(s, "slow", 2)
	_eq(Pathfinding.effective_move(s, gw), 2, "move: slow -2")
	s["status"].erase("slow")
	Status.add_status(s, "skitterBoost", 2)
	_eq(Pathfinding.effective_move(s, gw), 6, "move: skitter +2")
	s["status"].erase("skitterBoost")
	var fl := gw.spawn_unit("galewisp", 0, 1, 1)     # flying, move 5
	gw.weather = {"key": "gale", "turns_left": 5}    # gale fly_bonus 1
	_eq(Pathfinding.effective_move(fl, gw), 6, "move: gale +1 for flyers")
```

- [ ] **Step 2: Run — verify it fails (end_turn / capture_tower / new effective_move signature missing)**
```
pwsh -ExecutionPolicy Bypass -File godot/tests/run_tests.ps1; "EXIT=$LASTEXITCODE"
```
Expected: error about `gs.end_turn` (or `effective_move` arity), non-zero EXIT.

- [ ] **Step 3: Replace the `check_win_condition` stub and add `end_turn` + `capture_tower` to `godot/core/game_state.gd`.**

Add preloads at the top with the others:
```gdscript
const Status = preload("res://core/status.gd")
```
Replace the Task-2 stub:
```gdscript
func check_win_condition() -> void:
	pass
```
with the real body (port of `game.js` checkWinCondition 1066–1073, logic only):
```gdscript
## checkWinCondition — if a player's master is dead, the other player wins.
func check_win_condition() -> void:
	for owner in [0, 1]:
		if master_of(owner) == null:
			winner = 1 - owner
			return
```
Then append these methods (port of `game.js` endTurn 4719–4761 + captureTower 1166–1167, logic only — no AI/save/camera/log/anim):
```gdscript
## captureTower — flip a tower's ownership to the capturing unit's side.
func capture_tower(unit: Dictionary, cell: Dictionary) -> void:
	cell["owner"] = unit["owner"]

## endTurn — advance one player's turn: lock the outgoing side, switch player, bump
## the round counter, regen the incoming master's MP (base + 2/owned-tower), tick
## statuses, unlock + heal + evolve the incoming units, and roll weather per round.
## Logic only — AI handoff, autosave, camera, banners/logs return at the HUD/AI layers.
func end_turn() -> void:
	for u in alive_units(current_player):
		u["acted"] = true
	current_player = 1 - current_player
	if current_player == 0:
		turn += 1
	var m: Variant = master_of(current_player)
	if m != null:
		var tower_bonus: int = _owned_tower_count(current_player) * 2
		m["mp"] = mini(m["max_mp"], m["mp"] + m["mp_regen"] + tower_bonus)
	Status.tick_statuses(self, current_player)
	if winner != -1:
		return   # a burn-kill may have ended the match
	for u in alive_units(current_player):
		u["acted"] = false
		u["second_move"] = false
		if u["cd"] > 0:
			u["cd"] -= 1
		var c: Variant = cell_at(u["q"], u["r"])
		if c != null and c["terrain"] == "tower" and c.get("owner", -1) == u["owner"]:
			u["hp"] = mini(u["max_hp"], u["hp"] + 2)
		if c != null and c["terrain"] == "castle" and c.get("owner", -1) == u["owner"]:
			u["hp"] = mini(u["max_hp"], u["hp"] + 4)
		Units.try_evolve(u, c)
	if current_player == 0 and not weather.is_empty():
		weather["turns_left"] -= 1
		if weather["turns_left"] <= 0:
			Weather.roll_weather(self, false)
	check_win_condition()

## _owned_tower_count — towers (by board cell ownership) held by `owner`.
func _owned_tower_count(owner: int) -> int:
	var n := 0
	for t in map.get("towers", []):
		var c: Variant = cell_at(t.x, t.y)
		if c != null and c.get("owner", -1) == owner:
			n += 1
	return n
```

NOTE on `_owned_tower_count`: the JS reads `MAP.towers.filter(t => t.owner === ...)` where tower objects carry an `owner`. In the Godot port `map["towers"]` is an `Array[Vector2i]` of positions, and ownership lives on the CELL (set by `capture_tower`). So count by looking up each tower cell's `owner`. At match start no towers are owned, so the regen bonus is 0 until one is captured — matching the JS where towers start neutral (`owner: -1`).

- [ ] **Step 4: Extend `effective_move` in `godot/core/pathfinding.gd`.**

Add preloads at the top with the existing `Hex`/`Terrain`:
```gdscript
const Status = preload("res://core/status.gd")
const Weather = preload("res://core/weather.gd")
```
Replace the M3 stub:
```gdscript
static func effective_move(unit: Dictionary) -> int:
	return unit["move"]
```
with (port of `game.js` effectiveMove 5606–5612):
```gdscript
## effectiveMove — move allowance after status + weather. Slow -2 (min 1), skitter +2,
## and the weather fly bonus for flyers. Needs `state` for the active weather.
static func effective_move(unit: Dictionary, state) -> int:
	var m: int = unit["move"]
	if Status.has_status(unit, "slow"):
		m = maxi(1, m - 2)
	if Status.has_status(unit, "skitterBoost"):
		m += 2
	var w: Dictionary = Weather.weather_now(state)
	if w.get("fly_bonus", 0) != 0 and unit["flying"]:
		m += w["fly_bonus"]
	return m
```
Then update the ONE call site in `compute_reachable` — change:
```gdscript
	var limit := effective_move(unit)
```
to:
```gdscript
	var limit := effective_move(unit, state)
```

- [ ] **Step 5: Run — verify pass**
```
pwsh -ExecutionPolicy Bypass -File godot/tests/run_tests.ps1; "EXIT=$LASTEXITCODE"
```
Expected: green, `EXIT=0` (~13 new asserts). The M3 pathfinding tests still pass: `compute_reachable` now passes `state` into `effective_move`, and `_flat_state` boards have an empty `weather` (→ clear, no fly bonus) and units with no `status`. `0 failed` is the gate.

- [ ] **Step 6: Commit**
```
git add godot/core/game_state.gd godot/core/pathfinding.gd godot/tests/run_tests.gd
git commit -m "[godot] M4: turn machinery (end_turn, win, capture) + effective_move modifiers"
```

---

## Task 8: Wire attack / capture / end-turn into the board + close M4

Make the interactive board (from M3) drive the new combat loop: clicking an enemy within the selected unit's attack range resolves an inline attack; moving onto an enemy/neutral tower captures it; pressing Enter ends the turn (flipping to the other side — you drive both, since AI is M6). The logic is all headless-tested; the on-screen behavior is confirmed visually.

**Files:** Modify `godot/scenes/main.gd`, `ROADMAP_GODOT.md`. (No new headless asserts — `main.gd` has no `class_name`, so it is verified by a headless BOOT, then by the windowed visual check.)

- [ ] **Step 1: Replace `_on_click` and add an end-turn key in `godot/scenes/main.gd`.**

Add the `Combat` preload with the others at the top:
```gdscript
const Combat = preload("res://core/combat.gd")
```
Replace the whole `_on_click` function with:
```gdscript
func _on_click(a: Vector2i) -> void:
	# With a unit selected: attack an enemy in range, else move (and maybe capture).
	if selected != null:
		# Attack: clicked tile holds an enemy within attack range.
		var targets := Pathfinding.compute_attack_targets(state, selected, selected["q"], selected["r"])
		if targets.has(Hex.key(a)):
			var foe = state.unit_at(a.x, a.y)
			if foe != null:
				Combat.resolve_attack(state, selected, foe)
				_clear_selection()
				units_layer.set_state(state)
				return
		# Move: clicked a reachable tile (not the unit's own).
		var reach := Pathfinding.compute_reachable(state, selected)
		var is_own_tile: bool = (a.x == selected["q"] and a.y == selected["r"])
		if reach.has(Hex.key(a)) and not is_own_tile:
			selected["q"] = a.x
			selected["r"] = a.y
			# Capture a tower we landed on that isn't already ours.
			var cell = state.cell_at(a.x, a.y)
			if cell != null and cell["terrain"] == "tower" and cell.get("owner", -1) != selected["owner"]:
				state.capture_tower(selected, cell)
			_clear_selection()
			units_layer.set_state(state)
			return
	# Otherwise (re)select the current player's unit under the cursor.
	var u = state.unit_at(a.x, a.y)
	if u != null and u["owner"] == state.current_player:
		selected = u
		overlay.set_highlights(Pathfinding.compute_reachable(state, u), u)
	else:
		_clear_selection()
```
Then add an end-turn key handler — extend `_unhandled_input`:
```gdscript
func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		_on_click(Hex.pixel_to_axial(get_global_mouse_position()))
	elif event is InputEventKey and event.pressed and event.keycode == KEY_ENTER:
		state.end_turn()
		_clear_selection()
		units_layer.set_state(state)
		if state.winner != -1:
			print("WINNER: player %d" % state.winner)
```

- [ ] **Step 2: Headless boot check — confirm `main.gd` parses and the scene loads.**

`main.gd` has no `class_name`, so the test harness does NOT load it. Boot the project headless (loads `main.tscn` → `main.gd`, runs `_ready`, quits) and confirm no parse/load error:
```
godot --headless --path godot --quit-after 30 2>&1 | Select-String -Pattern "SCRIPT ERROR|Parse Error|Failed to load"
```
Expected: NO matching lines (empty output). If anything prints, `main.gd` has a parse error — fix it before continuing. (This is the gate that the M3 headless suite was blind to.)

- [ ] **Step 3: Run the harness — confirm no regression in the core.**
```
pwsh -ExecutionPolicy Bypass -File godot/tests/run_tests.ps1; "EXIT=$LASTEXITCODE"
```
Expected: green, `EXIT=0` (no new asserts this task).

- [ ] **Step 4: Visual confirmation (windowed) — YOU (a headless subagent) CANNOT DO THIS.**
The intended manual check, run by the user: `godot --path godot` shows the board; select an archon, click an adjacent enemy → it takes damage (token may vanish if killed); move a unit onto a tower → it captures (and now contributes MP/heals); press Enter → turn flips to the other side and you can move those units. Report this step as "NEEDS USER VISUAL CONFIRMATION". Do NOT run the windowed command.

- [ ] **Step 5: Check off M4 in `ROADMAP_GODOT.md`** — change `- [ ] M4 — Combat resolution + status engine + weather (logic + forecast)` to `- [x] M4 — ...`.

- [ ] **Step 6: Commit**
```
git add godot/scenes/main.gd ROADMAP_GODOT.md
git commit -m "[godot] M4: wire attack/capture/end-turn into board; close M4"
```

---

## Notes & risk callouts

- **Determinism via `state.rng`.** `compute_damage` is pure (`base` only). The ONLY runtime randomness is the ±1 jitter in `resolve_attack` and the weather roll — both from `GameState.rng` (a `Mulberry32` seeded in `new_skirmish`). This is a deliberate refactor of the JS `computeDamage` (which jittered internally with `Math.random`): the `base` is identical and the forecast already used `base`, so behavior matches while becoming testable. Never assert on a single jittered value — assert `base`, or seed the rng and assert reproducibility.
- **`roundi` vs `Math.round`.** For the positive operands in `compute_damage` (`base` is `max(1, ...)`), `roundi(x)` matches `Math.round(x)` (both round half up). The subtraction `- mit * 0.6` is INSIDE the round, matching JS — keep it there.
- **Status writers are M5.** M4 ships the engine and makes combat READ mark/bulwark/ward/slow/skitter, but only tests write them. In-game writers (abilities) arrive in M5, which also adds the optional `apply_status` param to `resolve_attack` (the JS `applySwing` `b.applyStatus` path). Don't add it now — YAGNI.
- **`check_win_condition` stub then real.** Task 2 adds a `pass` stub (so `tick_statuses` resolves); Task 7 replaces the body. If Task 7 is somehow skipped, burn-kills won't end the match — but the suite stays green either way.
- **Tower ownership lives on the CELL, not the tower object.** Unlike the JS `MAP.towers[i].owner`, the Godot `map["towers"]` is an `Array[Vector2i]` of positions; ownership is on `cells["q,r"]["owner"]` and flipped by `capture_tower`. `_owned_tower_count` looks each tower cell up. Towers start neutral (`owner -1`), so the MP regen bonus is 0 until capture — faithful to the JS.
- **`effective_move` signature changed** from `(unit)` to `(unit, state)`. The only caller is `compute_reachable` (updated in Task 7 Step 4). The M3 pathfinding tests still pass because `_flat_state` has an empty `weather` (→ clear) and status-free units.
- **`end_turn` weather tick.** The JS decrements `STATE.weather.turnsLeft` once per FULL round (when `currentPlayer === 0`) and re-rolls at 0. Ported verbatim. The initial `new_skirmish` roll sets `turns_left` 4..6, so the first re-roll is several rounds out.
- **No AI / save / camera / banners in `end_turn`.** Those are M6 (AI), M9 (save), and M7 (HUD banners/logs). M4's `end_turn` is pure rules. Pressing Enter just flips sides so combat/weather/heals/evolution are all manually exercisable on screen.
- **`main.gd` is not headless-tested** (no `class_name`). Task 8 Step 2 adds the explicit headless-boot parse check the M3 milestone learned to need — run it whenever `main.gd` changes.

---

## Self-review

- **Spec coverage** (design spec milestone 4 — "Combat + status + weather (logic + forecast); no cutaway yet, resolve inline"): `compute_damage`/`forecast_battle` (Task 5) + element matrix/affinity (Task 1) + weather mults (Task 3) + status reads mark/bulwark (Tasks 2/5); inline resolution with counter/ward/XP (Task 6); status engine add/has/tick (Task 2); weather engine roll/now (Task 3); leveling + evolution that combat drives (Task 4); turn machinery end_turn/heals/win/capture + effective_move modifiers (Task 7); board wiring (Task 8). ✅
- **Deferred with intent:** battle cutaway (M8), full gameover screen (M9), AI turn (M6), ability status-writers + `resolve_attack` status param (M5), save (M9), HUD banners/logs/floats (M7). All noted. ✅
- **Type/signature consistency:** `compute_damage(state, attacker, defender)` / `forecast_battle(state, a, d)` / `resolve_attack(state, a, d)` / `state_distance(a, b)` consistent across Tasks 5–6 and `main.gd`; `effective_move(unit, state)` updated at its sole call site (Task 7); `gain_xp`/`try_evolve`/`capture_tower`/`end_turn`/`check_win_condition` signatures match every call site in tests, `end_turn`, and `main.gd`; status dict shape `unit["status"][key]` consistent across `status.gd`, `combat.gd`, `end_turn`, and tests; weather dict shape `{key, turns_left}` and `WEATHERS` field names (`atk_mul`/`ranged_mul`/`fly_bonus`) consistent across `weather.gd`, `combat.gd`, `effective_move`, and `end_turn`. ✅
- **No placeholders:** every step ships complete code or an exact command + expected result. The Task-2 `check_win_condition` stub is explicitly a stub-then-replace, called out in both Task 2 and Task 7. ✅
