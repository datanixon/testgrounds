# Wraithspire Godot port — M9: title / gameover / save / difficulty / campaign → PARITY

Date: 2026-06-11
Branch: `godot-port`
Milestone: M9 (the parity-completing milestone; after it the Godot port matches
the frozen JS reference `game.js`)
Reference: `game.js` sections 5 (STATE/screen router), 6.1 (save/load), 13 (turn
machinery), 14 (title) + 14b (campaign screens), 3.3 (settings).
Port design spec: `docs/superpowers/specs/2026-06-10-wraithspire-godot-port-design.md`

## Goal

Close the full game loop. Today the Godot build boots straight into a hardcoded
skirmish (`main.gd._ready` → `GameState.new_skirmish(MAPS[0], 42)`), hardcodes
player 1 = AI, and prints the winner to the console. M9 adds the surrounding
shell so the port reaches parity with the JS reference: a title screen with
map/difficulty/campaign/continue, a campaign mission flow (list → story →
match → progression unlock), a gameover screen with a stats summary, autosave +
resume, a settings overlay, and a generalized per-player AI table.

This is a **parity port of a frozen, validated reference**, not novel design.
Each screen is a faithful translation of an existing JS render/input function.
Visual fidelity (synthwave title, archon-silhouette gameover) is the target.

## Scope decisions (locked with user, 2026-06-11)

- **Campaign:** full flow — list screen + per-mission story/intro screen +
  4 missions with `aiMpBonus`/`aiSummons` opening modifiers + progression unlock
  with persisted `campaign_progress`.
- **Settings:** full overlay now — MUSIC VOL / SFX VOL (persisted, **inert until
  M10** when the audio engine is ported) + BATTLE SCENE on/off toggle (the
  skip-cutaway toggle deferred from M8).
- **Title picks:** difficulty (easy/normal/hard) + skirmish map (`MAPS`); both
  persisted.
- **Architecture:** Router + Session split (see below).
- **Save format:** JSON at `user://` (`wraithspire_save.json`,
  `wraithspire_settings.json`).
- **map_def gap:** serialize `map_def` into the save (closes the JS
  resumed-campaign-weather gap — cheap win).
- **Execution:** subagent-driven (grinder implementer → spec + code review →
  fixes via same agent → commit; final whole-milestone opus review).

## Architecture: Router + Session split

The JS `STATE` is one global object holding both the screen and the live match.
In the Godot port `GameState` is the **pure, per-match logic core** (instantiated
by `new_skirmish`, headless-testable, no nodes). Title/gameover/settings/campaign
progress exist with **no match loaded**, so they cannot live in `GameState`.

Introduce a persistent **app/session state** distinct from the per-match state:

### `core/session.gd` (new — class `Session`, RefCounted)

Owned by the router; outlives any match. Holds:

| field | type | notes |
|-------|------|-------|
| `screen` | `String` | `title｜campaign｜story｜play｜gameover` |
| `settings` | `Dictionary` | `{music_vol:float, sfx_vol:float, battle_scene:bool}` |
| `difficulty` | `String` | persisted skirmish difficulty (`easy｜normal｜hard`) |
| `map_index` | `int` | persisted skirmish map (index into `MAPS`) |
| `campaign_progress` | `int` | highest unlocked mission index; persisted |
| `story_index` | `int` | mission selected on the campaign screen |
| `has_save` | `bool` | whether an autosave exists (drives CONTINUE) |
| `state` | `GameState`/null | the live match, or null on menu screens |

Match-start helpers (port of JS `startNewGame`):
- `start_skirmish()` — builds `state` via `GameState.new_skirmish(MAPS[map_index], <seed>)`,
  `match_difficulty = difficulty`, resets stats, `is_ai = [false, true]`,
  `campaign_index = -1`, `screen = "play"`.
- `start_campaign(scenario_index)` — builds `state` via a new
  `GameState.new_campaign(scenario)` that applies the scenario's map +
  `aiMpBonus` (added to the AI master's MP) + `aiSummons` (pre-summoned AI
  creatures), sets `match_difficulty = scenario.difficulty` (does **not**
  overwrite the persisted skirmish `difficulty`), `campaign_index = scenario_index`,
  `screen = "play"`.
