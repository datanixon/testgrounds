# Wraithspire Godot Port — Milestone 5: All 12 Abilities — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax.

**Goal:** Port all 12 monster-line abilities — the data table + the three resolution paths (instant self/area, enemy-target attack-with-status, tile-target Blink teleport) — into the pure Godot core, wired into the existing combat/status/weather systems, and triggerable on the board.

**Architecture:** A `data/abilities.gd` const table + `ability_for(unit)` helper (evolved forms get cd-1). Enemy-target abilities reuse `Combat.resolve_attack`, which gains an optional status payload (the JS `applySwing` `applyStatus` path). Instant (target:"none") and tile (Blink) abilities live in a new pure `core/ability_resolve.gd`. Cooldown lives on `unit["cd"]` (already decremented in `end_turn`); the CALLER sets it after a cast (matching the JS contract that `resolveInstantAbility` "sets nothing on the unit"). `main.gd` gets a minimal cast keybind (instant fires immediately; enemy/tile arm-then-click) — the full action menu is M7.

**Tech Stack:** GDScript, the headless harness (`pwsh -ExecutionPolicy Bypass -File godot/tests/run_tests.ps1`). Reference: `game.js` — ABILITIES table (5733–5746), abilityFor (5749–5755), resolveInstantAbility (5760–5815), enemy-ability via beginBattle payload (4301) + applySwing status (2385), Blink targeting (4673–4684) + teleport (4269–4275).

**Scope note:** M5 ports ability RESOLUTION + data + the combat status-payload seam. The AI ability scorer (`aiScoreInstantAbility`, game.js 5822) is **M6** (AI) — do NOT port it here. The full post-move action MENU + ability buttons + cooldown display are **M7** (HUD) — M5 uses a minimal cast keybind for on-screen verification. Summoning is **M7** (the M4 temp debug keys for fielding units stay until then).

---

## File structure (this milestone)

```
godot/data/abilities.gd        const ABILITIES (12) + ability_for(unit) (evolved cd-1)   [class Abilities]
godot/core/ability_resolve.gd  resolve_instant (heal/quake/skitter/galeRush/bulwark/ward)
                               + blink_targets / do_blink                                [class AbilityResolve]
godot/core/combat.gd           resolve_attack gains (apply_status, status_turns) params  [MODIFY]
godot/scenes/main.gd           cast keybind: instant fires now; enemy/tile arm→click     [MODIFY]
godot/tests/run_tests.gd       + _test_abilities_data, _test_attack_status,
                               _test_instant_abilities, _test_blink                      [MODIFY]
ROADMAP_GODOT.md               check off M5
```

**Class-name note:** the DATA file `data/abilities.gd` is `class_name Abilities`; the LOGIC file `core/ability_resolve.gd` is `class_name AbilityResolve`. Distinct names — do not merge.

---

## Task 1: Abilities data table + ability_for

Port the ABILITIES table and the `ability_for` helper. Enemy abilities carry `status`/`status_turns`; evolved forms shave 1 off the cooldown (min 1).

**Files:** Create `godot/data/abilities.gd`; Modify `godot/tests/run_tests.gd`.

- [ ] **Step 1: Add failing tests to `godot/tests/run_tests.gd`**

Add a preload (with the other data preloads):
```gdscript
const Abilities = preload("res://data/abilities.gd")
```
Add the call in `_initialize`, after `_test_turn()`:
```gdscript
	_test_abilities_data()
```
Append:
```gdscript
func _test_abilities_data() -> void:
	_eq(Abilities.ABILITIES.size(), 12, "abilities: 12 entries")
	_eq(Abilities.ABILITIES["ignite"]["target"], "enemy", "abilities: ignite is enemy-target")
	_eq(Abilities.ABILITIES["ignite"]["status"], "burn", "abilities: ignite burns")
	_eq(Abilities.ABILITIES["ignite"]["status_turns"], 2, "abilities: ignite 2 turns")
	_eq(Abilities.ABILITIES["healPulse"]["target"], "none", "abilities: heal is instant")
	_eq(Abilities.ABILITIES["blink"]["target"], "tile", "abilities: blink is tile-target")
	_eq(Abilities.ABILITIES["quake"]["cd"], 4, "abilities: quake cd 4")
	# ability_for: reads the unit's type ability; evolved shaves cd by 1 (min 1).
	var cinder := Units.make_unit(1, "cinderling", 0, 0, 0)   # ability ignite (cd 3), not evolved
	var ab := Abilities.ability_for(cinder)
	_eq(ab["key"], "ignite", "ability_for: cinderling -> ignite")
	_eq(ab["cd"], 3, "ability_for: base cd")
	var infern := Units.make_unit(2, "infernite", 0, 0, 0)    # evolved form, ability ignite
	_eq(Abilities.ability_for(infern)["cd"], 2, "ability_for: evolved cd-1")
	# master has no ability (type_key "master" not in UNIT_TYPES).
	var m := Units.make_master(3, 0, 0, 0)
	_eq(Abilities.ability_for(m), null, "ability_for: master has none")
```

