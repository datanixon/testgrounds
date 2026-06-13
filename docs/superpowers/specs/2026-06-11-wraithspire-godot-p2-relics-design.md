# Wraithspire Godot — ROADMAP2 Phase 2: Relics — design

Date: 2026-06-11
Branch: `godot-p2-relics`
Milestone: ROADMAP2 Phase 2 (first post-parity content milestone). The M1–M10
port reached full JS parity + real art/audio; Phases 2–8 are NEW content,
re-planned as Godot work (the JS reference stopped at Phase 1). This is Phase 2 =
**Relics**.
References: `ROADMAP2.md` Phase 2 (2.1/2.2); `docs/superpowers/specs/2026-06-10-
wraithspire-v2-design.md` "Phase 2 — Relics" (the relic table + mechanics).

## Goal

Add battlefield relics: items that spawn on the map, get auto-equipped when a unit
ends its move on them (one slot, swap drops the old), and modify the bearer through
the existing pure stat functions. Six passive relics + three consumables. Effects
flow through `compute_damage` / `effective_move` / range / heal reads so the
forecast and AI inherit them for free (the design principle from Phase 1).

## Scope decisions (locked with user, 2026-06-11)

- **Relic set:** adopt the v2 spec table as-is.
  - Passive (6): `atk_charm` (+2 ATK), `vital` (+4 max HP), `swift` (+1 MOV),
    `farsight` (+1 RNG, cap 2), `regenring` (regen 2/turn), `thorncharm` (counter +2).
  - Consumable (3): `phoenix` (revive once at 1 HP, then consumed), `warhorn`
    (next attack ×1.5, then consumed), `ley_crystal` (master-only, +6 MP on
    pickup, never equipped).
  - `veilstone` (+1 vision under fog) is **deferred to Phase 3** (needs the fog
    system).
- **Spawning:** every MAPS skirmish def + every CAMPAIGN mission def gains a
  `relics` count; map-gen places that many on plain tiles (min-distance, roughly
  symmetric, like towers).
- **Pickup:** auto-equip on move-end; a full slot drops the old relic back onto
  the tile (swap); no confirmation UI. Ley Crystal applies instantly (master only).
- **Glyph:** each relic tile shows that specific relic's glyph (player + AI see
  what it is).
- **Stat model:** dynamic read-time modifiers (no base-stat mutation), except a
  one-time HP top-up on equipping `vital`; drop re-clamps HP.

## Architecture

One new data file + one new pure helper module, threaded into the existing pure
stat functions, plus presentation (board glyph, card line) and the match-scene
pickup hook. Mirrors how weather/abilities were integrated in M4/M5.

### `data/relics.gd` (new — class `Relics`)

`RELICS` const dict keyed by relic id; each entry `{name, kind, glyph, color, ...effect}`:

| id | kind | effect | glyph |
|----|------|--------|-------|
| `atk_charm` | passive | `atk: 2` | "⚔" |
| `vital` | passive | `max_hp: 4` | "♥" |
| `swift` | passive | `move: 1` | "»" |
| `farsight` | passive | `range: 1` (capped to 2 total) | "◎" |
| `regenring` | passive | `regen: 2` | "✚" |
| `thorncharm` | passive | `counter: 2` | "✦" |
| `phoenix` | consumable | `revive: true` | "𝄞" |
| `warhorn` | consumable | `atk_mult: 1.5` | "♪" |
| `ley_crystal` | consumable | `master_only: true, mp: 6` | "✷" |

(Glyphs are single chars drawn procedurally; exact chars are tunable in the plan.)

Helpers (pure, static):
- `is_passive(id) -> bool`, `is_consumable(id) -> bool`
- `bonus(relic_id: String, key: String) -> Variant` — the effect value for `key`
  (e.g. `bonus("atk_charm","atk") == 2`), or 0/absent default. Used by the stat fns.
- `POOL` — the ids eligible to spawn on the map (all 9; map-gen rolls from it).

### Unit slot

`unit["relic"]` = relic id `String` or `""`. `core/units.gd make_unit` /
`make_master` default `""`. The slot rides the whole-unit serialize (save/load)
for free. Consumable lifecycle:
- `warhorn`: equipped, cleared after the bearer's next `resolve_attack` swing.
- `phoenix`: equipped, cleared when it triggers (a swing would kill the bearer).
- `ley_crystal`: never equipped — applied at pickup, tile cleared.

### Stat integration (dynamic reads — pure fns gain relic awareness)

- **`combat.gd compute_damage`** — attacker `atk_charm` adds +2 to power; `warhorn`
  multiplies the computed base ×1.5 (after other modifiers). Forecast + AI inherit.
- **`combat.gd resolve_attack`** — the counter-damage calc adds the defender's
  `thorncharm` +2; after the attacker's swing, if attacker had `warhorn`, clear it.
- **`game_state.gd effective_move`** — `swift` adds +1 (alongside slow/weather).
- **range** — `compute_attack_targets` / pathfinding range reads
  `effective_range(unit) = min(2, base_range + farsight_bonus)` (cap 2 total).
- **`effective_max_hp(unit)`** (new, on `GameState` or a shared helper) =
  `base max_hp + vital_bonus`; consumed by the HP bar (`unit_node`), HP fraction,
  battle HP bars, and all heal clamps (`end_turn` tower/castle heal, `healPulse`).
- **`game_state.gd end_turn` heal tick** — a unit with `regenring` heals +2 (capped
  to `effective_max_hp`); this is the writer the `regen` mechanic always lacked.

### Consumables — hook points

