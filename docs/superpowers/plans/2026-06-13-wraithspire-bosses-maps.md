# Bosses + Maps Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add two new skirmish maps (one fog-default) and two non-summonable boss monsters (Pyre Colossus, Storm Tyrant), with one boss demo'd in campaign mission 4.

**Architecture:** Pure data extensions: two `Maps.MAPS` entries, two `UNIT_TYPES` entries (kept out of `SUMMON_LIST`, reusing existing abilities), and one `ai_summons` addition. No new combat/render code; the title selector and map-gen already read the data generically. Boss sprites are art-pending (a `pending_art` skip keeps `_test_sprites` green).

**Tech Stack:** Godot 4 / GDScript. Harness: `godot/tests/run_tests.gd` (`_test_*` in `_initialize()`; `_eq`/`_ok`; `GameState.new_campaign(Campaign.CAMPAIGN[i], i)`; `Abilities`/`Campaign`/`UnitTypes`/`Maps` preloaded). Gate: `pwsh -File godot/tests/run_tests.ps1` (`== N passed, 0 failed ==`, EXIT 0; never `-ExecutionPolicy Bypass`). Indentation TABS.

**Spec:** `docs/superpowers/specs/2026-06-13-wraithspire-bosses-maps-design.md`

---

## File structure

| File | Responsibility | Task |
|---|---|---|
| `godot/tests/run_tests.gd` | `pending_art` boss stems; `_test_data` map count; `_test_bosses` | 1,2,3 |
| `godot/data/maps.gd` | 2 new skirmish maps | 2 |
| `godot/data/unit_types.gd` | 2 boss entries | 3 |
| `godot/data/campaign.gd` | boss in mission 4 `ai_summons` | 3 |

Three implementation tasks. The 4 boss sprite PNGs + import + `pending_art` removal are a **deferred follow-up** (spec §Deferred) — not in this plan.

---

### Task 1: Guard `_test_sprites` for the art-pending boss stems

**Files:** Modify `godot/tests/run_tests.gd` (`_test_sprites`).

Must land before the boss data (Task 3) — the new boss `sprite` ids have no PNG yet.

- [ ] **Step 1: Extend the skip set**

In `_test_sprites`, the line currently reads:
```gdscript
	var pending_art := ["hexlord", "sigilwarden", "glaciamaw", "dunestalker"]
```
Change it to:
```gdscript
	var pending_art := ["hexlord", "sigilwarden", "glaciamaw", "dunestalker", "pyre_colossus", "storm_tyrant"]
```

- [ ] **Step 2: Run the gate**

Run: `pwsh -File godot/tests/run_tests.ps1`
Expected: PASS — unchanged count (no boss stems exist yet, so the two new entries match nothing).

- [ ] **Step 3: Commit**

```bash
git add godot/tests/run_tests.gd
git commit -m "[godot] P4.3 bosses+maps: PENDING_ART += boss stems"
```

---

### Task 2: Two new skirmish maps

**Files:**
- Modify: `godot/data/maps.gd`
- Modify: `godot/tests/run_tests.gd` (`_test_data`)

- [ ] **Step 1: Bump the count + add map asserts (failing)**

In `_test_data`, change:
```gdscript
	_eq(Maps.MAPS.size(), 4, "maps: 4 skirmish")
```
to:
```gdscript
	_eq(Maps.MAPS.size(), 6, "maps: 6 skirmish")
```
Then, immediately after the existing `_eq(Maps.MAPS[2]["weather_table"], ...)` line (the last `Maps.MAPS[...]` assert in `_test_data`), add:
```gdscript
	_eq(Maps.MAPS[4]["key"], "mistveil", "maps: [4] key")
	_eq(Maps.MAPS[4]["fog"], true, "maps: mistveil fog-default")
	_eq(Maps.MAPS[5]["key"], "ashfall", "maps: [5] key")
	_eq(Maps.MAPS[5]["weather_table"], ["heat", "heat", "gale", "clear"], "maps: ashfall weather")
```

- [ ] **Step 2: Run the gate, verify FAIL**

Run: `pwsh -File godot/tests/run_tests.ps1`
Expected: FAIL — `maps: 6 skirmish` (still 4).

- [ ] **Step 3: Add the maps**

