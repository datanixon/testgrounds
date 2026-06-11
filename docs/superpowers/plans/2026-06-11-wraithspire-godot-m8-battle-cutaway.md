# Wraithspire Godot Port — Milestone 8: Battle cutaway — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax.

**Goal:** Add the full-screen battle cutaway — combat resolves synchronously and records a per-battle snapshot; the presentation drains the queue and plays a phased, richer-procedural cutaway per battle — plus a human-only move-slide.

**Architecture:** Resolve-then-replay. `Combat.resolve_attack` keeps its exact behavior + RNG draws (determinism intact) and appends a plain-data battle record to `GameState.battle_log`. A `BattleScene` (self-contained, fills screen) plays the phase machine `intro→standoff→aCharge→aImpact→aRecover→cPause→cCharge→cImpact→cRecover→outro→done` from a record and emits `finished`. `main.gd` drains the log and `await`s each cutaway after a human attack and after the (unchanged, synchronous) AI turn. `core/ai.gd` is untouched — the C#-swap seam holds. Procedural visuals port the JS `drawBattleSprite` / `drawAttackEffect` / `drawArenaBackground` (real art is M10).

**Tech Stack:** GDScript, Godot 4.6.3 standard build. Harness `pwsh -File godot/tests/run_tests.ps1` (the `-ExecutionPolicy Bypass` form is BLOCKED by the Claude Code classifier — always plain `pwsh -File`). Headless-boot parse gate (scene scripts have no `class_name`): `godot --headless --path godot --quit-after 30 2>&1 | Select-String "SCRIPT ERROR|Parse Error|Failed to load"` (clean = no matches).

---

## Verification model (read once)

- **Task 1** (combat record) and the **phase-machine function in Task 2** are pure → standard TDD with asserts.
- The **visual** parts (BattleScene rendering, sprites, fx, the `main.gd` driver) are presentation → gated by the headless-boot parse gate + harness staying green + the user's windowed visual confirmation. Every such task ships complete code or an exact source-port contract.
- Baseline at M8 start (`cf0fed6`): **374 passed, 0 failed**. Task 1 adds asserts (→ ~385); later tasks keep that count.

## File structure (this milestone)

```
godot/core/game_state.gd               + var battle_log: Array = []                       [MODIFY]
godot/core/combat.gd                   resolve_attack records a battle snapshot           [MODIFY]
godot/scenes/battle/battle_scene.gd    BattleScene — phase machine + play(record)+finished [NEW]
godot/scenes/battle/battle_sprites.gd  port of drawBattleSprite (per-type portraits)       [NEW]
godot/scenes/battle/battle_fx.gd       port of drawAttackEffect + drawArenaBackground       [NEW]
godot/scenes/main.gd                   _play_battles() replay driver + _busy; human move-slide [MODIFY]
godot/tests/run_tests.gd               + _test_battle_record, + _test_battle_phases         [MODIFY]
ROADMAP_GODOT.md                       check off M8
```

**Battle record shape** (what `resolve_attack` appends; what `BattleScene.play` consumes):
```gdscript
{
  "attacker": { "type_key", "name", "element", "sprite", "owner", "attack" },
  "defender": { "type_key", "name", "element", "sprite", "owner", "attack" },
  "atk_hp_before": int, "atk_max_hp": int, "def_hp_before": int, "def_max_hp": int,
  "primary": { "dmg": int, "absorbed": bool, "killed": bool },
  "counter": { "happened": bool, "dmg": int, "absorbed": bool, "killed": bool },
  "status": { "key": String, "turns": int } | null,
  "terrain": String,
}
```

---

## Task 1: Battle record on `GameState.battle_log`

`Combat.resolve_attack` keeps its exact resolution + RNG order and appends a snapshot. PURE data, TDD-tested.

**Files:** Modify `godot/core/game_state.gd`, `godot/core/combat.gd`, `godot/tests/run_tests.gd`.

- [ ] **Step 1: Add `battle_log` to `GameState`.** In `godot/core/game_state.gd`, add with the other vars (near `var winner` / `var difficulty`):
```gdscript
var battle_log: Array = []   # M8: per-battle snapshots appended by Combat.resolve_attack, drained by the presentation cutaway
```

