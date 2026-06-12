# Wraithspire Godot M9 — Title / Gameover / Save / Difficulty / Campaign → PARITY — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Close the full game loop — title → skirmish/campaign → match → gameover → title, with autosave/resume, a settings overlay, and a generalized per-player AI table — reaching parity with the frozen JS reference (`game.js`).

**Architecture:** Router + Session split. `main.gd` becomes a thin screen router; the current match controller (`scenes/main.gd`) moves to `scenes/match/match_scene.gd`. A persistent `core/session.gd` holds app state (screen, settings, difficulty, map_index, campaign_progress) and the live `GameState`. `GameState` stays the pure per-match logic core. Save/settings live in pure-ish `core/save_game.gd` / `core/settings_store.gd` (JSON at `user://`). Five procedural screen scenes port the JS render functions 1:1.

**Tech Stack:** Godot 4.6.3 (GDScript), headless harness `pwsh -File godot/tests/run_tests.ps1`, no .tscn for HUD/screens (built in code, matching house style).

**Spec:** `docs/superpowers/specs/2026-06-11-wraithspire-godot-m9-parity-design.md`

---

## Conventions for every task

- **Harness gate (after every task):** `pwsh -File godot/tests/run_tests.ps1` → last line `== N passed, 0 failed ==`, EXIT 0. (Do NOT use `-ExecutionPolicy Bypass` — blocked by the classifier.)
- **Headless-boot gate (after any task touching `scenes/main.gd` or any scene script):** `godot --headless --path godot --quit-after 30 2>&1 | Select-String "SCRIPT ERROR|Parse Error|Failed to load"` → no matches, EXIT 0.
- New harness tests are added INSIDE `godot/tests/run_tests.gd`: a `const` preload near the top, a `_test_xxx()` method, and a call to it in `_initialize()`. Use the existing `_ok(cond,msg)` / `_eq(got,want,msg)` helpers.
- New scene/screen scripts declare `class_name` so the harness loads (parse-checks) them even before the router instantiates them.
- Commit after each task: `git add <files> && git commit -m "[godot] M9 task N: <summary>"` (end body with the Co-Authored-By trailer per repo convention).

## File structure (created / modified)

| File | Responsibility |
|------|----------------|
| `core/game_state.gd` (modify) | + `is_ai`, `campaign_index`, `match_difficulty`, `stats`; `new_campaign`; stats hooks |
| `core/combat.gd` (modify) | `stats.battles`/`lost` increments in `resolve_attack` |
| `core/save_game.gd` (new) | pure `to_dict`/`from_dict` + `user://` save/load/delete/probe |
| `core/settings_store.gd` (new) | settings JSON persistence |
| `core/session.gd` (new) | app state + match-start helpers + progression |
| `data/palette.gd` (new) | `Pal` — ported PAL chrome colors for screens |
| `scenes/match/match_scene.gd` (new = moved `scenes/main.gd`) | match controller; reads `is_ai`; autosave; battle-scene toggle; `match_ended` |
| `scenes/main.gd` (rewrite) | thin router: Session + screen swap |
| `scenes/title/title_scene.gd` (new) | title screen |
| `scenes/campaign/campaign_scene.gd` (new) | mission list |
| `scenes/story/story_scene.gd` (new) | mission intro |
| `scenes/gameover/gameover_scene.gd` (new) | victory + stats summary |
| `scenes/hud/settings_panel.gd` (new) | settings overlay |
| `scenes/hud/top_bar.gd` (modify) | gear button → opens settings |
| `tests/run_tests.gd` (modify) | `_test_stats`, `_test_new_campaign`, `_test_save`, `_test_settings`, `_test_session` |

---

## Task 1: GameState additions + stats + new_campaign

**Files:**
- Modify: `godot/core/game_state.gd`
- Modify: `godot/core/combat.gd:80-86` (after the `battle_log.append`)
- Modify: `godot/tests/run_tests.gd`

- [ ] **Step 1: Write the failing tests** — add preload + two test methods + calls.

In `run_tests.gd`, the `GameState`/`Combat`/`Campaign` preloads already exist. Add the call lines in `_initialize()` (just before the final `print(...)`):

```gdscript
	_test_stats()
	_test_new_campaign()
```

Add these methods at the end of the file:

```gdscript
func _test_stats() -> void:
	var gs := GameState.new_skirmish(Maps.MAPS[0], 7041)
	# fresh stats
	_eq(gs.stats["summoned"], [0, 0], "stats: fresh summoned")
	_eq(gs.stats["lost"], [0, 0], "stats: fresh lost")
	_eq(gs.stats["battles"], 0, "stats: fresh battles")
	# spawning a non-master unit tallies summoned for its owner; masters do not
	gs.spawn_unit("imp", 0, 1, 1)
	_eq(gs.stats["summoned"], [1, 0], "stats: spawn_unit tallies summoned")
	# a resolved battle bumps battles, and a kill bumps the dead unit's owner's lost
	var atk := gs.spawn_unit("colossus", 0, 2, 2)   # heavy hitter
	var foe := gs.spawn_unit("imp", 1, 3, 2)         # adjacent, frail
	atk["acted"] = false
	Combat.resolve_attack(gs, atk, foe)
	_eq(gs.stats["battles"], 1, "stats: resolve bumps battles")
	_ok(gs.stats["lost"][1] >= 1, "stats: enemy loss tallied on kill")

func _test_new_campaign() -> void:
	var sc: Dictionary = Campaign.CAMPAIGN[1]   # Drowned Marches: ai_mp_bonus 0, ai_summons ["tidekin"]
	var gs := GameState.new_campaign(sc, 1)
	_eq(gs.campaign_index, 1, "campaign: index set")
	_eq(gs.match_difficulty, "normal", "campaign: match_difficulty from scenario")
	_eq(gs.difficulty, "normal", "campaign: AI weight profile follows match difficulty")
	# ai_summons pre-placed for player 1
	var ai_extra := 0
	for u in gs.units:
		if u["owner"] == 1 and not u.get("is_master", false):
			ai_extra += 1
	_eq(ai_extra, 1, "campaign: one ai_summon pre-placed")
	# ai_mp_bonus applied & clamped (mission 1 bonus 0 -> master mp unchanged but >= 4)
	var m1 = gs.master_of(1)
	_ok(m1["mp"] >= 4, "campaign: ai master mp clamped >= 4")
```

- [ ] **Step 2: Run harness, verify it fails**

Run: `pwsh -File godot/tests/run_tests.ps1`
Expected: FAIL (e.g. `Invalid access to property 'stats'` / `new_campaign` not found), EXIT 1.

- [ ] **Step 3: Add the fields + stats reset + new_campaign to `game_state.gd`**

After the existing `var difficulty := "normal"` / `var battle_log` declarations (around line 23-24), add:

```gdscript
var is_ai: Array[bool] = [false, true]   # M9: per-player AI flag (replaces the current_player==1 hardcode)
var campaign_index: int = -1             # M9: -1 skirmish; else CAMPAIGN index
var match_difficulty: String = "normal"  # M9: difficulty in force THIS match (campaign sets its own w/o touching prefs)
var stats: Dictionary = {"summoned": [0, 0], "lost": [0, 0], "battles": 0}  # M9: gameover summary
```

In `new_skirmish` (after `gs.map_def = def`), reset stats (match_difficulty/difficulty for skirmish are set by `Session.start_skirmish`, Task 4):

```gdscript
	gs.stats = {"summoned": [0, 0], "lost": [0, 0], "battles": 0}
```

(Keep `new_skirmish` otherwise unchanged. `match_difficulty`/`difficulty` for skirmish are set by `Session.start_skirmish`, which assigns `gs.difficulty` after construction — see Task 4. The reset above just guarantees clean stats.)

Add `new_campaign` right after `new_skirmish`:

```gdscript
## new_campaign — like new_skirmish but for a CAMPAIGN scenario: generates the
## scenario map, sets match_difficulty/difficulty from the scenario (without
## touching the persisted skirmish pref, which lives on Session), applies the
## AI opening modifiers (ai_mp_bonus clamped to [4, max_mp]; ai_summons pre-placed
## near the AI master), and tags campaign_index. Mirrors JS startNewGame(scenario).
## Uses the global `AI` class (ai.gd has class_name AI, does not preload GameState,
## so no preload const here — avoids a circular preload).
static func new_campaign(scenario: Dictionary, index: int) -> GameState:
	var def: Dictionary = scenario["map"]
	var gs := new_skirmish(def, def.get("seed", 0))
	gs.campaign_index = index
	gs.match_difficulty = scenario["difficulty"]
	gs.difficulty = scenario["difficulty"]
	var m1 = gs.master_of(1)
	if m1 != null:
		var bonus: int = scenario.get("ai_mp_bonus", 0)
		m1["mp"] = clampi(m1["mp"] + bonus, 4, m1["max_mp"])
		for k in scenario.get("ai_summons", []):
			var slot = AI.find_summon_slot(gs, m1)
			if slot == null:
				break
			gs.spawn_unit(k, 1, slot.x, slot.y)
	return gs
```

