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

### Phase 3 — UI/UX

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
- [ ] 3.4 Keyboard layer: arrow/WASD cursor + Enter select, Tab cycle unready
  units, E end turn, Esc cancel — full match playable mouse-free.
  [claude-sonnet-4-6 | medium]

### Phase 4 — AI opponents

- [ ] 4.1 AI v2 core: threat-map evaluation (per-tile enemy reach), retreat
  when low HP toward heal tiles, prefer high-defense terrain when ending
  moves, focus-fire to confirm kills, non-master units capture towers too.
  [claude-fable-5 | high]
- [ ] 4.2 Summon economy: pick summons by element counters vs player army +
  map terrain, save MP for big units when ahead, emergency cheap bodies when
  master threatened. [claude-opus-4-8 | high]
- [ ] 4.3 Difficulty levels: Easy (current random-ish), Normal (4.1+4.2),
  Hard (Normal + aggression tuning + perfect focus fire); title-screen
  selector. [claude-sonnet-4-6 | medium]

### Phase 5 — Content

- [ ] 5.1 Roster wave: 8 evolved forms get real sprites (map + battle) +
  4 new base monsters (incl. arcane element coverage); balance pass on
  cost/stats table. [claude-sonnet-4-6 | medium]
- [ ] 5.2 Map system: named map definitions (seed + params + handcrafted
  overrides: size, terrain mix, tower count, start positions); 4 distinct
  maps; map select on title screen. [claude-opus-4-8 | high]
- [ ] 5.3 Campaign arc: 4-scenario escalation (tutorial-ish skirmish → final
  showdown) with brief narrative interstitials (text panels in existing art
  style), campaign progress kept in memory (persisted in 6.1).
  [claude-opus-4-8 | high]

### Phase 6 — Systems

- [ ] 6.1 Save/load: serialize STATE+MAP to localStorage (versioned),
  continue button on title, autosave each turn, campaign progress persisted.
  [claude-opus-4-8 | high]
- [ ] 6.2 Undo move: snapshot before move, "Undo" in action menu until attack/
  capture/summon committed; battle log panel upgrade (scrollback, colors).
  [claude-sonnet-4-6 | medium]

### Phase 7 — Performance & health

- [ ] 7.1 Render perf: cache static terrain layer to offscreen canvas
  (invalidate on capture), profile battle scene, fix any GC churn in
  per-frame allocations. [claude-opus-4-8 | high]
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
