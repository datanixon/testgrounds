# Four New Evolutions Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add evolved terminal-tier forms (Hexlord/Sigilwarden/Glaciamaw/Dunestalker) for the four newest base monsters, completing the "every base evolves" rule.

**Architecture:** Pure data-table extension in `data/unit_types.gd` (four evolved entries + `evolves_to` on the four bases). The evolution mechanic (`Units.evolve_unit`) already reads `evolves_to` — no logic change. Sprites are art-pending; a `PENDING_ART` skip keeps `_test_sprites` green until the 8 PNGs land.

**Tech Stack:** Godot 4 / GDScript. Harness: `godot/tests/run_tests.gd` (`_test_*` in `_initialize()`; `_eq`/`_ok`; `Units.make_unit`/`gain_xp`/`try_evolve`). Gate: `pwsh -File godot/tests/run_tests.ps1` (`== N passed, 0 failed ==`, EXIT 0; never `-ExecutionPolicy Bypass`). Indentation TABS.

**Spec:** `docs/superpowers/specs/2026-06-13-wraithspire-evolutions-design.md`

---

## File structure

| File | Responsibility | Task |
|---|---|---|
| `godot/tests/run_tests.gd` | `PENDING_ART` skip; size assert; new evolution tests | 1,2 |
| `godot/data/unit_types.gd` | 4 evolved entries + `evolves_to` wiring | 2 |

Two implementation tasks. The 8 sprite PNGs + import + `PENDING_ART` removal are a **deferred follow-up** (spec §"Deferred: the art task") — not in this plan.

---

### Task 1: Guard `_test_sprites` against art-pending stems

**Files:** Modify `godot/tests/run_tests.gd` (`_test_sprites`).

This must land **before** the new data (Task 2), because the new evolved entries introduce sprite ids with no PNG, and `_test_sprites` currently asserts every `UNIT_TYPES` sprite id loads. On its own this task changes nothing observable (no new stems yet) — the suite stays green.

- [ ] **Step 1: Read the current `_test_sprites`**

It begins (around line 1385):
```gdscript
func _test_sprites() -> void:
	# every distinct sprite id in UNIT_TYPES resolves a non-null token + battle texture
	for key in UnitTypes.UNIT_TYPES:
		var sid: String = UnitTypes.UNIT_TYPES[key]["sprite"]
		_ok(Sprites.token(sid, 0) is Texture2D, "sprites: token %s loads" % sid)
		_ok(Sprites.battle(sid, 0) is Texture2D, "sprites: battle %s loads" % sid)
```

- [ ] **Step 2: Add the skip set**

Replace that block with:
```gdscript
func _test_sprites() -> void:
	# every distinct sprite id in UNIT_TYPES resolves a non-null token + battle texture,
	# EXCEPT art-pending stems (P4.1 evolved forms whose PNGs are not generated yet).
	var pending_art := ["hexlord", "sigilwarden", "glaciamaw", "dunestalker"]
	for key in UnitTypes.UNIT_TYPES:
		var sid: String = UnitTypes.UNIT_TYPES[key]["sprite"]
		if sid in pending_art:
			continue
		_ok(Sprites.token(sid, 0) is Texture2D, "sprites: token %s loads" % sid)
		_ok(Sprites.battle(sid, 0) is Texture2D, "sprites: battle %s loads" % sid)
```

- [ ] **Step 3: Run the gate**

Run: `pwsh -File godot/tests/run_tests.ps1`
Expected: PASS — unchanged count (no new stems exist yet, so the skip set matches nothing).

- [ ] **Step 4: Commit**

```bash
git add godot/tests/run_tests.gd
git commit -m "[godot] P4.1 evolutions: PENDING_ART skip in _test_sprites"
```

---

### Task 2: Add the four evolved forms + wiring

**Files:**
- Modify: `godot/data/unit_types.gd`
- Modify: `godot/tests/run_tests.gd` (size assert + new evolution test)

- [ ] **Step 1: Register the new test**

In `_initialize()`, immediately after `_test_leveling()` add:
```gdscript
	_test_new_evolutions()
```

- [ ] **Step 2: Bump the count assert + write the failing tests**

In `_test_unit_types`, change the size assertion line (currently):
```gdscript
	_eq(UnitTypes.UNIT_TYPES.size(), 20, "unit_types: 20 entries")
```
to:
```gdscript
	_eq(UnitTypes.UNIT_TYPES.size(), 24, "unit_types: 24 entries")
```
(Leave the comment on the line above as-is or update freely; only the number matters.)