Add the `summoned` tally inside `spawn_unit` (it is only ever called for non-master summons; masters go through `spawn_master`):

```gdscript
func spawn_unit(type_key: String, owner: int, q: int, r: int) -> Dictionary:
	var u := Units.make_unit(_new_id(), type_key, owner, q, r)
	units.append(u)
	if owner >= 0 and owner < 2:
		stats["summoned"][owner] += 1
	return u
```

- [ ] **Step 4: Add the battle/loss tally to `combat.gd`**

In `resolve_attack`, immediately AFTER `state.battle_log.append({...})` and BEFORE `state.check_win_condition()`:

```gdscript
	state.stats["battles"] += 1
	if primary.get("killed", false):
		state.stats["lost"][defender["owner"]] += 1
	if counter.get("killed", false):
		state.stats["lost"][attacker["owner"]] += 1
```

- [ ] **Step 5: Run harness, verify pass**

Run: `pwsh -File godot/tests/run_tests.ps1`
Expected: `== N passed, 0 failed ==`, EXIT 0 (N grew by the new asserts).

- [ ] **Step 6: Commit**

```bash
git add godot/core/game_state.gd godot/core/combat.gd godot/tests/run_tests.gd
git commit -m "[godot] M9 task 1: GameState is_ai/campaign_index/match_difficulty/stats + new_campaign"
```

**Note (accepted minor divergence):** `lost` tallies combat deaths only; a unit killed by an AoE ability (quake) is not counted in the summary. Record this in the milestone handoff. (JS counts all deaths; the discrepancy is cosmetic on the gameover stats table.)

---

## Task 2: SaveGame — pure to_dict/from_dict + user:// I/O

**Files:**
- Create: `godot/core/save_game.gd`
- Modify: `godot/tests/run_tests.gd`

- [ ] **Step 1: Write the failing test**

Add preload near the other core preloads in `run_tests.gd`:

```gdscript
const SaveGame = preload("res://core/save_game.gd")
```

Add the call in `_initialize()`:

```gdscript
	_test_save()
```

Add the method:

```gdscript
func _test_save() -> void:
	var gs := GameState.new_skirmish(Maps.MAPS[0], 7041)
	gs.spawn_unit("imp", 0, 1, 1)
	gs.spawn_unit("colossus", 1, 5, 5)
	gs.turn = 4
	gs.current_player = 1
	gs.campaign_index = 2
	gs.match_difficulty = "hard"
	gs.stats["battles"] = 3
	# round-trip through the pure dict
	var blob := SaveGame.to_dict(gs)
	_eq(blob["v"], 1, "save: version")
	var gs2 = SaveGame.from_dict(blob)
	_ok(gs2 != null, "save: from_dict returns a state")
	_eq(gs2.turn, 4, "save: turn restored")
	_eq(gs2.current_player, 1, "save: current_player restored")
	_eq(gs2.campaign_index, 2, "save: campaign_index restored")
	_eq(gs2.match_difficulty, "hard", "save: match_difficulty restored")
	_eq(gs2.stats["battles"], 3, "save: stats restored")
	# units (living only) restored with full fields
	_eq(gs2.units.size(), gs.units.size(), "save: unit count")
	var imp = gs2.unit_at(1, 1)
	_ok(imp != null and imp["type_key"] == "imp", "save: unit identity restored")
	_ok(typeof(imp["cd"]) == TYPE_INT or typeof(imp["cd"]) == TYPE_FLOAT, "save: unit cd present")
	# weather + map_def carried (closes the JS resumed-campaign-weather gap)
	_eq(gs2.weather.get("key"), gs.weather.get("key"), "save: weather restored")
	_eq(gs2.map_def.get("key"), gs.map_def.get("key"), "save: map_def restored")
	# map cells + rebuilt tower/castle lists
	_eq(gs2.map["cells"].size(), gs.map["cells"].size(), "save: cell count")
	_eq(gs2.map["castles"].size(), gs.map["castles"].size(), "save: castle list rebuilt")
	# version guard
	var bad := blob.duplicate(true)
	bad["v"] = 99
	_eq(SaveGame.from_dict(bad), null, "save: version guard rejects v!=1")
	# old-blob cd normalization
	var nocd := blob.duplicate(true)
	for u in nocd["units"]:
		u.erase("cd")
	var gs3 = SaveGame.from_dict(nocd)
	_ok(gs3 != null and gs3.units[0].get("cd", -1) == 0, "save: missing cd normalized to 0")
```

- [ ] **Step 2: Run harness, verify it fails**

Run: `pwsh -File godot/tests/run_tests.ps1`
Expected: FAIL (`Could not load res://core/save_game.gd`), EXIT 1.

- [ ] **Step 3: Implement `core/save_game.gd`**

```gdscript
class_name SaveGame
extends RefCounted
## M9 save/load. Pure to_dict/from_dict (harness-tested round-trip) + thin
## user:// file I/O. Versioned blob (v:1); loader defaults missing fields and
## normalizes pre-ability units (cd). Mirrors JS saveGame/loadGame (sec. 6.1),
## additionally serializing map_def to fix the resumed-campaign weather gap.

const GameStateLib = preload("res://core/game_state.gd")
const Rng = preload("res://core/rng.gd")

const SAVE_PATH := "user://wraithspire_save.json"

## to_dict — pure snapshot of a live match. Serializes living units whole, the
## terrain cells (owners mutate, so a seed isn't enough), weather, and map_def.
static func to_dict(state) -> Dictionary:
	var cells: Array = []
	for c in state.map.get("cells", {}).values():
		cells.append({"q": c["q"], "r": c["r"], "terrain": c["terrain"], "owner": c.get("owner", -1)})
	var living: Array = []
	for u in state.units:
		if u["hp"] > 0:
			living.append(u.duplicate(true))
	return {
		"v": 1,
		"turn": state.turn,
		"current_player": state.current_player,
		"next_id": state._next_id,
		"cols": state.map.get("cols", 0),
		"rows": state.map.get("rows", 0),
		"cells": cells,
		"units": living,
		"stats": state.stats.duplicate(true),
		"campaign_index": state.campaign_index,
		"match_difficulty": state.match_difficulty,
		"difficulty": state.difficulty,
		"is_ai": state.is_ai.duplicate(),
		"weather": state.weather.duplicate(true),
		"map_def": state.map_def.duplicate(true),
	}

## from_dict — rebuild a GameState from a blob, or null if invalid. Rebuilds the
## map cell dictionary + tower/castle reference lists, restores units (normalizing
## missing cd), and defaults missing weather/stats/is_ai for old blobs.
static func from_dict(blob) -> GameState:
	if blob == null or typeof(blob) != TYPE_DICTIONARY:
		return null
	if blob.get("v", 0) != 1:
		return null
	if typeof(blob.get("cells")) != TYPE_ARRAY or typeof(blob.get("units")) != TYPE_ARRAY:
		return null
	var gs = GameStateLib.new()
	var cells := {}
	var towers: Array = []
	var castles: Array = []
	for c in blob["cells"]:
		var cell := {"q": int(c["q"]), "r": int(c["r"]), "terrain": c["terrain"], "owner": int(c.get("owner", -1))}
		cells["%d,%d" % [cell["q"], cell["r"]]] = cell
		if cell["terrain"] == "tower":
			towers.append(cell)
		elif cell["terrain"] == "castle":
			castles.append(cell)
	gs.map = {
		"cols": int(blob.get("cols", 0)), "rows": int(blob.get("rows", 0)),
		"cells": cells, "towers": towers, "castles": castles,
	}
	var units: Array[Dictionary] = []
	for u in blob["units"]:
		var ud: Dictionary = (u as Dictionary).duplicate(true)
		if typeof(ud.get("cd")) != TYPE_INT and typeof(ud.get("cd")) != TYPE_FLOAT:
			ud["cd"] = 0
		units.append(ud)
	gs.units = units
	gs.turn = int(blob.get("turn", 1))
	gs.current_player = int(blob.get("current_player", 0))
	gs._next_id = int(blob.get("next_id", 1000))
	gs.stats = blob.get("stats", {"summoned": [0, 0], "lost": [0, 0], "battles": 0})
	gs.campaign_index = int(blob.get("campaign_index", -1))
	gs.match_difficulty = blob.get("match_difficulty", "normal")
	gs.difficulty = blob.get("difficulty", "normal")
	var ai = blob.get("is_ai", [false, true])
	gs.is_ai = [bool(ai[0]), bool(ai[1])] if ai.size() >= 2 else [false, true]
	gs.weather = blob.get("weather", {"key": "clear", "turns_left": 5})
	gs.map_def = blob.get("map_def", {})
	gs.rng = Rng.new(0)   # resumed match: fresh RNG stream (determinism is per-session, not cross-save)
	return gs

# ---- file I/O (thin; not unit-tested — the pure round-trip above is) ----

static func save(state) -> void:
	if state == null:
		return
	var f := FileAccess.open(SAVE_PATH, FileAccess.WRITE)
	if f == null:
		return
	f.store_string(JSON.stringify(to_dict(state)))
	f.close()

static func load_game() -> GameState:
	if not FileAccess.file_exists(SAVE_PATH):
		return null
	var f := FileAccess.open(SAVE_PATH, FileAccess.READ)
	if f == null:
		return null
	var txt := f.get_as_text()
	f.close()
	var parsed = JSON.parse_string(txt)
	return from_dict(parsed)

static func delete() -> void:
	if FileAccess.file_exists(SAVE_PATH):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(SAVE_PATH))

static func probe() -> bool:
	return FileAccess.file_exists(SAVE_PATH)
```