- [ ] **Step 2: Run — verify it fails (abilities.gd missing)**
```
pwsh -ExecutionPolicy Bypass -File godot/tests/run_tests.ps1; "EXIT=$LASTEXITCODE"
```
Expected: load error about `res://data/abilities.gd`, non-zero EXIT.

- [ ] **Step 3: Create `godot/data/abilities.gd`, verbatim** (port of game.js 5733–5755):
```gdscript
class_name Abilities
extends RefCounted
## Port of game.js ABILITIES + abilityFor (sec. 18). One active ability per monster
## line — an alternative to attacking. Cooldown lives on unit["cd"] (ticked in
## end_turn). target kinds: "none" (instant, resolve at current hex), "enemy"
## (attack-flavored, runs through Combat.resolve_attack with a status payload),
## "tile" (Blink teleport). JS `statusTurns` -> snake_case `status_turns`.

const UnitTypes = preload("res://data/unit_types.gd")

const ABILITIES := {
	"healPulse":    {"name": "Heal Pulse",    "cd": 3, "target": "none",  "desc": "+5 HP to adjacent allies"},
	"quake":        {"name": "Quake",         "cd": 4, "target": "none",  "desc": "4 dmg to all adjacent enemies, no counter"},
	"skitter":      {"name": "Skitter",       "cd": 2, "target": "none",  "desc": "take a second move-only action (+2 MOV)"},
	"frostBite":    {"name": "Frost Bite",    "cd": 3, "target": "enemy", "desc": "attack; slows the target", "status": "slow", "status_turns": 2},
	"ignite":       {"name": "Ignite",        "cd": 3, "target": "enemy", "desc": "attack; burns the target", "status": "burn", "status_turns": 2},
	"cinderBreath": {"name": "Cinder Breath", "cd": 4, "target": "enemy", "desc": "attack; burns the target", "status": "burn", "status_turns": 2},
	"undertow":     {"name": "Undertow",      "cd": 3, "target": "enemy", "desc": "attack; slows the target", "status": "slow", "status_turns": 2},
	"diveMark":     {"name": "Dive Mark",     "cd": 4, "target": "enemy", "desc": "attack; marks the target", "status": "mark", "status_turns": 2},
	"bulwark":      {"name": "Bulwark",       "cd": 3, "target": "none",  "desc": "+2 DEF to self & adjacent allies for a turn"},
	"ward":         {"name": "Ward",          "cd": 4, "target": "none",  "desc": "shield self & adjacent allies from the next hit"},
	"blink":        {"name": "Blink",         "cd": 3, "target": "tile",  "desc": "teleport up to 4 hexes"},
	"galeRush":     {"name": "Gale Rush",     "cd": 4, "target": "none",  "desc": "take a second move-only action"},
}

## abilityFor — the ability record for `unit`'s type, with `key` added. Evolved forms
## get cd reduced by 1 (min 1). Returns null if the type has no ability (e.g. master).
static func ability_for(unit: Dictionary) -> Variant:
	var t: Dictionary = UnitTypes.UNIT_TYPES.get(unit["type_key"], {})
	if not t.has("ability"):
		return null
	var base: Dictionary = ABILITIES.get(t["ability"], {})
	if base.is_empty():
		return null
	var out := base.duplicate()
	out["key"] = t["ability"]
	out["cd"] = maxi(1, base["cd"] - (1 if unit.get("evolved", false) else 0))
	return out
```

- [ ] **Step 4: Run — verify pass**
```
pwsh -ExecutionPolicy Bypass -File godot/tests/run_tests.ps1; "EXIT=$LASTEXITCODE"
```
Expected: green, `EXIT=0`. Baseline `236 passed`; ~11 new → ~247. `0 failed` is the gate.

- [ ] **Step 5: Commit**
```
git add godot/data/abilities.gd godot/tests/run_tests.gd
git commit -m "[godot] M5: abilities data table + ability_for (evolved cd-1)"
```

