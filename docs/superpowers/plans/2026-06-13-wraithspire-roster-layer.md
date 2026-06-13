# Phase 5.1 Campaign Roster Layer Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build `core/roster_store.gd` — a pure, harness-tested persistent-campaign roster module (veteran carry, permadeath, v1-progress migration) plus its `user://` JSON I/O.

**Architecture:** One self-contained `RefCounted` module modeled on `SaveGame`/`SettingsStore`: pure data ops (snapshot / add / remove / clear / reconcile / migrate) are unit-tested; file I/O is a thin wrapper with JSON int-coercion on load. Roster entries are full snapshots of a veteran's grown stats. No live game wiring — deploy, win-reconcile, and AI scaling land in Phase 5.2.

**Tech Stack:** Godot 4 / GDScript. Harness: `godot/tests/run_tests.gd` (`_test_*` registered in `_initialize()`; `_eq`/`_ok` helpers; `preload` block at top). Builds veterans through `core/units.gd` (`make_unit` / `apply_level_growth` / `evolve_unit` / `EVOLVE_LEVEL`) and reads `data/unit_types.gd`. Gate: `pwsh -File godot/tests/run_tests.ps1` (`== N passed, 0 failed ==`, EXIT 0; never `-ExecutionPolicy Bypass`). Indentation: TABS.

---

## File Structure

| File | Responsibility | Task |
|---|---|---|
| `godot/core/roster_store.gd` | the roster module (pure ops + I/O) | 1,2,3,4 |
| `godot/tests/run_tests.gd` | `RosterStore` preload; `_test_roster_*` registration + asserts | 1,2,3,4 |

Four tasks. Each is strict TDD: a stub makes the harness compile, the test is written and run to FAIL, then the real implementation makes it PASS, then commit. The module file is created in Task 1 and extended in 2–4.

---

## Task 1: Module skeleton + roster editors (new/snapshot/add/remove/clear)

**Files:**
- Create: `godot/core/roster_store.gd`
- Modify: `godot/tests/run_tests.gd` (preload block ~line 36; `_initialize` ~line 98; new test fn)

- [ ] **Step 1: Create the module with class header + stub editors (so the harness compiles)**

Create `godot/core/roster_store.gd`:

```gdscript
class_name RosterStore
extends RefCounted
## Phase 5.1 persistent campaign roster. Pure data ops (harness-tested) + thin
## user:// JSON I/O (the campaign.v2 slot). Veterans carry level/xp/evolution/
## relic between missions; deaths are permanent. Modeled on SaveGame /
## SettingsStore. Live wiring (deploy, win-reconcile, AI scaling) = Phase 5.2.

const Units = preload("res://core/units.gd")
const UnitTypes = preload("res://data/unit_types.gd")

const SLOT_PATH := "user://wraithspire_campaign.json"

# Non-transient unit fields stored verbatim in a roster entry (full snapshot).
const _CARRY_STR := ["type_key", "name", "element", "sprite", "attack", "relic"]
const _CARRY_INT := ["level", "xp", "max_hp", "power", "def", "move", "range"]

# ---- pure roster editors ----

static func new_roster() -> Dictionary:
	return {}

static func entry_from_unit(unit: Dictionary, roster_id: int) -> Dictionary:
	return {}

static func add_entry(blob: Dictionary, unit: Dictionary) -> int:
	return 0

static func remove_entry(blob: Dictionary, roster_id: int) -> bool:
	return false

static func clear(blob: Dictionary) -> void:
	pass
```

- [ ] **Step 2: Wire the preload + register + write the failing test**

In `godot/tests/run_tests.gd`, add to the preload block (after the `Objectives` line, ~line 36):

```gdscript
const RosterStore = preload("res://core/roster_store.gd")
```

In `_initialize()`, after `_test_fog_settings()` (~line 98), add:

```gdscript
	_test_roster_basic()
```

Add the test function (anywhere among the other `_test_*` fns):

