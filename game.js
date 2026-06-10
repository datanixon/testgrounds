// Wraithspire: Summoner's War
// Hex-based turn strategy with cinematic battle cutaways and procedural synth score.
// All units, names, lore, sprites, and music are original work for this project.
//
// ---------------------------------------------------------------------------
// Sections:
//   1. Constants & palette
//   2. Hex math (pointy-top axial)
//   3. Terrain & map generation
//   4. Unit & master definitions
//   5. Game state container
//   6. Pathfinding & action queries
//   7. Combat resolution (queues battle scene)
//   8. AI opponent
//   9. Procedural sprite drawing (map + battle)
//  10. Battle scene state machine & renderer
//  11. Map rendering pipeline
//  12. Input & action menus
//  13. Turn / phase machinery
//  14. UI screens (title, win/lose, banners)
//  15. Audio engine (SFX + 80s synth music loop)
//  16. Boot, resize, main loop

// =========================================================================
// 1. Constants & palette
// =========================================================================

const CANVAS_W = 1280;
const CANVAS_H = 800;
const TOPBAR_H = 48;
const SIDEBAR_W = 320;
const SIDEBAR_X = CANVAS_W - SIDEBAR_W;
const MAP_W = SIDEBAR_X;
const MAP_H = CANVAS_H - TOPBAR_H;

const HEX_SIZE = 36;
const HEX_W = Math.sqrt(3) * HEX_SIZE;
const HEX_H = 2 * HEX_SIZE;
const HEX_STEP_X = HEX_W;
const HEX_STEP_Y = HEX_SIZE * 1.5;

const COLS = 14;
const ROWS = 12;

const PAL = {
  bg: "#050409",
  panel: "#13111f",
  panelLight: "#1f1c30",
  ink: "#e8e6d8",
  inkDim: "#8a85a2",
  inkFaint: "#3a3650",
  gold: "#f0c674",
  red: "#cc4a4a",
  blue: "#5aa8d8",
  green: "#7ac075",
  purple: "#a07acd",

  plain: "#3a5a3e",
  plainAlt: "#456a48",
  forest: "#1f3e25",
  forestAlt: "#28522e",
  hill: "#6a5a3a",
  hillAlt: "#7a6a44",
  mountain: "#4a4452",
  mountainAlt: "#5a5462",
  water: "#264a78",
  waterAlt: "#326090",
  tower: "#6a5a72",
  towerCap: "#7a6a82",
  castle: "#9a8a52",

  p0: "#5aa8d8",
  p0Dark: "#1f4870",
  p0Trim: "#bce0ff",
  p1: "#cc6a4a",
  p1Dark: "#6a2818",
  p1Trim: "#ffc4a0",
  neutral: "#7a7080",
  neutralDark: "#4a4458",
};

const PLAYERS = [
  { id: 0, name: "AZURE",   color: PAL.p0, dark: PAL.p0Dark, trim: PAL.p0Trim, isAI: false },
  { id: 1, name: "CRIMSON", color: PAL.p1, dark: PAL.p1Dark, trim: PAL.p1Trim, isAI: true },
];

// =========================================================================
// 2. Hex math (pointy-top, axial coords q, r)
// =========================================================================

function axialToPixel(q, r) {
  const x = HEX_SIZE * Math.sqrt(3) * (q + r / 2);
  const y = HEX_SIZE * 1.5 * r;
  return { x: x + HEX_W / 2 + 6, y: y + HEX_H / 2 + 6 };
}

function pixelToAxial(px, py) {
  px -= HEX_W / 2 + 6;
  py -= HEX_H / 2 + 6;
  const q = (Math.sqrt(3) / 3 * px - 1 / 3 * py) / HEX_SIZE;
  const r = (2 / 3 * py) / HEX_SIZE;
  return roundAxial(q, r);
}

function roundAxial(q, r) {
  const s = -q - r;
  let rq = Math.round(q);
  let rr = Math.round(r);
  let rs = Math.round(s);
  const dq = Math.abs(rq - q);
  const dr = Math.abs(rr - r);
  const ds = Math.abs(rs - s);
  if (dq > dr && dq > ds) rq = -rr - rs;
  else if (dr > ds) rr = -rq - rs;
  return { q: rq, r: rr };
}

const HEX_DIRS = [
  { q: +1, r:  0 }, { q: +1, r: -1 }, { q:  0, r: -1 },
  { q: -1, r:  0 }, { q: -1, r: +1 }, { q:  0, r: +1 },
];

function hexNeighbors(q, r) {
  return HEX_DIRS.map(d => ({ q: q + d.q, r: r + d.r }));
}

function hexDistance(a, b) {
  return (Math.abs(a.q - b.q) + Math.abs(a.q + a.r - b.q - b.r) + Math.abs(a.r - b.r)) / 2;
}

function inBounds(q, r) { return MAP.cells.has(hexKey(q, r)); }
function hexKey(q, r) { return q + "," + r; }

function hexCorner(cx, cy, i) {
  const angle = Math.PI / 180 * (60 * i - 30);
  return { x: cx + HEX_SIZE * Math.cos(angle), y: cy + HEX_SIZE * Math.sin(angle) };
}

// =========================================================================
// 3. Terrain & map
// =========================================================================

const TERRAIN = {
  plain:    { name: "Plain",    moveCost: 1, def: 0, color: PAL.plain,    alt: PAL.plainAlt,    blocks: false },
  forest:   { name: "Forest",   moveCost: 2, def: 2, color: PAL.forest,   alt: PAL.forestAlt,   blocks: false },
  hill:     { name: "Hill",     moveCost: 2, def: 2, color: PAL.hill,     alt: PAL.hillAlt,     blocks: false },
  mountain: { name: "Mountain", moveCost: 4, def: 4, color: PAL.mountain, alt: PAL.mountainAlt, blocks: false, flyersOnly: true },
  water:    { name: "Tide",     moveCost: 99,def: 0, color: PAL.water,    alt: PAL.waterAlt,    blocks: true, flyersOnly: true },
  tower:    { name: "Spire",    moveCost: 1, def: 3, color: PAL.tower,    alt: PAL.towerCap,    blocks: false, capturable: true },
  castle:   { name: "Citadel",  moveCost: 1, def: 4, color: PAL.castle,   alt: PAL.castle,      blocks: false, capturable: false },
};

const MAP = {
  cells: new Map(),
  towers: [],
  castles: [],
};

function generateMap(seed) {
  let rng = mulberry32(seed);
  MAP.cells.clear();
  MAP.towers.length = 0;
  MAP.castles.length = 0;

  for (let r = 0; r < ROWS; r++) {
    const offset = -Math.floor(r / 2);
    for (let q = offset; q < offset + COLS; q++) {
      MAP.cells.set(hexKey(q, r), { q, r, terrain: "plain", owner: null });
    }
  }

  const cells = [...MAP.cells.values()];
  const pick = () => cells[Math.floor(rng() * cells.length)];

  const scatter = (kind, count) => {
    for (let i = 0; i < count; i++) {
      const c = pick();
      if (c.terrain !== "plain") { i--; continue; }
      c.terrain = kind;
    }
  };

  for (let i = 0; i < 4; i++) {
    let c = pick();
    const len = 2 + Math.floor(rng() * 3);
    for (let j = 0; j < len; j++) {
      if (!c) break;
      c.terrain = "mountain";
      const nbrs = hexNeighbors(c.q, c.r).filter(n => inBounds(n.q, n.r));
      c = nbrs.length ? cellAt(nbrs[Math.floor(rng() * nbrs.length)]) : null;
    }
  }

  for (let i = 0; i < 3; i++) {
    let c = pick();
    if (!c) continue;
    const lake = [c];
    while (lake.length < 4 + Math.floor(rng() * 3)) {
      const base = lake[Math.floor(rng() * lake.length)];
      const nbrs = hexNeighbors(base.q, base.r)
        .filter(n => inBounds(n.q, n.r))
        .map(n => cellAt(n))
        .filter(n => n && n.terrain === "plain" && !lake.includes(n));
      if (!nbrs.length) break;
      lake.push(nbrs[Math.floor(rng() * nbrs.length)]);
    }
    for (const c2 of lake) c2.terrain = "water";
  }

  scatter("forest", 22);
  scatter("hill", 14);

  const castleA = cellAt({ q: 0, r: 1 }) || cellAt({ q: 1, r: 1 });
  const castleB = cellAt({ q: COLS - 3 - Math.floor((ROWS - 2) / 2), r: ROWS - 2 });
  if (castleA) {
    clearAround(castleA);
    castleA.terrain = "castle";
    castleA.owner = 0;
    MAP.castles.push(castleA);
  }
  if (castleB) {
    clearAround(castleB);
    castleB.terrain = "castle";
    castleB.owner = 1;
    MAP.castles.push(castleB);
  }

  const towerCount = 5;
  let placed = 0, guard = 0;
  while (placed < towerCount && guard++ < 500) {
    const c = pick();
    if (!c || c.terrain !== "plain") continue;
    if (hexDistance(c, castleA) < 3 || hexDistance(c, castleB) < 3) continue;
    if (MAP.towers.some(t => hexDistance(t, c) < 2)) continue;
    c.terrain = "tower";
    c.owner = null;
    MAP.towers.push(c);
    placed++;
  }
}

function cellAt(qr) { return MAP.cells.get(hexKey(qr.q, qr.r)); }

function clearAround(c) {
  c.terrain = "plain";
  for (const n of hexNeighbors(c.q, c.r)) {
    const nc = cellAt(n);
    if (nc && (nc.terrain === "mountain" || nc.terrain === "water")) nc.terrain = "plain";
  }
}

function mulberry32(a) {
  return function () {
    a |= 0; a = a + 0x6D2B79F5 | 0;
    let t = a;
    t = Math.imul(t ^ t >>> 15, t | 1);
    t ^= t + Math.imul(t ^ t >>> 7, t | 61);
    return ((t ^ t >>> 14) >>> 0) / 4294967296;
  };
}

// =========================================================================
// 4. Unit & master definitions
// =========================================================================

const ELEMENT = {
  pyro:   { name: "Pyro",   color: "#e07050", short: "PYR" },
  hydro:  { name: "Hydro",  color: "#5aa8d8", short: "HYD" },
  terra:  { name: "Terra",  color: "#9a7a4a", short: "TER" },
  zephyr: { name: "Zephyr", color: "#c8c8d8", short: "ZEP" },
  arcane: { name: "Arcane", color: "#b078c8", short: "ARC" },
};

const ELEM_MATRIX = {
  pyro:   { pyro: 1.0, hydro: 0.7, terra: 1.0, zephyr: 1.3, arcane: 1.0 },
  hydro:  { pyro: 1.3, hydro: 1.0, terra: 0.7, zephyr: 1.0, arcane: 1.0 },
  terra:  { pyro: 1.0, hydro: 1.3, terra: 1.0, zephyr: 0.7, arcane: 1.0 },
  zephyr: { pyro: 0.7, hydro: 1.0, terra: 1.3, zephyr: 1.0, arcane: 1.0 },
  arcane: { pyro: 1.1, hydro: 1.1, terra: 1.1, zephyr: 1.1, arcane: 1.0 },
};

// Element ↔ terrain affinity: a unit attacking FROM a terrain its element
// resonates with deals +20% damage. Adds a terrain dimension to positioning
// on top of the element rock-paper-scissors above.
const AFFINITY_MULT = 1.2;
const ELEM_AFFINITY = {
  pyro:   { terrains: ["hill", "mountain"], label: "scorching heights" },
  hydro:  { terrains: ["water", "forest"],  label: "drenched ground" },
  terra:  { terrains: ["mountain", "hill"], label: "raw bedrock" },
  zephyr: { terrains: ["plain", "mountain"], label: "open skies" },
  arcane: { terrains: ["tower", "castle"],  label: "ley nexus" },
};
// Returns the affinity record if `element` is empowered on `terrain`, else null.
function affinityFor(element, terrain) {
  const a = ELEM_AFFINITY[element];
  return a && a.terrains.indexOf(terrain) >= 0 ? a : null;
}
// Elements empowered by a given terrain (reverse lookup, for tile tooltips).
function elementsEmpoweredBy(terrain) {
  return Object.keys(ELEM_AFFINITY).filter(e => ELEM_AFFINITY[e].terrains.indexOf(terrain) >= 0);
}

const UNIT_TYPES = {
  cinderling:  { name: "Cinderling",  element: "pyro",   maxHp: 12, move: 4, range: 1, power: 5, def: 1, cost: 6,  flying: false, sprite: "imp",      attack: "melee",  evolvesTo: "infernite" },
  pyrowyrm:    { name: "Pyrowyrm",    element: "pyro",   maxHp: 18, move: 3, range: 2, power: 7, def: 2, cost: 12, flying: false, sprite: "wyrm",     attack: "breath", evolvesTo: "emberdrake" },
  tidekin:     { name: "Tidekin",     element: "hydro",  maxHp: 14, move: 4, range: 1, power: 5, def: 2, cost: 7,  flying: false, sprite: "merfolk",  attack: "melee",  evolvesTo: "tidelord" },
  mistleviath: { name: "Mistlevy",    element: "hydro",  maxHp: 20, move: 3, range: 2, power: 6, def: 3, cost: 14, flying: false, sprite: "serpent",  attack: "spray",  evolvesTo: "leviathan" },
  stoneward:   { name: "Stoneward",   element: "terra",  maxHp: 22, move: 2, range: 1, power: 5, def: 4, cost: 8,  flying: false, sprite: "golem",    attack: "melee",  evolvesTo: "colossus" },
  geomaul:     { name: "Geomaul",     element: "terra",  maxHp: 26, move: 2, range: 1, power: 9, def: 4, cost: 16, flying: false, sprite: "ogre",     attack: "melee",  evolvesTo: "earthbreaker" },
  galewisp:    { name: "Galewisp",    element: "zephyr", maxHp: 10, move: 5, range: 2, power: 4, def: 1, cost: 7,  flying: true,  sprite: "wisp",     attack: "spark",  evolvesTo: "stormwisp" },
  skyharrow:   { name: "Skyharrow",   element: "zephyr", maxHp: 16, move: 4, range: 2, power: 7, def: 2, cost: 13, flying: true,  sprite: "raptor",   attack: "dive",   evolvesTo: "skytyrant" },

  // Evolved forms (terminal tier; not directly summonable). Reached when a
  // level-4+ unit starts its turn on an owned tower/castle. Sprites are stubs
  // that reuse the base form's sprite id (real art lands in milestone 5.1).
  infernite:    { name: "Infernite",    element: "pyro",   maxHp: 22, move: 4, range: 1, power: 9,  def: 3, cost: 18, flying: false, sprite: "imp",     attack: "melee",  evolved: true },
  emberdrake:   { name: "Emberdrake",   element: "pyro",   maxHp: 30, move: 3, range: 2, power: 11, def: 4, cost: 26, flying: false, sprite: "wyrm",    attack: "breath", evolved: true },
  tidelord:     { name: "Tidelord",     element: "hydro",  maxHp: 24, move: 4, range: 1, power: 9,  def: 4, cost: 18, flying: false, sprite: "merfolk", attack: "melee",  evolved: true },
  leviathan:    { name: "Leviathan",    element: "hydro",  maxHp: 32, move: 3, range: 2, power: 10, def: 5, cost: 28, flying: false, sprite: "serpent", attack: "spray",  evolved: true },
  colossus:     { name: "Colossus",     element: "terra",  maxHp: 36, move: 2, range: 1, power: 9,  def: 6, cost: 20, flying: false, sprite: "golem",   attack: "melee",  evolved: true },
  earthbreaker: { name: "Earthbreaker", element: "terra",  maxHp: 42, move: 2, range: 1, power: 14, def: 6, cost: 30, flying: false, sprite: "ogre",    attack: "melee",  evolved: true },
  stormwisp:    { name: "Stormwisp",    element: "zephyr", maxHp: 18, move: 5, range: 2, power: 8,  def: 2, cost: 18, flying: true,  sprite: "wisp",    attack: "spark",  evolved: true },
  skytyrant:    { name: "Skytyrant",    element: "zephyr", maxHp: 26, move: 4, range: 2, power: 11, def: 3, cost: 24, flying: true,  sprite: "raptor",  attack: "dive",   evolved: true },
};

const SUMMON_LIST = ["cinderling", "tidekin", "stoneward", "galewisp", "pyrowyrm", "mistleviath", "geomaul", "skyharrow"];

const MASTER_TEMPLATE = {
  name: "Archon", element: "arcane", maxHp: 40, maxMp: 30, move: 3, range: 1, power: 7, def: 3,
  mpRegen: 4, flying: false, sprite: "archon", attack: "bolt",
};

let nextUnitId = 1;

function makeUnit(typeKey, owner, q, r) {
  const t = UNIT_TYPES[typeKey];
  return {
    id: nextUnitId++,
    typeKey, name: t.name, element: t.element,
    owner, q, r,
    hp: t.maxHp, maxHp: t.maxHp,
    move: t.move, range: t.range, power: t.power, def: t.def,
    flying: t.flying, sprite: t.sprite, attack: t.attack,
    level: 1, xp: 0,
    acted: false, isMaster: false,
  };
}

function makeMaster(owner, q, r) {
  return {
    id: nextUnitId++,
    typeKey: "master", name: MASTER_TEMPLATE.name + " of " + PLAYERS[owner].name,
    element: MASTER_TEMPLATE.element,
    owner, q, r,
    hp: MASTER_TEMPLATE.maxHp, maxHp: MASTER_TEMPLATE.maxHp,
    mp: 14, maxMp: MASTER_TEMPLATE.maxMp,
    move: MASTER_TEMPLATE.move, range: MASTER_TEMPLATE.range,
    power: MASTER_TEMPLATE.power, def: MASTER_TEMPLATE.def,
    mpRegen: MASTER_TEMPLATE.mpRegen,
    flying: false, sprite: "archon", attack: "bolt",
    level: 1, xp: 0,
    acted: false, isMaster: true,
  };
}