- [ ] **Step 2: Add failing tests to `godot/tests/run_tests.gd`.** Add the call in `_initialize`, after `_test_ui_queries()`:
```gdscript
	_test_battle_record()
```
Append:
```gdscript
func _test_battle_record() -> void:
	# A plain attack records one snapshot with the right dmg/kill/terrain and counter.
	var gs := _combat_state()
	var atk := gs.spawn_unit("cinderling", 0, 2, 3)   # pyro, power 5
	var foe := gs.spawn_unit("galewisp", 1, 3, 3)       # zephyr, adjacent (pyro>zephyr)
	Combat.resolve_attack(gs, atk, foe)
	_eq(gs.battle_log.size(), 1, "record: one battle logged")
	var rec: Dictionary = gs.battle_log[0]
	_eq(rec["attacker"]["type_key"], "cinderling", "record: attacker type")
	_eq(rec["defender"]["type_key"], "galewisp", "record: defender type")
	_ok(rec["primary"]["dmg"] >= 1, "record: primary dealt damage")
	_eq(rec["def_hp_before"], 10, "record: defender pre-HP captured")  # galewisp max_hp 10
	_eq(rec["terrain"], "plain", "record: defender terrain")
	_ok(rec["counter"].has("happened"), "record: counter block present")
	# A lethal primary records killed + no counter.
	var gk := _combat_state()
	var killer := gk.spawn_unit("geomaul", 0, 2, 3)     # power 9
	var prey := gk.spawn_unit("galewisp", 1, 3, 3)
	prey["hp"] = 2
	Combat.resolve_attack(gk, killer, prey)
	var rk: Dictionary = gk.battle_log[0]
	_ok(rk["primary"]["killed"], "record: lethal primary flagged killed")
	_eq(rk["counter"]["happened"], false, "record: dead defender does not counter")
	# A warded defender records absorbed + no status, and survives.
	var gw := _combat_state()
	var hitter := gw.spawn_unit("cinderling", 0, 2, 3)
	var warded := gw.spawn_unit("stoneward", 1, 3, 3)
	Status.add_status(warded, "ward", 2)
	Combat.resolve_attack(gw, hitter, warded, "burn", 2)
	var rw: Dictionary = gw.battle_log[0]
	_ok(rw["primary"]["absorbed"], "record: ward absorbs primary")
	_eq(rw["status"], null, "record: absorbed swing applies no status")
	# An enemy-ability hit on a surviving defender records the applied status.
	var gstat := _combat_state()
	var burner := gstat.spawn_unit("cinderling", 0, 2, 3)
	var victim := gstat.spawn_unit("stoneward", 1, 3, 3)   # tanky, survives
	Combat.resolve_attack(gstat, burner, victim, "burn", 2)
	var rs: Dictionary = gstat.battle_log[0]
	_ok(rs["status"] != null and rs["status"]["key"] == "burn", "record: surviving defender takes the status")
```

- [ ] **Step 3: Run — verify it fails (battle_log empty / record shape missing).**
```
pwsh -File godot/tests/run_tests.ps1; "EXIT=$LASTEXITCODE"
```
Expected: failures on `record:` asserts (battle_log stays empty), non-zero EXIT.

- [ ] **Step 4: Make `_apply_hit` report its outcome + have `resolve_attack` record.** In `godot/core/combat.gd`, REPLACE `_apply_hit` with a version that returns a result dict:
```gdscript
## _apply_hit — one swing: ward absorbs (consumed, no damage/xp/status); else deal `dmg`,
## award XP (+kill bonus) to `src`, apply a surviving-defender status. Returns the outcome
## {dmg, absorbed, killed} so resolve_attack can record the battle. Mirrors applySwing.
static func _apply_hit(_state, src: Dictionary, dst: Dictionary, dmg: int, status := "", status_turns := 0) -> Dictionary:
	if Status.has_status(dst, "ward"):
		dst["status"].erase("ward")
		return {"dmg": 0, "absorbed": true, "killed": false}
	dst["hp"] -= dmg
	var killed: bool = dst["hp"] <= 0
	var xp_amt: int = dmg + (Units.KILL_XP_BONUS if killed else 0)
	Units.gain_xp(src, xp_amt)
	if status != "" and dst["hp"] > 0:
		Status.add_status(dst, status, status_turns)
	return {"dmg": dmg, "absorbed": false, "killed": killed}
```
Then REPLACE `resolve_attack` with the recording version (same compute/jitter order → determinism unchanged):
```gdscript
static func resolve_attack(state, attacker: Dictionary, defender: Dictionary, apply_status := "", status_turns := 0) -> void:
	var atk_hp_before: int = attacker["hp"]
	var def_hp_before: int = defender["hp"]
	var atk_max: int = attacker["max_hp"]
	var def_max: int = defender["max_hp"]
	var terrain := "plain"
	var dcell: Variant = state.cell_at(defender["q"], defender["r"])
	if dcell != null:
		terrain = dcell["terrain"]
	var a1: Dictionary = compute_damage(state, attacker, defender)
	var primary: Dictionary = _apply_hit(state, attacker, defender, _jitter(state, a1["base"]), apply_status, status_turns)
	var status_rec: Variant = null
	if apply_status != "" and not primary["absorbed"] and not primary["killed"]:
		status_rec = {"key": apply_status, "turns": status_turns}
	var counter := {"happened": false, "dmg": 0, "absorbed": false, "killed": false}
	if defender["hp"] > 0:
		var d: int = state_distance(attacker, defender)
		if d >= 1 and d <= defender["range"]:
			var a2: Dictionary = compute_damage(state, defender, attacker)
			var counter_dmg: int = maxi(1, roundi(_jitter(state, a2["base"]) * 0.8))
			var cres: Dictionary = _apply_hit(state, defender, attacker, counter_dmg)
			counter = {"happened": true, "dmg": cres["dmg"], "absorbed": cres["absorbed"], "killed": cres["killed"]}
	state.battle_log.append({
		"attacker": _combatant_view(attacker), "defender": _combatant_view(defender),
		"atk_hp_before": atk_hp_before, "atk_max_hp": atk_max,
		"def_hp_before": def_hp_before, "def_max_hp": def_max,
		"primary": primary, "counter": counter, "status": status_rec, "terrain": terrain,
	})
	state.check_win_condition()

## _combatant_view — the presentation-facing slice of a unit for a battle record (no live refs).
static func _combatant_view(u: Dictionary) -> Dictionary:
	return {
		"type_key": u["type_key"], "name": u["name"], "element": u["element"],
		"sprite": u["sprite"], "owner": u["owner"], "attack": u["attack"],
		"is_master": u.get("is_master", false),
	}
```
NOTE: RNG draw order is unchanged (`_jitter` for primary, then `_jitter` for counter); pre-HP/terrain capture draws no RNG. So every existing combat/AI determinism assert still holds.

