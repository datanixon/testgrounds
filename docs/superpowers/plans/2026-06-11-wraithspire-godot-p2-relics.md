# Wraithspire Godot — ROADMAP2 Phase 2: Relics — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add battlefield relics — 6 passive + 3 consumable — that spawn on maps, auto-equip on move-end (one slot, swap drops old), and modify the bearer through the existing pure stat functions so forecast + AI inherit them.

**Architecture:** A `data/relics.gd` table + pure helpers feed dynamic stat reads threaded into `compute_damage` / `effective_move` / range / a new `Relics.max_hp` / the `end_turn` regen tick. Map-gen spawns relic tiles; `GameState.pick_up_relic` handles equip/swap/Ley; consumables hook `resolve_attack` (Phoenix) and `compute_damage` (Warhorn). Board glyph + info-card line + AI move-nudge + save round-trip complete it.

**Tech Stack:** Godot 4.6.3 GDScript; pure-core + presentation split; headless harness.

**Spec:** `docs/superpowers/specs/2026-06-11-wraithspire-godot-p2-relics-design.md`
**Reference:** v2 design spec "Phase 2 — Relics"; `ROADMAP2.md` 2.1/2.2.

---

## Conventions (every task)

- **Harness gate:** `pwsh -File godot/tests/run_tests.ps1` → `== N passed, 0 failed ==`, EXIT 0. NO `-ExecutionPolicy Bypass`.
- **Headless-boot gate** (after any scene/`main`/`map_gen` change): `godot --headless --path godot --quit-after 30 2>&1 | Select-String "SCRIPT ERROR|Parse Error|Failed to load"` → no matches.
- New tests go in `godot/tests/run_tests.gd` (preload at top, `_test_*` method, call in `_initialize()`, helpers `_ok`/`_eq`/`_approx`).
- `Relics` is `class_name`-registered → harness parse-checks it.
- Commit after each task.

## File structure

| File | Responsibility |
|------|----------------|
| `data/relics.gd` (new) | RELICS table + pure helpers (`bonus`/`unit_bonus`/`max_hp`/`effective_range`/`is_*`/`POOL`) |
| `core/combat.gd` (edit) | atk_charm + warhorn in `compute_damage`; thorncharm + phoenix + warhorn-clear in `resolve_attack` |
| `core/pathfinding.gd` (edit) | swift in `effective_move`; `Relics.effective_range` in `compute_attack_targets` |
| `core/game_state.gd` (edit) | `effective_max_hp` heal clamps + regenring tick; `pick_up_relic` |
| `core/map_gen.gd` (edit) | spawn `def.relics` → `map["relics"]` |
| `data/maps.gd`, `data/campaign.gd` (edit) | `relics` count on each def |
| `core/save_game.gd` (edit) | serialize `map["relics"]` |
| `core/ai.gd` (edit) | move-nudge toward relic tiles |
| `scenes/board/board.gd` (edit) | relic glyph on tiles |
| `scenes/hud/info_card.gd` (edit) | relic line |
| `scenes/match/match_scene.gd` (edit) | call `pick_up_relic` after moves + SFX |
| `tests/run_tests.gd` (edit) | relic tests |

---

## Task 1: Relics data + helpers

**Files:**
- Create: `godot/data/relics.gd`
- Modify: `godot/tests/run_tests.gd`

- [ ] **Step 1: Write the failing test**

Add preload + call + method in `run_tests.gd`:
```gdscript
const Relics = preload("res://data/relics.gd")
```
```gdscript
	_test_relics_data()
```
```gdscript
func _test_relics_data() -> void:
	_eq(Relics.RELICS.size(), 9, "relics: 9 defined")
	_eq(Relics.bonus("atk_charm", "atk"), 2, "relics: atk_charm +2 atk")
	_eq(Relics.bonus("vital", "max_hp"), 4, "relics: vital +4 hp")
	_eq(Relics.bonus("swift", "move"), 1, "relics: swift +1 move")
	_eq(Relics.bonus("farsight", "range"), 1, "relics: farsight +1 range")
	_eq(Relics.bonus("regenring", "regen"), 2, "relics: regenring +2")
	_eq(Relics.bonus("thorncharm", "counter"), 2, "relics: thorncharm +2 counter")
	_eq(Relics.bonus("nonsense", "atk"), 0, "relics: unknown id -> 0")
	_eq(Relics.bonus("atk_charm", "move"), 0, "relics: missing key -> 0")
	_ok(Relics.is_passive("atk_charm") and not Relics.is_consumable("atk_charm"), "relics: atk_charm passive")
	_ok(Relics.is_consumable("phoenix") and not Relics.is_passive("phoenix"), "relics: phoenix consumable")
	_ok(Relics.RELICS["ley_crystal"].get("master_only", false), "relics: ley_crystal master_only")
	# unit_bonus reads unit.relic
	_eq(Relics.unit_bonus({"relic": "atk_charm"}, "atk"), 2, "relics: unit_bonus reads relic")
	_eq(Relics.unit_bonus({"relic": ""}, "atk"), 0, "relics: no relic -> 0")
	_eq(Relics.unit_bonus({}, "atk"), 0, "relics: missing relic key -> 0")
	# max_hp + effective_range helpers
	_eq(Relics.max_hp({"max_hp": 12, "relic": "vital"}), 16, "relics: max_hp adds vital")
	_eq(Relics.max_hp({"max_hp": 12, "relic": ""}), 12, "relics: max_hp base")
	_eq(Relics.effective_range({"range": 1, "relic": "farsight"}), 2, "relics: farsight 1->2")
	_eq(Relics.effective_range({"range": 2, "relic": "farsight"}), 2, "relics: range capped at 2")
	_eq(Relics.effective_range({"range": 1, "relic": ""}), 1, "relics: base range")
	# every POOL id is a real relic
	for id in Relics.POOL:
		_ok(Relics.RELICS.has(id), "relics: POOL id %s defined" % id)
```

