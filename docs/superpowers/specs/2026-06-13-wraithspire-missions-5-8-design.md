# Wraithspire — Phase 5.3 Missions 5–8 (Titans Awakened) design

Date: 2026-06-13. ROADMAP2 Phase 5 ("Persistent war campaign") slice 3 of 3 —
completes Phase 5. Builds on 5.1 (roster store) + 5.2 (deploy/survivors/scaling)
+ Phase 4 (objectives framework, bosses, fog, evolutions), all on main.

## Goal

Extend the campaign from 4 to 8 missions. The four new missions form a "titans
awakened" arc — escalating *hard* battles that exercise the content systems built
in Phase 4 (objectives, bosses, fog, weather skews) and lean on the veteran
roster the player has grown. Story: casting down the Crimson Archon (mission 4)
cracked the old seals; the elemental titans — the Pyre Colossus and the Storm
Tyrant — wake and march, ending in a dual-titan finale.

## Scope

**In 5.3:**
- 4 new scenario dicts in `data/campaign.gd` (`CAMPAIGN` 4 → 8): inline map defs +
  difficulty/`ai_mp_bonus`/`ai_summons`/`deploy_slots`/`intro` + objective flags.
- Two small `new_campaign` additions so the seize + protect objectives can be
  built from runtime placement (the only code): `seize_enemy_castle` and
  `protect_ally` scenario flags.
- `campaign_scene` layout shrink so 8 rows fit in-canvas + subtitle text update.
- `_test_*` coverage + `--shot campaign` validation.

**Out of scope / deferred:**
- Boss + evolved sprite **art** (engine-disc fallback until generated — unchanged).
- No per-mission custom map generation (reuse the generic deterministic generator
  via the existing map-def fields).
- The seize hex is not specially highlighted on the board; the enemy castle tile
  is the visible target and the lore intro points the player at it.
- Balance tuning of the new `ai_mp_bonus`/`deploy_slots` values → Phase 8.

## The objective wrinkles (why two `new_campaign` flags)

`Objectives.evaluate` shapes (from Phase 4.2): `{"kind":"survive","turns":int}`,
`{"kind":"seize","q":int,"r":int}`, `{"kind":"protect","unit_id":int}`,
`{"kind":"rout"}`. Two of these can't be fully expressed as static map-def data:

- **seize** needs a valid, known hex. Hardcoding `q,r` in a def is fragile (the
  map's axial offset is negative on lower rows — a literal coord can land
  off-board). Instead a `"seize_enemy_castle": true` flag makes `new_campaign`
  set the objective from `gs.map["castles"][1]` (player-1's castle) — always a
  real, occupiable cell (the enemy master spawns there), and a visible landmark.
- **protect** needs a real placed ally with a known id. A def can't predict the
  spawn id. Instead a `"protect_ally": "<type_key>"` flag makes `new_campaign`
  spawn that ally for player 0 near the player master and set the objective to its
  id. (Phase 4.2 left protect test-only for exactly this reason — 5.3 wires it.)

`rout` and `survive` need no special handling (plain `objective` in the map def).

## Architecture

### `core/game_state.gd` — `new_campaign` additions

Current `new_campaign(scenario, index)` builds the map via `new_skirmish` (which
copies `def.objective`), tags `campaign_index`/difficulty, applies `ai_mp_bonus`,
and pre-places `ai_summons` near the AI master. Add, AFTER the existing body,
before `return gs`:

```gdscript
	if scenario.get("seize_enemy_castle", false):
		var c1: Vector2i = gs.map["castles"][1]
		gs.objective = {"kind": "seize", "q": c1.x, "r": c1.y}
	var ally_key: String = scenario.get("protect_ally", "")
	if ally_key != "":
		var m0 = gs.master_of(0)
		if m0 != null:
			var slot = AILib.find_summon_slot(gs, m0)
			if slot != null:
				var ally := gs.spawn_unit(ally_key, 0, slot.x, slot.y)
				ally["acted"] = false
				gs.objective = {"kind": "protect", "unit_id": ally["id"]}
```

(`AILib` is the alias `new_campaign` already uses for the global `AI` class;
`find_summon_slot(state, master)` returns an open hex near `master` or null. The
protect/seize objective overrides whatever the map def carried — those missions
omit a static `objective`. The protect ally spawns ready to act so the player can
reposition it.)

`objective_progress` is set by `new_skirmish` to `{"start_turn": gs.turn}`; the
seize/protect overrides don't touch it (only `survive` reads it).

### `data/campaign.gd` — 4 new scenarios

Append four dicts to `CAMPAIGN` (indices 4–7). Each mirrors the existing
scenario shape: `name`, `difficulty`, `deploy_slots`, inline `map` (with
`key/name/desc/cols/rows/seed` + terrain counts + `towers`/`relics`, optional
`weather_table`/`fog`/`objective`), `ai_mp_bonus`, `ai_summons`, `intro` (array
of ~4 short lines), plus the new objective flags where used.

| # | key | name | objective | bosses (`ai_summons`) | flags | difficulty / ai_mp_bonus / deploy_slots |
|---|---|---|---|---|---|---|
| 5 | c5 | The First Tremor | `{"kind":"rout"}` (in map def) | `pyre_colossus`, `geomaul` | heat weather | hard / 10 / 5 |
| 6 | c6 | The Storm Crown | `seize_enemy_castle` | `storm_tyrant`, `skyharrow` | gale weather | hard / 12 / 5 |
| 7 | c7 | The Last Refuge | `protect_ally: "runeward"` | `geomaul`, `skyharrow` | `fog:true` | hard / 12 / 6 |
| 8 | c8 | The Titanfall | none (archon-kill finale) | `pyre_colossus`, `storm_tyrant` | mixed weather | hard / 14 / 6 |

Concrete map defs (deterministic seeds, distinct from the c1–c4 seeds):

```gdscript
	# Mission 5 — The First Tremor (rout; Pyre Colossus wakes)
	{"name": "The First Tremor", "difficulty": "hard", "deploy_slots": 5,
	 "map": {"key": "c5", "name": "The First Tremor", "desc": "", "cols": 15, "rows": 11, "seed": 52107,
	         "mountains": 8, "lakes": 1, "forests": 6, "hills": 22, "towers": 4, "relics": 2,
	         "weather_table": ["heat", "heat", "gale", "clear"], "objective": {"kind": "rout"}},
	 "ai_mp_bonus": 10, "ai_summons": ["pyre_colossus", "geomaul"],
	 "intro": ["The Wraithspire is yours — and that was the mistake.", "Its fall split the deep seals. Stone screams; the",
	           "Pyre Colossus drags itself into the light.", "Break its host. Leave nothing standing."]},

	# Mission 6 — The Storm Crown (seize the enemy spire; Storm Tyrant)
	{"name": "The Storm Crown", "difficulty": "hard", "deploy_slots": 5, "seize_enemy_castle": true,
	 "map": {"key": "c6", "name": "The Storm Crown", "desc": "", "cols": 15, "rows": 12, "seed": 60733,
	         "mountains": 4, "lakes": 2, "forests": 10, "hills": 16, "towers": 5, "relics": 2,
	         "weather_table": ["gale", "gale", "rain", "clear"]},
	 "ai_mp_bonus": 12, "ai_summons": ["storm_tyrant", "skyharrow"],
	 "intro": ["The Storm Tyrant roosts on the high spire and the", "winds answer it. While that crown stands, the sky",
	           "is theirs. Take the spire — seize the enemy seat", "and the storm has nowhere left to land."]},

	# Mission 7 — The Last Refuge (protect a wounded ally; fog)
	{"name": "The Last Refuge", "difficulty": "hard", "deploy_slots": 6, "protect_ally": "runeward",
	 "map": {"key": "c7", "name": "The Last Refuge", "desc": "", "cols": 15, "rows": 12, "seed": 71519,
	         "mountains": 2, "lakes": 3, "forests": 34, "hills": 10, "towers": 5, "relics": 2, "fog": true},
	 "ai_mp_bonus": 12, "ai_summons": ["geomaul", "skyharrow"],
	 "intro": ["The last free warden holds the misted wood, and", "everything the titans drove out shelters behind it.",
	           "Keep the warden alive. If the Runeward falls,", "the refuge falls — and the realm with it."]},

	# Mission 8 — The Titanfall (finale; both titans; archon-kill)
	{"name": "The Titanfall", "difficulty": "hard", "deploy_slots": 6,
	 "map": {"key": "c8", "name": "The Titanfall", "desc": "", "cols": 16, "rows": 13, "seed": 80021,
	         "mountains": 5, "lakes": 2, "forests": 18, "hills": 16, "towers": 6, "relics": 3,
	         "weather_table": ["heat", "gale", "rain", "clear"]},
	 "ai_mp_bonus": 14, "ai_summons": ["pyre_colossus", "storm_tyrant"],
	 "intro": ["Both titans, one field, and the thing that woke", "them waiting behind. There is no clever path left —",
	           "only your veterans and the ground you choose.", "End it. Put the seals back with their maker."]},
```

(Mission 7 has no `objective` in its map def — `new_campaign`'s `protect_ally`
builds it. Mission 6's def has no `objective` either — `seize_enemy_castle`
builds it. Missions 5 and 8 use plain data: 5 a static `rout`, 8 none.)

### `scenes/campaign/campaign_scene.gd` — fit 8 rows

The current `_row_rects` (`h 70`, `gap 16`, start `170 + i*86`) overflows the
800px canvas at 8 rows (row 8 bottom ≈ 842). Shrink to fit:

```gdscript
func _row_rects() -> Array:
	var w := 720.0; var h := 52.0; var gap := 10.0
	var x := (CW - w) / 2.0
	var out: Array = []
	for i in range(Campaign.CAMPAIGN.size()):
		out.append({"index": i, "r": Rect2(x, 150 + i * (h + gap), w, h)})
	return out
```

8 rows now span `150 .. 150 + 8*62 = 646` — clear of the footer at `CH-40`.
Adjust the two per-row text baselines in `_draw` from `y+28`/`y+48` to `y+22`/
`y+42` to sit inside the shorter 52px row. Update the subtitle string from
"— the fall of the crimson archon, in four battles —" to "— the fall of the
crimson archon, and the war of the titans after —". No other logic changes
(unlock-by-progress, click-to-pick, badges all already read `CAMPAIGN.size()`).

## Data flow

- Campaign list now shows 8 rows; mission `i` unlocks at `campaign_progress >= i`
  (unchanged). Clearing mission 7 unlocks 8; clearing 8 caps progress at 7
  (`Campaign.CAMPAIGN.size()-1`, the existing clamp).
- Picking a mission → story → deploy (5.2) → `new_campaign` builds the state,
  including the seize/protect objective for m6/m7 → play.
- Win/loss + roster reconcile unchanged (5.2).

## Error handling

- `seize_enemy_castle` reads `gs.map["castles"][1]` — every map has two castles
  (masters spawn there), so this is always valid.
- `protect_ally` guards `master_of(0)` and a null `find_summon_slot` (skips the
  spawn + objective if the board is impossibly full near the master — the mission
  then plays as a plain archon-kill rather than crashing).
- Boss/ally `type_key`s must exist in `UNIT_TYPES`; asserted by tests.

## Testing

Harness `_test_missions_5_8` (preload already has `Campaign`, `GameState`,
`UnitTypes`, `Objectives`, `AI`):
- `Campaign.CAMPAIGN.size() == 8`; each new scenario has `name`, `difficulty`,
  `deploy_slots`, a `map` with `seed`/`cols`/`rows`, and an `intro` of ≥1 line.
- Bosses referenced in `ai_summons` (`pyre_colossus`, `storm_tyrant`) exist in
  `UNIT_TYPES` with `boss == true`; the protect ally (`runeward`) exists.
- `deploy_slots` are 5/5/6/6 for missions 5–8.
- `GameState.new_campaign(CAMPAIGN[4], 4)` → objective `{"kind":"rout"}`.
- `new_campaign(CAMPAIGN[5], 5)` → objective kind `seize`, with `q,r` equal to
  `state.map["castles"][1]` (and `master_of(1)` sits there at start).
- `new_campaign(CAMPAIGN[6], 6)` → a player-0 non-master `runeward` exists,
  objective kind `protect` with `unit_id` matching that unit; `Objectives.evaluate`
  returns -1 while it lives and 1 after it's removed.
- `new_campaign(CAMPAIGN[7], 7)` → a `pyre_colossus` and a `storm_tyrant` exist for
  owner 1; objective empty (archon-kill finale).
- `new_campaign(CAMPAIGN[4], 4)` pre-places a `pyre_colossus` for owner 1 (boss demo).

Campaign screen is render-layer — validate the 8-row fit with `--shot campaign`
(read the PNG: 8 rows visible, none clipped, subtitle updated).

## Gates

- `pwsh -File godot/tests/run_tests.ps1` → `== N passed, 0 failed ==`, EXIT 0
  (never `-ExecutionPolicy Bypass`). Expected delta ≈ +20.
- Headless boot (game_state + campaign + scene change):
  `godot --headless --path godot --quit-after 30 2>&1 | Select-String "SCRIPT
  ERROR|Parse Error|Failed to load"` → no matches.
- `godot --path godot -- --shot campaign` then read the PNG.

## Build order (for the plan)

1. `data/campaign.gd` 4 scenarios (incl. the `seize_enemy_castle`/`protect_ally`
   flags) + `_test_missions_5_8` data asserts (`CAMPAIGN.size()==8`, shapes,
   bosses/ally exist, deploy_slots). Lands the data first so step 2's tests have
   real entries.
2. `new_campaign` `seize_enemy_castle` + `protect_ally` wiring + tests
   (seize objective from `castles[1]`; protect ally spawned + objective id;
   `Objectives.evaluate` protect-alive/dead).
3. `campaign_scene` row-fit + subtitle + `--shot campaign`.