- `return_to_title()` — `screen = "title"`, clears campaign tag, restores
  persisted skirmish prefs (a campaign mission overrode `match_difficulty`, not
  `difficulty`, so nothing to restore beyond clearing the tag).

### `GameState` additions (per-match)

- `is_ai: Array[bool] = [false, true]` — replaces the `current_player == 1`
  hardcode. Identical behavior today (single-player vs one AI), but correct.
- `campaign_index: int = -1` — `-1` for skirmish; else the mission index.
- `match_difficulty: String` — the difficulty in force for THIS match (campaign
  missions set their own without touching the persisted pref).
- `stats: Dictionary = {summoned:[0,0], lost:[0,0], battles:0}` — for the
  gameover summary. `summoned[owner]++` on each summon; `lost[owner]++` on each
  death; `battles++` per resolved battle.

(`difficulty` already exists on `GameState` — keep it as the AI weight profile
source, set from `match_difficulty` at match start.)

### `main.gd` → thin router

`main.gd` becomes a router (Node2D):
- `_ready`: create `Session`, load settings (`SettingsStore.load` into
  `session.settings`/`difficulty`/`map_index`/`campaign_progress`), probe save
  (`SaveGame.probe` → `session.has_save`), `session.screen = "title"`, show the
  title scene.
- Owns the current screen scene as a child; frees + re-instantiates on screen
  change. Screen scenes emit a `request_screen(name)` (or call back into a
  router method) to navigate; the router reads `session` to build the right scene.
- The match controller is no longer self-starting (see below).

The current match controller (`scenes/main.gd`, 362 lines) **moves verbatim** to
`scenes/match/match_scene.gd` (class `MatchScene`). Lift-and-shift, minimal logic
change:
- `_ready` no longer calls `new_skirmish` — it receives a `GameState` (and a
  back-reference to `session` for autosave + battle-scene setting) from the
  router and builds the board/units/HUD/camera around it.
- `_on_end_turn` reads `state.is_ai[state.current_player]` instead of
  `state.current_player == 1`.
- On win (`state.winner != -1`), instead of `print`, it: advances
  `campaign_progress` if a campaign mission was won by player 0
  (`campaign_progress = min(CAMPAIGN.size()-1, max(campaign_progress, campaign_index+1))`,
  persisted), deletes the autosave, and asks the router for `screen = "gameover"`.
- Autosave: `SaveGame.save(state)` at the end of each `end_turn` cycle.

## Screens (faithful ports of the JS render/input functions)

Each screen is a self-contained scene (Control or Node2D + `_draw`), drawn
procedurally to match the JS. They reuse `scenes/battle/battle_sprites.gd` for
the archon portraits where the JS calls `drawBattleSprite`.

### TitleScene (`scenes/title/title_scene.gd`) — port of `renderTitle` (4767)

- Vertical gradient `#1a1130`→`#05030c`; synthwave perspective grid floor
  (vanishing lines + perspective horizontals); scrolling twinkling stars; sun
  disc with horizontal bars; drop-shadowed gold "WRAITHSPIRE" + "— SUMMONER'S
  WAR —"; two archon previews (AZURE left +1 facing, CRIMSON right −1) with
  labels; two lore lines.
