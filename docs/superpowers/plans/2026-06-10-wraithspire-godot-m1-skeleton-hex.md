# Wraithspire Godot Port — Milestone 1: Skeleton + Headless Harness + Hex Core — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Stand up the Godot 4 project (.NET build), a `godot --headless` assert harness that gates every commit, and the pure hex-math core ported from the JS reference — all green.

**Architecture:** Pure logic core with zero node/render dependencies (per the port spec keystone). The Godot project lives in a `godot/` subfolder so the JS reference (`game.js`, `index.html`) stays pristine and Godot doesn't import the whole repo. Tests are a `SceneTree` script run headless via a PowerShell wrapper; exit code gates commits.

**Tech Stack:** Godot 4.x .NET (Mono) build, GDScript (zero C# until a profiled hotspot), PowerShell wrapper for the test gate. Spec: `docs/superpowers/specs/2026-06-10-wraithspire-godot-port-design.md`. Reference hex math: `game.js` section 2 (lines ~91–141).

---

## File structure (created this milestone)

```
godot/
  project.godot          minimal Godot 4 project config
  .gitignore             ignore .godot/ import cache (+ future .NET artifacts)
  core/
    hex.gd               pure pointy-top axial math (class_name Hex)
  data/        .gitkeep  (populated milestone 2)
  scenes/      .gitkeep  (populated milestone 2+)
  autoload/    .gitkeep  (populated later)
  assets/      .gitkeep  (populated milestone 10)
  tests/
    run_tests.gd         SceneTree headless harness + assert helpers + hex tests
    run_tests.ps1        wrapper: resolves Godot, runs harness, propagates exit code
ROADMAP_GODOT.md         milestone tracker (repo root, mirrors ROADMAP2.md)
```

The Godot project root is `godot/`. All `res://` paths are relative to it (e.g. `res://core/hex.gd` = `godot/core/hex.gd`).

---

## Task 1: Install the Godot 4 .NET build

**Who runs it:** the **user** runs the install (download/elevation is interactive). The agent verifies afterward. The .NET SDK is intentionally NOT installed — the Mono editor runs GDScript without it; the SDK is deferred until a real C# hotspot.

**Files:** none.

- [ ] **Step 1 (user): Install the Godot 4 .NET / Mono build**

Preferred (winget). Run in your terminal with the `!` prefix so the output lands in this session:

```
! winget install --id GodotEngine.GodotEngine.Mono -e --accept-source-agreements --accept-package-agreements
```

Fallback if winget has no such package or the install fails: download the **.NET** build of Godot 4 (latest stable) from https://godotengine.org/download/windows (the ".NET" / "Mono" download, not the standard one), extract the zip to a stable folder (e.g. `%LOCALAPPDATA%\Programs\Godot`), and note the full path to `Godot_v4.*-stable_mono_win64.exe`.

- [ ] **Step 2 (agent): Resolve a working `godot` invocation**

Try PATH first; if absent, locate the winget/extracted exe and either add its folder to PATH or set `$env:GODOT`.

Run:
```powershell
$g = (Get-Command godot -ErrorAction SilentlyContinue).Source
if (-not $g) {
  $cand = Get-ChildItem "$env:LOCALAPPDATA\Microsoft\WinGet\Packages\GodotEngine.GodotEngine.Mono*","$env:LOCALAPPDATA\Programs\Godot" -Recurse -Filter "*mono*win64*.exe" -ErrorAction SilentlyContinue |
          Select-Object -First 1
  if ($cand) { $env:GODOT = $cand.FullName }
}
$exe = if ($g) { $g } else { $env:GODOT }
if (-not $exe) { "GODOT NOT FOUND — ask the user for the exe path" } else { & $exe --version }
```
Expected: a version line like `4.4.1.stable.mono.<hash>` (major.minor 4.x, the `mono` token confirming the .NET build). If `godot` was not on PATH, `$env:GODOT` now points at the exe — later tasks and `run_tests.ps1` use that fallback.

- [ ] **Step 3 (agent): Record the Godot exe path and version**

If `godot` is not on PATH, set it as a **user** environment variable so it survives new shells:
```powershell
if (-not (Get-Command godot -ErrorAction SilentlyContinue) -and $env:GODOT) {
  [Environment]::SetEnvironmentVariable("GODOT", $env:GODOT, "User")
  "Persisted `$env:GODOT = $env:GODOT"
}
```
Expected: either `godot` is on PATH (nothing to do) or `GODOT` is persisted for the user. No commit (no repo files changed).

---

## Task 2: Project skeleton

**Files:**
- Create: `godot/project.godot`
- Create: `godot/.gitignore`
- Create: `godot/core/.gitkeep`, `godot/data/.gitkeep`, `godot/scenes/.gitkeep`, `godot/autoload/.gitkeep`, `godot/assets/.gitkeep`
- Create: `ROADMAP_GODOT.md`

- [ ] **Step 1: Create the folder structure**

Run:
```powershell
$dirs = "godot/core","godot/data","godot/scenes","godot/autoload","godot/assets","godot/tests"
$dirs | ForEach-Object { New-Item -ItemType Directory -Force -Path $_ | Out-Null }
"core","data","scenes","autoload","assets" | ForEach-Object {
  New-Item -ItemType File -Force -Path "godot/$_/.gitkeep" | Out-Null
}
Get-ChildItem godot -Directory | Select-Object Name
```
Expected: lists `assets core data scenes tests` (and `autoload`).

- [ ] **Step 2: Write `godot/project.godot` (version-matched)**

Derive the installed major.minor and write the project file. Run:
```powershell
$exe = (Get-Command godot -ErrorAction SilentlyContinue).Source; if (-not $exe) { $exe = $env:GODOT }
$ver = (& $exe --version)                      # e.g. 4.4.1.stable.mono.abc
$mm  = ($ver -split '\.')[0..1] -join '.'       # -> 4.4
@"
config_version=5