```gdscript
func _test_roster_basic() -> void:
	var b := RosterStore.new_roster()
	_eq(b["v"], 2, "roster: new version 2")
	_eq((b["roster"] as Array).size(), 0, "roster: new empty")
	_eq(b["next_roster_id"], 1, "roster: new next id 1")
	# entry_from_unit snapshots carry fields, strips transient, doesn't mutate.
	var u := {
		"id": 42, "owner": 0, "q": 3, "r": 5, "is_master": false,
		"type_key": "stoneward", "name": "Stoneward", "element": "terra",
		"sprite": "golem", "attack": "melee", "flying": false,
		"hp": 10, "max_hp": 26, "power": 6, "def": 5, "move": 2, "range": 1,
		"level": 2, "xp": 4, "relic": "vital", "acted": true, "cd": 1, "second_move": true,
	}
	var e := RosterStore.entry_from_unit(u, 7)
	_eq(e["roster_id"], 7, "entry: roster_id stamped")
	_eq(e["type_key"], "stoneward", "entry: type_key kept")
	_eq(e["level"], 2, "entry: level kept")
	_eq(e["xp"], 4, "entry: xp kept")
	_eq(e["max_hp"], 26, "entry: grown max_hp kept")
	_eq(e["power"], 6, "entry: grown power kept")
	_eq(e["relic"], "vital", "entry: relic kept")
	_eq(e["flying"], false, "entry: flying kept")
	_eq(e.has("q"), false, "entry: q stripped")
	_eq(e.has("hp"), false, "entry: hp stripped")
	_eq(e.has("id"), false, "entry: id stripped")
	_eq(e.has("acted"), false, "entry: acted stripped")
	_eq(u["id"], 42, "entry: source unit not mutated")
	# add / remove / clear.
	var id1 := RosterStore.add_entry(b, u)
	var id2 := RosterStore.add_entry(b, u)
	_eq(id1, 1, "add: first id 1")
	_eq(id2, 2, "add: second id 2")
	_eq(b["next_roster_id"], 3, "add: next id bumped")
	_eq((b["roster"] as Array).size(), 2, "add: roster size 2")
	_eq(RosterStore.remove_entry(b, 1), true, "remove: existing returns true")
	_eq(RosterStore.remove_entry(b, 99), false, "remove: missing returns false")
	_eq((b["roster"] as Array).size(), 1, "remove: roster size 1")
	RosterStore.clear(b)
	_eq((b["roster"] as Array).size(), 0, "clear: empty")
	_eq(b["next_roster_id"], 3, "clear: next id preserved")
```

- [ ] **Step 3: Run, verify FAIL**

Run: `pwsh -File godot/tests/run_tests.ps1`
Expected: FAIL — `_test_roster_basic` asserts fail (stubs return `{}` / `0` / `false`); last line shows a non-zero failed count, EXIT 1.

- [ ] **Step 4: Implement the editors for real**

Replace the five stub bodies in `godot/core/roster_store.gd`:

```gdscript
static func new_roster() -> Dictionary:
	return {"v": 2, "roster": [], "next_roster_id": 1}

static func entry_from_unit(unit: Dictionary, roster_id: int) -> Dictionary:
	var e := {"roster_id": roster_id}
	for k in _CARRY_STR:
		e[k] = String(unit.get(k, ""))
	for k in _CARRY_INT:
		e[k] = int(unit.get(k, 0))
	e["flying"] = bool(unit.get("flying", false))
	return e

static func add_entry(blob: Dictionary, unit: Dictionary) -> int:
	var rid: int = int(blob["next_roster_id"])
	(blob["roster"] as Array).append(entry_from_unit(unit, rid))
	blob["next_roster_id"] = rid + 1
	return rid

static func remove_entry(blob: Dictionary, roster_id: int) -> bool:
	var arr: Array = blob["roster"]
	for i in arr.size():
		if int(arr[i]["roster_id"]) == roster_id:
			arr.remove_at(i)
			return true
	return false

static func clear(blob: Dictionary) -> void:
	blob["roster"] = []
```

- [ ] **Step 5: Run, verify PASS**

Run: `pwsh -File godot/tests/run_tests.ps1`
Expected: PASS — `== N passed, 0 failed ==`, EXIT 0 (N ≈ +24 vs the 998 baseline).

- [ ] **Step 6: Commit**

```bash
git add godot/core/roster_store.gd godot/tests/run_tests.gd
git commit -m "[godot] P5.1 roster: module skeleton + roster editors"
```

---

## Task 2: reconcile (carry + permadeath core)

**Files:**
- Modify: `godot/core/roster_store.gd`
- Modify: `godot/tests/run_tests.gd`

- [ ] **Step 1: Add a stub `reconcile` (so the harness compiles)**

Append to `godot/core/roster_store.gd` (after `clear`):