- [ ] **Step 2: Run harness, verify fail** — `Could not load res://data/relics.gd`, EXIT 1.

- [ ] **Step 3: Implement `data/relics.gd`**

```gdscript
class_name Relics
extends RefCounted
## ROADMAP2 Phase 2 — relic table + pure stat helpers. Effects flow through the
## existing stat functions (compute_damage/effective_move/range/max_hp/regen), so
## forecast + AI inherit them. 6 passive + 3 consumable. (Veilstone -> Phase 3.)

const RELICS := {
	"atk_charm":   {"name": "Atk Charm",     "kind": "passive",    "glyph": "A", "color": Color("#e0662e"), "atk": 2},
	"vital":       {"name": "Vital Idol",    "kind": "passive",    "glyph": "V", "color": Color("#7ac075"), "max_hp": 4},
	"swift":       {"name": "Swift Boots",   "kind": "passive",    "glyph": "S", "color": Color("#7fd0c0"), "move": 1},
	"farsight":    {"name": "Farsight Lens", "kind": "passive",    "glyph": "F", "color": Color("#a07acd"), "range": 1},
	"regenring":   {"name": "Regen Ring",    "kind": "passive",    "glyph": "R", "color": Color("#70d070"), "regen": 2},
	"thorncharm":  {"name": "Thorn Charm",   "kind": "passive",    "glyph": "T", "color": Color("#cccccc"), "counter": 2},
	"phoenix":     {"name": "Phoenix Charm", "kind": "consumable", "glyph": "P", "color": Color("#ff7f50"), "revive": true},
	"warhorn":     {"name": "Warhorn",       "kind": "consumable", "glyph": "W", "color": Color("#f0c674"), "atk_mult": 1.5},
	"ley_crystal": {"name": "Ley Crystal",   "kind": "consumable", "glyph": "L", "color": Color("#5aa8d8"), "master_only": true, "mp": 6},
}

## Ids eligible to spawn on the map (all 9; map-gen rolls from this).
const POOL := ["atk_charm", "vital", "swift", "farsight", "regenring", "thorncharm", "phoenix", "warhorn", "ley_crystal"]

static func is_passive(id: String) -> bool:
	return RELICS.has(id) and RELICS[id]["kind"] == "passive"

static func is_consumable(id: String) -> bool:
	return RELICS.has(id) and RELICS[id]["kind"] == "consumable"

## bonus — numeric effect value for a relic id + key, 0 if absent.
static func bonus(id: String, key: String) -> Variant:
	if not RELICS.has(id):
		return 0
	return RELICS[id].get(key, 0)

## unit_bonus — bonus for the relic a unit currently holds.
static func unit_bonus(unit: Dictionary, key: String) -> Variant:
	return bonus(unit.get("relic", ""), key)

static func has_relic(unit: Dictionary, id: String) -> bool:
	return unit.get("relic", "") == id

## max_hp — effective max HP including a vital relic. Single source for HP clamps/bars.
static func max_hp(unit: Dictionary) -> int:
	return int(unit["max_hp"]) + int(unit_bonus(unit, "max_hp"))

## effective_range — attack range including farsight, capped at 2 total.
static func effective_range(unit: Dictionary) -> int:
	return mini(2, int(unit["range"]) + int(unit_bonus(unit, "range")))
```

- [ ] **Step 4: Run harness, verify pass** — `== N passed, 0 failed ==`, EXIT 0.

- [ ] **Step 5: Commit**
```bash
git add godot/data/relics.gd godot/tests/run_tests.gd
git commit -m "[godot] P2 relics task 1: Relics table + pure stat helpers"
```

---

## Task 2: Passive stat effects (combat / move / range / maxHP / regen)