- [ ] **Step 5: Run — verify pass.**
```
pwsh -File godot/tests/run_tests.ps1; "EXIT=$LASTEXITCODE"
```
Expected: green, `EXIT=0` (~10 new asserts). `0 failed` is the gate.

- [ ] **Step 6: Commit.**
```
git add godot/core/game_state.gd godot/core/combat.gd godot/tests/run_tests.gd
git commit -m "[godot] M8: Combat.resolve_attack records a battle snapshot to GameState.battle_log"
```

---

## Task 2: BattleScene skeleton — phase machine + play(record)/finished

A self-contained cutaway node that fills the screen and plays the phase sequence, with a PURE phase-advance function (TDD-tested) and placeholder combatant boxes (portraits land in Task 3). Emits `finished`.

**Files:** Create `godot/scenes/battle/battle_scene.gd`; Modify `godot/tests/run_tests.gd`.

- [ ] **Step 1: Add failing tests for the pure phase machine.** Add the call after `_test_battle_record()`:
```gdscript
	_test_battle_phases()
```
Append:
```gdscript
func _test_battle_phases() -> void:
	const BS = preload("res://scenes/battle/battle_scene.gd")
	# With a counter, the full a-then-c sequence runs to done.
	var seq: Array[String] = []
	var p := "intro"
	for i in range(20):
		seq.append(p)
		if p == "done":
			break
		p = BS.next_phase(p, true)
	_eq(seq[0], "intro", "phases: starts at intro")
	_ok(seq.has("cImpact"), "phases: counter runs the c-side")
	_eq(seq[seq.size() - 1], "done", "phases: reaches done")
	# Without a counter, aRecover jumps straight to outro (no c-side).
	var seq2: Array[String] = []
	var p2 := "intro"
	for i in range(20):
		seq2.append(p2)
		if p2 == "done":
			break
		p2 = BS.next_phase(p2, false)
	_ok(not seq2.has("cCharge"), "phases: no counter skips the c-side")
	_eq(BS.next_phase("aRecover", false), "outro", "phases: aRecover->outro without counter")
	_eq(BS.next_phase("aRecover", true), "cPause", "phases: aRecover->cPause with counter")
	_eq(BS.next_phase("outro", true), "done", "phases: outro->done")
```

- [ ] **Step 2: Run — verify it fails (battle_scene.gd missing).**
```
pwsh -File godot/tests/run_tests.ps1; "EXIT=$LASTEXITCODE"
```
Expected: load error about `res://scenes/battle/battle_scene.gd`, non-zero EXIT.

- [ ] **Step 3: Create `godot/scenes/battle/battle_scene.gd`, verbatim:**
```gdscript
class_name BattleScene
extends Control
## Full-screen battle cutaway (resolve-then-replay): play(record) animates one already-
## resolved battle, then emits finished. Self-contained — it fills the screen and does NOT
## render the map underneath. Portraits (battle_sprites) + effects (battle_fx) wire in at
## Tasks 3-4; this skeleton draws placeholder combatant boxes. Phase durations port the JS
## `B` table (frames @60fps). The phase ORDER is the pure next_phase() (harness-tested).

signal finished

## Phase frame budgets (JS B table; charge/impact/recover/pause shared by both sides).
const DUR := {
	"intro": 36, "standoff": 26, "aCharge": 22, "aImpact": 34, "aRecover": 18,
	"cPause": 22, "cCharge": 22, "cImpact": 34, "cRecover": 18, "outro": 32,
}

## next_phase — the pure phase transition. `has_counter` is record.counter.happened.
static func next_phase(phase: String, has_counter: bool) -> String:
	match phase:
		"intro": return "standoff"
		"standoff": return "aCharge"
		"aCharge": return "aImpact"
		"aImpact": return "aRecover"
		"aRecover": return "cPause" if has_counter else "outro"
		"cPause": return "cCharge"
		"cCharge": return "cImpact"
		"cImpact": return "cRecover"
		"cRecover": return "outro"
		"outro": return "done"
	return "done"

var _rec: Dictionary = {}
var _phase := "done"
var _frame := 0
var _acc := 0.0
var shake := 0.0
var flash := 0.0

func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	visible = false
	set_process(false)

## play — start the cutaway for one battle record. Emits finished when it reaches done.
func play(record: Dictionary) -> void:
	_rec = record
	_phase = "intro"
	_frame = 0
	_acc = 0.0
	shake = 0.0
	flash = 0.0
	visible = true
	set_process(true)
	queue_redraw()

func _has_counter() -> bool:
	return _rec.get("counter", {}).get("happened", false)

func _process(delta: float) -> void:
	# Advance in fixed 1/60s frames so the ported durations match the JS timing.
	_acc += delta
	flash *= 0.85
	shake *= 0.85
	while _acc >= 1.0 / 60.0:
		_acc -= 1.0 / 60.0
		_frame += 1
		var budget: int = DUR.get(_phase, 0)
		if _frame >= budget:
			if _phase == "aCharge" or _phase == "cCharge":
				flash = 1.0
				shake = 6.0
			_phase = next_phase(_phase, _has_counter())
			_frame = 0
			if _phase == "done":
				set_process(false)
				visible = false
				finished.emit()
				return
	queue_redraw()

func _draw() -> void:
	if _rec.is_empty():
		return
	var sz := size
	var ox := (randf() - 0.5) * shake
	var oy := (randf() - 0.5) * shake
	# Reveal/letterbox: bars shrink in during intro, grow back during outro.
	var reveal := 1.0
	if _phase == "intro":
		reveal = clampf(float(_frame) / float(DUR["intro"]), 0.0, 1.0)
	elif _phase == "outro":
		reveal = 1.0 - clampf(float(_frame) / float(DUR["outro"]), 0.0, 1.0)
	draw_rect(Rect2(Vector2.ZERO, sz), Color("#020107"))
	# Placeholder combatants (Task 3 replaces with portraits).
	var ground := sz.y * 0.62
	var ax := sz.x * 0.30 + ox
	var dx := sz.x * 0.70 + ox
	_draw_box(Vector2(ax, ground + oy), _rec["attacker"]["owner"])
	_draw_box(Vector2(dx, ground + oy), _rec["defender"]["owner"])
	# Letterbox bars.
	var bar_h := sz.y * (1.0 - reveal) / 2.0
	draw_rect(Rect2(Vector2.ZERO, Vector2(sz.x, bar_h)), Color.BLACK)
	draw_rect(Rect2(Vector2(0, sz.y - bar_h), Vector2(sz.x, bar_h)), Color.BLACK)
	# Hit flash.
	if flash > 0.01:
		draw_rect(Rect2(Vector2.ZERO, sz), Color(1, 1, 1, clampf(flash, 0, 1) * 0.6))

func _draw_box(center: Vector2, owner: int) -> void:
	var col := Color("#5aa8d8") if owner == 0 else Color("#cc6a4a")
	draw_rect(Rect2(center - Vector2(40, 80), Vector2(80, 80)), col)
```