- [ ] **Step 4: Run harness, verify pass**

Run: `pwsh -File godot/tests/run_tests.ps1`
Expected: `== N passed, 0 failed ==`, EXIT 0.

- [ ] **Step 5: Commit**

```bash
git add godot/core/save_game.gd godot/tests/run_tests.gd
git commit -m "[godot] M9 task 2: SaveGame pure round-trip + user:// I/O (map_def serialized)"
```

---

## Task 3: SettingsStore — settings JSON persistence

**Files:**
- Create: `godot/core/settings_store.gd`
- Modify: `godot/tests/run_tests.gd`

- [ ] **Step 1: Write the failing test**

Preload + call + method in `run_tests.gd`:

```gdscript
const SettingsStore = preload("res://core/settings_store.gd")
```
```gdscript
	_test_settings()
```
```gdscript
func _test_settings() -> void:
	# default blob shape
	var d := SettingsStore.defaults()
	_eq(d["music_vol"], 0.6, "settings: default music_vol")
	_eq(d["battle_scene"], true, "settings: default battle_scene")
	_eq(d["difficulty"], "normal", "settings: default difficulty")
	# merge sanitizes: good values applied, bad ones defaulted
	var merged := SettingsStore.merge(d, {"music_vol": 0.3, "difficulty": "hard", "map_index": 2, "campaign_progress": 1, "battle_scene": false})
	_eq(merged["music_vol"], 0.3, "settings: merge applies valid music_vol")
	_eq(merged["difficulty"], "hard", "settings: merge applies valid difficulty")
	_eq(merged["map_index"], 2, "settings: merge applies valid map_index")
	_eq(merged["battle_scene"], false, "settings: merge applies battle_scene")
	var bad := SettingsStore.merge(d, {"difficulty": "lunatic", "map_index": 99, "music_vol": "loud"})
	_eq(bad["difficulty"], "normal", "settings: merge rejects bad difficulty")
	_eq(bad["map_index"], 0, "settings: merge rejects out-of-range map_index")
	_eq(bad["music_vol"], 0.6, "settings: merge rejects non-number music_vol")
```

- [ ] **Step 2: Run harness, verify it fails**

Run: `pwsh -File godot/tests/run_tests.ps1`
Expected: FAIL (`Could not load res://core/settings_store.gd`), EXIT 1.

- [ ] **Step 3: Implement `core/settings_store.gd`**

```gdscript
class_name SettingsStore
extends RefCounted
## M9 settings persistence. Pure defaults()/merge() (harness-tested) + thin
## user:// JSON I/O. Holds music_vol, sfx_vol, battle_scene, plus the persisted
## skirmish prefs (difficulty, map_index, campaign_progress). Mirrors JS
## loadSettings/saveSettings (sec. 3.3). Music/sfx are inert until M10 audio.

const Maps = preload("res://data/maps.gd")
const AiProfiles = preload("res://data/ai_profiles.gd")

const SETTINGS_PATH := "user://wraithspire_settings.json"

static func defaults() -> Dictionary:
	return {
		"music_vol": 0.6, "sfx_vol": 0.6, "battle_scene": true,
		"difficulty": "normal", "map_index": 0, "campaign_progress": 0,
	}

## merge — fold a (possibly untrusted) saved blob onto defaults, accepting only
## values of the right type / range; bad fields keep the default.
static func merge(base: Dictionary, saved: Dictionary) -> Dictionary:
	var out := base.duplicate(true)
	for key in ["music_vol", "sfx_vol"]:
		if typeof(saved.get(key)) == TYPE_FLOAT or typeof(saved.get(key)) == TYPE_INT:
			out[key] = clampf(float(saved[key]), 0.0, 1.0)
	if typeof(saved.get("battle_scene")) == TYPE_BOOL:
		out["battle_scene"] = saved["battle_scene"]
	if AiProfiles.DIFFICULTIES.has(saved.get("difficulty")):
		out["difficulty"] = saved["difficulty"]
	if typeof(saved.get("map_index")) == TYPE_FLOAT or typeof(saved.get("map_index")) == TYPE_INT:
		var mi := int(saved["map_index"])
		if mi >= 0 and mi < Maps.MAPS.size():
			out["map_index"] = mi
	if typeof(saved.get("campaign_progress")) == TYPE_FLOAT or typeof(saved.get("campaign_progress")) == TYPE_INT:
		out["campaign_progress"] = maxi(0, int(saved["campaign_progress"]))
	return out

# ---- file I/O ----

static func load_blob() -> Dictionary:
	var base := defaults()
	if not FileAccess.file_exists(SETTINGS_PATH):
		return base
	var f := FileAccess.open(SETTINGS_PATH, FileAccess.READ)
	if f == null:
		return base
	var parsed = JSON.parse_string(f.get_as_text())
	f.close()
	if typeof(parsed) != TYPE_DICTIONARY:
		return base
	return merge(base, parsed)

static func save_blob(blob: Dictionary) -> void:
	var f := FileAccess.open(SETTINGS_PATH, FileAccess.WRITE)
	if f == null:
		return
	f.store_string(JSON.stringify(blob))
	f.close()
```

- [ ] **Step 4: Run harness, verify pass**

Run: `pwsh -File godot/tests/run_tests.ps1`
Expected: `== N passed, 0 failed ==`, EXIT 0.

- [ ] **Step 5: Commit**

```bash
git add godot/core/settings_store.gd godot/tests/run_tests.gd
git commit -m "[godot] M9 task 3: SettingsStore defaults/merge + user:// JSON I/O"
```

---

## Task 4: Session — app state + match-start + progression

**Files:**
- Create: `godot/core/session.gd`
- Modify: `godot/tests/run_tests.gd`

- [ ] **Step 1: Write the failing test**

Preload + call + method:

```gdscript
const Session = preload("res://core/session.gd")
```
```gdscript
	_test_session()
```
```gdscript
func _test_session() -> void:
	var s := Session.new()
	# defaults
	_eq(s.screen, "title", "session: starts on title")
	_eq(s.difficulty, "normal", "session: default difficulty")
	# start a skirmish: builds a live state on the selected map/difficulty
	s.map_index = 1
	s.difficulty = "hard"
	s.start_skirmish()
	_eq(s.screen, "play", "session: skirmish -> play")
	_ok(s.state != null, "session: skirmish builds a state")
	_eq(s.state.difficulty, "hard", "session: skirmish AI difficulty from pref")
	_eq(s.state.campaign_index, -1, "session: skirmish is not a campaign")
	_eq(s.state.is_ai, [false, true], "session: is_ai table")
	# start a campaign mission
	s.start_campaign(0)
	_eq(s.screen, "play", "session: campaign -> play")
	_eq(s.state.campaign_index, 0, "session: campaign index tagged")
	_eq(s.difficulty, "hard", "session: campaign did NOT overwrite skirmish pref")
	# progression rule: P0 wins mission 0 -> progress advances to 1
	s.campaign_progress = 0
	s.on_match_won(0)   # state.campaign_index is 0, winner 0
	_eq(s.campaign_progress, 1, "session: win advances campaign_progress")
	# a loss does not advance; progress never regresses
	s.start_campaign(0)
	s.campaign_progress = 2
	s.on_match_won(1)   # AI won
	_eq(s.campaign_progress, 2, "session: AI win leaves progress unchanged")
	# cap at last mission
	var last: int = Campaign.CAMPAIGN.size() - 1
	s.start_campaign(last)
	s.campaign_progress = last
	s.on_match_won(0)
	_eq(s.campaign_progress, last, "session: progress capped at last mission")
	# return_to_title clears the campaign tag
	s.return_to_title()
	_eq(s.screen, "title", "session: return_to_title")
```