Thread the passive relics into the existing pure stat reads. (Consumables warhorn/phoenix are Task 6; this task is the 5 passive stat relics + thorncharm.)

**Files:**
- Modify: `godot/core/combat.gd` (compute_damage atk + maxHP fraction; resolve_attack thorncharm counter)
- Modify: `godot/core/pathfinding.gd` (effective_move swift; compute_attack_targets range)
- Modify: `godot/core/game_state.gd` (heal clamps via Relics.max_hp; regenring tick)
- Modify: `godot/tests/run_tests.gd`

- [ ] **Step 1: Write the failing tests**

```gdscript
	_test_relic_effects()
```
```gdscript
func _test_relic_effects() -> void:
	var gs := GameState.new_skirmish(Maps.MAPS[0], 7041)
	# atk_charm: +2 power raises base damage vs the same defender
	var atk := gs.spawn_unit("colossus", 0, 2, 2)
	var foe := gs.spawn_unit("cinderling", 1, 3, 2)
	var base_no := Combat.compute_damage(gs, atk, foe)["base"]
	atk["relic"] = "atk_charm"
	var base_atk := Combat.compute_damage(gs, atk, foe)["base"]
	_ok(base_atk > base_no, "relic effect: atk_charm raises base damage")
	atk["relic"] = ""
	# effective_move: swift +1 (stacks with the base move)
	var u := gs.spawn_unit("cinderling", 0, 5, 5)
	var mv_no := Pathfinding.effective_move(u, gs)
	u["relic"] = "swift"
	_eq(Pathfinding.effective_move(u, gs), mv_no + 1, "relic effect: swift +1 move")
	# effective_max_hp + regenring heal in end_turn
	var v := gs.spawn_unit("cinderling", 0, 6, 6)
	v["relic"] = "vital"
	_eq(gs.effective_max_hp(v), v["max_hp"] + 4, "relic effect: vital +4 max hp")
	v["relic"] = "regenring"
	v["hp"] = 3
	v["acted"] = true
	# end_turn heals the INCOMING player's units; make player 0 incoming
	gs.current_player = 1
	gs.end_turn()   # -> player 0 incoming, regenring heals +2
	_eq(v["hp"], 5, "relic effect: regenring heals +2 on turn start")
	# thorncharm: defender's counter does +2 (compare counter dmg via resolve)
	var d := gs.spawn_unit("stoneward", 0, 8, 8)   # tanky, survives to counter
	var atkr := gs.spawn_unit("cinderling", 1, 9, 8)  # adjacent attacker
	d["relic"] = "thorncharm"
	var hp_before := atkr["hp"]
	Combat.resolve_attack(gs, atkr, d)   # d counters; thorncharm adds +2
	# attacker took counter damage; exact value varies by jitter, but with thorncharm
	# the counter is at least base_counter+2 -> attacker lost > 0 hp (sanity)
	_ok(atkr["hp"] < hp_before, "relic effect: thorncharm defender counters")
```
(The thorncharm assertion is a sanity check; the precise +2 is verified by the implementation reading `Relics.unit_bonus(defender,"counter")` in the counter calc.)

- [ ] **Step 2: Run harness, verify fail** (`effective_max_hp` not found / mismatches), EXIT 1.

- [ ] **Step 3: `combat.gd` — atk_charm + maxHP fraction**

Add the preload near the others:
```gdscript
const Relics = preload("res://data/relics.gd")
```
In `compute_damage`, change the `raw` line to include the atk relic + effective max HP:
```gdscript
	var power: int = int(attacker["power"]) + int(Relics.unit_bonus(attacker, "atk"))
	var raw: float = power * (float(attacker["hp"]) / float(Relics.max_hp(attacker)) * 0.5 + 0.5)
```
(Replaces the old `attacker["power"]` / `attacker["max_hp"]` usage in `raw`.)

- [ ] **Step 4: `combat.gd` — thorncharm on the counter**

In `resolve_attack`, the counter block computes `counter_dmg`. Add the defender's thorncharm bonus:
```gdscript
		var counter_dmg: int = maxi(1, roundi(_jitter(state, a2["base"]) * 0.8)) + int(Relics.unit_bonus(defender, "counter"))
```
Also mirror it in `forecast_battle` so the preview matches — change the `c_base` line:
```gdscript
		c_base = maxi(1, roundi(compute_damage(state, defender, attacker)["base"] * 0.8)) + int(Relics.unit_bonus(defender, "counter"))
```

- [ ] **Step 5: `pathfinding.gd` — swift + effective_range**

Add the preload:
```gdscript
const Relics = preload("res://data/relics.gd")
```
In `effective_move`, after the existing modifiers, before `return m`:
```gdscript
	m += int(Relics.unit_bonus(unit, "move"))
```
In `compute_attack_targets`, change the range check from `unit["range"]` to the effective range:
```gdscript
		if d <= Relics.effective_range(unit) and d >= 1:
```
(Also: in `combat.gd compute_damage`, the `w_ranged` check uses `attacker["range"] >= 2`; change it to `Relics.effective_range(attacker) >= 2` so a farsight-boosted unit gets ranged-weather treatment consistently.)