```gdscript
# ---- reconcile (called after a mission win, in Phase 5.2) ----

static func reconcile(blob: Dictionary, living_units: Array, deployed_ids: Array) -> Dictionary:
	return blob.duplicate(true)
```

- [ ] **Step 2: Register + write the failing test**

In `_initialize()`, after `_test_roster_basic()`:

```gdscript
	_test_roster_reconcile()
```

Add the test function:

```gdscript
func _test_roster_reconcile() -> void:
	# Seed a roster with two deployed veterans (roster_ids 1, 2).
	var b := RosterStore.new_roster()
	var vet_a := {"type_key": "stoneward", "name": "Stoneward", "element": "terra",
		"sprite": "golem", "attack": "melee", "flying": false,
		"max_hp": 26, "power": 6, "def": 5, "move": 2, "range": 1, "level": 2, "xp": 0, "relic": ""}
	var vet_b := {"type_key": "tidekin", "name": "Tidekin", "element": "hydro",
		"sprite": "merfolk", "attack": "melee", "flying": false,
		"max_hp": 22, "power": 6, "def": 3, "move": 4, "range": 1, "level": 3, "xp": 0, "relic": ""}
	var rid_a := RosterStore.add_entry(b, vet_a)   # 1
	var rid_b := RosterStore.add_entry(b, vet_b)   # 2
	# After the mission: vet A lived and leveled to 3 + grabbed a relic; vet B
	# died; a fresh summon (no roster_id) lived; another fresh summon died (absent).
	var living := [
		{"roster_id": rid_a, "type_key": "stoneward", "name": "Stoneward", "element": "terra",
		 "sprite": "golem", "attack": "melee", "flying": false,
		 "max_hp": 30, "power": 7, "def": 6, "move": 2, "range": 1, "level": 3, "xp": 2, "relic": "vital"},
		{"type_key": "galewisp", "name": "Galewisp", "element": "zephyr",
		 "sprite": "wisp", "attack": "spark", "flying": true,
		 "max_hp": 10, "power": 4, "def": 1, "move": 5, "range": 2, "level": 1, "xp": 0, "relic": ""},
	]
	var out := RosterStore.reconcile(b, living, [rid_a, rid_b])
	var arr: Array = out["roster"]
	_eq(arr.size(), 2, "reconcile: survivor-vet + fresh-survivor = 2")
	_eq((b["roster"] as Array).size(), 2, "reconcile: original blob untouched")
	var a_entry := {}
	var fresh_entry := {}
	var has_b := false
	for e in arr:
		if int(e["roster_id"]) == rid_a:
			a_entry = e
		elif int(e["roster_id"]) == rid_b:
			has_b = true
		elif e["type_key"] == "galewisp":
			fresh_entry = e
	_eq(a_entry.is_empty(), false, "reconcile: vet A retained")
	_eq(a_entry.get("level"), 3, "reconcile: vet A leveled to 3")
	_eq(a_entry.get("max_hp"), 30, "reconcile: vet A grown stats updated")
	_eq(a_entry.get("relic"), "vital", "reconcile: vet A relic carried")
	_eq(has_b, false, "reconcile: dead vet B culled (permadeath)")
	_eq(fresh_entry.is_empty(), false, "reconcile: fresh survivor added")
	_ok(int(fresh_entry["roster_id"]) >= 3, "reconcile: fresh survivor got a new id")
```

- [ ] **Step 3: Run, verify FAIL**

Run: `pwsh -File godot/tests/run_tests.ps1`
Expected: FAIL — the stub returns the seeded blob unchanged, so dead vet B is not culled and the fresh survivor is not added (`arr.size()` is 2 by coincidence but `has_b` is true and `fresh_entry` is empty → those asserts fail), EXIT 1.

- [ ] **Step 4: Implement `reconcile` + helper for real**

Replace the stub body and add the private helper:

```gdscript
static func reconcile(blob: Dictionary, living_units: Array, deployed_ids: Array) -> Dictionary:
	var out: Dictionary = blob.duplicate(true)
	# Index living units that carry a roster_id (deployed veterans that survived).
	var living_by_rid := {}
	for u in living_units:
		if u.has("roster_id"):
			living_by_rid[int(u["roster_id"])] = u
	# Deployed veterans: update survivors, cull the dead (permadeath).
	for rid in deployed_ids:
		var r := int(rid)
		if living_by_rid.has(r):
			_update_entry(out, r, living_by_rid[r])
		else:
			remove_entry(out, r)
	# Fresh summons that survived (no roster_id) join the roster.
	for u in living_units:
		if not u.has("roster_id"):
			add_entry(out, u)
	return out

static func _update_entry(blob: Dictionary, roster_id: int, unit: Dictionary) -> void:
	var arr: Array = blob["roster"]
	for i in arr.size():
		if int(arr[i]["roster_id"]) == roster_id:
			arr[i] = entry_from_unit(unit, roster_id)
			return
```