In `godot/data/maps.gd`, the `MAPS` array's last entry is `verdant` ending with `..."towers": 6, "relics": 3},` followed by the closing `]`. Insert the two new entries between the `verdant` entry and the closing `]`:
```gdscript
	{"key": "mistveil", "name": "Mistveil Hollow", "desc": "Fog-shrouded woods.",
	 "cols": 15, "rows": 12, "seed": -1, "mountains": 2, "lakes": 3, "forests": 34, "hills": 10,
	 "towers": 5, "relics": 2, "fog": true},
	{"key": "ashfall", "name": "Ashfall Basin", "desc": "Volcanic crags, ash winds.",
	 "cols": 15, "rows": 11, "seed": -1, "mountains": 8, "lakes": 1, "forests": 6, "hills": 22,
	 "towers": 4, "weather_table": ["heat", "heat", "gale", "clear"], "relics": 2},
```

- [ ] **Step 4: Run the gate, verify PASS**

Run: `pwsh -File godot/tests/run_tests.ps1`
Expected: PASS — `== N passed, 0 failed ==` (+5). The title map selector now lists 6 maps (it reads `Maps.MAPS.size()`).

- [ ] **Step 5: Headless boot** (map data feeds map-gen / the title selector)

Run: `godot --headless --path godot --quit-after 30 2>&1 | Select-String "SCRIPT ERROR|Parse Error|Failed to load"`
Expected: no matches.

- [ ] **Step 6: Commit**

```bash
git add godot/data/maps.gd godot/tests/run_tests.gd
git commit -m "[godot] P4.3 bosses+maps: 2 new skirmish maps (mistveil fog-default + ashfall)"
```

---

### Task 3: Two bosses + mission-4 demo

**Files:**
- Modify: `godot/data/unit_types.gd`
- Modify: `godot/data/campaign.gd`
- Modify: `godot/tests/run_tests.gd` (`_test_bosses`, register)

- [ ] **Step 1: Register the test**

In `_initialize()`, immediately after `_test_new_evolutions()` add:
```gdscript
	_test_bosses()
```

- [ ] **Step 2: Write the failing test**

Append to `godot/tests/run_tests.gd`:
```gdscript
func _test_bosses() -> void:
	_eq(UnitTypes.UNIT_TYPES.size(), 26, "bosses: 26 unit types")
	for id in ["pyre_colossus", "storm_tyrant"]:
		_ok(UnitTypes.UNIT_TYPES.has(id), "bosses: %s defined" % id)
		_eq(UnitTypes.UNIT_TYPES[id]["boss"], true, "bosses: %s boss flag" % id)
		_ok(not (id in UnitTypes.SUMMON_LIST), "bosses: %s not summonable" % id)
		_ok(Abilities.ABILITIES.has(UnitTypes.UNIT_TYPES[id]["ability"]), "bosses: %s ability exists" % id)
	_eq(UnitTypes.UNIT_TYPES["pyre_colossus"]["power"], 16, "bosses: pyre_colossus power")
	_eq(UnitTypes.UNIT_TYPES["pyre_colossus"]["ability"], "quake", "bosses: pyre_colossus quake")
	_eq(UnitTypes.UNIT_TYPES["storm_tyrant"]["flying"], true, "bosses: storm_tyrant flying")
	_eq(UnitTypes.UNIT_TYPES["storm_tyrant"]["ability"], "diveMark", "bosses: storm_tyrant diveMark")
	_eq(UnitTypes.SUMMON_LIST.size(), 12, "bosses: summon list still 12")
	# mission 4 fields the boss; new_campaign pre-places it for the AI (owner 1).
	_ok("pyre_colossus" in Campaign.CAMPAIGN[3]["ai_summons"], "bosses: mission 4 ai_summons has the boss")
	var gs := GameState.new_campaign(Campaign.CAMPAIGN[3], 3)
	var found := false
	for u in gs.units:
		if u["type_key"] == "pyre_colossus" and u["owner"] == 1:
			found = true
	_ok(found, "bosses: new_campaign spawns the boss for the AI")
```

- [ ] **Step 3: Run the gate, verify FAIL**

Run: `pwsh -File godot/tests/run_tests.ps1`
Expected: FAIL — `bosses: 26 unit types` (still 24) and the missing boss entries.

- [ ] **Step 4: Add the boss entries**

