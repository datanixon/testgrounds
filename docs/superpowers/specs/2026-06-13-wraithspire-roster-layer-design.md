# Wraithspire — Phase 5.1 Campaign Roster Layer (design)

Date: 2026-06-13. ROADMAP2 Phase 5 ("Persistent war campaign") slice 1 of 3.

## Goal

The persistence layer for a Fire-Emblem-style persistent campaign: veterans
carry their progression (level/XP/evolution/relic) between missions, deaths are
permanent, and a returning v1 player is seeded a small starting roster from their
prior campaign progress.

This slice is **pure data + storage only**. No UI, no live game wiring. The
pre-mission deploy screen, the AI opening-strength scaling, and the call sites
that stamp roster identity onto deployed units / invoke reconciliation after a
win all land in **Phase 5.2** (deploy screen). 5.1 ships a self-contained,
harness-tested module the way `core/vision.gd` and `core/objectives.gd` shipped
pure before their presentation wiring.

## Scope (5.1) vs deferred (5.2)

**In 5.1:**
- New module `core/roster_store.gd` (`class_name RosterStore extends RefCounted`).
- The roster data model + pure operations (snapshot, reconcile, migrate, edit).
- `user://` JSON persistence (the `campaign.v2` slot) + reset.
- Harness tests for every pure operation + the JSON round-trip.

**Deferred to 5.2 (NOT in this slice):**
- Deploy screen UI (veteran picker, slot caps).
- Stamping `roster_id` onto deployed units at match start.
- Calling `reconcile(...)` from `Session.on_match_won`.
- AI opening-strength scaling by roster value.
- Resetting the roster from the campaign screen (UI button; the store API
  exists in 5.1, the button is 5.2).
- Campaign extension to 8 missions (Phase 5.3).

## Architecture

One file, no dependencies on the live game beyond `core/units.gd` (for building
granted veterans through the same path the game uses). Modeled on the two
existing persistence modules:
- `SaveGame` — pure `to_dict`/`from_dict` round-trip + thin `user://` file I/O,
  with explicit JSON int→float re-coercion (GDScript 4 turns JSON numbers into
  floats on parse).
- `SettingsStore` — `defaults()` + a validating `merge()` that range/type-checks
  an untrusted saved blob.

`RosterStore` follows both: pure operations are unit-tested; file I/O is a thin
wrapper; loads validate and re-coerce.

### Storage

- File: `user://wraithspire_campaign.json` — the `campaign.v2` slot, separate
  from the per-match autosave (`user://wraithspire_save.json`).
- Blob shape: `{"v": 2, "roster": [<entry>, ...], "next_roster_id": <int>}`.
- Holds the **roster only**. Mission-unlock progress stays in
  `settings.campaign_progress` (already persisted, merged, and clamped by
  `SettingsStore`). **Deliberate divergence** from the v2 design's "roster +
  mission progress in one slot": progress already has a home, and duplicating it
  across two files invites drift. The migration *reads* `campaign_progress` to
  seed the grant; it does not move it.

### Roster entry (full snapshot)

A roster entry is a full snapshot of a veteran's persistent stats — the grown
numbers are stored verbatim (not recomputed on deploy):

```
{
  "roster_id": <int>,     # stable identity across missions (NOT the per-match unit id)
  "type_key": <String>,   # current form; evolution mutates this
  "name": <String>,
  "element": <String>,
  "sprite": <String>,
  "attack": <String>,
  "flying": <bool>,
  "evolved": <bool>,      # snapshot of the unit's evolved flag (drives the -1
                          # ability cooldown); carried verbatim, not re-derived
                          # from type_key — consistent with the full-snapshot rule
  "level": <int>,
  "xp": <int>,
  "max_hp": <int>,        # grown
  "power": <int>,         # grown
  "def": <int>,           # grown
  "move": <int>,
  "range": <int>,
  "relic": <String>,      # "" if none
}
```

Transient / per-match fields are NOT stored: `id`, `owner`, `q`, `r`, `hp`
(deploy resets to `max_hp`), `acted`, `cd`, `second_move`, `is_master`.
Masters are never roster members (HP resets between missions; the archon is
always present, not deployed).

### Pure API

