# Wraithspire Godot M10 — Art (real sprite integration) — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Swap the 44 generated sprite PNGs in behind the existing board-token and battle-portrait render seams, with engine-side team identity (ring + frame), replacing the placeholder procedural art.

**Architecture:** A cached `Sprites` loader resolves sprite-id (+ owner for archon) + kind → `Texture2D`. `unit_node._draw` keeps the team ring + HP/status overlays and draws the token texture; `BattleSprites.draw_unit` keeps its signature/bob/lunge/mirror but draws the battle texture + a team frame and drops all procedural `_draw_<sprite>` bodies. The 44 PNGs are imported (`.import` sidecars) and committed.

**Tech Stack:** Godot 4.6.3 GDScript; `draw_texture_rect` / `draw_set_transform`; `AudioStreamWAV`-style generated-asset discipline N/A here (real PNG textures); headless harness.

**Spec:** `docs/superpowers/specs/2026-06-11-wraithspire-godot-m10-art-design.md`
**Manifest:** `docs/superpowers/specs/2026-06-11-wraithspire-sprite-manifest.md`

---

## Conventions (every task)

- **Harness gate:** `pwsh -File godot/tests/run_tests.ps1` → last line `== N passed, 0 failed ==`, EXIT 0. NO `-ExecutionPolicy Bypass`.
- **Headless-boot gate** (after any scene/loader change — the KEY gate for art, surfaces failed texture loads): `godot --headless --path godot --quit-after 30 2>&1 | Select-String "SCRIPT ERROR|Parse Error|Failed to load"` → no matches.
- The 44 PNGs already exist in `godot/assets/sprites/` (validated: tokens 512², battles 1024², names per the manifest). `core/sprites.gd` resolves them.
- Commit after each task. `Sprites` is `class_name`-registered, so the harness parse-checks it.

## File structure

| File | Responsibility |
|------|----------------|
| `godot/assets/sprites/*.png` + `*.import` (commit) | the 44 textures + Godot import sidecars |
| `core/sprites.gd` (new) | cached `token(id,owner)`/`battle(id,owner)` → Texture2D resolver |
| `scenes/match/unit_node.gd` (edit) | board token: keep ring + HP/status, draw token texture |
| `scenes/battle/battle_sprites.gd` (edit) | battle: texture + team frame + mirror; remove procedural `_draw_<sprite>` |
| `tests/run_tests.gd` (edit) | `_test_sprites` completeness guard |

---

## Task 1: Import assets + commit

Godot needs `.import` sidecars (and an imported `.ctex` cache) before `load()` resolves a PNG. Generate them once, then commit the PNGs + sidecars.

**Files:**
- Commit: `godot/assets/sprites/*.png` (44) + the generated `godot/assets/sprites/*.import` (44)

- [ ] **Step 1: Run the import pass**

Run (repo root): `godot --headless --import --path godot`
Expected: Godot imports the textures and exits. If `--import` is unsupported on this build, use the fallback: `godot --headless --editor --quit --path godot` (opens the project headlessly, runs an import pass, quits).

- [ ] **Step 2: Verify the .import sidecars were created**

Run: `ls godot/assets/sprites/*.import | wc -l`
Expected: `44` (one `.import` per PNG). Also confirm `.godot/imported/` now holds `.ctex` files (these stay git-ignored per `godot/.gitignore`).

- [ ] **Step 3: Headless-boot gate**

Run: `godot --headless --path godot --quit-after 30 2>&1 | Select-String "SCRIPT ERROR|Parse Error|Failed to load"`
Expected: no matches (project still boots; nothing references the textures yet).

- [ ] **Step 4: Commit the assets**

```bash
git add godot/assets/sprites/*.png godot/assets/sprites/*.import
git commit -m "[godot] M10 art task 1: import + commit 44 sprite PNGs (.import sidecars)"
```
(`.godot/` is git-ignored, so only the PNGs + `.import` files are tracked.)

---

## Task 2: Sprites loader + completeness test

**Files:**
- Create: `godot/core/sprites.gd`
- Modify: `godot/tests/run_tests.gd`

- [ ] **Step 1: Write the failing test**

