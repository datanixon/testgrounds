# Wraithspire — Bosses + Maps (ROADMAP2 Phase 4.3) — design

Date: 2026-06-13. Branch: `godot-p4-3-bosses-maps` (off `main`). Third slice of the
Phase 4 "content wave". Adds two new skirmish maps (one fog-default) and two boss
monsters. Godot port; the JS build at repo root is the frozen reference and is **not**
touched.

## Goal

Two new skirmish maps (6 total, one fog-flagged by default — the first fog-default
*skirmish* map, deferred from Phase 3) and two boss monsters: big, non-summonable units
that arise only as pre-placed enemies in missions/gauntlet. Pure data + tests; the boss
sprites are art-pending (data-now/art-later, like 4.1).

## Decisions (locked)

- **Bosses reuse the existing ability set** (a fearsome stat block + an existing signature
  ability) — no new combat code; 4.3 stays a content slice.
- **Demo a boss in a campaign mission** (`ai_summons`) so it's playable in-game now.

## The two maps (`data/maps.gd`, MAPS index 4–5)

The title map selector iterates `Maps.MAPS`, so new entries appear automatically.

```gdscript
{"key": "mistveil", "name": "Mistveil Hollow", "desc": "Fog-shrouded woods.",
 "cols": 15, "rows": 12, "seed": -1, "mountains": 2, "lakes": 3, "forests": 34, "hills": 10,
 "towers": 5, "relics": 2, "fog": true},
{"key": "ashfall", "name": "Ashfall Basin", "desc": "Volcanic crags, ash winds.",
 "cols": 15, "rows": 11, "seed": -1, "mountains": 8, "lakes": 1, "forests": 6, "hills": 22,
 "towers": 4, "weather_table": ["heat", "heat", "gale", "clear"], "relics": 2},
```

- **Mistveil Hollow** — forests-heavy, `fog: true` (skirmish fog without touching the title
  toggle; the toggle still ORs in for the other maps). This exercises the fog system from a
  skirmish, which Phase 3 only did via campaign mission 4.
- **Ashfall Basin** — mountains/hills-heavy with a heat-skewed weather table (like the
  existing `crags`/`tides` weather maps).

## The two bosses (`data/unit_types.gd`, new `UNIT_TYPES` entries)

Top-tier stat blocks (above every evolved form), **not** in `SUMMON_LIST` (non-summonable —
they only appear pre-placed), each reusing an existing ability. A `"boss": true` data marker
(used later by Phase 6 records / Phase 7 gauntlet; no special rendering in this slice). New
sprite stem = the boss id (art-pending).

| id | name | element | max_hp | move | range | power | def | cost | flying | sprite | attack | ability | boss |
|---|---|---|---|---|---|---|---|---|---|---|---|---|---|
| `pyre_colossus` | Pyre Colossus | pyro | 52 | 2 | 1 | 16 | 6 | 40 | false | `pyre_colossus` | melee | quake | true |
| `storm_tyrant` | Storm Tyrant | zephyr | 40 | 4 | 2 | 14 | 4 | 38 | true | `storm_tyrant` | dive | diveMark | true |

- `Pyre Colossus` — a ground melee juggernaut whose `quake` (4 dmg to all adjacent enemies,
  no counter) punishes clustering; huge HP/power/def.
- `Storm Tyrant` — a flying ranged terror; `diveMark` marks a target (×1.2 incoming) and its
  range-2 dives let it kite. `attack: "dive"` reuses the existing battle FX flavor.
- `cost` is set high for completeness (army-value/gauntlet-draft scoring) but is inert for
  placement — bosses are spawned directly (no MP spent), never summoned.
- No `evolves_to`/`evolved` — bosses are terminal and get full ability cooldowns.

## Boss placement / demo (`data/campaign.gd`)

Bosses are pre-placed via the existing `ai_summons` field (which `new_campaign` spawns near
the AI master through `find_summon_slot` — no MP cost). Add `pyre_colossus` to mission 4
"The Wraithspire" `ai_summons` (currently `["geomaul", "skyharrow"]`) so the finale fields a
boss. Skirmish maps never place bosses (bosses aren't in `SUMMON_LIST`, and the AI summon
economy only draws from `SUMMON_LIST`).

## Architecture notes — why no new code

- **Non-summonable**: achieved by absence from `SUMMON_LIST` (same mechanism as evolved
  forms). The AI's `run_summons` only iterates `SUMMON_LIST`, so it never fields a boss on
  its own; bosses come only from `ai_summons` pre-placement.