[application]

config/name="Wraithspire (Godot port)"
config/features=PackedStringArray("$mm")
run/main_scene=""
"@ | Set-Content -Path godot/project.godot -Encoding utf8
Get-Content godot/project.godot
```
Expected: prints the file; `config/features` contains your installed `4.x`.

- [ ] **Step 3: Write `godot/.gitignore`**

```
# Godot 4 import cache
.godot/

# .NET build artifacts (added only when a C# hotspot is approved)
.mono/
bin/
obj/
```

- [ ] **Step 4: Create `ROADMAP_GODOT.md` at the repo root**

```markdown
# ROADMAP — Wraithspire Godot 4 port (`godot-port`)

Port-to-parity milestone tracker. Protocol: one milestone → verify
(`pwsh godot/tests/run_tests.ps1` green) → commit `[godot] N: <summary>` →
check off here. Spec: `docs/superpowers/specs/2026-06-10-wraithspire-godot-port-design.md`.
The Godot project lives in `godot/`; the JS build at repo root stays the frozen
reference. ROADMAP2 Phases 2–8 are deferred to their own specs post-parity.

- [ ] **M1 — Skeleton + headless harness + hex core**
- [ ] M2 — Data tables + deterministic map gen (placeholder tiles)
- [ ] M3 — Units + movement/pathfinding + selection
- [ ] M4 — Combat resolution + status engine + weather (logic + forecast)
- [ ] M5 — All 12 abilities
- [ ] M6 — AI (threat map + decision tree + summon economy)
- [ ] M7 — HUD/UI as Control nodes
- [ ] M8 — Battle cutaway scene
- [ ] M9 — Title + gameover + save/load + maps + campaign → parity
- [ ] M10 — Art + audio pass (real sprites swap in)
```

- [ ] **Step 5: Commit**

```powershell
git add godot/project.godot godot/.gitignore godot/core/.gitkeep godot/data/.gitkeep godot/scenes/.gitkeep godot/autoload/.gitkeep godot/assets/.gitkeep ROADMAP_GODOT.md
git commit -m "[godot] M1: project skeleton + roadmap"
```

---

## Task 3: Headless test harness + wrapper (proven green with a smoke assert)

Build the harness and prove the end-to-end headless pipeline works **before** writing real tests. This is the task where any flag/behavior surprise surfaces.

**Files:**
- Create: `godot/tests/run_tests.gd`
- Create: `godot/tests/run_tests.ps1`

- [ ] **Step 1: Write `godot/tests/run_tests.gd` (harness + one smoke assert)**

```gdscript
extends SceneTree
## Headless test harness. Run via tests/run_tests.ps1, which wraps:
##   godot --headless --path godot --script res://tests/run_tests.gd
## Exits 0 if all asserts pass, 1 otherwise. Pure-logic tests only (no display).

var _passed := 0
var _failed := 0

func _initialize() -> void:
	_test_harness_smoke()
	print("\n== %d passed, %d failed ==" % [_passed, _failed])
	quit(1 if _failed > 0 else 0)

# ---- assert helpers ----
func _ok(cond: bool, msg: String) -> void:
	if cond:
		_passed += 1
	else:
		_failed += 1
		printerr("FAIL: " + msg)

func _eq(got: Variant, want: Variant, msg: String) -> void:
	_ok(got == want, "%s  (got %s, want %s)" % [msg, str(got), str(want)])

# ---- tests ----
func _test_harness_smoke() -> void:
	_eq(1 + 1, 2, "harness smoke")