// ---- XP & leveling (section 4 cont.) ----
// Units earn XP equal to damage dealt in battle, plus a bonus on a kill.
// Five levels; each level-up bumps maxHp/power/def and fully restores HP
// (classic Master of Monsters behaviour). Stats live on the unit instance so
// computeDamage picks the growth up automatically.
const MAX_LEVEL = 5;
const KILL_XP_BONUS = 10;

// XP required to advance FROM `level` to the next (12, 20, 28, 36).
function xpToNext(level) { return level >= MAX_LEVEL ? Infinity : 12 + (level - 1) * 8; }

function applyLevelGrowth(unit) {
  unit.maxHp += unit.isMaster ? 6 : 4;
  unit.power += 1;
  unit.def += 1;
  unit.hp = unit.maxHp; // full restore on level-up
}

// Award XP; resolves multi-level-ups. Returns levels gained this call.
function gainXp(unit, amount) {
  if (!unit) return 0;
  unit.level = unit.level || 1;
  unit.xp = unit.xp || 0;
  if (amount <= 0 || unit.level >= MAX_LEVEL) return 0;
  unit.xp += amount;
  let gained = 0;
  while (unit.level < MAX_LEVEL && unit.xp >= xpToNext(unit.level)) {
    unit.xp -= xpToNext(unit.level);
    unit.level++;
    applyLevelGrowth(unit);
    gained++;
  }
  if (unit.level >= MAX_LEVEL) unit.xp = 0;
  return gained;
}

// ---- Evolution ----
// A level-4+ unit that starts its turn on an owned tower/castle evolves into
// its terminal form. Evolved base stats absorb the unit's accumulated level
// growth so leveling is never wasted, and the unit is fully restored.
const EVOLVE_LEVEL = 4;

function evolveUnit(unit) {
  const base = UNIT_TYPES[unit.typeKey];
  if (!base || !base.evolvesTo) return false;
  const evo = UNIT_TYPES[base.evolvesTo];
  if (!evo) return false;
  const lvlBonus = (unit.level || 1) - 1;
  unit.typeKey = base.evolvesTo;
  unit.name = evo.name;
  unit.element = evo.element;
  unit.move = evo.move;
  unit.range = evo.range;
  unit.flying = evo.flying;
  unit.sprite = evo.sprite;
  unit.attack = evo.attack;
  unit.maxHp = evo.maxHp + lvlBonus * 4;
  unit.power = evo.power + lvlBonus;
  unit.def = evo.def + lvlBonus;
  unit.hp = unit.maxHp; // full restore on evolution
  unit.evolved = true;
  return true;
}

function tryEvolve(unit, cell) {
  if (unit.isMaster || unit.evolved) return false;
  if ((unit.level || 1) < EVOLVE_LEVEL) return false;
  if (!cell || cell.owner !== unit.owner) return false;
  if (cell.terrain !== "tower" && cell.terrain !== "castle") return false;
  if (!UNIT_TYPES[unit.typeKey] || !UNIT_TYPES[unit.typeKey].evolvesTo) return false;
  const oldName = unit.name;
  if (!evolveUnit(unit)) return false;
  pushLog(oldName + " evolves into " + unit.name + "!");
  pushAnim("evolve", unit.q, unit.r, "EVOLVED!", PAL.gold);
  beep(523, 0.09, "triangle", 0.22);
  setTimeout(() => beep(659, 0.09, "triangle", 0.22), 100);
  setTimeout(() => beep(880, 0.16, "triangle", 0.22), 200);
  return true;
}

// =========================================================================
// 5. Game state
// =========================================================================

const STATE = {
  screen: "title",   // "title" | "play" | "battle" | "gameover"
  turn: 0,
  currentPlayer: 0,
  units: [],
  selected: null,
  reachable: null,
  attackTargets: null,
  menu: null,
  hover: null,
  banner: null,
  log: [],
  winner: null,
  cam: { x: 0, y: 0 },
  pendingAI: false,
  animations: [],
  battle: null,      // active battle scene; see startBattle()
  music: { wanted: true, started: false, trackIndex: 0 },
};

function startNewGame() {
  nextUnitId = 1;
  generateMap(Math.floor(Math.random() * 1e9));
  STATE.units = [];
  const cA = MAP.castles[0];
  const cB = MAP.castles[1];
  STATE.units.push(makeMaster(0, cA.q, cA.r));
  STATE.units.push(makeMaster(1, cB.q, cB.r));
  STATE.turn = 1;
  STATE.currentPlayer = 0;
  STATE.selected = null;
  STATE.reachable = null;
  STATE.attackTargets = null;
  STATE.menu = null;
  STATE.banner = { text: PLAYERS[0].name + " — TURN " + STATE.turn, ttl: 90 };
  STATE.log = [];
  STATE.winner = null;
  STATE.screen = "play";
  STATE.pendingAI = false;
  STATE.battle = null;
  for (const u of STATE.units) u.acted = false;
  pushLog("Battle begins on the Wraithspire frontier.");
  centerCameraOn(masterOf(0));
}

function unitAt(q, r) {
  return STATE.units.find(u => u.q === q && u.r === r && u.hp > 0);
}

function aliveUnits(owner) {
  return STATE.units.filter(u => u.hp > 0 && u.owner === owner);
}

function masterOf(owner) {
  return STATE.units.find(u => u.isMaster && u.owner === owner && u.hp > 0);
}

function pushLog(line) {
  STATE.log.unshift(line);
  if (STATE.log.length > 40) STATE.log.length = 40;
}

function centerCameraOn(unit) {
  if (!unit) return;
  const p = axialToPixel(unit.q, unit.r);
  STATE.cam.x = Math.max(MAP_W - mapPixelWidth(), Math.min(0, MAP_W / 2 - p.x));
  STATE.cam.y = Math.max(MAP_H - mapPixelHeight(), Math.min(0, MAP_H / 2 - p.y));
}

// =========================================================================
// 6. Pathfinding & action queries
// =========================================================================

function moveCostFor(unit, cell) {
  if (!cell) return Infinity;
  const t = TERRAIN[cell.terrain];
  if (t.blocks && !unit.flying) return Infinity;
  if (cell.terrain === "mountain" && !unit.flying) return Infinity;
  if (unit.flying) return 1;
  return t.moveCost;
}

function computeReachable(unit) {
  const out = new Map();
  const start = hexKey(unit.q, unit.r);
  out.set(start, { cost: 0, prev: null, q: unit.q, r: unit.r });
  const frontier = [{ q: unit.q, r: unit.r, cost: 0 }];
  while (frontier.length) {
    frontier.sort((a, b) => a.cost - b.cost);
    const cur = frontier.shift();
    for (const n of hexNeighbors(cur.q, cur.r)) {
      if (!inBounds(n.q, n.r)) continue;
      const cell = cellAt(n);
      const blocker = unitAt(n.q, n.r);
      if (blocker && blocker.owner !== unit.owner) continue;
      const step = moveCostFor(unit, cell);
      if (!isFinite(step)) continue;
      const newCost = cur.cost + step;
      if (newCost > unit.move) continue;
      const key = hexKey(n.q, n.r);
      const existing = out.get(key);
      if (!existing || existing.cost > newCost) {
        out.set(key, { cost: newCost, prev: hexKey(cur.q, cur.r), q: n.q, r: n.r });
        frontier.push({ q: n.q, r: n.r, cost: newCost });
      }
    }
  }
  for (const [k, v] of out) {
    const u = unitAt(v.q, v.r);
    if (u && !(v.q === unit.q && v.r === unit.r)) out.delete(k);
  }
  return out;
}

function computeAttackTargets(unit, fromQ, fromR) {
  const set = new Set();
  for (const u of STATE.units) {
    if (u.hp <= 0) continue;
    if (u.owner === unit.owner) continue;
    const d = hexDistance({ q: fromQ, r: fromR }, { q: u.q, r: u.r });
    if (d <= unit.range && d >= 1) set.add(hexKey(u.q, u.r));
  }
  return set;
}

function canCapture(unit, cell) {
  if (!unit.isMaster) return false;
  if (!cell) return false;
  if (cell.terrain !== "tower") return false;
  return cell.owner !== unit.owner;
}

// =========================================================================
// 7. Combat resolution (queues battle scene)
// =========================================================================

function computeDamage(attacker, defender) {
  const aCell = cellAt({ q: attacker.q, r: attacker.r });
  const dCell = cellAt({ q: defender.q, r: defender.r });
  const aTDef = TERRAIN[aCell.terrain].def;
  const dTDef = TERRAIN[dCell.terrain].def;
  const elemMul = ELEM_MATRIX[attacker.element][defender.element];
  const aff = affinityFor(attacker.element, aCell.terrain);
  const affMul = aff ? AFFINITY_MULT : 1.0;
  const raw = attacker.power * (attacker.hp / attacker.maxHp * 0.5 + 0.5);
  const mit = defender.def + dTDef * 0.5;
  let dmg = Math.max(1, Math.round(raw * elemMul * affMul - mit * 0.6));
  dmg = Math.max(1, dmg + Math.floor(Math.random() * 3) - 1);
  return { dmg, elemMul, affMul, hasAffinity: !!aff, aTDef, dTDef };
}

// Begins an attack: computes both swings up front, then opens the battle
// scene which will apply damage at impact frames and resume play on outro.
function beginBattle(attacker, defender, afterDone) {
  const a1 = computeDamage(attacker, defender);
  const willDie1 = defender.hp - a1.dmg <= 0;

  let a2 = null, willDie2 = false;
  if (!willDie1) {
    const d = hexDistance({ q: attacker.q, r: attacker.r }, { q: defender.q, r: defender.r });
    if (d <= defender.range && d >= 1) {
      a2 = computeDamage(defender, attacker);
      a2.dmg = Math.max(1, Math.round(a2.dmg * 0.8));
      willDie2 = attacker.hp - a2.dmg <= 0;
    }
  }

  STATE.battle = {
    attacker, defender,
    aDmg: a1.dmg, aElem: a1.elemMul,
    cDmg: a2 ? a2.dmg : 0, cElem: a2 ? a2.elemMul : 0,
    hasCounter: !!a2,
    willDieDef: willDie1,
    willDieAtk: willDie2,
    phase: "intro",
    phaseFrame: 0,
    shake: 0,
    flash: 0,
    applied1: false,
    applied2: false,
    afterDone,
    arenaSeed: Math.floor(Math.random() * 1e6),
  };
  STATE.screen = "battle";
  musicDuck(0.35); // dim music during battle
}

function endBattleAndResume() {
  const b = STATE.battle;
  STATE.battle = null;
  STATE.screen = "play";
  musicDuck(1);
  checkWinCondition();
  if (b && b.afterDone) b.afterDone();
}

function checkWinCondition() {
  for (const p of PLAYERS) {
    const m = masterOf(p.id);
    if (!m) {
      STATE.winner = 1 - p.id;
      STATE.screen = "gameover";
      pushLog(PLAYERS[STATE.winner].name + " is victorious!");
      beep(440, 0.2, "triangle", 0.25);
      setTimeout(() => beep(660, 0.3, "triangle", 0.25), 200);
      return;
    }
  }
}

// =========================================================================
// 8. AI opponent
// =========================================================================

function aiTakeTurn() {
  const owner = STATE.currentPlayer;
  const myUnits = aliveUnits(owner).filter(u => !u.acted);
  myUnits.sort((a, b) => (a.isMaster ? 1 : 0) - (b.isMaster ? 1 : 0));
  const enemyMaster = masterOf(1 - owner);
  if (!enemyMaster) { endTurn(); return; }
  const queue = [...myUnits];

  function step() {
    if (STATE.screen === "gameover") return;
    // Wait for any active battle to finish before advancing.
    if (STATE.screen === "battle") { setTimeout(step, 120); return; }
    if (!queue.length) {
      const master = masterOf(owner);
      if (master && master.mp >= 6) aiTrySummons(master);
      endTurn();
      return;
    }
    const u = queue.shift();
    if (u.hp <= 0) { step(); return; }
    aiActUnit(u, enemyMaster, step);
  }
  setTimeout(step, 600);
}

function aiActUnit(u, enemyMaster, done) {
  const reach = computeReachable(u);

  if (u.isMaster) {
    let bestTower = null, bestTowerCost = Infinity;
    for (const t of MAP.towers) {
      if (t.owner === u.owner) continue;
      const k = hexKey(t.q, t.r);
      const node = reach.get(k);
      if (!node) continue;
      const threat = enemyAdjacentThreat(t.q, t.r, u.owner);
      if (threat > u.hp * 0.6) continue;
      if (node.cost < bestTowerCost) { bestTower = t; bestTowerCost = node.cost; }
    }
    if (bestTower) {
      moveUnitTo(u, bestTower.q, bestTower.r);
      const cell = cellAt(bestTower);
      if (cell && cell.terrain === "tower" && cell.owner !== u.owner) {
        cell.owner = u.owner;
        pushLog(u.name + " claims a spire.");
        beep(520, 0.12, "triangle", 0.18);
      }
      u.acted = true;
      setTimeout(done, 260);
      return;
    }
  }

  let best = null;
  for (const [k, node] of reach) {
    const targets = computeAttackTargets(u, node.q, node.r);
    for (const tk of targets) {
      const enemy = STATE.units.find(e => hexKey(e.q, e.r) === tk && e.hp > 0);
      if (!enemy) continue;
      const elemMul = ELEM_MATRIX[u.element][enemy.element];
      const expected = u.power * elemMul - enemy.def * 0.6;
      const killBonus = expected >= enemy.hp ? 25 : 0;
      const masterBonus = enemy.isMaster ? 18 : 0;
      const distAfter = hexDistance({ q: node.q, r: node.r }, enemyMaster);
      const score = expected + killBonus + masterBonus - distAfter * 0.5;
      if (!best || score > best.score) best = { score, moveTo: node, target: enemy };
    }
  }

  if (best) {
    moveUnitTo(u, best.moveTo.q, best.moveTo.r);
    u.acted = true;
    beginBattle(u, best.target, () => setTimeout(done, 400));
    return;
  }

  let bestStep = null, bestDist = Infinity;
  for (const [k, node] of reach) {
    if (unitAt(node.q, node.r) && !(node.q === u.q && node.r === u.r)) continue;
    const d = hexDistance({ q: node.q, r: node.r }, enemyMaster);
    if (d < bestDist) { bestDist = d; bestStep = node; }
  }
  if (bestStep) moveUnitTo(u, bestStep.q, bestStep.r);
  u.acted = true;
  setTimeout(done, 260);
}

function enemyAdjacentThreat(q, r, owner) {
  let total = 0;
  for (const n of hexNeighbors(q, r)) {
    const u = unitAt(n.q, n.r);
    if (u && u.owner !== owner) total += u.power;
  }
  return total;
}

function aiTrySummons(master) {
  let attempts = 4;
  while (attempts-- > 0 && master.mp >= 6) {
    const affordable = SUMMON_LIST.filter(k => UNIT_TYPES[k].cost <= master.mp);
    if (!affordable.length) break;
    const choice = affordable[Math.floor(Math.random() * affordable.length)];
    const slot = findSummonSlot(master);
    if (!slot) break;
    master.mp -= UNIT_TYPES[choice].cost;
    const u = makeUnit(choice, master.owner, slot.q, slot.r);
    u.acted = true;
    STATE.units.push(u);
    pushLog(master.name + " summons " + u.name + ".");
    beep(660, 0.08, "triangle", 0.18);
  }
}

function findSummonSlot(master) {
  for (const n of hexNeighbors(master.q, master.r)) {
    if (!inBounds(n.q, n.r)) continue;
    const cell = cellAt(n);
    if (!cell) continue;
    if (TERRAIN[cell.terrain].blocks) continue;
    if (cell.terrain === "mountain") continue;
    if (unitAt(n.q, n.r)) continue;
    return n;
  }
  return null;
}

// =========================================================================
// 9. Procedural sprite drawing (map + battle portraits)
// =========================================================================

