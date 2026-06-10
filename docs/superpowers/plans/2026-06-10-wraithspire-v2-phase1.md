# Wraithspire v2 — Phase 1 (Combat Core) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Ship ROADMAP2 Phase 1 — status effects, one active ability per monster line, ability-aware AI, and global weather — all hooked into the existing combat/forecast/AI pipeline.

**Architecture:** All code in `game.js` (two-file zero-dep rule). New banner sections: **17. Status effects**, **18. Abilities**, **19. Weather**. Statuses are one mechanism (`u.status = {key: turnsLeft}`) ticked in `endTurn`; abilities are an action alternative resolved either instantly, via the existing battle pipeline (attack-flavored), or via targeting modes; weather is a global multiplier read inside `computeDamage`/`effectiveMove` so the AI and damage forecast inherit it for free.

**Tech stack:** vanilla JS + canvas. Verification per repo protocol: `node --check game.js`, `bash smoke-test.sh` (MUST pass before every commit), Playwright MCP probes over `python -m http.server 8765` (file:// is blocked; cache-bust with `?v=N`; STATE etc. are bare lexical globals, not on `window`). This repo has no unit-test framework — Playwright `browser_evaluate` probes with expected outputs are the test layer.

**Scope note:** This plan covers ROADMAP2 milestones 1.1–1.5 only. Phases 2–8 get their own plan documents when reached (spec: `docs/superpowers/specs/2026-06-10-wraithspire-v2-design.md`).

**Conventions that bite (from v1 handoffs):**
- `render()` is if/else-if with `renderTransition()` last — keep that shape.
- Never fold timers into rAF — `setTimeout` tickers survive headless virtual-time, rAF starves.
- Reset `ctx.textAlign = "left"` after right-aligned text. Wrap clips in save/restore.
- `STATE.undo` must be cleared at every action commit point.
- Each milestone = one commit `[v2] N.N: <summary>` + ROADMAP2.md checkoff in the same commit.

---

### Task 1 — Milestone 1.1: Status engine

**Files:**
- Modify: `game.js` — new section 17 (insert after section 16 boot, or between 8 and 9; keep banner numbering comments honest), hooks in `endTurn`, `computeReachable`, `renderUnits`, `drawUnitCard`, `startNewGame`, `loadGame`.
- Modify: `ROADMAP2.md` — checkoff.

- [ ] **Step 1: Add the status core (new banner section 17)**

```js
// =========================================================================
// 17. Status effects (v2 1.1)
// =========================================================================
// One mechanism, two flavors, all living in u.status = { key: turnsLeft }:
//  - ticking statuses: burn (damage at owner's turn start), regen (heal),
//    slow (move penalty, read via effectiveMove)
//  - turn-scoped combat flags set by abilities (1.3): bulwark, ward, mark —
//    read by combat code, expiring on the same tick as everything else.
const STATUS_META = {
  burn:    { color: "#e07050", label: "burning" },
  slow:    { color: "#5aa8d8", label: "slowed" },
  regen:   { color: "#7ac075", label: "regenerating" },
  bulwark: { color: "#f0c674", label: "bulwark +2 DEF" },
  ward:    { color: "#b078c8", label: "warded" },
  mark:    { color: "#ff8888", label: "marked +20% dmg taken" },
};

function addStatus(unit, key, turns) {
  if (!unit.status) unit.status = {};
  unit.status[key] = Math.max(unit.status[key] || 0, turns);
}

function hasStatus(unit, key) {
  return !!(unit.status && unit.status[key] > 0);
}

// Movement allowance after statuses (weather hook lands in 1.5).
function effectiveMove(unit) {
  let m = unit.move;
  if (hasStatus(unit, "slow")) m = Math.max(1, m - 2);
  return m;
}

// Tick all statuses for `owner`'s units at the start of their turn.
// Called from endTurn right after the acted-flag reset loop.
function tickStatuses(owner) {
  for (const u of aliveUnits(owner)) {
    if (!u.status) continue;
    if (u.status.burn > 0) {
      u.hp = Math.max(0, u.hp - 3);
      pushAnim("float", u.q, u.r, "-3 burn", PAL.red);
      if (u.hp <= 0) {
        pushLog(u.name + " succumbs to burns.", "#ff8888");
        if (STATE.stats) STATE.stats.lost[u.owner]++;
      }
    }
    if (u.status.regen > 0 && u.hp > 0 && u.hp < u.maxHp) {
      const heal = Math.min(2, u.maxHp - u.hp);
      u.hp += heal;
      pushAnim("float", u.q, u.r, "+" + heal, "#5fd06a");
    }
    for (const k of Object.keys(u.status)) {
      if (--u.status[k] <= 0) delete u.status[k];
    }
  }
  checkWinCondition(); // burn can kill — even a master
}
```

- [ ] **Step 2: Hook `endTurn`**

In `endTurn`, find the loop `for (const u of aliveUnits(STATE.currentPlayer)) { u.acted = false; ... }` (the heal/evolve loop after the player switch). Insert **before** that loop:

```js
  tickStatuses(STATE.currentPlayer);
  if (STATE.screen !== "play") return; // burn-kill may have ended the match
```

- [ ] **Step 3: Hook `computeReachable`**

In `computeReachable(unit)`, the Dijkstra budget compares accumulated cost against `unit.move`. Replace that read with `effectiveMove(unit)` (single substitution — grep `unit.move` inside the function; do NOT touch other `\.move` reads elsewhere).

- [ ] **Step 4: Map icons + card line**

In `renderUnits`, after the level-pips block, draw up to 3 status dots (3×3 px, `STATUS_META[k].color`, x-offset 5px apart) at `p.y + 33`. In `drawUnitCard`, after the "on TERRAIN" line, if the unit has statuses add one 9px line: active `STATUS_META[k].label`s joined with " · ", colored `PAL.inkDim`.

- [ ] **Step 5: Verify**

```
node --check game.js
bash smoke-test.sh        # expect: SMOKE PASS: SMOKE_OK ...
```

Playwright probe (server: `python -m http.server 8765`, navigate `?v=p11#autostart`):

```js
() => {
  const u = STATE.units.find(x => x.owner === 0);
  addStatus(u, "burn", 2); addStatus(u, "slow", 1);
  const moveBefore = effectiveMove(u);     // expect u.move - 2
  const hp0 = u.hp;
  tickStatuses(0);                          // burn ticks: -3 hp, counters decrement
  return { moveBefore, dmg: hp0 - u.hp, slowGone: !hasStatus(u, "slow"), burnLeft: u.status.burn };
}
// expect: { moveBefore: <move-2>, dmg: 3, slowGone: true, burnLeft: 1 }
```

- [ ] **Step 6: Checkoff + commit**

Check 1.1 off in ROADMAP2.md with a one-line note, then:

```bash
git add game.js ROADMAP2.md
git commit -m "[v2] 1.1: status engine — burn/slow/regen + combat flags"
```

---

### Task 2 — Milestone 1.2: Ability framework + first four

**Files:**
- Modify: `game.js` — new section 18; `UNIT_TYPES` entries; `makeUnit`/`makeMaster` (`cd: 0`); `openPostMoveMenu`; `selectMenuItem`; `endTurn` (cd tick); `drawUnitCard` (ability line).
- Modify: `ROADMAP2.md`.

- [ ] **Step 1: Ability table + lookup (new banner section 18)**

```js
// =========================================================================
// 18. Abilities (v2 1.2-1.4)
// =========================================================================
// One active ability per monster line — an ALTERNATIVE to attacking
// (a turn = move + one of attack/ability/capture/wait). Cooldown lives on
// the instance as u.cd (turns until ready), ticked in endTurn.
// target kinds: "none" (resolves instantly), "enemy" (attack-flavored,
// runs through beginBattle with a status payload — 1.3), "tile" (Blink).
const ABILITIES = {
  healPulse:    { name: "Heal Pulse",    cd: 3, target: "none",  desc: "+5 HP to adjacent allies" },
  quake:        { name: "Quake",         cd: 4, target: "none",  desc: "4 dmg to all adjacent enemies, no counter" },
  skitter:      { name: "Skitter",       cd: 2, target: "none",  desc: "take a second move-only action (+2 MOV)" },
  frostBite:    { name: "Frost Bite",    cd: 3, target: "enemy", desc: "attack; slows the target", status: "slow", statusTurns: 2 },
  ignite:       { name: "Ignite",        cd: 3, target: "enemy", desc: "attack; burns the target", status: "burn", statusTurns: 2 },
  cinderBreath: { name: "Cinder Breath", cd: 4, target: "enemy", desc: "attack; burns the target", status: "burn", statusTurns: 2 },
  undertow:     { name: "Undertow",      cd: 3, target: "enemy", desc: "attack; slows the target", status: "slow", statusTurns: 2 },
  diveMark:     { name: "Dive Mark",     cd: 4, target: "enemy", desc: "attack; marks the target", status: "mark", statusTurns: 2 },
  bulwark:      { name: "Bulwark",       cd: 3, target: "none",  desc: "+2 DEF to self & adjacent allies for a turn" },
  ward:         { name: "Ward",          cd: 4, target: "none",  desc: "shield self & adjacent allies from the next hit" },
  blink:        { name: "Blink",         cd: 3, target: "tile",  desc: "teleport up to 4 hexes" },
  galeRush:     { name: "Gale Rush",     cd: 4, target: "none",  desc: "take a second move-only action" },
};

// Evolved forms keep the line's ability one turn snappier.
function abilityFor(unit) {
  const t = UNIT_TYPES[unit.typeKey];
  if (!t || !t.ability) return null;
  const base = ABILITIES[t.ability];
  if (!base) return null;
  return Object.assign({ key: t.ability }, base, { cd: Math.max(1, base.cd - (t.evolved ? 1 : 0)) });
}
```

NOTE — design simplification (documented in spec deltas): **Skitter and Gale Rush both grant a second move-only action** (Skitter also +2 MOV on that leg). No attack on the second leg.

- [ ] **Step 2: Wire data**

Add `ability: "<key>"` to `UNIT_TYPES`: cinderling+infernite `ignite`; pyrowyrm+emberdrake `cinderBreath`; tidekin+tidelord `healPulse`; mistleviath+leviathan `undertow`; stoneward+colossus `bulwark`; geomaul+earthbreaker `quake`; galewisp+stormwisp `galeRush`; skyharrow+skytyrant `diveMark`; hexwisp `blink`; runeward `ward`; frostmaw `frostBite`; duneskink `skitter`. Add `cd: 0` to the literals in `makeUnit` and `makeMaster` (masters have no ability; `abilityFor` returns null for them since MASTER_TEMPLATE has no `ability`).

- [ ] **Step 3: Resolver for "none"-target abilities (this milestone ships healPulse, quake, skitter; bulwark/ward/galeRush land in 1.3)**

```js
// Resolve an instant (target:"none") ability at the unit's current hex.
// Returns true if it fired. Sets cooldown; caller handles acted/menu state.
function resolveInstantAbility(unit, ab) {
  if (ab.key === "healPulse") {
    let healed = 0;
    for (const n of hexNeighbors(unit.q, unit.r)) {
      const a = unitAt(n.q, n.r);
      if (a && a.owner === unit.owner && a.hp < a.maxHp) {
        const h = Math.min(5, a.maxHp - a.hp);
        a.hp += h; healed++;
        pushAnim("float", a.q, a.r, "+" + h, "#5fd06a");
      }
    }
    pushLog(unit.name + " pulses healing light.", PAL.green);
    beep(740, 0.1, "triangle", 0.2);
    return true;
  }
  if (ab.key === "quake") {
    let total = 0;
    for (const n of hexNeighbors(unit.q, unit.r)) {
      const e = unitAt(n.q, n.r);
      if (e && e.owner !== unit.owner) {
        e.hp -= 4; total += 4;
        pushAnim("float", e.q, e.r, "-4", PAL.red);
        if (e.hp <= 0) {
          pushLog(e.name + " is crushed.", "#ff8888");
          if (STATE.stats) STATE.stats.lost[e.owner]++;
          total += KILL_XP_BONUS;
        }
      }
    }
    if (total > 0 && gainXp(unit, total) > 0) pushAnim("float", unit.q, unit.r, "LEVEL UP!", PAL.gold, null, -22);
    pushLog(unit.name + " shakes the earth.", PAL.gold);
    beep(120, 0.18, "square", 0.25);
    checkWinCondition();
    return true;
  }
  if (ab.key === "skitter" || ab.key === "galeRush") {
    if (ab.key === "skitter") addStatus(unit, "skitterBoost", 1); // consumed by effectiveMove below
    unit.secondMove = true; // move-only leg; cleared on arrival or endTurn
    pushLog(unit.name + " surges with speed.", PAL.green);
    beep(880, 0.08, "triangle", 0.18);
    return true;
  }
  return false; // bulwark/ward arrive in 1.3
}
```

Extend `effectiveMove` (from 1.1): after the slow clause add `if (hasStatus(unit, "skitterBoost")) m += 2;`. Add `skitterBoost: { color: "#c8c8d8", label: "skittering" }` to STATUS_META.

- [ ] **Step 4: Menu + selection wiring**

In `openPostMoveMenu(unit)`, before the Undo/Wait inserts:

```js
  const ab = abilityFor(unit);
  if (ab) items.push({
    label: unit.cd > 0 ? ab.name + " (" + unit.cd + ")" : ab.name,
    kind: "ability", disabled: unit.cd > 0,
  });
```

In `selectMenuItem`, new branch (model on the existing "wait" branch — note it must clear `STATE.undo`):

```js
  } else if (item.kind === "ability") {
    const ab = abilityFor(unit);
    if (!ab) { closeMenu(); return; }
    if (ab.target === "none") {
      if (resolveInstantAbility(unit, ab)) {
        unit.cd = ab.cd;
        STATE.undo = null;
        if (unit.secondMove) {
          // second move-only leg: reselect with fresh reachable, not acted yet
          closeMenu();
          interactAt(unit.q, unit.r);
        } else {
          unit.acted = true;
          closeMenu();
        }
      }
      return;
    }
    // "enemy" and "tile" targeting modes land in 1.3 — until then those
    // ability keys are not yet assigned to any summonable in UNIT_TYPES.
```

Second-leg plumbing: in `openPostMoveMenu`, when `unit.secondMove` is true build ONLY `[Wait]` (+Capture if `canCapture`) — no Attack/Summon/Ability — and clear the flag (`unit.secondMove = false`). In `endTurn`, clear `u.secondMove = false` and tick `if (u.cd > 0) u.cd--;` inside the existing acted-reset loop for the incoming player.

NOTE: gate Step 2's data so only healPulse/quake/skitter/frostBite lines get their `ability:` field THIS milestone (frostBite is target:"enemy" — add the data but the menu item will show for frostmaw without working; therefore add frostmaw's `ability` in 1.3 instead. This milestone wires: tidekin/tidelord, geomaul/earthbreaker, duneskink, galewisp/stormwisp).