Append a new test at the END of `godot/tests/run_tests.gd`:
```gdscript
func _test_new_evolutions() -> void:
	# evolves_to wired on the four newest bases.
	_eq(UnitTypes.UNIT_TYPES["hexwisp"]["evolves_to"], "hexlord", "evo: hexwisp -> hexlord")
	_eq(UnitTypes.UNIT_TYPES["runeward"]["evolves_to"], "sigilwarden", "evo: runeward -> sigilwarden")
	_eq(UnitTypes.UNIT_TYPES["frostmaw"]["evolves_to"], "glaciamaw", "evo: frostmaw -> glaciamaw")
	_eq(UnitTypes.UNIT_TYPES["duneskink"]["evolves_to"], "dunestalker", "evo: duneskink -> dunestalker")
	# evolved entries exist with the evolved flag, lineage element, and the base's ability.
	for id in ["hexlord", "sigilwarden", "glaciamaw", "dunestalker"]:
		_ok(UnitTypes.UNIT_TYPES.has(id), "evo: %s defined" % id)
		_eq(UnitTypes.UNIT_TYPES[id]["evolved"], true, "evo: %s evolved flag" % id)
	_eq(UnitTypes.UNIT_TYPES["hexlord"]["element"], "arcane", "evo: hexlord arcane")
	_eq(UnitTypes.UNIT_TYPES["hexlord"]["flying"], true, "evo: hexlord flying")
	_eq(UnitTypes.UNIT_TYPES["hexlord"]["ability"], "blink", "evo: hexlord keeps blink")
	_eq(UnitTypes.UNIT_TYPES["glaciamaw"]["power"], 14, "evo: glaciamaw power")
	# evolved forms are NOT summonable.
	_eq(UnitTypes.SUMMON_LIST.size(), 12, "evo: summon list unchanged (12)")
	for id in ["hexlord", "sigilwarden", "glaciamaw", "dunestalker"]:
		_ok(not (id in UnitTypes.SUMMON_LIST), "evo: %s not summonable" % id)
	# behavior: a level-4 hexwisp on an owned tower evolves to hexlord, absorbing growth.
	var h := Units.make_unit(101, "hexwisp", 0, 0, 0)
	Units.gain_xp(h, 12 + 20 + 28)   # level 1 -> 4
	_eq(h["level"], 4, "evo: hexwisp at level 4")
	_ok(Units.try_evolve(h, {"terrain": "tower", "owner": 0}), "evo: hexwisp evolves on owned tower")
	_eq(h["type_key"], "hexlord", "evo: became hexlord")
	_eq(h["evolved"], true, "evo: hexlord evolved flag set")
	_eq(h["hp"], h["max_hp"], "evo: full restore on evolve")
	# spot-check a second line on an owned castle.
	var d := Units.make_unit(102, "duneskink", 0, 0, 0)
	Units.gain_xp(d, 12 + 20 + 28)
	_ok(Units.try_evolve(d, {"terrain": "castle", "owner": 0}), "evo: duneskink evolves on owned castle")
	_eq(d["type_key"], "dunestalker", "evo: became dunestalker")
```

- [ ] **Step 3: Run the gate, verify FAIL**

Run: `pwsh -File godot/tests/run_tests.ps1`
Expected: FAIL — `unit_types: 24 entries` (still 20) and the `evolves_to`/evolved-entry asserts (keys absent).

- [ ] **Step 4: Add the data**

In `godot/data/unit_types.gd`:

(a) Add `"evolves_to"` to the four base entries. Change each line as follows (add the key right before the closing `}` of the dict, matching the existing-base style where `evolves_to` precedes `ability`):