- **Abilities**: `Abilities.ability_for` reads the unit's `ability` key and the generic
  resolvers handle it — `quake` via `resolve_instant`, `diveMark` via `resolve_attack`'s
  status payload. No new ability entries or resolver branches.
- **Rendering**: `Sprites` resolves by the unit's `sprite` id and degrades gracefully on a
  missing PNG (engine disc + HP bar). No renderer change. The `boss` flag is inert here.
- **Maps**: `MapGen.generate` reads the terrain-count keys it already understands; `fog` /
  `weather_table` are existing optional keys. The title selector and `SettingsStore`
  map-index clamp both read `Maps.MAPS.size()` dynamically.

## Testing (harness-first)

- `_test_data`: `Maps.MAPS.size()` 4 → **6**; the two new keys (`mistveil`, `ashfall`);
  `mistveil.fog == true`; `ashfall.weather_table` present.
- New `_test_bosses`: `UNIT_TYPES.size()` 24 → **26**; both boss entries exist with
  `boss == true`, the listed stats (e.g. `pyre_colossus.power == 16`, `storm_tyrant.flying`),
  and a reused ability key that exists in `Abilities.ABILITIES`; `SUMMON_LIST.size() == 12`
  and contains neither boss id; mission 4 `ai_summons` contains `pyre_colossus`; a
  `new_campaign(CAMPAIGN[3], 3)` actually spawns a `pyre_colossus` for owner 1.
- `_test_sprites`: append `pyre_colossus`, `storm_tyrant` to the `pending_art` skip-set
  (joins the 4 evolution stems until the boss PNGs land).

Headless boot once at the end (data feeds scenes). Windowed/`--shot` confirms the new maps
appear in the title selector and a boss shows on the board (engine disc until art) —
`godot --path godot -- --shot mission2` analog for mission 4 can be added.

## Deferred: the art task (needs generated PNGs)

4 boss PNGs (`pyre_colossus_token/battle`, `storm_tyrant_token/battle`, 512²/1024²). When
they land in `godot/assets/sprites/`: run `godot --headless --import --path godot`, remove
the two ids from `pending_art`, commit PNGs + `.import` + test. Not executed in this slice.

## Out of scope / accepted divergences

- No new abilities or combat mechanics (bosses reuse the existing set).
- No special boss rendering (the `boss` flag is a data marker for later phases; no bigger
  token / "BOSS" label in this slice).
- Bosses are exercised only via mission 4's `ai_summons` demo; the full objective-driven
  boss missions are Phase 5.
- Boss sprites art-pending (engine disc until the 4 PNGs land).

## Build order (for the plan)

1. `_test_sprites` `pending_art` += the 2 boss stems (lands before the boss data, as in 4.1).
2. `data/maps.gd`: the 2 new maps + `_test_data` updates (size 6, keys, fog).
3. `data/unit_types.gd`: the 2 boss entries + `_test_bosses` (size 26, boss flag,
   non-summonable, stats, ability exists).
4. `data/campaign.gd`: `pyre_colossus` into mission 4 `ai_summons` + the campaign-spawn assert.
5. Whole-slice review + windowed/`--shot` pass. (Art generation + import = deferred.)

---

## Appendix — boss sprite generation prompt (paste into the image-gen agent)

Use with `docs/superpowers/specs/2026-06-10-wraithspire-art-brief.md` (same STYLE BIBLE,
TECHNICAL SPECS, ELEMENT PALETTE; 512² board token + 1024² battle portrait, transparent,
faction-neutral, element-colored, no baked shadow). These are **bosses** — bigger, more
fearsome and ornate than any base/evolved monster, clearly apex threats (not lineage of a
base). Use your locked style anchor:

```
Pyre Colossus | pyro  (#e07050) | a towering molten titan, cracked obsidian armor over a
                lava core, massive smoldering fists, horned head wreathed in flame; reads as
                an unstoppable juggernaut | heavy melee
Storm Tyrant  | zephyr (#c8c8d8) | a vast apex storm-raptor, lightning crackling across pale
                storm-feathered wings, talons bared mid-dive, eyes like white fire; reads as
                a flying terror | FLYING, diving attack
```

Deliver 4 files named exactly: `pyre_colossus_token.png`, `pyre_colossus_battle.png`,
`storm_tyrant_token.png`, `storm_tyrant_battle.png` → `godot/assets/sprites/`.
