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

## Phase 1 — Combat core: abilities, statuses, weather

- [x] 1.1 Status engine (S1): section 17 — STATUS_META, addStatus (max-merge),
  hasStatus, effectiveMove (slow → max(1, move−2)), tickStatuses (burn −3 w/
  death handling, regen +2 capped, decrement-and-delete, checkWinCondition);
  endTurn ticks incoming player pre-heal-loop w/ gameover guard; one Dijkstra
  budget read swapped to effectiveMove; map status dots + card status line
  (card h +12). Spec-reviewed ✅, quality-reviewed (2 nits, accepted).
  [claude-opus-4-8 | high]
- [ ] 1.2 Ability framework + first 4: ABILITIES table, per-type `ability`
  key (evolved −1 cd), u.cd ticking, "Ability" post-move menu entry, resolve
  + floats/sfx. Ships Heal Pulse, Quake, Skitter, Frost Bite.
  [claude-opus-4-8 | high]
- [ ] 1.3 Remaining 8 abilities: Ignite, Cinder Breath, Undertow, Dive Mark
  (attack-flavored via battle applyStatus), Bulwark, Ward (flag auras),
  Blink (teleport targeting), Gale Rush (move-again). [claude-opus-4-8 | high]
- [ ] 1.4 Ability AI: per-key heuristics scored as candidates in aiActUnit
  beside attack/capture/move. [claude-fable-5 | high]
- [ ] 1.5 Weather: STATE.weather, per-map tables, reroll ~5 turns,
  computeDamage/computeReachable hooks (AI + forecast free), topbar icon +
  change banner. [claude-sonnet-4-6 | medium]

## Phase 2 — Relics

- [ ] 2.1 Relic core: map-gen spawns (def.relics), pickup on move-end, one
  slot (swap drops old), 6 passive relics, tile glyph + card line + float.
  [claude-opus-4-8 | high]
- [ ] 2.2 Consumables + AI + saves: Phoenix Charm, Warhorn, Ley Crystal;
  AI pathing nudge toward relics; save blob v2 fields (cd/status/relic).
  [claude-sonnet-4-6 | medium]

## Phase 3 — Fog of war

- [ ] 3.1 Visibility engine: per-turn cached vision set (r3 ground/r4 fly +
  r2 owned spires), dim overlay, hidden enemies, hover/forecast gating,
  skirmish title toggle (default off). [claude-opus-4-8 | high]
- [ ] 3.2 Fair-AI fog + extras: buildThreatMap/target filtering to visible,
  Veilstone relic (+1 vision), fog-flagged map defs, cutaway reveals.
  [claude-opus-4-8 | high]

## Phase 4 — Content wave

- [ ] 4.1 Four evolutions for hexwisp/runeward/frostmaw/duneskink: data +
  map & battle sprites (every base now evolves). [claude-sonnet-4-6 | medium]
- [ ] 4.2 Objective framework: survive(n)/seize(hex)/protect(unit)/rout win
  conditions beside archon-kill; topbar objective line; AI weight shifts per
  objective. [claude-fable-5 | high]
- [ ] 4.3 Bosses + maps: 2 boss monsters (unique sprites/abilities, not
  summonable) + 2 new skirmish maps (one fog-default).
  [claude-sonnet-4-6 | medium]

## Phase 5 — Persistent war campaign

- [ ] 5.1 Roster layer: campaign roster storage ("wraithspire.campaign.v2"),
  survivor carry (level/xp/evolved/relic), permadeath, v1 progress → acts 1–4
  mapping. [claude-opus-4-8 | high]
- [ ] 5.2 Deploy screen + scaling: pre-mission veteran picker (slot caps),
  survivors join roster on win, AI opening strength scales with roster value.
  [claude-opus-4-8 | high]
- [ ] 5.3 Missions 5–8: defs with objectives/bosses/fog/weather skews + lore
  interstitials; campaign screen extended. [claude-opus-4-8 | high]

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

## Handoff log