Add the preload near the others in `run_tests.gd`:
```gdscript
const Sprites = preload("res://core/sprites.gd")
```
Call in `_initialize()`:
```gdscript
	_test_sprites()
```
Method (`UnitTypes` is already preloaded in run_tests.gd):
```gdscript
func _test_sprites() -> void:
	# every distinct sprite id in UNIT_TYPES resolves a non-null token + battle texture
	for key in UnitTypes.UNIT_TYPES:
		var sid: String = UnitTypes.UNIT_TYPES[key]["sprite"]
		_ok(Sprites.token(sid, 0) is Texture2D, "sprites: token %s loads" % sid)
		_ok(Sprites.battle(sid, 0) is Texture2D, "sprites: battle %s loads" % sid)
	# archon resolves for both factions, token + battle
	_ok(Sprites.token("archon", 0) is Texture2D, "sprites: archon azure token")
	_ok(Sprites.token("archon", 1) is Texture2D, "sprites: archon crimson token")
	_ok(Sprites.battle("archon", 0) is Texture2D, "sprites: archon azure battle")
	_ok(Sprites.battle("archon", 1) is Texture2D, "sprites: archon crimson battle")
	# archon art differs per faction; neutral monster art does NOT depend on owner
	_ok(Sprites.battle("archon", 0) != Sprites.battle("archon", 1), "sprites: archon faction split")
	_ok(Sprites.token("imp", 0) == Sprites.token("imp", 1), "sprites: neutral monster owner-independent")
```

- [ ] **Step 2: Run harness, verify fail**

Run: `pwsh -File godot/tests/run_tests.ps1` → FAIL (`Could not load res://core/sprites.gd`), EXIT 1.

- [ ] **Step 3: Implement `core/sprites.gd`**

```gdscript
class_name Sprites
extends RefCounted
## M10 art resolver: sprite-id (+ owner for the archon) + kind → Texture2D, cached.
## The single seam both renderers (board token, battle portrait) use to load art.
## Faction-neutral monsters ignore owner; only "archon" splits per faction.
## Files: res://assets/sprites/<stem>_<token|battle>.png (manifest naming).

const DIR := "res://assets/sprites/"

static var _cache := {}

## _stem — filename stem for a sprite id. Archon is bespoke per faction; all other
## monsters are faction-neutral (owner ignored).
static func _stem(sprite_id: String, owner: int) -> String:
	if sprite_id == "archon":
		return "archon_azure" if owner == 0 else "archon_crimson"
	return sprite_id

static func _tex(stem: String, kind: String) -> Texture2D:
	var path := "%s%s_%s.png" % [DIR, stem, kind]
	if _cache.has(path):
		return _cache[path]
	var t: Texture2D = null
	if ResourceLoader.exists(path):
		t = load(path)
	_cache[path] = t
	return t

static func token(sprite_id: String, owner: int) -> Texture2D:
	return _tex(_stem(sprite_id, owner), "token")

static func battle(sprite_id: String, owner: int) -> Texture2D:
	return _tex(_stem(sprite_id, owner), "battle")
```

- [ ] **Step 4: Run harness, verify pass**

Run: `pwsh -File godot/tests/run_tests.ps1` → `== N passed, 0 failed ==`, EXIT 0.
(If a texture fails to load headless — i.e. `is Texture2D` is false — the import from Task 1 didn't take; re-run Task 1's import pass. The textures DO load under the `--script` harness once `.godot/imported/` exists.)

- [ ] **Step 5: Commit**

```bash
git add godot/core/sprites.gd godot/tests/run_tests.gd
git commit -m "[godot] M10 art task 2: Sprites loader + completeness test"
```

---

## Task 3: Board token swap (`unit_node.gd`)

Replace the procedural element-circle + master-pip with the token texture; keep the team ring (faction ID) as a disc behind it, and keep the HP bar + status pips.

**Files:**
- Modify: `godot/scenes/match/unit_node.gd`

- [ ] **Step 1: Add the Sprites preload + rewrite `_draw`'s body block**