- `new_roster() -> Dictionary` — `{"v": 2, "roster": [], "next_roster_id": 1}`.
- `entry_from_unit(unit: Dictionary, roster_id: int) -> Dictionary` — build a
  snapshot entry from a (living) unit, copying the carry fields above and
  stamping `roster_id`. Pure; does not mutate the unit.
- `add_entry(blob, unit) -> int` — snapshot `unit` with `blob["next_roster_id"]`,
  append it, bump `next_roster_id`, return the assigned id. Mutates `blob`.
- `remove_entry(blob, roster_id) -> bool` — drop the entry with that id; return
  whether one was removed.
- `clear(blob) -> void` — empty the roster (keeps `next_roster_id` monotonic).
- `reconcile(blob, living_units: Array, deployed_ids: Array) -> Dictionary` —
  the carry + permadeath core, called after a mission win (in 5.2). Rules,
  applied to a duplicate of `blob` (pure — returns a new blob):
  - For each `rid` in `deployed_ids`: if some unit in `living_units` carries
    `roster_id == rid`, **update** that entry from the unit (refresh
    level/xp/type_key/grown stats/relic); else the deployed veteran died →
    **remove** its entry (permadeath).
  - For each unit in `living_units` with **no** `roster_id` (a fresh summon that
    survived) → **add** a new entry.
  - Units in `living_units` whose `roster_id` is in `deployed_ids` are handled by
    the update branch (not double-added).
  - `living_units` is the caller's set of surviving player-0 **non-master**
    units; the master is never reconciled.
- `migrate(progress: int) -> Dictionary` — build a fresh roster (starting from
  `new_roster()`) granting **one veteran per cleared act** per the grant table
  below. `progress` is `campaign_progress` (count of cleared missions, 0–4).
  `progress <= 0` → empty roster.

### Migration grant

`progress` = number of cleared v1 acts. For each cleared act `i` (1-based,
`i <= progress`), grant the act's veteran at the act's level. Each veteran is
built through the game's own progression path so it is rule-consistent with a
naturally leveled unit:

1. `Units.make_unit(<temp id>, type_key, 0, 0, 0)`,
2. set `u["level"] = level`, `u["xp"] = 0` (start of that level),
3. if `level >= Units.EVOLVE_LEVEL` and the type has `evolves_to`: call
   `Units.evolve_unit(u)` — it reads `u["level"]` and sets the snapshot's stats
   to the evolved base + `(level-1)` growth (so do NOT also call
   `apply_level_growth` on this path); else call `Units.apply_level_growth(u)`
   `(level - 1)` times to grow the base form,
4. snapshot via `add_entry` (no relic).

(`apply_level_growth` bumps `max_hp/power/def` and full-heals but does not touch
`level`; `evolve_unit` recomputes stats from the evolved base + level bonus and
sets `evolved=true`. The two paths are mutually exclusive per the table.)

Grant table:

| Cleared act | `type_key` | Level | Resulting form |
|---|---|---|---|
| 1 — The Border Skirmish | `stoneward` | 2 | Stoneward (terra tank) |
| 2 — The Drowned Marches | `tidekin`   | 3 | Tidekin (hydro) |
| 3 — The Emberfall Passes | `geomaul`  | 4 | Earthbreaker (geomaul evolved) |
| 4 — The Wraithspire | `hexwisp`       | 5 | Hexlord (hexwisp evolved) |

So `progress = 2` → a level-2 Stoneward + a level-3 Tidekin. New v2 players
(`progress = 0`) start with an empty roster and earn veterans by playing.

### I/O (thin; not unit-tested — the pure ops above are)

- `load_or_init(progress: int) -> Dictionary` — if the file exists and parses to
  a valid `v:2` blob, load it (validate + re-coerce, fall back to
  `migrate(progress)` on a corrupt/missing-key blob); else `migrate(progress)`,
  save it, and return it. The file's presence is the "already migrated" gate —
  migration runs exactly once, on first access.
- `save(blob) -> void` — `JSON.stringify` to the slot path.
- `reset() -> void` — delete the slot file (next `load_or_init` re-migrates from
  current progress). The campaign-screen reset button (5.2) calls this.
