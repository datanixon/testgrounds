# Wraithspire Godot port — M10 (Art): real sprite integration

Date: 2026-06-11
Branch: `godot-m10-art`
Milestone: M10 "Art + audio" — this spec covers the **ART half** (audio already
done + merged to main). After this, M10 is complete and the port has real art +
audio over the entire JS-parity feature set. ROADMAP2 Phases 2–8 then get
post-parity specs.
References: art brief `docs/superpowers/specs/2026-06-10-wraithspire-art-brief.md`;
filename manifest `docs/superpowers/specs/2026-06-11-wraithspire-sprite-manifest.md`;
port design spec "Art pipeline" section.

## Goal

Swap the 44 generated sprite PNGs (already in `godot/assets/sprites/`, validated:
22 tokens @512² + 22 battle portraits @1024²) in behind the existing render
seams, replacing the placeholder procedural art. Team identity stays engine-side
(colored base-ring on the board token, colored frame in the battle cutaway), so
the faction-NEUTRAL monster art serves both sides; archons are bespoke per
faction. This finalizes the deferred faction-ID decision and completes the port.

## Scope decisions (locked with user, 2026-06-11)

- **Faction-ID method:** engine ring (board) + frame/glow (battle); archons
  bespoke per faction. (Closes the port-design spec's deferred decision; NOT a
  palette-swap shader.)
- **Texture loading:** a single `Sprites` loader (cached preload), resolving
  sprite-id (+ owner for archon) + kind → `Texture2D`.
- **Battle motion:** keep the existing sine-bob idle + charge/impact lunge offset
  on the static portrait. Attack effects (`battle_fx`) stay procedural.
- **Procedural `_draw_<sprite>` bodies:** removed (replaced by the texture draw).
- **Assets in git:** commit the 44 PNGs + their `.import` sidecars on this branch
  (`.godot/` import cache stays git-ignored).

## Architecture

The art swap touches exactly two render seams and adds one loader; the data,
logic, HUD, screens, and audio are untouched.

### `core/sprites.gd` (new — class `Sprites`)

The single art-resolution seam. Both renderers call it; nothing else loads sprite
textures.

- `token(sprite_id: String, owner: int) -> Texture2D`
- `battle(sprite_id: String, owner: int) -> Texture2D`
- Resolution: filename stem is the `sprite_id`, EXCEPT `sprite_id == "archon"`
  which maps to `archon_azure` (owner 0) / `archon_crimson` (owner 1). Path:
  `res://assets/sprites/<stem>_<token|battle>.png`.
- Textures are cached in a static dict on first request (load-once). A missing
  file returns `null` (the completeness test guarantees none are missing).
- Pure-ish (no nodes); headless-loadable. The faction-neutral monsters ignore
  `owner`; only `archon` branches on it.

### Board token — `scenes/match/unit_node.gd`

`_draw` recomposes as: **team-colored base ring** (kept — faction ID) →
`Sprites.token(unit["sprite"], unit["owner"])` drawn centered and scaled to ~fit
the hex (ring radius is `Hex.SIZE * 0.62 ≈ 22`; the 512² token draws into roughly
a `2.2 × ring_radius` box, tuned for readability) → **HP bar + status pips** on
top (kept). The procedural element-circle + master pip are removed (the token art
carries the creature identity; the ring carries the team). Node interface
(`bind`/`refresh`) unchanged, so `units_layer` is untouched.

### Battle portrait — `scenes/battle/battle_sprites.gd`

`draw_unit(ci, view, cx, cy, facing, pose, t)` keeps its signature (so
`battle_scene` is untouched) but its body becomes:
1. Compute the existing `bob` (idle sine) + `lunge` (charge/impact) offsets →
   `ocx/ocy`.
2. Draw a **team-colored frame/glow** behind the portrait (battle faction ID),
   keyed on `view["owner"]` (reuses the `_pal(owner)` colors).
3. Draw `Sprites.battle(view["sprite"], view["owner"])` into a target rect
   centered on `(ocx, ocy)`, sized to the cutaway (the 1024² portrait scaled to a
   tuned on-screen height), **mirrored horizontally when `facing < 0`** (defender)
   via a negative-width `draw_texture_rect` (or `draw_texture_rect_region` with a
   flipped rect).
4. `is_master` resolves through `Sprites.battle("archon", owner)` (the archon
   branch), so the bespoke per-faction portraits show.

All 20+ `_draw_<sprite>` procedural functions + `_draw_archon` + `_draw_generic`
+ the `_p`/`_pal` pixel helpers that only they used are **removed**. `_pal` is
KEPT if the frame reuses it (team colors). The `SCALE` const and `_p` helper go
if nothing else references them (verify before deleting).

### Asset import

The PNGs need Godot `.import` sidecars + imported `.ctex` before `load()` works.
Generate them once headlessly: `godot --headless --import --path godot` (or
`--editor --quit`). Commit the 44 `.png` + 44 `.import` files; `.godot/` (the
imported `.ctex` cache) stays git-ignored and regenerates on import. The
headless-boot gate confirms the textures load with no errors.

## Testing

Harness (`pwsh -File godot/tests/run_tests.ps1`, `== N passed, 0 failed ==`):
- **`_test_sprites`** — completeness/loadability guard: for every `sprite` id in
  `UnitTypes.UNIT_TYPES` (20 distinct), assert `Sprites.token(id, 0)` and
  `Sprites.battle(id, 0)` return a non-null `Texture2D`; and for `"archon"`,
  assert both owners (0,1) resolve for token + battle. Also assert archon owner 0
  ≠ owner 1 texture (faction split) and a neutral monster resolves the same
  texture regardless of owner. This catches a missing/misnamed file or a broken
  resolver. (Textures load fine under the headless harness once imported.)

**Headless-boot gate** after any scene/loader change: `godot --headless --path
godot --quit-after 30 2>&1 | Select-String "SCRIPT ERROR|Parse Error|Failed to
load"` → clean. This is the key gate here — it surfaces a failed texture load
("Failed to load") or a draw error.

**Visual verification is manual/windowed** (`godot --path godot`): board tokens
show the real creatures with the team ring; battle cutaway shows the portraits
(attacker right-facing, defender mirrored) with the team frame; archons show the
bespoke AZURE/CRIMSON designs; attack FX still fire; readability holds at the
board's small scale and the battle's large scale.

## Accepted divergences / notes

- Single-pose portraits — no per-pose sprite frames; the bob + lunge transform
  supplies the cutaway motion (per the design spec's two-scale, single-pose art).
- Attack effects (`drawAttackEffect`: breath/spray/spark/dive/bolt/melee) remain
  procedural — they are FX layered over the portrait, not creature art.
- Board token scale is tuned to the 36px hex; the 512² source gives headroom so
  it stays crisp (`image-rendering` is engine-default; these are smooth textures,
  not pixel art).
- A missing texture would render nothing for that unit; the `_test_sprites`
  completeness guard prevents shipping with a gap.

## Success criteria

The game shows real generated art over the whole JS-parity feature set: board
tokens (neutral art + team ring), battle portraits (neutral art + team frame,
mirrored defender), bespoke archons per faction; attack FX and all M9/M10-audio
behavior intact. `_test_sprites` green; headless boot clean (textures load); no
runtime errors. Visual readability confirmed windowed at both scales. **M10
complete → the Godot port has real art + audio over full parity.** ROADMAP2
Phases 2–8 are next, each with its own post-parity spec.