- [ ] **Step 4: Run — verify pass (the pure phase asserts).**
```
pwsh -File godot/tests/run_tests.ps1; "EXIT=$LASTEXITCODE"
```
Expected: green, `EXIT=0` (~6 new asserts).

- [ ] **Step 5: Headless boot parse gate (PowerShell) — the node script must load.**
```
godot --headless --path godot --quit-after 30 2>&1 | Select-String -Pattern "SCRIPT ERROR|Parse Error|Failed to load"
```
Expected: NO output.

- [ ] **Step 6: Commit.**
```
git add godot/scenes/battle/battle_scene.gd godot/tests/run_tests.gd
git commit -m "[godot] M8: BattleScene skeleton — phase machine (pure next_phase, tested) + play/finished + letterbox"
```

---

## Task 3: Procedural battle portraits (`battle_sprites.gd`)

Port the JS `drawBattleSprite` per-type portraits into a static draw helper, and wire it into `BattleScene` to replace the placeholder boxes. This is a mechanical port of fully-specified source — the implementer ports from `game.js` directly using the API mapping below. Presentation only (no harness asserts) → gated by the headless boot + the user's visual check.

**Files:** Create `godot/scenes/battle/battle_sprites.gd`; Modify `godot/scenes/battle/battle_scene.gd`.

**Canvas2D → Godot `_draw`/CanvasItem mapping (use throughout Tasks 3-4):**
| JS Canvas2D | Godot (`ci` = the CanvasItem, e.g. the BattleScene) |
|---|---|
| `ctx.fillStyle=c; fillRect(x,y,w,h)` | `ci.draw_rect(Rect2(x,y,w,h), c)` |
| `ctx.fillStyle=c; arc(x,y,r,0,2π); fill()` | `ci.draw_circle(Vector2(x,y), r, c)` |
| `ctx.strokeStyle=c; lineWidth=w; arc(x,y,r,a0,a1); stroke()` | `ci.draw_arc(Vector2(x,y), r, a0, a1, 24, c, w)` |
| `ctx.moveTo(a)/lineTo(b); stroke()` | `ci.draw_line(Vector2(a), Vector2(b), c, w)` |
| polygon path + `fill()` | `ci.draw_colored_polygon(PackedVector2Array([...]), c)` |
| `"#rrggbb"` / `rgba(r,g,b,a)` | `Color("#rrggbb")` / `Color(r/255.0, g/255.0, b/255.0, a)` |
| `ELEMENT[el].color` | `Elements.ELEMENT[el]["color"]` (preload `res://data/elements.gd`) |
| `Math.random()` | `randf()` (cutaway is presentation — non-deterministic scatter is fine) |
| linear/radial gradient | approximate with a few stacked `draw_rect`/`draw_circle` of stepped colors |

- [ ] **Step 1: Create `godot/scenes/battle/battle_sprites.gd`** as a `class_name BattleSprites extends RefCounted` with a static entry point:
```gdscript
class_name BattleSprites
extends RefCounted
## Procedural battle portraits — port of game.js drawBattleSprite (sec. 9, ~line 1782).
## Placeholder-quality; real sprites replace these bodies at M10 behind the same signature.
## Pure draw helpers: they only call ci.draw_* and read the combatant view dict.

const Elements = preload("res://data/elements.gd")

## draw_unit — render one combatant centered near (cx, cy). `view` is the battle record's
## attacker/defender slice (type_key/element/owner/attack/is_master). `facing` is +1 (faces
## right) or -1 (mirrored). `pose` in {"idle","charge","impact","recover"}; `t` is 0..1 phase
## progress. Mirror by negating x-offsets when facing < 0.
static func draw_unit(ci: CanvasItem, view: Dictionary, cx: float, cy: float, facing: int, pose: String, t: float) -> void:
	# PORT the body from game.js drawBattleSprite: the shared archon branch (view.is_master)
	# plus a case per `view.sprite` id (the same sprite ids used by drawMapSprite). Use the
	# mapping table above. Element tint via Elements.ELEMENT[view.element].color.
	pass
```
Then PORT `drawBattleSprite` from `game.js` (find it: `function drawBattleSprite(ctx, unit, cx, cy, facing, pose, t)` ~line 1782, runs to the next top-level `function`). Translate each sprite-id branch and the archon (`is_master`) branch using the mapping table. Keep the same proportions/colors. Where the JS reads `unit.element`/`unit.owner`/`unit.sprite`, read `view["element"]`/`view["owner"]`/`view["sprite"]`. Replace the placeholder `pass` with the full ported body (one `match view["sprite"]:` over the sprite ids, plus the master branch).