- [ ] **Step 6: `game_state.gd` — effective_max_hp + heal clamps + regenring**

Add the preload near the top consts:
```gdscript
const Relics = preload("res://data/relics.gd")
```
Add the helper:
```gdscript
## effective_max_hp — base max HP plus a vital relic. Single source for heal clamps.
func effective_max_hp(unit: Dictionary) -> int:
	return Relics.max_hp(unit)
```
In `end_turn`, the per-unit incoming loop: change the tower/castle heal clamps to use `effective_max_hp`, and add the regenring heal after them:
```gdscript
		if c != null and c["terrain"] == "tower" and c.get("owner", -1) == u["owner"]:
			u["hp"] = mini(effective_max_hp(u), u["hp"] + 2)
		if c != null and c["terrain"] == "castle" and c.get("owner", -1) == u["owner"]:
			u["hp"] = mini(effective_max_hp(u), u["hp"] + 4)
		var rg: int = int(Relics.unit_bonus(u, "regen"))
		if rg > 0:
			u["hp"] = mini(effective_max_hp(u), u["hp"] + rg)
		Units.try_evolve(u, c)
```

- [ ] **Step 7: Run harness, verify pass** — `== N passed, 0 failed ==`, EXIT 0.

- [ ] **Step 8: Commit**
```bash
git add godot/core/combat.gd godot/core/pathfinding.gd godot/core/game_state.gd godot/tests/run_tests.gd
git commit -m "[godot] P2 relics task 2: passive stat effects (atk/swift/farsight/vital/regen/thorn)"
```

---

## Task 3: Map-gen relic spawn + per-map counts

**Files:**
- Modify: `godot/core/map_gen.gd`
- Modify: `godot/data/maps.gd`, `godot/data/campaign.gd`
- Modify: `godot/tests/run_tests.gd`

- [ ] **Step 1: Write the failing test**

```gdscript
	_test_relic_spawn()
```
```gdscript
func _test_relic_spawn() -> void:
	var def := {"key": "t", "name": "T", "cols": 12, "rows": 10, "seed": 7041,
		"mountains": 2, "lakes": 1, "forests": 8, "hills": 6, "towers": 3, "relics": 3}
	var m := MapGen.generate(7041, def)
	_ok(m.has("relics"), "spawn: map has relics list")
	_eq(m["relics"].size(), 3, "spawn: placed def.relics count")
	for r in m["relics"]:
		var cell = m["cells"]["%d,%d" % [r["q"], r["r"]]]
		_eq(cell["terrain"], "plain", "spawn: relic on plain tile")
		_ok(Relics.RELICS.has(r["relic"]), "spawn: valid relic id")
	# determinism: same seed+def -> identical relic layout
	var m2 := MapGen.generate(7041, def)
	_eq(m2["relics"], m["relics"], "spawn: deterministic for fixed seed")
	# zero relics when unspecified
	var def0 := {"key": "z", "name": "Z", "cols": 10, "rows": 8, "seed": 5,
		"mountains": 1, "lakes": 1, "forests": 4, "hills": 4, "towers": 2}
	_eq(MapGen.generate(5, def0)["relics"].size(), 0, "spawn: no relics key -> 0")
```

- [ ] **Step 2: Run harness, verify fail** (`map has relics list` fails), EXIT 1.

- [ ] **Step 3: `map_gen.gd` — place relics after towers**

Add the preload at the top:
```gdscript
const Relics = preload("res://data/relics.gd")
```
After the tower-placement loop (just before the final `return {...}`), add:
```gdscript
	# Relics: plain cells, >=3 from castles, >=2 from towers and other relics. Each
	# tile rolls a relic id from the pool. Deterministic via the seeded rng.
	var relics: Array = []
	var rcount: int = int(def.get("relics", 0))
	var rng := Rng.new(seed + 99991)   # distinct stream from terrain/towers
	var rguard := 0
	while relics.size() < rcount and rguard < 800:
		rguard += 1
		var rq := rng.below(cols)
		var rr := rng.below(rows)
		var rc: Variant = cells.get("%d,%d" % [rq, rr])
		if rc == null or rc["terrain"] != "plain":
			continue
		var rp := Vector2i(rq, rr)
		if Hex.distance(rp, Vector2i(start_a.x, start_a.y)) < 3 or Hex.distance(rp, Vector2i(start_b.x, start_b.y)) < 3:
			continue
		var clash := false
		for t in towers:
			if Hex.distance(t, rp) < 2:
				clash = true
		for er in relics:
			if Hex.distance(Vector2i(er["q"], er["r"]), rp) < 2:
				clash = true
		if clash:
			continue
		relics.append({"q": rq, "r": rr, "relic": Relics.POOL[rng.below(Relics.POOL.size())]})
	return {"cols": cols, "rows": rows, "cells": cells, "castles": castles, "towers": towers, "relics": relics}
```
(Use the existing `start_a`/`start_b` castle anchors the tower loop already references — confirm those variable names in the file and match them; if the tower loop used `pa`/`pb`, reuse those instead. `Rng` is already preloaded in map_gen.)