- `probe() -> bool` — whether the slot file exists.
- A private `_validate(blob, progress)` / re-coercion step mirrors `SaveGame`'s
  numeric int-coercion: every numeric entry field (`roster_id/level/xp/max_hp/
  power/def/move/range`) is `int(...)`-coerced after JSON parse; `next_roster_id`
  and `v` too. A blob failing validation falls back to `migrate(progress)`.

## Data flow

- **First campaign entry (5.2 will call):** `load_or_init(campaign_progress)` →
  roster (migrated once if absent).
- **Mission win (5.2 will call):** `reconcile(blob, survivors, deployed_ids)` →
  `save(new_blob)`.
- **Reset (5.2 UI):** `reset()`.

In 5.1 these are exercised only by the harness with synthetic units/blobs.

## Error handling

- Corrupt / non-dict / wrong-version blob on load → `migrate(progress)` (never
  crash; a returning player at worst re-receives their starter grant).
- `reconcile` tolerates units missing `roster_id` (treated as fresh) and ids in
  `deployed_ids` with no matching living unit (treated as dead).
- `migrate(progress)` clamps `progress` to `[0, 4]` defensively.
- All numeric fields int-coerced post-parse (the JSON-float gotcha).

## Testing

Harness `_test_roster_*` in `godot/tests/run_tests.gd` (preload `RosterStore`;
`_eq`/`_ok`). No file I/O in tests (pure ops only) — except a round-trip test
that stringifies + re-parses a blob in memory and asserts the re-coercion holds.

- `new_roster` shape (`v==2`, empty roster, `next_roster_id==1`).
- `entry_from_unit`: keeps level/xp/relic + grown `max_hp/power/def`; omits
  `q/r/id/owner/hp/acted/cd/second_move/is_master`; stamps `roster_id`; does not
  mutate the source unit.
- `add_entry` assigns sequential ids + bumps `next_roster_id`; `remove_entry`
  returns true/false correctly; `clear` empties roster but keeps `next_roster_id`.
- `reconcile`, all four cases in one scenario: a deployed veteran that lived
  (entry updated — e.g. level changed), a deployed veteran that died (entry
  culled), a fresh summon that lived (entry added), a fresh summon that died
  (nothing). Assert final roster size + that the survived-veteran entry reflects
  its new level and the dead veteran's id is gone. `blob` not mutated in place.
- `migrate`: `progress 0` → empty; `1` → [L2 stoneward]; `2` → [+L3 tidekin];
  `3` → third is evolved (`earthbreaker`, `level==4`); `4` → fourth is evolved
  (`hexlord`, `level==5`, `flying==true`). Assert each entry's `type_key`,
  `level`, and that the L≥4 grants are the evolved form.
- JSON round-trip: `JSON.parse_string(JSON.stringify(blob))` re-validated →
  numeric fields are ints, roster preserved.

`run_tests.gd` changes, so run the harness gate. No scene/autoload/`main.gd`
touched → headless boot not strictly required, but cheap; run it anyway.

## Gates

- `pwsh -File godot/tests/run_tests.ps1` → `== N passed, 0 failed ==`, EXIT 0
  (never `-ExecutionPolicy Bypass`). Expected delta ≈ +20.
- Headless boot (insurance): `godot --headless --path godot --quit-after 30 2>&1
  | Select-String "SCRIPT ERROR|Parse Error|Failed to load"` → no matches.

## Out of scope / accepted divergences

- Mission progress stays in `settings.campaign_progress`, not in the campaign.v2
  slot (single source of truth; see Storage).
- No retroactive *relics* on granted veterans (v1 never recorded them).
- Granted veteran types/levels are a fixed table (deterministic), not derived
  from which units the player actually used in v1 (that history doesn't exist).
- Master HP-reset-between-missions and the "archon still summons fresh units
  mid-battle" rule are unchanged in-engine; the roster never includes masters.
- Deploy, win-reconcile wiring, AI scaling, 8-mission campaign → Phases 5.2/5.3.

## Build order (for the plan)

1. `_test_roster_*` added to `run_tests.gd` first (TDD), referencing the
   `RosterStore` API below; expected to fail to compile until step 2.
2. `core/roster_store.gd`: `new_roster`/`entry_from_unit`/`add_entry`/
   `remove_entry`/`clear`/`reconcile`/`migrate` (pure) + grant table.
3. File I/O: `load_or_init`/`save`/`reset`/`probe` + `_validate`.
4. Run both gates.