- [ ] **Step 5: Card line**

`drawUnitCard`: under the stats row add, when `abilityFor(u)` exists, a 9px line: `"◆ " + ab.name + (u.cd > 0 ? " — ready in " + u.cd : " — ready")`, gold when ready, inkDim on cooldown.

- [ ] **Step 6: Verify**

```
node --check game.js && bash smoke-test.sh   # SMOKE PASS expected
```

Playwright (`?v=p12#autostart`):

```js
() => {
  const m0 = STATE.units.find(u => u.owner === 0);
  const tide = makeUnit("tidekin", 0, m0.q + 1, m0.r);
  const hurt = makeUnit("cinderling", 0, m0.q + 1, m0.r - 1); hurt.hp = 3;
  STATE.units.push(tide, hurt);
  const ab = abilityFor(tide);
  resolveInstantAbility(tide, ab); tide.cd = ab.cd;
  return { abName: ab.name, healedTo: hurt.hp, cd: tide.cd };
}
// expect: { abName: "Heal Pulse", healedTo: 8, cd: 3 }
```

- [ ] **Step 7: Checkoff + commit**

```bash
git add game.js ROADMAP2.md
git commit -m "[v2] 1.2: ability framework + Heal Pulse, Quake, Skitter, Gale Rush"
```

---

