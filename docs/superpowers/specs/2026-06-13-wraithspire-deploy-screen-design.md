# Wraithspire — Phase 5.2 Deploy Screen + Survivors + AI Scaling (design)

Date: 2026-06-13. ROADMAP2 Phase 5 ("Persistent war campaign") slice 2 of 3.
Builds directly on Phase 5.1 (`core/roster_store.gd`, merged to main).

## Goal

Make the persistent roster player-visible and self-sustaining: before each
campaign mission the player deploys veterans from the roster (up to a
mission-defined cap); survivors of a won mission carry back into the roster
(permadeath for the fallen); and the AI's opening strength scales lightly with
the value of the army the player brought, so a fat veteran roster stays
challenged. This is the slice that turns the 5.1 data layer into a loop.

## Scope

**In 5.2:**
- New pure `core/deploy.gd` (`class_name Deploy`) — reconstruct units from roster
  entries, value the deployed army, place veterans, apply AI scaling. Harness-tested.
- New `scenes/deploy/deploy_scene.gd` (Control) — the pre-mission veteran picker.
- Router (`scenes/main.gd`) + `Session` wiring: `story → deploy → play`; commit
  deploys + AI scaling on Begin; reconcile survivors into the roster on a campaign win.
- `GameState.deployed_roster_ids` (saved) + `roster_id` riding deployed units
  through save (add to `save_game`'s int-coercion list).
- Optional `deploy_slots` on the 4 CAMPAIGN scenarios (default 3).
- A minimal "reset roster" affordance on the deploy screen.
- `--shot deploy` target + `_test_deploy_*` harness tests.

**Campaign-only.** Skirmish stays instant pick-and-play — no deploy step, no
roster. (Decision: the roster is a campaign-progression feature; a skirmish
deploy would have no persistent roster to draw from.)

**Out of scope (later):** missions 5–8 + their `deploy_slots`/objectives/lore
(Phase 5.3); unlock gating + records (Phase 6); cross-system balance of the
AI-scaling constants (Phase 8 — they ship tunable here).

## Flow

```
title → campaign(list) → story(intro) → deploy(veteran pick) → play → gameover
                                              │                          │
                                  Deploy.commit(state, picks)   on_match_won →
                                  (place vets + AI scaling)      reconcile survivors
```

`Session.start_campaign(index)` already builds the campaign GameState (masters,
`ai_summons`, base `ai_mp_bonus`). Change: it sets `screen = "deploy"` (was
`"play"`). The deploy scene reads the roster, the player picks, and on Begin the
router calls `Deploy.commit` then routes to `"play"`.

## Architecture

### `core/deploy.gd` (pure-ish; harness-tested)

Depends on `core/units.gd`-adjacent data only (no GameState preload cycle — it
takes `state` as a param, mirroring `core/ai.gd`). Preloads `UnitTypes` and the
global `AI` class (for `find_summon_slot`).

The deploy scene emits the chosen roster **entry dicts** (not just ids) so the
router can call `Deploy.commit` without re-reading the about-to-be-freed scene.

Constants (tunable; Phase 8 balances them):
```
const AI_SCALE_DIVISOR := 10   # roster value per +1 AI MP
const AI_SCALE_CAP := 12       # max extra AI MP from scaling
const DEFAULT_SLOTS := 3       # deploy cap when a scenario omits deploy_slots
```

- `unit_from_entry(entry: Dictionary, id: int, owner: int, q: int, r: int) -> Dictionary`
  — inverse of `RosterStore.entry_from_unit`. Build a full live unit dict from a
  roster entry: copy every carry field (`type_key`/`name`/`element`/`sprite`/
  `attack`/`relic`, `flying`/`evolved`, `level`/`xp`/`max_hp`/`power`/`def`/
  `move`/`range`), set `hp = max_hp`, `owner`, `q`, `r`, `id`, `acted = false`
  (ready to act turn 1 — deployed, not summoned-this-turn), `is_master = false`,
  `cd = 0`, `second_move = false`, and stamp `roster_id = entry["roster_id"]`.
- `roster_value(entries: Array) -> int` — Σ `UnitTypes.UNIT_TYPES[e["type_key"]]
  .get("cost", 0)` over the deployed entries (evolved forms cost more, so a
  stronger army scores higher). Bosses never appear in a roster, so no special-case.
- `ai_scale_mp(value: int) -> int` — `clampi(value / AI_SCALE_DIVISOR, 0, AI_SCALE_CAP)`.
- `slots_for(scenario: Dictionary) -> int` — `int(scenario.get("deploy_slots", DEFAULT_SLOTS))`.
- `commit(state, entries: Array) -> void` — the deploy action:
  1. For each entry: `var slot = AI.find_summon_slot(state, state.master_of(0))`;
     if `slot == null` stop (board full); else `var u = unit_from_entry(entry,
     state._new_id(), 0, slot.x, slot.y)`, `state.units.append(u)`, and record
     `entry["roster_id"]` in `state.deployed_roster_ids`.
     (Use `state.units.append` + `_new_id` directly, NOT `spawn_unit`, so the
     full-snapshot stats are preserved and the `summoned` stat is not bumped —
     deployed veterans are not "summoned this match".)
  2. AI scaling: `var extra = ai_scale_mp(roster_value(entries))`; `var m1 =
     state.master_of(1)`; if `m1 != null`: `m1["mp"] = clampi(m1["mp"] + extra,
     mini(4, m1["max_mp"]), m1["max_mp"])` (same clamp idiom as `new_campaign`).

`commit` mutates `state` but is deterministic and harness-testable (place known
entries on a known map, assert positions/ids/`deployed_roster_ids`/AI mp).

### `scenes/deploy/deploy_scene.gd` (Control; render-layer, `--shot`-validated)

Mirrors `campaign_scene.gd`: `extends Control`, `set_anchors_preset(TOP_LEFT)` +
`size = Vector2(CW, CH)` (the size-0-Control fix), procedural `_draw`, mouse in
`_gui_input`, keys in `_unhandled_input`. Signals `begin_mission(picked_entries:
Array)` (the chosen roster entry dicts) and `back`.

- `var session`, `var scenario: Dictionary` (the CAMPAIGN entry), `var roster:
  Array` (entry dicts from `RosterStore.load_or_init(session.campaign_progress)`),
  `var picked := {}` (roster_id → true), `var _reset_armed := false`.
- Header: mission name + "DEPLOY — choose up to N veterans" (N = `Deploy.slots_for`).
- One row per roster entry: name · `L<level>` · element · `HP/PWR/DEF` · relic
  glyph-or-dash; selected rows highlighted; a count "k / N" shown. Clicking a row
  toggles `picked` (ignored when adding beyond N).
- Empty roster → a single line "no veterans yet — summon fresh in battle"; Begin
  still works (deploys nothing).
- "BEGIN MISSION" hotspot → `begin_mission.emit(the roster entries whose
  roster_id is in `picked`)`.
- "↻ reset roster" hotspot, two-click confirm (`_reset_armed`): first click arms
  ("click again to confirm"), second click `RosterStore.reset()` + reload `roster`
  + clear `picked`. (Divergence from the v2 design's "campaign screen" placement —
  the deploy screen is where the roster is on display, so reset is contextual.)
- ESC → `back` (router returns to the campaign list).

### Router + Session wiring (`scenes/main.gd`, `core/session.gd`)

- `Session.start_campaign(index)`: set `screen = "deploy"` (was `"play"`). Keep
  everything else (builds `state`, sets fog). The router needs the scenario at
  deploy time, so store it: `Session` already has `story_index`; add nothing —
  the deploy scene reads `Campaign.CAMPAIGN[session.story_index]`.
- `main.gd._route()`: add a `"deploy"` case mounting `DeployScene` with
  `session` + `scenario = Campaign.CAMPAIGN[session.story_index]`, wiring
  `begin_mission` → `_on_deploy_begin`, `back` → `_on_to_title`-style return to
  the campaign list (`_go("campaign")`).
- `main.gd._on_begin_mission` (from story) is unchanged in spirit but now lands on
  the deploy screen because `start_campaign` sets `screen = "deploy"`.
- New `main.gd._on_deploy_begin(picked_entries: Array)`: `Deploy.commit(
  session.state, picked_entries)`, then `_go("play")`.
- `Session.on_match_won(winner)` — extend: BEFORE the existing progress-advance +
  save-delete, if `state != null && state.campaign_index >= 0 && winner == 0`:
  - `var blob = RosterStore.load_or_init(campaign_progress)`
  - gather survivors: `state.alive_units(0)` minus the master (`is_master`)
  - `blob = RosterStore.reconcile(blob, survivors, state.deployed_roster_ids)`
  - `RosterStore.save(blob)`
  Loss or skirmish → roster untouched (a failed mission is replayed; no permadeath
  on loss). Progress advance + autosave-delete stay as they are.

### State + save (`core/game_state.gd`, `core/save_game.gd`)

- `GameState.deployed_roster_ids: Array[int] = []` — set by `Deploy.commit`,
  read by `on_match_won`. SAVED (a mid-mission autosave must preserve it so a
  resumed-then-won mission still reconciles). `new_skirmish` initializes it `[]`.
- Deployed units carry a `roster_id` field; unit dicts serialize whole, so it
  rides along. Add `roster_id` and the `deployed_roster_ids` array to
  `save_game.to_dict`/`from_dict` with int re-coercion (the JSON float gotcha):
  serialize `deployed_roster_ids`; in `from_dict` coerce each to int, and add
  `roster_id` to the per-unit numeric-field coercion loop (guarded by `has`).

### Data (`data/campaign.gd`)

Add `"deploy_slots": <n>` to each of the 4 scenarios (e.g. 3 / 3 / 4 / 4 — the
later, harder missions allow a bigger committed army). Absent → `DEFAULT_SLOTS`
(3) via `Deploy.slots_for`, so this is additive and old saves are unaffected.

## Data flow

- **Enter mission:** story Begin → `start_campaign` (builds state, `screen=deploy`)
  → deploy scene loads `RosterStore.load_or_init(progress)`.
- **Begin mission:** `Deploy.commit(state, picks)` places veterans near the
  player master + bumps AI MP → `screen=play`.
- **Win:** `on_match_won` → `reconcile(roster, survivors, deployed_ids)` → save;
  then progress advance + autosave delete (existing).
- **Loss:** gameover, roster unchanged.

## Error handling

- Empty roster → deploy a nothing; `commit` places zero, AI scaling adds zero.
- Board too full for all picks → `commit` stops at the first `null` slot (rare on
  campaign maps; the slot cap is small).
- `find_summon_slot` returning `null` for the very first pick → no veterans placed
  (graceful; the player still has the master + can summon).
- `reconcile` already tolerates missing `roster_id`/absent-deployed ids (5.1).

## Testing

Harness `_test_deploy_*` (preload `Deploy`; build a small `new_campaign` or
`new_skirmish` state):
- `unit_from_entry`: every carry field copied; `hp == max_hp`; `acted == false`;
  `is_master == false`; `roster_id` stamped; given id/owner/q/r set.
- `roster_value`: sum of costs over mixed entries; evolved entry contributes the
  evolved cost.
- `ai_scale_mp`: 0 at value 0; linear under the cap; clamped at `AI_SCALE_CAP`.
- `slots_for`: scenario with `deploy_slots` returns it; without → `DEFAULT_SLOTS`.
- `commit`: places K veterans at distinct hexes near the player master; sets
  `state.deployed_roster_ids` to their ids; bumps the AI master mp by
  `ai_scale_mp(roster_value)` (clamped to `max_mp`); does NOT bump the `summoned`
  stat.
- on_match_won reconcile path: campaign win with deployed veterans (one survives
  leveled, one died) → roster reflects carry + permadeath; a skirmish win or a
  loss leaves the roster untouched. (Driven through `Session` with a synthetic
  state + a temp roster file, OR a pure call to the same `RosterStore.reconcile`
  the handler uses — prefer the pure assertion to avoid file I/O in tests.)
- save round-trip: a state with `deployed_roster_ids` + a unit carrying
  `roster_id` survives `to_dict`/`from_dict` with ints re-coerced.

Deploy/campaign scenes are render-layer (not harness-visible) — validate with a
new `--shot deploy` target in `scenes/main.gd._run_shot` (drive
`start_campaign(0)` so `screen=deploy`, capture, quit) plus a windowed pass.

## Gates

- `pwsh -File godot/tests/run_tests.ps1` → `== N passed, 0 failed ==`, EXIT 0
  (never `-ExecutionPolicy Bypass`). Expected delta ≈ +20.
- Headless boot (scenes + main.gd + autoload-free core change):
  `godot --headless --path godot --quit-after 30 2>&1 | Select-String "SCRIPT
  ERROR|Parse Error|Failed to load"` → no matches.
- `--shot deploy` then read the PNG: roster rows, selection highlight, slot
  counter, Begin + reset hotspots render in-frame.

## Out of scope / accepted divergences

- AI scaling is a single MP bump (no extra summons / no per-mission re-weighting)
  — the "light" option; constants tunable, balanced in Phase 8.
- Reset roster lives on the deploy screen, not the campaign screen (contextual).
- Deployed veterans spawn near the player master via `find_summon_slot`; no
  player-chosen placement (YAGNI for this slice).
- Master HP is NOT carried between missions (resets each mission) — unchanged;
  the master is never a roster member.
- Skirmish has no deploy step (campaign-only).

## Build order (for the plan)

1. `core/deploy.gd` — `unit_from_entry`/`roster_value`/`ai_scale_mp`/`slots_for`
   + `_test_deploy_*` (pure pieces first, TDD).
2. `GameState.deployed_roster_ids` + `Deploy.commit` + commit tests.
3. `save_game` — serialize `deployed_roster_ids` + `roster_id` coercion + round-trip test.
4. `scenes/deploy/deploy_scene.gd` + router `"deploy"` case + `start_campaign`
   screen change + `_on_deploy_begin`.
5. `Session.on_match_won` reconcile-on-campaign-win + `data/campaign.gd`
   `deploy_slots` + `--shot deploy`; both gates + shot.