---

## Task 2: resolve_attack status payload (enemy abilities)

Enemy-target abilities are attack-flavored: they run the normal battle but apply a status to the defender on the hit. Extend `Combat.resolve_attack` (and its `_apply_hit`) with optional `apply_status` / `status_turns` params. The status applies ONLY on the primary swing (not the counter) and ONLY if the defender survives the hit — a faithful port of the JS `applySwing` rule `if (!counter && b.applyStatus && dst.hp > 0) addStatus(...)`. A ward-absorbed hit applies no status (the early return covers it).

**Files:** Modify `godot/core/combat.gd`, `godot/tests/run_tests.gd`.

- [ ] **Step 1: Add failing tests to `godot/tests/run_tests.gd`**

Add the call after `_test_abilities_data()`:
```gdscript
	_test_attack_status()
```
Append:
```gdscript
func _test_attack_status() -> void:
	# ignite: a surviving defender gets burn(2).
	var gs := _combat_state()
	gs.rng = Rng.new(5)
	var atk := gs.spawn_unit("cinderling", 0, 2, 3)
	var dfn := gs.spawn_unit("stoneward", 1, 3, 3)   # 22 hp, survives a cinderling hit
	Combat.resolve_attack(gs, atk, dfn, "burn", 2)
	_ok(Status.has_status(dfn, "burn"), "attack-status: surviving defender burns")
	_eq(dfn["status"]["burn"], 2, "attack-status: 2 turns")
	# a dead defender gets no status (it's gone).
	var gs2 := _combat_state()
	gs2.rng = Rng.new(5)
	var a2 := gs2.spawn_unit("cinderling", 0, 2, 3)
	var d2 := gs2.spawn_unit("galewisp", 1, 3, 3)
	d2["hp"] = 2
	Combat.resolve_attack(gs2, a2, d2, "burn", 2)
	_ok(d2["hp"] <= 0, "attack-status: lethal kills")
	_ok(not Status.has_status(d2, "burn"), "attack-status: no status on a dead target")
	# the counter does NOT inflict the attacker's status on the attacker.
	var gs3 := _combat_state()
	gs3.rng = Rng.new(5)
	var a3 := gs3.spawn_unit("stoneward", 0, 2, 3)   # terra, weak vs nothing; survives
	var d3 := gs3.spawn_unit("galewisp", 1, 3, 3)     # range 2, counters
	Combat.resolve_attack(gs3, a3, d3, "burn", 2)
	_ok(not Status.has_status(a3, "burn"), "attack-status: counter inflicts no status on attacker")
	# a basic attack (no payload) inflicts nothing.
	var gs4 := _combat_state()
	gs4.rng = Rng.new(5)
	var a4 := gs4.spawn_unit("cinderling", 0, 2, 3)
	var d4 := gs4.spawn_unit("stoneward", 1, 3, 3)
	Combat.resolve_attack(gs4, a4, d4)
	_ok(not Status.has_status(d4, "burn"), "attack-status: plain attack inflicts nothing")
	# a warded defender absorbs the hit AND takes no status.
	var gs5 := _combat_state()
	gs5.rng = Rng.new(5)
	var a5 := gs5.spawn_unit("cinderling", 0, 2, 3)
	var d5 := gs5.spawn_unit("stoneward", 1, 3, 3)
	Status.add_status(d5, "ward", 1)
	Combat.resolve_attack(gs5, a5, d5, "burn", 2)
	_ok(not Status.has_status(d5, "burn"), "attack-status: warded hit applies no status")
```

- [ ] **Step 2: Run — verify it fails (resolve_attack arity / status not applied)**
```
pwsh -ExecutionPolicy Bypass -File godot/tests/run_tests.ps1; "EXIT=$LASTEXITCODE"
```
Expected: error about `resolve_attack` argument count, non-zero EXIT.