- [ ] **Step 2: Run harness, verify it fails**

Run: `pwsh -File godot/tests/run_tests.ps1`
Expected: FAIL (`Could not load res://core/session.gd`), EXIT 1.

- [ ] **Step 3: Implement `core/session.gd`**

```gdscript
class_name Session
extends RefCounted
## M9 app/session state — the slice of the JS STATE that outlives any single
## match: the active screen, persisted prefs (difficulty/map_index/campaign_progress),
## the settings blob, and the live GameState (or null on menu screens). Owned by
## the router (scenes/main.gd). Match-start helpers mirror JS startNewGame.

const GameStateLib = preload("res://core/game_state.gd")
const Maps = preload("res://data/maps.gd")
const Campaign = preload("res://data/campaign.gd")
const SettingsStore = preload("res://core/settings_store.gd")
const SaveGame = preload("res://core/save_game.gd")

var screen: String = "title"          # title | campaign | story | play | gameover
var settings: Dictionary = SettingsStore.defaults()
var difficulty: String = "normal"     # persisted skirmish difficulty
var map_index: int = 0                 # persisted skirmish map
var campaign_progress: int = 0         # highest unlocked mission index
var story_index: int = 0               # mission selected on the campaign screen
var has_save: bool = false
var state = null                       # the live GameState, or null

## load_prefs — pull persisted settings into the session at boot.
func load_prefs() -> void:
	settings = SettingsStore.load_blob()
	difficulty = settings["difficulty"]
	map_index = settings["map_index"]
	campaign_progress = settings["campaign_progress"]
	has_save = SaveGame.probe()

## persist_prefs — write current prefs back to the settings file.
func persist_prefs() -> void:
	settings["difficulty"] = difficulty
	settings["map_index"] = map_index
	settings["campaign_progress"] = campaign_progress
	SettingsStore.save_blob(settings)

func start_skirmish() -> void:
	var def: Dictionary = Maps.MAPS[map_index] if map_index < Maps.MAPS.size() else Maps.MAPS[0]
	var seed: int = def["seed"] if int(def.get("seed", -1)) >= 0 else randi()
	state = GameStateLib.new_skirmish(def, seed)
	state.difficulty = difficulty
	state.match_difficulty = difficulty
	state.campaign_index = -1
	screen = "play"

func start_campaign(index: int) -> void:
	state = GameStateLib.new_campaign(Campaign.CAMPAIGN[index], index)
	screen = "play"

## on_match_won — called by MatchScene when a winner is decided. Advances campaign
## progress on a player-0 mission win (capped, never regressing) and persists it.
func on_match_won(winner: int) -> void:
	if state != null and state.campaign_index >= 0 and winner == 0:
		campaign_progress = mini(Campaign.CAMPAIGN.size() - 1, maxi(campaign_progress, state.campaign_index + 1))
		persist_prefs()
	SaveGame.delete()
	has_save = false

func return_to_title() -> void:
	screen = "title"
	state = null
```

- [ ] **Step 4: Run harness, verify pass**

Run: `pwsh -File godot/tests/run_tests.ps1`
Expected: `== N passed, 0 failed ==`, EXIT 0.

Note: `randi()` is allowed in normal runtime (only `tests` avoid randomness; this branch isn't exercised by the test, which uses `map_index = 1` whose `seed` is `-1` → would call `randi()`... use map_index 1's seed). **Correction for the test:** Shattered Tides (index 1) has `seed: -1`, so `start_skirmish` calls `randi()` — fine at runtime. The test only asserts difficulty/campaign_index/is_ai, not determinism, so `randi()` is acceptable here.

- [ ] **Step 5: Commit**

```bash
git add godot/core/session.gd godot/tests/run_tests.gd
git commit -m "[godot] M9 task 4: Session app-state + start_skirmish/campaign + progression"
```

---

## Task 5: Move match controller → scenes/match/match_scene.gd

This is a lift-and-shift of `scenes/main.gd` into a reusable `MatchScene` that the router drives. `scenes/main.gd` is LEFT UNTOUCHED in this task (it still boots the old hardcoded match, so the headless boot stays green); the router rewrite in Task 10 retires it.

**Files:**
- Create: `godot/scenes/match/match_scene.gd` (copy of `scenes/main.gd`, adapted)

- [ ] **Step 1: Copy the file**

Copy `godot/scenes/main.gd` verbatim to `godot/scenes/match/match_scene.gd`.

- [ ] **Step 2: Adapt the header + class + init**

Change the top of `match_scene.gd`:

```gdscript
class_name MatchScene
extends Node2D
## M9 match controller (was scenes/main.gd). Driven by the router: receives a
## GameState + Session via init() instead of self-starting a skirmish. Reads
## state.is_ai for the AI branch, autosaves at end of turn, honors the
## battle-scene setting, and emits match_ended(winner) for the gameover handoff.

signal match_ended(winner: int)

const SaveGame = preload("res://core/save_game.gd")
# ... keep ALL existing preloads (Hex, Maps, GameState, Pathfinding, Combat,
#     Abilities, AbilityResolve, AI, UnitTypes, UiQueries, BoardScript,
#     UnitsLayerScript, OverlayScript, TopBarScript, InfoCardScript,
#     ActionMenuScript, SummonListScript, BattleSceneScript) ...

var session = null   # set by init(); used for the battle-scene setting + on_match_won
```

Replace `_ready()`'s first line. The current `_ready` does `state = GameState.new_skirmish(...)` then builds the scene. Split it: keep the scene-building, but take `state`/`session` from `init`:

```gdscript
func init(p_state, p_session) -> void:
	state = p_state
	session = p_session

func _ready() -> void:
	# state was provided by init() before the node entered the tree.
	# Draw order: board (bottom) -> overlay -> tokens (top).
	var board := BoardScript.new()
	board.set_map(state.map)
	add_child(board)
	# ... REST OF THE EXISTING _ready() BODY UNCHANGED (overlay, units_layer,
	#     cam centered on master_of(0)->use master_of(state.current_player),
	#     hud, top_bar, info_card, action_menu, summon_list, battle_scene) ...
```

(Keep the rest of `_ready` exactly as in `scenes/main.gd`. The only logic change is removing the `new_skirmish` line — `state` now arrives via `init`.)

- [ ] **Step 3: Generalize the AI branch in `_on_end_turn`**

Replace the hardcoded player check. In `_on_end_turn`, change:

```gdscript
	if state.winner == -1 and state.current_player == 1:
		AI.take_turn(state)
```
to:
```gdscript
	if state.winner == -1 and state.is_ai[state.current_player]:
		AI.take_turn(state)
```

And at the END of `_on_end_turn` (after `_center_on_master()` / `_finish_action()`), add autosave + win handoff:

```gdscript
	if state.winner != -1:
		_end_match()
	else:
		SaveGame.save(state)
```

- [ ] **Step 4: Replace the console win print + add the match-end handoff**

In `_finish_action`, REMOVE the trailing:

```gdscript
	if state.winner != -1:
		print("WINNER: player %d" % state.winner)
```

Add a new method:

```gdscript
## _end_match — a winner was decided. Advance campaign progress + clear the
## autosave (via Session), then tell the router to show the gameover screen.
func _end_match() -> void:
	if session != null:
		session.on_match_won(state.winner)
	match_ended.emit(state.winner)
```

Also call `_end_match()` after a human attack resolves a win. In `_resolve_armed`, after `await _play_battles()` (the success path), and in `_play_battles`'s caller paths, the simplest single chokepoint is: at the end of `_play_battles`, check the winner. Add to the end of `_play_battles` (after the HUD refresh):

```gdscript
	if state.winner != -1:
		_end_match()
```

- [ ] **Step 5: Honor the battle-scene setting in `_play_battles`**

Change the top of `_play_battles` so an OFF setting drains the log without awaiting cutaways:

```gdscript
func _play_battles() -> void:
	if state.battle_log.is_empty():
		return
	var show: bool = session == null or session.settings.get("battle_scene", true)
	if not show:
		state.battle_log.clear()   # combat already resolved; skip the animation
		units_layer.set_state(state)
		if top_bar != null:
			top_bar.refresh(state)
		if state.winner != -1:
			_end_match()
		return
	_busy = true
	# ... existing while-loop cutaway drain ...
```

- [ ] **Step 6: Harness + boot gates**

Run: `pwsh -File godot/tests/run_tests.ps1` → `== N passed, 0 failed ==`, EXIT 0 (MatchScene parses via class_name; no new asserts).
Run: `godot --headless --path godot --quit-after 30 2>&1 | Select-String "SCRIPT ERROR|Parse Error|Failed to load"` → no matches (old `main.gd` still boots the hardcoded match).