### Task 3 — Milestone 1.3: Remaining abilities

**Files:**
- Modify: `game.js` — section 18 (targeting modes, flag auras), `beginBattle`/`applySwing`/`computeDamage` (status payload + flag reads), `interactAt` (target-mode routing), `renderOverlays` (target highlights), `UNIT_TYPES` (remaining `ability:` fields).
- Modify: `ROADMAP2.md`.

- [ ] **Step 1: Combat-flag reads**

In `computeDamage(attacker, defender)`:

```js
  // v2 combat flags (1.3)
  const markMul = hasStatus(defender, "mark") ? 1.2 : 1.0;
  const bulwarkDef = hasStatus(defender, "bulwark") ? 2 : 0;
```

Fold `markMul` into the `base` product (next to `affMul`) and add `bulwarkDef` into `mit` (`defender.def + bulwarkDef + dTDef * 0.5`). Both flow into the forecast and AI automatically.

In `applySwing(b, counter)`, before `dst.hp -= dmg;`:

```js
  if (hasStatus(dst, "ward")) {
    delete dst.status.ward; // consumed
    if (STATE.screen === "battle") pushAnim("dmgB", dst.q, dst.r, "WARDED", PAL.purple);
    b.floats.push({ q: dst.q, r: dst.r, text: "WARDED", color: PAL.purple, dy: 0 });
    pushLog(dst.name + "'s ward absorbs the blow.", PAL.purple);
    if (!counter) b.wardedA = true; else b.wardedC = true;
    return; // no damage, no XP from a negated hit
  }
```