- [ ] **Step 2: Wire portraits into `BattleScene`.** Add the preload at the top of `battle_scene.gd`:
```gdscript
const BattleSprites = preload("res://scenes/battle/battle_sprites.gd")
```
In `_draw`, REPLACE the two `_draw_box(...)` calls with portrait draws (attacker faces right, defender mirrored), passing a pose derived from the phase:
```gdscript
	BattleSprites.draw_unit(self, _rec["attacker"], ax, ground + oy, 1, _pose_for("a"), _phase_t())
	BattleSprites.draw_unit(self, _rec["defender"], dx, ground + oy, -1, _pose_for("c"), _phase_t())
```
Add the helpers (and DELETE the now-unused `_draw_box`):
```gdscript
func _phase_t() -> float:
	var budget: int = DUR.get(_phase, 1)
	return clampf(float(_frame) / float(maxi(1, budget)), 0.0, 1.0)

## _pose_for — map the current phase to a combatant pose for side "a" (attacker) or "c" (defender).
func _pose_for(side: String) -> String:
	var p := _phase
	if side == "a":
		if p == "aCharge": return "charge"
		if p == "aImpact": return "impact"
		if p == "aRecover": return "recover"
	else:
		if p == "cCharge": return "charge"
		if p == "cImpact": return "impact"
		if p == "cRecover": return "recover"
	return "idle"
```

- [ ] **Step 3: Headless boot parse gate (PowerShell).**
```
godot --headless --path godot --quit-after 30 2>&1 | Select-String -Pattern "SCRIPT ERROR|Parse Error|Failed to load"
```
Expected: NO output. (Boot only parses/loads — it won't render; the visual check is the user's.)

- [ ] **Step 4: Harness still green.**
```
pwsh -File godot/tests/run_tests.ps1; "EXIT=$LASTEXITCODE"
```
Expected: same count as Task 2, `0 failed`, EXIT 0.

- [ ] **Step 5: Commit.**
```
git add godot/scenes/battle/battle_sprites.gd godot/scenes/battle/battle_scene.gd
git commit -m "[godot] M8: procedural battle portraits (port of drawBattleSprite) wired into BattleScene"
```

---

## Task 4: Attack effects + arena background (`battle_fx.gd`)

Port `drawAttackEffect` (6 flavors via `drawAttackTrail`/`drawImpactBurst`) and `drawArenaBackground`. Wire both into `BattleScene` (arena behind combatants; effects during charge/impact). Add floating damage numbers + HP bars from the record. Presentation only.

**Files:** Create `godot/scenes/battle/battle_fx.gd`; Modify `godot/scenes/battle/battle_scene.gd`.

- [ ] **Step 1: Create `godot/scenes/battle/battle_fx.gd`:**
```gdscript
class_name BattleFx
extends RefCounted
## Battle arena + attack effects — port of game.js drawArenaBackground / drawAttackEffect
## (drawAttackTrail + drawImpactBurst). Pure draw helpers. Placeholder-quality (M10 replaces).

const Elements = preload("res://data/elements.gd")

## draw_arena — full-screen background tinted by the defender's terrain. Port of
## drawArenaBackground(terrainKind, seed) ~game.js 2699: sky gradient (approximate with a
## few stacked draw_rect bands) + a ground line + sparse parallax detail.
static func draw_arena(ci: CanvasItem, terrain: String, screen: Vector2) -> void:
	pass   # PORT from drawArenaBackground using the mapping table in Task 3.

## draw_attack_effect — the per-flavor effect during a charge/impact phase. Port of
## drawAttackEffect + drawAttackTrail + drawImpactBurst (~game.js 2582-2697). `flavor` is the
## acting unit's `attack` (or "bolt" for a master). `phase` is the BattleScene phase; `t` is
## phase progress 0..1; `atk_x`/`def_x`/`ground_y` are pixel anchors.
static func draw_attack_effect(ci: CanvasItem, phase: String, attacker_flavor: String, defender_flavor: String, attacker_el: String, defender_el: String, atk_x: float, def_x: float, ground_y: float, t: float) -> void:
	pass   # PORT from drawAttackEffect: aImpact->burst at def, aCharge->trail from atk; cImpact->burst at atk, cCharge->trail from def.
```
Then PORT the bodies from `game.js`: `drawArenaBackground` (~2699), `drawAttackEffect` (~2582), `drawAttackTrail` (~2596, the 6 `kind` branches melee/breath/spray/spark/dive/bolt), `drawImpactBurst` (~2675). Use the mapping table. For the master, `flavor` is `"bolt"`. Replace each `pass`.