// drawMapSprite: small map-scale sprite (~24px area).
function drawMapSprite(ctx, unit, cx, cy, t) {
  const player = PLAYERS[unit.owner];
  const color = player.color, dark = player.dark, trim = player.trim;
  ctx.save();
  ctx.translate(cx, cy);
  const bob = Math.sin(t / 16 + cx) * 1.0;
  ctx.translate(0, bob);

  const px = (x, y, w, h, fill) => { ctx.fillStyle = fill; ctx.fillRect(x, y, w, h); };

  // NOTE: every branch in this function MUST round-trip through the
  // ctx.restore() at the bottom. A missing restore here leaves the canvas
  // transformed for whatever draws next (HP bars, the next unit, eventually
  // the topbar) — that bug previously offset master HP bars by one hex and
  // pushed the CRIMSON archon off the grid.
  if (unit.isMaster) {
    // Player-specific archon silhouette
    if (unit.owner === 0) {
      // AZURE: round-hat archon, soft curves, crescent staff
      px(-10, -16, 20, 6, dark);                  // wide hat brim
      px(-8, -22, 16, 6, color);                  // round crown
      px(-2, -19, 4, 2, trim);                    // crystal
      px(-4, -10, 8, 3, trim);                    // eye band
      px(-3, -9, 1, 1, "#fff");                   // eye glint
      px(2, -9, 1, 1, "#fff");
      px(-10, -3, 20, 14, dark);                  // robe
      px(-8, -1, 16, 10, color);                  // robe inner
      px(-6, 4, 12, 7, dark);                     // sash
      px(-2, 11, 4, 3, trim);                     // belt jewel
      px(-12, -6, 2, 18, "#aaa");                 // staff shaft
      px(-13, -10, 4, 4, trim);                   // crescent top
      px(-13, -10, 1, 3, dark);
    } else {
      // CRIMSON: spiked-hat archon, sharp edges, flame staff
      px(-10, -16, 20, 4, dark);                  // pointed brim
      // pointed crown
      px(-8, -22, 16, 6, color);
      px(-2, -25, 4, 3, color);
      px(-1, -27, 2, 2, trim);                    // tip jewel
      px(-4, -10, 8, 3, trim);
      px(-3, -9, 1, 1, "#fff");
      px(2, -9, 1, 1, "#fff");
      px(-10, -3, 20, 14, dark);
      px(-8, -1, 16, 10, color);
      px(-6, 4, 12, 7, dark);
      px(-2, 11, 4, 3, trim);
      px(10, -6, 2, 18, "#aaa");                  // staff right side
      px(9, -10, 4, 4, trim);                     // flame top
      px(10, -12, 2, 2, "#ffe0a0");
      px(10, -13, 1, 1, trim);
    }
    ctx.restore();
    return;
  }

  switch (unit.sprite) {
    case "imp": {
      px(-6, -10, 12, 9, color);
      px(-8, -12, 3, 3, color); px(5, -12, 3, 3, color);
      px(-3, -7, 2, 2, "#100");
      px(1, -7, 2, 2, "#100");
      px(-6, -1, 12, 9, dark);
      px(-4, 1, 8, 4, color);
      px(-3, 8, 2, 4, dark); px(1, 8, 2, 4, dark);
      px(-10, 1, 3, 5, color); px(7, 1, 3, 5, color);
      break;
    }
    case "wyrm": {
      px(-12, -3, 22, 9, color);
      px(8, -6, 6, 9, color);
      px(11, -4, 2, 2, "#ffcd5a");
      px(11, -1, 1, 1, "#100");
      px(-14, 0, 6, 3, color);
      px(-6, 6, 3, 5, dark); px(3, 6, 3, 5, dark);
      px(-10, -8, 4, 3, dark); px(-2, -8, 4, 3, dark); px(6, -9, 3, 3, dark);
      break;
    }
    case "merfolk": {
      px(-4, -12, 8, 7, color);
      px(-2, -9, 1, 1, "#100"); px(1, -9, 1, 1, "#100");
      px(0, -7, 1, 1, trim);
      px(-6, -5, 12, 8, dark);
      px(-5, -3, 10, 5, color);
      px(-4, 3, 8, 5, color);
      px(-9, 8, 6, 4, color); px(3, 8, 6, 4, color);
      break;
    }
    case "serpent": {
      px(-13, 0, 6, 5, color);
      px(-7, -3, 6, 5, color);
      px(-1, 0, 6, 5, color);
      px(5, -3, 6, 5, color);
      px(11, -6, 4, 5, color);
      px(13, -5, 1, 1, "#fff");
      px(13, -3, 1, 1, "#100");
      px(-14, 5, 3, 3, dark);
      break;
    }
    case "golem": {
      px(-10, -10, 20, 22, dark);
      px(-8, -8, 16, 6, color);
      px(-4, -14, 8, 6, dark);
      px(-3, -12, 1, 1, "#ffcd5a"); px(2, -12, 1, 1, "#ffcd5a");
      px(-12, -5, 3, 12, color); px(9, -5, 3, 12, color);
      px(-6, 0, 12, 2, trim);
      break;
    }
    case "ogre": {
      px(-9, -13, 18, 9, color);
      px(-3, -10, 2, 2, "#100"); px(1, -10, 2, 2, "#100");
      px(-5, -5, 2, 2, "#fff");
      px(3, -5, 2, 2, dark);                       // tusk
      px(-10, -4, 20, 14, dark);
      px(-13, 0, 4, 8, color); px(9, 0, 4, 8, color);
      px(10, -8, 4, 10, "#aaa");                   // weapon haft
      px(8, -11, 8, 5, "#ccc");                    // weapon head
      break;
    }
    case "wisp": {
      px(-4, -4, 8, 8, color);
      px(-3, -3, 6, 6, "#fff5b6");
      px(-2, -2, 4, 4, "#ffffff");
      px(-7, 0, 1, 1, color); px(6, 0, 1, 1, color);
      px(-10, -1, 1, 1, dark); px(9, -1, 1, 1, dark);
      px(0, -7, 1, 1, color); px(0, 6, 1, 1, color);
      px(-5, -8, 2, 1, "rgba(255,255,200,0.6)");
      break;
    }
    case "raptor": {
      px(-13, -3, 9, 6, dark);
      px(3, -3, 9, 6, dark);
      px(-12, -1, 7, 3, color); px(5, -1, 7, 3, color);
      px(-4, -5, 8, 8, color);
      px(-1, -9, 4, 4, color);
      px(2, -7, 1, 1, "#ffcd5a"); px(2, -5, 1, 1, "#100");
      px(-2, 4, 4, 4, dark);
      px(-3, 7, 2, 2, dark); px(1, 7, 2, 2, dark);
      break;
    }
  }
  ctx.restore();
}

// drawBattleSprite: large detailed portrait used in cinematic battle scene.
// pose: "idle" | "attack" | "hit"
function drawBattleSprite(ctx, unit, cx, cy, facing, pose, t) {
  const player = PLAYERS[unit.owner];
  const color = player.color, dark = player.dark, trim = player.trim;
  const SCALE = 5;

  ctx.save();
  ctx.translate(cx, cy);
  if (facing < 0) ctx.scale(-1, 1);
  const bob = Math.sin(t / 14) * 1.2;
  ctx.translate(0, bob);

  let lunge = 0;
  if (pose === "attack") lunge = 6;
  let recoil = 0;
  if (pose === "hit") recoil = -8;
  ctx.translate(lunge + recoil, 0);

  if (pose === "hit") {
    // hit flash tint - we'll overlay after the sprite
  }

  // Helper: scaled pixel rect, centered around 0,0
  const P = (x, y, w, h, fill) => {
    ctx.fillStyle = fill;
    ctx.fillRect(x * SCALE, y * SCALE, w * SCALE, h * SCALE);
  };

  if (unit.isMaster) {
    if (unit.owner === 0) {
      // AZURE archon — detailed
      P(-7, -2, 14, 16, dark);                    // robe lower
      P(-6, 0, 12, 12, color);
      P(-8, 4, 16, 4, dark);                      // sash band
      P(-3, 6, 6, 2, trim);                       // belt jewel
      P(-9, -3, 18, 5, dark);                     // shoulders
      P(-7, -2, 14, 3, color);
      P(-9, -1, 2, 6, color); P(7, -1, 2, 6, color); // arms
      // hood
      P(-6, -10, 12, 4, dark);
      P(-5, -12, 10, 3, color);
      P(-4, -13, 8, 2, color);
      P(-1, -11, 2, 2, trim);                      // forehead jewel
      // face shadow
      P(-3, -7, 6, 3, "#13111f");
      P(-2, -6, 1, 1, "#bce0ff");
      P(1, -6, 1, 1, "#bce0ff");
      // staff
      P(-12, -12, 1, 22, "#bbb");
      P(-13, -14, 3, 3, trim);                    // crescent jewel
      P(-13, -14, 1, 3, dark);
      // shoes
      P(-5, 14, 4, 2, dark); P(1, 14, 4, 2, dark);
    } else {
      // CRIMSON archon
      P(-7, -2, 14, 16, dark);
      P(-6, 0, 12, 12, color);
      P(-8, 4, 16, 4, dark);
      P(-3, 6, 6, 2, trim);
      P(-9, -3, 18, 5, dark);
      P(-7, -2, 14, 3, color);
      P(-9, -1, 2, 6, color); P(7, -1, 2, 6, color);
      // spiked hood
      P(-6, -10, 12, 4, dark);
      P(-5, -13, 10, 4, color);
      P(-3, -15, 2, 3, color);                    // center spike
      P(1, -15, 2, 3, color);
      P(-1, -17, 2, 2, trim);                     // jewel tip
      P(-3, -7, 6, 3, "#13111f");
      P(-2, -6, 1, 1, "#ffd6b0");
      P(1, -6, 1, 1, "#ffd6b0");
      // flaming staff
      P(11, -12, 1, 22, "#bbb");
      P(10, -15, 3, 3, trim);                     // flame
      P(11, -17, 1, 2, "#ffe0a0");
      P(10, -13, 1, 1, dark);
      P(-5, 14, 4, 2, dark); P(1, 14, 4, 2, dark);
    }
  } else {
    switch (unit.sprite) {
      case "imp": {
        // big head + small body imp
        P(-6, -8, 12, 8, color);
        P(-8, -10, 3, 3, color); P(5, -10, 3, 3, color);            // horns
        P(-9, -7, 1, 2, color);  P(8, -7, 1, 2, color);
        P(-3, -5, 2, 2, "#100"); P(1, -5, 2, 2, "#100");
        P(-1, -2, 2, 1, trim);                                       // grin
        P(-6, 0, 12, 8, dark);
        P(-4, 1, 8, 4, color);
        P(-3, 8, 2, 4, dark); P(1, 8, 2, 4, dark);
        P(-10, 0, 3, 5, color); P(7, 0, 3, 5, color);                // wing nubs
        P(-12, -3, 2, 4, dark); P(10, -3, 2, 4, dark);
        // tail
        P(7, 7, 2, 2, color); P(9, 9, 2, 2, color); P(11, 10, 2, 1, trim);
        break;
      }
      case "wyrm": {
        P(-12, -3, 22, 9, color);
        P(-10, 0, 18, 5, dark);                                       // belly shadow
        P(8, -6, 7, 10, color);                                       // head
        P(11, -4, 3, 3, "#ffcd5a"); P(12, -3, 1, 1, "#100");
        P(14, -2, 2, 2, color);                                       // snout
        P(-14, 0, 6, 3, color);                                       // tail
        P(-16, 1, 3, 2, color);
        P(-6, 6, 3, 5, dark); P(3, 6, 3, 5, dark);                    // legs
        P(-10, -8, 4, 3, dark); P(-2, -8, 4, 3, dark); P(6, -9, 3, 3, dark);
        // little wings
        P(-3, -11, 5, 3, dark);
        P(-3, -11, 5, 1, color);
        break;
      }
      case "merfolk": {
        // head + torso + finned tail
        P(-4, -11, 8, 8, color);
        P(-2, -8, 1, 1, "#100"); P(1, -8, 1, 1, "#100");
        P(-3, -5, 6, 2, trim);                                        // gills
        P(-7, -4, 14, 8, dark);                                       // torso
        P(-6, -2, 12, 4, color);
        P(-9, -3, 3, 6, color); P(6, -3, 3, 6, color);                // arms
        P(-4, 4, 8, 6, color);                                        // tail base
        P(-10, 10, 7, 5, color); P(3, 10, 7, 5, color);               // tail fins
        P(-8, 13, 4, 2, dark); P(4, 13, 4, 2, dark);
        // crown spike
        P(-1, -14, 2, 3, trim);
        break;
      }
      case "serpent": {
        // long coiled serpent
        P(-15, 4, 7, 4, color);
        P(-10, 1, 7, 4, color);
        P(-5, 4, 7, 4, color);
        P(0, 1, 7, 4, color);
        P(5, 4, 7, 4, color);
        P(10, -2, 5, 6, color);                                       // head
        P(13, -1, 1, 1, "#fff");
        P(13, 1, 1, 1, "#100");
        P(15, 1, 2, 2, color);                                        // snout
        // crest
        P(11, -5, 4, 3, dark);
        P(12, -6, 2, 1, trim);
        // tail
        P(-17, 5, 3, 2, dark);
        break;
      }
      case "golem": {
        P(-9, -10, 18, 20, dark);                                     // body
        P(-7, -8, 14, 6, color);                                      // chest plate
        P(-3, -15, 6, 5, dark);                                       // head
        P(-2, -13, 1, 1, "#ffcd5a"); P(1, -13, 1, 1, "#ffcd5a");
        P(-1, -11, 2, 1, "#fff");
        P(-12, -5, 3, 14, color); P(9, -5, 3, 14, color);             // arm pauldrons
        P(-13, 8, 5, 4, dark); P(8, 8, 5, 4, dark);                   // fists
        P(-7, 0, 14, 2, trim);                                        // chest gem line
        P(-3, 2, 6, 2, trim);
        P(-5, 10, 4, 4, dark); P(1, 10, 4, 4, dark);                  // feet
        break;
      }
      case "ogre": {
        P(-8, -14, 16, 9, color);                                     // head
        P(-2, -11, 2, 2, "#100"); P(0, -11, 2, 2, "#100");
        P(-3, -7, 8, 2, dark);                                        // grimace
        P(-2, -6, 1, 1, "#fff");
        P(2, -6, 1, 1, dark);                                         // tusk
        P(-10, -5, 20, 14, dark);                                     // torso
        P(-8, -3, 16, 8, color);
        P(-13, 0, 4, 8, color); P(9, 0, 4, 8, color);                 // arms
        P(11, -10, 4, 12, "#aaa");                                    // haft
        P(8, -14, 9, 6, "#ddd");                                      // head of weapon
        P(9, -16, 2, 2, "#fff");
        P(-5, 9, 4, 4, dark); P(1, 9, 4, 4, dark);
        break;
      }
      case "wisp": {
        // floating glow ball
        for (let r = 7; r >= 1; r--) {
          const alpha = (8 - r) / 8;
          ctx.fillStyle = `rgba(255, 230, 160, ${alpha * 0.4})`;
          ctx.beginPath();
          ctx.arc(0, 0, r * SCALE * 0.9, 0, Math.PI * 2);
          ctx.fill();
        }
        P(-4, -4, 8, 8, color);
        P(-3, -3, 6, 6, "#fff5b6");
        P(-2, -2, 4, 4, "#ffffff");
        // floating motes
        for (let i = 0; i < 5; i++) {
          const ang = t / 30 + i * 1.2;
          const rd = 9 + Math.sin(t / 18 + i) * 2;
          ctx.fillStyle = trim;
          ctx.fillRect(Math.cos(ang) * rd * SCALE - 1, Math.sin(ang) * rd * SCALE - 1, SCALE, SCALE);
        }
        break;
      }
      case "raptor": {
        // outstretched wings
        const flap = Math.sin(t / 6) * 2;
        P(-14, -2 - flap, 10, 4, dark);
        P(4, -2 - flap, 10, 4, dark);
        P(-13, 0 - flap, 8, 3, color);
        P(5, 0 - flap, 8, 3, color);
        // body
        P(-4, -4, 8, 9, color);
        P(-1, -9, 4, 5, color);                                       // head
        P(2, -7, 1, 1, "#ffcd5a"); P(2, -5, 1, 1, "#100");
        P(3, -8, 2, 1, trim);                                         // beak
        P(-3, 5, 6, 4, dark);                                         // tail base
        P(-4, 9, 3, 3, dark); P(1, 9, 3, 3, dark);                    // tail feathers
        break;
      }
    }
  }

  ctx.restore();
}

function drawTerrainDetail(ctx, cell, cx, cy) {
  switch (cell.terrain) {
    case "forest": {
      const dots = [[-12, 4], [4, -6], [-4, -12], [10, 8], [-8, -4]];
      for (const [dx, dy] of dots) {
        ctx.fillStyle = "#0a2010";
        ctx.fillRect(cx + dx, cy + dy, 6, 9);
        ctx.fillStyle = "#3a6840";
        ctx.fillRect(cx + dx + 1, cy + dy, 4, 7);
        ctx.fillStyle = "#5a8a60";
        ctx.fillRect(cx + dx + 2, cy + dy + 1, 1, 1);
      }
      break;
    }
    case "hill": {
      ctx.fillStyle = "#564022";
      ctx.fillRect(cx - 10, cy + 3, 20, 6);
      ctx.fillStyle = "#876844";
      ctx.fillRect(cx - 8, cy + 2, 16, 3);
      ctx.fillStyle = "#564022";
      ctx.fillRect(cx - 4, cy - 7, 8, 6);
      ctx.fillStyle = "#a08560";
      ctx.fillRect(cx - 3, cy - 6, 6, 2);
      break;
    }
    case "mountain": {
      ctx.fillStyle = "#2a2434";
      ctx.beginPath();
      ctx.moveTo(cx - 14, cy + 10);
      ctx.lineTo(cx - 4, cy - 12);
      ctx.lineTo(cx + 2, cy - 4);
      ctx.lineTo(cx + 10, cy - 14);
      ctx.lineTo(cx + 16, cy + 10);
      ctx.closePath();
      ctx.fill();
      ctx.fillStyle = "#bdb6c8";
      ctx.fillRect(cx - 5, cy - 12, 3, 3);
      ctx.fillRect(cx + 9, cy - 14, 3, 3);
      ctx.fillStyle = "#3a3344";
      ctx.fillRect(cx - 8, cy - 2, 4, 2);
      ctx.fillRect(cx + 4, cy - 4, 4, 2);
      break;
    }
    case "water": {
      ctx.fillStyle = "#bcdcf0";
      for (let i = 0; i < 4; i++) {
        const yy = cy - 8 + i * 6;
        ctx.fillRect(cx - 11, yy, 6, 1);
        ctx.fillRect(cx + 2, yy + 3, 6, 1);
      }
      break;
    }
    case "tower": {
      ctx.fillStyle = "#3a3242";
      ctx.fillRect(cx - 6, cy - 14, 12, 22);
      ctx.fillStyle = "#5a5060";
      ctx.fillRect(cx - 5, cy - 13, 10, 20);
      ctx.fillStyle = "#1a161e";
      ctx.fillRect(cx - 2, cy - 4, 4, 6);
      ctx.fillStyle = "#3a3242";
      ctx.fillRect(cx - 6, cy - 17, 3, 3);
      ctx.fillRect(cx + 3, cy - 17, 3, 3);
      ctx.fillRect(cx - 2, cy - 17, 4, 2);
      // banner
      const flagColor = cell.owner === null ? PAL.neutral : PLAYERS[cell.owner].color;
      ctx.fillStyle = "#100c18";
      ctx.fillRect(cx - 1, cy - 22, 1, 10);
      ctx.fillStyle = flagColor;
      ctx.fillRect(cx, cy - 22, 8, 5);
      break;
    }
    case "castle": {
      ctx.fillStyle = "#3a322a";
      ctx.fillRect(cx - 16, cy - 12, 32, 22);
      ctx.fillStyle = "#7a6a4e";
      ctx.fillRect(cx - 14, cy - 11, 28, 20);
      ctx.fillStyle = "#1a1610";
      ctx.fillRect(cx - 3, cy - 2, 6, 10);
      ctx.fillStyle = "#3a322a";
      ctx.fillRect(cx - 18, cy - 16, 6, 26);
      ctx.fillRect(cx + 12, cy - 16, 6, 26);
      for (let i = 0; i < 5; i++) ctx.fillRect(cx - 14 + i * 6, cy - 14, 3, 3);
      ctx.fillRect(cx - 18, cy - 19, 3, 3); ctx.fillRect(cx - 14, cy - 19, 2, 3);
      ctx.fillRect(cx + 12, cy - 19, 3, 3); ctx.fillRect(cx + 16, cy - 19, 2, 3);
      if (cell.owner !== null) {
        ctx.fillStyle = "#100c18";
        ctx.fillRect(cx - 1, cy - 26, 1, 12);
        ctx.fillStyle = PLAYERS[cell.owner].color;
        ctx.fillRect(cx, cy - 26, 9, 6);
      }
      break;
    }
  }
}