And after damage application (non-counter swing only): `if (b.applyStatus && dst.hp > 0) addStatus(dst, b.applyStatus, b.statusTurns);`

- [ ] **Step 2: beginBattle payload**

`beginBattle(attacker, defender, afterDone, opts)` — add the 4th param; in the `STATE.battle = { ... }` literal add `applyStatus: opts && opts.applyStatus, statusTurns: opts ? opts.statusTurns : 0`. All existing call sites pass nothing — unchanged behavior.

- [ ] **Step 3: Bulwark + Ward instant resolution (extend `resolveInstantAbility`)**

```js
  if (ab.key === "bulwark" || ab.key === "ward") {
    const flag = ab.key;
    addStatus(unit, flag, 2); // expires at owner's next turn tick
    for (const n of hexNeighbors(unit.q, unit.r)) {
      const a = unitAt(n.q, n.r);
      if (a && a.owner === unit.owner) addStatus(a, flag, 2);
    }
    pushLog(unit.name + " raises a " + ab.name.toLowerCase() + ".", PAL.purple);
    beep(560, 0.1, "triangle", 0.2);
    return true;
  }
```

- [ ] **Step 4: Enemy-target mode (Ignite, Cinder Breath, Undertow, Dive Mark, Frost Bite)**

In `selectMenuItem`'s ability branch, the `target === "enemy"` case:

```js
    if (ab.target === "enemy") {
      const targets = computeAttackTargets(unit, unit.q, unit.r);
      if (!targets.size) { pushLog("No target in range."); return; }
      STATE.attackTargets = targets;
      STATE.abilityArm = { unit, ab };   // interactAt routes the next target click
      STATE.menu = null;
      return;
    }
```

In `interactAt(q, r)`, at the top of the existing attack-target branch (where a click on `STATE.attackTargets` fires `beginBattle`), route armed abilities first:

```js
    if (STATE.abilityArm && STATE.attackTargets && STATE.attackTargets.has(hexKey(q, r))) {
      const target = unitAt(q, r);
      const { unit: au, ab } = STATE.abilityArm;
      if (target) {
        STATE.abilityArm = null;
        STATE.attackTargets = null;
        au.acted = true; au.cd = ab.cd;
        STATE.undo = null;
        beginBattle(au, target, null, { applyStatus: ab.status, statusTurns: ab.statusTurns });
      }
      return;
    }
```

Esc/cancel must also clear `STATE.abilityArm` (add to `cancelMenu` and the Esc handler alongside the attackTargets clears). Add `abilityArm: null` to the STATE literal and `startNewGame`/`loadGame` transient resets.

- [ ] **Step 5: Blink (tile target)**