`hexwisp` — change the trailing `..."attack": "bolt",  "ability": "blink"}` to:
```gdscript
..."attack": "bolt",  "evolves_to": "hexlord",     "ability": "blink"},
```
`runeward` — `..."attack": "melee", "ability": "ward"}` to:
```gdscript
..."attack": "melee", "evolves_to": "sigilwarden", "ability": "ward"},
```
`frostmaw` — `..."attack": "melee", "ability": "frostBite"}` to:
```gdscript
..."attack": "melee", "evolves_to": "glaciamaw",   "ability": "frostBite"},
```
`duneskink` — `..."attack": "melee", "ability": "skitter"}` to:
```gdscript
..."attack": "melee", "evolves_to": "dunestalker", "ability": "skitter"},
```
(Keep each line's leading content/stats exactly as they are; only insert the `"evolves_to": "<id>",` key before `"ability"`.)

(b) Add the four evolved entries. After the existing evolved block (after the `"skytyrant": {...}` line) and before the `# New base monsters` comment, insert:
```gdscript
	# Evolved forms for the four newest bases (P4.1; sprites art-pending)
	"hexlord":     {"name": "Hexlord",     "element": "arcane", "max_hp": 19, "move": 5, "range": 2, "power": 9,  "def": 2, "cost": 20, "flying": true,  "sprite": "hexlord",     "attack": "bolt",  "evolved": true, "ability": "blink"},
	"sigilwarden": {"name": "Sigilwarden", "element": "arcane", "max_hp": 38, "move": 2, "range": 1, "power": 10, "def": 7, "cost": 30, "flying": false, "sprite": "sigilwarden", "attack": "melee", "evolved": true, "ability": "ward"},
	"glaciamaw":   {"name": "Glaciamaw",   "element": "hydro",  "max_hp": 40, "move": 3, "range": 1, "power": 14, "def": 5, "cost": 34, "flying": false, "sprite": "glaciamaw",   "attack": "melee", "evolved": true, "ability": "frostBite"},
	"dunestalker": {"name": "Dunestalker", "element": "terra",  "max_hp": 23, "move": 5, "range": 1, "power": 10, "def": 3, "cost": 16, "flying": false, "sprite": "dunestalker", "attack": "melee", "evolved": true, "ability": "skitter"},
```

- [ ] **Step 5: Run the gate, verify PASS**

Run: `pwsh -File godot/tests/run_tests.ps1`
Expected: PASS — `== N passed, 0 failed ==` (+~22). `_test_sprites` stays green (the four new stems are in `pending_art`). `_test_unit_types` size assert now 24.

- [ ] **Step 6: Headless boot (cheap insurance — data feeds scenes)**

Run: `godot --headless --path godot --quit-after 30 2>&1 | Select-String "SCRIPT ERROR|Parse Error|Failed to load"`
Expected: no matches.

- [ ] **Step 7: Commit**

```bash
git add godot/data/unit_types.gd godot/tests/run_tests.gd
git commit -m "[godot] P4.1 evolutions: 4 evolved forms + evolves_to wiring"
```

---

### Task 3: Review + roadmap check-off

**Files:** docs only.

- [ ] **Step 1: Quick code review** of `git diff main...godot-p4-1-evolutions -- godot/` (a `caveman:cavecrew-reviewer` over the small diff): confirm the four evolved stat blocks are balanced vs the existing evolved tier, `evolves_to` ids match the new entry keys exactly, the dicts are well-formed (no trailing-comma/brace errors), and `SUMMON_LIST` is unchanged.

- [ ] **Step 2: Both gates** one final time: `pwsh -File godot/tests/run_tests.ps1` → green; headless boot → no matches.

- [ ] **Step 3: Roadmap + handoff.** Note in `ROADMAP2.md` that 4.1's **data** is done and the **art (8 PNGs) is pending** (leave 4.1 unchecked or mark it "data done / art pending" — it's not fully complete until the sprites land). Update `SESSION_STATE.md` + `HANDOFF.md` (4.1 data on branch; the generation prompt is in the spec appendix; art-import follow-up steps). Update auto-memory. Commit. FF-merge to `main` + push only after the user approves.

- [ ] **Step 4: Windowed pass** (`godot --path godot`): evolve a hexwisp/duneskink (level a summoned unit to 4 on an owned spire) → it changes type/stats and renders the engine base-disc (no creature art yet — expected until the PNGs land). No errors.

---

## Self-review

**Spec coverage:**
- 4 evolved entries with mirrored stats → Task 2 (data + asserts). ✓
- `evolves_to` on the 4 bases → Task 2. ✓
- Evolution mechanic unchanged; behavior verified → Task 2 (`try_evolve` test). ✓
- `SUMMON_LIST` unchanged + evolved not summonable → Task 2 (asserts). ✓
- `_test_sprites` `PENDING_ART` skip → Task 1. ✓
- Sprites code unchanged (id-based, graceful null) → no task needed. ✓
- Art generation + import → deferred follow-up (spec §Deferred); explicitly out of this plan. ✓

**Placeholder scan:** none — full stat blocks, exact test code, exact dict edits.

**Type consistency:** evolved ids (`hexlord`/`sigilwarden`/`glaciamaw`/`dunestalker`) are identical across the `evolves_to` values, the new `UNIT_TYPES` keys, the `sprite` stems, the `PENDING_ART` set, and every test assertion. Stats in the data match the asserted spot-checks (`glaciamaw.power == 14`, `hexlord` arcane/flying/blink).
