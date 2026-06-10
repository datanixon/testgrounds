# Wraithspire v2 — Design

Date: 2026-06-10 · Branch: `world-update-2` · Status: approved by user

## Context

Wraithspire v1 shipped a complete single-player loop (ROADMAP.md, all phases checked off, merged to main at `c8ba204`): 12 summonable monsters + 8 evolutions, XP/leveling, terrain/element systems, cinematic battles, threat-map AI with 3 difficulties, 4 skirmish maps, a 4-mission campaign, save/load, undo, keyboard play, settings, and a perf pass.

v2 chases three directions the user picked: **deeper strategy**, **more content**, and **meta progression** (all four meta shapes: persistent war campaign, unlock tree, roguelite gauntlet, records/achievements). Local multiplayer is explicitly out of scope.

**Ordering principle (approach A, "systems-first"):** build combat-layer systems before anything that consumes them. Content, campaign, and gauntlet are designed *around* abilities/relics/fog rather than retrofitted. The gauntlet lands last because it is almost pure reuse.

## Constraints

- **Two-file zero-dependency architecture stays**: `index.html` + `game.js`, no build step, no packages. New code goes in new banner-numbered sections (17+). game.js will grow to roughly 8–9k lines; section discipline is the mitigation.
- `bash smoke-test.sh` must pass before every commit (fog stays off on the smoke path).
- Every gameplay system ships with its AI hook in the same milestone — no human-only mechanics.
- Process identical to v1: `ROADMAP2.md`, one milestone → verify → commit `[v2] N.N: summary` → check off; handoff blocks for session continuity.

## Non-goals

- No multiplayer (hotseat or networked).
- No engine/framework change, no asset files (art and audio remain procedural).
- No mobile/touch support work beyond what already exists.

---

## Phase 1 — Unit abilities + status effects + weather