- [ ] **Step 4: Add `relics` counts to the data defs**

In `godot/data/maps.gd`, add `"relics": 2` (frontier/tides/crags) and `"relics": 3` (verdant — the big 6-spire map) to each MAPS entry dict.
In `godot/data/campaign.gd`, add `"relics": 2` to each mission's `map` dict (all four).

- [ ] **Step 5: Run harness, verify pass.** Also run the headless-boot gate (map_gen changed): clean.

- [ ] **Step 6: Commit**
```bash
git add godot/core/map_gen.gd godot/data/maps.gd godot/data/campaign.gd godot/tests/run_tests.gd
git commit -m "[godot] P2 relics task 3: map-gen relic spawn + per-map counts"
```

---

## Task 4: Pickup (equip/swap/Ley) + board glyph + card line + SFX

**Files:**
- Modify: `godot/core/game_state.gd` (`pick_up_relic`)
- Modify: `godot/scenes/match/match_scene.gd` (call it after moves)
- Modify: `godot/scenes/board/board.gd` (relic glyph)
- Modify: `godot/scenes/hud/info_card.gd` (relic line)
- Modify: `godot/tests/run_tests.gd`

- [ ] **Step 1: Write the failing test (pickup logic is pure-ish — on GameState)**

```gdscript
	_test_relic_pickup()
```
```gdscript
func _test_relic_pickup() -> void:
	var gs := GameState.new_skirmish(Maps.MAPS[0], 7041)
	gs.map["relics"] = [{"q": 3, "r": 3, "relic": "atk_charm"}]
	var u := gs.spawn_unit("cinderling", 0, 3, 3)
	# equip into empty slot
	_eq(gs.pick_up_relic(u), "atk_charm", "pickup: returns equipped id")
	_eq(u["relic"], "atk_charm", "pickup: unit equips")
	_eq(gs.map["relics"].size(), 0, "pickup: tile cleared on empty-slot equip")
	# swap: dropping old back onto the tile
	gs.map["relics"] = [{"q": 3, "r": 3, "relic": "swift"}]
	_eq(gs.pick_up_relic(u), "swift", "pickup: swap returns new id")
	_eq(u["relic"], "swift", "pickup: unit now holds new")
	_eq(gs.map["relics"].size(), 1, "pickup: old relic dropped on tile")
	_eq(gs.map["relics"][0]["relic"], "atk_charm", "pickup: dropped relic is the old one")
	# vital tops up hp on equip
	gs.map["relics"] = [{"q": 4, "r": 4, "relic": "vital"}]
	var w := gs.spawn_unit("cinderling", 0, 4, 4)
	var hp0 := w["hp"]
	gs.pick_up_relic(w)
	_eq(w["hp"], hp0 + 4, "pickup: vital tops up hp by 4")
	# ley_crystal: master applies MP + tile cleared; non-master leaves it
	gs.map["relics"] = [{"q": 5, "r": 5, "relic": "ley_crystal"}]
	var grunt := gs.spawn_unit("cinderling", 0, 5, 5)
	_eq(gs.pick_up_relic(grunt), "", "pickup: non-master leaves ley_crystal")
	_eq(gs.map["relics"].size(), 1, "pickup: ley tile remains for non-master")
	var master = gs.master_of(0)
	master["q"] = 5; master["r"] = 5
	var mp0 := master["mp"]
	_eq(gs.pick_up_relic(master), "ley_crystal", "pickup: master takes ley")
	_eq(master["mp"], mini(master["max_mp"], mp0 + 6), "pickup: ley grants +6 mp (capped)")
	_eq(master["relic"], "", "pickup: ley never equips")
	_eq(gs.map["relics"].size(), 0, "pickup: ley tile cleared")
	# no relic on tile -> ""
	_eq(gs.pick_up_relic(u), "", "pickup: empty tile -> ''")
```

- [ ] **Step 2: Run harness, verify fail** (`pick_up_relic` not found), EXIT 1.

- [ ] **Step 3: `game_state.gd` — `pick_up_relic`**