- [ ] **Step 7: Commit**

```bash
git add godot/scenes/match/match_scene.gd
git commit -m "[godot] M9 task 5: extract MatchScene (init/is_ai/autosave/battle-scene toggle/match_ended)"
```

---

## Task 6: Palette + TitleScene

**Files:**
- Create: `godot/data/palette.gd`
- Create: `godot/scenes/title/title_scene.gd`

- [ ] **Step 1: Create `data/palette.gd` (ported PAL chrome colors)**

```gdscript
class_name Pal
extends RefCounted
## Ported JS PAL chrome colors used by the M9 screens (game.js sec. 1).

const BG := Color("#050409")
const PANEL_LIGHT := Color("#1f1c30")
const INK := Color("#e8e6d8")
const INK_DIM := Color("#8a85a2")
const INK_FAINT := Color("#3a3650")
const GOLD := Color("#f0c674")
const RED := Color("#cc4a4a")
const GREEN := Color("#7ac075")
const PURPLE := Color("#a07acd")
const P0 := Color("#5aa8d8")   # AZURE
const P1 := Color("#cc6a4a")   # CRIMSON
```

- [ ] **Step 2: Implement `scenes/title/title_scene.gd`** — port of `renderTitle` (game.js 4767-4922) + rect helpers (4924-4954). Canvas is 1280×800 (`CANVAS_W`/`CANVAS_H`). A `_process` advances a frame counter for the star scroll / blink; `_draw` paints; clicks navigate via signals.

```gdscript
class_name TitleScene
extends Control
## M9 title screen — port of game.js renderTitle (sec. 14). Synthwave backdrop,
## map + difficulty selectors, CAMPAIGN / CONTINUE buttons. Emits navigation
## signals the router handles. Reads/writes Session prefs on selection.

const Pal = preload("res://data/palette.gd")
const Maps = preload("res://data/maps.gd")
const Campaign = preload("res://data/campaign.gd")
const AiProfiles = preload("res://data/ai_profiles.gd")
const BattleSprites = preload("res://scenes/battle/battle_sprites.gd")

signal begin_skirmish          # click-anywhere / Enter
signal open_campaign           # CAMPAIGN button
signal continue_save           # CONTINUE button

const CW := 1280.0
const CH := 800.0

var session = null
var _frame := 0

func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)

func _process(_delta: float) -> void:
	_frame += 1
	queue_redraw()

func _diff_rects() -> Array:
	var w := 92.0; var h := 24.0; var gap := 14.0
	var n := AiProfiles.DIFFICULTIES.size()
	var total := n * w + (n - 1) * gap
	var x0 := (CW - total) / 2.0
	var out: Array = []
	for i in range(n):
		out.append({"key": AiProfiles.DIFFICULTIES[i], "r": Rect2(x0 + i * (w + gap), 742, w, h)})
	return out

func _map_rects() -> Array:
	var w := 150.0; var h := 22.0; var gap := 8.0
	var n := Maps.MAPS.size()
	var total := n * w + (n - 1) * gap
	var x0 := (CW - total) / 2.0
	var out: Array = []
	for i in range(n):
		out.append({"index": i, "r": Rect2(x0 + i * (w + gap), 698, w, h)})
	return out

func _campaign_rect() -> Rect2:
	var y := CH * 0.60
	return Rect2(CW / 2 - 188, y, 180, 38) if session.has_save else Rect2(CW / 2 - 90, y, 180, 38)

func _continue_rect() -> Rect2:
	return Rect2(CW / 2 + 8, CH * 0.60, 180, 38)

func _draw() -> void:
	var fnt := ThemeDB.fallback_font
	# backdrop gradient (approx via two rects + blend; flat fill is acceptable parity)
	draw_rect(Rect2(0, 0, CW, CH), Color("#1a1130"))
	draw_rect(Rect2(0, CH * 0.5, CW, CH * 0.5), Color("#05030c"))
	# synthwave grid floor
	var horizon := CH * 0.62
	for i in range(-8, 9):
		draw_line(Vector2(CW / 2, horizon), Vector2(CW / 2 + i * 200, CH), Color(0.78, 0.31, 0.78, 0.4), 1.0)
	for i in range(1, 12):
		var yy := horizon + pow(float(i) / 12.0, 2.2) * (CH - horizon)
		var wln := (float(i) / 12.0) * CW * 0.9
		draw_line(Vector2(CW / 2 - wln, yy), Vector2(CW / 2 + wln, yy), Color(0.78, 0.31, 0.78, maxf(0.0, 0.6 - i * 0.04)), 1.0)
	# stars
	for i in range(120):
		var x := float((i * 73 + int(_frame / 4.0)) % int(CW))
		var y := float((i * 31) % int(CH * 0.55))
		var tw := (sin(_frame / 20.0 + i) + 1.0) / 2.0
		draw_rect(Rect2(x, y, 2, 2), Color(0.86, 0.82, 1.0, 0.3 + tw * 0.5))
	# sun + bars
	draw_circle(Vector2(CW / 2, CH * 0.36), 130, Color("#c8418a"))
	for i in range(5):
		draw_rect(Rect2(CW / 2 - 130, CH * 0.36 + 60 + i * 14, 260, 4), Color("#1a1130"))
	# title text
	draw_string(fnt, Vector2(CW / 2 - 250, CH * 0.38), "WRAITHSPIRE", HORIZONTAL_ALIGNMENT_CENTER, 500, 80, Pal.GOLD)
	draw_string(fnt, Vector2(CW / 2 - 250, CH * 0.46), "— SUMMONER'S WAR —", HORIZONTAL_ALIGNMENT_CENTER, 500, 20, Pal.INK)
	# archon previews
	BattleSprites.draw_unit(self, {"owner": 0, "is_master": true, "sprite": "archon"}, CW / 2 - 180, CH * 0.66, 1, "idle", float(_frame))
	BattleSprites.draw_unit(self, {"owner": 1, "is_master": true, "sprite": "archon"}, CW / 2 + 180, CH * 0.66, -1, "idle", float(_frame))
	# CAMPAIGN / CONTINUE buttons
	var next_idx := -1 if session.campaign_progress >= Campaign.CAMPAIGN.size() - 1 else session.campaign_progress
	var next_name: String = "all missions open" if next_idx < 0 else "next: " + Campaign.CAMPAIGN[next_idx]["name"]
	_draw_btn(_campaign_rect(), "CAMPAIGN", next_name, Pal.GOLD, fnt)
	if session.has_save:
		_draw_btn(_continue_rect(), "CONTINUE", "resume the saved battle", Pal.GREEN, fnt)
	# map selector
	for m in _map_rects():
		var sel: bool = m["index"] == session.map_index
		draw_rect(m["r"], Pal.PURPLE if sel else Color(0.12, 0.11, 0.19, 0.85))
		draw_rect(m["r"], Pal.PURPLE if sel else Pal.INK_FAINT, false, 1.0)
		draw_string(fnt, Vector2(m["r"].position.x, m["r"].position.y + 15), String(Maps.MAPS[m["index"]]["name"]).to_upper(), HORIZONTAL_ALIGNMENT_CENTER, m["r"].size.x, 11, Pal.BG if sel else Pal.INK_DIM)
	# difficulty selector
	for d in _diff_rects():
		var sel2: bool = d["key"] == session.difficulty
		draw_rect(d["r"], Pal.GOLD if sel2 else Color(0.12, 0.11, 0.19, 0.85))
		draw_rect(d["r"], Pal.GOLD if sel2 else Pal.INK_FAINT, false, 1.0)
		draw_string(fnt, Vector2(d["r"].position.x, d["r"].position.y + 16), String(d["key"]).to_upper(), HORIZONTAL_ALIGNMENT_CENTER, d["r"].size.x, 12, Pal.BG if sel2 else Pal.INK_DIM)
	# blinking prompt
	if int(_frame / 30.0) % 2 == 0:
		draw_string(fnt, Vector2(CW / 2 - 250, CH * 0.973), "CLICK OR PRESS ENTER TO BEGIN", HORIZONTAL_ALIGNMENT_CENTER, 500, 15, Pal.GOLD)

func _draw_btn(r: Rect2, label: String, sub: String, accent: Color, fnt: Font) -> void:
	draw_rect(r, Color(0.12, 0.11, 0.19, 0.9))
	draw_rect(r, accent, false, 1.0)
	draw_string(fnt, Vector2(r.position.x, r.position.y + 17), label, HORIZONTAL_ALIGNMENT_CENTER, r.size.x, 13, accent)
	draw_string(fnt, Vector2(r.position.x, r.position.y + 30), sub, HORIZONTAL_ALIGNMENT_CENTER, r.size.x, 9, Pal.INK_DIM)

func _gui_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and event.keycode == KEY_ENTER:
		begin_skirmish.emit()
		return
	if not (event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT):
		return
	var p: Vector2 = event.position
	for m in _map_rects():
		if (m["r"] as Rect2).has_point(p):
			session.map_index = m["index"]; session.persist_prefs(); return
	for d in _diff_rects():
		if (d["r"] as Rect2).has_point(p):
			session.difficulty = d["key"]; session.persist_prefs(); return
	if _campaign_rect().has_point(p):
		open_campaign.emit(); return
	if session.has_save and _continue_rect().has_point(p):
		continue_save.emit(); return
	begin_skirmish.emit()
```

