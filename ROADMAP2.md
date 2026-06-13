# ROADMAP 2 — Wraithspire v2 (world-update-2)

Persistent milestone tracker, same protocol as v1 ROADMAP.md: one milestone →
verify (`node --check game.js` + `bash smoke-test.sh` green, Playwright probe
for UI work) → commit `[v2] N.N: <summary>` → check off here. Handoff blocks
at the bottom carry session-to-session state. Spec:
`docs/superpowers/specs/2026-06-10-wraithspire-v2-design.md`. Detailed
per-phase plans: `docs/superpowers/plans/` (Phase 1 written; later phases get
theirs when reached).

Hard rules (carried from v1): two-file zero-dep architecture; smoke test green
before every commit (fog OFF on smoke path); every gameplay system ships with
its AI hook in the same milestone; new code in banner sections 17+.

Tag legend: `[model | effort]` routing hints, same rubric as v1.

## Phase 1 — Combat core: abilities, statuses, weather  ✅ COMPLETE (S1)
## ⛔ JS WORK ENDS HERE — Phases 2-8 move to the Godot 4 port (decision log)

- [x] 1.1 Status engine (S1): section 17 — STATUS_META, addStatus (max-merge),
  hasStatus, effectiveMove (slow → max(1, move−2)), tickStatuses (burn −3 w/
  death handling, regen +2 capped, decrement-and-delete, checkWinCondition);
  endTurn ticks incoming player pre-heal-loop w/ gameover guard; one Dijkstra
  budget read swapped to effectiveMove; map status dots + card status line
  (card h +12). Spec-reviewed ✅, quality-reviewed (2 nits, accepted).
  [claude-opus-4-8 | high]