- [ ] **Step 2: Wire into `BattleScene`.** Add the preload:
```gdscript
const BattleFx = preload("res://scenes/battle/battle_fx.gd")
```
In `_draw`, AFTER the `#020107` fill and BEFORE the portraits, draw the arena:
```gdscript
	BattleFx.draw_arena(self, _rec.get("terrain", "plain"), sz)
```
AFTER the portraits, draw the active attack effect, the damage popups, and HP bars:
```gdscript
	var a_flavor: String = "bolt" if _rec["attacker"].get("is_master", false) else _rec["attacker"]["attack"]
	var d_flavor: String = "bolt" if _rec["defender"].get("is_master", false) else _rec["defender"]["attack"]
	BattleFx.draw_attack_effect(self, _phase, a_flavor, d_flavor, _rec["attacker"]["element"], _rec["defender"]["element"], ax, dx, ground + oy, _phase_t())
	_draw_hp_bars(Vector2(ax, ground + oy), Vector2(dx, ground + oy))
	_draw_damage_popups(Vector2(ax, ground + oy), Vector2(dx, ground + oy))
```
Add the HP-bar + popup helpers (HP animates from `*_hp_before` toward the post-swing value as the matching impact lands):
```gdscript
func _draw_hp_bars(atk_c: Vector2, def_c: Vector2) -> void:
	var def_now: int = _rec["def_hp_before"]
	if _phase in ["aImpact", "aRecover", "cPause", "cCharge", "cImpact", "cRecover", "outro"] and not _rec["primary"]["absorbed"]:
		def_now = maxi(0, _rec["def_hp_before"] - _rec["primary"]["dmg"])
	var atk_now: int = _rec["atk_hp_before"]
	if _rec["counter"]["happened"] and _phase in ["cImpact", "cRecover", "outro"] and not _rec["counter"]["absorbed"]:
		atk_now = maxi(0, _rec["atk_hp_before"] - _rec["counter"]["dmg"])
	_hp_bar(atk_c + Vector2(-40, -96), float(atk_now) / float(maxi(1, _rec["atk_max_hp"])))
	_hp_bar(def_c + Vector2(-40, -96), float(def_now) / float(maxi(1, _rec["def_max_hp"])))

func _hp_bar(top_left: Vector2, frac: float) -> void:
	draw_rect(Rect2(top_left, Vector2(80, 7)), Color(0, 0, 0, 0.7))
	var c := Color("#5ad06a") if frac > 0.5 else (Color("#e0d050") if frac > 0.25 else Color("#e05050"))
	draw_rect(Rect2(top_left, Vector2(80.0 * clampf(frac, 0, 1), 7)), c)

func _draw_damage_popups(atk_c: Vector2, def_c: Vector2) -> void:
	var font := ThemeDB.fallback_font
	if _phase == "aImpact":
		var txt := "WARDED" if _rec["primary"]["absorbed"] else "-%d" % _rec["primary"]["dmg"]
		draw_string(font, def_c + Vector2(-20, -110), txt, HORIZONTAL_ALIGNMENT_CENTER, -1, 22, Color("#e85858"))
	if _phase == "cImpact" and _rec["counter"]["happened"]:
		var txt2 := "WARDED" if _rec["counter"]["absorbed"] else "-%d" % _rec["counter"]["dmg"]
		draw_string(font, atk_c + Vector2(-20, -110), txt2, HORIZONTAL_ALIGNMENT_CENTER, -1, 22, Color("#e85858"))
```

- [ ] **Step 3: Headless boot parse gate (PowerShell).**
```
godot --headless --path godot --quit-after 30 2>&1 | Select-String -Pattern "SCRIPT ERROR|Parse Error|Failed to load"
```
Expected: NO output.

- [ ] **Step 4: Harness still green.**
```
pwsh -File godot/tests/run_tests.ps1; "EXIT=$LASTEXITCODE"
```
Expected: same count, `0 failed`, EXIT 0.

- [ ] **Step 5: Commit.**
```
git add godot/scenes/battle/battle_fx.gd godot/scenes/battle/battle_scene.gd
git commit -m "[godot] M8: attack-flavor effects + arena background + damage popups + HP bars in the cutaway"
```

---

## Task 5: Replay driver — human attack routes through the cutaway

`main.gd` instantiates the BattleScene, drains `battle_log` and `await`s a cutaway per record, and blocks board input while playing. The human attack path (`_resolve_armed`) routes through it.

**Files:** Modify `godot/scenes/main.gd`.

- [ ] **Step 1: Preload + instantiate the BattleScene + a busy flag.** Add the preload with the HUD preloads:
```gdscript
const BattleSceneScript = preload("res://scenes/battle/battle_scene.gd")
```
Add member vars near `var hud`:
```gdscript
var battle_scene: BattleSceneScript
var _busy := false   # blocks board input while a cutaway or move-slide plays
```
In `_ready()`, AFTER the HUD is built (so the cutaway draws above it), add:
```gdscript
	battle_scene = BattleSceneScript.new()
	hud.add_child(battle_scene)
```

- [ ] **Step 2: Add the replay coroutine.** Add:
```gdscript
## _play_battles — drain GameState.battle_log, awaiting one cutaway per recorded battle.
## Blocks board input via _busy. Refreshes the board + HUD afterward. No state mutation
## (combat already resolved; the cutaway is pure animation).
func _play_battles() -> void:
	if state.battle_log.is_empty():
		return
	_busy = true
	while not state.battle_log.is_empty():
		var rec: Dictionary = state.battle_log.pop_front()
		battle_scene.play(rec)
		await battle_scene.finished
	_busy = false
	units_layer.set_state(state)
	if top_bar != null:
		top_bar.refresh(state)
```

- [ ] **Step 3: Block input while busy.** At the very TOP of `_unhandled_input(event)` add:
```gdscript
	if _busy:
		return
```
And at the very TOP of `_on_click(a)` add:
```gdscript
	if _busy:
		return
```