- [ ] **Step 3: Harness + boot gates**

Run: `pwsh -File godot/tests/run_tests.ps1` → green (Pal + TitleScene parse via class_name).
Run: `godot --headless --path godot --quit-after 30 2>&1 | Select-String "SCRIPT ERROR|Parse Error|Failed to load"` → no matches.

- [ ] **Step 4: Commit**

```bash
git add godot/data/palette.gd godot/scenes/title/title_scene.gd
git commit -m "[godot] M9 task 6: Pal palette + TitleScene (map/difficulty/campaign/continue)"
```

---

## Task 7: CampaignScene + StoryScene

**Files:**
- Create: `godot/scenes/campaign/campaign_scene.gd` (port of `renderCampaignScreen` 4978 + `campaignRowRects` 4971)
- Create: `godot/scenes/story/story_scene.gd` (port of `renderStoryScreen` 5023)

- [ ] **Step 1: Implement `scenes/campaign/campaign_scene.gd`**

```gdscript
class_name CampaignScene
extends Control
## M9 campaign mission list — port of game.js renderCampaignScreen (sec. 14b).
## Rows unlock by Session.campaign_progress. Click unlocked -> story; ESC -> title.

const Pal = preload("res://data/palette.gd")
const Campaign = preload("res://data/campaign.gd")

signal pick_mission(index: int)
signal back_to_title

const CW := 1280.0
const CH := 800.0

var session = null

func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)

func _row_rects() -> Array:
	var w := 720.0; var h := 70.0; var gap := 16.0
	var x := (CW - w) / 2.0
	var out: Array = []
	for i in range(Campaign.CAMPAIGN.size()):
		out.append({"index": i, "r": Rect2(x, 170 + i * (h + gap), w, h)})
	return out

func _draw() -> void:
	var fnt := ThemeDB.fallback_font
	draw_rect(Rect2(0, 0, CW, CH), Pal.BG)
	draw_string(fnt, Vector2(CW / 2 - 200, 90), "CAMPAIGN", HORIZONTAL_ALIGNMENT_CENTER, 400, 28, Pal.GOLD)
	draw_string(fnt, Vector2(CW / 2 - 300, 116), "— the fall of the crimson archon, in four battles —", HORIZONTAL_ALIGNMENT_CENTER, 600, 11, Pal.INK_DIM)
	for row in _row_rects():
		var i: int = row["index"]
		var r: Rect2 = row["r"]
		var sc: Dictionary = Campaign.CAMPAIGN[i]
		var unlocked: bool = i <= session.campaign_progress
		var cleared: bool = i < session.campaign_progress
		draw_rect(r, Pal.PANEL_LIGHT if unlocked else Color(0.075, 0.067, 0.12, 0.7))
		draw_rect(r, Pal.GOLD if unlocked else Pal.INK_FAINT, false, 1.0)
		draw_string(fnt, Vector2(r.position.x + 18, r.position.y + 28), "%d.  %s" % [i + 1, sc["name"]], HORIZONTAL_ALIGNMENT_LEFT, -1, 16, Pal.GOLD if unlocked else Pal.INK_FAINT)
		var teaser: String = (sc["intro"][0] + " ...") if unlocked else "locked — clear the previous mission"
		draw_string(fnt, Vector2(r.position.x + 18, r.position.y + 48), teaser, HORIZONTAL_ALIGNMENT_LEFT, -1, 10, Pal.INK_DIM if unlocked else Pal.INK_FAINT)
		var badge: String = "CLEARED" if cleared else ("READY" if unlocked else "LOCKED")
		var bcol: Color = Pal.GREEN if cleared else (Pal.GOLD if unlocked else Pal.INK_FAINT)
		draw_string(fnt, Vector2(r.position.x + r.size.x - 120, r.position.y + 28), badge, HORIZONTAL_ALIGNMENT_RIGHT, 104, 11, bcol)
		draw_string(fnt, Vector2(r.position.x + r.size.x - 120, r.position.y + 48), String(sc["difficulty"]).to_upper(), HORIZONTAL_ALIGNMENT_RIGHT, 104, 10, Pal.INK_DIM if unlocked else Pal.INK_FAINT)
	draw_string(fnt, Vector2(CW / 2 - 250, CH - 40), "click a mission to begin  ·  ESC to return", HORIZONTAL_ALIGNMENT_CENTER, 500, 11, Pal.INK_DIM)

func _gui_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and event.keycode == KEY_ESCAPE:
		back_to_title.emit(); return
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		for row in _row_rects():
			if (row["r"] as Rect2).has_point(event.position) and row["index"] <= session.campaign_progress:
				pick_mission.emit(row["index"]); return
```

- [ ] **Step 2: Implement `scenes/story/story_scene.gd`**

```gdscript
class_name StoryScene
extends Control
## M9 mission intro — port of game.js renderStoryScreen (sec. 14b). Intro lines
## fade in sequentially; click begins the match.

const Pal = preload("res://data/palette.gd")
const Campaign = preload("res://data/campaign.gd")

signal begin_mission

const CW := 1280.0
const CH := 800.0

var session = null
var _frame := 0
var _shown_at := 0

func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)

func _process(_delta: float) -> void:
	_frame += 1
	queue_redraw()

func _draw() -> void:
	var fnt := ThemeDB.fallback_font
	var sc: Dictionary = Campaign.CAMPAIGN[session.story_index]
	draw_rect(Rect2(0, 0, CW, CH), Pal.BG)
	draw_string(fnt, Vector2(CW / 2 - 200, CH * 0.3), "MISSION %d OF %d" % [session.story_index + 1, Campaign.CAMPAIGN.size()], HORIZONTAL_ALIGNMENT_CENTER, 400, 10, Pal.INK_FAINT)
	draw_string(fnt, Vector2(CW / 2 - 300, CH * 0.3 + 34), String(sc["name"]).to_upper(), HORIZONTAL_ALIGNMENT_CENTER, 600, 24, Pal.GOLD)
	var lines: Array = sc["intro"]
	for i in range(lines.size()):
		var a := clampf((_frame - _shown_at - i * 26) / 26.0, 0.0, 1.0)
		if a <= 0.0:
			continue
		draw_string(fnt, Vector2(CW / 2 - 300, CH * 0.46 + i * 24), lines[i], HORIZONTAL_ALIGNMENT_CENTER, 600, 14, Color(Pal.INK, a))
	if int(_frame / 30.0) % 2 == 0:
		draw_string(fnt, Vector2(CW / 2 - 200, CH * 0.78), "CLICK TO BEGIN", HORIZONTAL_ALIGNMENT_CENTER, 400, 14, Pal.GOLD)

func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		begin_mission.emit()
```

- [ ] **Step 3: Harness + boot gates**

Run: `pwsh -File godot/tests/run_tests.ps1` → green.
Run: `godot --headless --path godot --quit-after 30 2>&1 | Select-String "SCRIPT ERROR|Parse Error|Failed to load"` → no matches.

- [ ] **Step 4: Commit**

```bash
git add godot/scenes/campaign/campaign_scene.gd godot/scenes/story/story_scene.gd
git commit -m "[godot] M9 task 7: CampaignScene mission list + StoryScene intro"
```

---

## Task 8: GameoverScene

**Files:**
- Create: `godot/scenes/gameover/gameover_scene.gd` (port of `renderGameOver` 5054-5120)

- [ ] **Step 1: Implement `scenes/gameover/gameover_scene.gd`**