// =========================================================================
// 10. Battle scene state machine & renderer
// =========================================================================

// Phase durations (frames @ 60 fps). Tuned to feel cinematic rather than
// snappy — the player needs time to read the damage number, see who hit
// who, and process the counter. Total no-counter ≈ 2.8 s, with counter
// ≈ 4 s. Bump these if you want even slower drama; trim to make turns
// move faster.
const B = {
  intro: 36,     // 600 ms — letterbox wipes in, "BATTLE" banner appears
  standoff: 26,  // 433 ms — both combatants in idle, banner finishes fading
  charge: 22,    // 367 ms — attacker dashes forward (or projectile flies)
  impact: 34,    // 567 ms — hit flash + damage popup, screen shake
  recover: 18,   // 300 ms — attacker returns to start position
  pause: 22,     // 367 ms — dramatic beat before counterattack
  outro: 32,     // 533 ms — letterbox closes, return to map
};

// Fired when a combatant levels up mid-battle: log line, fanfare, and a
// "LEVEL UP!" banner over that side of the arena.
function onBattleLevelUp(unit, side) {
  pushLog(unit.name + " reached Level " + unit.level + "!");
  if (STATE.battle) {
    STATE.battle.flash = Math.max(STATE.battle.flash, 0.85);
    STATE.battle.levelUp = { side, ttl: 64 };
  }
  beep(523, 0.08, "triangle", 0.2);
  setTimeout(() => beep(784, 0.13, "triangle", 0.2), 90);
}

function updateBattle() {
  const b = STATE.battle;
  if (!b) return;
  b.phaseFrame++;
  b.flash *= 0.85;
  b.shake *= 0.85;
  if (b.levelUp && --b.levelUp.ttl <= 0) b.levelUp = null;

  const advance = (next) => { b.phase = next; b.phaseFrame = 0; };

  switch (b.phase) {
    case "intro":
      if (b.phaseFrame >= B.intro) advance("standoff");
      break;
    case "standoff":
      if (b.phaseFrame >= B.standoff) advance("aCharge");
      break;
    case "aCharge":
      if (b.phaseFrame >= B.charge) {
        b.flash = 1; b.shake = 6;
        advance("aImpact");
        beep(140 + Math.random() * 60, 0.08, "square", 0.18);
      }
      break;
    case "aImpact":
      if (!b.applied1) {
        b.defender.hp -= b.aDmg;
        pushAnim("dmgB", b.defender.q, b.defender.r, "-" + b.aDmg, PAL.red);
        pushLog(b.attacker.name + " strikes " + b.defender.name + " for " + b.aDmg + ".");
        b.applied1 = true;
        if (b.defender.hp <= 0) pushLog(b.defender.name + " is destroyed.");
        const killed = b.defender.hp <= 0;
        if (gainXp(b.attacker, b.aDmg + (killed ? KILL_XP_BONUS : 0)) > 0) onBattleLevelUp(b.attacker, "a");
      }
      if (b.phaseFrame >= B.impact) advance("aRecover");
      break;
    case "aRecover":
      if (b.phaseFrame >= B.recover) {
        if (b.hasCounter && b.defender.hp > 0) advance("cPause");
        else advance("outro");
      }
      break;
    case "cPause":
      if (b.phaseFrame >= B.pause) advance("cCharge");
      break;
    case "cCharge":
      if (b.phaseFrame >= B.charge) {
        b.flash = 1; b.shake = 5;
        advance("cImpact");
        beep(180 + Math.random() * 60, 0.08, "square", 0.14);
      }
      break;
    case "cImpact":
      if (!b.applied2) {
        b.attacker.hp -= b.cDmg;
        pushAnim("dmgB", b.attacker.q, b.attacker.r, "-" + b.cDmg, PAL.red);
        pushLog(b.defender.name + " counters for " + b.cDmg + ".");
        b.applied2 = true;
        if (b.attacker.hp <= 0) pushLog(b.attacker.name + " is destroyed.");
        const killed = b.attacker.hp <= 0;
        if (gainXp(b.defender, b.cDmg + (killed ? KILL_XP_BONUS : 0)) > 0) onBattleLevelUp(b.defender, "c");
      }
      if (b.phaseFrame >= B.impact) advance("cRecover");
      break;
    case "cRecover":
      if (b.phaseFrame >= B.recover) advance("outro");
      break;
    case "outro":
      if (b.phaseFrame >= B.outro) endBattleAndResume();
      break;
  }
}

function renderBattle() {
  const b = STATE.battle;
  if (!b) return;

  // Background: arena framed by black bars with parallax stars/banners
  const introT = Math.min(1, b.phase === "intro" ? b.phaseFrame / B.intro : 1);
  const outroT = b.phase === "outro" ? 1 - b.phaseFrame / B.outro : 1;
  const reveal = b.phase === "intro" ? easeOutCubic(introT) : (b.phase === "outro" ? easeInCubic(outroT) : 1);

  // Wipe bars (top and bottom shrink in/out)
  const barH = Math.round(CANVAS_H * (1 - reveal) / 2);
  // Fill full bg first
  ctx.fillStyle = "#020107";
  ctx.fillRect(0, 0, CANVAS_W, CANVAS_H);

  const shakeX = (Math.random() - 0.5) * b.shake * 2;
  const shakeY = (Math.random() - 0.5) * b.shake * 2;
  ctx.save();
  ctx.translate(shakeX, shakeY);

  // Arena gradient ground based on defender's terrain
  const defTerr = cellAt({ q: b.defender.q, r: b.defender.r }).terrain;
  drawArenaBackground(defTerr, b.arenaSeed);

  // Combatants
  const atkX = CANVAS_W * 0.30;
  const defX = CANVAS_W * 0.70;
  const groundY = CANVAS_H * 0.62;

  const atkPose = (b.phase === "aCharge" || b.phase === "aImpact" || b.phase === "aRecover") ? attackerPose(b)
              : (b.phase === "cImpact") ? "hit"
              : "idle";
  const defPose = (b.phase === "cCharge" || b.phase === "cImpact" || b.phase === "cRecover") ? defenderPose(b)
              : (b.phase === "aImpact") ? "hit"
              : "idle";

  // Attacker (facing right)
  drawCombatant(b.attacker, atkX + chargeOffset(b, "a"), groundY, +1, atkPose);
  // Defender (facing left)
  drawCombatant(b.defender, defX + chargeOffset(b, "c"), groundY, -1, defPose);

  // Projectile / effect overlays
  drawAttackEffect(b, atkX, defX, groundY);

  // Damage flash on impact
  if (b.flash > 0.05) {
    ctx.fillStyle = `rgba(255, 240, 200, ${b.flash * 0.5})`;
    ctx.fillRect(0, 0, CANVAS_W, CANVAS_H);
  }

  // Floating damage texts (rendered in the same shake-translated space)
  renderBattleAnims();

  ctx.restore();

  // Letterbox bars
  ctx.fillStyle = "#000";
  ctx.fillRect(0, 0, CANVAS_W, barH);
  ctx.fillRect(0, CANVAS_H - barH, CANVAS_W, barH);

  // HUD overlays (name plates, HP bars)
  drawCombatantHud(b.attacker, 24, CANVAS_H - 100, false, b);
  drawCombatantHud(b.defender, CANVAS_W - 24, CANVAS_H - 100, true, b);

  // "LEVEL UP!" banner over the side that leveled
  if (b.levelUp) {
    const lx = b.levelUp.side === "a" ? CANVAS_W * 0.30 : CANVAS_W * 0.70;
    const k = b.levelUp.ttl / 64;
    const rise = (1 - k) * 30;
    ctx.font = "bold 30px 'Courier New', monospace";
    ctx.textAlign = "center";
    ctx.fillStyle = `rgba(0,0,0,${k})`;
    ctx.fillText("LEVEL UP!", lx + 2, CANVAS_H * 0.30 - rise + 2);
    ctx.fillStyle = `rgba(240, 198, 116, ${k})`;
    ctx.fillText("LEVEL UP!", lx, CANVAS_H * 0.30 - rise);
  }

  // "BATTLE" banner intro
  if (b.phase === "intro" || (b.phase === "standoff" && b.phaseFrame < 12)) {
    const a = (b.phase === "intro" ? introT : 1 - b.phaseFrame / 12);
    ctx.font = "bold 56px 'Courier New', monospace";
    ctx.textAlign = "center";
    ctx.fillStyle = `rgba(20, 14, 28, ${a * 0.9})`;
    ctx.fillText("BATTLE", CANVAS_W / 2 + 4, CANVAS_H / 2 + 4);
    ctx.fillStyle = `rgba(240, 198, 116, ${a})`;
    ctx.fillText("BATTLE", CANVAS_W / 2, CANVAS_H / 2);
  }
}

function attackerPose(b) {
  if (b.phase === "aCharge") return "attack";
  if (b.phase === "aImpact") return "attack";
  return "idle";
}
function defenderPose(b) {
  if (b.phase === "cCharge") return "attack";
  if (b.phase === "cImpact") return "attack";
  return "idle";
}

function chargeOffset(b, which) {
  // attacker (a) dashes right toward defender; defender (c) dashes left
  if (which === "a") {
    if (b.phase === "aCharge") return ease01(b.phaseFrame / B.charge) * 90;
    if (b.phase === "aImpact") return 90 + (1 - ease01(b.phaseFrame / B.impact)) * 0;
    if (b.phase === "aRecover") return 90 * (1 - ease01(b.phaseFrame / B.recover));
    return 0;
  } else {
    if (b.phase === "cCharge") return -ease01(b.phaseFrame / B.charge) * 90;
    if (b.phase === "cImpact") return -90;
    if (b.phase === "cRecover") return -90 * (1 - ease01(b.phaseFrame / B.recover));
    return 0;
  }
}

function ease01(t) { return t < 0 ? 0 : t > 1 ? 1 : t * (2 - t); }
function easeOutCubic(t) { return 1 - Math.pow(1 - t, 3); }
function easeInCubic(t) { return Math.pow(t, 3); }

function drawCombatant(unit, x, y, facing, pose) {
  // shadow
  ctx.fillStyle = "rgba(0,0,0,0.5)";
  ctx.beginPath();
  ctx.ellipse(x, y + 16, 60, 8, 0, 0, Math.PI * 2);
  ctx.fill();
  // evolved combatants stand in a pulsing gold halo
  if (unit.evolved) {
    const pulse = 0.3 + 0.18 * Math.sin(frame / 10 + unit.id);
    ctx.strokeStyle = `rgba(240, 198, 116, ${pulse})`;
    ctx.lineWidth = 3;
    ctx.beginPath();
    ctx.ellipse(x, y + 14, 64, 12, 0, 0, Math.PI * 2);
    ctx.stroke();
  }
  drawBattleSprite(ctx, unit, x, y - 30, facing, pose, frame);
}

function drawAttackEffect(b, atkX, defX, groundY) {
  // Attacker effect during aCharge/aImpact
  if (b.phase === "aImpact") {
    drawImpactBurst(defX - 20, groundY - 40, b.attacker.element);
  } else if (b.phase === "aCharge") {
    drawAttackTrail(b.attacker, atkX + 60, groundY - 40, +1, b.phaseFrame / B.charge);
  }
  if (b.phase === "cImpact") {
    drawImpactBurst(atkX + 20, groundY - 40, b.defender.element);
  } else if (b.phase === "cCharge") {
    drawAttackTrail(b.defender, defX - 60, groundY - 40, -1, b.phaseFrame / B.charge);
  }
}

function drawAttackTrail(unit, x, y, facing, t) {
  const kind = unit.isMaster ? "bolt" : (unit.attack || "melee");
  const tx = x + (unit.range > 1 ? facing * t * 260 : facing * t * 30);
  if (kind === "melee") {
    // arc swoosh
    ctx.strokeStyle = "rgba(255, 240, 180, 0.85)";
    ctx.lineWidth = 3;
    ctx.beginPath();
    const rad = 36;
    const a0 = facing > 0 ? -Math.PI / 3 : Math.PI + Math.PI / 3;
    const a1 = facing > 0 ? Math.PI / 3 : Math.PI - Math.PI / 3;
    ctx.arc(x, y, rad, a0, a1, facing < 0);
    ctx.stroke();
  } else if (kind === "breath") {
    // cone of fire
    for (let i = 0; i < 8; i++) {
      const dx = facing * (i * 16 + Math.random() * 6);
      const dy = (Math.random() - 0.5) * 26;
      const r = 6 - i * 0.4;
      ctx.fillStyle = `rgba(255, ${120 + i * 10}, 40, ${0.7 - i * 0.06})`;
      ctx.beginPath();
      ctx.arc(x + dx, y + dy, r, 0, Math.PI * 2);
      ctx.fill();
    }
  } else if (kind === "spray") {
    // water spray
    for (let i = 0; i < 14; i++) {
      const dx = facing * (i * 14 + Math.random() * 4);
      const dy = Math.sin(i + frame / 4) * 18;
      ctx.fillStyle = `rgba(120, 200, 240, ${0.7 - i * 0.04})`;
      ctx.fillRect(x + dx - 2, y + dy - 2, 4, 4);
    }
  } else if (kind === "spark") {
    // wisp sparks
    for (let i = 0; i < 12; i++) {
      const ang = Math.random() * Math.PI * 2;
      const r = 10 + Math.random() * 26;
      ctx.fillStyle = `rgba(255, 240, 170, ${Math.random()})`;
      ctx.fillRect(x + Math.cos(ang) * r, y + Math.sin(ang) * r, 2, 2);
    }
    // streak
    ctx.strokeStyle = "rgba(255, 240, 170, 0.9)";
    ctx.lineWidth = 2;
    ctx.beginPath();
    ctx.moveTo(x, y);
    ctx.lineTo(tx, y);
    ctx.stroke();
  } else if (kind === "dive") {
    // swooping diagonal
    ctx.strokeStyle = "rgba(220, 220, 240, 0.8)";
    ctx.lineWidth = 4;
    ctx.beginPath();
    ctx.moveTo(x - facing * 80, y - 60);
    ctx.lineTo(tx + facing * 30, y + 6);
    ctx.stroke();
  } else if (kind === "bolt") {
    // arcane bolt
    const grad = ctx.createRadialGradient(tx, y, 2, tx, y, 20);
    grad.addColorStop(0, "#fff");
    grad.addColorStop(0.4, "#c8a0ff");
    grad.addColorStop(1, "rgba(120, 80, 200, 0)");
    ctx.fillStyle = grad;
    ctx.beginPath();
    ctx.arc(tx, y, 20, 0, Math.PI * 2);
    ctx.fill();
    // jagged trail
    ctx.strokeStyle = "rgba(200, 160, 255, 0.85)";
    ctx.lineWidth = 2;
    ctx.beginPath();
    let cx = x;
    ctx.moveTo(cx, y);
    while ((facing > 0 ? cx < tx : cx > tx)) {
      cx += facing * 8;
      ctx.lineTo(cx, y + (Math.random() - 0.5) * 14);
    }
    ctx.stroke();
  }
}

function drawImpactBurst(x, y, element) {
  const col = ELEMENT[element]?.color || "#fff";
  // expanding ring
  for (let i = 0; i < 3; i++) {
    ctx.strokeStyle = `rgba(255, 240, 200, ${0.6 - i * 0.15})`;
    ctx.lineWidth = 3 - i;
    ctx.beginPath();
    ctx.arc(x, y, 20 + i * 14, 0, Math.PI * 2);
    ctx.stroke();
  }
  // shards
  for (let i = 0; i < 14; i++) {
    const a = i * (Math.PI / 7) + Math.random() * 0.3;
    const r = 18 + Math.random() * 24;
    ctx.fillStyle = col;
    ctx.fillRect(x + Math.cos(a) * r, y + Math.sin(a) * r, 3, 3);
  }
  // center flash
  ctx.fillStyle = "rgba(255, 245, 210, 0.9)";
  ctx.beginPath();
  ctx.arc(x, y, 12, 0, Math.PI * 2);
  ctx.fill();
}