```gdscript
## pick_up_relic — if a relic sits on `unit`'s tile, resolve pickup and return the
## relic id taken (or "" if none / left). Ley Crystal: master-only, applies MP and
## clears the tile. Others: equip; a full slot drops the old relic back onto the tile.
func pick_up_relic(unit: Dictionary) -> String:
	var relics: Array = map.get("relics", [])
	var idx := -1
	for i in relics.size():
		if relics[i]["q"] == unit["q"] and relics[i]["r"] == unit["r"]:
			idx = i
			break
	if idx < 0:
		return ""
	var rid: String = relics[idx]["relic"]
	if Relics.RELICS[rid].get("master_only", false):
		if not unit.get("is_master", false):
			return ""   # non-master leaves it
		unit["mp"] = mini(unit["max_mp"], unit["mp"] + int(Relics.bonus(rid, "mp")))
		relics.remove_at(idx)
		return rid
	var old: String = unit.get("relic", "")
	unit["relic"] = rid
	if int(Relics.bonus(rid, "max_hp")) > 0:
		unit["hp"] = mini(effective_max_hp(unit), unit["hp"] + int(Relics.bonus(rid, "max_hp")))
	if old != "":
		relics[idx] = {"q": unit["q"], "r": unit["r"], "relic": old}   # swap: drop old
	else:
		relics.remove_at(idx)
	return rid
```

- [ ] **Step 4: `match_scene.gd` — call pickup after a move commits**

In `_on_click`, after the human move slides and BEFORE `_open_menu_for(selected)` (i.e. right after `selected["q"]/["r"]` are set + the slide awaited), add:
```gdscript
		var got := state.pick_up_relic(selected)
		if got != "":
			Audio.beep(720.0, 0.08, "triangle", 0.2)
			units_layer.set_state(state)
```
Also call it for AI moves: in `_play_battles`/the AI path, after `AI.take_turn(state)` resolves (the AI moves units), iterate the AI's units and pick up — simplest: make `AI.take_turn` itself call `state.pick_up_relic(u)` at each unit's move-end. EDIT `core/ai.gd`: wherever a unit's move is committed (its q/r updated), append `state.pick_up_relic(u)`. (See Task 7 note — fold this single call into the AI move commit there; for THIS task, only the human pickup + the GameState method are required. Mark the AI pickup as done in Task 7.)

Also refresh the info card after pickup if the unit is selected — `info_card.show_unit(selected)` already runs in `_open_menu_for`; the relic line (Step 6) renders from the unit record.

- [ ] **Step 5: `board.gd` — draw relic glyphs**

`board.gd` draws the terrain. Add a relic-glyph pass. The board has the map (`set_map`); add a method to also receive `map["relics"]` (or read from the stored map). In `board.gd`'s `_draw` (after terrain), for each relic in `map.get("relics", [])`: draw a small colored gem (a `draw_circle`/diamond in the relic's `color`) + the glyph char centered, at `Hex.axial_to_pixel(Vector2i(r.q, r.r))`. Pull `Relics.RELICS[r["relic"]]` for `color`/`glyph`. Add `const Relics = preload("res://data/relics.gd")`. If `board.gd` stores the map dict, ensure it's the live `state.map` (so picked-up relics disappear on the next `queue_redraw`); `match_scene` calls `board.queue_redraw()` after pickups (add that call after `state.pick_up_relic`).

- [ ] **Step 6: `info_card.gd` — relic line**

In the card's unit display, if `unit.get("relic","") != ""`, add a line: `"Relic: " + Relics.RELICS[unit["relic"]]["name"]`. Add `const Relics = preload("res://data/relics.gd")`.

- [ ] **Step 7: Harness + boot gates** — both green/clean.

- [ ] **Step 8: Commit**
```bash
git add godot/core/game_state.gd godot/scenes/match/match_scene.gd godot/scenes/board/board.gd godot/scenes/hud/info_card.gd godot/tests/run_tests.gd
git commit -m "[godot] P2 relics task 4: pickup (equip/swap/ley) + board glyph + card line + SFX"
```

---

## Task 5: Save — serialize map.relics

**Files:**
- Modify: `godot/core/save_game.gd`
- Modify: `godot/tests/run_tests.gd`

- [ ] **Step 1: Write the failing test** — extend `_test_save` (append):
```gdscript
	# relics: map.relics + unit.relic round-trip
	var rgs := GameState.new_skirmish(Maps.MAPS[0], 7041)
	rgs.map["relics"] = [{"q": 2, "r": 2, "relic": "swift"}]
	var ru := rgs.spawn_unit("cinderling", 0, 1, 1)
	ru["relic"] = "atk_charm"
	var rblob = SaveGame.from_dict(JSON.parse_string(JSON.stringify(SaveGame.to_dict(rgs))))
	_eq(rblob.map["relics"], [{"q": 2, "r": 2, "relic": "swift"}], "save: map.relics round-trips")
	var ru2 = rblob.unit_at(1, 1)
	_eq(ru2["relic"], "atk_charm", "save: unit.relic round-trips")
	# old blob (no relics key) defaults to []
	var noblob := SaveGame.to_dict(rgs)
	noblob.erase("relics")
	_eq(SaveGame.from_dict(noblob).map["relics"], [], "save: missing relics -> []")
```
(Note: the JSON round-trip turns the `{q,r}` ints into floats then `from_dict` must re-int them — mirror the existing unit/stats coercion.)