```gdscript
class_name GameoverScene
extends Control
## M9 victory screen — port of game.js renderGameOver (sec. 14). Winning archon
## silhouette, faction banner, stats summary, campaign verdict. Click/Enter ->
## title. Built from a finished GameState handed in via set_result().

const Pal = preload("res://data/palette.gd")
const Campaign = preload("res://data/campaign.gd")
const BattleSprites = preload("res://scenes/battle/battle_sprites.gd")

signal to_title

const CW := 1280.0
const CH := 800.0

var _state = null
var _frame := 0

func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)

func set_result(state) -> void:
	_state = state

func _process(_delta: float) -> void:
	_frame += 1
	queue_redraw()

func _draw() -> void:
	if _state == null:
		return
	var fnt := ThemeDB.fallback_font
	draw_rect(Rect2(0, 0, CW, CH), Pal.BG)
	var won_p0: bool = _state.winner == 0
	var text: String = ("AZURE" if won_p0 else "CRIMSON") + " TRIUMPHS"
	var col: Color = Pal.P0 if won_p0 else Pal.P1
	BattleSprites.draw_unit(self, {"owner": _state.winner, "is_master": true, "sprite": "archon"}, CW / 2, CH / 2 - 40, 1, "idle", float(_frame))
	draw_string(fnt, Vector2(CW / 2 - 350, CH / 2 + 80), text, HORIZONTAL_ALIGNMENT_CENTER, 700, 56, col)
	var st: Dictionary = _state.stats
	# towers/castles are stored as Array[Vector2i] coords; ownership lives on the
	# CELL (cell.owner), not the tower entry — so look up each tower's cell.
	var towers := [0, 0]
	for t in _state.map.get("towers", []):
		var tcell = _state.cell_at(t.x, t.y)
		if tcell != null:
			var o: int = tcell.get("owner", -1)
			if o == 0 or o == 1:
				towers[o] += 1
	draw_string(fnt, Vector2(CW / 2 - 300, CH / 2 + 116), "Turns elapsed: %d     Battles fought: %d" % [_state.turn, st["battles"]], HORIZONTAL_ALIGNMENT_CENTER, 600, 14, Pal.INK_DIM)
	# two-column stat table
	var cx0 := CW / 2; var colL := cx0 - 90; var colR := cx0 + 90; var top := CH / 2 + 140
	draw_string(fnt, Vector2(colL - 50, top), "AZURE", HORIZONTAL_ALIGNMENT_CENTER, 100, 13, Pal.P0)
	draw_string(fnt, Vector2(colR - 50, top), "CRIMSON", HORIZONTAL_ALIGNMENT_CENTER, 100, 13, Pal.P1)
	var rows := [
		["Summoned", st["summoned"][0], st["summoned"][1]],
		["Lost", st["lost"][0], st["lost"][1]],
		["Spires", towers[0], towers[1]],
	]
	for i in range(rows.size()):
		var ry := top + 20 + i * 17
		draw_string(fnt, Vector2(cx0 - 50, ry), String(rows[i][0]), HORIZONTAL_ALIGNMENT_CENTER, 100, 12, Pal.INK_DIM)
		draw_string(fnt, Vector2(colL - 50, ry), str(rows[i][1]), HORIZONTAL_ALIGNMENT_CENTER, 100, 12, Pal.INK)
		draw_string(fnt, Vector2(colR - 50, ry), str(rows[i][2]), HORIZONTAL_ALIGNMENT_CENTER, 100, 12, Pal.INK)
	# campaign verdict
	if _state.campaign_index >= 0:
		var msg: String; var vcol: Color
		if won_p0:
			var last: bool = _state.campaign_index >= Campaign.CAMPAIGN.size() - 1
			msg = "CAMPAIGN COMPLETE — THE REALM IS YOURS" if last else "MISSION COMPLETE — THE NEXT BATTLE AWAITS"
			vcol = Pal.GREEN
		else:
			msg = "MISSION FAILED — THE FRONTIER REMEMBERS"
			vcol = Pal.RED
		draw_string(fnt, Vector2(CW / 2 - 350, CH / 2 + 196), msg, HORIZONTAL_ALIGNMENT_CENTER, 700, 13, vcol)
	if int(_frame / 30.0) % 2 == 0:
		draw_string(fnt, Vector2(CW / 2 - 300, CH - 60), "CLICK OR PRESS ENTER TO RETURN TO TITLE", HORIZONTAL_ALIGNMENT_CENTER, 600, 14, Pal.GOLD)

func _gui_input(event: InputEvent) -> void:
	var click := event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT
	var enter := event is InputEventKey and event.pressed and event.keycode == KEY_ENTER
	if click or enter:
		to_title.emit()
```

- [ ] **Step 2: Harness + boot gates**

Run: `pwsh -File godot/tests/run_tests.ps1` → green.
Run: `godot --headless --path godot --quit-after 30 2>&1 | Select-String "SCRIPT ERROR|Parse Error|Failed to load"` → no matches.

- [ ] **Step 3: Commit**

```bash
git add godot/scenes/gameover/gameover_scene.gd
git commit -m "[godot] M9 task 8: GameoverScene — winner banner + stats summary + campaign verdict"
```

---

## Task 9: Settings overlay + top_bar gear button

**Files:**
- Create: `godot/scenes/hud/settings_panel.gd`
- Modify: `godot/scenes/hud/top_bar.gd`

- [ ] **Step 1: Implement `scenes/hud/settings_panel.gd`** — port of `renderSettingsOverlay` rows (music/sfx 10-seg + battle-scene on/off). Music/sfx are inert until M10 but persist.

```gdscript
class_name SettingsPanel
extends Control
## M9 settings overlay. Modal panel: MUSIC VOL / SFX VOL (10-segment, persisted,
## inert until M10) + BATTLE SCENE on/off (live: skips the cutaway). Writes back
## to Session.settings via SettingsStore. Mirrors game.js renderSettingsOverlay.

const Pal = preload("res://data/palette.gd")
const SettingsStore = preload("res://core/settings_store.gd")

var session = null
var _panel: Panel
var _built := false

func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	visible = false
	mouse_filter = Control.MOUSE_FILTER_STOP

func open(p_session) -> void:
	session = p_session
	if not _built:
		_build()
		_built = true
	_refresh()
	visible = true

func close() -> void:
	visible = false

func _build() -> void:
	var dim := ColorRect.new()
	dim.color = Color(0, 0, 0, 0.55)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	dim.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(dim)
	_panel = Panel.new()
	_panel.size = Vector2(360, 240)
	_panel.position = Vector2(640 - 180, 400 - 120)
	add_child(_panel)
	var vb := VBoxContainer.new()
	vb.position = Vector2(20, 18)
	vb.custom_minimum_size = Vector2(320, 0)
	_panel.add_child(vb)
	var title := Label.new(); title.text = "SETTINGS"; vb.add_child(title)
	_add_vol_row(vb, "MUSIC VOL", "music_vol")
	_add_vol_row(vb, "SFX VOL", "sfx_vol")
	# battle scene toggle
	var bs := HBoxContainer.new()
	var bsl := Label.new(); bsl.text = "BATTLE SCENE"; bsl.custom_minimum_size = Vector2(140, 0); bs.add_child(bsl)
	var on := Button.new(); on.text = "ON"; on.pressed.connect(func(): _set_bs(true)); bs.add_child(on)
	var off := Button.new(); off.text = "OFF"; off.pressed.connect(func(): _set_bs(false)); bs.add_child(off)
	vb.add_child(bs)
	var closeb := Button.new(); closeb.text = "CLOSE"; closeb.pressed.connect(close); vb.add_child(closeb)

func _add_vol_row(vb: VBoxContainer, label: String, key: String) -> void:
	var row := HBoxContainer.new()
	var l := Label.new(); l.text = label; l.custom_minimum_size = Vector2(140, 0); row.add_child(l)
	for i in range(10):
		var seg := Button.new()
		seg.text = "·"
		seg.custom_minimum_size = Vector2(16, 0)
		var v := (i + 1) / 10.0
		seg.pressed.connect(func(): _set_vol(key, v))
		row.add_child(seg)
	vb.add_child(row)

func _set_vol(key: String, v: float) -> void:
	session.settings[key] = v
	SettingsStore.save_blob(session.settings)
	_refresh()

func _set_bs(on: bool) -> void:
	session.settings["battle_scene"] = on
	SettingsStore.save_blob(session.settings)
	_refresh()

func _refresh() -> void:
	queue_redraw()   # segment fill is cosmetic; M10 wires real audio + filled bars
```

- [ ] **Step 2: Add a gear button to `top_bar.gd`**

In `top_bar.gd`, add a signal and a button. After the `signal end_turn_pressed` line:

```gdscript
signal settings_pressed
```

In `_ready()`, after the End-Turn button is added:

```gdscript
	var gear := Button.new()
	gear.text = "⚙"
	gear.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	gear.offset_left = -150
	gear.offset_top = 4
	gear.offset_right = -118
	gear.offset_bottom = 32
	gear.pressed.connect(func(): settings_pressed.emit())
	add_child(gear)
```

- [ ] **Step 3: Wire the gear in MatchScene**

In `scenes/match/match_scene.gd` `_ready()`, after `top_bar.end_turn_pressed.connect(_on_end_turn)` and after the settings panel would exist, add a settings panel to the HUD and connect it. Near where `battle_scene` is added to `hud`:

```gdscript
	var settings_panel := preload("res://scenes/hud/settings_panel.gd").new()
	hud.add_child(settings_panel)
	top_bar.settings_pressed.connect(func(): settings_panel.open(session))
```

(Place the `preload` as a `const SettingsPanelScript = preload("res://scenes/hud/settings_panel.gd")` at the top with the other consts, and use `SettingsPanelScript.new()` for house consistency.)

- [ ] **Step 4: Harness + boot gates**

Run: `pwsh -File godot/tests/run_tests.ps1` → green.
Run: `godot --headless --path godot --quit-after 30 2>&1 | Select-String "SCRIPT ERROR|Parse Error|Failed to load"` → no matches.

- [ ] **Step 5: Commit**

```bash
git add godot/scenes/hud/settings_panel.gd godot/scenes/hud/top_bar.gd godot/scenes/match/match_scene.gd
git commit -m "[godot] M9 task 9: settings overlay (battle-scene toggle live, vol persisted) + gear button"
```

---

## Task 10: Router — rewrite scenes/main.gd

Retire the old hardcoded match boot. `main.gd` becomes a router that owns a `Session`, loads prefs, and swaps screen scenes. This is the integration task; verify the FULL loop manually after it.

**Files:**
- Rewrite: `godot/scenes/main.gd`

- [ ] **Step 1: Replace `scenes/main.gd` entirely**

```gdscript
extends Node2D
## M9 root router. Owns the persistent Session, loads prefs + probes the save at
## boot, and swaps the active screen scene whenever Session.screen changes. Screen
## scenes emit navigation signals; the router updates the Session and re-routes.
## (No class_name: this is the main scene entry point.)

const Session = preload("res://core/session.gd")
const SaveGame = preload("res://core/save_game.gd")
const TitleScene = preload("res://scenes/title/title_scene.gd")
const CampaignScene = preload("res://scenes/campaign/campaign_scene.gd")
const StoryScene = preload("res://scenes/story/story_scene.gd")
const GameoverScene = preload("res://scenes/gameover/gameover_scene.gd")
const MatchScene = preload("res://scenes/match/match_scene.gd")

var session: Session
var _current: Node = null

func _ready() -> void:
	session = Session.new()
	session.load_prefs()
	session.screen = "title"
	_route()

## _route — free the current screen scene and build the one matching session.screen.
func _route() -> void:
	if _current != null:
		_current.queue_free()
		_current = null
	match session.screen:
		"title":
			session.has_save = SaveGame.probe()
			var t := TitleScene.new()
			t.session = session
			t.begin_skirmish.connect(_on_begin_skirmish)
			t.open_campaign.connect(_on_open_campaign)
			t.continue_save.connect(_on_continue)
			_mount(t)
		"campaign":
			var c := CampaignScene.new()
			c.session = session
			c.pick_mission.connect(_on_pick_mission)
			c.back_to_title.connect(func(): _go("title"))
			_mount(c)
		"story":
			var s := StoryScene.new()
			s.session = session
			s.begin_mission.connect(_on_begin_mission)
			_mount(s)
		"play":
			var m := MatchScene.new()
			m.init(session.state, session)
			m.match_ended.connect(_on_match_ended)
			_mount(m)
		"gameover":
			var g := GameoverScene.new()
			g.set_result(session.state)
			g.to_title.connect(func(): _go("title"))
			_mount(g)

func _mount(node: Node) -> void:
	_current = node
	add_child(node)

func _go(screen: String) -> void:
	session.screen = screen
	_route()

# ---- navigation handlers ----

func _on_begin_skirmish() -> void:
	session.start_skirmish()    # sets screen = "play"
	_route()

func _on_open_campaign() -> void:
	_go("campaign")

func _on_continue() -> void:
	var loaded = SaveGame.load_game()
	if loaded == null:
		return
	session.state = loaded
	session.screen = "play"
	_route()

func _on_pick_mission(index: int) -> void:
	session.story_index = index
	_go("story")

func _on_begin_mission() -> void:
	session.start_campaign(session.story_index)   # sets screen = "play"
	_route()

func _on_match_ended(_winner: int) -> void:
	# session.on_match_won already ran inside MatchScene; just show the result.
	_go("gameover")
```

- [ ] **Step 2: Verify `main.tscn` still points at `main.gd`**

Confirm `godot/scenes/main.tscn` root node is a `Node2D` with `script = main.gd`. No change expected; the router replaces the script's behavior, not the scene file. If `main.tscn` had baked child nodes from the old match controller, they should already be absent (the old `main.gd` built everything in code). Open the file to confirm it's just a scripted Node2D root.

- [ ] **Step 3: Harness + boot gates**

Run: `pwsh -File godot/tests/run_tests.ps1` → `== N passed, 0 failed ==`, EXIT 0.
Run: `godot --headless --path godot --quit-after 30 2>&1 | Select-String "SCRIPT ERROR|Parse Error|Failed to load"` → **no matches** (the game now boots to the title screen cleanly).

- [ ] **Step 4: Manual full-loop verification (windowed)**

Run: `godot --path godot`. Walk the loop:
1. Title appears (synthwave, two archons, map + difficulty rows, CAMPAIGN button; no CONTINUE on a fresh `user://`).
2. Pick a map + difficulty (selection highlights move); click empty area → skirmish starts on that map.
3. End a few turns → confirm an autosave file appears at `user://wraithspire_save.json` (printed path: `godot --path godot` console, or check `%APPDATA%/Godot/app_userdata/<project>/`).
4. Win/lose a match (fastest: small map, rush the enemy master) → Gameover shows the banner + stats table → click → back to Title, now WITHOUT a CONTINUE (save deleted on match end).
5. Start a match, end one turn, quit, relaunch → Title shows CONTINUE → click → match resumes at the saved turn/weather.
6. CAMPAIGN → mission 1 READY, 2-4 LOCKED → click 1 → story intro fades in → click → mission plays → win → "MISSION COMPLETE" → Title → CAMPAIGN → mission 2 now READY.
7. In-match gear button → settings overlay → toggle BATTLE SCENE OFF → trigger a battle → resolves instantly with no cutaway. Toggle ON → cutaway returns.

- [ ] **Step 5: Commit**

```bash
git add godot/scenes/main.gd
git commit -m "[godot] M9 task 10: thin router — Session + screen swap; full loop closed"
```

---

## Final milestone review

After Task 10, run the whole-milestone review (per the M3–M8 process):
- `git diff <pre-M9-base>..HEAD -- godot/` through an opus reviewer (spec-compliance + code-quality). Base = the commit before Task 1 (`git log --oneline` to find it; likely `c64ce43` or the M9-spec commit).
- Apply any fixes via the implementing agent + `git commit --amend`/follow-up commit.
- Update `ROADMAP_GODOT.md`: check off `- [x] M9 — ...`.
- Update `SESSION_STATE.md`: mark M9 complete, **PARITY REACHED**, point next session at M10 (art + audio) and note ROADMAP2 Phases 2–8 now get their own post-parity specs.
- Record accepted divergences in the handoff: music/sfx sliders inert until M10; `lost` stat counts combat deaths only (AoE-ability kills uncounted); `map_def` IS serialized (closes the JS resumed-campaign-weather gap).

---

## Self-review notes (author)

- **Spec coverage:** Session/router split (Task 4/10) ✓; is_ai table (Task 1/5) ✓; new_campaign + opening modifiers (Task 1) ✓; stats for gameover (Task 1) ✓; SaveGame with map_def (Task 2) ✓; SettingsStore (Task 3) ✓; title/campaign/story/gameover screens (Tasks 6-8) ✓; settings overlay + battle-scene toggle (Task 9) ✓; autosave at end-turn + delete on end + CONTINUE (Tasks 5/10) ✓; difficulty + map pick (Task 6) ✓.
- **Type consistency:** `Session.state`/`Session.settings`/`Session.has_save`/`Session.campaign_progress` used identically across tasks; `MatchScene.init(state, session)` matches the router call; `on_match_won(winner)` matches MatchScene `_end_match`; screen scene signal names (`begin_skirmish`/`open_campaign`/`continue_save`/`pick_mission`/`back_to_title`/`begin_mission`/`to_title`/`match_ended`) match the router connects.
- **Correction folded in:** the spec listed per-feature test files (`test_save.gd` etc.); the actual harness is monolithic `run_tests.gd`, so tests are added there as `_test_*` methods. No behavior change.
- **`draw_string` font sizing:** uses `ThemeDB.fallback_font` at the JS px sizes; exact glyph metrics differ from Courier New — visual parity is "close", confirmed in the windowed pass, not pixel-identical (acceptable; M10 may add a monospace theme font).