function drawArenaBackground(terrainKind, seed) {
  // sky gradient
  const sky = ctx.createLinearGradient(0, 0, 0, CANVAS_H);
  if (terrainKind === "water") {
    sky.addColorStop(0, "#0a2238");
    sky.addColorStop(1, "#1a4a7a");
  } else if (terrainKind === "mountain") {
    sky.addColorStop(0, "#1a1432");
    sky.addColorStop(1, "#3a324a");
  } else if (terrainKind === "forest") {
    sky.addColorStop(0, "#0a1820");
    sky.addColorStop(1, "#1a3a2a");
  } else if (terrainKind === "tower" || terrainKind === "castle") {
    sky.addColorStop(0, "#1a1024");
    sky.addColorStop(1, "#3a2a44");
  } else {
    sky.addColorStop(0, "#1a1430");
    sky.addColorStop(1, "#3a2840");
  }
  ctx.fillStyle = sky;
  ctx.fillRect(0, 0, CANVAS_W, CANVAS_H);

  // stars / twinkling
  const rng = mulberry32(seed);
  for (let i = 0; i < 60; i++) {
    const x = rng() * CANVAS_W;
    const y = rng() * CANVAS_H * 0.5;
    const tw = (Math.sin(frame / 30 + i) + 1) / 2;
    ctx.fillStyle = `rgba(220, 210, 255, ${0.2 + tw * 0.4})`;
    ctx.fillRect(x, y, 2, 2);
  }

  // distant mountains silhouette
  ctx.fillStyle = "#0e0a18";
  ctx.beginPath();
  ctx.moveTo(0, CANVAS_H * 0.55);
  let x = 0;
  const r2 = mulberry32(seed + 7);
  while (x < CANVAS_W) {
    const px = x;
    const py = CANVAS_H * 0.55 - 30 - r2() * 60;
    ctx.lineTo(px, py);
    x += 40 + r2() * 50;
  }
  ctx.lineTo(CANVAS_W, CANVAS_H * 0.55);
  ctx.lineTo(CANVAS_W, CANVAS_H);
  ctx.lineTo(0, CANVAS_H);
  ctx.closePath();
  ctx.fill();

  // ground
  const groundY = CANVAS_H * 0.62;
  const ground = ctx.createLinearGradient(0, groundY, 0, CANVAS_H);
  const tCol = TERRAIN[terrainKind].color;
  const tAlt = TERRAIN[terrainKind].alt;
  ground.addColorStop(0, tAlt);
  ground.addColorStop(1, "#06040a");
  ctx.fillStyle = ground;
  ctx.fillRect(0, groundY, CANVAS_W, CANVAS_H - groundY);

  // ground hex pattern
  ctx.strokeStyle = "rgba(255,255,255,0.05)";
  ctx.lineWidth = 1;
  for (let i = 0; i < 12; i++) {
    const yy = groundY + 30 + i * 18;
    const off = (i % 2) * 30;
    for (let j = 0; j < 30; j++) {
      const xx = j * 60 + off;
      ctx.beginPath();
      ctx.moveTo(xx, yy);
      ctx.lineTo(xx + 20, yy);
      ctx.stroke();
    }
  }

  // ground splotches per terrain
  ctx.fillStyle = tCol;
  for (let i = 0; i < 20; i++) {
    const xx = rng() * CANVAS_W;
    const yy = groundY + 20 + rng() * (CANVAS_H - groundY - 40);
    ctx.fillRect(xx, yy, 8, 3);
  }

  // foreground rocks/grass tufts
  if (terrainKind === "forest") {
    ctx.fillStyle = "#0a1810";
    for (let i = 0; i < 6; i++) {
      const xx = rng() * CANVAS_W;
      ctx.fillRect(xx, CANVAS_H - 30, 12, 20);
      ctx.fillStyle = "#1a3220";
      ctx.fillRect(xx + 2, CANVAS_H - 30, 8, 16);
      ctx.fillStyle = "#0a1810";
    }
  } else if (terrainKind === "mountain") {
    ctx.fillStyle = "#0a0814";
    for (let i = 0; i < 5; i++) {
      const xx = rng() * CANVAS_W;
      const w = 30 + rng() * 30;
      ctx.beginPath();
      ctx.moveTo(xx, CANVAS_H);
      ctx.lineTo(xx + w / 2, CANVAS_H - 30 - rng() * 20);
      ctx.lineTo(xx + w, CANVAS_H);
      ctx.closePath();
      ctx.fill();
    }
  }
}

function drawCombatantHud(unit, anchorX, y, alignRight, b) {
  const w = 280, h = 76;
  const x = alignRight ? anchorX - w : anchorX;
  const player = PLAYERS[unit.owner];
  // panel
  ctx.fillStyle = "rgba(8, 6, 14, 0.85)";
  ctx.fillRect(x, y, w, h);
  ctx.strokeStyle = player.color;
  ctx.lineWidth = 2;
  ctx.strokeRect(x + 0.5, y + 0.5, w - 1, h - 1);

  // name + element
  ctx.font = "bold 14px 'Courier New', monospace";
  ctx.textAlign = "left";
  ctx.fillStyle = player.color;
  ctx.fillText(player.name, x + 10, y + 18);
  ctx.fillStyle = PAL.ink;
  ctx.fillText(unit.name, x + 10, y + 34);
  const el = ELEMENT[unit.element];
  ctx.fillStyle = el.color;
  ctx.font = "11px 'Courier New', monospace";
  ctx.textAlign = "right";
  ctx.fillText("Lv " + (unit.level || 1) + "  [" + el.short + "]", x + w - 10, y + 18);

  // HP bar
  const hpFrac = Math.max(0, unit.hp / unit.maxHp);
  const barW = w - 20;
  ctx.fillStyle = "#000";
  ctx.fillRect(x + 10, y + 42, barW, 12);
  ctx.fillStyle = "#3a1010";
  ctx.fillRect(x + 11, y + 43, barW - 2, 10);
  const col = hpFrac > 0.5 ? "#5fd06a" : hpFrac > 0.25 ? "#f0c674" : "#cc4a4a";
  ctx.fillStyle = col;
  ctx.fillRect(x + 11, y + 43, Math.round((barW - 2) * hpFrac), 10);
  ctx.fillStyle = PAL.ink;
  ctx.font = "10px 'Courier New', monospace";
  ctx.textAlign = "right";
  ctx.fillText(unit.hp + " / " + unit.maxHp, x + w - 10, y + 52);

  // XP bar (thin gold), or "MAX" at top level
  const lvl = unit.level || 1;
  ctx.fillStyle = "#000";
  ctx.fillRect(x + 10, y + 60, barW, 7);
  if (lvl >= MAX_LEVEL) {
    ctx.fillStyle = PAL.gold;
    ctx.fillRect(x + 11, y + 61, barW - 2, 5);
    ctx.fillStyle = "#000";
    ctx.font = "8px 'Courier New', monospace";
    ctx.textAlign = "center";
    ctx.fillText("MAX LEVEL", x + 10 + barW / 2, y + 66);
  } else {
    const xpFrac = Math.max(0, Math.min(1, (unit.xp || 0) / xpToNext(lvl)));
    ctx.fillStyle = "#2a2410";
    ctx.fillRect(x + 11, y + 61, barW - 2, 5);
    ctx.fillStyle = PAL.gold;
    ctx.fillRect(x + 11, y + 61, Math.round((barW - 2) * xpFrac), 5);
  }
}

function renderBattleAnims() {
  for (let i = STATE.animations.length - 1; i >= 0; i--) {
    const a = STATE.animations[i];
    a.y += a.vy;
    a.ttl--;
    if (a.ttl <= 0) { STATE.animations.splice(i, 1); continue; }
    if (a.kind !== "dmgB") continue; // map-only damage in renderAnimations
    // In battle mode show damage above whichever combatant
    const isAttacker = STATE.battle && STATE.battle.attacker.q === a.q && STATE.battle.attacker.r === a.r;
    const x = isAttacker ? CANVAS_W * 0.30 : CANVAS_W * 0.70;
    const y = CANVAS_H * 0.45 + (50 - a.ttl) * -1;
    ctx.font = "bold 28px 'Courier New', monospace";
    ctx.textAlign = "center";
    ctx.fillStyle = "#000";
    ctx.fillText(a.text, x + 2, y + 2);
    ctx.fillStyle = a.color;
    ctx.fillText(a.text, x, y);
  }
}

function pushAnim(kind, q, r, text, color) {
  const p = axialToPixel(q, r);
  STATE.animations.push({ kind, q, r, x: p.x, y: p.y, text, color, ttl: 50, vy: -0.4 });
}

// =========================================================================
// 11. Map rendering pipeline
// =========================================================================

let ctx, canvas;
let frame = 0;

function render() {
  // Defensive: reset all canvas state every frame so a thrown render
  // call never leaves transform/clip state lingering for the next frame.
  // Reassigning canvas.width is the only way to wipe an active clip path.
  canvas.width = CANVAS_W;
  ctx.imageSmoothingEnabled = false;
  frame++;
  ctx.fillStyle = PAL.bg;
  ctx.fillRect(0, 0, CANVAS_W, CANVAS_H);

  if (STATE.screen === "title") { renderTitle(); return; }
  if (STATE.screen === "gameover") { renderGameOver(); return; }
  if (STATE.screen === "battle") {
    updateBattle();
    renderBattle();
    return;
  }

  renderMap();
  renderOverlays();
  renderUnits();
  renderAnimationsMap();
  renderTopBar();
  renderSidebar();
  renderMenu();
  renderBanner();
}

function renderMap() {
  ctx.save();
  ctx.beginPath();
  ctx.rect(0, TOPBAR_H, MAP_W, MAP_H);
  ctx.clip();
  ctx.translate(STATE.cam.x, STATE.cam.y + TOPBAR_H);
  for (const cell of MAP.cells.values()) {
    const p = axialToPixel(cell.q, cell.r);
    drawHex(cell, p.x, p.y);
  }
  ctx.restore();
}

function drawHex(cell, cx, cy) {
  const t = TERRAIN[cell.terrain];
  let baseColor = t.color;
  if (cell.terrain === "tower" && cell.owner !== null) baseColor = PAL.towerCap;
  ctx.fillStyle = baseColor;
  hexPath(cx, cy); ctx.fill();
  ctx.fillStyle = t.alt + "40";
  hexPath(cx, cy - 1); ctx.fill();
  ctx.strokeStyle = "#1a1622";
  ctx.lineWidth = 1;
  hexPath(cx, cy); ctx.stroke();
  drawTerrainDetail(ctx, cell, cx, cy);
}

function renderOverlays() {
  ctx.save();
  ctx.beginPath();
  ctx.rect(0, TOPBAR_H, MAP_W, MAP_H);
  ctx.clip();
  ctx.translate(STATE.cam.x, STATE.cam.y + TOPBAR_H);

  if (STATE.reachable) {
    const selEl = STATE.selected ? STATE.selected.element : null;
    for (const node of STATE.reachable.values()) {
      const p = axialToPixel(node.q, node.r);
      ctx.fillStyle = "rgba(120, 180, 255, 0.22)";
      hexPath(p.x, p.y); ctx.fill();
      ctx.strokeStyle = "rgba(120, 180, 255, 0.55)";
      ctx.lineWidth = 1;
      hexPath(p.x, p.y); ctx.stroke();
      // affinity glint: tile empowers the selected unit's element
      if (selEl && affinityFor(selEl, cellAt(node).terrain)) {
        const tw = (Math.sin(frame / 8 + node.q * 2 + node.r) + 1) / 2;
        ctx.fillStyle = `rgba(240, 198, 116, ${0.35 + tw * 0.4})`;
        for (let s = 0; s < 3; s++) {
          const ang = frame / 20 + s * (Math.PI * 2 / 3);
          ctx.fillRect(p.x + Math.cos(ang) * 9 - 1, p.y + Math.sin(ang) * 7 - 1, 2, 2);
        }
      }
    }
  }
  if (STATE.attackTargets) {
    for (const k of STATE.attackTargets) {
      const [q, r] = k.split(",").map(Number);
      const p = axialToPixel(q, r);
      ctx.fillStyle = "rgba(220, 80, 80, 0.32)";
      hexPath(p.x, p.y); ctx.fill();
      ctx.strokeStyle = "rgba(255, 120, 120, 0.85)";
      ctx.lineWidth = 2;
      hexPath(p.x, p.y); ctx.stroke();
    }
  }
  if (STATE.hover && inBounds(STATE.hover.q, STATE.hover.r)) {
    const p = axialToPixel(STATE.hover.q, STATE.hover.r);
    ctx.strokeStyle = "rgba(255, 240, 180, 0.9)";
    ctx.lineWidth = 2;
    hexPath(p.x, p.y); ctx.stroke();
  }
  if (STATE.selected) {
    const p = axialToPixel(STATE.selected.q, STATE.selected.r);
    ctx.strokeStyle = PAL.gold;
    ctx.lineWidth = 3;
    hexPath(p.x, p.y); ctx.stroke();
  }
  ctx.restore();
}

function hexPath(cx, cy) {
  ctx.beginPath();
  for (let i = 0; i < 6; i++) {
    const c = hexCorner(cx, cy, i);
    if (i === 0) ctx.moveTo(c.x, c.y);
    else ctx.lineTo(c.x, c.y);
  }
  ctx.closePath();
}

function renderUnits() {
  ctx.save();
  ctx.beginPath();
  ctx.rect(0, TOPBAR_H, MAP_W, MAP_H);
  ctx.clip();
  ctx.translate(STATE.cam.x, STATE.cam.y + TOPBAR_H);

  const list = STATE.units.filter(u => u.hp > 0).slice();
  list.sort((a, b) => a.r - b.r);

  for (const u of list) {
    const p = axialToPixel(u.q, u.r);
    const player = PLAYERS[u.owner];
    ctx.fillStyle = u.acted ? "rgba(20,18,30,0.55)" : player.dark;
    ctx.beginPath();
    ctx.ellipse(p.x, p.y + 16, 18, 6, 0, 0, Math.PI * 2);
    ctx.fill();

    // evolved units get a faint pulsing gold aura ring (stub visual until 5.1)
    if (u.evolved) {
      const pulse = 0.35 + 0.2 * Math.sin(frame / 12 + u.id);
      ctx.strokeStyle = `rgba(240, 198, 116, ${pulse})`;
      ctx.lineWidth = 1.5;
      ctx.beginPath();
      ctx.ellipse(p.x, p.y + 14, 20, 8, 0, 0, Math.PI * 2);
      ctx.stroke();
    }

    drawMapSprite(ctx, u, p.x, p.y, frame + u.id * 7);

    const barW = 32, barH = 4;
    ctx.fillStyle = "#000";
    ctx.fillRect(p.x - barW / 2 - 1, p.y + 20, barW + 2, barH + 2);
    ctx.fillStyle = "#400";
    ctx.fillRect(p.x - barW / 2, p.y + 21, barW, barH);
    const frac = Math.max(0, u.hp / u.maxHp);
    ctx.fillStyle = frac > 0.5 ? "#5fd06a" : frac > 0.25 ? "#f0c674" : "#cc4a4a";
    ctx.fillRect(p.x - barW / 2, p.y + 21, Math.round(barW * frac), barH);

    // level pips below the HP bar (level 2+ shows level-1 gold chevrons)
    const lvl = u.level || 1;
    if (lvl > 1) {
      const n = lvl - 1;
      for (let i = 0; i < n; i++) {
        const cx2 = p.x - (n - 1) * 3 + i * 6;
        const cy2 = p.y + 28;
        ctx.fillStyle = "#000";
        ctx.fillRect(cx2 - 3, cy2 - 1, 6, 4);
        ctx.fillStyle = PAL.gold;
        ctx.fillRect(cx2 - 2, cy2, 4, 1);   // chevron base
        ctx.fillRect(cx2 - 1, cy2 - 1, 2, 1); // chevron tip
      }
    }

    if (u.isMaster) {
      ctx.fillStyle = PAL.gold;
      ctx.fillRect(p.x - 5, p.y - 26, 10, 2);
      ctx.fillRect(p.x - 5, p.y - 24, 1, 3);
      ctx.fillRect(p.x - 2, p.y - 24, 2, 3);
      ctx.fillRect(p.x + 1, p.y - 24, 2, 3);
      ctx.fillRect(p.x + 4, p.y - 24, 1, 3);
    }
  }
  ctx.restore();
}

function renderAnimationsMap() {
  ctx.save();
  ctx.beginPath();
  ctx.rect(0, TOPBAR_H, MAP_W, MAP_H);
  ctx.clip();
  ctx.translate(STATE.cam.x, STATE.cam.y + TOPBAR_H);
  for (let i = STATE.animations.length - 1; i >= 0; i--) {
    const a = STATE.animations[i];
    if (a.kind === "dmgB") continue; // shown only during battle scene
    a.y += a.vy;
    a.ttl--;
    if (a.ttl <= 0) { STATE.animations.splice(i, 1); continue; }
    if (a.kind === "evolve") {
      // expanding gold ring burst behind the rising text
      const prog = (50 - a.ttl) / 50;
      const rad = 8 + prog * 34;
      ctx.strokeStyle = `rgba(240, 198, 116, ${1 - prog})`;
      ctx.lineWidth = 3;
      ctx.beginPath();
      ctx.arc(a.x, a.y + 6, rad, 0, Math.PI * 2);
      ctx.stroke();
      ctx.strokeStyle = `rgba(255, 248, 220, ${(1 - prog) * 0.6})`;
      ctx.lineWidth = 1;
      ctx.beginPath();
      ctx.arc(a.x, a.y + 6, rad * 0.6, 0, Math.PI * 2);
      ctx.stroke();
    }
    ctx.font = "bold 14px 'Courier New', monospace";
    ctx.textAlign = "center";
    ctx.fillStyle = "#000";
    ctx.fillText(a.text, a.x + 1, a.y + 1);
    ctx.fillStyle = a.color;
    ctx.fillText(a.text, a.x, a.y);
  }
  ctx.restore();
}

