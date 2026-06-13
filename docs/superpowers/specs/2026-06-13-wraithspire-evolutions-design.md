# Wraithspire — Four New Evolutions (ROADMAP2 Phase 4.1) — design

Date: 2026-06-13. Branch: `godot-p4-1-evolutions` (off `main`). Second slice of the
Phase 4 "content wave". Completes the "every base monster evolves" rule by adding
evolved forms for the four newest bases. Godot port; the JS build at repo root is the
frozen reference and is **not** touched.

## Goal

Give `hexwisp` / `runeward` / `frostmaw` / `duneskink` evolved terminal-tier forms,
matching how the original 8 bases evolve. This is mostly a data-table extension plus
test coverage; the evolution *mechanic* (`Units.evolve_unit`, level-4-on-owned-spire)
already reads `evolves_to` and needs no change.

## Decision (locked): art split — data now, sprites later

`Sprites.token/battle(id)` resolves `res://assets/sprites/<stem>_<token|battle>.png`
and **degrades gracefully** on a miss (returns null; `unit_node` draws the engine
base-disc + HP bar, `battle_sprites` draws the team glow + shadow — no crash). So the
data half ships first and is fully playable; the 8 new PNGs (token + battle × 4) are
generated through the user's image pipeline afterward and dropped in. A ready-to-paste
generation prompt is in the appendix.

## The four evolved forms

Stats mirror the existing evolved tier (keep move/range/flying/element/attack/ability;
+~8–14 HP, +4 power, +1–2 def, cost ~roughly doubled). New sprite stem = the evolved
form's own id (no PNG yet — see the test note).

| id | name | element | max_hp | move | range | power | def | cost | flying | sprite | attack | ability |
|---|---|---|---|---|---|---|---|---|---|---|---|---|
| `hexlord` | Hexlord | arcane | 19 | 5 | 2 | 9 | 2 | 20 | true | `hexlord` | bolt | blink |
| `sigilwarden` | Sigilwarden | arcane | 38 | 2 | 1 | 10 | 7 | 30 | false | `sigilwarden` | melee | ward |
| `glaciamaw` | Glaciamaw | hydro | 40 | 3 | 1 | 14 | 5 | 34 | false | `glaciamaw` | melee | frostBite |
| `dunestalker` | Dunestalker | terra | 23 | 5 | 1 | 10 | 3 | 16 | false | `dunestalker` | melee | skitter |

Wire `evolves_to` on the four bases: `hexwisp→hexlord`, `runeward→sigilwarden`,
`frostmaw→glaciamaw`, `duneskink→dunestalker`. Each evolved entry carries
`"evolved": true` (terminal tier; cd-1 on the ability, like the existing evolved forms).

## Architecture

### `data/unit_types.gd`
- Add the four evolved entries to `UNIT_TYPES` (after the existing evolved block).
- Add `"evolves_to": "<id>"` to each of the four base entries (`hexwisp`, `runeward`,
  `frostmaw`, `duneskink`).