- **Map selector** row (`MAPS`, highlight `map_index`, blurb line beneath:
  `desc (cols×rows, N spires)`); **difficulty** row (`DIFFICULTIES`, highlight
  `difficulty`); **CAMPAIGN** button (sub-label = next mission name or "all
  missions open"); **CONTINUE** button beside it only when `has_save`; blinking
  "CLICK OR PRESS ENTER TO BEGIN".
- Input: click a map/difficulty box → set + `SettingsStore.save`; CAMPAIGN →
  router `screen=campaign`; CONTINUE → `SaveGame.load` → `screen=play`;
  ↑/↓ cycles `map_index`; click elsewhere or Enter → `session.start_skirmish()`.
- Rect helpers (`title_diff_rects`, `title_map_rects`, `title_campaign_rect`,
  `title_continue_rect`) shared by draw + hit-test, ported 1:1.

### CampaignScene (`scenes/campaign/campaign_scene.gd`) — port of `renderCampaignScreen` (4978)

- `#05030c` fill; "CAMPAIGN" title + subtitle; 4 mission rows. Each row: index +
  name, intro-teaser or "locked — clear the previous mission", and a state badge
  (`CLEARED` if `index < campaign_progress`, `READY` if `== progress`, `LOCKED`
  if `>`), difficulty label. Unlocked = `index <= campaign_progress`.
- Input: click an unlocked row → `session.story_index = index`,
  `screen=story`. ESC → `screen=title`.

### StoryScene (`scenes/story/story_scene.gd`) — port of `renderStoryScreen` (5023)

- `#05030c`; "MISSION n OF 4"; mission name; intro lines fade in sequentially
  (per-line alpha ramp keyed off a frame counter). Blinking "CLICK TO BEGIN".
- Input: click → `session.start_campaign(story_index)`.

### GameoverScene (`scenes/gameover/gameover_scene.gd`) — port of `renderGameOver` (5054)

- `#05030c`; winning archon silhouette (`battle_sprites`); drop-shadowed
  "AZURE/CRIMSON TRIUMPHS" in the faction color; summary line (turns elapsed,
  battles fought); two-column stat table (Summoned / Lost / Spires per player —
  spires counted from `state.map` tower owners); campaign verdict line when
  `campaign_index >= 0` ("CAMPAIGN COMPLETE…" / "MISSION COMPLETE…" / "MISSION
  FAILED…"). Blinking continue prompt.
- Input: click/Enter → `session.return_to_title()`. (Campaign progress was
  already advanced and the save already deleted at win time in `match_scene`.)

## Save / load — `core/save_game.gd` (new, class `SaveGame`)

Pure serialization + thin file I/O, so the round-trip is harness-testable.

- `to_dict(state: GameState) -> Dictionary` — versioned `{v:1, turn,
  current_player, cols, rows, cells:[{q,r,terrain,owner}], units:[...living...],
  stats, next_id, campaign_index, match_difficulty, weather, map_def,
  is_ai}`. Units serialized whole (incl. `cd`, `status`, `level`, `xp`,
  `evolved`). **`map_def` IS serialized** (closes the JS resumed-campaign-weather
  gap).
- `from_dict(dict) -> GameState`/null — validates `v == 1` + array shapes;
  rebuilds the map cells (and the `towers`/`castles` reference lists from cell
  terrain); restores units, normalizing missing `cd` → 0 (old-blob safety);
  defaults missing `weather`; rebuilds `_next_id`; restores `stats`/`is_ai` with
  defaults. Resets all transient/selection state implicitly (a fresh `GameState`
  + restored fields; presentation rebuilds from it).
- File wrappers (touch `user://wraithspire_save.json`): `save(state)` (guard:
  only when a match is live), `load() -> GameState`/null, `delete()`,
  `probe() -> bool`.
- Autosave: called from `match_scene` at every end-of-turn; `delete()` on match
  end so a finished match leaves no stale CONTINUE.

## Settings — `core/settings_store.gd` (new, class `SettingsStore`)

`user://wraithspire_settings.json`: `{music_vol, sfx_vol, battle_scene,
difficulty, map_index, campaign_progress}`. `load(session)` merges into the
session at boot (validating ranges / enum membership, defaulting missing keys);
`save(session)` writes after every change. Music/sfx vols are stored and
round-tripped but have no audible effect until M10.

## Settings overlay — `scenes/hud/settings_panel.gd` (new)

A gear button added to `top_bar` opens the overlay during play (modal Control
over the HUD). Three rows ported from `renderSettingsOverlay`:
- MUSIC VOL / SFX VOL — 10-segment bars + mute; click sets the value and
  `SettingsStore.save`. Inert (no audio) until M10.
- BATTLE SCENE — ON/OFF. When OFF, `match_scene._play_battles` **drains the
  battle_log without awaiting the cutaway** (combat already resolved in core —
  the cutaway is pure animation, so skipping it is safe and matches JS
  `STATE.settings.battleScene === false`). Close button → dismiss.

## Project structure (new/changed files)

```
core/session.gd          (new) app/session state + match-start helpers
core/save_game.gd        (new) pure to_dict/from_dict + user:// I/O
core/settings_store.gd   (new) settings JSON persistence
core/game_state.gd       (edit) + is_ai, campaign_index, match_difficulty, stats, new_campaign
core/combat.gd           (edit) stats.battles++ / lost[owner]++ on resolution
scenes/main.gd           (rewrite → thin router)
scenes/match/match_scene.gd  (new = moved scenes/main.gd; reads is_ai; autosave; gameover handoff; battle-scene toggle)
scenes/title/title_scene.gd      (new)
scenes/campaign/campaign_scene.gd (new)
scenes/story/story_scene.gd       (new)
scenes/gameover/gameover_scene.gd (new)
scenes/hud/top_bar.gd    (edit) + gear button → opens settings
scenes/hud/settings_panel.gd     (new)
data/campaign.gd         (already ported — CAMPAIGN data, verify aiMpBonus/aiSummons/intro fields present)
tests/test_save.gd, test_settings.gd, test_session.gd, test_campaign_progress.gd (new)
```

`main.tscn` root stays a Node2D; the router swaps screen children at runtime.

## Testing

Harness (`pwsh -File godot/tests/run_tests.ps1`, `== N passed, 0 failed ==`,
EXIT 0) after every task. Harness covers the pure core:
- **Save round-trip:** `to_dict(state)` → `from_dict` preserves units (incl.
  cd/status/level/xp/evolved), stats, weather, **map_def**, campaign_index,
  match_difficulty, turn, current_player, map cells + rebuilt tower/castle lists,
  `_next_id`. Old-blob normalization (missing `cd` → 0; missing weather default).
  Version guard (`v != 1` → null).
- **Settings round-trip:** `save`→`load` preserves all fields; out-of-range /
  bad-enum values default safely.
- **Campaign progression rule:** win as player 0 on mission `i` ⇒
  `campaign_progress = max(progress, i+1)`, capped at `CAMPAIGN.size()-1`; a
  loss or a player-1 win leaves it unchanged.
- **`is_ai` table:** the AI branch fires for `is_ai[current_player] == true` and
  not otherwise.
- **`new_campaign`:** applies `aiMpBonus` (AI master MP delta) and pre-summons
  `aiSummons`; sets `campaign_index`/`match_difficulty`.

**Headless-boot gate** (catches parse errors in no-`class_name` scene scripts —
the M3 blind spot) after ANY scene/`main.gd`/`match_scene` change:
`godot --headless --path godot --quit-after 30 2>&1 | Select-String "SCRIPT
ERROR|Parse Error|Failed to load"` → clean (no matches), EXIT 0.

Visual verification stays manual/windowed (`godot --path godot`): title →
pick map+difficulty → skirmish → win → gameover → title; CAMPAIGN → mission 1 →
story → match → win → mission 2 unlocked; CONTINUE resumes a saved match;
settings overlay toggles the battle scene off (instant resolution).

## Accepted divergences from the JS reference

- Music/sfx volume sliders are **inert** until M10 (no audio engine ported yet);
  they persist and round-trip, just produce no sound.
- We **serialize `map_def`** (the JS reference does not), so resumed campaign
  matches roll correct weather — a deliberate improvement over the reference's
  known gap, not a parity break.
- (Carried from M8) Board updates under the cutaway, not at impact frames; AI
  movement is not animated. Unchanged here.

## Success criteria

The full loop closes with the same feel as the JS reference: title screen plays
a skirmish or a campaign mission; matches save at each turn and resume via
CONTINUE; a finished match shows the stats summary and routes back to title;
campaign missions unlock in sequence; the settings overlay toggles the cutaway.
Harness green and headless-boot clean at every commit. **Parity reached** —
after M9 the Godot port matches the JS reference; ROADMAP2 Phases 2–8 then get
their own post-parity specs. (M10 = art + audio is the only remaining port
milestone.)