At the top, add near `const Hex`:
```gdscript
const Sprites = preload("res://core/sprites.gd")
```
Replace the current `_draw` (the ring + fill + master-pip block) with — keep the HP bar + status pip calls:
```gdscript
func _draw() -> void:
	if unit == null:
		return
	var radius := Hex.SIZE * 0.62
	# Team-colored base disc (faction identity) — the transparent-bg token sits on it.
	draw_circle(Vector2.ZERO, radius, TEAM_COLORS[unit["owner"]])
	# Real creature art (faction-neutral; archon splits on owner inside Sprites).
	var tex := Sprites.token(unit["sprite"], unit["owner"])
	if tex != null:
		var s := radius * 2.0          # token fills the team disc; transparent edges show the ring
		draw_texture_rect(tex, Rect2(-s / 2.0, -s / 2.0, s, s), false)
	_draw_hp_bar(radius)
	_draw_status_pips(radius)
```
(The `TEAM_COLORS` const + `_draw_hp_bar` + `_draw_status_pips` already exist and are unchanged. The `ELEMENT_COLORS` const is now only used if something else references it — leave it; it's harmless data. Remove it only if unused after this change.)

- [ ] **Step 2: Harness + boot gates**

Run: `pwsh -File godot/tests/run_tests.ps1` → `== N passed, 0 failed ==`, EXIT 0.
Run: `godot --headless --path godot --quit-after 30 2>&1 | Select-String "SCRIPT ERROR|Parse Error|Failed to load"` → no matches.

- [ ] **Step 3: Commit**

```bash
git add godot/scenes/match/unit_node.gd
git commit -m "[godot] M10 art task 3: board token swap (team ring + token texture + HP/status)"
```

---

## Task 4: Battle portrait swap (`battle_sprites.gd`)

Rewrite `draw_unit` to draw the battle texture (mirrored for the defender) with a team-colored frame, keeping bob/lunge. Remove all procedural `_draw_<sprite>` bodies.

**Files:**
- Modify: `godot/scenes/battle/battle_sprites.gd`

- [ ] **Step 1: Add the Sprites preload**

At the top, near `const Elements`:
```gdscript
const Sprites = preload("res://core/sprites.gd")
```

- [ ] **Step 2: Rewrite `draw_unit`**

Replace the entire `draw_unit` function (the bob/lunge calc + the `is_master`/`match view["sprite"]` dispatch) with:
```gdscript
## draw_unit — render one combatant's real portrait centered with feet at (cx,cy).
## Keeps the idle bob + charge/impact lunge; mirrors for the defender (facing -1).
## A team-colored backing glow gives battle-scene faction identity (monsters are
## faction-neutral art; the archon portrait is already bespoke per faction).
## `view` carries sprite/owner/is_master; `pose` ∈ idle/charge/impact/recover; t = phase 0..1.
const PORTRAIT_H := 320.0   # on-screen portrait height (1024² source scaled down)

static func draw_unit(ci: CanvasItem, view: Dictionary, cx: float, cy: float, facing: int, pose: String, t: float) -> void:
	var bob := sin(t * 42.0 / 14.0) * 1.2
	var lunge := 0.0
	if pose == "charge":
		lunge = facing * 6.0 * SCALE
	elif pose == "impact":
		lunge = facing * -8.0 * SCALE
	var ocx := cx + lunge
	var ocy := cy + bob
	var sprite_id: String = "archon" if view.get("is_master", false) else view["sprite"]
	var tex := Sprites.battle(sprite_id, view.get("owner", 0))
	var p := _pal(view.get("owner", 0))
	# Backing glow (team identity): a soft team-colored ellipse behind the portrait.
	var glow: Color = p["color"]
	glow.a = 0.22
	_draw_ellipse(ci, Vector2(ocx, ocy - PORTRAIT_H * 0.42), PORTRAIT_H * 0.34, PORTRAIT_H * 0.5, glow)
	# Ground shadow.
	_draw_ellipse(ci, Vector2(ocx, ocy), PORTRAIT_H * 0.30, PORTRAIT_H * 0.07, Color(0, 0, 0, 0.35))
	if tex == null:
		return
	# Portrait: square source, drawn feet-at-(ocx,ocy), bottom-centered; mirror on facing.
	var w := PORTRAIT_H
	ci.draw_set_transform(Vector2(ocx, ocy), 0.0, Vector2(facing, 1.0))
	ci.draw_texture_rect(tex, Rect2(-w / 2.0, -PORTRAIT_H, w, PORTRAIT_H), false)
	ci.draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
```
Add the ellipse helper (after `draw_unit`):
```gdscript
## _draw_ellipse — filled ellipse via a scaled circle (no native draw_ellipse).
static func _draw_ellipse(ci: CanvasItem, center: Vector2, rx: float, ry: float, col: Color) -> void:
	ci.draw_set_transform(center, 0.0, Vector2(rx, ry))
	ci.draw_circle(Vector2.ZERO, 1.0, col)
	ci.draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
```

- [ ] **Step 3: Delete the procedural sprite functions**

Remove ALL of these static functions from `battle_sprites.gd` (they are now dead):
`_draw_archon`, `_draw_imp`, `_draw_wyrm`, `_draw_merfolk`, `_draw_serpent`, `_draw_golem`, `_draw_ogre`, `_draw_wisp`, `_draw_raptor`, `_draw_infernite`, `_draw_emberdrake`, `_draw_tidelord`, `_draw_leviathan`, `_draw_colossus`, `_draw_earthbreaker`, `_draw_stormwisp`, `_draw_skytyrant`, `_draw_hexwisp`, `_draw_runeward`, `_draw_frostmaw`, `_draw_duneskink`, `_draw_generic`.
Also remove the `_p` helper (only the deleted functions used it). **Keep** `_pal` (the frame/glow uses it) and `SCALE` (the lunge uses it). After deleting, grep the file for `_p(` and `Elements` — if `_p` has no remaining callers it's removed; if the `Elements` preload has no remaining references, remove that preload line too.

Run: `grep -nE "_draw_|_p\(|Elements\." godot/scenes/battle/battle_sprites.gd` → should show NO `_draw_<sprite>`/`_p(` calls and no `Elements.` uses (remove the `const Elements` preload if so).

- [ ] **Step 4: Harness + boot gates**

Run: `pwsh -File godot/tests/run_tests.ps1` → `== N passed, 0 failed ==`, EXIT 0. (The harness force-preloads `battle_sprites.gd` and calls its static `next_phase`? — no, that's `battle_scene.gd`. `battle_sprites.gd` is class_name-registered; it parse-loads. Confirm green.)
Run: `godot --headless --path godot --quit-after 30 2>&1 | Select-String "SCRIPT ERROR|Parse Error|Failed to load"` → no matches.

- [ ] **Step 5: Commit**

```bash
git add godot/scenes/battle/battle_sprites.gd
git commit -m "[godot] M10 art task 4: battle portrait swap (texture + team frame + mirror); drop procedural draws"
```

---

## Manual (windowed) verification — after Task 4

Headless can't render. Run `godot --path godot` and confirm:
- Board: each unit shows its real creature token on a team-colored disc; HP bar + status pips still overlay; readable at hex scale.
- Battle cutaway (`#battle`-equivalent: trigger a fight): attacker portrait faces right, defender mirrored faces left, each on a team-colored glow; archons show the bespoke AZURE (round hood) / CRIMSON (spiked) designs; attack FX (breath/spray/etc) still fire; HP bars + damage popups intact.
- Title screen archon previews + gameover archon (both call `BattleSprites.draw_unit`) now show the real archon art.

---

## Final milestone review

After Task 4: whole-sub-milestone opus review over `git diff <base>..HEAD -- godot/` (base = commit before Task 1). Then:
- Update `ROADMAP_GODOT.md`: check off `- [x] M10 — Art + audio` (both halves now done).
- Update `SESSION_STATE.md`: M10 COMPLETE — port has real art + audio over full JS parity; next = ROADMAP2 Phases 2–8 (each its own post-parity spec).
- Record accepted divergences (single-pose portraits + bob/lunge; procedural attack FX retained; team ring/frame faction-ID).

---

## Self-review notes (author)

- **Spec coverage:** Sprites loader + completeness test (T2) ✓; board token swap keeping ring + HP/status (T3) ✓; battle portrait swap + team frame + mirror + bob/lunge, remove procedural (T4) ✓; archon-by-owner via Sprites (T2 resolver, used in T3/T4) ✓; import + commit assets (T1) ✓; engine ring/frame faction-ID (T3/T4) ✓.
- **Type consistency:** `Sprites.token(id,owner)` / `Sprites.battle(id,owner)` signatures defined in T2 match the calls in T3 (`unit_node`) and T4 (`battle_sprites`). `draw_unit` keeps its exact signature so `battle_scene` (caller, untouched) still works. `_pal(owner)` (kept) returns `{color,dark,trim}` as used by the glow.
- **Ordering:** Task 1 (import) MUST precede Task 2 (the test loads textures); the plan sequences it first.
- **Headless texture load:** under `--script`, `load("res://...png")` resolves the imported `.ctex` once `.godot/imported/` exists (Task 1). If the harness can't load a texture, `is Texture2D` fails loudly — re-run import. Not expected to be an issue.
- **Removal safety (T4):** the instruction greps for `_p(`/`_draw_`/`Elements.` after deletion so no dangling reference survives; `_pal`/`SCALE` are explicitly kept.
