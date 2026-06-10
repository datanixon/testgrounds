# ROADMAP — Master of Monsters Remake (overnight world update)

Persistent state for unattended overnight sessions. Sessions have no memory:
this file + git history are the only carriers. Update it every session.

## How to run / verify

- Play: `start index.html` (no build, no deps — single `index.html` + `game.js`).
- Smoke test (MANDATORY before every commit): `bash smoke-test.sh`
  — syntax-checks `game.js`, then headless-boots the game on `#smoke`, plays a
  full first turn (player summons, AI plays its whole turn), greps for
  `SMOKE_OK`. Exit 0 = green.
- Visual check: headless Chrome screenshot recipe in `CLAUDE.md` (`#autostart`,
  `#demo`, `#battle`, `#gameover` hash hooks).

## Quality bar ("AAA-adjacent")

- A stranger clones the repo, opens `index.html`, and plays a complete,
  legible, satisfying match vs the AI without reading code.
- Every player action has visual and/or audio feedback.
- No dead buttons, no placeholder text, no console errors during a normal match.

## Repo audit (Session 1)

- Stack: vanilla JS + canvas, single 2.9k-line `game.js`, 16 banner-numbered
  sections (see `CLAUDE.md` for the section map). No build step, no deps.
- **Already working**: pointy-top axial hex map (procedural, seeded mulberry32),
  terrain w/ move cost + defense + flyer-only, 8 monsters + 2 archon masters,
  5-element matrix, MP summoning economy, tower capture (+2 MP/turn each),
  tower/castle healing, Dijkstra reachability, pure `computeDamage`, cinematic
  battle cutaway scene (10-phase state machine), single-difficulty AI
  (target scoring + master tower-grabbing + random summons), title/gameover
  screens, 5-track procedural synth music + SFX, turn banner, sidebar log.
- **Missing vs original Master of Monsters**: unit XP/leveling/evolution,
  multiple maps / map select, campaign/scenarios, save/load, AI difficulty
  levels + summon strategy, unit info panel/tooltips, settings, undo,
  roster breadth (original ~40 summons), narrative framing.

## Decision log

- S1: Smoke test = `#smoke` hash hook in `game.js` (DOM marker `SMOKE_OK`) +
  `smoke-test.sh` headless Chrome runner with `--virtual-time-budget=30000`.
  Chosen over Playwright/puppeteer to keep the zero-dependency rule.
- S1: No new dependencies added. Keep the game a 2-file, no-build artifact.
- S1: `error1.png` is a stray debug screenshot; `*.png` added to `.gitignore`
  (all art is procedural — no image assets exist or are planned).

## Milestones

Tag legend: `[model | effort]` consumed by the session router.
Check off with a one-line note when done. Mark `BLOCKED:`/`PARKED:` per rules.

### Phase 1 — Core completeness

- [x] 1.1 XP & leveling (S2): gainXp at aImpact/cImpact (dmg dealt +10 kill
  bonus), levels 1–5, +hp/+power/+def per level, full heal on level-up. Gold
  pips on map sprite, Lv label + XP bar in battle HUD, "LEVEL UP!" banner +
  fanfare. Stats live on the instance so computeDamage absorbs growth.
  [claude-opus-4-8 | high]
- [x] 1.2 Evolution system (S2): 8 evolved forms + `evolvesTo` links; non-master
  level-4+ unit on owned tower/castle evolves at turn start (tryEvolve in
  endTurn), growth absorbed into evolved base, full restore. Gold ring burst +
  "EVOLVED!" + 3-note fanfare; pulsing gold halo on map + battle (sprite stubs
  reuse base ids until 5.1). [claude-opus-4-8 | high]
- [x] 1.3 Terrain & element depth (S2): ELEM_AFFINITY — +20% attack from a
  terrain your element resonates with (pyro hill/mtn, hydro water/forest,
  terra mtn/hill, zephyr plain/mtn, arcane tower/castle), hooked in
  computeDamage. Hover sidebar shows DEF as gold diamonds + "Empowers:" element
  codes + unit "empowered" note; selected unit's reachable favorable tiles
  glint gold. [claude-sonnet-4-6 | medium]
- [x] 1.4 Match stats (S2): STATE.stats tracks summoned/lost per player +
  battles fought (incremented at summon sites & battle death frames); gameover
  screen shows turns, battles, and an AZURE/CRIMSON summoned/lost/spires table.
  [claude-sonnet-4-6 | medium]