**Abilities.** Each monster type gets exactly one active ability, an alternative to attacking (a unit's turn = move + one of attack/ability/capture/wait). Cooldown counted in turns, stored on the unit instance (`u.cd`), ticks down in `endTurn` for the owner's units.

Initial ability table (tune freely during implementation; one per base line, evolved forms inherit with −1 cooldown):

| Line | Ability | Effect | CD |
|---|---|---|---|
| tidekin | Heal Pulse | adjacent allies +5 HP | 3 |
| cinderling | Ignite | attack that also burns (3 dmg/turn × 2) | 3 |
| stoneward | Bulwark | adjacent allies +2 DEF until your next turn | 3 |
| galewisp | Gale Rush | may move again after acting | 4 |
| pyrowyrm | Cinder Breath | normal breath attack +burn | 4 |
| mistleviath | Undertow | attack that slows (target −2 MOV next turn) | 3 |
| geomaul | Quake | damage all adjacent enemies (no counter) | 4 |
| skyharrow | Dive Mark | attack; target takes +20% dmg until your next turn | 4 |
| hexwisp | Blink | teleport up to 4 hexes (visible tiles only under fog) | 3 |
| runeward | Ward | negate the next hit on an adjacent ally | 4 |
| frostmaw | Frost Bite | attack that slows | 3 |
| duneskink | Skitter | +2 MOV this turn, cannot attack | 2 |

**Status effects — one mechanism, two flavors.** All effects live in `u.status = {key: turnsLeft}` and tick in `endTurn`. Flavor 1, ticking statuses (exactly three): `burn` (damage at turn start), `slow` (move penalty, read in `computeReachable`), `regen` (heal at turn start, used by a relic). Flavor 2, turn-scoped combat flags set by abilities (`bulwark`, `ward`, `mark`): boolean-with-ttl entries in the same map, read by `computeDamage`/`beginBattle`, auto-expiring at the owner's next turn start. No other status types. Shown as tiny icons under the map HP bar and a line on the sidebar card.

**UI:** "Ability" item in the post-move menu showing name + cooldown state; ability line on the unit info card; floats + beep on use.

**AI:** abilities become scored candidates in `aiActUnit` via a small per-ability-key heuristic switch (heal if adjacent ally below 60%, Quake if ≥2 adjacent enemies, Blink toward objective when blocked, etc.). The existing decision tree (kill > retreat > capture > attack > move) gains an "ability" candidate scored against attack.

**Weather.** Global `STATE.weather = {key, turnsLeft}`; re-rolls every ~5 turns from a per-map weather table. Types: clear, rain (+15% hydro attack / −15% pyro), heatwave (inverse), gale (flyers +1 MOV, all ranged damage −20%). Implementation: one multiplier inside `computeDamage` + one hook in `computeReachable` — AI and damage forecast pick it up for free. Topbar weather icon + name; banner on change. Per-map tables let desert maps skew heatwave, marsh maps skew rain.

## Phase 2 — Relics

Items on the battlefield. Map defs gain a `relics` count; relics spawn on plain tiles at generation (placement rules like towers). A unit ending its move on a relic tile auto-equips it — **one slot per unit**, no swapping UI (picking up with a full slot drops the old one on the tile).

Relic table (~10): +2 ATK, +4 maxHP, +1 MOV, +1 RNG (cap 2), Regenring (regen 2/turn), Thorncharm (counters +2), Phoenix Charm (revive once at 1 HP, consumed), Warhorn (next attack +50%, consumed), Ley Crystal (master only: +6 MP, consumed on pickup), Veilstone (under fog: +1 vision).

UI: relic glyph on the tile, relic line on the unit card, pickup float. Serialization: `u.relic` key. AI: small pathing bonus toward relic tiles in move-only scoring; effects flow through existing stat reads, so no further AI logic.

## Phase 3 — Fog of war

Per-map/mission flag plus a skirmish title toggle; **off by default** on classic maps and on the smoke path. Terrain always visible (classic Master of Monsters style); enemy units hidden outside vision. Vision = union over your units (radius 3, flyers 4) plus owned spires/citadel (radius 2). Visibility set cached per turn, recomputed on move/summon/death.

Render: dim overlay on out-of-vision tiles; hidden enemies not drawn; hover card and forecast refuse hidden targets. **The AI plays fair:** its threat map and target list are filtered to units it can see (one filter in `buildThreatMap`/target collection). Battle cutaways reveal the attacker.

## Phase 4 — Content wave

- **4 evolutions** for hexwisp/runeward/frostmaw/duneskink (completing the "every base evolves" rule), map + battle sprites in the established procedural style.
- **2 boss monsters** (unique sprites, big stat blocks, abilities) — campaign/gauntlet only, never in SUMMON_LIST.
- **2 new skirmish maps** (6 total), one fog-flagged by default.
- **Mission objective framework** — win conditions beyond archon-kill: `survive(n)`, `seize(hex)`, `protect(unitId)`, `rout`. Objective state checked alongside the existing win condition; topbar shows the active objective; AI weights adjust per objective (defend vs rush). This framework is the foundation for Phases 5 and 7.

## Phase 5 — Persistent war campaign

Campaign v2 extends 4 → **8 missions**: v1's four stay as acts 1–4; four new missions use objectives, bosses, fog, and weather skews.

**Persistent roster:** survivors carry level/XP/evolution/relic between missions; deaths are permanent (Fire Emblem rules). Pre-mission **deploy screen**: choose veterans up to a mission-defined slot cap; the archon still summons fresh units mid-battle, and survivors join the roster after a win. Master HP resets between missions. AI opening strength scales lightly with roster power (sum of unit values) so veteran armies stay challenged.

Storage: `wraithspire.campaign.v2` slot (roster + mission progress), separate from the per-match autosave; resettable from the campaign screen. v1 campaign progress maps to "acts 1–4 cleared".

## Phase 6 — Unlock tree + records

**Unlocks** (stored in settings blob): hard AI unlocks on first win; maps 5–6 unlock through play; the four new evolutions unlock via campaign clears; gauntlet unlocks after campaign mission 2. Classic v1 content never locks. Locked items render greyed with their unlock hint.

**Records screen** (off the title): lifetime totals (matches, wins per difficulty, battles, summons/losses, per-monster kills, favorite summon), best gauntlet streak, and ~12 achievements (first evolution, flawless win, fog win, weather-empowered kill, full campaign clear, ...). One `recordEvent(key, data)` hook wired into existing event sites; persists in `wraithspire.records.v1`.

## Phase 7 — Roguelite gauntlet

Run = **6 escalating battles** on small fixed-seed maps with mixed objectives. Start: pick 2 starter monsters. Between battles: **draft 1 of 3** — relic / recruit / upgrade (+1 level to a chosen unit). In-run roster persists (reuses the campaign roster machinery); full heal between fights; archon falls = run over. Difficulty ramps easy→hard across the run. Run state saved (`wraithspire.gauntlet.v1`) so runs are resumable; streaks and clears feed records. Mostly UI + run flow — systems all exist by this phase.

## Phase 8 — Balance, perf, docs

Cross-system balance pass (abilities vs stats, relic power, campaign difficulty curve with veteran rosters), perf check (fog overlay and status rendering must not regress the terrain-cache win), README v2, final integration playtest, ROADMAP2 closeout.

---

## Cross-cutting

**Save versioning:** match autosave bumps to v2 (adds `u.cd`, `u.status`, `u.relic`, weather, objective state, relic tiles). The v2 loader migrates v1 blobs by defaulting the new fields. Campaign, gauntlet, and records live in their own keyed slots so corruption is isolated.

**Data model deltas:** `UNIT_TYPES[*].ability`, `MAPS[*].relics/fog/weatherTable`, mission defs gain `objective` + `deploySlots`, `STATE` gains `weather`, `visibility`, `objective`.

**Testing:** smoke test unchanged and mandatory (fog off). Per-milestone verification via Playwright over `python -m http.server` (file:// blocked in the MCP; cache-bust `?v=N`; bare lexical names). Full-match playtest at Phase 8.

**Success criteria:** a player can — in one sitting — toggle fog on a new map, watch weather shift a battle forecast, grab a relic, fire an ability the AI also uses against them, take a veteran army through a campaign mission with an objective that isn't "kill the archon", lose a unit permanently and feel it, then spend an evening chasing a gauntlet streak. No console errors; smoke test green at every commit.