`target === "tile"` case in the ability branch:

```js
    if (ab.target === "tile") {
      const tiles = new Set();
      for (const cell of MAP.cells.values()) {
        if (hexDistance(cell, unit) <= 4 && !unitAt(cell.q, cell.r) &&
            !TERRAIN[cell.terrain].blocks && !(TERRAIN[cell.terrain].flyersOnly && !unit.flying)) {
          tiles.add(hexKey(cell.q, cell.r));
        }
      }
      if (!tiles.size) { pushLog("Nowhere to blink."); return; }
      STATE.blinkArm = { unit, ab, tiles };
      STATE.menu = null;
      return;
    }
```

In `interactAt`, before all other branches: if `STATE.blinkArm` and the clicked hex is in `tiles` → `moveUnitTo(unit, q, r)`, ring burst `pushAnim("summon", q, r, "", PAL.purple, "176, 120, 200")`, `unit.acted = true; unit.cd = ab.cd; STATE.undo = null; STATE.blinkArm = null;` and return. Any other click clears `blinkArm`. Render the candidate tiles in `renderOverlays` exactly like the reachable highlight but purple (`rgba(176,120,200,0.28)` fill) when `STATE.blinkArm` is set. Add `blinkArm: null` to STATE + resets.

- [ ] **Step 6: Wire remaining `ability:` data** — cinderling/infernite `ignite`, pyrowyrm/emberdrake `cinderBreath`, mistleviath/leviathan `undertow`, skyharrow/skytyrant `diveMark`, stoneward/colossus `bulwark`, runeward `ward`, hexwisp `blink`, frostmaw `frostBite`.

- [ ] **Step 7: Verify**

```
node --check game.js && bash smoke-test.sh
```

Playwright (`?v=p13#autostart`):

```js
() => {
  STATE.settings.battleScene = false;
  const m0 = STATE.units.find(u => u.owner === 0);
  const cin = makeUnit("cinderling", 0, m0.q + 1, m0.r);
  const foe = makeUnit("stoneward", 1, m0.q + 2, m0.r);
  STATE.units.push(cin, foe);
  beginBattle(cin, foe, null, { applyStatus: "burn", statusTurns: 2 });
  const burned = hasStatus(foe, "burn");
  addStatus(foe, "ward", 2);
  const hp0 = foe.hp;
  beginBattle(cin, foe, null, {});
  return { burned, wardNegated: foe.hp === hp0, wardConsumed: !hasStatus(foe, "ward") };
}
// expect: { burned: true, wardNegated: true, wardConsumed: true }
```

- [ ] **Step 8: Checkoff + commit**

```bash
git add game.js ROADMAP2.md
git commit -m "[v2] 1.3: all 12 abilities — attack payloads, auras, Blink"
```

---

### Task 4 — Milestone 1.4: Ability AI

**Files:**
- Modify: `game.js` — section 18 (`aiScoreInstantAbility`), `aiActUnit` (candidates).
- Modify: `ROADMAP2.md`.

- [ ] **Step 1: Instant-ability scorer (current-tile evaluation — documented simplification: auras/heals are evaluated where the unit stands, not across all reachable tiles)**

```js
// Score firing the unit's instant ability from its CURRENT hex.
// Returns {score} or null. Tuned against the attack scores in aiActUnit
// (a confirmed kill ≈ 30+, a decent attack ≈ 8-15).
function aiScoreInstantAbility(u) {
  const ab = abilityFor(u);
  if (!ab || u.cd > 0 || ab.target !== "none") return null;
  let s = 0;
  if (ab.key === "healPulse") {
    for (const n of hexNeighbors(u.q, u.r)) {
      const a = unitAt(n.q, n.r);
      if (a && a.owner === u.owner && a.hp < a.maxHp * 0.6) s += 12;
    }
  } else if (ab.key === "quake") {
    for (const n of hexNeighbors(u.q, u.r)) {
      const e = unitAt(n.q, n.r);
      if (e && e.owner !== u.owner) s += e.hp <= 4 ? 20 : 9;
    }
    if (s < 18) s = 0; // not worth the action for a single soft hit
  } else if (ab.key === "bulwark" || ab.key === "ward") {
    for (const n of hexNeighbors(u.q, u.r)) {
      const a = unitAt(n.q, n.r);
      if (a && a.owner === u.owner) s += 5;
    }
    s += hasStatus(u, ab.key) ? -99 : 4; // never refresh an active aura
    if (s < 12) s = 0;
  }
  // skitter/galeRush: handled as movement, not scored here (kept out of AI v1)
  return s > 0 ? { score: s } : null;
}
```