- [ ] **Step 3: Modify `godot/core/combat.gd`.** REPLACE the existing `resolve_attack` and `_apply_hit` (keep `_jitter` unchanged) with these versions that thread the status payload:
```gdscript
## resolve_attack — INLINE battle (no cutaway). Primary swing, then a counter if the
## defender survives and the attacker is within the defender's range. Jitter and the
## counter 0.8x are drawn from state.rng. `apply_status`/`status_turns` (M5 abilities)
## apply to the defender ONLY on the primary swing and ONLY if it survives — the
## counter never inflicts a status. Mirrors beginBattle + applySwing, minus the
## animation/float/log side effects (those return with the M8 battle scene + M7 HUD).
static func resolve_attack(state, attacker: Dictionary, defender: Dictionary, apply_status := "", status_turns := 0) -> void:
	var a1: Dictionary = compute_damage(state, attacker, defender)
	_apply_hit(state, attacker, defender, _jitter(state, a1["base"]), apply_status, status_turns)
	if defender["hp"] > 0:
		var d: int = state_distance(attacker, defender)
		if d >= 1 and d <= defender["range"]:
			var a2: Dictionary = compute_damage(state, defender, attacker)
			var counter_dmg: int = maxi(1, roundi(_jitter(state, a2["base"]) * 0.8))
			_apply_hit(state, defender, attacker, counter_dmg, "", 0)
	state.check_win_condition()

## _apply_hit — one swing: ward absorbs (consumed, no damage/xp/status); else deal
## `dmg`, award `dmg` (+kill bonus) XP to `src`, leave death detection to hp <= 0, and
## apply `status` to a surviving `dst` (empty string = none). `_state` is unused now;
## reserved for M8 float/log emission without a signature change.
static func _apply_hit(_state, src: Dictionary, dst: Dictionary, dmg: int, status := "", status_turns := 0) -> void:
	if Status.has_status(dst, "ward"):
		dst["status"].erase("ward")
		return
	dst["hp"] -= dmg
	var killed: bool = dst["hp"] <= 0
	var xp_amt: int = dmg + (Units.KILL_XP_BONUS if killed else 0)
	Units.gain_xp(src, xp_amt)
	if status != "" and dst["hp"] > 0:
		Status.add_status(dst, status, status_turns)
```

- [ ] **Step 4: Run — verify pass**
```
pwsh -ExecutionPolicy Bypass -File godot/tests/run_tests.ps1; "EXIT=$LASTEXITCODE"
```
Expected: green, `EXIT=0` (~6 new asserts). The existing `_test_resolve` (no-payload calls) still passes — the new params default to `""`/`0`. `0 failed` is the gate.

- [ ] **Step 5: Commit**
```
git add godot/core/combat.gd godot/tests/run_tests.gd
git commit -m "[godot] M5: resolve_attack status payload (enemy abilities inflict on hit)"
```

---

## Task 3: Instant abilities (resolve_instant)

Port `resolveInstantAbility` — the six target:"none" abilities — into a new `core/ability_resolve.gd`. Pure logic on a GameState. Cooldown/acted are the caller's job (the JS contract); `resolve_instant` only applies effects and returns whether it fired.

**Files:** Create `godot/core/ability_resolve.gd`; Modify `godot/tests/run_tests.gd`.

- [ ] **Step 1: Add failing tests to `godot/tests/run_tests.gd`**