- [ ] **Step 4: Route the human attack through the cutaway.** In `_resolve_armed`, the enemy-hit branch currently calls `Combat.resolve_attack(...)` then `_commit(unit)`. The battle is now recorded; play it before/after the commit. REPLACE the hit path so it commits state, then plays the cutaway. Specifically, change the hit branch's tail from:
```gdscript
		armed = null
		overlay.set_armed({})
		_commit(unit)
		return
```
to:
```gdscript
		armed = null
		overlay.set_armed({})
		_commit(unit)
		await _play_battles()
		return
```
NOTE: `_commit` → `_finish_action` already rebuilds the board to final state; `_play_battles` then plays the recorded cutaway over it (the scene fills the screen, so the pre-update is not perceived). `_unhandled_input` must be able to `await` — GDScript allows `await` in any function; the engine handles the suspended input handler. Because `_busy` is set for the duration, no re-entrant input is processed.

- [ ] **Step 5: Headless boot parse gate (PowerShell). MANDATORY — main.gd change.**
```
godot --headless --path godot --quit-after 30 2>&1 | Select-String -Pattern "SCRIPT ERROR|Parse Error|Failed to load"
```
Expected: NO output.

- [ ] **Step 6: Harness still green.**
```
pwsh -File godot/tests/run_tests.ps1; "EXIT=$LASTEXITCODE"
```
Expected: same count, `0 failed`, EXIT 0.

- [ ] **Step 7: Commit.**
```
git add godot/scenes/main.gd
git commit -m "[godot] M8: replay driver — human attack plays the battle cutaway (input blocked while busy)"
```

---

## Task 6: AI-turn replay + human move-slide; fold M7 polish; close M8

The AI turn already records all its battles in `take_turn`; drain them after. Add the human move-slide. Fold in the three M7 polish carry-forwards. Close the milestone.

**Files:** Modify `godot/scenes/main.gd`, `godot/scenes/match/overlay.gd`, `godot/scenes/hud/info_card.gd`, `godot/scenes/hud/action_menu.gd`, `godot/scenes/hud/summon_list.gd`, `ROADMAP_GODOT.md`.

- [ ] **Step 1: Play the AI's battles after its turn.** In `_on_end_turn`, the AI block currently is:
```gdscript
	if state.winner == -1 and state.current_player == 1:
		AI.take_turn(state)
		if state.winner == -1:
			state.end_turn()
	_center_on_master()
	_finish_action()
```
REPLACE it so the recorded AI battles replay (await), then control returns:
```gdscript
	if state.winner == -1 and state.current_player == 1:
		AI.take_turn(state)
		_finish_action()
		await _play_battles()
		if state.winner == -1:
			state.end_turn()
	_center_on_master()
	_finish_action()
```
NOTE: `_finish_action` before `_play_battles` rebuilds the board to the AI's final state; the cutaways then replay its battles. Since `_on_end_turn` already returns early at the top when `state.winner != -1` (M7 guard), and `_busy` blocks input during playback, no re-entrancy occurs.