- [x] 1.2 Ability framework + first 4 (S1): section 18 — ABILITIES (all 12
  defined), abilityFor (evolved −1 cd, floor 1), resolveInstantAbility;
  wired healPulse (tidekin line), quake (geomaul line), skitter (duneskink),
  galeRush (galewisp line) — NOTE: shipped galeRush instead of frostBite
  (frostBite is enemy-target, lands with 1.3's targeting). Post-move menu
  Ability item w/ cooldown label; second-move-only leg (secondMove flag,
  attack rings suppressed in interactAt, leg menu = Capture/Wait); cd tick +
  flag clear in endTurn; card ability line (+12 h). Spec-reviewed ✅ twice
  (leak fixed: attack-during-leg), quality-reviewed (5 fragility notes,
  none reachable — accepted). [claude-opus-4-8 | high]
- [x] 1.3 Remaining 8 abilities (S1): mark ×1.2 / bulwark +2 DEF in
  computeDamage (forecast+AI inherit), ward consume-one-hit in applySwing,
  beginBattle opts {applyStatus, statusTurns} (non-counter swing only);
  bulwark/ward self+adjacent auras; enemy-target arming (STATE.abilityArm) +
  Blink tile-targeting (STATE.blinkArm, purple overlay) routed at top of
  interactAt; arm clears at cancel/Esc/mis-click/endTurn + state resets.
  All 12 lines wired. BONUS: fixed pre-existing v1 dead button — post-move
  "Attack" never fired (reachable nulled → branch unreachable); now unified
  through the arm pattern (ab:null = plain attack, no cd). Spec-reviewed ✅
  (live behavioral tests incl. ward/counter phases), quality clean.
  [claude-opus-4-8 | high]
- [x] 1.4 Ability AI (S1): aiScoreInstantAbility — healPulse +12/wounded-adj-
  ally, quake 20/9 per adj enemy (floor 18), bulwark/ward allies×5+4 (floor
  12, never refreshes active aura), current-hex evaluation (documented
  simplification; skitter/galeRush excluded). Attack-flavored abilities ride
  the pair loop (+6, useAbility flag) — but confirmed kills take the plain
  attack and keep the cooldown. Decision tree: kill → retreat → instant
  ability → capture → attack → move. Live-verified: AI casts Heal Pulse when
  no kill on offer; prefers kills when available; zero errors over full AI
  turns. [claude-fable-5 | high]
- [x] 1.5 Weather (S1): section 19 — WEATHERS (rain hydro+15/pyro−15, heat
  inverse, gale ranged −20% + flyers +1 MOV), per-map weatherTables (tides
  rain-heavy, crags heat-heavy), reroll 4-6 turns at round wrap; wMul inside
  computeDamage + flyBonus in effectiveMove → forecast/AI inherit free;
  topbar label; STATE.mapDef so campaign defs get the right table; weather
  in save blob (v1 saves default clear, blob.v unchanged). Live-verified all
  four effects. Final Phase-1 review fixes folded in: weather banner no
  longer clobbered by turn banner; arm-cancel re-move exploit closed
  (mis-click/Esc on an armed attack/ability/blink reopens the post-move menu
  instead of freeing the moved unit); v1-save cd normalization in loadGame
  (AI ability lockout); bulwark/ward 2→1 tick (one enemy round, as labeled).
  Known accepted gaps: forecast/AI blind to ward negation (symmetric),
  regen status has no writer until Phase-2 relics. [claude-sonnet-4-6 | medium]

## Phase 2 — Relics

- [x] 2.1 Relic core (Godot): data/relics.gd (6 passive + helpers); dynamic stat
  seam (atk/swift/farsight/vital→effective_max_hp/regen/thorn) in compute_damage/
  effective_move/effective_range/heal; map-gen spawn (def.relics, _pick+main rng);
  pick_up_relic (auto-equip, swap drops old, master-only Ley); board glyph + card
  line + SFX; save map.relics. [claude-opus-4-8 | high]
- [x] 2.2 Consumables + AI + saves (Godot): Phoenix (revive @1HP in _apply_hit),
  Warhorn (×1.5 in compute_damage, consume post-swing), Ley Crystal (master +6 MP
  on pickup); AI relic_tile_bonus move-nudge + pick_up_relic on move/attack/capture;
  save round-trips unit.relic + map.relics. 882 tests; opus review end-to-end sound.
  [claude-sonnet-4-6 | medium]

## Phase 3 — Fog of war

- [x] 3.1 Visibility engine (Godot): pure `core/vision.gd` (r3 ground/r4 fly +
  r2 owned spires, no LOS), `GameState.fog`/`visibility`/`revealed` +
  `recompute_visibility`; dim overlay + hidden-enemy gating (overlay/units_layer);
  `match_scene` recompute on move/summon/death/turn; skirmish title toggle (default
  off) + settings persistence. (Hover/forecast gating moot — no enemy card/forecast
  in the port; in-range enemies always within sight.) [claude-opus-4-8 | high]
- [x] 3.2 Fair-AI fog + extras (Godot): vision filter in `build_threat_map` +
  `run_summons` (fog-off = byte-identical, determinism preserved); `approach_target`
  falls back to the enemy castle when the master is hidden (no beeline); Veilstone
  relic (+1 vision) in POOL; `fog` flag on mission 4 (Wraithspire) + save round-trip;
  cutaway ambush reveal (attacker tile shown for the rest of the turn). 919 tests;
  opus whole-milestone review = merge-ready. [claude-opus-4-8 | high]

## Phase 4 — Content wave

- [~] 4.1 Four evolutions for hexwisp/runeward/frostmaw/duneskink — **DATA DONE**
  (Godot, branch `godot-p4-1-evolutions`): Hexlord/Sigilwarden/Glaciamaw/Dunestalker
  evolved entries + `evolves_to` wiring (mechanic unchanged); evolved forms non-summonable;
  `_test_sprites` PENDING_ART skip; 978 tests; cavecrew review clean. **ART PENDING** — 8
  sprite PNGs (token+battle ×4) not yet generated; loader degrades gracefully (engine disc
  until they land). Generation prompt in the spec appendix; import + PENDING_ART removal =
  the deferred art follow-up. [claude-sonnet-4-6 | medium]
- [x] 4.2 Objective framework (Godot): pure `core/objectives.gd` (evaluate/label for
  survive(n)/seize(hex)/protect(unit_id)/rout, beside always-on archon-kill);
  `GameState.objective`/`objective_progress` + `unit_by_id`/`enemy_non_masters` +
  `check_win_condition` hook (archon-death precedence kept) + `new_skirmish` copy;
  rush/defend AI weight tweak (no-objective = byte-identical, determinism preserved);
  seize evaluated on move (human + AI); topbar objective line; save round-trip; demo
  survive objective on campaign mission 2. 950 tests; opus whole-milestone review =
  merge-ready. [claude-fable-5 | high]
- [~] 4.3 Bosses + maps — **DATA DONE** (Godot, branch `godot-p4-3-bosses-maps`):
  2 new skirmish maps (Mistveil Hollow `fog:true` — first fog-default skirmish map +
  Ashfall Basin heat-weather; MAPS 4→6, title selector auto-lists them); 2 bosses
  (Pyre Colossus pyro/quake 52/16/6, Storm Tyrant zephyr-fly/diveMark 40/14/4) —
  non-summonable, `boss:true`, reuse existing abilities (no new combat code); Pyre
  Colossus demo'd in mission 4 `ai_summons`. 998 tests; `_test_sprites` pending_art skip.
  **BOSS ART PENDING** — 4 sprite PNGs not generated (prompt in spec appendix).
  [claude-sonnet-4-6 | medium]

## Phase 5 — Persistent war campaign

- [x] 5.1 Roster layer: pure `core/roster_store.gd` (campaign.v2 slot
  `user://wraithspire_campaign.json`) — full-snapshot entries (level/xp/evolved/
  relic + grown stats), `reconcile` (veteran carry + permadeath), `migrate`
  (v1 progress → 1 starter veteran/cleared act: stoneward L2 / tidekin L3 /
  earthbreaker L4 / hexlord L5), `load_or_init`/`save`/`reset`/`probe` + JSON
  int/bool re-coercion guard. Data-only; live wiring (deploy/win-reconcile/AI
  scaling) is 5.2; mission-unlock progress stays in settings. 1067 tests.
  [claude-opus-4-8 | high]
- [x] 5.2 Deploy screen + scaling: `core/deploy.gd` (unit_from_entry / roster_value
  / ai_scale_mp ÷10 cap 12 / slots_for / commit — place veterans near player master,
  record `deployed_roster_ids`, bump AI MP by scaled army value) + `scenes/deploy/
  deploy_scene.gd` (paged picker, two-click reset); router `story→deploy→play`;
  `on_match_won` reconciles survivors into roster on campaign win (permadeath on
  death, untouched on loss); `deployed_roster_ids`+`roster_id` saved; per-mission
  `deploy_slots` (3/3/4/4). Campaign-only. 1112 tests. [claude-opus-4-8 | high]
- [x] 5.3 Missions 5–8 (titans-awakened arc): 4 hard scenarios in campaign.gd
  (CAMPAIGN 4→8) — The First Tremor (rout/Pyre Colossus), The Storm Crown
  (seize enemy castle/Storm Tyrant), The Last Refuge (protect Runeward/fog),
  The Titanfall (both titans, archon-kill finale); ai_mp_bonus 10/12/12/14,
  deploy_slots 5/5/6/6, weather/fog skews. `new_campaign` gained runtime
  objective builders `seize_enemy_castle` (from castles[1]) + `protect_ally`
  (spawn ally + {protect,unit_id}); campaign screen shrunk to fit 8 rows +
  titan subtitle. 1162 tests. [claude-opus-4-8 | high]

## Phase 6 — Unlocks + records

- [ ] 6.1 Unlock system: hard-AI/map/evolution/gauntlet gates in settings
  blob; greyed UI + unlock hints; classic content never locks.
  [claude-sonnet-4-6 | medium]
- [ ] 6.2 Records: recordEvent() hooks, lifetime totals + per-monster kills,
  ~12 achievements, RECORDS title screen, "wraithspire.records.v1".
  [claude-sonnet-4-6 | medium]

## Phase 7 — Roguelite gauntlet

- [ ] 7.1 Run core: 6-battle chain (small fixed-seed maps, mixed objectives),
  2-starter pick, in-run roster (reuse 5.1), full heal between, archon death
  ends run; resumable "wraithspire.gauntlet.v1". [claude-opus-4-8 | high]
- [ ] 7.2 Draft + ramp: between-battle draft (relic / recruit / upgrade),
  easy→hard ramp, streaks/clears → records, title entry behind 6.1 gate.
  [claude-opus-4-8 | high]

## Phase 8 — Balance, perf, docs

- [ ] 8.1 Balance + save audit: cross-system balance pass (abilities, relics,
  veteran-campaign curve), v1→v2 save migration audit.
  [claude-fable-5 | high]
- [ ] 8.2 Perf + README v2 + final full-match playtest (all systems on) +
  ROADMAP2 closeout. [claude-fable-5 | high]

## Decision log

- S1 (2026-06-10): systems-first ordering (approach A) approved; spec
  committed at 5a7f27a. Two-file zero-dep architecture retained.
- S1 (2026-06-10): ENGINE DECISION — finish Phase 1 in JS as the cheap design
  lab, then port the proven game to Godot 4 ("path B"). JS work STOPS after
  milestone 1.5; Phases 2-8 of this roadmap will be re-planned as Godot work
  (spec + ROADMAP2 + ability/relic tables carry over as the build plan; code
  does not). Cleanest-cut rationale: every JS milestone past Phase 1 would be
  redone in Godot.

## Handoff log

## Session 1 — 2026-06-10
Done: Phase 1 COMPLETE via subagent-driven execution (implementer + spec
review + quality review per milestone) — 1.1 status engine, 1.2 ability
framework, 1.3 all 12 abilities (+ fixed v1's dead post-move Attack button),
1.4 ability AI, 1.5 weather (+ final-review fixes: banner clobber, arm-cancel
re-move exploit, v1-save cd normalization, bulwark/ward duration).
State: GREEN — smoke pass at every commit; abilities/weather live-verified
via Playwright (player paths, AI casting, forecast deltas).
Next: NO further JS milestones. Per the engine decision, next session starts
Godot 4 port planning — carry over the v2 spec, this roadmap (Phases 2-8),
data tables (UNIT_TYPES/ELEM_MATRIX/ABILITIES/WEATHERS/MAPS/CAMPAIGN), AI
architecture, and Phase-1's validated combat design. The JS build remains
the playable reference implementation.
Risks/notes: forecast/AI treat warded targets as killable (symmetric,
accepted); regen status awaits Phase-2 relics; resumed campaign saves fall
back to the skirmish weather table (STATE.mapDef not serialized).