Add a preload (with the core preloads):
```gdscript
const AbilityResolve = preload("res://core/ability_resolve.gd")
```
Add the call after `_test_attack_status()`:
```gdscript
	_test_instant_abilities()
```
Append:
```gdscript
func _instant(key: String) -> Dictionary:
	return {"key": key}   # resolve_instant only reads ab["key"]

func _test_instant_abilities() -> void:
	# healPulse: +5 to a wounded adjacent ally, capped at max_hp; full allies untouched.
	var gs := _flat_state(5, 5)
	var caster := gs.spawn_unit("tidekin", 0, 2, 2)      # healPulse line
	var hurt := gs.spawn_unit("stoneward", 0, 3, 2)      # adjacent ally, hp 22
	hurt["hp"] = 10
	var full := gs.spawn_unit("cinderling", 0, 2, 3)     # adjacent ally at full
	_ok(AbilityResolve.resolve_instant(gs, caster, _instant("healPulse")), "instant: heal fired")
	_eq(hurt["hp"], 15, "heal: +5 to wounded ally")
	_eq(full["hp"], full["max_hp"], "heal: full ally untouched")
	# quake: 4 dmg to every adjacent enemy, no counter; caster gains xp; a kill counts.
	var gq := _flat_state(5, 5)
	var ogre := gq.spawn_unit("geomaul", 0, 2, 2)        # quake line
	var e1 := gq.spawn_unit("cinderling", 1, 3, 2)       # adjacent enemy, hp 12
	var e2 := gq.spawn_unit("galewisp", 1, 2, 3)         # adjacent enemy, hp 10
	e2["hp"] = 3                                          # will die to the 4 dmg
	_ok(AbilityResolve.resolve_instant(gq, ogre, _instant("quake")), "instant: quake fired")
	_eq(e1["hp"], 8, "quake: -4 to survivor")
	_ok(e2["hp"] <= 0, "quake: kills the soft target")
	_ok(ogre["xp"] > 0 or ogre["level"] > 1, "quake: caster gained xp")
	# skitter: adds skitterBoost(1) and flags a second move.
	var gsk := _flat_state(5, 5)
	var skink := gsk.spawn_unit("duneskink", 0, 2, 2)
	_ok(AbilityResolve.resolve_instant(gsk, skink, _instant("skitter")), "instant: skitter fired")
	_ok(Status.has_status(skink, "skitterBoost"), "skitter: boost applied")
	_ok(skink["second_move"], "skitter: second move flagged")
	# galeRush: second move, but NO skitterBoost.
	var ggr := _flat_state(5, 5)
	var wisp := ggr.spawn_unit("galewisp", 0, 2, 2)
	_ok(AbilityResolve.resolve_instant(ggr, wisp, _instant("galeRush")), "instant: galeRush fired")
	_ok(wisp["second_move"], "galeRush: second move flagged")
	_ok(not Status.has_status(wisp, "skitterBoost"), "galeRush: no skitter boost")
	# bulwark: self + adjacent allies get bulwark(1); enemies don't.
	var gb := _flat_state(5, 5)
	var ward_u := gb.spawn_unit("stoneward", 0, 2, 2)    # bulwark line
	var ally := gb.spawn_unit("cinderling", 0, 3, 2)
	var enemy := gb.spawn_unit("cinderling", 1, 2, 3)
	_ok(AbilityResolve.resolve_instant(gb, ward_u, _instant("bulwark")), "instant: bulwark fired")
	_ok(Status.has_status(ward_u, "bulwark"), "bulwark: self shielded")
	_ok(Status.has_status(ally, "bulwark"), "bulwark: adjacent ally shielded")
	_ok(not Status.has_status(enemy, "bulwark"), "bulwark: enemy not shielded")
```

- [ ] **Step 2: Run — verify it fails (ability_resolve.gd missing)**
```
pwsh -ExecutionPolicy Bypass -File godot/tests/run_tests.ps1; "EXIT=$LASTEXITCODE"
```
Expected: load error about `res://core/ability_resolve.gd`, non-zero EXIT.

- [ ] **Step 3: Create `godot/core/ability_resolve.gd`, verbatim** (port of game.js resolveInstantAbility 5760–5815, logic only — no floats/logs/beeps):
```gdscript
class_name AbilityResolve
extends RefCounted
## Instant + tile ability resolution — port of game.js resolveInstantAbility + the
## Blink teleport (sec. 18). Enemy-target abilities run through Combat.resolve_attack
## with a status payload (handled in combat.gd, not here). Pure logic on a GameState;
## cooldown/acted are set by the CALLER (matching the JS contract).

const Hex = preload("res://core/hex.gd")
const Status = preload("res://core/status.gd")
const Units = preload("res://core/units.gd")
const Terrain = preload("res://data/terrain.gd")

## resolve_instant — fire a target:"none" ability at the unit's current hex. Returns
## true if it fired. Does NOT set cd/acted (caller owns those).
static func resolve_instant(state, unit: Dictionary, ab: Dictionary) -> bool:
	match ab["key"]:
		"healPulse":
			for n in Hex.neighbors(Vector2i(unit["q"], unit["r"])):
				var a: Variant = state.unit_at(n.x, n.y)
				if a != null and a["owner"] == unit["owner"] and a["hp"] < a["max_hp"]:
					a["hp"] += mini(5, a["max_hp"] - a["hp"])
			return true
		"quake":
			var total := 0
			for n in Hex.neighbors(Vector2i(unit["q"], unit["r"])):
				var e: Variant = state.unit_at(n.x, n.y)
				if e != null and e["owner"] != unit["owner"]:
					e["hp"] -= 4
					total += 4
					if e["hp"] <= 0:
						total += Units.KILL_XP_BONUS
			if total > 0:
				Units.gain_xp(unit, total)
			state.check_win_condition()
			return true
		"skitter", "galeRush":
			if ab["key"] == "skitter":
				Status.add_status(unit, "skitterBoost", 1)
			unit["second_move"] = true
			return true
		"bulwark", "ward":
			Status.add_status(unit, ab["key"], 1)
			for n in Hex.neighbors(Vector2i(unit["q"], unit["r"])):
				var a: Variant = state.unit_at(n.x, n.y)
				if a != null and a["owner"] == unit["owner"]:
					Status.add_status(a, ab["key"], 1)
			return true
	return false
```