- **Phoenix** (`resolve_attack`): when a swing (primary or counter) would set a
  Phoenix-bearer's hp ≤ 0, instead set hp = 1 and clear `relic` (one-shot). Emits a
  battle-log note (and a float/SFX at the presentation layer). The win-condition
  check sees the survivor.
- **Warhorn**: handled in `compute_damage` (×1.5) + cleared post-swing in
  `resolve_attack`.
- **Ley Crystal** (pickup, master only): `mp = min(max_mp, mp + 6)`; tile removed.

### Map-gen spawn — `core/map_gen.gd`

`generate(seed, def)` reads `def.get("relics", 0)` and places that many relic tiles
after towers: plain tiles only, ≥ a min hex-distance from castles, towers, and other
relics, mirrored across the board center for symmetry (same discipline as tower
placement). Each placed tile rolls a relic id from `Relics.POOL` via the seeded
`rng`. Result stored as `map["relics"] = Array[Dictionary]` of `{q, r, relic}`.
Determinism: same seed+def → same relic layout (harness-asserted).

### Pickup — `scenes/match/match_scene.gd`

After a human move commits onto a tile (the existing slide → menu path) and after
each AI move, check `map["relics"]` for the unit's `(q,r)`:
- If the tile relic is `ley_crystal`: master only → apply +6 MP, remove the tile;
  non-master → leave it (no pickup).
- Else: if the unit already holds a relic, push the old id back onto the tile
  (swap); set `unit["relic"]` = the tile's relic; remove/replace the tile entry.
  `vital` equip tops up `hp = min(effective_max_hp, hp + 4)`.
A pure `core/relic_pickup.gd` (or a static on `Relics`) computes the
equip/swap/Ley outcome (`apply_pickup(state, unit, tile) -> {...}`) so it's
harness-testable; `match_scene` calls it + plays SFX/float.

### Presentation

- **Board glyph** — `scenes/board/board.gd` (or a small relics layer) draws each
  `map["relics"]` tile: a colored gem diamond + the relic's glyph char, sized like
  terrain detail. Picked-up relics disappear; swapped-out relics appear.
- **Info card** — `scenes/hud/info_card.gd` gains a relic line (name) when the
  selected unit holds one.
- **Pickup feedback** — `Audio.beep` + a log/banner line on equip; `vital` HP
  top-up reflected in the bar.

### AI — `core/ai.gd`

Move-only scoring adds a small bonus when a candidate end-tile is an un-owned relic
tile (and a smaller bonus for being nearer one), so the AI drifts toward relics
without new decision logic. Relic stat effects already flow through the scored
`compute_damage`/reach, so kill/attack/retreat scoring inherits them automatically.
Determinism preserved (normal/hard draw zero rng).

### Save — `core/save_game.gd`

`unit["relic"]` already serializes with the unit. Add `map["relics"]` to the blob
(`to_dict` serializes the `{q,r,relic}` list; `from_dict` restores it + defaults
missing → `[]` for old blobs). The save blob version note bumps conceptually to
"v2 fields" but the loader stays tolerant (defaults), matching the existing
`from_dict` discipline.

## Testing

Harness (`pwsh -File godot/tests/run_tests.ps1`, `== N passed, 0 failed ==`):
- **`_test_relics_data`** — table shape; `bonus` accessor returns the right values;
  `is_passive`/`is_consumable` split; POOL membership.
- **combat** — `compute_damage` with `atk_charm` (+2), `warhorn` (×1.5),
  `thorncharm` counter (+2): assert exact resulting numbers vs the no-relic baseline.
- **`effective_move`/`effective_range`/`effective_max_hp`** with relics: assert the
  deltas + the range cap-at-2 + move stacking with slow/weather.
- **Phoenix** — a lethal `resolve_attack` on a Phoenix-bearer leaves hp=1, clears
  the relic, and the bearer survives the win check; a second lethal hit kills.
- **Regenring** — `end_turn` heals the bearer +2 (capped at effective_max_hp).
- **map-gen** — `def.relics = N` → exactly N relic tiles, all on plain terrain,
  none on castle/tower/another relic, deterministic for a fixed seed.
- **pickup** — `apply_pickup`: equip into empty slot; swap drops old onto tile;
  Ley Crystal master-only (master applies MP, non-master no-op); vital HP top-up.
- **save** — `to_dict`→`from_dict` preserves `map["relics"]` + `unit["relic"]`;
  old blob (no relics key) defaults to `[]`.

**Headless-boot gate** after any scene/`main` change (board glyph, info_card,
match_scene pickup): `godot --headless --path godot --quit-after 30` clean.

**Visual/manual** (windowed): relic glyphs show on the board; ending a move on one
equips it (card line updates, SFX); swapping drops the old onto the tile; Phoenix
saves a unit once; the AI walks onto relics.

## Accepted divergences / notes

- Relic glyphs are procedural (colored gem + glyph char) — no relic art this phase.
- `effective_max_hp` is a new dynamic-stat seam; all HP reads/clamps must route
  through it (the plan enumerates the call sites).
- Veilstone deferred to Phase 3 (fog).
- Pickup is auto (no UI), per the v2 spec.
- Warhorn/Phoenix consume on use; Ley Crystal consumes on pickup — the slot is
  empty afterward.

## Success criteria

Relics spawn on every map, show their glyph, auto-equip on move-end (swap drops the
old), and modify the bearer through the existing stat reads — so the hover forecast
and the AI both account for them with no bespoke logic. The three consumables fire
(Phoenix revive, Warhorn burst, Ley Crystal MP). Save/resume preserves relics.
Harness green (combat/stat/pickup/spawn/save parity); headless boot clean; behavior
confirmed windowed. Closes ROADMAP2 Phase 2; Phase 3 (fog) is next, with its own spec.