- [ ] **Step 2: Human move-slide.** In `_on_click`, the reachable-tile move branch currently snaps:
```gdscript
		if reach.has(Hex.key(a)) and not is_own_tile:
			undo_snapshot = {"unit": selected, "q": selected["q"], "r": selected["r"]}
			selected["q"] = a.x
			selected["r"] = a.y
			units_layer.set_state(state)
			overlay.set_highlights({}, selected)
			_open_menu_for(selected)
			return
```
REPLACE with a version that tweens the unit node to the destination before opening the menu:
```gdscript
		if reach.has(Hex.key(a)) and not is_own_tile:
			undo_snapshot = {"unit": selected, "q": selected["q"], "r": selected["r"]}
			var from_px := Hex.axial_to_pixel(Vector2i(selected["q"], selected["r"]))
			var to_px := Hex.axial_to_pixel(a)
			selected["q"] = a.x
			selected["r"] = a.y
			overlay.set_highlights({}, selected)
			await _slide_unit(selected, from_px, to_px)
			_open_menu_for(selected)
			return
```
Add the slide helper (a straight hex-to-hex tween of the moving unit's node; `_busy` blocks input during it):
```gdscript
## _slide_unit — animate the moving unit's UnitNode from from_px to to_px, then snap the
## layer to final state. A straight glide (per-hex path-following is a later polish).
func _slide_unit(unit, from_px: Vector2, to_px: Vector2) -> void:
	_busy = true
	units_layer.set_state(state)              # rebuild so the node exists at the new record
	var node := _unit_node_for(unit)
	if node != null:
		node.position = from_px
		var tw := create_tween()
		tw.tween_property(node, "position", to_px, 0.18)
		await tw.finished
	_busy = false
	units_layer.set_state(state)

## _unit_node_for — find the UnitNode bound to `unit` in the units layer (or null).
func _unit_node_for(unit):
	for child in units_layer.get_children():
		if child.unit == unit:
			return child
	return null
```

- [ ] **Step 3: Fold in the M7 polish carry-forwards.**
  - **(a)** `godot/scenes/match/overlay.gd`: delete the dead `attack` field, `set_attack()`, and the `_fill(attack, …)` line in `_draw` (attack targets render via `set_armed`). Concretely: remove `var attack: Dictionary = {}`, remove the `func set_attack(...)` method, remove `attack = {}` from `clear_all()`, and remove the `_fill(attack, Color(1.0, 0.35, 0.35, 0.30))` call in `_draw`.
  - **(b)** `godot/scenes/hud/info_card.gd`: have `main.gd` refresh the card after a self-affecting action. Simplest: in `main.gd`'s `_commit`, before `_finish_action()`, if the unit is still alive call `info_card.show_unit(unit)` is NOT wanted (commit clears selection) — instead, in `_arm_ability`'s `"none"` non-second-move branch, after `AbilityResolve.resolve_instant(...)`, add `info_card.show_unit(unit)` so a self-heal/ward/bulwark visibly updates the card for the moment before commit. (One line; leave the rest.)
  - **(c)** `godot/scenes/hud/action_menu.gd` and `summon_list.gd`: replace the hardcoded width in `_clamp_on_screen` with the real panel width after layout. In each, change the `sz` line to read the panel's size:
    ```gdscript
    	var sz := _panel.size if _panel.size.x > 0 else Vector2(160, 28 * maxi(1, _vbox.get_child_count()))
    ```
    (`_panel.size` is valid after the buttons are added + a layout pass; the fallback covers the first frame.)

- [ ] **Step 4: Headless boot parse gate (PowerShell). MANDATORY.**
```
godot --headless --path godot --quit-after 30 2>&1 | Select-String -Pattern "SCRIPT ERROR|Parse Error|Failed to load"
```
Expected: NO output.

- [ ] **Step 5: Harness still green.**
```
pwsh -File godot/tests/run_tests.ps1; "EXIT=$LASTEXITCODE"
```
Expected: same count, `0 failed`, EXIT 0.

- [ ] **Step 6: Visual confirmation — NEEDS USER (no display in-session).** Report as "NEEDS USER VISUAL CONFIRMATION": `godot --path godot` → attack an adjacent enemy (cutaway plays: arena by terrain, portraits charge/impact, damage numbers, HP bars, counter if any), move a unit (it slides), press Enter (the AI takes its turn and its battles replay as cutaways, then control returns). Do NOT run the windowed command.

- [ ] **Step 7: Check off M8 in `ROADMAP_GODOT.md`** — change `- [ ] M8 — Battle cutaway scene` to `- [x] M8 — Battle cutaway scene` (match the exact line text).

- [ ] **Step 8: Commit.**
```
git add godot/scenes/main.gd godot/scenes/match/overlay.gd godot/scenes/hud/info_card.gd godot/scenes/hud/action_menu.gd godot/scenes/hud/summon_list.gd ROADMAP_GODOT.md
git commit -m "[godot] M8: AI-turn battle replay + human move-slide + M7 polish; close M8"
```

---

## Notes & risk callouts

- **Determinism is preserved exactly.** `resolve_attack` keeps its `compute_damage` + `_jitter` (`state.rng.below(3)`) draw order — primary then counter. The record is a side-write of already-computed values; pre-HP/terrain capture draws no RNG. Every existing combat/AI assert (the 374) must stay green after Task 1 — that's the gate.
- **The cutaway never mutates game state.** Combat already resolved; `BattleScene` animates from the record's numbers. This is the whole point of resolve-then-replay and why `core/ai.gd` is untouched (`take_turn` stays synchronous; the seam holds).
- **`await` in input handlers.** `_unhandled_input` / `_on_click` `await`ing `_play_battles` is valid GDScript; `_busy` blocks re-entrant board input for the duration. The AI path awaits in `_on_end_turn` similarly.
- **Frame-stepped phases.** `BattleScene._process` advances in fixed 1/60 s frames so the ported JS durations match regardless of real framerate. The phase ORDER is the pure `next_phase` (harness-tested); only the timing lives in the node.
- **Procedural ports (Tasks 3-4) are mechanical.** They translate fully-specified JS draw code via the mapping table; the implementer reads `game.js` directly. They carry no game logic and are M10-replaceable behind fixed signatures (`BattleSprites.draw_unit`, `BattleFx.draw_arena`/`draw_attack_effect`).
- **Accepted divergences (from the spec):** the board reflects final state under the cutaway; AI movement is not animated (only battles replay). Human moves DO slide (Task 6).
- **Deferred:** real art + audio (M10); the battle-scene on/off setting + difficulty/title/gameover/save (M9).

## Self-review

- **Spec coverage:** battle_log + record (Task 1); BattleScene phase machine + play/finished (Task 2); richer portraits (Task 3); attack-flavor effects + arena + damage numbers + HP bars (Task 4); replay driver + human-attack cutaway + input block (Task 5); AI-turn replay + human move-slide + M7 polish + close (Task 6). ✅
- **Placeholder scan:** Tasks 1, 2, 5, 6 ship complete code + exact commands. Tasks 3-4 are bulk procedural ports specified by source range + API mapping + integration contract + worked signatures (the appropriate granularity for translating fully-defined draw code; not logic hand-waving). ✅
- **Type/signature consistency:** record shape is identical across `resolve_attack` (producer), `_test_battle_record`, `BattleScene.play`/`_draw`, and `BattleFx`/`BattleSprites` consumers (`attacker`/`defender` views with `type_key`/`element`/`owner`/`attack`/`is_master`; `primary`/`counter` with `dmg`/`absorbed`/`killed`; `status`; `terrain`; `*_hp_before`/`*_max_hp`). `next_phase(phase, has_counter)` is used in the node and the test. `_play_battles`/`_busy`/`_slide_unit`/`_unit_node_for` are defined in Tasks 5-6 and used consistently. `BattleSceneScript`/`BattleSprites`/`BattleFx` preload-const-as-type per the main.gd no-class_name pattern. ✅