- [ ] **Step 4: Run — verify pass**
```
pwsh -ExecutionPolicy Bypass -File godot/tests/run_tests.ps1; "EXIT=$LASTEXITCODE"
```
Expected: green, `EXIT=0` (~16 new asserts). `0 failed` is the gate. Note: a quake that kills can level the caster (kill XP) — the test asserts `xp > 0 or level > 1` to allow either.

- [ ] **Step 5: Commit**
```
git add godot/core/ability_resolve.gd godot/tests/run_tests.gd
git commit -m "[godot] M5: instant abilities (heal/quake/skitter/galeRush/bulwark/ward)"
```

---

## Task 4: Blink (tile teleport)

Port Blink — the only tile-target ability. `blink_targets` returns every hex within 4 of the unit that is empty and landable (not a `blocks` tile, not a `flyers_only` tile for a non-flyer). `do_blink` teleports. Add both to `core/ability_resolve.gd`.

**Files:** Modify `godot/core/ability_resolve.gd`, `godot/tests/run_tests.gd`.

- [ ] **Step 1: Add failing tests to `godot/tests/run_tests.gd`**

Add the call after `_test_instant_abilities()`:
```gdscript
	_test_blink()
```
Append:
```gdscript
func _test_blink() -> void:
	var gs := _flat_state(11, 11)
	var hexwisp := gs.spawn_unit("hexwisp", 0, 5, 5)   # flying blinker
	var tg := AbilityResolve.blink_targets(gs, hexwisp)
	# in range (<=4): a tile 3 away is a target; 5 away is not; the own tile is not.
	_ok(tg.has("8,5"), "blink: tile 3 away is a target")          # distance 3
	_ok(not tg.has("10,5"), "blink: tile 5 away out of range")    # distance 5
	_ok(not tg.has("5,5"), "blink: own tile excluded")
	# occupied tiles are excluded.
	gs.spawn_unit("cinderling", 1, 7, 5)
	_ok(not AbilityResolve.blink_targets(gs, hexwisp).has("7,5"), "blink: occupied tile excluded")
	# water blocks landing for everyone (even flyers); mountain only for non-flyers.
	var gw := _flat_state(11, 11)
	gw.cell_at(6, 5)["terrain"] = "water"
	gw.cell_at(6, 6)["terrain"] = "mountain"
	var flyer := gw.spawn_unit("hexwisp", 0, 5, 5)        # flying
	var tg2 := AbilityResolve.blink_targets(gw, flyer)
	_ok(not tg2.has("6,5"), "blink: water never landable")
	_ok(tg2.has("6,6"), "blink: flyer may land on mountain")
	var gg := _flat_state(11, 11)
	gg.cell_at(6, 6)["terrain"] = "mountain"
	var ground := gg.spawn_unit("runeward", 0, 5, 5)      # non-flyer (would be ward, but fine for blink targeting)
	_ok(not AbilityResolve.blink_targets(gg, ground).has("6,6"), "blink: non-flyer cannot land on mountain")
	# do_blink teleports.
	AbilityResolve.do_blink(hexwisp, 8, 5)
	_eq(Vector2i(hexwisp["q"], hexwisp["r"]), Vector2i(8, 5), "blink: teleported")
```

- [ ] **Step 2: Run — verify it fails (blink_targets missing)**
```
pwsh -ExecutionPolicy Bypass -File godot/tests/run_tests.ps1; "EXIT=$LASTEXITCODE"
```
Expected: error about `AbilityResolve.blink_targets`, non-zero EXIT.

- [ ] **Step 3: Append to `godot/core/ability_resolve.gd`, verbatim** (port of game.js Blink targeting 4673–4680 + teleport 4272):
```gdscript

## blink_targets — set of "q,r" within 4 hexes of `unit` that are empty and landable:
## not a `blocks` tile (water — excluded for everyone), and not a `flyers_only` tile
## (mountain) for a non-flyer. The unit's own tile is excluded (it's occupied).
static func blink_targets(state, unit: Dictionary) -> Dictionary:
	var out := {}
	var origin := Vector2i(unit["q"], unit["r"])
	for key in state.map["cells"]:
		var c: Dictionary = state.map["cells"][key]
		var p := Vector2i(c["q"], c["r"])
		if Hex.distance(origin, p) > 4:
			continue
		if state.unit_at(p.x, p.y) != null:
			continue
		var t: Dictionary = Terrain.TERRAIN[c["terrain"]]
		if t.get("blocks", false):
			continue
		if t.get("flyers_only", false) and not unit["flying"]:
			continue
		out[key] = true
	return out

## do_blink — teleport `unit` to (q,r). Caller validates it's a blink_targets entry.
static func do_blink(unit: Dictionary, q: int, r: int) -> void:
	unit["q"] = q
	unit["r"] = r
```