- [ ] **Step 5: Run, verify PASS**

Run: `pwsh -File godot/tests/run_tests.ps1`
Expected: PASS — `== N passed, 0 failed ==`, EXIT 0 (N ≈ +9 vs Task 1).

- [ ] **Step 6: Commit**

```bash
git add godot/core/roster_store.gd godot/tests/run_tests.gd
git commit -m "[godot] P5.1 roster: reconcile (veteran carry + permadeath)"
```

---

## Task 3: migrate (v1-progress → starter-veteran grant)

**Files:**
- Modify: `godot/core/roster_store.gd`
- Modify: `godot/tests/run_tests.gd`

- [ ] **Step 1: Add the grant table + stub `migrate` (so the harness compiles)**

Append to `godot/core/roster_store.gd`:

```gdscript
# ---- migration: v1 campaign_progress -> starter roster ----

# One veteran per cleared act: [type_key, level]. Acts 1..4 (index 0..3).
# geomaul@4 and hexwisp@5 cross EVOLVE_LEVEL, so they migrate as their evolved
# forms (earthbreaker / hexlord) via Units.evolve_unit.
const GRANT := [
	["stoneward", 2],
	["tidekin", 3],
	["geomaul", 4],
	["hexwisp", 5],
]

static func migrate(progress: int) -> Dictionary:
	return new_roster()
```

- [ ] **Step 2: Register + write the failing test**

In `_initialize()`, after `_test_roster_reconcile()`:

```gdscript
	_test_roster_migrate()
```

Add the test function:

```gdscript
func _test_roster_migrate() -> void:
	_eq((RosterStore.migrate(0)["roster"] as Array).size(), 0, "migrate(0): empty roster")
	var m1: Array = RosterStore.migrate(1)["roster"]
	_eq(m1.size(), 1, "migrate(1): one veteran")
	_eq(m1[0]["type_key"], "stoneward", "migrate(1): stoneward")
	_eq(m1[0]["level"], 2, "migrate(1): level 2")
	_eq(m1[0]["relic"], "", "migrate: no relic granted")
	var m2: Array = RosterStore.migrate(2)["roster"]
	_eq(m2.size(), 2, "migrate(2): two veterans")
	_eq(m2[1]["type_key"], "tidekin", "migrate(2): second is tidekin")
	_eq(m2[1]["level"], 3, "migrate(2): tidekin level 3")
	var m3: Array = RosterStore.migrate(3)["roster"]
	_eq(m3.size(), 3, "migrate(3): three veterans")
	_eq(m3[2]["type_key"], "earthbreaker", "migrate(3): geomaul migrated as earthbreaker")
	_eq(m3[2]["level"], 4, "migrate(3): level 4")
	var m4: Array = RosterStore.migrate(4)["roster"]
	_eq(m4.size(), 4, "migrate(4): four veterans")
	_eq(m4[3]["type_key"], "hexlord", "migrate(4): hexwisp migrated as hexlord")
	_eq(m4[3]["level"], 5, "migrate(4): level 5")
	_eq(m4[3]["flying"], true, "migrate(4): hexlord flies")
	# Roster ids are sequential starting at 1.
	_eq(m4[0]["roster_id"], 1, "migrate: first id 1")
	_eq(m4[3]["roster_id"], 4, "migrate: fourth id 4")
	# Over-progress is clamped to the grant table size.
	_eq((RosterStore.migrate(9)["roster"] as Array).size(), 4, "migrate(9): clamped to 4")
```

- [ ] **Step 3: Run, verify FAIL**

Run: `pwsh -File godot/tests/run_tests.ps1`
Expected: FAIL — the stub returns an empty roster, so every `migrate(>0)` size/type assert fails, EXIT 1.

- [ ] **Step 4: Implement `migrate` + veteran builder for real**

Replace the `migrate` stub body and add the builder:

```gdscript
static func migrate(progress: int) -> Dictionary:
	var blob := new_roster()
	var n := clampi(progress, 0, GRANT.size())
	for i in n:
		add_entry(blob, _build_veteran(GRANT[i][0], GRANT[i][1]))
	return blob

# Build a veteran through the game's own progression path so it is rule-
# consistent with a naturally leveled unit. apply_level_growth bumps stats but
# not level; evolve_unit reads unit["level"] and recomputes stats from the
# evolved base + (level-1) growth. The two paths are mutually exclusive.
static func _build_veteran(type_key: String, level: int) -> Dictionary:
	var u := Units.make_unit(0, type_key, 0, 0, 0)
	u["level"] = level
	u["xp"] = 0
	if level >= Units.EVOLVE_LEVEL and UnitTypes.UNIT_TYPES[type_key].has("evolves_to"):
		Units.evolve_unit(u)
	else:
		for _i in range(level - 1):
			Units.apply_level_growth(u)
	return u
```

- [ ] **Step 5: Run, verify PASS**

Run: `pwsh -File godot/tests/run_tests.ps1`
Expected: PASS — `== N passed, 0 failed ==`, EXIT 0 (N ≈ +15 vs Task 2).

- [ ] **Step 6: Commit**

```bash
git add godot/core/roster_store.gd godot/tests/run_tests.gd
git commit -m "[godot] P5.1 roster: migrate v1 progress to starter veterans"
```

---

## Task 4: I/O + load validation + JSON round-trip

**Files:**
- Modify: `godot/core/roster_store.gd`
- Modify: `godot/tests/run_tests.gd`

- [ ] **Step 1: Add stub `_validate` + the I/O functions (so the harness compiles)**

Append to `godot/core/roster_store.gd`:

```gdscript
# ---- load validation + file I/O (thin; only _validate is unit-tested) ----

# Validate + re-coerce a parsed blob (JSON turns ints into floats). Returns a
# clean blob, or null if the blob is not a usable v:2 roster.
static func _validate(parsed) -> Variant:
	return null

static func load_or_init(progress: int) -> Dictionary:
	if FileAccess.file_exists(SLOT_PATH):
		var f := FileAccess.open(SLOT_PATH, FileAccess.READ)
		if f != null:
			var txt := f.get_as_text()
			f.close()
			var v = _validate(JSON.parse_string(txt))
			if v != null:
				return v
	var blob := migrate(progress)
	save(blob)
	return blob

static func save(blob: Dictionary) -> void:
	var f := FileAccess.open(SLOT_PATH, FileAccess.WRITE)
	if f == null:
		return
	f.store_string(JSON.stringify(blob))
	f.close()

static func reset() -> void:
	if FileAccess.file_exists(SLOT_PATH):
		DirAccess.remove_absolute(SLOT_PATH)

static func probe() -> bool:
	return FileAccess.file_exists(SLOT_PATH)
```

- [ ] **Step 2: Register + write the failing test**

In `_initialize()`, after `_test_roster_migrate()`:

```gdscript
	_test_roster_roundtrip()
```

Add the test function:

```gdscript
func _test_roster_roundtrip() -> void:
	# A migrated roster survives JSON stringify -> parse -> _validate, with all
	# numeric fields re-coerced from float back to int.
	var blob := RosterStore.migrate(4)
	var parsed = JSON.parse_string(JSON.stringify(blob))
	var v = RosterStore._validate(parsed)
	_ok(v != null, "roundtrip: valid blob validates")
	_eq((v["roster"] as Array).size(), 4, "roundtrip: 4 entries preserved")
	_eq(v["next_roster_id"], 5, "roundtrip: next_roster_id preserved")
	var e0: Dictionary = v["roster"][0]
	_eq(typeof(e0["roster_id"]), TYPE_INT, "roundtrip: roster_id re-coerced to int")
	_eq(typeof(e0["level"]), TYPE_INT, "roundtrip: level re-coerced to int")
	_eq(typeof(e0["max_hp"]), TYPE_INT, "roundtrip: max_hp re-coerced to int")
	_eq(typeof(v["next_roster_id"]), TYPE_INT, "roundtrip: next_roster_id int")
	_eq(e0["type_key"], "stoneward", "roundtrip: type_key preserved")
	# Garbage / wrong-version blobs are rejected (loader falls back to migrate).
	_eq(RosterStore._validate("not a dict"), null, "roundtrip: non-dict rejected")
	_eq(RosterStore._validate({"v": 1, "roster": []}), null, "roundtrip: wrong version rejected")
	_eq(RosterStore._validate({"v": 2}), null, "roundtrip: missing roster rejected")
```