- `SUMMON_LIST` is **unchanged** (12) — evolved forms are not directly summonable; they
  arise only through evolution. (AI summons from `SUMMON_LIST`, so it never summons the
  new evolved forms; evolution happens in `end_turn`'s `try_evolve`.)

### Evolution mechanic — no change
`Units.evolve_unit` (`core/units.gd`) reads `base.evolves_to`, swaps `type_key`, and
absorbs level growth into the evolved base stats; `try_evolve` gates on level 4 + an
owned tower/castle + `not evolved`. Adding the data is sufficient. `Abilities.ability_for`
already shaves cd by 1 when `evolved` (the new forms inherit that).

### Sprites — id-based, no code change
`core/sprites.gd` resolves by the unit's `sprite` id. The four new stems just won't
resolve until their PNGs exist. `unit_node` / `battle_sprites` already handle a null
texture. No change to either renderer.

## Testing (harness-first)

- `_test_unit_types`: `UNIT_TYPES.size()` 20 → **24**; the four evolved entries exist
  with `evolved == true` and representative stats; `evolves_to` is set on the four bases
  (e.g. `hexwisp.evolves_to == "hexlord"`); `SUMMON_LIST.size() == 12` (unchanged, and
  contains none of the new evolved ids).
- Evolution behavior (extend `_test_leveling` or a new `_test_new_evolutions`): a level-4
  `hexwisp` on an owned tower evolves to `hexlord`, absorbing level growth (mirrors the
  existing cinderling→infernite assertion); confirm `evolved == true`, the new
  `type_key`/stats, and full-restore HP. Spot-check one more line (e.g. `duneskink →
  dunestalker`).
- **`_test_sprites` (line ~1387) currently asserts every `UNIT_TYPES` sprite id loads** —
  the four new artless stems would fail it. Add a `PENDING_ART` skip-set
  (`["hexlord", "sigilwarden", "glaciamaw", "dunestalker"]`) and `continue` past those
  ids. Strictness is preserved for every stem that *should* have art. The later art task
  removes the skip set, at which point `_test_sprites` covers the new sprites.

Headless boot gate after any change that could touch a scene path: not strictly needed
here (data-only + tests), but run it once at the end. The visual result (engine disc for
the new evolved forms until art lands) is confirmed in the windowed pass.

## Deferred: the art task (own follow-up, needs the generated PNGs)

Once the user generates the 8 PNGs (per the appendix) and drops them in
`godot/assets/sprites/` as `hexlord_token.png` / `hexlord_battle.png` / … :
1. Run the Godot import pass so `.import` sidecars exist:
   `godot --headless --import --path godot` (or `--editor --quit`). (Gotcha: `load()`
   won't resolve a PNG until its `.import` sidecar is generated; the `.godot/imported/`
   cache is git-ignored, and `godot/.gitignore` whitelists `!assets/sprites/*.png`.)
2. Remove the four ids from `PENDING_ART` in `_test_sprites` so the suite now asserts
   they load.
3. Commit the PNGs + `.import` sidecars + the test change. Windowed-verify the board
   tokens + battle portraits.

This task is **not** executed in this slice — it lands when the assets exist.

## Out of scope / accepted divergences

- No new abilities — each evolved form keeps its base's ability (same as the existing
  evolved tier).
- Evolved forms remain non-summonable (evolution-only), so no `SUMMON_LIST` / AI-summon
  changes.
- The four new sprites are art-pending; until the PNGs land, the new evolved forms render
  with the engine base-disc only (graceful).

## Build order (for the plan)

1. `data/unit_types.gd`: four evolved entries + `evolves_to` on the four bases.
2. `_test_unit_types` updates (size 24, entries, wiring) + evolution-behavior test.
3. `_test_sprites` `PENDING_ART` skip set.
4. Whole-slice review + windowed pass. (Art generation + import = deferred follow-up.)

---

## Appendix — sprite generation prompt (paste into the image-gen agent)

Use alongside `docs/superpowers/specs/2026-06-10-wraithspire-art-brief.md` (same STYLE
BIBLE, TECHNICAL SPECS, ELEMENT PALETTE, and per-creature deliverables: 512² board token
+ 1024² battle portrait, transparent, faction-neutral, element-colored, no baked shadow).
Generate these four **evolved forms** — "bigger, more ornate version of the base, clearly
the same lineage" — using your locked style anchor:

```
Hexlord     | arcane (#b078c8) | (Hexwisp+) greater arcane construct — a large floating
              runic core wreathed in orbiting glyph-rings, several arcane eyes, crackling
              purple energy arcs | FLYING, bolt
Sigilwarden | arcane (#b078c8) | (Runeward+) towering rune-armored sentinel, great glowing
              sigil-shield, heavy runic plate, commanding defensive bulk | melee defender
Glaciamaw   | hydro  (#5aa8d8) | (Frostmaw+) colossal glacial beast, jagged ice-crystal
              mane and spine, longer icicle fangs, cold frost aura (cooler white-blue) | melee
Dunestalker | terra  (#9a7a4a) | (Duneskink+) larger sand-scaled predator lizard, ridged
              frill, lashing tail, coiled to spring (warm tan) | fast melee
```

Deliver 8 files named exactly: `hexlord_token.png`, `hexlord_battle.png`,
`sigilwarden_token.png`, `sigilwarden_battle.png`, `glaciamaw_token.png`,
`glaciamaw_battle.png`, `dunestalker_token.png`, `dunestalker_battle.png`.