### Phase 2 — Game feel & polish  ✅ COMPLETE (S3)

- [x] 2.1 Animated unit movement (S3): units slide hex-to-hex along the
  Dijkstra path (~85ms/hex smoothstep), camera eases to follow; input + AI step
  blocked during slide. reconstructPath walks reach prev-links; startMove/
  tickMove driven by a setTimeout ticker (NOT rAF — survives headless virtual-
  time); renderUnits interpolates the slider. Extracted openPostMoveMenu (deps
  3 copies). [claude-opus-4-8 | high]
- [x] 2.2 Map-layer feedback (S3): battle records damage/xp/LEVEL-UP floats in
  `b.floats`, emitted on the map in endBattleAndResume (after the cutaway);
  heal "+N" floats in endTurn; capture sparkle + summon ring burst at both
  player & AI sites. Generalised pushAnim with `ring` ("r,g,b" burst) + `dy`
  (stack offset); renderAnimationsMap rings key off `a.ring`. [claude-sonnet-4-6 | medium]
- [x] 2.3 Smooth camera (S3): STATE.camTarget + updateCamera() eases cam toward
  target each frame (k=0.18, snap when <0.3px). centerCameraOn sets the target
  (instant flag for fresh match); arrows + move-follow + battle handoff all set
  the target. RTS edge-pan from parked mouse (STATE.mouse, cleared on
  mouseleave); Space centers on selected unit / active master. [claude-sonnet-4-6 | medium]
- [x] 2.4 Transitions (S3): generic STATE.transition overlay (renderTransition
  drawn over every screen) — 'wipe' uncovers left→right with a gold leading
  edge (title→play), 'fade' dissolves from black (→ victory screen). Turn
  banner restyled: slides in from the left (easeOutCubic) with player-tinted
  accent rules + in/out fade. Battle cutaway already had its bar-wipe in/out.
  [claude-sonnet-4-6 | medium]

### Phase 3 — UI/UX  ✅ COMPLETE (S4)

- [x] 3.1 Unit info panel (S4): drawUnitCard in sidebar — portrait (map sprite
  1.5× in element-rimmed clipped box), owner/Lv/element, HP/MP/XP bars, stat
  row, standing-tile DEF diamonds + empowered note; hover enemy w/ friendly
  selected → FORECAST block (deal X–Y, elem mult, KO!, counter X–Y / none).
  computeDamage now also returns pre-jitter `base`; forecastBattle mirrors
  beginBattle's counter rule for stable UI ranges. [claude-opus-4-8 | high]
- [x] 3.2 Terrain tooltip + summon menu upgrade (S4): renderTerrainTooltip —
  cursor-anchored box (terrain name, move cost/impassable, DEF), map-area
  clamped, hidden during menu/moveAnim; renderSummonPanel — side panel on the
  summon menu's highlighted item (clipped 1.5× portrait, HP/element/MP cost,
  avg ELEM_MATRIX hint strong/even/weak vs foe, stat row).
  [claude-sonnet-4-6 | medium]
- [x] 3.3 Settings & help (S4): STATE.settings {musicVol, sfxVol, battleScene}
  persisted to localStorage ("wraithspire.settings.v1", incl. trackIndex);
  topbar gear/? buttons (topBarButtonRects shared by render+click); settings
  overlay (track </>, 10-seg vol bars + MUTE, battle scene ON/OFF, all rects
  from settingsRects); help overlay (controls list + ELEM_MATRIX pentagon
  wheel). Battle-scene OFF → beginBattle resolves instantly via extracted
  applySwing (same dmg/XP/floats path, no cutaway). musicVol multiplies the
  five music voices, sfxVol multiplies beep. [claude-sonnet-4-6 | medium]