In `godot/data/unit_types.gd`, the `UNIT_TYPES` dict's final entries are the four P4.1 evolved forms (ending with the `"dunestalker": {...}` line), then the closing `}`. Insert the two boss entries after the last entry (`dunestalker`) and before the closing `}` (ensure the `dunestalker` line keeps its trailing comma):
```gdscript
	# Bosses (P4.3; non-summonable, pre-placed only; reuse existing abilities; sprites art-pending)
	"pyre_colossus": {"name": "Pyre Colossus", "element": "pyro",   "max_hp": 52, "move": 2, "range": 1, "power": 16, "def": 6, "cost": 40, "flying": false, "sprite": "pyre_colossus", "attack": "melee", "ability": "quake",    "boss": true},
	"storm_tyrant":  {"name": "Storm Tyrant",  "element": "zephyr", "max_hp": 40, "move": 4, "range": 2, "power": 14, "def": 4, "cost": 38, "flying": true,  "sprite": "storm_tyrant",  "attack": "dive",  "ability": "diveMark", "boss": true},
```

- [ ] **Step 5: Field the boss in mission 4**

In `godot/data/campaign.gd`, the fourth mission ("The Wraithspire", index 3) has the line:
```gdscript
	 "ai_mp_bonus": 10, "ai_summons": ["geomaul", "skyharrow"],
```
Change it to:
```gdscript
	 "ai_mp_bonus": 10, "ai_summons": ["geomaul", "skyharrow", "pyre_colossus"],
```

- [ ] **Step 6: Run the gate, verify PASS**

Run: `pwsh -File godot/tests/run_tests.ps1`
Expected: PASS — `== N passed, 0 failed ==` (+~14). `_test_sprites` stays green (boss stems are in `pending_art`); `SUMMON_LIST` still 12.

- [ ] **Step 7: Headless boot**

Run: `godot --headless --path godot --quit-after 30 2>&1 | Select-String "SCRIPT ERROR|Parse Error|Failed to load"`
Expected: no matches.

- [ ] **Step 8: Commit**

```bash
git add godot/data/unit_types.gd godot/data/campaign.gd godot/tests/run_tests.gd
git commit -m "[godot] P4.3 bosses+maps: Pyre Colossus + Storm Tyrant + mission-4 demo"
```

---

### Task 4: Review + roadmap check-off

**Files:** docs only.

- [ ] **Step 1: Quick review** of `git diff main...godot-p4-3-bosses-maps -- godot/` (a `caveman:cavecrew-reviewer`): the two boss dicts are well-formed (all keys, valid braces/commas), reuse abilities that exist, are absent from `SUMMON_LIST`, and have top-tier stats; the two map dicts are well-formed; `pyre_colossus` is in mission 4's `ai_summons`.

- [ ] **Step 2: Both gates** one final time: `pwsh -File godot/tests/run_tests.ps1` → green; headless boot → no matches.

- [ ] **Step 3: `--shot` visual check.** Capture the title (the new maps appear in the selector — `godot --path godot -- --shot title`) and, optionally, add a `mission4` shot target to `scenes/main.gd` `_run_shot` (`session.start_campaign(3); _route()`) to see the boss on the board (engine disc until art). Read the PNGs.

- [ ] **Step 4: Roadmap + handoff.** Mark ROADMAP2 4.3 **data done / art pending** (4 boss PNGs); update `SESSION_STATE.md` + `HANDOFF.md` (4.3 data on branch; generation prompt in the spec appendix; art-import follow-up). Update auto-memory. Commit. FF-merge to `main` + push only after the user approves.

---

## Self-review

**Spec coverage:**
- 2 new maps (one fog-default) → Task 2. ✓
- Title selector auto-lists them → no code (reads `MAPS.size()`); verified in Task 4 shot. ✓
- 2 boss entries, non-summonable, reuse abilities, `boss` flag, top-tier stats → Task 3. ✓
- Boss demo in mission 4 `ai_summons` + spawn verification → Task 3. ✓
- `pending_art` skip for boss sprites → Task 1. ✓
- No new combat/render code → confirmed (reused abilities, id-based sprites). ✓
- Art generation + import → deferred follow-up (spec §Deferred); out of this plan. ✓

**Placeholder scan:** none — full map dicts, full boss dicts, exact test code.

**Type consistency:** boss ids (`pyre_colossus`/`storm_tyrant`) identical across `UNIT_TYPES` keys, `sprite` stems, `pending_art`, the mission-4 `ai_summons`, and every assert. Map keys (`mistveil`/`ashfall`) consistent across the def and the `_test_data` asserts. Abilities referenced (`quake`/`diveMark`) exist in `Abilities.ABILITIES` and are asserted to. `MAPS.size()` 6 / `UNIT_TYPES.size()` 26 match the additions.