- [ ] **Step 2: Run harness, verify fail**, EXIT 1.

- [ ] **Step 3: `save_game.gd` — serialize + restore relics**

In `to_dict`, add to the returned blob:
```gdscript
		"relics": (state.map.get("relics", []) as Array).duplicate(true),
```
In `from_dict`, after the map dict is built, restore relics (re-int the coords from JSON floats):
```gdscript
	var relics: Array = []
	for r in blob.get("relics", []):
		relics.append({"q": int(r["q"]), "r": int(r["r"]), "relic": String(r["relic"])})
	gs.map["relics"] = relics
```

- [ ] **Step 4: Run harness, verify pass.**

- [ ] **Step 5: Commit**
```bash
git add godot/core/save_game.gd godot/tests/run_tests.gd
git commit -m "[godot] P2 relics task 5: save/load map.relics round-trip"
```

---

## Task 6: Consumables — Phoenix + Warhorn + Ley (Ley done in T4)

Phoenix (revive) + Warhorn (×1.5 then consume). Ley Crystal already lands in Task 4's `pick_up_relic`.

**Files:**
- Modify: `godot/core/combat.gd` (warhorn in compute_damage + clear; phoenix in `_apply_hit`)
- Modify: `godot/tests/run_tests.gd`

- [ ] **Step 1: Write the failing tests**

```gdscript
	_test_relic_consumables()
```
```gdscript
func _test_relic_consumables() -> void:
	var gs := GameState.new_skirmish(Maps.MAPS[0], 7041)
	# warhorn: boosts compute_damage base ~1.5x, then clears after the swing
	var atk := gs.spawn_unit("colossus", 0, 2, 2)
	var foe := gs.spawn_unit("stoneward", 1, 3, 2)
	var base_no := Combat.compute_damage(gs, atk, foe)["base"]
	atk["relic"] = "warhorn"
	var base_wh := Combat.compute_damage(gs, atk, foe)["base"]
	_ok(base_wh > base_no, "consumable: warhorn boosts base damage")
	Combat.resolve_attack(gs, atk, foe)
	_eq(atk["relic"], "", "consumable: warhorn consumed after attack")
	# phoenix: a lethal hit leaves the bearer at 1 hp, relic cleared, alive
	var killer := gs.spawn_unit("colossus", 0, 6, 6)
	var victim := gs.spawn_unit("cinderling", 1, 7, 6)
	victim["relic"] = "phoenix"
	victim["hp"] = 1   # ensure the swing is lethal
	Combat.resolve_attack(gs, killer, victim)
	_eq(victim["hp"], 1, "consumable: phoenix revives at 1 hp")
	_eq(victim["relic"], "", "consumable: phoenix consumed")
	_ok(gs.unit_at(7, 6) != null, "consumable: phoenix-saved unit still alive")
	# a second lethal hit (no phoenix now) kills
	victim["hp"] = 1
	Combat.resolve_attack(gs, killer, victim)
	_ok(victim["hp"] <= 0, "consumable: no phoenix second time -> dead")
```

- [ ] **Step 2: Run harness, verify fail**, EXIT 1.

- [ ] **Step 3: `combat.gd` — warhorn boost + phoenix revive**

In `compute_damage`, after `base` is computed, apply the warhorn multiplier:
```gdscript
	if Relics.has_relic(attacker, "warhorn"):
		base = maxi(1, roundi(base * float(Relics.bonus(attacker, "atk_mult"))))
```
(Place it right before the `return {...}`; update the returned `base`.)