- [ ] **Step 3: Run, verify FAIL**

Run: `pwsh -File godot/tests/run_tests.ps1`
Expected: FAIL — `_validate` stub returns `null` for the valid blob, so `v != null` and every field assert fails, EXIT 1.

- [ ] **Step 4: Implement `_validate` for real**

Replace the `_validate` stub body:

```gdscript
static func _validate(parsed) -> Variant:
	if typeof(parsed) != TYPE_DICTIONARY:
		return null
	if int(parsed.get("v", 0)) != 2:
		return null
	if typeof(parsed.get("roster")) != TYPE_ARRAY:
		return null
	var out := {"v": 2, "roster": [], "next_roster_id": int(parsed.get("next_roster_id", 1))}
	for e in parsed["roster"]:
		if typeof(e) != TYPE_DICTIONARY:
			return null
		var entry := {"roster_id": int(e.get("roster_id", 0))}
		for k in _CARRY_STR:
			entry[k] = String(e.get(k, ""))
		for k in _CARRY_INT:
			entry[k] = int(e.get(k, 0))
		entry["flying"] = bool(e.get("flying", false))
		(out["roster"] as Array).append(entry)
	return out
```

- [ ] **Step 5: Run, verify PASS**

Run: `pwsh -File godot/tests/run_tests.ps1`
Expected: PASS — `== N passed, 0 failed ==`, EXIT 0 (N ≈ +11 vs Task 3; total ≈ 1057 from the 998 baseline).

- [ ] **Step 6: Headless boot (insurance — no scene/autoload changed, but a new core script was added)**

Run: `godot --headless --path godot --quit-after 30 2>&1 | Select-String "SCRIPT ERROR|Parse Error|Failed to load"`
Expected: no matches (clean), EXIT 0.

- [ ] **Step 7: Commit**

```bash
git add godot/core/roster_store.gd godot/tests/run_tests.gd
git commit -m "[godot] P5.1 roster: campaign.v2 file I/O + load validation"
```

---

## Self-Review

**Spec coverage:**
- Module `core/roster_store.gd`, pure + I/O, modeled on SaveGame/SettingsStore → Tasks 1–4. ✓
- Storage `user://wraithspire_campaign.json`, blob `{v:2, roster, next_roster_id}`, roster-only → `SLOT_PATH` + `new_roster` (T1), I/O (T4). ✓
- Full-snapshot entry, carry fields kept / transient stripped / `roster_id` stamped → `entry_from_unit` + `_CARRY_*` (T1), asserted. ✓
- `new_roster / entry_from_unit / add_entry / remove_entry / clear` → T1. ✓
- `reconcile` (deployed-alive update / deployed-dead cull / fresh-survivor add / fresh-dead ignore; pure, blob untouched) → T2, all four cases asserted. ✓
- `migrate` (1 veteran/cleared act, grant table, built via Units helpers, evolved where L≥4, clamp) → T3, progress 0–4 + clamp asserted. ✓
- `load_or_init / save / reset / probe` + `_validate` int-coercion + corrupt/wrong-version fallback → T4. ✓
- Progress stays in `settings` (divergence) → honored: this module never reads/writes campaign_progress; `migrate` takes it as an arg. ✓
- Gates → harness after each task; headless boot in T4. ✓

**Placeholder scan:** none — every step has complete code, exact commands, expected output.

**Type consistency:** `RosterStore` API names identical across module + tests (`new_roster`/`entry_from_unit`/`add_entry`/`remove_entry`/`clear`/`reconcile`/`migrate`/`load_or_init`/`save`/`reset`/`probe`/`_validate`/`_update_entry`/`_build_veteran`); blob keys (`v`/`roster`/`next_roster_id`/`roster_id`) and `_CARRY_STR`/`_CARRY_INT`/`GRANT` consistent. `Units.make_unit(id,type_key,owner,q,r)`, `Units.apply_level_growth(u)`, `Units.evolve_unit(u)`, `Units.EVOLVE_LEVEL`, `UnitTypes.UNIT_TYPES[k]` match `core/units.gd` / `data/unit_types.gd`. Test counts are estimates (the gate only requires `0 failed`).

**Build-order note:** each task stubs the new symbol first so the harness compiles, writes the test, runs it RED, then implements GREEN — real TDD under GDScript's analyze-time static-call checking.