- [ ] **Step 4: Run — verify pass**
```
pwsh -ExecutionPolicy Bypass -File godot/tests/run_tests.ps1; "EXIT=$LASTEXITCODE"
```
Expected: green, `EXIT=0` (~8 new asserts). `0 failed` is the gate.

- [ ] **Step 5: Commit**
```
git add godot/core/ability_resolve.gd godot/tests/run_tests.gd
git commit -m "[godot] M5: Blink ability (tile teleport ≤4 hexes, landable-tile targeting)"
```

---

## Task 5: Wire abilities into the board + close M5

Add a minimal cast interaction to `main.gd`: pressing **A** with a unit selected casts its ability — instant abilities fire immediately; enemy/tile abilities ARM, and the next click resolves on a valid target (or cancels). Cooldown is set on cast; `ability_for` already returns the cd. The full action menu is M7; this is the on-screen verification path.

**Files:** Modify `godot/scenes/main.gd`, `ROADMAP_GODOT.md`.

- [ ] **Step 1: Add the cast keybind + arm handling to `godot/scenes/main.gd`.**

Add preloads with the others:
```gdscript
const Abilities = preload("res://data/abilities.gd")
const AbilityResolve = preload("res://core/ability_resolve.gd")
```
Add an arm var beside `var selected = null`:
```gdscript
var armed = null   # {ab: Dictionary, kind: String, targets: Dictionary} when an enemy/tile ability is armed
```
In `_unhandled_input`, add an **A**-key branch (after the `KEY_T` debug branch, before the function ends):
```gdscript
	elif event is InputEventKey and event.pressed and event.keycode == KEY_A:
		_cast_ability()
```
Add these functions (place after `_on_click`):
```gdscript
func _cast_ability() -> void:
	if selected == null:
		return
	var ab = Abilities.ability_for(selected)
	if ab == null or selected["cd"] > 0:
		return
	match ab["target"]:
		"none":
			AbilityResolve.resolve_instant(state, selected, ab)
			selected["cd"] = ab["cd"]
			_clear_selection()
			units_layer.set_state(state)
			if state.winner != -1:
				print("WINNER: player %d" % state.winner)
		"enemy":
			var targets := Pathfinding.compute_attack_targets(state, selected, selected["q"], selected["r"])
			if not targets.is_empty():
				armed = {"ab": ab, "kind": "enemy", "targets": targets}
		"tile":
			var tiles := AbilityResolve.blink_targets(state, selected)
			if not tiles.is_empty():
				armed = {"ab": ab, "kind": "tile", "targets": tiles}

func _resolve_armed(a: Vector2i) -> void:
	var key := Hex.key(a)
	if armed["targets"].has(key):
		if armed["kind"] == "enemy":
			var foe = state.unit_at(a.x, a.y)
			if foe != null:
				Combat.resolve_attack(state, selected, foe, armed["ab"].get("status", ""), armed["ab"].get("status_turns", 0))
				selected["cd"] = armed["ab"]["cd"]
		else:   # tile (blink)
			AbilityResolve.do_blink(selected, a.x, a.y)
			selected["cd"] = armed["ab"]["cd"]
	armed = null
	_clear_selection()
	units_layer.set_state(state)
	if state.winner != -1:
		print("WINNER: player %d" % state.winner)
```
Finally, route armed clicks FIRST in `_on_click` — add this at the very top of `_on_click`, before the `if selected != null` block:
```gdscript
	if armed != null:
		_resolve_armed(a)
		return
```