- [ ] **Step 2: Candidates in `aiActUnit`**

(a) Attack-flavored abilities: inside the existing (node, target) scoring loop, after `bestAtk` scoring, when `u.cd <= 0` and `abilityFor(u)?.target === "enemy"`, add `+6` to that pair's score and set `useAbility: true` on the candidate object. When executing `attack()`, if `bestAtk.useAbility`, set `u.cd = abilityFor(u).cd` and pass `{ applyStatus: ab.status, statusTurns: ab.statusTurns }` to `beginBattle`.

(b) Instant abilities: after `bestAtk` is computed and before the decision tree picks, compute `const bestInst = aiScoreInstantAbility(u);`. Add a decision-tree rung between the capture rung and the plain-attack rung:

```js
  if (bestInst && (!bestAtk || bestInst.score > bestAtk.score)) {
    const ab = abilityFor(u);
    resolveInstantAbility(u, ab);
    u.cd = ab.cd;
    u.secondMove = false; // AI doesn't take second legs (v1 simplification)
    finish();
    return;
  }
```

- [ ] **Step 3: Verify**

```
node --check game.js && bash smoke-test.sh
```

Playwright soak (`?v=p14#autostart`): run 10 idle-player turns exactly like the v1 AI soak (`endTurn()` loop guarded on `currentPlayer/pendingAI/moveAnim/battle`), with `STATE.settings.battleScene = false`, collecting `window.onerror` into an array. Expect: zero errors, and `STATE.log` containing at least one ability line ("pulses healing light" / "shakes the earth" / "raises a") by turn 10 — the AI summons tidekin/geomaul/stoneward lines often enough that one fires. If none fired, seed the board: give CRIMSON a wounded tidekin pair adjacent to each other and re-run two turns; expect a heal line.

- [ ] **Step 4: Checkoff + commit**

```bash
git add game.js ROADMAP2.md
git commit -m "[v2] 1.4: AI fires abilities — heuristic candidates in aiActUnit"
```

---

### Task 5 — Milestone 1.5: Weather

**Files:**
- Modify: `game.js` — new banner section 19 (weather), `MAPS` defs (`weatherTable`), `computeDamage`, `effectiveMove`, `endTurn`, `startNewGame`, `loadGame`/`saveGame`, `renderTopBar`.
- Modify: `ROADMAP2.md`.

- [ ] **Step 1: Weather core (new banner section 19)**

```js
// =========================================================================
// 19. Weather (v2 1.5)
// =========================================================================
// One global modifier, re-rolled every ~5 turns from the map's table.
// Implemented as reads inside computeDamage/effectiveMove, so the AI and
// the damage forecast understand weather with zero extra code.
const WEATHERS = {
  clear: { name: "Clear",    color: "#8a85a2" },
  rain:  { name: "Rain",     color: "#5aa8d8", atkMul: { hydro: 1.15, pyro: 0.85 } },
  heat:  { name: "Heatwave", color: "#e07050", atkMul: { pyro: 1.15, hydro: 0.85 } },
  gale:  { name: "Gale",     color: "#c8c8d8", rangedMul: 0.8, flyBonus: 1 },
};
const DEFAULT_WEATHER_TABLE = ["clear", "clear", "rain", "heat", "gale"];

function rollWeather(initial) {
  const def = MAPS[STATE.mapIndex] || MAPS[0];
  const table = def.weatherTable || DEFAULT_WEATHER_TABLE;
  const key = initial ? "clear" : table[Math.floor(Math.random() * table.length)];
  const changed = !STATE.weather || STATE.weather.key !== key;
  STATE.weather = { key, turnsLeft: 4 + Math.floor(Math.random() * 3) };
  if (changed && !initial) {
    const w = WEATHERS[key];
    STATE.banner = { text: "WEATHER — " + w.name.toUpperCase(), ttl: 70, color: w.color };
    pushLog("The skies shift: " + w.name + ".", w.color);
  }
}

function weatherNow() { return WEATHERS[(STATE.weather || {}).key] || WEATHERS.clear; }
```

