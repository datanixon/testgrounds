# Phase 5.3 Missions 5–8 (Titans Awakened) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Extend the campaign from 4 to 8 missions with a "titans awakened" arc that exercises the objective framework (rout/seize/protect), the bosses, and fog, ending in a dual-titan finale.

**Architecture:** Mostly data — four new `CAMPAIGN` scenario dicts. Two objectives that can't be static data (seize a known hex, protect a placed ally) are built at runtime by two small `new_campaign` flags (`seize_enemy_castle`, `protect_ally`). The campaign-list screen shrinks its rows to fit 8 missions.

**Tech Stack:** Godot 4 / GDScript. Harness `godot/tests/run_tests.gd` (`_test_*` in `_initialize()`; `_eq`/`_ok`; preloads `Campaign`, `GameState`, `UnitTypes`, `Objectives`, `Deploy`, `AI`). Gate: `pwsh -File godot/tests/run_tests.ps1` (`== N passed, 0 failed ==`, EXIT 0; never `-ExecutionPolicy Bypass`). Indentation TABS.

---

## File Structure

| File | Responsibility | Task |
|---|---|---|
| `godot/data/campaign.gd` | 4 new scenario dicts (`CAMPAIGN` 4→8) | 1 |
| `godot/core/game_state.gd` | `new_campaign` seize/protect objective wiring | 2 |
| `godot/scenes/campaign/campaign_scene.gd` | row-fit for 8 missions + subtitle | 3 |
| `godot/tests/run_tests.gd` | `_test_missions_5_8` (data) + `_test_missions_objectives` (wiring) | 1,2 |