- [x] 3.4 Keyboard layer (S4): STATE.cursor hex cursor (arrows/WASD, parity
  zigzag for visual up/down, camera follows near edges, syncs STATE.hover so
  the card/forecast work); Enter acts via interactAt (extracted from onClick —
  shared mouse/keyboard core); Tab cycles ready units (clears selection first
  so interactAt can't misread it as a move); Esc clears overlay→menu→selection
  →cursor. Old arrow camera-pan removed; help text updated.
  [claude-sonnet-4-6 | medium]

### Phase 4 — AI opponents  ✅ COMPLETE (S4)

- [x] 4.1 AI v2 core (S4): buildThreatMap (per-enemy reach × attack range,
  stacked dmg per tile, built once/turn); aiActUnit rewritten as scored
  decision tree — confirmed kills always taken (no counter on lethal), wounded
  retreat via aiRetreatNode (heal-tile distance + threat + cover), capture
  scored vs attack (any unit captures now — canCapture isMaster check dropped,
  shared captureTower helper), attacks use forecastBattle exact bases w/
  counter-risk/-death penalties + focus-fire bonus, move-only shaped by
  terrain def + threat (master drifts to unowned spires, never beelines).
  Weights in AI_W for 4.3 difficulty profiles. Soak: 16 turns headless, 0
  errors, all 4 spires by t8, master untouched. [claude-fable-5 | high]
- [x] 4.2 Summon economy (S4): aiTrySummons rewritten — scoreType = element
  edge vs enemy army (offense ×20, their counter-edge ×-10) + map terrain
  resonance fraction + stat-per-MP + variety penalty; ahead (army value
  >1.25×) → bank MP for cost≥12 units unless regen would overflow the cap;
  enemy within move+range of master → cheap-half flood to wall off. Verified:
  vs pyro-heavy player army AI fields hydro counters. [claude-opus-4-8 | high]
- [x] 4.3 Difficulty levels (S4): AI_W → AI_PROFILES {easy, normal, hard} +
  aiW() getter keyed off STATE.difficulty. Easy = threat-blind, no retreat,
  ±6 score jitter, random summons (v1 feel); Hard = bigger kill/master/focus
  bonuses, cheap trades (counterRisk .45), approach 1.7, earlier retreat.
  Title-screen EASY/NORMAL/HARD boxes (titleDiffRects shared render/click),
  ←/→ keys cycle, choice persisted in the settings blob.
  [claude-sonnet-4-6 | medium]

### Phase 5 — Content  ✅ COMPLETE (S4)

- [x] 5.1 Roster wave (S4): 8 evolved forms get own sprite ids + map & battle
  cases (base look, ascended — bigger silhouette, hotter palette, extra
  features); 4 new bases — hexwisp (arcane flyer rng2 c8), runeward (arcane
  tank c15), frostmaw (hydro bruiser c18), duneskink (terra runner c6) —
  SUMMON_LIST now 12. No evolvesTo on the new four (future). Stale index.html
  hint bar refreshed for the 3.4 keyboard layer. [claude-sonnet-4-6 | medium]
- [x] 5.2 Map system (S4): MAPS[] named defs (cols/rows, terrain mix counts,
  towers, optional fixed seed + handcrafted castle starts) consumed by
  parameterized generateMap(seed, def); COLS/ROWS now per-map lets. 4 maps:
  Frontier (classic), Shattered Tides (8 lakes), Emberfall Crags (15×11,
  9 ridges, handcrafted E-W standoff starts), Verdant Expanse (16×13, 6
  spires). Title map row (titleMapRects, ↑/↓ cycles, blurb w/ size+spires),
  choice persisted. Camera clamps auto-adapt via mapPixelWidth/Height.
  [claude-opus-4-8 | high]
- [x] 5.3 Campaign arc (S4): CAMPAIGN[] — 4 missions w/ fixed-seed map defs
  (11×9 skirmish → drowned marches → crags passes → 16×13 finale), per-mission
  difficulty + AI mp bonus + pre-summons + 4-line lore. New screens: campaign
  list (locked/READY/CLEARED rows) + story interstitial (staggered fade-in,
  click to begin). Title CAMPAIGN button ("next: <mission>"); win unlocks next
  (campaignProgress persisted in settings blob; full saves in 6.1); gameover
  shows MISSION COMPLETE/FAILED/CAMPAIGN COMPLETE. STATE.matchDifficulty keeps
  scenario difficulty match-local so skirmish prefs survive (caught via
  Playwright test — saveSettings mid-campaign had clobbered the pref).
  [claude-opus-4-8 | high]

### Phase 6 — Systems  ✅ COMPLETE (S4)

- [x] 6.1 Save/load (S4): one autosave slot "wraithspire.save.v1" (versioned
  blob: cells serialized directly since tower owners mutate, units incl.
  level/xp/evolved, stats, campaign tag, matchDifficulty, nextUnitId, log
  head). saveGame at every endTurn; deleteSave when a match ends; loadGame
  rebuilds MAP.towers/castles as refs into the cell map, resets transients,
  re-kicks AI if saved on its turn. Title CONTINUE button (green, beside
  CAMPAIGN) when probeSave finds a slot; corrupt save → cleared. Round-trip
  verified exact via Playwright (units/towers/stats identical after wreck +
  load). Campaign progress was already persisted (5.3).
  [claude-opus-4-8 | high]
- [x] 6.2 Undo move + log upgrade (S4): STATE.undo {unit,q,r} snapshot set
  before player startMove; "Undo" item in post-move menu (before Wait) —
  teleports back, un-acts, re-selects via interactAt; cleared at every commit
  point (attack target, capture, summonChoice, wait, Esc-cancel, endTurn).
  Log: pushLog(line, color), entries {text,color} (renderer tolerates legacy
  string saves), colorized call sites (red hits, gold captures/levels, purple
  summons, winner-tinted victory), wheel scrollback over the log strip w/
  ▲/▼ hints, snaps to newest on push. [claude-sonnet-4-6 | medium]

### Phase 7 — Performance & health

- [x] 7.1 Render perf (S5): terrain layer cached to offscreen canvas
  (terrainCache; drawHex/drawTerrainDetail verified frame/random-free) and
  blitted per frame — measured 1.09ms → 0.002ms/frame (~650×); also kills the
  168×7 hexCorner allocations/frame (main GC churn). Invalidated in
  generateMap, loadGame, captureTower (all owner-flip paths) — capture
  invalidation verified live. Battle scene profiled at 0.10ms/frame — no
  work needed. [claude-opus-4-8 | high]
- [ ] 7.2 README + final integration pass: rewrite README (screenshot, one
  command quickstart, controls, credits), full-match playtest checklist, fix
  anything found. [claude-fable-5 | high]

## Handoff log

## Session 1 — 2026-06-09
Done: Phase 0 — repo audit, this roadmap, `.claude/agents/grinder.md` +
`architect.md`, `#smoke` hook in `game.js` + `smoke-test.sh` (verified green:
`SMOKE_OK turn=2 units=6`), `.gitignore` for stray screenshots.
State: GREEN — last green commit: 6c7e7c2
Next: 1.1 XP & leveling
NEXT_MODEL: claude-opus-4-8
NEXT_EFFORT: high
Risks/notes: Smoke test needs Chrome at
`C:/Program Files/Google/Chrome/Application/chrome.exe`. Battle pacing was
recently slowed (b37e57d) — anything that adds battles to the smoke path may
need a bigger `--virtual-time-budget`. `runDemo`-summoned units spawn with
`acted: true`; smoke success condition is player-0 control on turn ≥ 2.

## Session 2 — 2026-06-09
Done: Phase 1 COMPLETE — 1.1 XP & leveling (gainXp at impact frames, lv1–5,
stat growth + full heal, map pips, battle HUD XP bar + "LEVEL UP!" banner),
1.2 Evolution (8 evolved forms + evolvesTo, tryEvolve on owned tower/castle at
lv4+, growth absorbed, gold ring/halo + fanfare), 1.3 Terrain-element affinity
(+20% atk on resonant terrain in computeDamage, DEF diamonds + Empowers line +
reachable glint), 1.4 Match stats (STATE.stats, gameover summary table). Also
gitignored `.playwright-mcp` verification artifacts.
State: GREEN — last green commit: 41fa922
Next: 2.1 Animated unit movement (slide hex-to-hex along Dijkstra path,
~80ms/hex eased, camera follows, input + AI step blocked during slide).
NEXT_MODEL: claude-opus-4-8
NEXT_EFFORT: high
Risks/notes: New combat fields live on the unit INSTANCE (level, xp, evolved)
and on STATE (stats) — when save/load (6.1) serializes STATE, include these.
computeDamage now returns `affMul`/`hasAffinity` too (for future damage
forecast in 3.1). Evolved types reuse base sprite ids as STUBS — real art is
milestone 5.1; the gold halo is the only current visual tell. Verified hover/
glint via Playwright over a local `python -m http.server` (file:// is blocked
in the Playwright MCP). A stray `python -m http.server 8765` may still be
running in the background from this session — harmless, dies with the shell.

## Session 3 — 2026-06-09
Done: Phase 2 COMPLETE — 2.1 Animated movement (reconstructPath +
startMove/tickMove; setTimeout-driven NOT rAF so it survives headless
virtual-time; renderUnits interpolates; input + AI gated; extracted
openPostMoveMenu dedup), 2.2 Map-layer feedback (battle damage/xp/LEVEL-UP
floats emitted post-cutaway via b.floats; heal floats; capture/summon ring
bursts at player+AI sites; pushAnim gained `ring`/`dy`), 2.3 Smooth camera
(STATE.camTarget + updateCamera lerp; RTS edge-pan from STATE.mouse; Space
centers; arrows/follow/handoff all drive the target), 2.4 Transitions
(STATE.transition wipe/fade overlay over every screen; title→play gold wipe;
gameover fade; restyled slide+fade turn banner with player-tinted rules).
State: GREEN — last green commit: cb1c849
Next: 3.1 Unit info panel (click/hover unit → sidebar card: portrait, element,
HP/MP bars, stats, XP bar, current-tile terrain bonus; hover enemy → damage
forecast vs selected unit via pure computeDamage).
NEXT_MODEL: claude-opus-4-8
NEXT_EFFORT: high
Risks/notes: render() is now if/else-if (not early-return) so renderTransition
draws last over all screens — keep that shape if adding screens. Animation
ticks: map anims (STATE.animations) decrement ttl in BOTH renderAnimationsMap
AND renderBattleAnims — anything pushed during a battle gets double/early-aged,
which is why 2.2 defers battle floats to endBattleAndResume. The slide ticker
(tickMove) MUST stay setTimeout-driven, not folded into the rAF render loop, or
the smoke test deadlocks under virtual-time (empty timer queue halts the
virtual clock → rAF starves). `const STATE`/top-level functions are NOT on
`window` (lexical globals) — Playwright probes must reference bare names, not
`window.STATE`. For 3.1: computeDamage is pure and already returns
affMul/hasAffinity/aTDef/dTDef — reuse it for the hover forecast. Save/load
(6.1) must still serialize the per-instance level/xp/evolved + STATE.stats.

## Session 4 — 2026-06-10 (interactive; overnight script retired)
Done: Phases 3, 4, 5, 6 ALL COMPLETE — 3.1 unit info card + damage forecast,
3.2 terrain tooltip + summon preview panel, 3.3 settings/help overlays +
battle-scene toggle (applySwing extraction + instant resolver), 3.4 keyboard
layer (interactAt extraction, hex cursor, Tab cycle), 4.1 AI v2 (threat map,
retreat, focus fire, universal capture via shared captureTower), 4.2 summon
economy (element counters, MP banking, emergency walls), 4.3 difficulty
profiles + title selector, 5.1 roster wave (12 new sprite sets, SUMMON_LIST
=12), 5.2 map system (MAPS[] defs, parameterized generateMap, title select),
5.3 campaign (4 missions, story screens, unlock progress), 6.1 save/load
(autosave each endTurn, title CONTINUE), 6.2 undo move + colored scrollable
log. One commit per milestone, smoke test green throughout.
State: GREEN — last green commit: d0288b0
Next: 7.1 Render perf (then 7.2 README + final pass — roadmap is then done).
NEXT_MODEL: claude-opus-4-8
NEXT_EFFORT: high
Risks/notes — read before 7.1:
- 7.1 scouting already done: drawTerrainDetail + drawHex are fully static (no
  frame/random deps) → safe to cache the whole map terrain layer to an
  offscreen canvas. Invalidate on: generateMap, loadGame, and captureTower
  (ALL owner-flip paths now route through captureTower — player menu + both
  AI paths). drawArenaBackground twinkles via `frame` — do NOT cache it.
- axialToPixel offsets by +HEX_W/2+6; rows start at q=-floor(r/2) so world
  x can go slightly negative — pad the offscreen canvas (~40px) and draw it
  back at the same offset.
- aiW() reads STATE.matchDifficulty (campaign) falling back to
  STATE.difficulty (skirmish pref). Never saveSettings mid-campaign with a
  scenario difficulty — that bug was caught and fixed in 5.3.
- Settings blob v1 ("wraithspire.settings.v1"): musicVol, sfxVol, battleScene,
  trackIndex, difficulty, mapIndex, campaignProgress. Save blob v1
  ("wraithspire.save.v1"): cells serialized raw (owners mutate), units,
  stats, campaign, matchDifficulty, nextUnitId, log head. Log entries are
  {text,color} — renderer tolerates legacy plain strings.
- interactAt(q,r) is the shared mouse/keyboard action core; STATE.undo is
  cleared at every commit point (attack/capture/summon/wait/Esc/endTurn).
- Playwright verification: python -m http.server 8765 (file:// blocked in
  the MCP), bare lexical names (no window.*), cache-bust with ?v=N on every
  reload or you test stale game.js.
- Stray verification PNGs in repo root are gitignored — safe to delete.
