# Wraithspire — Sprite Filename Manifest (M10 Art)

Companion to the art brief (`2026-06-10-wraithspire-art-brief.md`). Maps each
roster entry to the engine's `sprite` id and the exact asset filenames, so
generated PNGs drop straight into `godot/assets/sprites/` and the M10-art
integration is mechanical.

## Why filenames key on `sprite` id (not display name or type_key)

The battle renderer (`godot/scenes/battle/battle_sprites.gd`) and the board-token
renderer branch on each unit's **`sprite`** field (`_draw_<sprite>` functions),
NOT its `type_key` or display name. For the original 8 monsters the `sprite` id
differs from the type_key (e.g. type_key `cinderling` → sprite `imp`). So assets
are named by `sprite` id — the integration loads
`res://assets/sprites/<sprite>_<token|battle>.png` and assigns by the unit's
`sprite` value directly.

## Conventions

- **Two files per creature:** `<sprite>_token.png` (512×512, board) and
  `<sprite>_battle.png` (1024×1024, battle portrait), per the art brief specs.
- **Directory:** `godot/assets/sprites/`
- **Archons** are bespoke per-faction: sprite id `archon`, two variants keyed by
  owner (0 = AZURE, 1 = CRIMSON) → `archon_azure_*` / `archon_crimson_*`. The
  battle renderer's archon branch already splits on `unit.owner`.
- 22 creatures (12 base + 8 evolved + 2 archons) × 2 deliverables = **44 PNGs.**

## Base monsters (12)

| Roster name | Element | type_key | sprite id | Token file | Battle file |
|-------------|---------|----------|-----------|-----------|-------------|
| Cinderling | pyro | `cinderling` | `imp` | `imp_token.png` | `imp_battle.png` |
| Pyrowyrm | pyro | `pyrowyrm` | `wyrm` | `wyrm_token.png` | `wyrm_battle.png` |
| Tidekin | hydro | `tidekin` | `merfolk` | `merfolk_token.png` | `merfolk_battle.png` |
| Mistlevy | hydro | `mistleviath` | `serpent` | `serpent_token.png` | `serpent_battle.png` |
| Stoneward | terra | `stoneward` | `golem` | `golem_token.png` | `golem_battle.png` |
| Geomaul | terra | `geomaul` | `ogre` | `ogre_token.png` | `ogre_battle.png` |
| Galewisp | zephyr | `galewisp` | `wisp` | `wisp_token.png` | `wisp_battle.png` |
| Skyharrow | zephyr | `skyharrow` | `raptor` | `raptor_token.png` | `raptor_battle.png` |
| Hexwisp | arcane | `hexwisp` | `hexwisp` | `hexwisp_token.png` | `hexwisp_battle.png` |
| Runeward | arcane | `runeward` | `runeward` | `runeward_token.png` | `runeward_battle.png` |
| Frostmaw | hydro | `frostmaw` | `frostmaw` | `frostmaw_token.png` | `frostmaw_battle.png` |
| Duneskink | terra | `duneskink` | `duneskink` | `duneskink_token.png` | `duneskink_battle.png` |

## Evolved forms (8) — sprite id == type_key

| Roster name | Element | type_key / sprite id | Token file | Battle file |
|-------------|---------|----------------------|-----------|-------------|
| Infernite | pyro | `infernite` | `infernite_token.png` | `infernite_battle.png` |
| Emberdrake | pyro | `emberdrake` | `emberdrake_token.png` | `emberdrake_battle.png` |
| Tidelord | hydro | `tidelord` | `tidelord_token.png` | `tidelord_battle.png` |
| Leviathan | hydro | `leviathan` | `leviathan_token.png` | `leviathan_battle.png` |
| Colossus | terra | `colossus` | `colossus_token.png` | `colossus_battle.png` |
| Earthbreaker | terra | `earthbreaker` | `earthbreaker_token.png` | `earthbreaker_battle.png` |
| Stormwisp | zephyr | `stormwisp` | `stormwisp_token.png` | `stormwisp_battle.png` |
| Skytyrant | zephyr | `skytyrant` | `skytyrant_token.png` | `skytyrant_battle.png` |

## Archons (2) — bespoke per-faction, sprite id `archon`

| Roster name | Faction (owner) | Token file | Battle file |
|-------------|-----------------|-----------|-------------|
| AZURE Archon | 0 (AZURE) | `archon_azure_token.png` | `archon_azure_battle.png` |
| CRIMSON Archon | 1 (CRIMSON) | `archon_crimson_token.png` | `archon_crimson_battle.png` |

## Full file checklist (44)

Board tokens (22): `imp_token` `wyrm_token` `merfolk_token` `serpent_token`
`golem_token` `ogre_token` `wisp_token` `raptor_token` `hexwisp_token`
`runeward_token` `frostmaw_token` `duneskink_token` `infernite_token`
`emberdrake_token` `tidelord_token` `leviathan_token` `colossus_token`
`earthbreaker_token` `stormwisp_token` `skytyrant_token` `archon_azure_token`
`archon_crimson_token`

Battle portraits (22): same stems with `_battle` instead of `_token`.

All `.png`, transparent, in `godot/assets/sprites/`.

## Integration note (for the M10-art milestone)

Real sprites swap in behind the EXISTING signatures — `BattleSprites.draw_unit`
already takes a `view` dict carrying `sprite`/`owner`; replace the procedural
`_draw_<sprite>` bodies with a `Sprite2D`/texture draw keyed on
`view["sprite"]` (+ `view["owner"]` for the archon). The board token renderer is
swapped the same way. Team identity stays engine-side (colored base-ring on the
board, colored frame in battle), so the neutral monster art serves both factions;
only the archon ships two faction variants. The first 8-image comparison batch
from the art brief covers `imp`, `raptor`, `golem`, and `archon_azure`.