function renderTopBar() {
  ctx.fillStyle = PAL.panel;
  ctx.fillRect(0, 0, CANVAS_W, TOPBAR_H);
  ctx.fillStyle = PAL.inkFaint;
  ctx.fillRect(0, TOPBAR_H - 1, CANVAS_W, 1);

  ctx.font = "bold 20px 'Courier New', monospace";
  ctx.textAlign = "left";
  ctx.fillStyle = PAL.gold;
  ctx.fillText("WRAITHSPIRE", 16, 32);
  ctx.font = "10px 'Courier New', monospace";
  ctx.fillStyle = PAL.inkDim;
  ctx.fillText("— SUMMONER'S WAR —", 196, 32);

  ctx.fillStyle = PLAYERS[STATE.currentPlayer].color;
  ctx.font = "bold 18px 'Courier New', monospace";
  ctx.textAlign = "center";
  ctx.fillText("TURN " + STATE.turn + " — " + PLAYERS[STATE.currentPlayer].name + " PHASE", CANVAS_W / 2, 30);

  ctx.fillStyle = PAL.inkDim;
  ctx.font = "11px 'Courier New', monospace";
  ctx.textAlign = "right";
  const trackLabel = STATE.music.wanted
    ? "♪ " + (TRACKS[STATE.music.trackIndex] || TRACKS[0]).name
    : "music OFF";
  ctx.fillText("E end turn  |  M mute  |  N next  |  " + trackLabel, CANVAS_W - 16, 30);
  ctx.textAlign = "left";
}

function renderSidebar() {
  ctx.fillStyle = PAL.panel;
  ctx.fillRect(SIDEBAR_X, TOPBAR_H, SIDEBAR_W, CANVAS_H - TOPBAR_H);
  ctx.fillStyle = PAL.inkFaint;
  ctx.fillRect(SIDEBAR_X, TOPBAR_H, 1, CANVAS_H - TOPBAR_H);

  let y = TOPBAR_H + 24;
  ctx.font = "bold 14px 'Courier New', monospace";
  ctx.textAlign = "left";
  for (const p of PLAYERS) {
    const m = masterOf(p.id);
    ctx.fillStyle = p.color;
    ctx.fillText(p.name + " ARCHON", SIDEBAR_X + 14, y);
    ctx.font = "12px 'Courier New', monospace";
    ctx.fillStyle = PAL.ink;
    if (m) {
      drawStatBar(SIDEBAR_X + 14, y + 12, SIDEBAR_W - 28, 10, m.hp, m.maxHp, "#5fd06a", "HP");
      drawStatBar(SIDEBAR_X + 14, y + 28, SIDEBAR_W - 28, 10, m.mp, m.maxMp, "#7aa8e0", "MP");
    } else {
      ctx.fillStyle = PAL.red;
      ctx.fillText("FALLEN", SIDEBAR_X + 14, y + 18);
    }
    const towers = MAP.towers.filter(t => t.owner === p.id).length;
    ctx.fillStyle = PAL.inkDim;
    ctx.font = "11px 'Courier New', monospace";
    ctx.fillText("Spires held: " + towers + "  (+" + (towers * 2) + " MP/turn)", SIDEBAR_X + 14, y + 52);
    ctx.font = "bold 14px 'Courier New', monospace";
    y += 76;
  }

  ctx.fillStyle = PAL.inkFaint;
  ctx.fillRect(SIDEBAR_X + 12, y, SIDEBAR_W - 24, 1);
  y += 8;

  ctx.font = "11px 'Courier New', monospace";
  if (STATE.hover && inBounds(STATE.hover.q, STATE.hover.r)) {
    const cell = cellAt(STATE.hover);
    const t = TERRAIN[cell.terrain];
    ctx.fillStyle = PAL.gold;
    ctx.fillText("TERRAIN: " + t.name.toUpperCase(), SIDEBAR_X + 14, y + 12);
    ctx.fillStyle = PAL.inkDim;
    ctx.fillText("move cost " + (t.moveCost === 99 ? "X" : t.moveCost), SIDEBAR_X + 14, y + 26);
    ctx.fillText("DEF", SIDEBAR_X + 14, y + 42);
    drawDefStars(SIDEBAR_X + 48, y + 38, t.def);
    y += 52;
    // which elements this terrain empowers (+20% attack)
    const emp = elementsEmpoweredBy(cell.terrain);
    if (emp.length) {
      ctx.fillStyle = PAL.inkDim;
      ctx.font = "10px 'Courier New', monospace";
      ctx.fillText("Empowers:", SIDEBAR_X + 14, y);
      let ex = SIDEBAR_X + 84;
      for (const e of emp) {
        ctx.fillStyle = ELEMENT[e].color;
        ctx.fillText(ELEMENT[e].short, ex, y);
        ex += 34;
      }
      ctx.font = "11px 'Courier New', monospace";
      y += 16;
    }
    if (cell.terrain === "tower" || cell.terrain === "castle") {
      const owner = cell.owner === null ? "neutral" : PLAYERS[cell.owner].name;
      ctx.fillStyle = cell.owner === null ? PAL.neutral : PLAYERS[cell.owner].color;
      ctx.fillText("held by: " + owner, SIDEBAR_X + 14, y);
      y += 16;
    }
    const u = unitAt(STATE.hover.q, STATE.hover.r);
    if (u) {
      const el = ELEMENT[u.element];
      ctx.fillStyle = el.color;
      ctx.font = "bold 12px 'Courier New', monospace";
      ctx.fillText(u.name.toUpperCase() + "  [" + el.short + "]", SIDEBAR_X + 14, y + 14);
      ctx.fillStyle = PAL.ink;
      ctx.font = "11px 'Courier New', monospace";
      ctx.fillText("HP " + u.hp + "/" + u.maxHp + "    ATK " + u.power, SIDEBAR_X + 14, y + 28);
      ctx.fillText("DEF " + u.def + "    RNG " + u.range + "    MOV " + u.move, SIDEBAR_X + 14, y + 42);
      ctx.fillStyle = u.acted ? PAL.inkDim : PAL.green;
      ctx.fillText(u.acted ? "spent this turn" : "ready", SIDEBAR_X + 14, y + 56);
      y += 70;
      const ua = affinityFor(u.element, cell.terrain);
      if (ua) {
        ctx.fillStyle = PAL.gold;
        ctx.fillText("* empowered: " + ua.label + " (+20% atk)", SIDEBAR_X + 14, y);
        y += 16;
      }
    }
  }

  ctx.fillStyle = PAL.inkFaint;
  ctx.fillRect(SIDEBAR_X + 12, CANVAS_H - 170, SIDEBAR_W - 24, 1);
  ctx.fillStyle = PAL.gold;
  ctx.font = "bold 10px 'Courier New', monospace";
  ctx.fillText("BATTLE LOG", SIDEBAR_X + 14, CANVAS_H - 154);
  ctx.font = "10px 'Courier New', monospace";
  for (let i = 0; i < 10; i++) {
    const line = STATE.log[i];
    if (!line) break;
    ctx.fillStyle = i === 0 ? PAL.ink : PAL.inkDim;
    wrapText(line, SIDEBAR_X + 14, CANVAS_H - 138 + i * 13, SIDEBAR_W - 26, 12);
  }
}

// Defense rating as a row of gold diamonds (filled = terrain def points).
function drawDefStars(x, y, n) {
  const max = 5;
  for (let i = 0; i < max; i++) {
    const cx = x + i * 11;
    ctx.fillStyle = i < n ? PAL.gold : "#3a3622";
    ctx.beginPath();
    ctx.moveTo(cx, y - 4); ctx.lineTo(cx + 4, y); ctx.lineTo(cx, y + 4); ctx.lineTo(cx - 4, y);
    ctx.closePath(); ctx.fill();
  }
  ctx.textAlign = "left";
}

function drawStatBar(x, y, w, h, val, max, color, label) {
  ctx.fillStyle = "#000";
  ctx.fillRect(x, y, w, h);
  ctx.fillStyle = "#1c1828";
  ctx.fillRect(x + 1, y + 1, w - 2, h - 2);
  const frac = Math.max(0, val / max);
  ctx.fillStyle = color;
  ctx.fillRect(x + 1, y + 1, Math.round((w - 2) * frac), h - 2);
  ctx.fillStyle = PAL.ink;
  ctx.font = "9px 'Courier New', monospace";
  ctx.textAlign = "left";
  ctx.fillText(label, x + 4, y + h - 2);
  ctx.textAlign = "right";
  ctx.fillText(val + "/" + max, x + w - 4, y + h - 2);
  // Reset textAlign so callers don't inherit "right" — previously this leak
  // caused sidebar text (Spires held, BATTLE LOG) to render right-aligned
  // at the panel's left edge, drifting off the left side of the sidebar.
  ctx.textAlign = "left";
}

function wrapText(text, x, y, maxW, lh) {
  const words = text.split(" ");
  let line = "";
  for (const w of words) {
    const test = line ? line + " " + w : w;
    if (ctx.measureText(test).width > maxW && line) {
      ctx.fillText(line, x, y);
      y += lh; line = w;
    } else {
      line = test;
    }
  }
  if (line) ctx.fillText(line, x, y);
}

function renderMenu() {
  if (!STATE.menu) return;
  const m = STATE.menu;
  const r = menuRect(m);
  const { x, y, w, h, padX, padY, lineH } = r;

  ctx.fillStyle = "rgba(8, 6, 14, 0.95)";
  ctx.fillRect(x, y, w, h);
  ctx.strokeStyle = PAL.gold;
  ctx.lineWidth = 2;
  ctx.strokeRect(x + 0.5, y + 0.5, w - 1, h - 1);

  ctx.font = "14px 'Courier New', monospace";
  ctx.textAlign = "left";
  for (let i = 0; i < m.items.length; i++) {
    const it = m.items[i];
    if (i === m.index) {
      ctx.fillStyle = PAL.gold;
      ctx.fillRect(x + 3, y + padY + i * lineH - 2, w - 6, lineH);
      ctx.fillStyle = PAL.bg;
    } else {
      ctx.fillStyle = it.disabled ? PAL.inkFaint : PAL.ink;
    }
    ctx.fillText(it.label, x + padX, y + padY + i * lineH + 14);
  }
}

function renderBanner() {
  if (!STATE.banner) return;
  STATE.banner.ttl--;
  if (STATE.banner.ttl <= 0) { STATE.banner = null; return; }
  const alpha = Math.min(1, STATE.banner.ttl / 30, (90 - STATE.banner.ttl) / 15 + 0.1);
  ctx.fillStyle = `rgba(8, 6, 14, ${0.7 * alpha})`;
  ctx.fillRect(0, CANVAS_H / 2 - 36, CANVAS_W, 72);
  ctx.font = "bold 32px 'Courier New', monospace";
  ctx.textAlign = "center";
  ctx.fillStyle = `rgba(240, 198, 116, ${alpha})`;
  ctx.fillText(STATE.banner.text, CANVAS_W / 2, CANVAS_H / 2 + 10);
}

// =========================================================================
// 12. Input & action menus
// =========================================================================

function clientToCanvas(ev) {
  const rect = canvas.getBoundingClientRect();
  return {
    x: (ev.clientX - rect.left) * (CANVAS_W / rect.width),
    y: (ev.clientY - rect.top) * (CANVAS_H / rect.height),
  };
}

function onMouseMove(ev) {
  const p = clientToCanvas(ev);
  // Menu hover takes precedence — move the selection cursor to whichever
  // item the mouse is over.
  if (STATE.menu) {
    const rect = menuRect(STATE.menu);
    if (p.x >= rect.x && p.x <= rect.x + rect.w && p.y >= rect.y && p.y <= rect.y + rect.h) {
      const idx = Math.floor((p.y - rect.y - rect.padY) / rect.lineH);
      if (idx >= 0 && idx < STATE.menu.items.length && !STATE.menu.items[idx].disabled) {
        STATE.menu.index = idx;
      }
    }
  }
  if (p.x > MAP_W || p.y < TOPBAR_H) { STATE.hover = null; return; }
  STATE.hover = pixelToAxial(p.x - STATE.cam.x, p.y - STATE.cam.y - TOPBAR_H);
}

// Single source of truth for where the menu is drawn on screen so the
// click hit-test and the renderer don't drift.
function menuRect(m) {
  const padX = 12, padY = 10, lineH = 20;
  const w = m.kind === "summonMenu" ? 200 : 150;
  const h = padY * 2 + m.items.length * lineH;
  const x = Math.min(CANVAS_W - SIDEBAR_W - w - 8, Math.max(8, m.anchor.x + 18));
  const y = Math.min(CANVAS_H - h - 8, Math.max(TOPBAR_H + 8, m.anchor.y - h / 2));
  return { x, y, w, h, padX, padY, lineH };
}

function onClick(ev) {
  startMusicOnGesture();
  if (STATE.screen === "title") { startNewGame(); return; }
  if (STATE.screen === "gameover") { STATE.screen = "title"; return; }
  if (STATE.screen === "battle") return;
  if (STATE.pendingAI) return;
  if (PLAYERS[STATE.currentPlayer].isAI) return;

  const p = clientToCanvas(ev);

  // If a menu is open, route the click to its hit-test before touching the map.
  if (STATE.menu) {
    const rect = menuRect(STATE.menu);
    if (p.x >= rect.x && p.x <= rect.x + rect.w && p.y >= rect.y && p.y <= rect.y + rect.h) {
      const idx = Math.floor((p.y - rect.y - rect.padY) / rect.lineH);
      if (idx >= 0 && idx < STATE.menu.items.length && !STATE.menu.items[idx].disabled) {
        STATE.menu.index = idx;
        selectMenuItem(STATE.menu.items[idx]);
      }
      return;
    }
    // Clicking outside the menu closes it (Wait-equivalent escape).
    cancelMenu();
    return;
  }

  if (p.x > MAP_W || p.y < TOPBAR_H) return;
  const local = pixelToAxial(p.x - STATE.cam.x, p.y - STATE.cam.y - TOPBAR_H);
  if (!inBounds(local.q, local.r)) return;

  const onUnit = unitAt(local.q, local.r);

  if (STATE.selected && STATE.reachable) {
    const k = hexKey(local.q, local.r);
    if (STATE.reachable.has(k)) {
      const unit = STATE.selected;
      moveUnitTo(unit, local.q, local.r);
      const targets = computeAttackTargets(unit, unit.q, unit.r);
      const cellHere = cellAt({ q: unit.q, r: unit.r });
      const items = [];
      if (targets.size > 0) items.push({ label: "Attack", kind: "attackMode" });
      if (canCapture(unit, cellHere)) items.push({ label: "Capture", kind: "capture" });
      if (unit.isMaster && unit.mp >= 6) items.push({ label: "Summon", kind: "summon" });
      items.push({ label: "Wait", kind: "wait" });
      STATE.reachable = null;
      STATE.attackTargets = null;
      const px2 = axialToPixel(unit.q, unit.r);
      STATE.menu = {
        kind: "postMove", unit, items, index: 0,
        anchor: { x: px2.x + STATE.cam.x, y: px2.y + STATE.cam.y + TOPBAR_H },
      };
      return;
    } else if (STATE.attackTargets && STATE.attackTargets.has(hexKey(local.q, local.r))) {
      const target = unitAt(local.q, local.r);
      if (target) {
        const atk = STATE.selected;
        atk.acted = true;
        STATE.selected = null; STATE.reachable = null; STATE.attackTargets = null;
        beginBattle(atk, target);
        return;
      }
    } else {
      STATE.selected = null; STATE.reachable = null; STATE.attackTargets = null;
      return;
    }
  }

  if (onUnit && onUnit.owner === STATE.currentPlayer && !onUnit.acted) {
    STATE.selected = onUnit;
    STATE.reachable = computeReachable(onUnit);
    STATE.attackTargets = computeAttackTargets(onUnit, onUnit.q, onUnit.r);
  } else {
    STATE.selected = null; STATE.reachable = null; STATE.attackTargets = null;
  }
}

function moveUnitTo(unit, q, r) { unit.q = q; unit.r = r; }

function onKey(ev) {
  startMusicOnGesture();
  if (ev.key === "m" || ev.key === "M") { toggleMusic(); return; }
  if (ev.key === "n" || ev.key === "N") { cycleTrack(); return; }
  if (STATE.screen === "title") {
    if (ev.key === "Enter" || ev.key === " ") startNewGame();
    return;
  }
  if (STATE.screen === "gameover") {
    if (ev.key === "Enter" || ev.key === " ") STATE.screen = "title";
    return;
  }
  if (STATE.screen === "battle") return;
  if (PLAYERS[STATE.currentPlayer].isAI && STATE.pendingAI) return;

  if (STATE.menu) {
    if (ev.key === "ArrowDown" || ev.key === "s") {
      do { STATE.menu.index = (STATE.menu.index + 1) % STATE.menu.items.length; }
      while (STATE.menu.items[STATE.menu.index].disabled);
    } else if (ev.key === "ArrowUp" || ev.key === "w") {
      do { STATE.menu.index = (STATE.menu.index - 1 + STATE.menu.items.length) % STATE.menu.items.length; }
      while (STATE.menu.items[STATE.menu.index].disabled);
    } else if (ev.key === "Enter" || ev.key === " ") {
      selectMenuItem(STATE.menu.items[STATE.menu.index]);
    } else if (ev.key === "Escape") {
      cancelMenu();
    }
    return;
  }

  if (ev.key === "e" || ev.key === "E") { endTurn(); return; }
  if (ev.key === "Escape") {
    STATE.selected = null; STATE.reachable = null; STATE.attackTargets = null;
    return;
  }
  const PAN = 36;
  if (ev.key === "ArrowLeft")  STATE.cam.x = Math.min(0, STATE.cam.x + PAN);
  if (ev.key === "ArrowRight") STATE.cam.x = Math.max(MAP_W - mapPixelWidth(), STATE.cam.x - PAN);
  if (ev.key === "ArrowUp")    STATE.cam.y = Math.min(0, STATE.cam.y + PAN);
  if (ev.key === "ArrowDown")  STATE.cam.y = Math.max(MAP_H - mapPixelHeight(), STATE.cam.y - PAN);
}

function mapPixelWidth() { return HEX_STEP_X * (COLS + 0.5) + 12; }
function mapPixelHeight() { return HEX_STEP_Y * ROWS + HEX_SIZE + 12; }