Three tasks. Task 1 lands the data first (so Task 2's tests have real entries). Task 2 is TDD (RED before the wiring exists). Task 3 is render-layer (headless boot + `--shot campaign`).

---

## Task 1: Four new campaign scenarios + data tests

**Files:**
- Modify: `godot/data/campaign.gd`
- Modify: `godot/tests/run_tests.gd`

- [ ] **Step 1: Append the four scenarios to `CAMPAIGN`**

In `godot/data/campaign.gd`, add these four dicts to the `CAMPAIGN` array, after the existing mission-4 ("The Wraithspire") entry and before the closing `]`:

```gdscript
	{"name": "The First Tremor", "difficulty": "hard", "deploy_slots": 5,
	 "map": {"key": "c5", "name": "The First Tremor", "desc": "", "cols": 15, "rows": 11, "seed": 52107,
	         "mountains": 8, "lakes": 1, "forests": 6, "hills": 22, "towers": 4, "relics": 2,
	         "weather_table": ["heat", "heat", "gale", "clear"], "objective": {"kind": "rout"}},
	 "ai_mp_bonus": 10, "ai_summons": ["pyre_colossus", "geomaul"],
	 "intro": ["The Wraithspire is yours — and that was the mistake.", "Its fall split the deep seals. Stone screams; the",
	           "Pyre Colossus drags itself into the light.", "Break its host. Leave nothing standing."]},
	{"name": "The Storm Crown", "difficulty": "hard", "deploy_slots": 5, "seize_enemy_castle": true,
	 "map": {"key": "c6", "name": "The Storm Crown", "desc": "", "cols": 15, "rows": 12, "seed": 60733,
	         "mountains": 4, "lakes": 2, "forests": 10, "hills": 16, "towers": 5, "relics": 2,
	         "weather_table": ["gale", "gale", "rain", "clear"]},
	 "ai_mp_bonus": 12, "ai_summons": ["storm_tyrant", "skyharrow"],
	 "intro": ["The Storm Tyrant roosts on the high spire and the", "winds answer it. While that crown stands, the sky",
	           "is theirs. Take the spire — seize the enemy seat", "and the storm has nowhere left to land."]},
	{"name": "The Last Refuge", "difficulty": "hard", "deploy_slots": 6, "protect_ally": "runeward",
	 "map": {"key": "c7", "name": "The Last Refuge", "desc": "", "cols": 15, "rows": 12, "seed": 71519,
	         "mountains": 2, "lakes": 3, "forests": 34, "hills": 10, "towers": 5, "relics": 2, "fog": true},
	 "ai_mp_bonus": 12, "ai_summons": ["geomaul", "skyharrow"],
	 "intro": ["The last free warden holds the misted wood, and", "everything the titans drove out shelters behind it.",
	           "Keep the warden alive. If the Runeward falls,", "the refuge falls — and the realm with it."]},
	{"name": "The Titanfall", "difficulty": "hard", "deploy_slots": 6,
	 "map": {"key": "c8", "name": "The Titanfall", "desc": "", "cols": 16, "rows": 13, "seed": 80021,
	         "mountains": 5, "lakes": 2, "forests": 18, "hills": 16, "towers": 6, "relics": 3,
	         "weather_table": ["heat", "gale", "rain", "clear"]},
	 "ai_mp_bonus": 14, "ai_summons": ["pyre_colossus", "storm_tyrant"],
	 "intro": ["Both titans, one field, and the thing that woke", "them waiting behind. There is no clever path left —",
	           "only your veterans and the ground you choose.", "End it. Put the seals back with their maker."]},
```

- [ ] **Step 2: Register + write the data test**

In `godot/tests/run_tests.gd` `_initialize()`, after `_test_deploy_reconcile_on_win()`:

```gdscript
	_test_missions_5_8()
```

Add the test function:

```gdscript
func _test_missions_5_8() -> void:
	_eq(Campaign.CAMPAIGN.size(), 8, "campaign: 8 missions")
	for i in [4, 5, 6, 7]:
		var sc: Dictionary = Campaign.CAMPAIGN[i]
		_ok(sc.has("name") and String(sc["name"]) != "", "campaign %d: has name" % i)
		_eq(sc["difficulty"], "hard", "campaign %d: hard" % i)
		_ok(int(sc.get("deploy_slots", 0)) > 0, "campaign %d: has deploy_slots" % i)
		var m: Dictionary = sc["map"]
		_ok(m.has("seed") and m.has("cols") and m.has("rows"), "campaign %d: map seed/dims" % i)
		_ok((sc.get("intro", []) as Array).size() >= 1, "campaign %d: has intro" % i)
	_eq(Deploy.slots_for(Campaign.CAMPAIGN[4]), 5, "campaign m5: slots 5")
	_eq(Deploy.slots_for(Campaign.CAMPAIGN[5]), 5, "campaign m6: slots 5")
	_eq(Deploy.slots_for(Campaign.CAMPAIGN[6]), 6, "campaign m7: slots 6")
	_eq(Deploy.slots_for(Campaign.CAMPAIGN[7]), 6, "campaign m8: slots 6")
	_eq(UnitTypes.UNIT_TYPES["pyre_colossus"].get("boss", false), true, "pyre_colossus is boss")
	_eq(UnitTypes.UNIT_TYPES["storm_tyrant"].get("boss", false), true, "storm_tyrant is boss")
	_ok(UnitTypes.UNIT_TYPES.has("runeward"), "runeward exists (protect ally)")
	_eq(Campaign.CAMPAIGN[4]["map"].get("objective", {}).get("kind", ""), "rout", "m5: rout objective")
	_eq(Campaign.CAMPAIGN[7]["map"].has("objective"), false, "m8: no static objective")
	_ok("pyre_colossus" in Campaign.CAMPAIGN[4]["ai_summons"], "m5 summons pyre_colossus")
	_ok("storm_tyrant" in Campaign.CAMPAIGN[5]["ai_summons"], "m6 summons storm_tyrant")
	_ok("pyre_colossus" in Campaign.CAMPAIGN[7]["ai_summons"] and "storm_tyrant" in Campaign.CAMPAIGN[7]["ai_summons"], "m8 summons both titans")
	_eq(Campaign.CAMPAIGN[5].get("seize_enemy_castle", false), true, "m6: seize_enemy_castle flag")
	_eq(Campaign.CAMPAIGN[6].get("protect_ally", ""), "runeward", "m7: protect_ally runeward")
```

- [ ] **Step 3: Run, verify PASS**

Run: `pwsh -File godot/tests/run_tests.ps1`
Expected: PASS — `== N passed, 0 failed ==`, EXIT 0 (N ≈ +24 vs the 1112 baseline). (Pure data addition: the test passes once the scenarios exist; the assertions are the regression guard.)

- [ ] **Step 4: Headless boot (campaign data feeds scenes)**

Run: `godot --headless --path godot --quit-after 30 2>&1 | Select-String "SCRIPT ERROR|Parse Error|Failed to load"`
Expected: no matches.

- [ ] **Step 5: Commit**

```bash
git add godot/data/campaign.gd godot/tests/run_tests.gd
git commit -m "[godot] P5.3 missions 5-8: 4 titan-arc scenarios + data tests"
```

---

## Task 2: `new_campaign` seize + protect objective wiring

**Files:**
- Modify: `godot/core/game_state.gd`
- Modify: `godot/tests/run_tests.gd`

- [ ] **Step 1: Register + write the failing test**

In `godot/tests/run_tests.gd` `_initialize()`, after `_test_missions_5_8()`:

```gdscript
	_test_missions_objectives()
```

Add the test function:

```gdscript
func _test_missions_objectives() -> void:
	# m5: static rout objective survives into the state; boss pre-placed for AI.
	var g5 := GameState.new_campaign(Campaign.CAMPAIGN[4], 4)
	_eq(g5.objective.get("kind", ""), "rout", "m5 state: rout objective")
	var has_boss := false
	for u in g5.units:
		if u["owner"] == 1 and u["type_key"] == "pyre_colossus":
			has_boss = true
	_eq(has_boss, true, "m5 state: pyre_colossus pre-placed for AI")
	# m6: seize objective built from the enemy castle.
	var g6 := GameState.new_campaign(Campaign.CAMPAIGN[5], 5)
	_eq(g6.objective.get("kind", ""), "seize", "m6 state: seize objective")
	var c1: Vector2i = g6.map["castles"][1]
	_eq(g6.objective["q"], c1.x, "m6: seize q = enemy castle q")
	_eq(g6.objective["r"], c1.y, "m6: seize r = enemy castle r")
	var m1 = g6.master_of(1)
	_eq(Vector2i(m1["q"], m1["r"]), c1, "m6: enemy master spawns on the seize hex")
	# m7: protect ally spawned for player 0; objective points at it; evaluate alive vs dead.
	var g7 := GameState.new_campaign(Campaign.CAMPAIGN[6], 6)
	_eq(g7.objective.get("kind", ""), "protect", "m7 state: protect objective")
	var pid: int = int(g7.objective["unit_id"])
	var ally = g7.unit_by_id(pid)
	_ok(ally != null, "m7: protect ally exists")
	_eq(ally["owner"], 0, "m7: protect ally is player 0")
	_eq(ally["type_key"], "runeward", "m7: protect ally is runeward")
	_eq(ally["is_master"], false, "m7: protect ally not a master")
	_eq(Objectives.evaluate(g7), -1, "m7: protect undecided while ally lives")
	ally["hp"] = 0
	_eq(Objectives.evaluate(g7), 1, "m7: player loses if ally dies")
	# m8: no objective (archon-kill finale); both titans pre-placed for AI.
	var g8 := GameState.new_campaign(Campaign.CAMPAIGN[7], 7)
	_eq(g8.objective.is_empty(), true, "m8 state: no objective (archon-kill)")
	var titans := 0
	for u in g8.units:
		if u["owner"] == 1 and (u["type_key"] == "pyre_colossus" or u["type_key"] == "storm_tyrant"):
			titans += 1
	_eq(titans, 2, "m8 state: both titans pre-placed for AI")
```

- [ ] **Step 2: Run, verify FAIL**

Run: `pwsh -File godot/tests/run_tests.ps1`
Expected: FAIL — `new_campaign` doesn't yet build the seize/protect objectives, so m6's objective is empty (`"seize"` assert fails) and m7 has no ally (`protect` assert / `ally != null` fail), EXIT 1.

- [ ] **Step 3: Add the seize + protect wiring to `new_campaign`**

In `godot/core/game_state.gd`, in `new_campaign`, insert the following just before the final `return gs` (after the existing `ai_summons` placement loop):

```gdscript
	if scenario.get("seize_enemy_castle", false):
		var c1: Vector2i = gs.map["castles"][1]
		gs.objective = {"kind": "seize", "q": c1.x, "r": c1.y}
	var ally_key: String = scenario.get("protect_ally", "")
	if ally_key != "":
		var m0 = gs.master_of(0)
		if m0 != null:
			var slot = AILib.find_summon_slot(gs, m0)
			if slot != null:
				var ally := gs.spawn_unit(ally_key, 0, slot.x, slot.y)
				ally["acted"] = false
				gs.objective = {"kind": "protect", "unit_id": ally["id"]}
```

(`AILib` is the alias `new_campaign` already uses for the global `AI` class — the
existing `ai_summons` loop calls `AILib.find_summon_slot(gs, m1)`. The seize/protect
override replaces whatever `objective` the map def carried; m6 and m7 omit a static
`objective`. The protect ally spawns `acted = false` so the player can move it turn 1.)

- [ ] **Step 4: Run, verify PASS**

Run: `pwsh -File godot/tests/run_tests.ps1`
Expected: PASS — `== N passed, 0 failed ==`, EXIT 0 (N ≈ +14 vs Task 1).

- [ ] **Step 5: Headless boot (game_state changed)**

Run: `godot --headless --path godot --quit-after 30 2>&1 | Select-String "SCRIPT ERROR|Parse Error|Failed to load"`
Expected: no matches.

- [ ] **Step 6: Commit**

```bash
git add godot/core/game_state.gd godot/tests/run_tests.gd
git commit -m "[godot] P5.3 missions 5-8: new_campaign seize-castle + protect-ally objectives"
```

---

## Task 3: Campaign screen fits 8 missions

**Files:**
- Modify: `godot/scenes/campaign/campaign_scene.gd`

- [ ] **Step 1: Shrink the rows so 8 fit in-canvas**

In `godot/scenes/campaign/campaign_scene.gd` `_row_rects`, change the sizing line and the row `y` origin. Replace:

```gdscript
	var w := 720.0; var h := 70.0; var gap := 16.0
	var x := (CW - w) / 2.0
	var out: Array = []
	for i in range(Campaign.CAMPAIGN.size()):
		out.append({"index": i, "r": Rect2(x, 170 + i * (h + gap), w, h)})
```

with:

```gdscript
	var w := 720.0; var h := 52.0; var gap := 10.0
	var x := (CW - w) / 2.0
	var out: Array = []
	for i in range(Campaign.CAMPAIGN.size()):
		out.append({"index": i, "r": Rect2(x, 150 + i * (h + gap), w, h)})
```

(8 rows now span y 150 → 646, clear of the footer at `CH - 40 = 760`.)

- [ ] **Step 2: Move the per-row text inside the shorter rows**

In `_draw`, the four per-row `draw_string` calls use `r.position.y + 28` (the
title/badge baseline) and `r.position.y + 48` (the teaser/difficulty baseline).
Change every `+ 28` to `+ 22` and every `+ 48` to `+ 42` in those four calls
(the mission-name line, the teaser line, the badge line, the difficulty line).
For example the mission-name line becomes:

```gdscript
		draw_string(fnt, Vector2(r.position.x + 18, r.position.y + 22), "%d.  %s" % [i + 1, sc["name"]], HORIZONTAL_ALIGNMENT_LEFT, -1, 16, Pal.GOLD if unlocked else Pal.INK_FAINT)
```

and the teaser line becomes `r.position.y + 42`; likewise the badge (`+ 22`) and
difficulty (`+ 42`) lines on the right.

- [ ] **Step 3: Update the subtitle for the 8-mission arc**

In `_draw`, change the subtitle string. Replace:

```gdscript
	draw_string(fnt, Vector2(CW / 2 - 300, 116), "— the fall of the crimson archon, in four battles —", HORIZONTAL_ALIGNMENT_CENTER, 600, 11, Pal.INK_DIM)
```

with:

```gdscript
	draw_string(fnt, Vector2(CW / 2 - 300, 116), "— the fall of the crimson archon, and the war of titans after —", HORIZONTAL_ALIGNMENT_CENTER, 600, 11, Pal.INK_DIM)
```

- [ ] **Step 4: Headless boot**

Run: `godot --headless --path godot --quit-after 30 2>&1 | Select-String "SCRIPT ERROR|Parse Error|Failed to load"`
Expected: no matches.

- [ ] **Step 5: Run the harness (no new tests, must stay green)**

Run: `pwsh -File godot/tests/run_tests.ps1`
Expected: PASS — `== N passed, 0 failed ==`, EXIT 0 (unchanged count from Task 2).

- [ ] **Step 6: Visual check — capture the campaign screen**

Run: `godot --path godot -- --shot campaign`
Then read `godot/tools/shots/campaign.png`: confirm all 8 mission rows render in-canvas (none clipped past the bottom), rows 1–? show as unlocked/cleared per progress, the new titan-arc subtitle shows, and the footer hint is still visible.

- [ ] **Step 7: Commit**

```bash
git add godot/scenes/campaign/campaign_scene.gd
git commit -m "[godot] P5.3 missions 5-8: campaign screen fits 8 rows + titan subtitle"
```

---

## Self-Review

**Spec coverage:**
- `CAMPAIGN` 4→8, four titan-arc scenarios (maps/seeds/intros/difficulty/ai_mp_bonus/ai_summons/deploy_slots) → Task 1. ✓
- Objective spread rout(m5)/seize(m6)/protect(m7)/archon-kill(m8) → m5 static data (Task 1), m6/m7 runtime wiring (Task 2), m8 empty (Task 1 data + Task 2 assert). ✓
- `seize_enemy_castle` builds `{seize, castles[1]}`; `protect_ally` spawns ally + `{protect, unit_id}` → Task 2. ✓
- Bosses in `ai_summons` (pyre_colossus/storm_tyrant), demo boss pre-placed → Task 1 data + Task 2 spawn assert. ✓
- deploy_slots 5/5/6/6 → Task 1. ✓
- Campaign screen fits 8 + subtitle → Task 3. ✓
- Tests (size, shapes, seize-from-castle, protect spawn + evaluate alive/dead, both-titans) → Tasks 1–2. ✓
- Gates (harness + headless + `--shot campaign`) → all tasks. ✓

**Placeholder scan:** none — full scenario dicts, full test code, exact edits + commands.

**Type consistency:** scenario flags `seize_enemy_castle` (bool) / `protect_ally` (String) consistent between campaign.gd data, new_campaign reads, and the tests. Objective shapes match `Objectives.evaluate` exactly (`{kind:"seize",q,r}`, `{kind:"protect",unit_id}`, `{kind:"rout"}`). `AILib.find_summon_slot(gs, master)` matches the existing `new_campaign` usage. `gs.spawn_unit(type_key, owner, q, r)`, `gs.master_of`, `gs.unit_by_id`, `gs.map["castles"]` match `core/game_state.gd`. `Deploy.slots_for` matches Phase 5.2. Mission indices 4–7 / map keys c5–c8 consistent across data + tests.

**Build-order note:** Task 1 is data-first (the pure data addition has no meaningful RED — accessing a not-yet-existing `CAMPAIGN[4]` would abort the harness rather than fail cleanly, so the data lands first and the assertions guard it). Task 2 is true TDD (objective wiring absent → seize/protect asserts fail RED → wiring → GREEN). Task 3 is render-layer (no unit test; `--shot campaign` + headless boot).