```

- [ ] **Step 2: Write `godot/tests/run_tests.ps1` (wrapper that gates commits)**

```powershell
#requires -version 5
$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent $PSScriptRoot   # godot/tests -> godot
$godot = (Get-Command godot -ErrorAction SilentlyContinue).Source
if (-not $godot) { $godot = $env:GODOT }
if (-not $godot -or -not (Test-Path $godot)) {
  throw "Godot not found. Put 'godot' on PATH or set `$env:GODOT to the Godot .NET exe."
}
& $godot --headless --path $root --script "res://tests/run_tests.gd"
exit $LASTEXITCODE
```

- [ ] **Step 3: Run the harness — verify it passes and exits 0**

Run:
```powershell
pwsh godot/tests/run_tests.ps1; "EXIT=$LASTEXITCODE"
```
(If `pwsh` is unavailable, use `powershell -File godot/tests/run_tests.ps1`.)
Expected: output ends with `== 1 passed, 0 failed ==` and `EXIT=0`. The first run may print Godot import lines (it builds `.godot/`); that's normal.

- [ ] **Step 4: Verify the gate fails red on a failing assert**

Temporarily break the smoke assert to confirm the exit code gates commits. Run:
```powershell
(Get-Content godot/tests/run_tests.gd) -replace '1 \+ 1, 2', '1 + 1, 3' | Set-Content godot/tests/run_tests.gd
pwsh godot/tests/run_tests.ps1; "EXIT=$LASTEXITCODE"
```
Expected: `FAIL: harness smoke ...`, `== 0 passed, 1 failed ==`, `EXIT=1`.

Then restore it:
```powershell
(Get-Content godot/tests/run_tests.gd) -replace '1 \+ 1, 3', '1 + 1, 2' | Set-Content godot/tests/run_tests.gd
pwsh godot/tests/run_tests.ps1; "EXIT=$LASTEXITCODE"
```
Expected: back to `== 1 passed, 0 failed ==`, `EXIT=0`.

- [ ] **Step 5: Commit**

```powershell
git add godot/tests/run_tests.gd godot/tests/run_tests.ps1
git commit -m "[godot] M1: headless test harness + commit gate"
```

---

## Task 4: Hex math core (TDD)

Port the JS pointy-top axial math (`game.js` section 2) to a pure GDScript lib, test-first. Axial coords are `Vector2i` (x=q, y=r). The pixel conversion is grid-relative and layout-free (the board node applies its own screen offset later) — so the JS `+6`/`HEX_W/2` canvas margins are intentionally NOT ported here.

**Files:**
- Create: `godot/core/hex.gd`
- Modify: `godot/tests/run_tests.gd` (add `_test_hex`, preload the lib, call it from `_initialize`)
- Modify: `ROADMAP_GODOT.md` (check off M1)

- [ ] **Step 1: Add the failing hex tests to `godot/tests/run_tests.gd`**

Add the preload at the top, just under `extends SceneTree`:
```gdscript
const HexLib = preload("res://core/hex.gd")
```

Add the call inside `_initialize`, right after `_test_harness_smoke()`:
```gdscript
	_test_hex()
```

Append this test function to the file:
```gdscript
func _test_hex() -> void:
	# distance
	_eq(HexLib.distance(Vector2i(0, 0), Vector2i(0, 0)), 0, "distance: self")
	_eq(HexLib.distance(Vector2i(0, 0), Vector2i(1, 0)), 1, "distance: +q neighbor")
	_eq(HexLib.distance(Vector2i(0, 0), Vector2i(0, 1)), 1, "distance: +r neighbor")
	_eq(HexLib.distance(Vector2i(0, 0), Vector2i(1, -1)), 1, "distance: diagonal neighbor")
	_eq(HexLib.distance(Vector2i(0, 0), Vector2i(3, 0)), 3, "distance: straight 3")
	_eq(HexLib.distance(Vector2i(0, 0), Vector2i(-2, -1)), 3, "distance: -2,-1")
	_eq(HexLib.distance(Vector2i(2, -1), Vector2i(-1, 1)), 3, "distance: arbitrary")
	# neighbors (DIRS order, matching the JS HEX_DIRS)
	_eq(HexLib.neighbors(Vector2i(0, 0)), HexLib.DIRS, "neighbors: origin == DIRS")
	_eq(HexLib.neighbors(Vector2i(2, 3)), [
		Vector2i(3, 3), Vector2i(3, 2), Vector2i(2, 2),
		Vector2i(1, 3), Vector2i(1, 4), Vector2i(2, 4),
	], "neighbors: offset")
	# key
	_eq(HexLib.key(Vector2i(3, -2)), "3,-2", "key: format")
	# pixel round-trip: a hex center maps back to its own axial
	for a in [Vector2i(0, 0), Vector2i(3, -2), Vector2i(-4, 5), Vector2i(7, 0), Vector2i(0, 6)]:
		_eq(HexLib.pixel_to_axial(HexLib.axial_to_pixel(a)), a, "round-trip %s" % str(a))