function selectMenuItem(item) {
  if (item.disabled) return;
  const unit = STATE.menu.unit;
  if (item.kind === "wait") {
    unit.acted = true; closeMenu();
  } else if (item.kind === "attackMode") {
    STATE.selected = unit;
    STATE.attackTargets = computeAttackTargets(unit, unit.q, unit.r);
    STATE.reachable = null;
    STATE.menu = null;
  } else if (item.kind === "capture") {
    const cell = cellAt({ q: unit.q, r: unit.r });
    if (cell && cell.terrain === "tower") {
      cell.owner = unit.owner;
      pushLog(unit.name + " captures a spire.");
      beep(520, 0.12, "triangle", 0.18);
    }
    unit.acted = true; closeMenu();
  } else if (item.kind === "summon") {
    const items = SUMMON_LIST.map(k => {
      const t = UNIT_TYPES[k];
      const aff = unit.mp >= t.cost;
      const el = ELEMENT[t.element].short;
      return {
        label: `${t.name.padEnd(11)} ${el} ${String(t.cost).padStart(2)}MP`,
        kind: "summonChoice", choice: k, disabled: !aff,
      };
    });
    items.push({ label: "Back", kind: "back" });
    const px = axialToPixel(unit.q, unit.r);
    STATE.menu = {
      kind: "summonMenu", unit, items, index: items.findIndex(i => !i.disabled),
      anchor: { x: px.x + STATE.cam.x, y: px.y + STATE.cam.y + TOPBAR_H },
    };
  } else if (item.kind === "summonChoice") {
    const slot = findSummonSlot(unit);
    if (!slot) { pushLog("No open hex to summon into."); return; }
    const cost = UNIT_TYPES[item.choice].cost;
    unit.mp -= cost;
    const u = makeUnit(item.choice, unit.owner, slot.q, slot.r);
    u.acted = true;
    STATE.units.push(u);
    pushLog(unit.name + " summons " + u.name + ".");
    beep(660, 0.08, "triangle", 0.18);
    unit.acted = true; closeMenu();
  } else if (item.kind === "back") {
    const items = [];
    const targets = computeAttackTargets(unit, unit.q, unit.r);
    const cellHere = cellAt({ q: unit.q, r: unit.r });
    if (targets.size > 0) items.push({ label: "Attack", kind: "attackMode" });
    if (canCapture(unit, cellHere)) items.push({ label: "Capture", kind: "capture" });
    if (unit.isMaster && unit.mp >= 6) items.push({ label: "Summon", kind: "summon" });
    items.push({ label: "Wait", kind: "wait" });
    const px = axialToPixel(unit.q, unit.r);
    STATE.menu = {
      kind: "postMove", unit, items, index: 0,
      anchor: { x: px.x + STATE.cam.x, y: px.y + STATE.cam.y + TOPBAR_H },
    };
  }
}

function closeMenu() {
  STATE.menu = null;
  STATE.selected = null;
  STATE.reachable = null;
  STATE.attackTargets = null;
}

function cancelMenu() {
  if (!STATE.menu) return;
  // Submenu (Summon picker) — back out to the parent post-move menu so
  // the player can still pick a different action for this unit.
  if (STATE.menu.kind === "summonMenu") {
    const unit = STATE.menu.unit;
    const items = [];
    const targets = computeAttackTargets(unit, unit.q, unit.r);
    const cellHere = cellAt({ q: unit.q, r: unit.r });
    if (targets.size > 0) items.push({ label: "Attack", kind: "attackMode" });
    if (canCapture(unit, cellHere)) items.push({ label: "Capture", kind: "capture" });
    if (unit.isMaster && unit.mp >= 6) items.push({ label: "Summon", kind: "summon" });
    items.push({ label: "Wait", kind: "wait" });
    const px = axialToPixel(unit.q, unit.r);
    STATE.menu = {
      kind: "postMove", unit, items, index: 0,
      anchor: { x: px.x + STATE.cam.x, y: px.y + STATE.cam.y + TOPBAR_H },
    };
    return;
  }
  // Post-move menu cancel commits the move (move is already applied; this
  // is equivalent to Wait). Without this, the unit becomes reselectable
  // and the player can repeatedly move it.
  if (STATE.menu.unit && !STATE.menu.unit.acted) STATE.menu.unit.acted = true;
  closeMenu();
}

// =========================================================================
// 13. Turn / phase machinery
// =========================================================================

function endTurn() {
  if (STATE.menu) closeMenu();
  for (const u of aliveUnits(STATE.currentPlayer)) u.acted = true;
  STATE.currentPlayer = 1 - STATE.currentPlayer;
  if (STATE.currentPlayer === 0) STATE.turn++;
  const m = masterOf(STATE.currentPlayer);
  if (m) {
    const towerBonus = MAP.towers.filter(t => t.owner === STATE.currentPlayer).length * 2;
    const regen = m.mpRegen + towerBonus;
    m.mp = Math.min(m.maxMp, m.mp + regen);
    pushLog(PLAYERS[STATE.currentPlayer].name + " gains " + regen + " MP (towers +" + towerBonus + ").");
  }
  for (const u of aliveUnits(STATE.currentPlayer)) {
    u.acted = false;
    const c = cellAt({ q: u.q, r: u.r });
    if (c && c.terrain === "tower" && c.owner === u.owner) u.hp = Math.min(u.maxHp, u.hp + 2);
    if (c && c.terrain === "castle" && c.owner === u.owner) u.hp = Math.min(u.maxHp, u.hp + 4);
    tryEvolve(u, c); // level-4+ on owned tower/castle → terminal form
  }
  STATE.selected = null;
  STATE.reachable = null;
  STATE.attackTargets = null;
  STATE.banner = { text: PLAYERS[STATE.currentPlayer].name + " — TURN " + STATE.turn, ttl: 80 };
  checkWinCondition();
  if (STATE.screen !== "play") return;
  centerCameraOn(masterOf(STATE.currentPlayer));
  if (PLAYERS[STATE.currentPlayer].isAI) {
    STATE.pendingAI = true;
    setTimeout(() => { STATE.pendingAI = false; aiTakeTurn(); }, 800);
  }
}

// =========================================================================
// 14. UI screens (title, win/lose)
// =========================================================================

function renderTitle() {
  const grad = ctx.createLinearGradient(0, 0, 0, CANVAS_H);
  grad.addColorStop(0, "#1a1130");
  grad.addColorStop(1, "#05030c");
  ctx.fillStyle = grad;
  ctx.fillRect(0, 0, CANVAS_W, CANVAS_H);

  // synthwave grid floor
  ctx.save();
  ctx.translate(CANVAS_W / 2, CANVAS_H * 0.62);
  const horizon = CANVAS_H * 0.62;
  ctx.strokeStyle = "rgba(200, 80, 200, 0.4)";
  ctx.lineWidth = 1;
  // vanishing lines
  for (let i = -8; i <= 8; i++) {
    ctx.beginPath();
    ctx.moveTo(0, 0);
    ctx.lineTo(i * 200, CANVAS_H - horizon);
    ctx.stroke();
  }
  // horizontal lines (perspective)
  for (let i = 1; i < 12; i++) {
    const yy = Math.pow(i / 12, 2.2) * (CANVAS_H - horizon);
    const w = (i / 12) * CANVAS_W * 0.9;
    ctx.strokeStyle = `rgba(200, 80, 200, ${0.6 - i * 0.04})`;
    ctx.beginPath();
    ctx.moveTo(-w, yy);
    ctx.lineTo(w, yy);
    ctx.stroke();
  }
  ctx.restore();

  // stars
  for (let i = 0; i < 120; i++) {
    const x = (i * 73 + Math.floor(frame / 4)) % CANVAS_W;
    const y = (i * 31) % (CANVAS_H * 0.55);
    const tw = (Math.sin(frame / 20 + i) + 1) / 2;
    ctx.fillStyle = `rgba(220, 210, 255, ${0.3 + tw * 0.5})`;
    ctx.fillRect(x, y, 2, 2);
  }

  // sun behind logo
  const sg = ctx.createLinearGradient(0, CANVAS_H * 0.20, 0, CANVAS_H * 0.55);
  sg.addColorStop(0, "#ff7f50");
  sg.addColorStop(0.5, "#c8418a");
  sg.addColorStop(1, "#5a2a8a");
  ctx.fillStyle = sg;
  ctx.beginPath();
  ctx.arc(CANVAS_W / 2, CANVAS_H * 0.36, 130, 0, Math.PI * 2);
  ctx.fill();
  // sun bars
  ctx.fillStyle = "#1a1130";
  for (let i = 0; i < 5; i++) {
    ctx.fillRect(CANVAS_W / 2 - 130, CANVAS_H * 0.36 + 60 + i * 14, 260, 4);
  }

  ctx.font = "bold 86px 'Courier New', monospace";
  ctx.textAlign = "center";
  ctx.fillStyle = "#1a1024";
  ctx.fillText("WRAITHSPIRE", CANVAS_W / 2 + 6, CANVAS_H * 0.38 + 6);
  ctx.fillStyle = PAL.gold;
  ctx.fillText("WRAITHSPIRE", CANVAS_W / 2, CANVAS_H * 0.38);

  ctx.font = "bold 22px 'Courier New', monospace";
  ctx.fillStyle = PAL.ink;
  ctx.fillText("— SUMMONER'S WAR —", CANVAS_W / 2, CANVAS_H * 0.46);

  // archons preview
  drawBattleSprite(ctx, { owner: 0, isMaster: true, sprite: "archon" }, CANVAS_W / 2 - 180, CANVAS_H * 0.66, +1, "idle", frame);
  drawBattleSprite(ctx, { owner: 1, isMaster: true, sprite: "archon" }, CANVAS_W / 2 + 180, CANVAS_H * 0.66, -1, "idle", frame);
  ctx.font = "bold 14px 'Courier New', monospace";
  ctx.fillStyle = PAL.p0;
  ctx.fillText("AZURE", CANVAS_W / 2 - 180, CANVAS_H * 0.78);
  ctx.fillStyle = PAL.p1;
  ctx.fillText("CRIMSON", CANVAS_W / 2 + 180, CANVAS_H * 0.78);

  ctx.font = "13px 'Courier New', monospace";
  ctx.fillStyle = PAL.inkDim;
  const lore = [
    "Two summoning archons command the frontier.",
    "Bind elemental beasts. Seize the spires.",
    "Cast the rival Archon down. Inherit the realm.",
  ];
  for (let i = 0; i < lore.length; i++) {
    ctx.fillText(lore[i], CANVAS_W / 2, CANVAS_H * 0.84 + i * 18);
  }

  const blink = Math.floor(frame / 30) % 2 === 0;
  if (blink) {
    ctx.font = "bold 16px 'Courier New', monospace";
    ctx.fillStyle = PAL.gold;
    ctx.fillText("CLICK OR PRESS ENTER TO BEGIN", CANVAS_W / 2, CANVAS_H * 0.95);
  }
  ctx.font = "10px 'Courier New', monospace";
  ctx.fillStyle = PAL.inkFaint;
  ctx.fillText("v1.1 — press M to toggle music", CANVAS_W / 2, CANVAS_H - 12);
}

function renderGameOver() {
  ctx.fillStyle = "#05030c";
  ctx.fillRect(0, 0, CANVAS_W, CANVAS_H);
  const won = STATE.winner === 0;
  const text = (won ? "AZURE" : "CRIMSON") + " TRIUMPHS";
  const color = won ? PAL.p0 : PAL.p1;

  drawBattleSprite(ctx, { owner: won ? 0 : 1, isMaster: true, sprite: "archon" }, CANVAS_W / 2, CANVAS_H / 2 - 40, +1, "idle", frame);

  ctx.font = "bold 56px 'Courier New', monospace";
  ctx.textAlign = "center";
  ctx.fillStyle = "#1a1024";
  ctx.fillText(text, CANVAS_W / 2 + 4, CANVAS_H / 2 + 80 + 4);
  ctx.fillStyle = color;
  ctx.fillText(text, CANVAS_W / 2, CANVAS_H / 2 + 80);

  ctx.font = "16px 'Courier New', monospace";
  ctx.fillStyle = PAL.ink;
  ctx.fillText("Turns elapsed: " + STATE.turn, CANVAS_W / 2, CANVAS_H / 2 + 116);

  const blink = Math.floor(frame / 30) % 2 === 0;
  if (blink) {
    ctx.font = "14px 'Courier New', monospace";
    ctx.fillStyle = PAL.gold;
    ctx.fillText("PRESS ENTER TO RETURN", CANVAS_W / 2, CANVAS_H / 2 + 170);
  }
}

// =========================================================================
// 15. Audio engine (SFX + 80s synth music loop)
// =========================================================================

const audio = {
  ctx: null,
  master: null,
  musicGain: null,
  enabled: false,
  step: 0,
  interval: null,
  duck: 1.0,
};

function ensureAudio() {
  if (audio.ctx) return;
  try {
    audio.ctx = new (window.AudioContext || window.webkitAudioContext)();
    audio.master = audio.ctx.createGain();
    audio.master.gain.value = 0.6;
    audio.master.connect(audio.ctx.destination);
    audio.musicGain = audio.ctx.createGain();
    audio.musicGain.gain.value = 0.45;
    audio.musicGain.connect(audio.master);

    // Delay-based fake reverb send bus. Synths can route some signal here
    // via the `reverbSend` arg on playSynth; the feedback loop with a
    // lowpass filter approximates a dark plate reverb tail. Cheap, no IR
    // sample needed, and gives the loops the spacious 80s feel.
    audio.reverbIn = audio.ctx.createGain();
    audio.reverbIn.gain.value = 1.0;
    const delay = audio.ctx.createDelay(1.0);
    delay.delayTime.value = 0.21;
    const feedback = audio.ctx.createGain();
    feedback.gain.value = 0.48;
    const reverbFilter = audio.ctx.createBiquadFilter();
    reverbFilter.type = "lowpass";
    reverbFilter.frequency.value = 3500;
    const reverbOut = audio.ctx.createGain();
    reverbOut.gain.value = 0.6;
    audio.reverbIn.connect(delay);
    delay.connect(reverbFilter);
    reverbFilter.connect(feedback);
    feedback.connect(delay);
    reverbFilter.connect(reverbOut);
    reverbOut.connect(audio.musicGain);

    // Reusable noise buffer for hi-hat / snare layers (avoid allocating
    // a fresh AudioBuffer every 16th note).
    const bufLen = audio.ctx.sampleRate;
    audio.noiseBuf = audio.ctx.createBuffer(1, bufLen, audio.ctx.sampleRate);
    const data = audio.noiseBuf.getChannelData(0);
    for (let i = 0; i < bufLen; i++) data[i] = Math.random() * 2 - 1;
  } catch (e) { /* audio unavailable */ }
}

function startMusicOnGesture() {
  if (audio.enabled) return;
  if (!STATE.music.wanted) return;
  ensureAudio();
  if (!audio.ctx) return;
  if (audio.ctx.state === "suspended") audio.ctx.resume();
  audio.enabled = true;
  audio.step = 0;
  audio.interval = setInterval(musicTick, 170); // ~88 BPM in 16ths
  STATE.music.started = true;
}

function stopMusic() {
  audio.enabled = false;
  if (audio.interval) { clearInterval(audio.interval); audio.interval = null; }
}

function toggleMusic() {
  STATE.music.wanted = !STATE.music.wanted;
  if (STATE.music.wanted) startMusicOnGesture();
  else stopMusic();
}

function musicDuck(level) { audio.duck = level; }