- [ ] **Step 2: Hooks**

`computeDamage` — next to the affinity multiplier:

```js
  const w = weatherNow();
  const wMul = (w.atkMul && w.atkMul[attacker.element] ? w.atkMul[attacker.element] : 1.0)
             * (w.rangedMul && attacker.range >= 2 ? w.rangedMul : 1.0);
```

Multiply `wMul` into the `base` product. `effectiveMove` — add `if (weatherNow().flyBonus && unit.flying) m += weatherNow().flyBonus;`. `endTurn` — after the turn increments (`if (STATE.currentPlayer === 0) STATE.turn++;` block): `if (STATE.currentPlayer === 0 && --STATE.weather.turnsLeft <= 0) rollWeather();`. `startNewGame` — `rollWeather(true);` after map gen. `saveGame`/`loadGame` — add `weather: STATE.weather` to the blob and restore it (default `{key:"clear",turnsLeft:5}` when absent — keeps v1 saves loadable; the formal v2 version bump happens in milestone 2.2). Give two `MAPS` defs flavored tables (tides: rain-heavy `["rain","rain","clear","gale"]`; crags: `["heat","heat","clear","gale"]`).

- [ ] **Step 3: Topbar UI**

In `renderTopBar`, prepend the weather to the right-aligned hint string: `"☼ " + weatherNow().name + "  |  " + ...` colored normally (the string is already inkDim; acceptable). Keep it inside the existing right-aligned text so no layout shifts.

- [ ] **Step 4: Verify**

```
node --check game.js && bash smoke-test.sh
```

Playwright (`?v=p15#autostart`):

```js
() => {
  const m0 = STATE.units.find(u => u.owner === 0);
  const tide = makeUnit("tidekin", 0, m0.q + 1, m0.r);
  const cin  = makeUnit("cinderling", 1, m0.q + 2, m0.r);
  STATE.units.push(tide, cin);
  STATE.weather = { key: "rain", turnsLeft: 5 };
  const wet = forecastBattle(tide, cin);   // hydro buffed in rain
  STATE.weather = { key: "clear", turnsLeft: 5 };
  const dry = forecastBattle(tide, cin);
  const wisp = makeUnit("galewisp", 0, m0.q, m0.r + 1); STATE.units.push(wisp);
  STATE.weather = { key: "gale", turnsLeft: 5 };
  const galeMove = effectiveMove(wisp);
  return { rainBuffs: wet.hi > dry.hi, galeMove, baseMove: wisp.move };
}
// expect: { rainBuffs: true, galeMove: baseMove + 1, ... }
```

- [ ] **Step 5: Checkoff + commit, plus Phase 1 handoff block in ROADMAP2.md**

```bash
git add game.js ROADMAP2.md
git commit -m "[v2] 1.5: weather — rain/heat/gale modifiers, topbar; Phase 1 done"
```

---

## Plan self-review notes

- Spec coverage: 1.1 status engine ✓ (both flavors), 1.2/1.3 all 12 abilities ✓ (Skitter/Gale Rush simplified to second-move-only legs — recorded in the spec's "tune freely" license), 1.4 AI ✓ (current-tile evaluation simplification documented), 1.5 weather ✓ (all four types, per-map tables, forecast/AI-free hooks).
- Type consistency: `u.cd` (number), `u.status` (map), `u.secondMove` (bool), `STATE.abilityArm`/`STATE.blinkArm` ({unit, ab[, tiles]}) used consistently across tasks; `beginBattle(attacker, defender, afterDone, opts)` signature introduced in Task 3 and used in Task 4.
- Save compatibility: new unit fields default-undefined-safe; weather defaulted on load; formal blob version bump deferred to milestone 2.2 per spec.