```

- [ ] **Step 2: Run — verify it fails (hex.gd does not exist yet)**

Run:
```powershell
pwsh godot/tests/run_tests.ps1; "EXIT=$LASTEXITCODE"
```
Expected: a parse/load error referencing `res://core/hex.gd` not found (preload of a missing file), non-zero `EXIT`. This confirms the new tests are wired in and currently failing.

- [ ] **Step 3: Implement `godot/core/hex.gd`**

```gdscript
class_name Hex
extends RefCounted
## Pointy-top axial hex math. Ported from the JS reference (game.js, section 2).
## Axial coords are Vector2i where x = q, y = r. Pure: no node/render deps.

const SIZE := 36.0  ## hex "radius" (HEX_SIZE in the JS reference)

## Six axial neighbor directions, in the JS reference order (HEX_DIRS).
const DIRS: Array[Vector2i] = [
	Vector2i(1, 0), Vector2i(1, -1), Vector2i(0, -1),
	Vector2i(-1, 0), Vector2i(-1, 1), Vector2i(0, 1),
]

## Axial -> pixel, grid-relative (hex {0,0} center is the origin). The board node
## applies its own screen offset; this lib stays layout-free, so the JS canvas
## margins (+6 / HEX_W/2) are intentionally not ported here.
static func axial_to_pixel(a: Vector2i) -> Vector2:
	var q := float(a.x)
	var r := float(a.y)
	return Vector2(SIZE * sqrt(3.0) * (q + r / 2.0), SIZE * 1.5 * r)

## Pixel (grid-relative) -> nearest axial.
static func pixel_to_axial(p: Vector2) -> Vector2i:
	var q := (sqrt(3.0) / 3.0 * p.x - 1.0 / 3.0 * p.y) / SIZE
	var r := (2.0 / 3.0 * p.y) / SIZE
	return round_axial(q, r)

## Cube-rounding of fractional axial coords to the nearest hex.
static func round_axial(qf: float, rf: float) -> Vector2i:
	var sf := -qf - rf
	var rq := roundi(qf)
	var rr := roundi(rf)
	var rs := roundi(sf)
	var dq := absf(rq - qf)
	var dr := absf(rr - rf)
	var ds := absf(rs - sf)
	if dq > dr and dq > ds:
		rq = -rr - rs
	elif dr > ds:
		rr = -rq - rs
	return Vector2i(rq, rr)

## The six neighbors of an axial coord, in DIRS order.
static func neighbors(a: Vector2i) -> Array[Vector2i]:
	var out: Array[Vector2i] = []
	for d in DIRS:
		out.append(a + d)
	return out

## Axial distance (number of steps between two hexes).
static func distance(a: Vector2i, b: Vector2i) -> int:
	return (absi(a.x - b.x) + absi(a.x + a.y - b.x - b.y) + absi(a.y - b.y)) / 2

## Storage key "q,r" (matches the JS hexKey).
static func key(a: Vector2i) -> String:
	return "%d,%d" % [a.x, a.y]
```

- [ ] **Step 4: Run — verify all tests pass**

Run:
```powershell
pwsh godot/tests/run_tests.ps1; "EXIT=$LASTEXITCODE"
```
Expected: `== 16 passed, 0 failed ==` (1 smoke + 15 hex asserts) and `EXIT=0`.

- [ ] **Step 5: Check off M1 in `ROADMAP_GODOT.md`**

Change `- [ ] **M1 — Skeleton...` to `- [x] **M1 — Skeleton...`.

- [ ] **Step 6: Commit**

```powershell
git add godot/core/hex.gd godot/tests/run_tests.gd ROADMAP_GODOT.md
git commit -m "[godot] M1: hex math core (axial coords, neighbors, distance, pixel conv)"
```

---

## Notes & risk callouts

- **First headless run builds `.godot/`** (import cache) — ignored by `godot/.gitignore`. Expect import chatter on stdout the first time; it doesn't affect the exit code.
- **`--script` + `SceneTree`**: if a Godot version rejects `_initialize()` or the `--script` invocation differs, Task 3's smoke step is where it surfaces — fix the harness there before Task 4. The fallback invocation is `& $godot --headless --path godot res://tests/run_tests.gd` (positional script) if `--script` misbehaves.
- **`preload` vs `class_name`**: tests `preload` the lib under the name `HexLib` to avoid depending on global-class registration timing in `--script` runs (and to avoid shadowing the `class_name Hex` global). `hex.gd` keeps `class_name Hex` for editor/other-script ergonomics.
- **Array equality**: Godot 4 compares `Array` by value (size + elements), so `neighbors(...) == [Vector2i(...), ...]` works.
- **`.NET` SDK absent on purpose**: the Mono editor runs GDScript without it. Installing the .NET SDK + creating a `.csproj` happens only when a C# hotspot is approved (the AI scorer seam).
```