// Six original 80s-dark-synth-fantasy loops. Each track is a 4-bar minor-key
// progression with its own arp pattern and sparse lead melody. Pure chord
// progressions and pentatonic phrases are not copyrightable expression —
// these are written as generic genre-style patterns.
const TRACKS = [
  {
    name: "WRAITHSPIRE FRONTIER",
    // i-VI-III-VII in A minor — the classic "main theme" feel.
    chords: [
      { root: 110.00, third: 130.81, fifth: 164.81 }, // Am
      { root:  87.31, third: 110.00, fifth: 130.81 }, // F
      { root:  65.41, third:  82.41, fifth:  98.00 }, // C
      { root:  98.00, third: 123.47, fifth: 146.83 }, // G
    ],
    arp: [0, 1, 2, 1, 0, 2, 1, 2, 0, 1, 2, 1, 0, 2, 1, 2],
    lead: [
      [{ s: 4, hz: 440 }, { s: 8, hz: 523.25 }, { s: 12, hz: 392 }],
      [{ s: 0, hz: 349.23 }, { s: 8, hz: 440 }],
      [{ s: 4, hz: 392 }, { s: 10, hz: 329.63 }, { s: 14, hz: 261.63 }],
      [{ s: 2, hz: 293.66 }, { s: 8, hz: 392 }, { s: 12, hz: 440 }],
    ],
  },
  {
    name: "SHADOW VEIL",
    // D minor, slower descending arp — more brooding/atmospheric.
    chords: [
      { root: 73.42, third:  87.31, fifth: 110.00 }, // Dm
      { root: 58.27, third:  73.42, fifth:  87.31 }, // Bb
      { root: 87.31, third: 110.00, fifth: 130.81 }, // F
      { root: 65.41, third:  82.41, fifth:  98.00 }, // C
    ],
    arp: [2, 1, 0, 1, 2, 1, 0, 1, 2, 1, 0, 1, 2, 1, 0, 1],
    lead: [
      [{ s: 0, hz: 293.66 }, { s: 8, hz: 349.23 }, { s: 12, hz: 440 }],
      [{ s: 4, hz: 466.16 }, { s: 10, hz: 392 }],
      [{ s: 0, hz: 349.23 }, { s: 8, hz: 261.63 }],
      [{ s: 4, hz: 261.63 }, { s: 8, hz: 311.13 }, { s: 14, hz: 233.08 }],
    ],
  },
  {
    name: "IRON CATACOMBS",
    // E minor, bouncing arp, energetic exploration feel.
    chords: [
      { root: 82.41, third:  98.00, fifth: 123.47 }, // Em
      { root: 65.41, third:  82.41, fifth:  98.00 }, // C
      { root: 98.00, third: 123.47, fifth: 146.83 }, // G
      { root: 73.42, third:  92.50, fifth: 110.00 }, // D
    ],
    arp: [0, 2, 1, 2, 0, 2, 1, 2, 0, 2, 1, 2, 0, 2, 1, 2],
    lead: [
      [{ s: 0, hz: 329.63 }, { s: 6, hz: 392 }, { s: 12, hz: 493.88 }],
      [{ s: 4, hz: 523.25 }, { s: 10, hz: 392 }],
      [{ s: 2, hz: 587.33 }, { s: 8, hz: 493.88 }, { s: 12, hz: 392 }],
      [{ s: 0, hz: 440 }, { s: 8, hz: 369.99 }, { s: 14, hz: 293.66 }],
    ],
  },
  {
    name: "PYRE OF STARS",
    // i-VII-VI-i descending bass — dramatic Andalusian cadence in A minor.
    chords: [
      { root: 110.00, third: 130.81, fifth: 164.81 }, // Am
      { root:  98.00, third: 123.47, fifth: 146.83 }, // G
      { root:  87.31, third: 110.00, fifth: 130.81 }, // F
      { root:  82.41, third:  98.00, fifth: 123.47 }, // Em
    ],
    arp: [0, 1, 2, 1, 0, 1, 2, 1, 0, 1, 2, 1, 0, 1, 2, 1],
    lead: [
      [{ s: 0, hz: 440 }, { s: 6, hz: 523.25 }, { s: 12, hz: 659.25 }],
      [{ s: 0, hz: 587.33 }, { s: 8, hz: 392 }],
      [{ s: 0, hz: 523.25 }, { s: 6, hz: 440 }, { s: 12, hz: 349.23 }],
      [{ s: 0, hz: 329.63 }, { s: 4, hz: 246.94 }, { s: 12, hz: 329.63 }],
    ],
  },
  {
    name: "TOWER WATCH",
    // C minor, octave-jumping sparse arp — melancholic standing-vigil mood.
    chords: [
      { root: 65.41, third: 77.78, fifth:  98.00 }, // Cm
      { root: 98.00, third: 116.54, fifth: 146.83 }, // Gm
      { root: 51.91, third: 65.41, fifth:  77.78 }, // Ab
      { root: 58.27, third: 73.42, fifth:  87.31 }, // Bb
    ],
    arp: [0, 2, 0, 2, 0, 2, 0, 2, 0, 2, 0, 2, 0, 2, 0, 2],
    lead: [
      [{ s: 4, hz: 261.63 }, { s: 12, hz: 311.13 }],
      [{ s: 0, hz: 391.99 }, { s: 8, hz: 466.16 }],
      [{ s: 4, hz: 415.31 }, { s: 12, hz: 311.13 }],
      [{ s: 0, hz: 349.23 }, { s: 8, hz: 466.16 }, { s: 14, hz: 392 }],
    ],
  },
  {
    name: "HEX STORM",
    // E minor with secondary minor, syncopated busy lead — combat tension.
    chords: [
      { root: 82.41, third:  98.00, fifth: 123.47 }, // Em
      { root: 61.74, third:  73.42, fifth:  92.50 }, // Bm (low)
      { root: 65.41, third:  82.41, fifth:  98.00 }, // C
      { root: 98.00, third: 123.47, fifth: 146.83 }, // G
    ],
    arp: [0, 2, 1, 2, 1, 0, 1, 2, 0, 2, 1, 2, 1, 0, 1, 2],
    lead: [
      [{ s: 2, hz: 329.63 }, { s: 6, hz: 493.88 }, { s: 10, hz: 587.33 }, { s: 14, hz: 392 }],
      [{ s: 0, hz: 493.88 }, { s: 6, hz: 587.33 }, { s: 12, hz: 369.99 }],
      [{ s: 4, hz: 523.25 }, { s: 8, hz: 659.25 }, { s: 14, hz: 392 }],
      [{ s: 0, hz: 587.33 }, { s: 8, hz: 392 }, { s: 12, hz: 493.88 }],
    ],
  },
];

function musicTick() {
  if (!audio.enabled) return;
  const track = TRACKS[STATE.music.trackIndex] || TRACKS[0];
  const stepGlobal = audio.step++;
  const stepsPerBar = 16;
  const barIdx = Math.floor(stepGlobal / stepsPerBar) % track.chords.length;
  const beat = stepGlobal % stepsPerBar;
  const chord = track.chords[barIdx];
  const notes = [chord.root, chord.third, chord.fifth];

  // -------- DRUMS --------
  // Kick on the 1 and the 3 (beats 1 and 9 of 16 sixteenths).
  if (beat === 0 || beat === 8) playKick(0.5);
  // Snare backbeat on the 2 and 4 (beats 5 and 13).
  if (beat === 4 || beat === 12) playSnare(0.22);
  // Hi-hat on every 8th note, accent on the 16th-note pickups.
  if (beat % 2 === 0) playHihat(beat % 4 === 2 ? 0.10 : 0.06);

  // -------- BASS --------
  // Filter-swept sawtooth bass on downbeats (the "wow" envelope) plus
  // walking notes on the offbeats to keep it moving.
  if (beat === 0 || beat === 8) playBass(chord.root, 0.42, 0.22, 2400);
  if (beat === 4)  playBass(chord.fifth * 0.5, 0.28, 0.13, 1600);
  if (beat === 12) playBass(chord.third * 0.5, 0.28, 0.13, 1600);

  // -------- ARP --------
  // Triangle arp every 16th, light reverb so it sparkles without smearing.
  const arpNote = notes[track.arp[beat] % notes.length] * 2;
  playSynth(arpNote, "triangle", 0.14, 0.05, 4000, undefined, 0.18);

  // -------- PAD --------
  // Sawtooth chord layered with a soft sine octave on bar downbeat. The
  // pad is the main carrier of reverb — high send keeps the loop spacious.
  if (beat === 0) {
    for (const n of notes) playSynth(n * 2, "sawtooth", 1.8, 0.028, 1100, 0.04, 0.45);
    for (const n of notes) playSynth(n * 4, "sine",     1.8, 0.014, 4000, 0.04, 0.35);
  }

  // -------- LEAD --------
  // Lead notes get the most reverb so they sit on top of the mix.
  for (const lead of track.lead[barIdx]) {
    if (lead.s === beat) playSynth(lead.hz, "sawtooth", 0.50, 0.07, 1900, 0.06, 0.55);
  }
}

function cycleTrack() {
  STATE.music.trackIndex = (STATE.music.trackIndex + 1) % TRACKS.length;
  audio.step = 0; // restart the new track at bar 1
  STATE.banner = { text: "♪ " + TRACKS[STATE.music.trackIndex].name, ttl: 60 };
}

function playSynth(freq, type, dur, gain, filterHz, attack, reverbSend) {
  if (!audio.ctx) return;
  const t = audio.ctx.currentTime;
  const osc = audio.ctx.createOscillator();
  const g = audio.ctx.createGain();
  const lp = audio.ctx.createBiquadFilter();
  lp.type = "lowpass";
  lp.frequency.value = filterHz || 2000;
  lp.Q.value = 0.7;
  osc.type = type;
  osc.frequency.value = freq;
  const peak = gain * audio.duck;
  const a = attack || 0.005;
  g.gain.setValueAtTime(0, t);
  g.gain.linearRampToValueAtTime(peak, t + a);
  g.gain.exponentialRampToValueAtTime(0.0001, t + dur);
  osc.connect(lp); lp.connect(g); g.connect(audio.musicGain);
  if (reverbSend && audio.reverbIn) {
    const send = audio.ctx.createGain();
    send.gain.value = reverbSend;
    g.connect(send); send.connect(audio.reverbIn);
  }
  osc.start(t);
  osc.stop(t + dur + 0.05);
}

// Sawtooth bass with a fast filter-envelope sweep — the synthwave "wow"
// signature. Filter opens from 200 Hz up to `sweepTo` Hz over 60 ms, then
// drifts back closed across the note's tail.
function playBass(freq, dur, gain, sweepTo) {
  if (!audio.ctx) return;
  const t = audio.ctx.currentTime;
  const osc = audio.ctx.createOscillator();
  const g = audio.ctx.createGain();
  const lp = audio.ctx.createBiquadFilter();
  lp.type = "lowpass";
  lp.Q.value = 6;
  lp.frequency.setValueAtTime(200, t);
  lp.frequency.linearRampToValueAtTime(sweepTo || 1500, t + 0.06);
  lp.frequency.exponentialRampToValueAtTime(180, t + dur);
  osc.type = "sawtooth";
  osc.frequency.value = freq;
  const peak = gain * audio.duck;
  g.gain.setValueAtTime(0, t);
  g.gain.linearRampToValueAtTime(peak, t + 0.005);
  g.gain.exponentialRampToValueAtTime(0.0001, t + dur);
  osc.connect(lp); lp.connect(g); g.connect(audio.musicGain);
  osc.start(t);
  osc.stop(t + dur + 0.05);
}

// 808-style kick: sine wave pitch-bent from ~110 Hz down to ~40 Hz with
// a quick lowpassed noise click on top for transient body.
function playKick(gain) {
  if (!audio.ctx) return;
  const t = audio.ctx.currentTime;
  const osc = audio.ctx.createOscillator();
  const g = audio.ctx.createGain();
  osc.type = "sine";
  osc.frequency.setValueAtTime(110, t);
  osc.frequency.exponentialRampToValueAtTime(40, t + 0.08);
  g.gain.setValueAtTime(0, t);
  g.gain.linearRampToValueAtTime(gain * audio.duck, t + 0.002);
  g.gain.exponentialRampToValueAtTime(0.0001, t + 0.22);
  osc.connect(g); g.connect(audio.musicGain);
  osc.start(t);
  osc.stop(t + 0.3);

  // Click transient
  const src = audio.ctx.createBufferSource();
  src.buffer = audio.noiseBuf;
  src.loop = false;
  const clickFilt = audio.ctx.createBiquadFilter();
  clickFilt.type = "lowpass";
  clickFilt.frequency.value = 3500;
  const clickG = audio.ctx.createGain();
  clickG.gain.setValueAtTime(gain * 0.5 * audio.duck, t);
  clickG.gain.exponentialRampToValueAtTime(0.0001, t + 0.015);
  src.connect(clickFilt); clickFilt.connect(clickG); clickG.connect(audio.musicGain);
  src.start(t, 0, 0.02);
}

// Snare: noise band-passed at 1.5 kHz with a short tonal "thwack" body
// triangle at 200→100 Hz layered underneath.
function playSnare(gain) {
  if (!audio.ctx) return;
  const t = audio.ctx.currentTime;
  // Noise body
  const src = audio.ctx.createBufferSource();
  src.buffer = audio.noiseBuf;
  const bp = audio.ctx.createBiquadFilter();
  bp.type = "bandpass";
  bp.frequency.value = 1700;
  bp.Q.value = 0.7;
  const ng = audio.ctx.createGain();
  ng.gain.setValueAtTime(0, t);
  ng.gain.linearRampToValueAtTime(gain * audio.duck, t + 0.002);
  ng.gain.exponentialRampToValueAtTime(0.0001, t + 0.13);
  src.connect(bp); bp.connect(ng); ng.connect(audio.musicGain);
  src.start(t, 0, 0.18);
  // Tonal body
  const osc = audio.ctx.createOscillator();
  osc.type = "triangle";
  osc.frequency.setValueAtTime(220, t);
  osc.frequency.exponentialRampToValueAtTime(110, t + 0.06);
  const og = audio.ctx.createGain();
  og.gain.setValueAtTime(0, t);
  og.gain.linearRampToValueAtTime(gain * 0.45 * audio.duck, t + 0.002);
  og.gain.exponentialRampToValueAtTime(0.0001, t + 0.09);
  osc.connect(og); og.connect(audio.musicGain);
  osc.start(t);
  osc.stop(t + 0.15);
  // Small reverb tail on snare for "in the room" feel
  if (audio.reverbIn) {
    const send = audio.ctx.createGain();
    send.gain.value = 0.2;
    ng.connect(send); send.connect(audio.reverbIn);
  }
}

// Closed hi-hat: high-passed noise with a very short envelope.
function playHihat(gain) {
  if (!audio.ctx) return;
  const t = audio.ctx.currentTime;
  const src = audio.ctx.createBufferSource();
  src.buffer = audio.noiseBuf;
  const hp = audio.ctx.createBiquadFilter();
  hp.type = "highpass";
  hp.frequency.value = 7000;
  const g = audio.ctx.createGain();
  g.gain.setValueAtTime(0, t);
  g.gain.linearRampToValueAtTime(gain * audio.duck, t + 0.001);
  g.gain.exponentialRampToValueAtTime(0.0001, t + 0.04);
  src.connect(hp); hp.connect(g); g.connect(audio.musicGain);
  src.start(t, 0, 0.06);
}

function beep(freq, dur, type, gain) {
  ensureAudio();
  if (!audio.ctx) return;
  const t = audio.ctx.currentTime;
  const osc = audio.ctx.createOscillator();
  const g = audio.ctx.createGain();
  osc.type = type || "square";
  osc.frequency.value = freq;
  g.gain.setValueAtTime(0, t);
  g.gain.linearRampToValueAtTime(gain || 0.1, t + 0.005);
  g.gain.exponentialRampToValueAtTime(0.001, t + dur);
  osc.connect(g); g.connect(audio.master);
  osc.start(t);
  osc.stop(t + dur + 0.02);
}

// =========================================================================
// 16. Boot, resize, main loop
// =========================================================================

function boot() {
  canvas = document.getElementById("game");
  ctx = canvas.getContext("2d");
  ctx.imageSmoothingEnabled = false;

  generateMap(123);

  canvas.addEventListener("mousemove", onMouseMove);
  canvas.addEventListener("click", onClick);
  window.addEventListener("keydown", onKey);
  window.addEventListener("resize", resizeCanvasCSS);

  resizeCanvasCSS();

  if (window.location.hash === "#autostart") startNewGame();
  if (window.location.hash === "#demo") runDemo();
  if (window.location.hash === "#battle") runBattleDemo();
  if (window.location.hash === "#gameover") runGameOverDemo();
  if (window.location.hash === "#smoke") runSmokeTest();

  requestAnimationFrame(loop);
}

function resizeCanvasCSS() {
  // Fit the canvas to the viewport while preserving 16:10 aspect ratio EXACTLY.
  // We compute a single uniform scale factor, then derive height from the
  // floored width so the displayed ratio is identical to the internal ratio.
  // Without this, flooring width and height independently produces slightly
  // different x/y scales — pixelated rendering skews text and sprites.
  const vw = Math.max(320, window.innerWidth);
  const vh = Math.max(200, window.innerHeight) - 24;
  const scale = Math.min(vw / CANVAS_W, vh / CANVAS_H);
  const dispW = Math.floor(CANVAS_W * scale);
  const dispH = Math.round(dispW * CANVAS_H / CANVAS_W);
  canvas.style.width = dispW + "px";
  canvas.style.height = dispH + "px";
}

function loop() {
  render();
  requestAnimationFrame(loop);
}

window.addEventListener("DOMContentLoaded", boot);

// ---------------------------------------------------------------------------
// Headless smoke-test hooks
// ---------------------------------------------------------------------------

function runDemo() {
  startNewGame();
  const azureMaster = masterOf(0);
  function summonAdjacent(type) {
    const slot = findSummonSlot(azureMaster);
    if (!slot) return;
    const cost = UNIT_TYPES[type].cost;
    if (azureMaster.mp < cost) return;
    azureMaster.mp -= cost;
    const u = makeUnit(type, 0, slot.q, slot.r);
    u.acted = true;
    STATE.units.push(u);
    pushLog(azureMaster.name + " summons " + u.name + ".");
  }
  summonAdjacent("tidekin");
  summonAdjacent("cinderling");
  azureMaster.acted = true;
  setTimeout(() => endTurn(), 50);
}

function runBattleDemo() {
  startNewGame();
  const azureMaster = masterOf(0);
  const crimsonMaster = masterOf(1);
  // Put both within range and trigger a battle immediately.
  azureMaster.q = 4; azureMaster.r = 5;
  crimsonMaster.q = 5; crimsonMaster.r = 5;
  // Force the battle scene
  setTimeout(() => beginBattle(azureMaster, crimsonMaster), 80);
}

function runGameOverDemo() {
  startNewGame();
  masterOf(1).hp = 0;
  checkWinCondition();
}

// #smoke — plays a full first turn (player summons + ends turn, AI plays its
// whole turn) and writes a DOM marker the headless runner greps for.
// Success: no JS errors, AI turn completed, control back with player 0 on
// turn 2 (or a legitimate gameover). Run via smoke-test.sh.
function runSmokeTest() {
  const errors = [];
  window.addEventListener("error", e => errors.push(e.message || String(e.error)));
  window.addEventListener("unhandledrejection", e => errors.push("rejection: " + e.reason));

  function report(text) {
    let el = document.getElementById("smoke-result");
    if (!el) {
      el = document.createElement("div");
      el.id = "smoke-result";
      document.body.appendChild(el);
    }
    el.textContent = text;
    document.title = text.slice(0, 60);
  }

  runDemo(); // start game, summon two units, end turn → AI plays

  const startedAt = Date.now();
  function poll() {
    if (errors.length) {
      report("SMOKE_FAIL " + errors.join(" | "));
      return;
    }
    const aiDone = STATE.screen === "play" && STATE.currentPlayer === 0 && STATE.turn >= 2;
    const legitimateEnd = STATE.screen === "gameover";
    if (aiDone || legitimateEnd) {
      report("SMOKE_OK turn=" + STATE.turn + " units=" + STATE.units.filter(u => u.hp > 0).length);
      return;
    }
    if (Date.now() - startedAt > 25000) {
      report("SMOKE_TIMEOUT screen=" + STATE.screen + " player=" + STATE.currentPlayer + " turn=" + STATE.turn);
      return;
    }
    setTimeout(poll, 300);
  }
  setTimeout(poll, 500);
}