In `resolve_attack`, after the attacker's primary swing is applied (after the `_apply_hit` for the primary), clear a spent warhorn:
```gdscript
	if Relics.has_relic(attacker, "warhorn"):
		attacker["relic"] = ""
```
(Place it after the primary `_apply_hit` call, before the counter block — the boost already applied to that swing's damage via compute_damage.)

In `_apply_hit`, add Phoenix just after `dst["hp"] -= dmg` / the `killed` computation:
```gdscript
	dst["hp"] -= dmg
	var killed: bool = dst["hp"] <= 0
	if killed and Relics.has_relic(dst, "phoenix"):
		dst["hp"] = 1
		dst["relic"] = ""
		killed = false
	var xp_amt: int = dmg + (Units.KILL_XP_BONUS if killed else 0)
```
(Phoenix flips `killed` to false so no kill XP / death; both primary and counter route through `_apply_hit`, so both are covered.)

- [ ] **Step 4: Run harness, verify pass.**

- [ ] **Step 5: Commit**
```bash
git add godot/core/combat.gd godot/tests/run_tests.gd
git commit -m "[godot] P2 relics task 6: consumables — phoenix revive + warhorn burst"
```

---

## Task 7: AI relic pickup + move-nudge

**Files:**
- Modify: `godot/core/ai.gd`
- Modify: `godot/tests/run_tests.gd`

- [ ] **Step 1: Write the failing test**

Find the AI move-scoring helper (the move-only branch of `decide_unit_action` / `score_attacks` that scores candidate end-tiles). The test asserts the AI prefers a relic tile when otherwise-equal. A robust, low-coupling test: a small bonus is added to a candidate tile that holds a relic. Add:
```gdscript
	_test_ai_relic_nudge()
```
```gdscript
func _test_ai_relic_nudge() -> void:
	# relic_tile_bonus is a small pure helper: >0 when the tile holds an un-owned relic
	var gs := GameState.new_skirmish(Maps.MAPS[0], 7041)
	gs.map["relics"] = [{"q": 4, "r": 4, "relic": "atk_charm"}]
	_ok(AI.relic_tile_bonus(gs, 4, 4) > 0.0, "ai: relic tile scored positively")
	_eq(AI.relic_tile_bonus(gs, 0, 0), 0.0, "ai: non-relic tile no bonus")
```

- [ ] **Step 2: Run harness, verify fail** (`relic_tile_bonus` not found), EXIT 1.

- [ ] **Step 3: `ai.gd` — add the helper + fold into move scoring + AI pickup**

Add the pure helper:
```gdscript
## relic_tile_bonus — a small move-scoring nudge for ending on a relic tile.
static func relic_tile_bonus(state, q: int, r: int) -> float:
	for rl in state.map.get("relics", []):
		if rl["q"] == q and rl["r"] == r:
			return 3.0
	return 0.0
```
In the move-only scoring (where a candidate end-tile's score is accumulated — the same place `score_attacks`/`decide_unit_action` evaluates a destination tile), add `+ relic_tile_bonus(state, cand_q, cand_r)` to the tile's score (use the candidate tile's q/r variables already in scope there).
In `take_turn`, after a unit's move is committed (its `q`/`r` updated to the chosen destination), add the pickup call:
```gdscript
		state.pick_up_relic(u)
```
(This is the AI-pickup deferred from Task 4. Place it right after the AI applies a unit's move.)

- [ ] **Step 4: Run harness, verify pass.** Also headless-boot (ai.gd is core, but match_scene drives it — boot clean).

- [ ] **Step 5: Commit**
```bash
git add godot/core/ai.gd godot/tests/run_tests.gd
git commit -m "[godot] P2 relics task 7: AI relic pickup + move-nudge"
```

---

## Manual (windowed) verification — after Task 7

`godot --path godot`: relic glyphs (colored gem + letter) show on the board; ending a move on one equips it (info-card relic line + SFX); a full slot drops the old relic onto the tile; the +HP relic bumps the bar; Phoenix saves a unit once in a battle; the AI walks onto relics; save/resume keeps relics + equipped slots.

## Final milestone review

After Task 7: whole-milestone opus review over `git diff <base>..HEAD -- godot/` (base = the plan commit). Then:
- Check off `ROADMAP2.md` 2.1 + 2.2.
- Update `SESSION_STATE.md`: Phase 2 (relics) complete; next = Phase 3 (fog of war), its own spec. Note Veilstone lands in Phase 3.
- Record accepted divergences (procedural glyphs; `effective_max_hp`/`effective_range` dynamic seams; Veilstone deferred).

---

## Self-review notes (author)

- **Spec coverage:** relic table (T1) ✓; 6 passive effects + thorncharm (T2) ✓; spawn + per-map counts (T3) ✓; pickup equip/swap/Ley + glyph + card + SFX (T4) ✓; save (T5) ✓; Phoenix + Warhorn (T6) ✓; AI pickup + nudge (T7) ✓; Veilstone deferred ✓.
- **Type consistency:** `Relics.unit_bonus/bonus/max_hp/effective_range/has_relic/is_passive/is_consumable/POOL/RELICS` defined in T1, used consistently in T2/T3/T4/T6/T7. `GameState.effective_max_hp` (T2) used by `pick_up_relic` (T4). `pick_up_relic` (T4) called by AI (T7) + match_scene (T4). `map["relics"]` shape `{q,r,relic}` consistent across map_gen/pickup/save/AI/board.
- **Ordering:** T1 data → T2 effects → T3 spawn → T4 pickup (needs effective_max_hp from T2) → T5 save → T6 consumables → T7 AI (needs pick_up_relic from T4). Sound.
- **Verify-in-file notes:** map_gen castle anchor var names (`start_a`/`start_b` vs `pa`/`pb`) — the implementer matches the actual names. AI move-scoring insertion point — the implementer locates the candidate-tile score accumulation; the pure `relic_tile_bonus` helper is the tested seam, the in-tree wiring is light.