- [ ] **Step 2: Headless boot check — confirm `main.gd` parses (it has no class_name, so the harness can't catch its errors).**
```
godot --headless --path godot --quit-after 30 2>&1 | Select-String -Pattern "SCRIPT ERROR|Parse Error|Failed to load"
```
Run via the PowerShell tool. Expected: NO output. If anything prints, fix the parse error before continuing. REQUIRED GATE.

- [ ] **Step 3: Run the harness — confirm no core regression.**
```
pwsh -ExecutionPolicy Bypass -File godot/tests/run_tests.ps1; "EXIT=$LASTEXITCODE"
```
Expected: green, `EXIT=0` (no new asserts this task — `main.gd` isn't headless-tested).

- [ ] **Step 4: Visual confirmation (windowed) — YOU CANNOT DO THIS (no display).**
Manual check (run by the USER): `godot --path godot`, press **D** (M4 debug) to spawn an ally + adjacent enemy near your archon, select a unit with an ability, press **A** to cast — an instant fires immediately (e.g. a wounded ally heals, or quake hits adjacent enemies), an enemy-ability arms then resolves on the next enemy click (target takes damage + a status), Blink arms then teleports on the next tile click. Report this step as "NEEDS USER VISUAL CONFIRMATION". Do NOT run the windowed command.

- [ ] **Step 5: Check off M5 in `ROADMAP_GODOT.md`** — change `- [ ] M5 — All 12 abilities` to `- [x] M5 — All 12 abilities`.

- [ ] **Step 6: Commit**
```
git add godot/scenes/main.gd ROADMAP_GODOT.md
git commit -m "[godot] M5: wire ability cast (A key) into board; close M5"
```

---

## Notes & risk callouts

- **Caller owns cooldown/acted.** `resolve_instant` and `do_blink` set NOTHING on the unit beyond their effect — exactly like the JS `resolveInstantAbility`. The cast site (`_cast_ability`/`_resolve_armed`) sets `unit["cd"] = ab["cd"]`. `cd` is decremented in `end_turn` (already). M5's `main.gd` has no `acted` gate (that's M7's menu), so casting doesn't lock the unit — fine for the placeholder.
- **Status payload only on the primary, surviving swing.** `_apply_hit` applies the status after damage/XP, gated on `dst["hp"] > 0`, and the counter call passes `status=""`. A warded hit returns early → no status. This is the faithful `applySwing` rule.
- **Evolved cd-1 via `ability_for`.** The `cd` reduction is computed at fetch time from `unit.evolved`, not stored — so an evolving unit's ability gets snappier automatically. `master`'s `type_key` isn't in `UNIT_TYPES`, so `ability_for` returns null (masters have no ability).
- **Blink excludes water for everyone** (it's a `blocks` tile) and mountains for non-flyers (`flyers_only`); the own tile is excluded because it's occupied. Distance is straight hex distance ≤ 4 (a teleport — ignores move cost), matching the JS.
- **quake can level the caster** (kill XP), exactly like a normal kill — the test asserts `xp > 0 or level > 1` rather than a literal xp, to allow the level-up-zeroes-xp case.
- **`ability_for` returns Variant (dict-or-null)**, like `affinity_for`. Callers null-check.
- **`second_move`/`skitterBoost`**: M5 sets them; the "take a second move-only action" UX is the M7 menu. In M4's free-move `main.gd` the flag is inert beyond `skitterBoost` feeding `effective_move` (+2). That's the testable part and it's covered.
- **AI ability scoring is M6** (`aiScoreInstantAbility`) — not here. **Summoning is M7** — the M4 temp debug keys (D/T) stay until then.
- **`main.gd` is not headless-tested** (no class_name). Task 5 Step 2's headless boot is the only automated parse check — run it.

---

## Self-review

- **Spec coverage** (design spec milestone 5 — "All 12, wired into combat/status/weather"): data table + `ability_for` (Task 1); the 5 enemy abilities via the `resolve_attack` status payload (Task 2); the 6 instant abilities (Task 3 — heal/quake/skitter/galeRush/bulwark/ward); the 1 tile ability Blink (Task 4); board wiring for all three kinds (Task 5). 5 enemy + 6 instant + 1 tile = 12. ✅
- **Deferred with intent:** AI ability scorer (M6), action-menu UI + cooldown display + summoning (M7), battle cutaway (M8). All noted. ✅
- **Type/signature consistency:** `ability_for(unit) -> Variant` (key/cd/target/status/status_turns) consistent across Tasks 1/5; `resolve_attack(state, atk, def, apply_status, status_turns)` matches the enemy-ability call in `_resolve_armed`; `resolve_instant(state, unit, ab)` reads `ab["key"]`, matching both the `_instant()` test helper and `ability_for`'s output; `blink_targets(state, unit)` / `do_blink(unit, q, r)` match their call sites; status keys (`burn`/`slow`/`mark`/`bulwark`/`ward`/`skitterBoost`) match `STATUS_META` and the M4 combat reads. ✅
- **No placeholders:** every step ships complete code or an exact command + expected result. ✅
