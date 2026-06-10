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
//  17. Status effects (v2 1.1)
//  18. Abilities (v2 1.2-1.4)

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

// Map dimensions are per-map since 5.2 — generateMap sets them from the
// selected MAPS[] definition. These are the classic defaults.
let COLS = 14;
let ROWS = 12;

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

// Named map definitions (5.2). Each is the procedural generator's parameter
// set — size, terrain mix, tower count — plus optional handcrafted overrides
// (fixed `seed` for a repeatable layout, explicit `castles` start positions).
// `seed: null` rolls a fresh layout every match.
const MAPS = [
  { key: "frontier", name: "Wraithspire Frontier", desc: "The classic borderland.",
    cols: 14, rows: 12, seed: null,
    mountains: 4, lakes: 3, forests: 22, hills: 14, towers: 5 },
  { key: "tides", name: "Shattered Tides", desc: "Drowned field — flyers rule.",
    cols: 14, rows: 12, seed: null,
    mountains: 1, lakes: 8, forests: 12, hills: 6, towers: 5,
    weatherTable: ["rain", "rain", "clear", "gale"] },
  { key: "crags", name: "Emberfall Crags", desc: "Walls of stone, tight passes.",
    cols: 15, rows: 11, seed: null,
    mountains: 9, lakes: 1, forests: 8, hills: 22, towers: 4,
    castles: [{ q: 0, r: 5 }, { q: 9, r: 5 }],   // handcrafted: east-west standoff
    weatherTable: ["heat", "heat", "clear", "gale"] },
  { key: "verdant", name: "Verdant Expanse", desc: "Wide greens, six spires.",
    cols: 16, rows: 13, seed: null,
    mountains: 2, lakes: 2, forests: 30, hills: 10, towers: 6 },
];

// Campaign scenarios (5.3): an escalating 4-mission arc. Each carries its own
// map definition (fixed seed → handcrafted-feeling, repeatable layouts), an AI
// difficulty, opening-strength modifiers, and interstitial lore. Progress
// (highest unlocked index) is kept in the settings blob; full save/load is 6.1.
const CAMPAIGN = [
  {
    name: "The Border Skirmish", difficulty: "easy",
    map: { key: "c1", name: "Border Skirmish", desc: "", cols: 11, rows: 9, seed: 7041,
           mountains: 2, lakes: 1, forests: 12, hills: 8, towers: 3 },
    aiMpBonus: -6, aiSummons: [],
    intro: [
      "The old truce is ash. CRIMSON riders burn the",
      "border farms, and the Azure throne calls you —",
      "its youngest archon — to answer.",
      "Drive them from the frontier.",
    ],
  },
  {
    name: "The Drowned Marches", difficulty: "normal",
    map: { key: "c2", name: "Drowned Marches", desc: "", cols: 14, rows: 12, seed: 11317,
           mountains: 1, lakes: 8, forests: 12, hills: 6, towers: 5 },
    aiMpBonus: 0, aiSummons: ["tidekin"],
    intro: [
      "You chased them into the marches, where the",
      "tide swallows roads whole. CRIMSON's leviathans",
      "glide where your soldiers drown.",
      "Take wing, or take the long way around.",
    ],
  },
  {
    name: "The Emberfall Passes", difficulty: "normal",
    map: { key: "c3", name: "Emberfall Passes", desc: "", cols: 15, rows: 11, seed: 40923,
           mountains: 9, lakes: 1, forests: 8, hills: 22, towers: 4,
           castles: [{ q: 0, r: 5 }, { q: 9, r: 5 }] },
    aiMpBonus: 6, aiSummons: ["stoneward", "cinderling"],
    intro: [
      "Only the high passes lead to the enemy's seat,",
      "and CRIMSON knows it. Stoneward garrisons hold",
      "every defile, fed by the spires you must take.",
      "The mountains do not forgive haste.",
    ],
  },
  {
    name: "The Wraithspire", difficulty: "hard",
    map: { key: "c4", name: "The Wraithspire", desc: "", cols: 16, rows: 13, seed: 86011,
           mountains: 4, lakes: 3, forests: 24, hills: 12, towers: 6 },
    aiMpBonus: 10, aiSummons: ["geomaul", "skyharrow"],
    intro: [
      "The Wraithspire itself — the first spire, the",
      "one all others echo. The CRIMSON archon waits",
      "beneath it with everything he has left.",
      "Cast him down. Inherit the realm.",
    ],
  },
];

function generateMap(seed, def = MAPS[0]) {
  let rng = mulberry32(seed);
  COLS = def.cols;
  ROWS = def.rows;
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
    let guard = 0;
    for (let i = 0; i < count && guard++ < 1000; i++) {
      const c = pick();
      if (c.terrain !== "plain") { i--; continue; }
      c.terrain = kind;
    }
  };

  for (let i = 0; i < def.mountains; i++) {
    let c = pick();
    const len = 2 + Math.floor(rng() * 3);
    for (let j = 0; j < len; j++) {
      if (!c) break;
      c.terrain = "mountain";
      const nbrs = hexNeighbors(c.q, c.r).filter(n => inBounds(n.q, n.r));
      c = nbrs.length ? cellAt(nbrs[Math.floor(rng() * nbrs.length)]) : null;
    }
  }

  for (let i = 0; i < def.lakes; i++) {
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

  scatter("forest", def.forests);
  scatter("hill", def.hills);

  // Start positions: handcrafted override or the default opposite corners.
  const startA = def.castles ? def.castles[0] : { q: 0, r: 1 };
  const startB = def.castles ? def.castles[1]
    : { q: COLS - 3 - Math.floor((ROWS - 2) / 2), r: ROWS - 2 };
  const castleA = cellAt(startA) || cellAt({ q: 1, r: 1 });
  const castleB = cellAt(startB);
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

  let placed = 0, guard = 0;
  while (placed < def.towers && guard++ < 500) {
    const c = pick();
    if (!c || c.terrain !== "plain") continue;
    if (hexDistance(c, castleA) < 3 || hexDistance(c, castleB) < 3) continue;
    if (MAP.towers.some(t => hexDistance(t, c) < 2)) continue;
    c.terrain = "tower";
    c.owner = null;
    MAP.towers.push(c);
    placed++;
  }
  invalidateTerrainCache(); // 7.1 — function declaration, hoisted, safe here
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
  cinderling:  { name: "Cinderling",  element: "pyro",   maxHp: 12, move: 4, range: 1, power: 5, def: 1, cost: 6,  flying: false, sprite: "imp",      attack: "melee",  evolvesTo: "infernite",   ability: "ignite" },
  pyrowyrm:    { name: "Pyrowyrm",    element: "pyro",   maxHp: 18, move: 3, range: 2, power: 7, def: 2, cost: 12, flying: false, sprite: "wyrm",     attack: "breath", evolvesTo: "emberdrake",  ability: "cinderBreath" },
  tidekin:     { name: "Tidekin",     element: "hydro",  maxHp: 14, move: 4, range: 1, power: 5, def: 2, cost: 7,  flying: false, sprite: "merfolk",  attack: "melee",  evolvesTo: "tidelord",    ability: "healPulse" },
  mistleviath: { name: "Mistlevy",    element: "hydro",  maxHp: 20, move: 3, range: 2, power: 6, def: 3, cost: 14, flying: false, sprite: "serpent",  attack: "spray",  evolvesTo: "leviathan",   ability: "undertow" },
  stoneward:   { name: "Stoneward",   element: "terra",  maxHp: 22, move: 2, range: 1, power: 5, def: 4, cost: 8,  flying: false, sprite: "golem",    attack: "melee",  evolvesTo: "colossus",    ability: "bulwark" },
  geomaul:     { name: "Geomaul",     element: "terra",  maxHp: 26, move: 2, range: 1, power: 9, def: 4, cost: 16, flying: false, sprite: "ogre",     attack: "melee",  evolvesTo: "earthbreaker", ability: "quake" },
  galewisp:    { name: "Galewisp",    element: "zephyr", maxHp: 10, move: 5, range: 2, power: 4, def: 1, cost: 7,  flying: true,  sprite: "wisp",     attack: "spark",  evolvesTo: "stormwisp",   ability: "galeRush" },
  skyharrow:   { name: "Skyharrow",   element: "zephyr", maxHp: 16, move: 4, range: 2, power: 7, def: 2, cost: 13, flying: true,  sprite: "raptor",   attack: "dive",   evolvesTo: "skytyrant",   ability: "diveMark" },

  // Evolved forms (terminal tier; not directly summonable). Reached when a
  // level-4+ unit starts its turn on an owned tower/castle. Real sprites added
  // in milestone 5.1 — each evolved form now has its own unique sprite id.
  infernite:    { name: "Infernite",    element: "pyro",   maxHp: 22, move: 4, range: 1, power: 9,  def: 3, cost: 18, flying: false, sprite: "infernite",    attack: "melee",  evolved: true, ability: "ignite" },
  emberdrake:   { name: "Emberdrake",   element: "pyro",   maxHp: 30, move: 3, range: 2, power: 11, def: 4, cost: 26, flying: false, sprite: "emberdrake",   attack: "breath", evolved: true, ability: "cinderBreath" },
  tidelord:     { name: "Tidelord",     element: "hydro",  maxHp: 24, move: 4, range: 1, power: 9,  def: 4, cost: 18, flying: false, sprite: "tidelord",     attack: "melee",  evolved: true, ability: "healPulse" },
  leviathan:    { name: "Leviathan",    element: "hydro",  maxHp: 32, move: 3, range: 2, power: 10, def: 5, cost: 28, flying: false, sprite: "leviathan",    attack: "spray",  evolved: true, ability: "undertow" },
  colossus:     { name: "Colossus",     element: "terra",  maxHp: 36, move: 2, range: 1, power: 9,  def: 6, cost: 20, flying: false, sprite: "colossus",     attack: "melee",  evolved: true, ability: "bulwark" },
  earthbreaker: { name: "Earthbreaker", element: "terra",  maxHp: 42, move: 2, range: 1, power: 14, def: 6, cost: 30, flying: false, sprite: "earthbreaker", attack: "melee",  evolved: true, ability: "quake" },
  stormwisp:    { name: "Stormwisp",    element: "zephyr", maxHp: 18, move: 5, range: 2, power: 8,  def: 2, cost: 18, flying: true,  sprite: "stormwisp",    attack: "spark",  evolved: true, ability: "galeRush" },
  skytyrant:    { name: "Skytyrant",    element: "zephyr", maxHp: 26, move: 4, range: 2, power: 11, def: 3, cost: 24, flying: true,  sprite: "skytyrant",    attack: "dive",   evolved: true, ability: "diveMark" },

  // New base monsters (milestone 5.1 — arcane element coverage + roster depth)
  hexwisp:   { name: "Hexwisp",   element: "arcane", maxHp: 11, move: 5, range: 2, power: 5,  def: 1, cost: 8,  flying: true,  sprite: "hexwisp",   attack: "bolt",  ability: "blink" },
  runeward:  { name: "Runeward",  element: "arcane", maxHp: 24, move: 2, range: 1, power: 7,  def: 5, cost: 15, flying: false, sprite: "runeward",  attack: "melee", ability: "ward" },
  frostmaw:  { name: "Frostmaw",  element: "hydro",  maxHp: 28, move: 3, range: 1, power: 10, def: 3, cost: 18, flying: false, sprite: "frostmaw",  attack: "melee", ability: "frostBite" },
  duneskink: { name: "Duneskink", element: "terra",  maxHp: 13, move: 5, range: 1, power: 6,  def: 1, cost: 6,  flying: false, sprite: "duneskink", attack: "melee", ability: "skitter" },
};

const SUMMON_LIST = ["cinderling", "tidekin", "stoneward", "galewisp", "duneskink", "pyrowyrm", "hexwisp", "mistleviath", "runeward", "geomaul", "frostmaw", "skyharrow"];

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
    cd: 0, secondMove: false,
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
    cd: 0, secondMove: false,
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
  pushLog(oldName + " evolves into " + unit.name + "!", PAL.gold);
  pushAnim("evolve", unit.q, unit.r, "EVOLVED!", PAL.gold, "240, 198, 116");
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
  cursor: null,    // {q,r} keyboard hex cursor (3.4); null = inactive
  banner: null,
  log: [],
  winner: null,
  cam: { x: 0, y: 0 },
  camTarget: { x: 0, y: 0 },  // cam eases toward this each frame (2.3)
  mouse: null,                // {x,y} canvas coords for edge-pan (2.3)
  pendingAI: false,
  animations: [],
  battle: null,      // active battle scene; see startBattle()
  moveAnim: null,    // active hex-to-hex slide; see startMove()/updateMove()
  transition: null,  // full-screen scene wipe/fade; see renderTransition()
  music: { wanted: true, started: false, trackIndex: 0 },
  settings: { musicVol: 1, sfxVol: 1, battleScene: true }, // 3.3
  settingsOpen: false,  // 3.3 gear overlay
  helpOpen: false,      // 3.3 ? overlay
  difficulty: "normal", // 4.3 AI profile key; chosen on the title screen
  mapIndex: 0,          // 5.2 index into MAPS; chosen on the title screen
  campaign: null,       // 5.3 {index} while a campaign mission is live
  campaignProgress: 0,  // 5.3 highest unlocked mission index
  story: null,          // 5.3 {index} for the interstitial screen
  undo: null,           // 6.2 {unit, q, r} pre-move snapshot; cleared on commit
  logScroll: 0,         // 6.2 entries scrolled back from newest (0 = live tail)
  abilityArm: null,     // 1.3 armed enemy-target ability waiting for click
  blinkArm: null,       // 1.3 armed blink (tile-target) waiting for click
  weather: { key: "clear", turnsLeft: 5 }, // 1.5 current weather
  mapDef: null,         // 1.5 active map definition (campaign-safe rollWeather)
};

// ---- Settings persistence (3.3) ----
// Merged from localStorage key "wraithspire.settings.v1" at boot.
// saveSettings() is called after every change so the overlay stays in sync.
const SETTINGS_KEY = "wraithspire.settings.v1";

function loadSettings() {
  try {
    const raw = localStorage.getItem(SETTINGS_KEY);
    if (!raw) return;
    const saved = JSON.parse(raw);
    if (typeof saved.musicVol   === "number") STATE.settings.musicVol   = saved.musicVol;
    if (typeof saved.sfxVol     === "number") STATE.settings.sfxVol     = saved.sfxVol;
    if (typeof saved.battleScene === "boolean") STATE.settings.battleScene = saved.battleScene;
    // Restore last track so music resumes where the player left it.
    if (typeof saved.trackIndex === "number" &&
        saved.trackIndex >= 0 && saved.trackIndex < TRACKS.length) {
      STATE.music.trackIndex = saved.trackIndex;
    }
    if (DIFFICULTIES.includes(saved.difficulty)) STATE.difficulty = saved.difficulty;
    if (typeof saved.mapIndex === "number" && saved.mapIndex >= 0 && saved.mapIndex < MAPS.length) {
      STATE.mapIndex = saved.mapIndex;
    }
    if (typeof saved.campaignProgress === "number" &&
        saved.campaignProgress >= 0 && saved.campaignProgress < CAMPAIGN.length) {
      STATE.campaignProgress = saved.campaignProgress;
    }
  } catch (_) { /* localStorage can throw on file:// in some browsers */ }
}

function saveSettings() {
  try {
    const blob = {
      musicVol:    STATE.settings.musicVol,
      sfxVol:      STATE.settings.sfxVol,
      battleScene: STATE.settings.battleScene,
      trackIndex:  STATE.music.trackIndex,
      difficulty:  STATE.difficulty,
      mapIndex:    STATE.mapIndex,
      campaignProgress: STATE.campaignProgress,
    };
    localStorage.setItem(SETTINGS_KEY, JSON.stringify(blob));
  } catch (_) { /* ignore write failures */ }
}

// ---- Save / load (6.1) ----
// One autosave slot, written at every end-of-turn and cleared when a match
// ends. Cells are serialized directly (tower owners mutate, so a seed isn't
// enough); MAP.towers/castles are rebuilt as references into the cell map.
const SAVE_KEY = "wraithspire.save.v1";

function saveGame() {
  if (STATE.screen !== "play") return;
  try {
    const blob = {
      v: 1,
      turn: STATE.turn,
      currentPlayer: STATE.currentPlayer,
      cols: COLS, rows: ROWS,
      cells: [...MAP.cells.values()].map(c => ({ q: c.q, r: c.r, terrain: c.terrain, owner: c.owner })),
      units: STATE.units.filter(u => u.hp > 0),
      stats: STATE.stats,
      nextUnitId,
      campaign: STATE.campaign,
      matchDifficulty: STATE.matchDifficulty,
      log: STATE.log.slice(0, 12),
      weather: STATE.weather, // 1.5
    };
    localStorage.setItem(SAVE_KEY, JSON.stringify(blob));
    STATE.hasSave = true;
  } catch (_) { /* storage full / unavailable — autosave is best-effort */ }
}

function deleteSave() {
  try { localStorage.removeItem(SAVE_KEY); } catch (_) {}
  STATE.hasSave = false;
}

function probeSave() {
  try { STATE.hasSave = !!localStorage.getItem(SAVE_KEY); } catch (_) { STATE.hasSave = false; }
}

function loadGame() {
  let blob;
  try { blob = JSON.parse(localStorage.getItem(SAVE_KEY)); } catch (_) { return false; }
  if (!blob || blob.v !== 1 || !Array.isArray(blob.cells) || !Array.isArray(blob.units)) return false;

  COLS = blob.cols; ROWS = blob.rows;
  MAP.cells.clear();
  MAP.towers.length = 0;
  MAP.castles.length = 0;
  for (const c of blob.cells) {
    const cell = { q: c.q, r: c.r, terrain: c.terrain, owner: c.owner };
    MAP.cells.set(hexKey(c.q, c.r), cell);
    if (cell.terrain === "tower") MAP.towers.push(cell);
    if (cell.terrain === "castle") MAP.castles.push(cell);
  }

  nextUnitId = blob.nextUnitId || 1000;
  STATE.units = blob.units;
  // v1-blob units predate abilities — normalize so cd gates (u.cd <= 0)
  // behave; undefined would lock the AI out of its abilities forever.
  for (const u of STATE.units) { if (typeof u.cd !== "number") u.cd = 0; }
  STATE.turn = blob.turn;
  STATE.currentPlayer = blob.currentPlayer;
  STATE.stats = blob.stats || { summoned: [0, 0], lost: [0, 0], battles: 0 };
  STATE.campaign = blob.campaign || null;
  STATE.matchDifficulty = blob.matchDifficulty || STATE.difficulty;
  STATE.log = Array.isArray(blob.log) ? blob.log : [];
  STATE.weather = blob.weather || { key: "clear", turnsLeft: 5 }; // 1.5 (defaults old saves)
  STATE.mapDef = null; // 1.5 campaign def not serialised; rollWeather falls back to skirmish def

  invalidateTerrainCache(); // 7.1 — rebuilt cells need a fresh terrain layer

  // Transient state resets — mirror startNewGame.
  STATE.selected = null; STATE.reachable = null; STATE.attackTargets = null;
  STATE.cursor = null; STATE.menu = null; STATE.battle = null; STATE.moveAnim = null;
  STATE.animations = []; STATE.winner = null; STATE.pendingAI = false;
  STATE.undo = null; STATE.logScroll = 0; // 6.2
  STATE.abilityArm = null; STATE.blinkArm = null; // 1.3
  STATE.screen = "play";
  startTransition("wipe", 30);
  STATE.banner = { text: "RESUMED — TURN " + STATE.turn, ttl: 80, color: PLAYERS[STATE.currentPlayer].color };
  pushLog("The battle resumes.");
  centerCameraOn(masterOf(STATE.currentPlayer), true);
  // If we saved mid-AI-turn somehow, hand control back cleanly.
  if (PLAYERS[STATE.currentPlayer].isAI) {
    STATE.pendingAI = true;
    setTimeout(() => { STATE.pendingAI = false; aiTakeTurn(); }, 800);
  }
  return true;
}

// Starts a match. With no argument it's a free skirmish on the title-screen
// map/difficulty; with a CAMPAIGN scenario it uses the scenario's map, sets
// its difficulty for the match (without persisting over skirmish prefs), and
// applies its AI opening-strength modifiers.
function startNewGame(scenario) {
  nextUnitId = 1;
  const def = scenario ? scenario.map : (MAPS[STATE.mapIndex] || MAPS[0]);
  STATE.mapDef = def; // 1.5 store active def so rollWeather works for campaign maps
  generateMap(def.seed != null ? def.seed : Math.floor(Math.random() * 1e9), def);
  STATE.campaign = scenario ? { index: CAMPAIGN.indexOf(scenario) } : null;
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
  STATE.cursor = null;
  STATE.menu = null;
  STATE.abilityArm = null;
  STATE.blinkArm = null;
  STATE.banner = { text: PLAYERS[0].name + " — TURN " + STATE.turn, ttl: 90, color: PLAYERS[0].color };
  STATE.log = [];
  STATE.logScroll = 0;  // 6.2 reset scrollback on new game
  STATE.winner = null;
  STATE.screen = "play";
  startTransition("wipe", 30);   // title → play uncover
  STATE.pendingAI = false;
  STATE.battle = null;
  STATE.stats = { summoned: [0, 0], lost: [0, 0], battles: 0 };
  for (const u of STATE.units) u.acted = false;
  STATE.matchDifficulty = scenario ? scenario.difficulty : STATE.difficulty;
  if (scenario) {
    const m1 = masterOf(1);
    if (m1) {
      m1.mp = Math.max(4, Math.min(m1.maxMp, m1.mp + (scenario.aiMpBonus || 0)));
      for (const k of scenario.aiSummons || []) {
        const slot = findSummonSlot(m1);
        if (!slot) break;
        STATE.units.push(makeUnit(k, 1, slot.q, slot.r));
      }
    }
    pushLog("Mission " + (STATE.campaign.index + 1) + ": " + scenario.name);
  } else {
    pushLog("Battle begins on the Wraithspire frontier.");
  }
  rollWeather(true); // 1.5 initialise weather silently at match start
  centerCameraOn(masterOf(0), true);
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

// 6.2: entries are stored as {text, color} objects. color may be null (use
// renderer default). Old saves hold plain strings; the renderer handles both
// shapes via `typeof entry === "string" ? {text: entry} : entry`.
function pushLog(line, color) {
  STATE.log.unshift({ text: line, color: color || null });
  if (STATE.log.length > 40) STATE.log.length = 40;
  STATE.logScroll = 0;   // snap view to newest on every new entry
}

function clampCamX(x) { return Math.max(MAP_W - mapPixelWidth(), Math.min(0, x)); }
function clampCamY(y) { return Math.max(MAP_H - mapPixelHeight(), Math.min(0, y)); }

// Glide the camera so `unit` is centred. Sets the lerp target; pass instant to
// also snap immediately (used on a fresh match so the first frame isn't a pan).
function centerCameraOn(unit, instant) {
  if (!unit) return;
  const p = axialToPixel(unit.q, unit.r);
  STATE.camTarget.x = clampCamX(MAP_W / 2 - p.x);
  STATE.camTarget.y = clampCamY(MAP_H / 2 - p.y);
  if (instant) { STATE.cam.x = STATE.camTarget.x; STATE.cam.y = STATE.camTarget.y; }
}

// Per-frame: RTS edge-pan from the parked mouse, then ease cam → camTarget.
function updateCamera() {
  const mo = STATE.mouse;
  if (mo && !STATE.menu && !STATE.settingsOpen && !STATE.helpOpen) {
    const EDGE = 42, SPEED = 13;
    if (mo.x >= 0 && mo.x <= MAP_W && mo.y >= TOPBAR_H && mo.y <= CANVAS_H) {
      if (mo.x < EDGE)               STATE.camTarget.x = clampCamX(STATE.camTarget.x + SPEED);
      else if (mo.x > MAP_W - EDGE)  STATE.camTarget.x = clampCamX(STATE.camTarget.x - SPEED);
      if (mo.y < TOPBAR_H + EDGE)    STATE.camTarget.y = clampCamY(STATE.camTarget.y + SPEED);
      else if (mo.y > CANVAS_H - EDGE) STATE.camTarget.y = clampCamY(STATE.camTarget.y - SPEED);
    }
  }
  STATE.cam.x += (STATE.camTarget.x - STATE.cam.x) * 0.18;
  STATE.cam.y += (STATE.camTarget.y - STATE.cam.y) * 0.18;
  if (Math.abs(STATE.camTarget.x - STATE.cam.x) < 0.3) STATE.cam.x = STATE.camTarget.x;
  if (Math.abs(STATE.camTarget.y - STATE.cam.y) < 0.3) STATE.cam.y = STATE.camTarget.y;
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
      if (newCost > effectiveMove(unit)) continue;
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

// Any unit can flip a spire (4.1) — matches the original game, and gives the
// AI's grunts a reason to spread out.
function canCapture(unit, cell) {
  if (!cell) return false;
  if (cell.terrain !== "tower") return false;
  return cell.owner !== unit.owner;
}

// ---- Animated movement (milestone 2.1) ------------------------------------
// Units slide hex-to-hex along the Dijkstra path before their action menu
// opens. Input and the AI step chain are blocked while STATE.moveAnim is live
// (same gating pattern as the battle scene). Time-based so speed is FPS-stable.
const MOVE_TICK_MS = 16;      // slide ticker cadence (~60Hz), setTimeout-driven
const MOVE_STEP = 0.2;        // progress per tick for one hex step (~85ms/hex)
const MOVE_EASE = t => t * t * (3 - 2 * t); // smoothstep

// Walk `prev` links in a computeReachable() result back from (q,r) to the
// unit's start, returning the full path as [{q,r}, ...] start-first.
function reconstructPath(reach, q, r) {
  const path = [];
  let key = hexKey(q, r);
  let guard = 0;
  while (key && guard++ < 4096) {
    const node = reach.get(key);
    if (!node) break;
    path.push({ q: node.q, r: node.r });
    key = node.prev;
  }
  path.reverse();
  return path;
}

// Begin sliding `unit` to (destQ,destR) along its reachable path, then invoke
// onArrive() once the unit settles. No path (or a zero-length hop) arrives
// immediately so callers never special-case standing still. The slide is
// advanced by a setTimeout ticker (tickMove) — NOT the rAF render loop — so it
// keeps progressing under headless virtual-time, where an empty timer queue
// halts the virtual clock and starves rAF.
function startMove(unit, destQ, destR, reach, onArrive) {
  const path = reach ? reconstructPath(reach, destQ, destR) : null;
  if (!path || path.length < 2) {
    moveUnitTo(unit, destQ, destR);
    if (onArrive) onArrive();
    return;
  }
  STATE.moveAnim = { unit, path, seg: 0, t: 0, onArrive };
  setTimeout(tickMove, MOVE_TICK_MS);
}

// One slide tick: advance progress, follow the camera, commit + fire onArrive
// when the last segment finishes, else schedule the next tick.
function tickMove() {
  const m = STATE.moveAnim;
  if (!m) return;
  m.t += MOVE_STEP;
  while (m.t >= 1) {
    m.t -= 1;
    m.seg++;
    if (m.seg >= m.path.length - 1) {
      const dest = m.path[m.path.length - 1];
      STATE.moveAnim = null;
      moveUnitTo(m.unit, dest.q, dest.r);
      if (m.onArrive) m.onArrive();
      return;
    }
  }
  // Camera follow: aim the lerp target at the slider; updateCamera() eases the
  // actual cam toward it each frame, so long marches stay on-screen.
  const p = moveAnimPixel(m);
  STATE.camTarget.x = clampCamX(MAP_W / 2 - p.x);
  STATE.camTarget.y = clampCamY(MAP_H / 2 - p.y);
  setTimeout(tickMove, MOVE_TICK_MS);
}

// Interpolated map-pixel position of the sliding unit this frame.
function moveAnimPixel(m) {
  const a = axialToPixel(m.path[m.seg].q, m.path[m.seg].r);
  const b = axialToPixel(m.path[m.seg + 1].q, m.path[m.seg + 1].r);
  const e = MOVE_EASE(Math.min(1, m.t));
  return { x: a.x + (b.x - a.x) * e, y: a.y + (b.y - a.y) * e };
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
  // v2 combat flags (1.3)
  const markMul = hasStatus(defender, "mark") ? 1.2 : 1.0;
  const bulwarkDef = hasStatus(defender, "bulwark") ? 2 : 0;
  // v2 weather modifier (1.5)
  const w = weatherNow();
  const wMul = (w.atkMul && w.atkMul[attacker.element] ? w.atkMul[attacker.element] : 1.0)
             * (w.rangedMul && attacker.range >= 2 ? w.rangedMul : 1.0);
  const raw = attacker.power * (attacker.hp / attacker.maxHp * 0.5 + 0.5);
  const mit = defender.def + bulwarkDef + dTDef * 0.5;
  const base = Math.max(1, Math.round(raw * elemMul * affMul * markMul * wMul - mit * 0.6));
  const dmg = Math.max(1, base + Math.floor(Math.random() * 3) - 1);
  return { dmg, base, elemMul, affMul, hasAffinity: !!aff, aTDef, dTDef };
}

// Two-way battle forecast for the sidebar card (3.1). Mirrors beginBattle's
// counter rule (defender in range → 0.8× swing) but reports the pre-jitter
// `base` so the UI shows a stable X–Y range instead of a live roll.
function forecastBattle(attacker, defender) {
  const a = computeDamage(attacker, defender);
  const dist = hexDistance({ q: attacker.q, r: attacker.r }, { q: defender.q, r: defender.r });
  const canCounter = dist >= 1 && dist <= defender.range;
  const cBase = canCounter ? Math.max(1, Math.round(computeDamage(defender, attacker).base * 0.8)) : 0;
  return {
    lo: Math.max(1, a.base - 1), hi: a.base + 1,
    elemMul: a.elemMul, hasAffinity: a.hasAffinity,
    canCounter, cLo: canCounter ? Math.max(1, cBase - 1) : 0, cHi: canCounter ? cBase + 1 : 0,
    sureKill: defender.hp <= Math.max(1, a.base - 1),
  };
}

// Begins an attack: computes both swings up front, then opens the battle
// scene which will apply damage at impact frames and resume play on outro.
function beginBattle(attacker, defender, afterDone, opts) {
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
    floats: [],   // map-layer damage/xp/level floats, emitted on resume (2.2)
    afterDone,
    arenaSeed: Math.floor(Math.random() * 1e6),
    applyStatus: opts && opts.applyStatus ? opts.applyStatus : null,
    statusTurns: opts && opts.statusTurns ? opts.statusTurns : 0,
  };
  if (STATE.stats) STATE.stats.battles++;

  // Settings can turn the cutaway off (3.3): resolve both swings right here
  // on the map screen — same damage/XP/floats path, no scene, no input block.
  if (STATE.settings && !STATE.settings.battleScene) {
    const b = STATE.battle;
    applySwing(b, false); b.applied1 = true;
    if (b.hasCounter && b.defender.hp > 0) { applySwing(b, true); b.applied2 = true; }
    beep(150, 0.08, "square", 0.18);
    endBattleAndResume();
    return;
  }

  STATE.screen = "battle";
  musicDuck(0.35); // dim music during battle
}

function endBattleAndResume() {
  const b = STATE.battle;
  STATE.battle = null;
  STATE.screen = "play";
  musicDuck(1);
  // Emit the combat's map-layer floats now that the cutaway is gone (2.2).
  if (b && b.floats) for (const f of b.floats) pushAnim("float", f.q, f.r, f.text, f.color, null, f.dy || 0);
  checkWinCondition();
  if (b && b.afterDone) b.afterDone();
}

function checkWinCondition() {
  for (const p of PLAYERS) {
    const m = masterOf(p.id);
    if (!m) {
      STATE.winner = 1 - p.id;
      STATE.screen = "gameover";
      startTransition("fade", 45);   // dissolve into the victory screen
      pushLog(PLAYERS[STATE.winner].name + " is victorious!", PLAYERS[STATE.winner].color);
      // Campaign (5.3): a mission win unlocks the next scenario.
      if (STATE.campaign && STATE.winner === 0) {
        STATE.campaignProgress = Math.min(CAMPAIGN.length - 1,
          Math.max(STATE.campaignProgress, STATE.campaign.index + 1));
        saveSettings();
      }
      deleteSave(); // finished matches don't leave a stale CONTINUE (6.1)
      beep(440, 0.2, "triangle", 0.25);
      setTimeout(() => beep(660, 0.3, "triangle", 0.25), 200);
      return;
    }
  }
}

// =========================================================================
// 8. AI opponent
// =========================================================================

// ---- AI v2 (4.1) -----------------------------------------------------------
// Decisions are scored against a per-turn threat map (how much damage the
// enemy could land on each tile next turn) plus exact damage forecasts from
// forecastBattle. Tuning lives in AI_PROFILES (4.3): the difficulty selected
// on the title screen swaps the weight profile without touching the logic.
//   easy   — threat-blind, no retreat, jittered scores, random summons (v1 feel)
//   normal — the 4.1/4.2 brain as tuned
//   hard   — accepts trades, hunts kills and the archon, retreats earlier
const AI_PROFILES = {
  easy: {
    killBonus: 18, masterBonus: 10, focusFire: 3,
    counterRisk: 0.3, counterDeath: 5, terrainDef: 0.5,
    threatSafe: 0, threatHurt: 0, approach: 1.0,
    captureBonus: 18, retreatHpFrac: 0, atkFloor: 0,
    scoreJitter: 6, randomSummons: true,
  },
  normal: {
    killBonus: 30,       // a confirmed kill (worst roll still lethal)
    masterBonus: 18,     // hitting the enemy archon
    focusFire: 10,       // × target's missing-hp fraction — finish wounded units
    counterRisk: 0.8,    // × counter damage we'd eat if the target survives
    counterDeath: 25,    // extra penalty when the counter could kill us
    terrainDef: 2.0,     // per defense point of the tile we end on
    threatSafe: 0.35,    // threat weight on end tile while healthy
    threatHurt: 1.1,     // threat weight while wounded
    approach: 1.2,       // per-hex pull toward the enemy master (move-only)
    captureBonus: 26,    // value of flipping a spire
    retreatHpFrac: 0.35, // below this hp fraction a unit looks for heal tiles
    atkFloor: 0,         // minimum attack score worth taking
    scoreJitter: 0, randomSummons: false,
  },
  hard: {
    killBonus: 40, masterBonus: 26, focusFire: 16,
    counterRisk: 0.45, counterDeath: 12, terrainDef: 2.0,
    threatSafe: 0.3, threatHurt: 0.9, approach: 1.7,
    captureBonus: 26, retreatHpFrac: 0.28, atkFloor: -3,
    scoreJitter: 0, randomSummons: false,
  },
};
const DIFFICULTIES = ["easy", "normal", "hard"];

// The live match's profile: campaign missions set matchDifficulty without
// touching the player's persisted skirmish preference (STATE.difficulty).
function aiW() {
  return AI_PROFILES[STATE.matchDifficulty || STATE.difficulty] || AI_PROFILES.normal;
}

// Sum of potential enemy damage onto every tile: each enemy's reachable
// nodes are expanded by its attack range. One enemy contributes at most once
// per tile; separate enemies stack. Built once per AI turn (the defending
// player's units don't move while the AI acts).
function buildThreatMap(owner) {
  const threat = new Map();
  for (const e of aliveUnits(1 - owner)) {
    const seen = new Set();
    const mark = (q, r) => {
      const k = hexKey(q, r);
      if (seen.has(k)) return;
      seen.add(k);
      threat.set(k, (threat.get(k) || 0) + e.power);
    };
    const reach = computeReachable(e);
    for (const [, node] of reach) {
      for (const n1 of hexNeighbors(node.q, node.r)) {
        mark(n1.q, n1.r);
        if (e.range >= 2) for (const n2 of hexNeighbors(n1.q, n1.r)) mark(n2.q, n2.r);
      }
    }
  }
  return threat;
}

// Flip a tower to `unit`'s owner with the shared log/anim/sfx. Player menu
// and both AI capture paths all route through here.
function captureTower(unit, cell) {
  cell.owner = unit.owner;
  invalidateTerrainCache(); // tower cap + flag tint live in the cached layer (7.1)
  pushLog(unit.name + " captures a spire.", PAL.gold);
  pushAnim("capture", cell.q, cell.r, "CAPTURED", PAL.gold, "120, 220, 240");
  beep(520, 0.12, "triangle", 0.18);
}

// Best reachable tile for a wounded unit: close to an owned heal tile
// (tower/castle), low threat, decent cover.
function aiRetreatNode(u, reach, threatAt) {
  const heals = [];
  for (const cell of MAP.cells.values()) {
    if ((cell.terrain === "tower" || cell.terrain === "castle") && cell.owner === u.owner) heals.push(cell);
  }
  let best = null, bestScore = Infinity;
  for (const [, node] of reach) {
    const dHeal = heals.length ? Math.min(...heals.map(h => hexDistance(node, h))) : 0;
    const tdef = TERRAIN[cellAt(node).terrain].def;
    const s = dHeal * 2 + threatAt(node.q, node.r) * 1.5 - tdef * 1.5;
    if (s < bestScore) { bestScore = s; best = node; }
  }
  return best;
}

function aiTakeTurn() {
  const owner = STATE.currentPlayer;
  const myUnits = aliveUnits(owner).filter(u => !u.acted);
  myUnits.sort((a, b) => (a.isMaster ? 1 : 0) - (b.isMaster ? 1 : 0));
  const enemyMaster = masterOf(1 - owner);
  if (!enemyMaster) { endTurn(); return; }
  const queue = [...myUnits];
  const threat = buildThreatMap(owner);

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
    aiActUnit(u, enemyMaster, step, threat);
  }
  setTimeout(step, 600);
}

function aiActUnit(u, enemyMaster, done, threat) {
  const W = aiW();
  const reach = computeReachable(u);
  const threatAt = (q, r) => threat.get(hexKey(q, r)) || 0;
  const lowHp = u.hp < u.maxHp * W.retreatHpFrac;
  const finish = () => { u.acted = true; setTimeout(done, 260); };

  // ---- Score every (end tile, target) attack pair with exact damage math.
  // u.q/u.r are temporarily set to the candidate tile so computeDamage sees
  // the right attacker terrain/affinity; restored right after the loop.
  const atkAb = (() => {
    const ab = abilityFor(u);
    return ab && ab.target === "enemy" && u.cd <= 0 ? ab : null;
  })();
  let bestAtk = null;
  const oq = u.q, oRr = u.r;
  for (const [, node] of reach) {
    const targets = computeAttackTargets(u, node.q, node.r);
    if (!targets.size) continue;
    u.q = node.q; u.r = node.r;
    const tdef = TERRAIN[cellAt(node).terrain].def;
    for (const tk of targets) {
      const enemy = STATE.units.find(e => e.hp > 0 && hexKey(e.q, e.r) === tk);
      if (!enemy) continue;
      const f = forecastBattle(u, enemy);
      const kills = enemy.hp <= f.lo; // worst roll still lethal → no counter
      let score = (f.lo + f.hi) / 2;
      if (kills) score += W.killBonus;
      if (enemy.isMaster) score += W.masterBonus;
      score += W.focusFire * (1 - enemy.hp / enemy.maxHp); // focus fire
      if (!kills && f.canCounter) {
        score -= f.cHi * W.counterRisk;
        if (u.hp <= f.cHi) score -= W.counterDeath;
      }
      score += tdef * W.terrainDef * 0.5;
      score -= threatAt(node.q, node.r) * (lowHp ? W.threatHurt : W.threatSafe) * 0.5;
      if (W.scoreJitter) score += (Math.random() * 2 - 1) * W.scoreJitter; // easy: sloppy picks
      if (atkAb) score += 6;
      if (!bestAtk || score > bestAtk.score) bestAtk = { score, node, enemy, kills, useAbility: !!atkAb };
    }
  }
  u.q = oq; u.r = oRr;

  const attack = () => startMove(u, bestAtk.node.q, bestAtk.node.r, reach, () => {
    u.acted = true;
    // Don't burn the cooldown statusing a corpse — confirmed kills take the
    // plain attack and keep the ability ready.
    if (bestAtk.useAbility && atkAb && !bestAtk.kills) {
      u.cd = atkAb.cd;
      beginBattle(u, bestAtk.enemy, () => setTimeout(done, 400), { applyStatus: atkAb.status, statusTurns: atkAb.statusTurns });
    } else {
      beginBattle(u, bestAtk.enemy, () => setTimeout(done, 400));
    }
  });

  // ---- 1. Confirmed kills are always worth taking (no counter comes back).
  // The master still refuses if the end tile is hot enough to kill it next turn.
  if (bestAtk && bestAtk.kills && !(u.isMaster && threatAt(bestAtk.node.q, bestAtk.node.r) >= u.hp)) {
    attack();
    return;
  }

  // ---- 2. Wounded units fall back toward owned heal tiles.
  if (lowHp) {
    const node = aiRetreatNode(u, reach, threatAt);
    if (node) { startMove(u, node.q, node.r, reach, finish); return; }
  }

  // ---- Instant abilities (1.4): fire from where we stand when the heuristic
  // beats the best attack on offer.
  const bestInst = aiScoreInstantAbility(u);
  if (bestInst && (!bestAtk || bestInst.score > bestAtk.score)) {
    const ab = abilityFor(u);
    resolveInstantAbility(u, ab);
    u.cd = ab.cd;
    u.secondMove = false; // AI takes no second legs (v1 simplification)
    finish();
    return;
  }

  // ---- 3. Capture: any unit can flip a spire now. Score it against the
  // best attack so a juicy kill still wins over a grab.
  let bestCap = null;
  for (const t of MAP.towers) {
    if (t.owner === u.owner) continue;
    const node = reach.get(hexKey(t.q, t.r));
    if (!node) continue;
    const heat = threatAt(t.q, t.r);
    if (heat >= u.hp) continue; // don't capture into certain death
    const capScore = W.captureBonus - heat * 0.5 - node.cost;
    if (!bestCap || capScore > bestCap.score) bestCap = { score: capScore, node, cell: cellAt(t) };
  }
  if (bestCap && (!bestAtk || bestCap.score > bestAtk.score)) {
    startMove(u, bestCap.node.q, bestCap.node.r, reach, () => {
      if (bestCap.cell && bestCap.cell.terrain === "tower" && bestCap.cell.owner !== u.owner) captureTower(u, bestCap.cell);
      finish();
    });
    return;
  }

  // ---- 4. Plain attacks need to clear the floor; the master is choosier
  // (it never trades into tiles where the standing threat outweighs it).
  if (bestAtk && bestAtk.score > W.atkFloor &&
      !(u.isMaster && (bestAtk.score < 8 || threatAt(bestAtk.node.q, bestAtk.node.r) > u.hp * 0.6))) {
    attack();
    return;
  }

  // ---- 5. Move-only. Non-masters advance on the enemy master, shaped by
  // cover and threat. The master instead drifts toward the nearest unowned
  // spire (its capture branch handles the final hop) and otherwise holds on
  // safe, defensible ground.
  let bestStep = null, bestScore = -Infinity;
  const unownedTowers = MAP.towers.filter(t => t.owner !== u.owner);
  for (const [, node] of reach) {
    const tdef = TERRAIN[cellAt(node).terrain].def;
    let s = tdef * W.terrainDef - threatAt(node.q, node.r) * (u.isMaster ? W.threatHurt : W.threatSafe);
    if (u.isMaster) {
      if (unownedTowers.length) {
        const dTower = Math.min(...unownedTowers.map(t => hexDistance(node, t)));
        s -= dTower * 0.8;
      }
    } else {
      s -= hexDistance(node, enemyMaster) * W.approach;
    }
    if (s > bestScore) { bestScore = s; bestStep = node; }
  }
  if (bestStep) {
    startMove(u, bestStep.q, bestStep.r, reach, finish);
  } else {
    finish();
  }
}

// AI summon economy (4.2): summons are scored by element matchup against the
// enemy army (offense and how hard they hit back), how much of the map
// resonates with the element, raw stat value per MP, and a variety nudge.
// When clearly ahead the AI banks MP for heavy hitters instead of trickling
// chaff; when enemies are in striking range of the master it floods cheap
// bodies to wall it off.
function aiTrySummons(master) {
  const owner = master.owner;
  const enemies = aliveUnits(1 - owner);
  const myArmy = aliveUnits(owner).filter(u => !u.isMaster);
  const randomSummons = aiW().randomSummons; // easy: v1's random picks

  // Fraction of the map that empowers each element (+20% terrain).
  const terrFrac = {};
  for (const el of Object.keys(ELEMENT)) {
    let n = 0, tot = 0;
    for (const c of MAP.cells.values()) { tot++; if (affinityFor(el, c.terrain)) n++; }
    terrFrac[el] = tot ? n / tot : 0;
  }

  const armyValue = (list) => list.reduce((a, u) => a + u.power + u.maxHp * 0.25, 0);
  const ahead = armyValue(myArmy) > armyValue(enemies.filter(e => !e.isMaster)) * 1.25;
  const emergency = enemies.some(e => hexDistance(e, master) <= e.move + e.range);

  const scoreType = (k) => {
    const t = UNIT_TYPES[k];
    let s = 0;
    if (enemies.length) {
      // offense: avg element edge vs their army; defense: how hard they counter-hit
      s += enemies.reduce((a, e) => a + (ELEM_MATRIX[t.element][e.element] - 1), 0) / enemies.length * 20;
      s -= enemies.reduce((a, e) => a + (ELEM_MATRIX[e.element][t.element] - 1), 0) / enemies.length * 10;
    }
    s += terrFrac[t.element] * 12;
    s += (t.maxHp * 0.25 + t.power) / t.cost * 6;   // stat value per MP
    s -= myArmy.filter(m => m.typeKey === k).length * 4; // variety
    return s;
  };

  let attempts = 4;
  while (attempts-- > 0 && master.mp >= 6) {
    let pool = SUMMON_LIST.filter(k => UNIT_TYPES[k].cost <= master.mp);
    if (!pool.length) break;
    if (randomSummons) {
      pool = [pool[Math.floor(Math.random() * pool.length)]];
    } else if (emergency) {
      // Wall off the master: cheap half of the affordable pool, best-scored.
      pool.sort((a, b) => UNIT_TYPES[a].cost - UNIT_TYPES[b].cost);
      pool = pool.slice(0, Math.max(1, Math.ceil(pool.length / 2)));
    } else if (ahead) {
      // Bank MP for big units — unless next turn's regen would overflow the
      // cap, in which case spending now is free.
      const bigs = pool.filter(k => UNIT_TYPES[k].cost >= 12);
      const regen = master.mpRegen + MAP.towers.filter(t => t.owner === owner).length * 2;
      if (!bigs.length && master.mp + regen <= master.maxMp) break;
      if (bigs.length) pool = bigs;
    }
    pool.sort((a, b) => scoreType(b) - scoreType(a));
    const choice = pool[0];
    const slot = findSummonSlot(master);
    if (!slot) break;
    master.mp -= UNIT_TYPES[choice].cost;
    const u = makeUnit(choice, owner, slot.q, slot.r);
    u.acted = true;
    STATE.units.push(u);
    myArmy.push(u); // keep the variety penalty honest across this loop
    if (STATE.stats) STATE.stats.summoned[owner]++;
    pushLog(master.name + " summons " + u.name + ".", PAL.purple);
    pushAnim("summon", slot.q, slot.r, "", PAL.gold, "190, 150, 230");
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
    // ---- Evolved forms (milestone 5.1) ----
    case "infernite": {
      // Ascended imp: broader silhouette, armored chest, crown of horns, second tail
      px(-7, -11, 14, 10, color);                  // head (wider)
      px(-10, -13, 4, 4, color); px(6, -13, 4, 4, color); // large outer horns
      px(-5, -14, 3, 3, dark); px(2, -14, 3, 3, dark);    // inner horns
      px(-3, -8, 2, 2, "#100"); px(1, -8, 2, 2, "#100");  // eyes
      px(-1, -5, 2, 1, "#ff4040");                 // ember grin
      px(-7, -1, 14, 10, dark);                    // body
      px(-5, 1, 10, 5, color);
      px(-4, 9, 2, 5, dark); px(2, 9, 2, 5, dark);        // legs
      px(-12, 1, 4, 6, color); px(8, 1, 4, 6, color);     // wings
      px(-14, -4, 3, 5, dark); px(11, -4, 3, 5, dark);    // wing tips
      // dual tails
      px(7, 8, 2, 2, color); px(9, 10, 2, 2, color); px(11, 11, 2, 1, trim);
      px(5, 10, 2, 2, color); px(7, 12, 2, 2, color);
      break;
    }
    case "emberdrake": {
      // Ascended wyrm: larger body, frill crest, armored back plates, fiercer head
      px(-13, -4, 25, 10, color);                  // body (wider)
      px(-11, -1, 20, 5, dark);                    // belly
      px(10, -7, 7, 11, color);                    // head
      px(14, -5, 2, 2, "#ff9020"); px(15, -4, 1, 1, "#100"); // eye
      px(16, -3, 3, 3, color);                     // snout
      px(-15, 1, 7, 3, color); px(-17, 2, 3, 2, color);     // tail
      px(-7, 7, 3, 6, dark); px(3, 7, 3, 6, dark);          // legs
      // back armor plates
      px(-8, -9, 4, 4, dark); px(-2, -9, 4, 4, dark); px(4, -10, 4, 4, dark);
      // head frill
      px(8, -10, 5, 4, trim); px(10, -12, 3, 2, color);
      break;
    }
    case "tidelord": {
      // Ascended merfolk: taller silhouette, crown crest, dual fins, scales shimmer
      px(-5, -13, 10, 8, color);                   // head (taller)
      px(-2, -10, 1, 1, "#100"); px(1, -10, 1, 1, "#100");
      px(-1, -7, 2, 1, trim);                      // mouth
      px(-1, -16, 2, 3, trim); px(-3, -15, 1, 2, color); px(2, -15, 1, 2, color); // triple crown
      px(-7, -5, 14, 9, dark);                     // torso
      px(-6, -3, 12, 5, color);
      px(-10, -4, 3, 7, color); px(7, -4, 3, 7, color);    // arms
      px(-5, 4, 10, 6, color);                     // tail base
      px(-11, 10, 7, 5, color); px(4, 10, 7, 5, color);    // tail fins (wider)
      px(-9, 13, 4, 2, dark); px(5, 13, 4, 2, dark);
      // scale row
      px(-4, -1, 1, 1, trim); px(-1, -1, 1, 1, trim); px(2, -1, 1, 1, trim);
      break;
    }
    case "leviathan": {
      // Ascended serpent: thicker coils, double crest, armored head, longer body
      px(-14, 1, 7, 6, color); px(-7, -4, 7, 6, color);
      px(-1, 1, 7, 6, color); px(6, -4, 7, 6, color);
      px(12, 1, 6, 6, color); px(13, -7, 5, 7, color);     // head (larger)
      px(15, -6, 1, 1, "#fff"); px(15, -4, 1, 1, "#100");
      px(17, -4, 2, 3, color);                     // snout
      // double crest
      px(12, -10, 4, 4, dark); px(13, -12, 2, 2, trim);
      px(10, -8, 3, 3, dark); px(11, -10, 1, 1, trim);
      // armored belly strip
      px(-13, 3, 27, 2, dark);
      px(-15, 6, 3, 3, dark);                      // tail fin
      break;
    }
    case "colossus": {
      // Ascended golem: massive frame, shoulder spires, glowing gem array
      px(-12, -12, 24, 26, dark);                  // body (larger)
      px(-9, -9, 18, 7, color);                    // chest plate
      px(-5, -16, 10, 6, dark);                    // head
      px(-3, -14, 1, 1, "#ffcd5a"); px(2, -14, 1, 1, "#ffcd5a");
      px(-1, -12, 2, 1, "#fff");
      px(-14, -6, 3, 15, color); px(11, -6, 3, 15, color); // arm pauldrons (taller)
      px(-15, 9, 6, 5, dark); px(9, 9, 6, 5, dark);        // fists
      // shoulder spires
      px(-16, -10, 3, 6, dark); px(-14, -13, 2, 4, trim);
      px(13, -10, 3, 6, dark); px(14, -13, 2, 4, trim);
      // gem array on chest
      px(-7, 1, 14, 3, trim); px(-4, 4, 8, 2, trim); px(-2, 6, 4, 1, "#ffe080");
      break;
    }
    case "earthbreaker": {
      // Ascended ogre: hulking, stone armor plating, war-maul, stone crown
      px(-10, -15, 20, 10, color);                 // head
      px(-3, -12, 2, 2, "#100"); px(1, -12, 2, 2, "#100");
      px(-4, -8, 9, 2, dark);                      // grimace
      px(-2, -7, 1, 1, "#fff"); px(3, -7, 2, 2, dark);     // tusk (larger)
      // stone crown
      px(-8, -19, 3, 5, dark); px(-4, -20, 3, 5, dark); px(1, -20, 3, 5, dark); px(5, -19, 3, 5, dark);
      px(-11, -6, 22, 15, dark);                   // torso (wider)
      px(-9, -4, 18, 9, color);
      px(-14, 1, 5, 9, color); px(9, 1, 5, 9, color);      // arms (thicker)
      // stone armor shoulder plates
      px(-15, -4, 5, 5, dark); px(10, -4, 5, 5, dark);
      // massive war-maul
      px(12, -12, 4, 14, "#888");                  // haft
      px(9, -15, 10, 6, "#bbb");                   // head
      px(10, -17, 3, 3, "#fff"); px(15, -17, 2, 2, dark);  // spikes
      px(-6, 10, 5, 5, dark); px(1, 10, 5, 5, dark);
      break;
    }
    case "stormwisp": {
      // Ascended wisp: larger corona, crackling lightning arcs, dual motes
      px(-5, -5, 10, 10, color);                   // core (larger)
      px(-4, -4, 8, 8, "#d8f0ff");
      px(-3, -3, 6, 6, "#ffffff");
      // static ring
      px(-9, 0, 2, 2, color); px(7, 0, 2, 2, color);
      px(-12, -1, 2, 2, dark); px(10, -1, 2, 2, dark);
      px(0, -9, 2, 2, color); px(0, 7, 2, 2, color);
      // lightning arcs
      px(-7, -6, 1, 2, "#c8e8ff"); px(6, -6, 1, 2, "#c8e8ff");
      px(-7, 4, 1, 2, "#c8e8ff"); px(6, 4, 1, 2, "#c8e8ff");
      px(-5, -9, 2, 1, "rgba(200,230,255,0.7)");
      px(3, -9, 2, 1, "rgba(200,230,255,0.7)");
      break;
    }
    case "skytyrant": {
      // Ascended raptor: broader wings, armored body, talons, twin tail fans
      px(-15, -4, 11, 7, dark); px(4, -4, 11, 7, dark);   // wings (wider)
      px(-14, -2, 9, 4, color); px(5, -2, 9, 4, color);
      // wing armor edge
      px(-16, -3, 2, 5, trim); px(14, -3, 2, 5, trim);
      px(-5, -6, 10, 10, color);                   // body
      px(-2, -11, 5, 5, color);                    // head
      px(2, -9, 1, 1, "#ffcd5a"); px(2, -7, 1, 1, "#100");
      px(3, -10, 3, 1, trim);                      // crest
      px(3, -12, 2, 2, trim);
      px(-4, 4, 5, 5, dark);                       // tail base
      // twin tail fans
      px(-5, 9, 3, 3, dark); px(-3, 11, 2, 2, trim);
      px(2, 9, 3, 3, dark); px(3, 11, 2, 2, trim);
      break;
    }
    // ---- New base monsters (milestone 5.1) ----
    case "hexwisp": {
      // Floating arcane rune-eye wisp — purple/violet, visibly different from galewisp
      px(-3, -3, 6, 6, "#7040c0");                 // core (violet, smaller than stormwisp)
      px(-2, -2, 4, 4, "#c0a0ff");                 // mid glow
      px(-1, -1, 2, 2, "#ffffff");                 // bright eye center
      // rune pupils
      px(-1, -1, 1, 1, "#300060"); px(0, 0, 1, 1, "#300060");
      // radial rune sparks (6-fold)
      px(-6, 0, 2, 1, "#9060d0"); px(4, 0, 2, 1, "#9060d0");
      px(-3, -5, 1, 2, "#9060d0"); px(2, -5, 1, 2, "#9060d0");
      px(-3, 3, 1, 2, "#9060d0"); px(2, 3, 1, 2, "#9060d0");
      // outer haze
      px(-8, -1, 1, 1, dark); px(7, -1, 1, 1, dark);
      px(-1, -8, 1, 1, dark); px(-1, 7, 1, 1, dark);
      break;
    }
    case "runeward": {
      // Squat obsidian guardian with glowing glyphs — wide, low, heavily armored
      px(-10, -8, 20, 20, dark);                   // body block (obsidian)
      px(-8, -6, 16, 5, color);                    // shoulder plate
      px(-5, -14, 10, 6, dark);                    // head
      px(-3, -12, 1, 1, trim); px(2, -12, 1, 1, trim);     // glyph eyes
      px(-1, -10, 2, 1, "#fff");                   // glyph mouth-line
      // glyph runes on chest
      px(-7, 0, 3, 2, trim); px(-2, 0, 2, 2, trim); px(3, 0, 3, 2, trim);
      px(-5, 4, 2, 2, trim); px(1, 4, 2, 2, trim);
      // stubby arms
      px(-13, -4, 3, 14, color); px(10, -4, 3, 14, color);
      px(-14, 8, 5, 4, dark); px(9, 8, 5, 4, dark);        // fists
      break;
    }
    case "frostmaw": {
      // Hulking ice-jawed beast — broad, pale blue/white
      px(-10, -8, 20, 12, color);                  // body
      px(-8, -5, 16, 6, "#d0eeff");                // pale belly
      px(-8, -15, 16, 8, color);                   // head
      px(-3, -12, 2, 2, "#100"); px(1, -12, 2, 2, "#100"); // eyes (beady)
      // ice jaw
      px(-9, -8, 18, 4, "#c0e8ff");                // lower jaw
      px(-7, -7, 3, 3, "#ffffff"); px(-2, -7, 3, 3, "#ffffff"); // teeth
      px(2, -7, 3, 3, "#ffffff"); px(5, -7, 3, 3, "#ffffff");
      // frost plating on shoulders
      px(-13, -4, 3, 8, "#d0eeff"); px(10, -4, 3, 8, "#d0eeff");
      px(-4, 4, 8, 8, dark);                       // hindquarters
      px(-6, 7, 3, 5, dark); px(3, 7, 3, 5, dark);         // hind legs
      break;
    }
    case "duneskink": {
      // Low fast sand lizard — tan/ochre, elongated, alert
      px(-12, -2, 22, 6, color);                   // body (long, low)
      px(-14, 0, 4, 3, color);                     // tail
      px(-16, 1, 3, 2, dark);                      // tail tip
      px(8, -5, 6, 6, color);                      // head
      px(11, -4, 1, 1, "#100"); px(11, -2, 1, 1, "#fff");  // eye
      px(13, -3, 3, 2, dark);                      // snout
      // dorsal stripe
      px(-10, -3, 18, 1, dark);
      // four stubby legs
      px(-7, 4, 2, 4, dark); px(-2, 4, 2, 4, dark);
      px(3, 4, 2, 4, dark); px(6, 4, 2, 4, dark);
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
      // ---- Evolved forms (milestone 5.1) ----
      case "infernite": {
        // Ascended imp: broader frame, crown of horns, armor chest, dual tails
        P(-7, -9, 14, 9, color);                                      // head
        P(-10, -12, 4, 4, color); P(6, -12, 4, 4, color);             // outer horns
        P(-5, -13, 3, 4, dark); P(2, -13, 3, 4, dark);                // inner horns
        P(-3, -5, 2, 2, "#100"); P(1, -5, 2, 2, "#100");              // eyes
        P(-1, -2, 2, 1, "#ff4040");                                   // ember grin
        P(-7, 0, 14, 9, dark);                                        // body
        P(-5, 1, 10, 5, color);
        // armor chest stripe
        P(-5, 3, 10, 2, trim);
        P(-3, 9, 2, 5, dark); P(1, 9, 2, 5, dark);                    // legs
        P(-12, 0, 4, 6, color); P(8, 0, 4, 6, color);                 // wing nubs (larger)
        P(-14, -4, 2, 5, dark); P(12, -4, 2, 5, dark);                // wing tips
        // dual tails
        P(7, 8, 2, 2, color); P(9, 10, 2, 2, color); P(11, 11, 2, 1, trim);
        P(5, 10, 2, 2, color); P(7, 12, 2, 2, color); P(9, 13, 1, 1, trim);
        break;
      }
      case "emberdrake": {
        // Ascended wyrm: thicker body, head frill, back armor, larger tail
        P(-13, -3, 26, 10, color);                                    // body
        P(-11, 0, 22, 5, dark);                                       // belly
        P(10, -7, 8, 12, color);                                      // head (larger)
        P(14, -5, 3, 3, "#ff9020"); P(15, -4, 1, 1, "#100");          // eye
        P(17, -3, 3, 3, color);                                       // snout
        P(-15, 1, 8, 3, color); P(-18, 2, 4, 2, color);               // tail
        P(-7, 7, 3, 6, dark); P(3, 7, 3, 6, dark);                    // legs
        // back armor plates
        P(-9, -9, 4, 5, dark); P(-2, -10, 4, 5, dark); P(5, -11, 4, 5, dark);
        // head frill
        P(9, -11, 5, 4, trim); P(12, -13, 3, 3, color);
        // little wings (larger)
        P(-3, -12, 6, 4, dark); P(-3, -12, 6, 1, color);
        break;
      }
      case "tidelord": {
        // Ascended merfolk: taller frame, triple crown, wide tail fins, scale shimmer
        P(-5, -12, 10, 9, color);                                     // head (taller)
        P(-2, -9, 1, 1, "#100"); P(1, -9, 1, 1, "#100");
        P(-3, -6, 6, 2, trim);                                        // gills
        // triple crown
        P(-1, -15, 2, 4, trim); P(-3, -14, 1, 3, color); P(2, -14, 1, 3, color);
        P(-8, -4, 16, 9, dark);                                       // torso
        P(-6, -2, 12, 5, color);
        P(-10, -3, 3, 7, color); P(7, -3, 3, 7, color);               // arms
        P(-5, 5, 10, 7, color);                                       // tail base
        P(-12, 12, 8, 6, color); P(4, 12, 8, 6, color);               // tail fins (wider)
        P(-10, 15, 5, 2, dark); P(5, 15, 5, 2, dark);
        // scale row on torso
        P(-4, 0, 1, 1, trim); P(-1, 0, 1, 1, trim); P(2, 0, 1, 1, trim);
        // crown spike
        P(-1, -15, 2, 4, trim);
        break;
      }
      case "leviathan": {
        // Ascended serpent: thicker coils, armored head, double crest, imposing
        P(-16, 5, 8, 5, color); P(-10, 1, 8, 5, color);
        P(-4, 5, 8, 5, color); P(2, 1, 8, 5, color);
        P(8, 5, 7, 5, color); P(12, -3, 6, 7, color);                 // head
        P(15, -2, 1, 1, "#fff"); P(15, 1, 1, 1, "#100");
        P(17, 1, 2, 2, color);                                        // snout
        // armored belly band
        P(-15, 6, 28, 3, dark);
        // double crest
        P(13, -7, 5, 3, dark); P(14, -9, 3, 2, trim);
        P(11, -5, 4, 2, dark); P(12, -7, 2, 2, trim);
        // tail fin
        P(-18, 6, 3, 4, dark); P(-18, 9, 4, 2, trim);
        break;
      }
      case "colossus": {
        // Ascended golem: massive frame, shoulder spires, gem array
        P(-10, -11, 20, 22, dark);                                    // body (larger)
        P(-8, -9, 16, 7, color);                                      // chest plate
        P(-4, -16, 8, 5, dark);                                       // head
        P(-2, -14, 1, 1, "#ffcd5a"); P(1, -14, 1, 1, "#ffcd5a");
        P(-1, -12, 2, 1, "#fff");
        P(-13, -6, 3, 16, color); P(10, -6, 3, 16, color);            // arm pauldrons (taller)
        P(-14, 10, 6, 5, dark); P(8, 10, 6, 5, dark);                 // fists
        // shoulder spires
        P(-16, -11, 3, 7, dark); P(-14, -14, 2, 4, trim);
        P(13, -11, 3, 7, dark); P(14, -14, 2, 4, trim);
        // gem array
        P(-7, 1, 14, 3, trim); P(-4, 5, 8, 3, trim); P(-2, 8, 4, 2, "#ffe080");
        P(-5, 11, 4, 5, dark); P(1, 11, 4, 5, dark);                  // feet
        break;
      }
      case "earthbreaker": {
        // Ascended ogre: hulking, stone armor, stone crown, massive war-maul
        P(-9, -15, 18, 10, color);                                    // head
        P(-2, -12, 2, 2, "#100"); P(0, -12, 2, 2, "#100");
        P(-3, -7, 8, 2, dark);                                        // grimace
        P(-2, -6, 1, 1, "#fff"); P(2, -6, 2, 2, dark);                // tusk (larger)
        // stone crown (5 battlements)
        P(-9, -20, 3, 6, dark); P(-5, -21, 3, 6, dark); P(-1, -21, 3, 6, dark); P(3, -21, 3, 6, dark); P(6, -20, 3, 6, dark);
        P(-11, -6, 22, 15, dark);                                     // torso (wider)
        P(-9, -4, 18, 9, color);
        P(-15, 1, 5, 10, color); P(10, 1, 5, 10, color);              // arms (thicker)
        // shoulder armor plates
        P(-16, -5, 5, 6, dark); P(11, -5, 5, 6, dark);
        // massive war-maul
        P(13, -12, 4, 14, "#888");                                    // haft
        P(10, -16, 10, 6, "#ccc");                                    // weapon head
        P(11, -18, 3, 3, "#fff"); P(16, -18, 2, 2, dark);             // spikes
        P(-6, 10, 5, 5, dark); P(1, 10, 5, 5, dark);
        break;
      }
      case "stormwisp": {
        // Ascended wisp: larger glow corona, blue-white, crackling lightning
        for (let r = 9; r >= 1; r--) {
          const alpha = (10 - r) / 10;
          ctx.fillStyle = `rgba(180, 220, 255, ${alpha * 0.35})`;
          ctx.beginPath();
          ctx.arc(0, 0, r * SCALE * 0.9, 0, Math.PI * 2);
          ctx.fill();
        }
        P(-5, -5, 10, 10, color);
        P(-4, -4, 8, 8, "#d8f0ff");
        P(-3, -3, 6, 6, "#ffffff");
        // floating lightning motes (different orbit from galewisp)
        for (let i = 0; i < 6; i++) {
          const ang = t / 22 + i * 1.05;
          const rd = 11 + Math.sin(t / 14 + i) * 2;
          ctx.fillStyle = "#d0f0ff";
          ctx.fillRect(Math.cos(ang) * rd * SCALE - 1, Math.sin(ang) * rd * SCALE - 1, SCALE, SCALE);
        }
        // lightning arcs
        P(-8, 0, 2, 1, trim); P(6, 0, 2, 1, trim);
        P(0, -8, 1, 2, trim); P(0, 6, 1, 2, trim);
        break;
      }
      case "skytyrant": {
        // Ascended raptor: armored wings, spiked crest, talons, twin tail fans
        const flap2 = Math.sin(t / 5) * 2;
        P(-16, -3 - flap2, 12, 5, dark);                              // wings (broader)
        P(4, -3 - flap2, 12, 5, dark);
        P(-15, -1 - flap2, 10, 3, color);
        P(5, -1 - flap2, 10, 3, color);
        // wing armor edge
        P(-17, -2, 2, 6, trim); P(15, -2, 2, 6, trim);
        // body
        P(-5, -5, 10, 10, color);
        P(-2, -10, 5, 6, color);                                      // head
        P(2, -8, 1, 1, "#ffcd5a"); P(2, -6, 1, 1, "#100");
        // spiked head crest
        P(3, -11, 3, 2, trim); P(4, -13, 2, 3, color); P(5, -15, 1, 2, trim);
        P(-4, 5, 7, 5, dark);                                         // tail base
        // twin tail fans
        P(-5, 10, 3, 4, dark); P(-3, 13, 2, 2, trim);
        P(2, 10, 3, 4, dark); P(3, 13, 2, 2, trim);
        break;
      }
      // ---- New base monsters (milestone 5.1) ----
      case "hexwisp": {
        // Floating arcane rune-eye wisp — purple/violet glow, distinct from galewisp
        for (let r = 7; r >= 1; r--) {
          const alpha = (8 - r) / 8;
          ctx.fillStyle = `rgba(160, 80, 240, ${alpha * 0.38})`;
          ctx.beginPath();
          ctx.arc(0, 0, r * SCALE * 0.9, 0, Math.PI * 2);
          ctx.fill();
        }
        P(-4, -4, 8, 8, "#7040c0");                                   // core
        P(-3, -3, 6, 6, "#c0a0ff");
        P(-2, -2, 4, 4, "#ffffff");                                   // bright eye
        // rune pupils
        P(-1, -1, 1, 1, "#300060"); P(0, 0, 1, 1, "#300060");
        // orbital rune motes (6-fold, different from galewisp's 5-fold orbit)
        for (let i = 0; i < 6; i++) {
          const ang = t / 25 + i * (Math.PI / 3);
          const rd = 8 + Math.sin(t / 16 + i) * 1.5;
          ctx.fillStyle = "#9060d0";
          ctx.fillRect(Math.cos(ang) * rd * SCALE - 1, Math.sin(ang) * rd * SCALE - 1, SCALE, SCALE);
        }
        break;
      }
      case "runeward": {
        // Squat obsidian guardian — wide low silhouette, glowing glyphs on chest
        P(-10, -9, 20, 21, dark);                                     // body block
        P(-8, -7, 16, 6, color);                                      // shoulder plate
        P(-5, -16, 10, 7, dark);                                      // head
        P(-3, -13, 1, 1, trim); P(2, -13, 1, 1, trim);                // glyph eyes
        P(-1, -11, 2, 1, "#fff");                                     // glyph mouth
        // glyph inscriptions on chest (arcane rune pattern)
        P(-7, 1, 3, 3, trim); P(-2, 1, 2, 3, trim); P(3, 1, 3, 3, trim);
        P(-6, 6, 2, 2, trim); P(-1, 5, 4, 2, "#ffe080"); P(4, 6, 2, 2, trim);
        P(-4, 9, 8, 2, trim);
        // arms
        P(-14, -5, 3, 16, color); P(11, -5, 3, 16, color);
        P(-15, 10, 6, 5, dark); P(9, 10, 6, 5, dark);                 // fists
        P(-5, 12, 4, 5, dark); P(1, 12, 4, 5, dark);                  // feet
        break;
      }
      case "frostmaw": {
        // Hulking ice-jawed beast — broad, pale blue/white, massive jaw
        P(-11, -9, 22, 14, color);                                    // body
        P(-9, -5, 18, 7, "#d0eeff");                                  // pale belly
        P(-9, -17, 18, 9, color);                                     // head
        P(-3, -13, 2, 2, "#100"); P(1, -13, 2, 2, "#100");            // eyes
        // massive ice jaw
        P(-10, -9, 20, 5, "#c0e8ff");                                 // lower jaw
        P(-8, -8, 3, 3, "#ffffff"); P(-3, -8, 3, 3, "#ffffff");        // teeth
        P(1, -8, 3, 3, "#ffffff"); P(5, -8, 3, 3, "#ffffff");
        // frost plating on shoulders
        P(-14, -5, 4, 9, "#d0eeff"); P(10, -5, 4, 9, "#d0eeff");
        P(-13, -7, 2, 2, "#ffffff"); P(11, -7, 2, 2, "#ffffff");       // ice shoulder spikes
        P(-5, 5, 10, 8, dark);                                        // hindquarters
        P(-7, 9, 4, 6, dark); P(3, 9, 4, 6, dark);                    // hind legs
        P(-5, 15, 4, 3, dark); P(1, 15, 4, 3, dark);                  // paws
        break;
      }
      case "duneskink": {
        // Low fast sand lizard — elongated body, tan/ochre, quick alert posture
        P(-13, -2, 25, 7, color);                                     // body (long)
        P(-11, 0, 21, 3, "#d0a050");                                  // pale underbelly
        P(-15, 1, 5, 3, color);                                       // tail
        P(-17, 2, 3, 2, dark); P(-18, 3, 2, 1, dark);                 // tail tip
        P(10, -7, 7, 7, color);                                       // head
        P(13, -5, 1, 1, "#100"); P(13, -3, 1, 1, "#fff");             // eye
        P(16, -4, 3, 2, dark);                                        // snout
        P(17, -3, 2, 1, trim);                                        // tongue flick
        // dorsal stripe
        P(-11, -3, 20, 1, dark);
        // four legs, splayed wide
        P(-8, 5, 2, 5, dark); P(-3, 5, 2, 5, dark);
        P(3, 5, 2, 5, dark); P(7, 5, 2, 5, dark);
        // toe details
        P(-9, 9, 2, 1, dark); P(-7, 9, 2, 1, dark);
        P(2, 9, 2, 1, dark); P(8, 9, 2, 1, dark);
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
  pushLog(unit.name + " reached Level " + unit.level + "!", PAL.gold);
  if (STATE.battle) {
    STATE.battle.flash = Math.max(STATE.battle.flash, 0.85);
    STATE.battle.levelUp = { side, ttl: 64 };
  }
  beep(523, 0.08, "triangle", 0.2);
  setTimeout(() => beep(784, 0.13, "triangle", 0.2), 90);
}

// Applies one battle swing — damage, log, loss stats, XP, map floats.
// Shared by the cutaway's impact frames and the instant resolver used when
// battle scenes are disabled in settings (3.3). The direct dmgB anim only
// fires under the cutaway (it pre-dates floats and ages double there); the
// instant path relies on the floats emitted by endBattleAndResume.
function applySwing(b, counter) {
  const src = counter ? b.defender : b.attacker;
  const dst = counter ? b.attacker : b.defender;
  const dmg = counter ? b.cDmg : b.aDmg;
  if (hasStatus(dst, "ward")) {
    delete dst.status.ward; // consumed by this hit
    if (STATE.screen === "battle") pushAnim("dmgB", dst.q, dst.r, "WARDED", PAL.purple);
    b.floats.push({ q: dst.q, r: dst.r, text: "WARDED", color: PAL.purple, dy: 0 });
    pushLog(dst.name + "'s ward absorbs the blow.", PAL.purple);
    return; // negated: no damage, no XP from this swing
  }
  dst.hp -= dmg;
  if (STATE.screen === "battle") pushAnim("dmgB", dst.q, dst.r, "-" + dmg, PAL.red);
  pushLog(counter
    ? src.name + " counters for " + dmg + "."
    : src.name + " strikes " + dst.name + " for " + dmg + ".", PAL.red);
  if (dst.hp <= 0) { pushLog(dst.name + " is destroyed.", "#ff8888"); if (STATE.stats) STATE.stats.lost[dst.owner]++; }
  const killed = dst.hp <= 0;
  const xpAmt = dmg + (killed ? KILL_XP_BONUS : 0);
  if (gainXp(src, xpAmt) > 0) {
    onBattleLevelUp(src, counter ? "c" : "a");
    b.floats.push({ q: src.q, r: src.r, text: "LEVEL UP!", color: PAL.gold, dy: -22 });
  }
  b.floats.push({ q: dst.q, r: dst.r, text: "-" + dmg, color: PAL.red, dy: 0 });
  if (xpAmt > 0) b.floats.push({ q: src.q, r: src.r, text: "+" + xpAmt + " xp", color: PAL.gold, dy: -10 });
  if (!counter && b.applyStatus && dst.hp > 0) addStatus(dst, b.applyStatus, b.statusTurns);
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
      if (!b.applied1) { applySwing(b, false); b.applied1 = true; }
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
      if (!b.applied2) { applySwing(b, true); b.applied2 = true; }
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

// kind: free label. ring: "r, g, b" to draw an expanding burst behind the
// text (capture/summon/evolve/level flashes). dy: initial vertical offset so
// stacked floats over one tile don't overlap.
function pushAnim(kind, q, r, text, color, ring, dy) {
  const p = axialToPixel(q, r);
  STATE.animations.push({ kind, q, r, x: p.x, y: p.y + (dy || 0), text, color, ring: ring || null, ttl: 50, vy: -0.4 });
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

  if (STATE.screen === "title") {
    renderTitle();
  } else if (STATE.screen === "campaign") {
    renderCampaignScreen();
  } else if (STATE.screen === "story") {
    renderStoryScreen();
  } else if (STATE.screen === "gameover") {
    renderGameOver();
  } else if (STATE.screen === "battle") {
    updateBattle();
    renderBattle();
  } else {
    updateCamera();
    renderMap();
    renderOverlays();
    renderUnits();
    renderAnimationsMap();
    renderTopBar();
    renderSidebar();
    renderMenu();
    renderBanner();
    renderTerrainTooltip();
    // Settings/help overlays drawn last (before renderTransition) so they
    // sit above all map content but below the scene wipe (3.3).
    if (STATE.settingsOpen) renderSettingsOverlay();
    if (STATE.helpOpen)     renderHelpOverlay();
  }
  renderTransition();
}

// Full-screen scene transition drawn over everything (2.4). 'wipe' uncovers
// left→right; 'fade' dissolves from black. ttl counts down to 0.
function startTransition(kind, dur) { STATE.transition = { kind, dur, ttl: dur }; }

function renderTransition() {
  const tr = STATE.transition;
  if (!tr) return;
  tr.ttl--;
  if (tr.ttl <= 0) { STATE.transition = null; return; }
  const a = tr.ttl / tr.dur; // 1 → 0
  ctx.save();
  if (tr.kind === "wipe") {
    const w = Math.ceil(CANVAS_W * easeInCubic(a));
    ctx.fillStyle = "#04030a";
    ctx.fillRect(CANVAS_W - w, 0, w, CANVAS_H);
    // bright leading edge
    ctx.fillStyle = `rgba(240, 198, 116, ${a})`;
    ctx.fillRect(CANVAS_W - w, 0, 3, CANVAS_H);
  } else {
    ctx.fillStyle = `rgba(4, 3, 10, ${a})`;
    ctx.fillRect(0, 0, CANVAS_W, CANVAS_H);
  }
  ctx.restore();
}

// 7.1 — static terrain layer cache. drawHex/drawTerrainDetail have no frame
// or random dependence, so the whole layer is drawn once into an offscreen
// canvas and blitted per frame. invalidateTerrainCache() must be called by
// anything that changes terrain or a cell owner: generateMap, loadGame, and
// captureTower (every owner-flip path routes through it).
const terrainCache = { canvas: null, dirty: true };

function invalidateTerrainCache() { terrainCache.dirty = true; }

function renderMap() {
  const w = Math.ceil(mapPixelWidth()) + 8;
  const h = Math.ceil(mapPixelHeight()) + 8;
  if (!terrainCache.canvas || terrainCache.canvas.width !== w || terrainCache.canvas.height !== h) {
    terrainCache.canvas = document.createElement("canvas");
    terrainCache.canvas.width = w;
    terrainCache.canvas.height = h;
    terrainCache.dirty = true;
  }
  if (terrainCache.dirty) {
    const tctx = terrainCache.canvas.getContext("2d");
    tctx.imageSmoothingEnabled = false;
    tctx.clearRect(0, 0, w, h);
    // drawHex and friends draw through the global ctx — point it at the
    // offscreen layer for the rebuild, then restore. Synchronous, so safe.
    const main = ctx;
    ctx = tctx;
    for (const cell of MAP.cells.values()) {
      const p = axialToPixel(cell.q, cell.r);
      drawHex(cell, p.x, p.y);
    }
    ctx = main;
    terrainCache.dirty = false;
  }
  ctx.save();
  ctx.beginPath();
  ctx.rect(0, TOPBAR_H, MAP_W, MAP_H);
  ctx.clip();
  ctx.translate(STATE.cam.x, STATE.cam.y + TOPBAR_H);
  ctx.drawImage(terrainCache.canvas, 0, 0);
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
  if (STATE.blinkArm) {
    for (const k of STATE.blinkArm.tiles) {
      const [bq, br] = k.split(",").map(Number);
      const p = axialToPixel(bq, br);
      ctx.fillStyle = "rgba(176,120,200,0.28)";
      hexPath(p.x, p.y); ctx.fill();
      ctx.strokeStyle = "rgba(176,120,200,0.70)";
      ctx.lineWidth = 1.5;
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
  // Keyboard cursor (3.4): gold hex outline with a gentle pulse. Drawn on top
  // of hover/selected highlights so it's always visible.
  if (STATE.cursor && inBounds(STATE.cursor.q, STATE.cursor.r)) {
    const p = axialToPixel(STATE.cursor.q, STATE.cursor.r);
    const alpha = 0.55 + 0.35 * Math.sin(frame / 9);
    ctx.strokeStyle = `rgba(240, 198, 116, ${alpha})`;
    ctx.lineWidth = 2;
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

  const slide = STATE.moveAnim;
  for (const u of list) {
    const p = (slide && slide.unit === u) ? moveAnimPixel(slide) : axialToPixel(u.q, u.r);
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

    // status dots: up to 3 colored 3×3 px squares centered under the unit
    if (u.status) {
      const keys = Object.keys(u.status).filter(k => u.status[k] > 0);
      const show = keys.slice(0, 3);
      const dotSpan = show.length * 5 - 2; // total width (3px dot + 2px gap each, no trailing gap)
      for (let di = 0; di < show.length; di++) {
        ctx.fillStyle = STATUS_META[show[di]] ? STATUS_META[show[di]].color : "#ffffff";
        ctx.fillRect(p.x - Math.floor(dotSpan / 2) + di * 5, p.y + 33, 3, 3);
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
    if (a.ring) {
      // expanding ring burst behind the rising text
      const prog = (50 - a.ttl) / 50;
      const rad = 8 + prog * 34;
      ctx.strokeStyle = `rgba(${a.ring}, ${1 - prog})`;
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

// Single source for the two top-bar icon buttons (gear + ?) so renderTopBar
// and onClick both use the exact same rects and can never drift.
function topBarButtonRects() {
  const bSize = 24, gap = 6, right = CANVAS_W - 10;
  const gearX = right - bSize;
  const helpX = gearX - gap - bSize;
  const by = Math.floor((TOPBAR_H - bSize) / 2);
  return {
    gear: { x: gearX, y: by, w: bSize, h: bSize },
    help: { x: helpX, y: by, w: bSize, h: bSize },
  };
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

  // Keyboard hint text — shifted left to make room for the two icon buttons.
  const btns = topBarButtonRects();
  const textRight = btns.help.x - 8;
  ctx.fillStyle = PAL.inkDim;
  ctx.font = "11px 'Courier New', monospace";
  ctx.textAlign = "right";
  const trackLabel = STATE.music.wanted
    ? "♪ " + (TRACKS[STATE.music.trackIndex] || TRACKS[0]).name
    : "music OFF";
  ctx.fillText(weatherNow().name + "  |  E end turn  |  M mute  |  N next  |  " + trackLabel, textRight, 30);
  ctx.textAlign = "left";

  // Gear button (⚙) and help button (?)
  const drawIconBtn = (r, label, active) => {
    ctx.fillStyle = active ? PAL.gold : PAL.panelLight;
    ctx.fillRect(r.x, r.y, r.w, r.h);
    ctx.strokeStyle = active ? PAL.gold : PAL.inkFaint;
    ctx.lineWidth = 1;
    ctx.strokeRect(r.x + 0.5, r.y + 0.5, r.w - 1, r.h - 1);
    ctx.font = "bold 14px 'Courier New', monospace";
    ctx.textAlign = "center";
    ctx.fillStyle = active ? PAL.bg : PAL.ink;
    ctx.fillText(label, r.x + r.w / 2, r.y + r.h / 2 + 5);
    ctx.textAlign = "left";
  };
  drawIconBtn(btns.gear, "⚙", STATE.settingsOpen);
  drawIconBtn(btns.help, "?", STATE.helpOpen);
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
  let cardUnit = null;
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
    cardUnit = unitAt(STATE.hover.q, STATE.hover.r);
  }
  // Card falls back to the selected unit so clicking a unit pins its info (3.1).
  if (!cardUnit && STATE.selected && STATE.selected.hp > 0) cardUnit = STATE.selected;
  if (cardUnit) y = drawUnitCard(cardUnit, y + 6);

  ctx.fillStyle = PAL.inkFaint;
  ctx.fillRect(SIDEBAR_X + 12, CANVAS_H - 170, SIDEBAR_W - 24, 1);
  ctx.fillStyle = PAL.gold;
  ctx.font = "bold 10px 'Courier New', monospace";
  ctx.fillText("BATTLE LOG", SIDEBAR_X + 14, CANVAS_H - 154);
  // 6.2 — scrollback hint: "▼ newer" when scrolled back, "▲" when more above.
  const logMax = Math.max(0, STATE.log.length - 10);
  if (STATE.logScroll > 0) {
    ctx.textAlign = "right";
    ctx.fillStyle = PAL.gold;
    ctx.fillText("▼ newer (wheel)", SIDEBAR_X + SIDEBAR_W - 14, CANVAS_H - 154);
    ctx.textAlign = "left";
  }
  ctx.font = "10px 'Courier New', monospace";
  for (let i = 0; i < 10; i++) {
    const entry = STATE.log[STATE.logScroll + i];
    if (!entry) break;
    // 6.2 — tolerate both old string entries (from saves) and new {text,color} objects.
    const { text, color } = typeof entry === "string" ? { text: entry, color: null } : entry;
    if (i === 0 && STATE.logScroll === 0) {
      ctx.fillStyle = color || PAL.ink; // newest line: entry color or bright default
    } else {
      ctx.fillStyle = color || PAL.inkDim; // older lines: entry color or dim default
    }
    wrapText(text, SIDEBAR_X + 14, CANVAS_H - 138 + i * 13, SIDEBAR_W - 26, 12);
  }
  if (STATE.logScroll < logMax) {
    ctx.fillStyle = PAL.inkDim;
    ctx.font = "10px 'Courier New', monospace";
    ctx.fillText("▲ older", SIDEBAR_X + 14, CANVAS_H - 5);
  }
  ctx.textAlign = "left";
}

// 3.1 — full unit info card: portrait, element, HP/MP/XP bars, stats, the
// bonus from the tile the unit stands on, and (when hovering an enemy with a
// friendly unit selected) a damage forecast for the would-be exchange.
function drawUnitCard(u, y) {
  const x = SIDEBAR_X + 10, w = SIDEBAR_W - 20;
  const sel = STATE.selected;
  const showForecast = sel && sel !== u && sel.hp > 0 && sel.owner !== u.owner;
  const statusKeys = u.status ? Object.keys(u.status).filter(k => u.status[k] > 0) : [];
  const showStatus = statusKeys.length > 0;
  const showAbility = !!abilityFor(u);
  const h = 112 + (showAbility ? 12 : 0) + (showStatus ? 12 : 0) + (showForecast ? 44 : 0);
  // never collide with the battle log strip at the sidebar bottom
  if (y + h > CANVAS_H - 178) y = CANVAS_H - 178 - h;

  const pl = PLAYERS[u.owner];
  const el = ELEMENT[u.element];
  ctx.fillStyle = PAL.panelLight;
  ctx.fillRect(x, y, w, h);
  ctx.lineWidth = 1;
  ctx.strokeStyle = pl.dark;
  ctx.strokeRect(x + 0.5, y + 0.5, w - 1, h - 1);

  // portrait: the map sprite blown up 1.5× in a clipped, element-rimmed box
  const pbx = x + 8, pby = y + 8;
  ctx.fillStyle = "#0b0916";
  ctx.fillRect(pbx, pby, 64, 64);
  ctx.save();
  ctx.beginPath(); ctx.rect(pbx, pby, 64, 64); ctx.clip();
  ctx.translate(pbx + 32, pby + 36);
  ctx.scale(1.5, 1.5);
  drawMapSprite(ctx, u, 0, 3, frame);
  ctx.restore();
  ctx.strokeStyle = el.color;
  ctx.strokeRect(pbx + 0.5, pby + 0.5, 63, 63);

  const tx = x + 82, barW = x + w - 8 - tx;
  ctx.textAlign = "left";
  ctx.font = "bold 12px 'Courier New', monospace";
  ctx.fillStyle = el.color;
  ctx.fillText(u.name.toUpperCase(), tx, y + 18);
  ctx.font = "10px 'Courier New', monospace";
  ctx.fillStyle = pl.color;
  ctx.fillText(pl.name, tx, y + 31);
  ctx.fillStyle = PAL.gold;
  ctx.fillText("Lv " + (u.level || 1) + "  [" + el.short + "]" + (u.evolved ? "  EVOLVED" : ""), tx + 64, y + 31);
  ctx.fillStyle = u.acted ? PAL.inkDim : PAL.green;
  ctx.textAlign = "right";
  ctx.fillText(u.acted ? "spent" : "ready", x + w - 8, y + 18);
  ctx.textAlign = "left";

  drawStatBar(tx, y + 38, barW, 9, u.hp, u.maxHp, "#5fd06a", "HP");
  let by = y + 50;
  if (u.isMaster) { drawStatBar(tx, by, barW, 9, u.mp, u.maxMp, "#7aa8e0", "MP"); by += 12; }
  const lvl = u.level || 1;
  if (lvl >= MAX_LEVEL) drawStatBar(tx, by, barW, 8, 1, 1, "#b89a50", "XP MAX");
  else drawStatBar(tx, by, barW, 8, u.xp || 0, xpToNext(lvl), "#b89a50", "XP");

  ctx.font = "11px 'Courier New', monospace";
  ctx.fillStyle = PAL.ink;
  ctx.fillText("ATK " + u.power + "   DEF " + u.def + "   RNG " + u.range + "   MOV " + u.move, x + 8, y + 86);

  // bonus from the tile the unit is standing on (not the hovered tile)
  const cell = cellAt({ q: u.q, r: u.r });
  if (cell) {
    const t = TERRAIN[cell.terrain];
    ctx.fillStyle = PAL.inkDim;
    const onLabel = "on " + t.name.toUpperCase();
    ctx.fillText(onLabel, x + 8, y + 102);
    drawDefStars(x + 8 + ctx.measureText(onLabel).width + 14, y + 98, t.def);
    if (affinityFor(u.element, cell.terrain)) {
      ctx.fillStyle = PAL.gold;
      ctx.textAlign = "right";
      ctx.fillText("empowered +20%", x + w - 8, y + 102);
      ctx.textAlign = "left";
    }
  }

  // ability line: 9px, gold when ready, dimmed on cooldown (card height +12 when present)
  if (showAbility) {
    const ab = abilityFor(u);
    ctx.font = "9px 'Courier New', monospace";
    ctx.fillStyle = u.cd > 0 ? PAL.inkDim : PAL.gold;
    ctx.textAlign = "left";
    ctx.fillText(
      "◆ " + ab.name + (u.cd > 0 ? " — ready in " + u.cd : " — ready"),
      x + 8, y + 114
    );
  }

  // status labels: one 9px line listing active effect names (option a: card height +12)
  if (showStatus) {
    ctx.font = "9px 'Courier New', monospace";
    ctx.fillStyle = PAL.inkDim;
    ctx.textAlign = "left";
    ctx.fillText(statusKeys.map(k => STATUS_META[k] ? STATUS_META[k].label : k).join(" · "), x + 8, y + 114 + (showAbility ? 12 : 0));
  }

  if (showForecast) {
    const f = forecastBattle(sel, u);
    const fy = y + 112 + (showAbility ? 12 : 0) + (showStatus ? 12 : 0);
    ctx.fillStyle = "#0e0c1a";
    ctx.fillRect(x + 4, fy, w - 8, 36);
    ctx.font = "bold 10px 'Courier New', monospace";
    ctx.fillStyle = PAL.gold;
    ctx.fillText("FORECAST — " + sel.name.toUpperCase() + " ATTACKS", x + 10, fy + 12);
    ctx.font = "11px 'Courier New', monospace";
    ctx.fillStyle = PAL.green;
    let line = "deal " + f.lo + "-" + f.hi;
    if (f.elemMul !== 1) line += "  elem x" + f.elemMul.toFixed(1);
    if (f.hasAffinity) line += "  +aff";
    if (f.sureKill) line += "  KO!";
    ctx.fillText(line, x + 10, fy + 27);
    ctx.textAlign = "right";
    if (f.canCounter) {
      ctx.fillStyle = PAL.red;
      ctx.fillText("counter " + f.cLo + "-" + f.cHi, x + w - 10, fy + 27);
    } else {
      ctx.fillStyle = PAL.inkDim;
      ctx.fillText("no counter", x + w - 10, fy + 27);
    }
    ctx.textAlign = "left";
  }
  return y + h + 6;
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

  // Summon menu side-panel: portrait + stats for the currently highlighted unit.
  if (m.kind === "summonMenu") {
    const hov = m.items[m.index];
    if (hov && hov.kind === "summonChoice" && hov.choice) {
      renderSummonPanel(hov.choice, m.unit, r);
    }
  }
}

// Part A — floating terrain info tooltip near the cursor while hovering the map.
// Shown when: screen=play, hover set, mouse in map area, no menu, no moveAnim.
function renderTerrainTooltip() {
  if (STATE.menu) return;
  if (STATE.moveAnim) return;
  if (STATE.settingsOpen || STATE.helpOpen) return;
  if (!STATE.hover || !inBounds(STATE.hover.q, STATE.hover.r)) return;
  if (!STATE.mouse) return;
  const mo = STATE.mouse;
  if (mo.x > MAP_W || mo.y < TOPBAR_H) return;

  const cell = cellAt(STATE.hover);
  if (!cell) return;
  const t = TERRAIN[cell.terrain];

  // Build two lines of text.
  const line1 = t.name.toUpperCase();
  const costStr = t.moveCost === 99 ? "impassable" : ("move " + t.moveCost);
  const line2 = costStr + "   DEF " + t.def;

  const tw = 130, th = 40, pad = 5;
  let tx = mo.x + 14;
  let ty = mo.y - th - 6;
  // Clamp: never leave the map area (x < MAP_W, y > TOPBAR_H).
  if (tx + tw > MAP_W - 2) tx = MAP_W - tw - 4;
  if (tx < 2) tx = 2;
  if (ty < TOPBAR_H + 2) ty = mo.y + 14;
  if (ty + th > CANVAS_H - 2) ty = CANVAS_H - th - 4;

  ctx.save();
  ctx.fillStyle = PAL.panel;
  ctx.fillRect(tx, ty, tw, th);
  ctx.strokeStyle = PAL.inkFaint;
  ctx.lineWidth = 1;
  ctx.strokeRect(tx + 0.5, ty + 0.5, tw - 1, th - 1);
  ctx.font = "10px 'Courier New', monospace";
  ctx.textAlign = "left";
  ctx.fillStyle = PAL.ink;
  ctx.fillText(line1, tx + pad, ty + pad + 10);
  ctx.fillStyle = PAL.inkDim;
  ctx.fillText(line2, tx + pad, ty + pad + 24);
  ctx.restore();
}

// Part B — summon preview side-panel next to the summon menu.
// Shows portrait, stats, element, cost, and element-vs-enemy hint.
function renderSummonPanel(typeKey, master, menuR) {
  const t = UNIT_TYPES[typeKey];
  if (!t) return;
  const el = ELEMENT[t.element];

  // Panel geometry: appear to the LEFT of the menu (preferred) or right.
  const pw = 164, ph = 122;
  let px = menuR.x - pw - 6;
  if (px < 2) px = menuR.x + menuR.w + 6;
  let py = menuR.y;
  // Clamp vertically inside the canvas.
  if (py + ph > CANVAS_H - 4) py = CANVAS_H - ph - 4;
  if (py < TOPBAR_H + 2) py = TOPBAR_H + 2;

  ctx.save();
  ctx.fillStyle = "rgba(8, 6, 14, 0.95)";
  ctx.fillRect(px, py, pw, ph);
  ctx.strokeStyle = PAL.gold;
  ctx.lineWidth = 1;
  ctx.strokeRect(px + 0.5, py + 0.5, pw - 1, ph - 1);

  // Portrait: map sprite scaled 1.5× in a clipped box (mirrors drawUnitCard).
  const pbx = px + 6, pby = py + 6, pbSize = 48;
  ctx.fillStyle = "#0b0916";
  ctx.fillRect(pbx, pby, pbSize, pbSize);
  ctx.save();
  ctx.beginPath();
  ctx.rect(pbx, pby, pbSize, pbSize);
  ctx.clip();
  ctx.translate(pbx + pbSize / 2, pby + pbSize / 2 + 4);
  ctx.scale(1.5, 1.5);
  // Build a throwaway unit object literal; avoids incrementing nextUnitId.
  const fakeUnit = {
    typeKey, name: t.name, element: t.element,
    owner: master.owner, q: 0, r: 0,
    hp: t.maxHp, maxHp: t.maxHp,
    move: t.move, range: t.range, power: t.power, def: t.def,
    flying: t.flying, sprite: t.sprite, attack: t.attack,
    level: 1, xp: 0, acted: false, isMaster: false,
    id: 0,
  };
  drawMapSprite(ctx, fakeUnit, 0, 3, frame);
  ctx.restore();
  ctx.strokeStyle = el.color;
  ctx.strokeRect(pbx + 0.5, pby + 0.5, pbSize - 1, pbSize - 1);

  // Stats block to the right of the portrait.
  const sx = pbx + pbSize + 6;
  const sy = py + 8;
  ctx.font = "bold 10px 'Courier New', monospace";
  ctx.textAlign = "left";
  ctx.fillStyle = el.color;
  ctx.fillText(t.name.toUpperCase(), sx, sy + 10);
  ctx.font = "9px 'Courier New', monospace";
  ctx.fillStyle = PAL.inkDim;
  ctx.fillText("HP " + t.maxHp, sx, sy + 22);
  ctx.fillStyle = el.color;
  ctx.fillText(el.short, sx, sy + 34);
  ctx.fillStyle = PAL.gold;
  ctx.fillText(t.cost + " MP", sx + 40, sy + 34);

  // Element vs enemy composition hint.
  const enemyPlayer = 1 - master.owner;
  const enemies = aliveUnits(enemyPlayer);
  let hint = "", hintColor = PAL.inkDim;
  if (enemies.length > 0) {
    let sumMul = 0;
    for (const e of enemies) {
      sumMul += ELEM_MATRIX[t.element][e.element] || 1;
    }
    const avg = sumMul / enemies.length;
    if (avg > 1.05) {
      hint = "strong vs foe"; hintColor = PAL.green;
    } else if (avg < 0.95) {
      hint = "weak vs foe"; hintColor = PAL.red;
    } else {
      hint = "even vs foe"; hintColor = PAL.inkDim;
    }
  }
  if (hint) {
    ctx.fillStyle = hintColor;
    ctx.font = "9px 'Courier New', monospace";
    ctx.fillText(hint, sx, sy + 46);
  }

  // Separator + stat row along the bottom of the panel.
  const bottomY = py + ph - 20;
  ctx.fillStyle = PAL.inkFaint;
  ctx.fillRect(px + 4, bottomY - 6, pw - 8, 1);
  ctx.font = "10px 'Courier New', monospace";
  ctx.fillStyle = PAL.ink;
  ctx.fillText("ATK " + t.power + "  DEF " + t.def + "  RNG " + t.range + "  MOV " + t.move, px + 6, bottomY + 10);

  ctx.restore();
}

function renderBanner() {
  const b = STATE.banner;
  if (!b) return;
  if (b.max === undefined) b.max = b.ttl;
  b.ttl--;
  if (b.ttl <= 0) { STATE.banner = null; return; }
  const inT = Math.min(1, (b.max - b.ttl) / 12);   // entry progress
  const outT = Math.min(1, b.ttl / 16);            // exit fade
  const alpha = Math.min(inT, outT);
  const slide = (1 - easeOutCubic(inT)) * 70;       // text eases in from the left
  const col = b.color || PAL.gold;
  const cy = CANVAS_H / 2;
  ctx.save();
  ctx.globalAlpha = alpha;
  // band with player-tinted accent rules top & bottom
  ctx.fillStyle = "rgba(8, 6, 14, 0.74)";
  ctx.fillRect(0, cy - 34, CANVAS_W, 68);
  ctx.fillStyle = col;
  ctx.fillRect(0, cy - 34, CANVAS_W, 2);
  ctx.fillRect(0, cy + 32, CANVAS_W, 2);
  ctx.font = "bold 32px 'Courier New', monospace";
  ctx.textAlign = "center";
  ctx.fillStyle = "#000";
  ctx.fillText(b.text, CANVAS_W / 2 - slide + 2, cy + 12);
  ctx.fillStyle = col;
  ctx.fillText(b.text, CANVAS_W / 2 - slide, cy + 10);
  ctx.restore();
}

// =========================================================================
// 11b. Settings & help overlays (3.3)
// =========================================================================

// Single source of truth for all clickable rects in the settings overlay.
// Returns an object with one entry per interactive element. Used by both
// renderSettingsOverlay (to draw) and onClick (to hit-test).
function settingsRects() {
  const pw = 420, ph = 310;
  const ox = Math.floor((CANVAS_W - pw) / 2);
  const oy = Math.floor((CANVAS_H - ph) / 2);
  // Labels live in the left column (ox+20); controls start at rowLeft so
  // the two never overlap.
  const rowH = 36, rowLeft = ox + 130, rowRight = ox + pw - 20;
  const rowY = (i) => oy + 72 + i * rowH; // first data row at oy+72
  // Track arrows
  const arrowW = 24;
  const trackY = rowY(0);
  const trackLeft  = { x: rowLeft, y: trackY, w: arrowW, h: 22 };
  const trackRight = { x: rowRight - arrowW, y: trackY, w: arrowW, h: 22 };
  // Music vol segments (10 + mute)
  const mvY = rowY(1);
  const segW = 18, segH = 20, segGap = 3;
  const mvSegs = [];
  for (let i = 0; i < 10; i++) mvSegs.push({ x: rowLeft + i * (segW + segGap), y: mvY, w: segW, h: segH });
  const mvMute = { x: rowLeft + 10 * (segW + segGap) + 8, y: mvY, w: 40, h: segH };
  // SFX vol segments (10 + mute)
  const svY = rowY(2);
  const svSegs = [];
  for (let i = 0; i < 10; i++) svSegs.push({ x: rowLeft + i * (segW + segGap), y: svY, w: segW, h: segH });
  const svMute = { x: rowLeft + 10 * (segW + segGap) + 8, y: svY, w: 40, h: segH };
  // Battle scene toggle
  const bsY = rowY(3);
  const bsOn  = { x: rowRight - 76, y: bsY, w: 34, h: 22 };
  const bsOff = { x: rowRight - 38, y: bsY, w: 34, h: 22 };
  // Close button
  const closeW = 100, closeH = 28;
  const closeBtn = { x: ox + Math.floor((pw - closeW) / 2), y: oy + ph - 42, w: closeW, h: closeH };
  return { ox, oy, pw, ph, trackLeft, trackRight, mvSegs, mvMute, svSegs, svMute, bsOn, bsOff, closeBtn };
}

function renderSettingsOverlay() {
  const r = settingsRects();
  ctx.save();
  // Scrim
  ctx.fillStyle = "rgba(0, 0, 0, 0.55)";
  ctx.fillRect(0, 0, CANVAS_W, CANVAS_H);
  // Panel
  ctx.fillStyle = PAL.panel;
  ctx.fillRect(r.ox, r.oy, r.pw, r.ph);
  ctx.strokeStyle = PAL.gold;
  ctx.lineWidth = 1;
  ctx.strokeRect(r.ox + 0.5, r.oy + 0.5, r.pw - 1, r.ph - 1);
  // Header
  ctx.font = "bold 18px 'Courier New', monospace";
  ctx.textAlign = "center";
  ctx.fillStyle = PAL.gold;
  ctx.fillText("SETTINGS", r.ox + r.pw / 2, r.oy + 28);
  ctx.fillStyle = PAL.inkFaint;
  ctx.fillRect(r.ox + 12, r.oy + 36, r.pw - 24, 1);

  const labelX = r.ox + 20;

  // Helper: row label
  const rowLabel = (label, y) => {
    ctx.font = "11px 'Courier New', monospace";
    ctx.textAlign = "left";
    ctx.fillStyle = PAL.inkDim;
    ctx.fillText(label, labelX, y + 15);
  };

  // ---- MUSIC TRACK row ----
  const trackY = r.oy + 72;
  rowLabel("MUSIC TRACK", trackY);
  const track = TRACKS[STATE.music.trackIndex] || TRACKS[0];
  // < arrow
  ctx.fillStyle = PAL.panelLight;
  ctx.fillRect(r.trackLeft.x, r.trackLeft.y, r.trackLeft.w, r.trackLeft.h);
  ctx.strokeStyle = PAL.inkFaint; ctx.lineWidth = 1;
  ctx.strokeRect(r.trackLeft.x + 0.5, r.trackLeft.y + 0.5, r.trackLeft.w - 1, r.trackLeft.h - 1);
  ctx.font = "bold 13px 'Courier New', monospace";
  ctx.textAlign = "center";
  ctx.fillStyle = PAL.ink;
  ctx.fillText("<", r.trackLeft.x + r.trackLeft.w / 2, r.trackLeft.y + 15);
  // > arrow
  ctx.fillStyle = PAL.panelLight;
  ctx.fillRect(r.trackRight.x, r.trackRight.y, r.trackRight.w, r.trackRight.h);
  ctx.strokeStyle = PAL.inkFaint; ctx.lineWidth = 1;
  ctx.strokeRect(r.trackRight.x + 0.5, r.trackRight.y + 0.5, r.trackRight.w - 1, r.trackRight.h - 1);
  ctx.textAlign = "center";
  ctx.fillStyle = PAL.ink;
  ctx.fillText(">", r.trackRight.x + r.trackRight.w / 2, r.trackRight.y + 15);
  // Track name
  ctx.font = "11px 'Courier New', monospace";
  ctx.fillStyle = PAL.gold;
  // Track name centred between the two arrows (controls column, not panel).
  ctx.fillText(track.name, (r.trackLeft.x + r.trackRight.x + r.trackRight.w) / 2, trackY + 15);

  // Helper: draw a 10-segment + mute volume row
  const drawVolRow = (label, y, segs, muteR, vol) => {
    rowLabel(label, y);
    const activeCount = Math.round(vol * 10);
    for (let i = 0; i < 10; i++) {
      const s = segs[i];
      ctx.fillStyle = i < activeCount ? PAL.gold : PAL.panelLight;
      ctx.fillRect(s.x, s.y, s.w, s.h);
      ctx.strokeStyle = PAL.inkFaint; ctx.lineWidth = 1;
      ctx.strokeRect(s.x + 0.5, s.y + 0.5, s.w - 1, s.h - 1);
    }
    ctx.fillStyle = vol === 0 ? PAL.gold : PAL.panelLight;
    ctx.fillRect(muteR.x, muteR.y, muteR.w, muteR.h);
    ctx.strokeStyle = PAL.inkFaint; ctx.lineWidth = 1;
    ctx.strokeRect(muteR.x + 0.5, muteR.y + 0.5, muteR.w - 1, muteR.h - 1);
    ctx.font = "9px 'Courier New', monospace";
    ctx.textAlign = "center";
    ctx.fillStyle = vol === 0 ? PAL.bg : PAL.ink;
    ctx.fillText("MUTE", muteR.x + muteR.w / 2, muteR.y + 13);
    ctx.textAlign = "left";
  };

  const rowY1 = r.oy + 72 + 36;     // row index 1
  const rowY2 = r.oy + 72 + 72;     // row index 2
  drawVolRow("MUSIC VOL", rowY1, r.mvSegs, r.mvMute, STATE.settings.musicVol);
  drawVolRow("SFX VOL",   rowY2, r.svSegs, r.svMute, STATE.settings.sfxVol);

  // ---- BATTLE SCENES row ----
  const bsY = r.oy + 72 + 108;      // row index 3
  rowLabel("BATTLE SCENES", bsY);
  const bsVal = STATE.settings.battleScene;
  ctx.fillStyle = bsVal ? PAL.gold : PAL.panelLight;
  ctx.fillRect(r.bsOn.x, r.bsOn.y, r.bsOn.w, r.bsOn.h);
  ctx.strokeStyle = PAL.inkFaint; ctx.lineWidth = 1;
  ctx.strokeRect(r.bsOn.x + 0.5, r.bsOn.y + 0.5, r.bsOn.w - 1, r.bsOn.h - 1);
  ctx.font = "10px 'Courier New', monospace";
  ctx.textAlign = "center";
  ctx.fillStyle = bsVal ? PAL.bg : PAL.ink;
  ctx.fillText("ON", r.bsOn.x + r.bsOn.w / 2, r.bsOn.y + 15);

  ctx.fillStyle = !bsVal ? PAL.gold : PAL.panelLight;
  ctx.fillRect(r.bsOff.x, r.bsOff.y, r.bsOff.w, r.bsOff.h);
  ctx.strokeStyle = PAL.inkFaint; ctx.lineWidth = 1;
  ctx.strokeRect(r.bsOff.x + 0.5, r.bsOff.y + 0.5, r.bsOff.w - 1, r.bsOff.h - 1);
  ctx.textAlign = "center";
  ctx.fillStyle = !bsVal ? PAL.bg : PAL.ink;
  ctx.fillText("OFF", r.bsOff.x + r.bsOff.w / 2, r.bsOff.y + 15);
  ctx.textAlign = "left";

  // ---- CLOSE button ----
  ctx.fillStyle = PAL.panelLight;
  ctx.fillRect(r.closeBtn.x, r.closeBtn.y, r.closeBtn.w, r.closeBtn.h);
  ctx.strokeStyle = PAL.gold; ctx.lineWidth = 1;
  ctx.strokeRect(r.closeBtn.x + 0.5, r.closeBtn.y + 0.5, r.closeBtn.w - 1, r.closeBtn.h - 1);
  ctx.font = "bold 12px 'Courier New', monospace";
  ctx.textAlign = "center";
  ctx.fillStyle = PAL.gold;
  ctx.fillText("CLOSE", r.closeBtn.x + r.closeBtn.w / 2, r.closeBtn.y + 19);
  ctx.textAlign = "left";
  ctx.restore();
}

function handleSettingsClick(p) {
  const r = settingsRects();
  const hit = (rect) => p.x >= rect.x && p.x <= rect.x + rect.w && p.y >= rect.y && p.y <= rect.y + rect.h;
  // Close
  if (hit(r.closeBtn)) { STATE.settingsOpen = false; return; }
  // Track arrows — reuse cycleTrack pattern (step ±1, reset audio.step)
  if (hit(r.trackLeft)) {
    STATE.music.trackIndex = (STATE.music.trackIndex - 1 + TRACKS.length) % TRACKS.length;
    audio.step = 0;
    STATE.banner = { text: "♪ " + TRACKS[STATE.music.trackIndex].name, ttl: 60 };
    saveSettings(); return;
  }
  if (hit(r.trackRight)) {
    cycleTrack(); saveSettings(); return;
  }
  // Music vol segments
  for (let i = 0; i < r.mvSegs.length; i++) {
    if (hit(r.mvSegs[i])) { STATE.settings.musicVol = (i + 1) / 10; saveSettings(); return; }
  }
  if (hit(r.mvMute)) { STATE.settings.musicVol = 0; saveSettings(); return; }
  // SFX vol segments
  for (let i = 0; i < r.svSegs.length; i++) {
    if (hit(r.svSegs[i])) {
      STATE.settings.sfxVol = (i + 1) / 10;
      saveSettings();
      // Play a confirmation beep at the new volume so the user can hear it.
      beep(660, 0.12, "triangle", 0.18);
      return;
    }
  }
  if (hit(r.svMute)) { STATE.settings.sfxVol = 0; saveSettings(); return; }
  // Battle scene toggle
  if (hit(r.bsOn))  { STATE.settings.battleScene = true;  saveSettings(); return; }
  if (hit(r.bsOff)) { STATE.settings.battleScene = false; saveSettings(); return; }
}

function renderHelpOverlay() {
  const pw = 640, ph = 460;
  const ox = Math.floor((CANVAS_W - pw) / 2);
  const oy = Math.floor((CANVAS_H - ph) / 2);
  ctx.save();
  // Scrim
  ctx.fillStyle = "rgba(0, 0, 0, 0.55)";
  ctx.fillRect(0, 0, CANVAS_W, CANVAS_H);
  // Panel
  ctx.fillStyle = PAL.panel;
  ctx.fillRect(ox, oy, pw, ph);
  ctx.strokeStyle = PAL.gold;
  ctx.lineWidth = 1;
  ctx.strokeRect(ox + 0.5, oy + 0.5, pw - 1, ph - 1);
  // Header
  ctx.font = "bold 18px 'Courier New', monospace";
  ctx.textAlign = "center";
  ctx.fillStyle = PAL.gold;
  ctx.fillText("HELP", ox + pw / 2, oy + 28);
  ctx.fillStyle = PAL.inkFaint;
  ctx.fillRect(ox + 12, oy + 36, pw - 24, 1);
  ctx.textAlign = "left";

  // ---- Left column: CONTROLS ----
  const lx = ox + 20, ly = oy + 52;
  ctx.font = "bold 11px 'Courier New', monospace";
  ctx.fillStyle = PAL.gold;
  ctx.fillText("CONTROLS", lx, ly);
  const controls = [
    ["click",            "select unit / move / attack"],
    ["right-click / Esc","cancel / deselect"],
    ["E",                "end turn"],
    ["M",                "toggle music"],
    ["N",                "next music track"],
    ["Space",            "center camera on unit"],
    ["arrows / WASD",    "move cursor"],
    ["Enter",            "select / act at cursor"],
    ["Tab",              "next ready unit"],
    ["?  or  H",         "this help screen"],
    ["⚙ (top-right)",   "settings"],
  ];
  ctx.font = "10px 'Courier New', monospace";
  let cy2 = ly + 16;
  for (const [key, desc] of controls) {
    ctx.fillStyle = PAL.gold;
    ctx.fillText(key, lx, cy2);
    ctx.fillStyle = PAL.inkDim;
    ctx.fillText(desc, lx + 116, cy2);
    cy2 += 16;
  }

  // ---- Right column: ELEMENT WHEEL ----
  const rx = ox + pw / 2 + 20;
  const ry = oy + 52;
  ctx.font = "bold 11px 'Courier New', monospace";
  ctx.fillStyle = PAL.gold;
  ctx.fillText("STRONG VS →", rx, ry);

  // Draw the 5 elements as labeled nodes in a pentagon, with advantage arrows.
  const elemKeys = Object.keys(ELEMENT);  // ["pyro","hydro","terra","zephyr","arcane"]
  const wheelCX = rx + (pw / 2 - 20 - 20) / 2;
  const wheelCY = ry + 130;
  const wheelR = 90;
  // Compute positions
  const nodePos = {};
  for (let i = 0; i < elemKeys.length; i++) {
    const ang = -Math.PI / 2 + i * (Math.PI * 2 / elemKeys.length);
    nodePos[elemKeys[i]] = {
      x: wheelCX + Math.cos(ang) * wheelR,
      y: wheelCY + Math.sin(ang) * wheelR,
    };
  }
  // Draw advantage arrows first (behind nodes)
  for (const a of elemKeys) {
    for (const b of elemKeys) {
      if (a === b) continue;
      if ((ELEM_MATRIX[a] || {})[b] <= 1) continue;
      const pa = nodePos[a], pb = nodePos[b];
      const dx = pb.x - pa.x, dy = pb.y - pa.y;
      const len = Math.sqrt(dx * dx + dy * dy);
      const ux = dx / len, uy = dy / len;
      const nodeRad = 14;
      const ax = pa.x + ux * nodeRad, ay = pa.y + uy * nodeRad;
      const bx = pb.x - ux * nodeRad, by = pb.y - uy * nodeRad;
      ctx.strokeStyle = ELEMENT[a].color;
      ctx.lineWidth = 1.5;
      ctx.globalAlpha = 0.7;
      ctx.beginPath();
      ctx.moveTo(ax, ay);
      ctx.lineTo(bx, by);
      ctx.stroke();
      // Arrowhead
      const hw = 5;
      const px2 = bx - ux * hw - uy * hw;
      const py2 = by - uy * hw + ux * hw;
      const px3 = bx - ux * hw + uy * hw;
      const py3 = by - uy * hw - ux * hw;
      ctx.fillStyle = ELEMENT[a].color;
      ctx.beginPath();
      ctx.moveTo(bx, by);
      ctx.lineTo(px2, py2);
      ctx.lineTo(px3, py3);
      ctx.closePath();
      ctx.fill();
    }
  }
  ctx.globalAlpha = 1;
  // Draw element nodes
  for (const key of elemKeys) {
    const pos = nodePos[key];
    const el = ELEMENT[key];
    ctx.fillStyle = el.color;
    ctx.beginPath();
    ctx.arc(pos.x, pos.y, 14, 0, Math.PI * 2);
    ctx.fill();
    ctx.font = "bold 8px 'Courier New', monospace";
    ctx.textAlign = "center";
    ctx.fillStyle = "#000";
    ctx.fillText(el.short, pos.x, pos.y + 3);
  }
  ctx.textAlign = "left";

  // Affinity note below the wheel
  ctx.font = "9px 'Courier New', monospace";
  ctx.fillStyle = PAL.inkDim;
  ctx.textAlign = "center";
  ctx.fillText("+20% atk on resonant terrain (gold glint)", wheelCX, wheelCY + wheelR + 22);
  ctx.textAlign = "left";

  // ---- CLOSE button ----
  const closeW = 100, closeH = 28;
  const cbx = ox + Math.floor((pw - closeW) / 2);
  const cby = oy + ph - 42;
  ctx.fillStyle = PAL.panelLight;
  ctx.fillRect(cbx, cby, closeW, closeH);
  ctx.strokeStyle = PAL.gold; ctx.lineWidth = 1;
  ctx.strokeRect(cbx + 0.5, cby + 0.5, closeW - 1, closeH - 1);
  ctx.font = "bold 12px 'Courier New', monospace";
  ctx.textAlign = "center";
  ctx.fillStyle = PAL.gold;
  ctx.fillText("CLOSE", cbx + closeW / 2, cby + 19);
  ctx.textAlign = "left";
  ctx.restore();
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
  STATE.mouse = { x: p.x, y: p.y };  // for RTS edge-pan in updateCamera()
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
  if (STATE.screen === "campaign") {
    const p = clientToCanvas(ev);
    for (const r of campaignRowRects()) {
      if (r.index <= STATE.campaignProgress &&
          p.x >= r.x && p.x <= r.x + r.w && p.y >= r.y && p.y <= r.y + r.h) {
        STATE.story = { index: r.index, shownAt: frame };
        STATE.screen = "story";
        beep(620, 0.08, "triangle", 0.18);
        return;
      }
    }
    return;
  }
  if (STATE.screen === "story") {
    startNewGame(CAMPAIGN[STATE.story.index]);
    STATE.story = null;
    return;
  }
  if (STATE.screen === "title") {
    // Clicking the campaign button, a map box, or a difficulty box selects;
    // clicking anywhere else starts a skirmish.
    const p = clientToCanvas(ev);
    const hit = (r) => p.x >= r.x && p.x <= r.x + r.w && p.y >= r.y && p.y <= r.y + r.h;
    if (hit(titleCampaignRect())) {
      STATE.screen = "campaign";
      beep(620, 0.08, "triangle", 0.18);
      return;
    }
    if (STATE.hasSave && hit(titleContinueRect())) {
      if (loadGame()) beep(660, 0.1, "triangle", 0.2);
      else { deleteSave(); beep(180, 0.15, "square", 0.2); } // corrupt save: clear it
      return;
    }
    for (const r of titleMapRects()) {
      if (hit(r)) {
        STATE.mapIndex = r.index;
        saveSettings();
        beep(620, 0.06, "triangle", 0.15);
        return;
      }
    }
    for (const r of titleDiffRects()) {
      if (hit(r)) {
        STATE.difficulty = r.key;
        saveSettings();
        beep(520, 0.06, "triangle", 0.15);
        return;
      }
    }
    startNewGame();
    return;
  }
  if (STATE.screen === "gameover") { returnToTitle(); return; }
  if (STATE.screen === "battle") return;
  if (STATE.moveAnim) return;
  if (STATE.pendingAI) return;
  if (PLAYERS[STATE.currentPlayer].isAI) return;

  const p = clientToCanvas(ev);

  // Overlays intercept all map input (3.3). Settings clicks are routed to
  // handleSettingsClick; any click closes the help screen.
  if (STATE.screen === "play" && STATE.settingsOpen) { handleSettingsClick(p); return; }
  if (STATE.screen === "play" && STATE.helpOpen)     { STATE.helpOpen = false; return; }

  // Top-bar icon buttons — check before map/menu logic.
  if (STATE.screen === "play" && p.y < TOPBAR_H) {
    const btns = topBarButtonRects();
    const hit = (r) => p.x >= r.x && p.x <= r.x + r.w && p.y >= r.y && p.y <= r.y + r.h;
    if (hit(btns.gear)) { STATE.settingsOpen = true; STATE.helpOpen = false; return; }
    if (hit(btns.help)) { STATE.helpOpen = true; STATE.settingsOpen = false; return; }
  }

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

  interactAt(local.q, local.r);
}

// 6.2 — log scrollback: wheel inside the BATTLE LOG strip scrolls older/newer.
function onWheel(ev) {
  if (STATE.screen !== "play") return;
  const p = clientToCanvas(ev);
  // Log strip occupies x >= SIDEBAR_X, y >= CANVAS_H - 170.
  if (p.x < SIDEBAR_X || p.y < CANVAS_H - 170) return;
  ev.preventDefault();
  const logMax = Math.max(0, STATE.log.length - 10);
  STATE.logScroll = Math.max(0, Math.min(logMax, STATE.logScroll + Math.sign(ev.deltaY)));
}

// Map-interaction core: select a unit, move into a reachable hex, fire an
// attack, or deselect. Shared by mouse clicks and the keyboard cursor (3.4).
function interactAt(q, r) {
  if (!inBounds(q, r)) return;

  // 1.3: blink arm — tile-target; must be checked first (blinkArm may be set
  // without STATE.selected/reachable, so the normal umbrella won't catch it).
  if (STATE.blinkArm) {
    const arm = STATE.blinkArm;
    const unit = arm.unit;
    const ab = arm.ab;
    if (arm.tiles.has(hexKey(q, r))) {
      STATE.blinkArm = null;
      STATE.selected = null; STATE.reachable = null; STATE.attackTargets = null;
      moveUnitTo(unit, q, r);
      pushAnim("summon", q, r, "", PAL.purple, "176, 120, 200");
      beep(700, 0.1, "triangle", 0.2);
      unit.acted = true; unit.cd = ab.cd; STATE.undo = null;
    } else {
      // mis-click: back out to the unit's post-move menu. The unit already
      // moved, so freeing it here would grant a repeatable extra move
      // (Phase-1 review exploit fix) — the menu keeps its options open
      // without re-opening movement.
      STATE.blinkArm = null;
      STATE.selected = null; STATE.reachable = null; STATE.attackTargets = null;
      openPostMoveMenu(unit);
    }
    return;
  }

  // 1.3: enemy-target ability arm (and plain-attack arm when ab===null) —
  // STATE.reachable is null in the post-move context, so this must live before
  // the selected+reachable umbrella which would otherwise be skipped entirely.
  if (STATE.abilityArm && STATE.attackTargets && STATE.attackTargets.has(hexKey(q, r))) {
    const target = unitAt(q, r);
    const arm = STATE.abilityArm;
    if (target) {
      STATE.abilityArm = null;
      STATE.selected = null; STATE.reachable = null; STATE.attackTargets = null;
      arm.unit.acted = true;
      if (arm.ab) arm.unit.cd = arm.ab.cd; // plain attack (ab=null) has no cooldown
      STATE.undo = null;
      if (arm.ab) {
        beginBattle(arm.unit, target, null, { applyStatus: arm.ab.status, statusTurns: arm.ab.statusTurns });
      } else {
        beginBattle(arm.unit, target, null); // plain attack — no opts
      }
    }
    return;
  }
  if (STATE.abilityArm) {
    // mis-click outside targets: back out to the unit's post-move menu —
    // the move already happened, so the unit must not become re-selectable
    // (Phase-1 review exploit fix).
    const unit = STATE.abilityArm.unit;
    STATE.abilityArm = null;
    STATE.selected = null; STATE.reachable = null; STATE.attackTargets = null;
    openPostMoveMenu(unit);
    return;
  }

  const onUnit = unitAt(q, r);

  if (STATE.selected && STATE.reachable) {
    const k = hexKey(q, r);
    if (STATE.reachable.has(k)) {
      const unit = STATE.selected;
      const reach = STATE.reachable;
      STATE.selected = null;
      STATE.reachable = null;
      STATE.attackTargets = null;
      STATE.undo = { unit, q: unit.q, r: unit.r }; // 6.2 snapshot pre-move position
      startMove(unit, q, r, reach, () => openPostMoveMenu(unit));
      return;
    } else if (STATE.attackTargets && STATE.attackTargets.has(hexKey(q, r))) {
      const target = unitAt(q, r);
      if (target) {
        const atk = STATE.selected;
        atk.acted = true;
        STATE.selected = null; STATE.reachable = null; STATE.attackTargets = null;
        STATE.undo = null; // 6.2 attack committed
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
    // secondMove leg (skitter/galeRush): move-only — suppress attack rings entirely
    // so the player cannot attack from this re-select (ability + attack in one turn).
    if (onUnit.secondMove) STATE.attackTargets = null;
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
    // ←/→ cycle the AI difficulty (4.3); ↑/↓ cycle the map (5.2)
    if (ev.key === "ArrowLeft" || ev.key === "ArrowRight") {
      const dir = ev.key === "ArrowLeft" ? -1 : 1;
      const i = DIFFICULTIES.indexOf(STATE.difficulty);
      STATE.difficulty = DIFFICULTIES[(i + dir + DIFFICULTIES.length) % DIFFICULTIES.length];
      saveSettings();
      beep(520, 0.06, "triangle", 0.15);
    }
    if (ev.key === "ArrowUp" || ev.key === "ArrowDown") {
      const dir = ev.key === "ArrowUp" ? -1 : 1;
      STATE.mapIndex = (STATE.mapIndex + dir + MAPS.length) % MAPS.length;
      saveSettings();
      beep(620, 0.06, "triangle", 0.15);
    }
    if (ev.key === "c" || ev.key === "C") STATE.screen = "campaign";
    return;
  }
  if (STATE.screen === "campaign") {
    if (ev.key === "Escape") STATE.screen = "title";
    return;
  }
  if (STATE.screen === "story") {
    if (ev.key === "Enter" || ev.key === " ") {
      startNewGame(CAMPAIGN[STATE.story.index]);
      STATE.story = null;
    }
    if (ev.key === "Escape") { STATE.screen = "campaign"; STATE.story = null; }
    return;
  }
  if (STATE.screen === "gameover") {
    if (ev.key === "Enter" || ev.key === " ") returnToTitle();
    return;
  }
  if (STATE.screen === "battle") return;
  if (STATE.moveAnim) return;
  if (PLAYERS[STATE.currentPlayer].isAI && STATE.pendingAI) return;

  // Overlay close / toggle — handle before menu logic so Esc also closes overlays (3.3).
  if (STATE.screen === "play") {
    if (ev.key === "Escape") {
      if (STATE.settingsOpen) { STATE.settingsOpen = false; return; }
      if (STATE.helpOpen)     { STATE.helpOpen = false;     return; }
    }
    if (ev.key === "?" || ev.key === "h" || ev.key === "H") {
      STATE.helpOpen = !STATE.helpOpen;
      STATE.settingsOpen = false;
      return;
    }
  }

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
  if (ev.key === " ") {  // centre on the selected unit, else the active master
    ev.preventDefault();
    centerCameraOn(STATE.selected || masterOf(STATE.currentPlayer));
    return;
  }
  if (ev.key === "Escape") {
    // Esc on a live arm backs out to the unit's post-move menu — the move
    // already happened, so the unit must not become re-selectable
    // (Phase-1 review exploit fix).
    const arm = STATE.abilityArm || STATE.blinkArm;
    STATE.selected = null; STATE.reachable = null; STATE.attackTargets = null;
    STATE.abilityArm = null; STATE.blinkArm = null; // 1.3
    if (arm) { openPostMoveMenu(arm.unit); return; }
    // If cursor was active but nothing was selected, clear it too.
    if (!STATE.selected) STATE.cursor = null;
    return;
  }

  // ---- Keyboard cursor (3.4) ----
  // Arrows and WASD move a hex cursor around the map (replaces old camera pan).
  // The cursor's camera-follow handles panning. w/s are consumed by menu nav
  // above (that block returns early) so they only reach here when no menu.
  const isArrow = ev.key === "ArrowLeft" || ev.key === "ArrowRight" ||
                  ev.key === "ArrowUp"   || ev.key === "ArrowDown";
  const isWASD  = ev.key === "a" || ev.key === "d" ||
                  ev.key === "w" || ev.key === "s";

  if (isArrow || isWASD) {
    ev.preventDefault();
    // Initialize cursor if not yet active.
    if (!STATE.cursor) {
      if (STATE.selected) {
        STATE.cursor = { q: STATE.selected.q, r: STATE.selected.r };
      } else {
        const m = masterOf(STATE.currentPlayer);
        if (m) {
          STATE.cursor = { q: m.q, r: m.r };
        } else {
          // Fallback: map centre hex.
          const cells = [...MAP.cells.values()];
          const mid = cells[Math.floor(cells.length / 2)];
          STATE.cursor = { q: mid.q, r: mid.r };
        }
      }
    }
    const cq = STATE.cursor.q, cr = STATE.cursor.r;
    let nq = cq, nr = cr;
    // Pointy-top axial zigzag: up/down pick the diagonal that keeps the cursor
    // visually above/below the current hex. The choice depends on row parity.
    // "r odd" means the row index is odd (using standard offset parity).
    if (ev.key === "ArrowLeft"  || ev.key === "a") { nq = cq - 1; nr = cr; }
    if (ev.key === "ArrowRight" || ev.key === "d") { nq = cq + 1; nr = cr; }
    if (ev.key === "ArrowUp"    || ev.key === "w") {
      // Preferred: r odd → NE(+1,-1); r even → NW(0,-1)
      if ((cr & 1) === 1) { nq = cq + 1; nr = cr - 1; }
      else                { nq = cq;     nr = cr - 1; }
      // Fallback: if preferred is out of bounds, try the other diagonal.
      if (!inBounds(nq, nr)) {
        if ((cr & 1) === 1) { nq = cq;     nr = cr - 1; }
        else                { nq = cq + 1; nr = cr - 1; }
      }
      if (!inBounds(nq, nr)) { nq = cq; nr = cr; } // both fail: stay
    }
    if (ev.key === "ArrowDown"  || ev.key === "s") {
      // Preferred: r odd → SE(0,+1); r even → SW(-1,+1)
      if ((cr & 1) === 1) { nq = cq;     nr = cr + 1; }
      else                { nq = cq - 1; nr = cr + 1; }
      // Fallback: try the other diagonal.
      if (!inBounds(nq, nr)) {
        if ((cr & 1) === 1) { nq = cq - 1; nr = cr + 1; }
        else                { nq = cq;     nr = cr + 1; }
      }
      if (!inBounds(nq, nr)) { nq = cq; nr = cr; } // both fail: stay
    }
    STATE.cursor = { q: nq, r: nr };
    STATE.hover  = { q: nq, r: nr };   // sidebar card + forecast

    // Follow cursor: if it's near the viewport edge, ease the camera to it.
    const cp = axialToPixel(nq, nr);
    const visL = -STATE.cam.x, visR = -STATE.cam.x + MAP_W;
    const visT = -STATE.cam.y, visB = -STATE.cam.y + MAP_H;
    const edgePad = HEX_SIZE * 1.5;
    if (cp.x < visL + edgePad || cp.x > visR - edgePad ||
        cp.y < visT + edgePad || cp.y > visB - edgePad) {
      centerCameraOn({ q: nq, r: nr });
    }
    return;
  }

  // Enter confirms action at the cursor hex (or no-op if cursor not set).
  if (ev.key === "Enter") {
    if (!STATE.cursor) return;
    interactAt(STATE.cursor.q, STATE.cursor.r);
    return;
  }

  // Tab cycles through the current player's ready units (non-AI turn only).
  if (ev.key === "Tab") {
    ev.preventDefault();
    if (PLAYERS[STATE.currentPlayer].isAI) return;
    const ready = STATE.units.filter(
      u => u.hp > 0 && !u.acted && u.owner === STATE.currentPlayer
    );
    if (!ready.length) return;
    // Find the index after the currently selected unit; wrap around.
    let idx = 0;
    if (STATE.selected) {
      const cur = ready.indexOf(STATE.selected);
      if (cur >= 0) idx = (cur + 1) % ready.length;
    }
    const next = ready[idx];
    // Drop any live selection first so interactAt can't read the next unit's
    // hex as a move/attack destination for the previously selected unit.
    STATE.selected = null; STATE.reachable = null; STATE.attackTargets = null;
    interactAt(next.q, next.r);  // select it the same way a click would
    STATE.cursor = { q: next.q, r: next.r };
    STATE.hover  = { q: next.q, r: next.r };
    centerCameraOn({ q: next.q, r: next.r });
    return;
  }
}

function mapPixelWidth() { return HEX_STEP_X * (COLS + 0.5) + 12; }
function mapPixelHeight() { return HEX_STEP_Y * ROWS + HEX_SIZE + 12; }

// Build the post-move action menu for `unit` at its current tile. Shared by
// the move handler, the summon-picker "Back", and the cancel-out path.
function openPostMoveMenu(unit) {
  const items = [];
  const cellHere = cellAt({ q: unit.q, r: unit.r });
  // Second-move leg (skitter/galeRush): only Capture and Wait are available —
  // no Attack, Summon, Ability, or Undo.
  if (unit.secondMove) {
    unit.secondMove = false;
    if (canCapture(unit, cellHere)) items.push({ label: "Capture", kind: "capture" });
    items.push({ label: "Wait", kind: "wait" });
  } else {
    const targets = computeAttackTargets(unit, unit.q, unit.r);
    if (targets.size > 0) items.push({ label: "Attack", kind: "attackMode" });
    if (canCapture(unit, cellHere)) items.push({ label: "Capture", kind: "capture" });
    if (unit.isMaster && unit.mp >= 6) items.push({ label: "Summon", kind: "summon" });
    const ab = abilityFor(unit);
    if (ab) items.push({
      label: unit.cd > 0 ? ab.name + " (" + unit.cd + ")" : ab.name,
      kind: "ability", disabled: unit.cd > 0,
    });
    if (STATE.undo && STATE.undo.unit === unit) items.push({ label: "Undo", kind: "undo" }); // 6.2
    items.push({ label: "Wait", kind: "wait" });
  }
  const px = axialToPixel(unit.q, unit.r);
  STATE.menu = {
    kind: "postMove", unit, items, index: 0,
    anchor: { x: px.x + STATE.cam.x, y: px.y + STATE.cam.y + TOPBAR_H },
  };
}

function selectMenuItem(item) {
  if (item.disabled) return;
  const unit = STATE.menu.unit;
  if (item.kind === "wait") {
    STATE.undo = null; unit.acted = true; closeMenu(); // 6.2 commit clears undo
  } else if (item.kind === "attackMode") {
    // Fix A (1.3): arm a plain attack via the abilityArm pattern so interactAt
    // can route it — the old path set reachable=null which made the attack branch
    // inside the selected+reachable umbrella unreachable, silently dead-buttoning.
    const targets = computeAttackTargets(unit, unit.q, unit.r);
    if (!targets.size) { pushLog("No target in range."); return; } // menu stays open
    STATE.attackTargets = targets;
    STATE.abilityArm = { unit, ab: null }; // ab=null → plain attack, no cd
    STATE.menu = null;
    // NOTE: STATE.undo stays live until the actual attack is confirmed in
    // interactAt — at that point STATE.undo is set to null.
  } else if (item.kind === "capture") {
    const cell = cellAt({ q: unit.q, r: unit.r });
    if (cell && cell.terrain === "tower") captureTower(unit, cell);
    STATE.undo = null; unit.acted = true; closeMenu(); // 6.2 commit clears undo
  } else if (item.kind === "undo") {
    // 6.2 — teleport the unit back to its pre-move hex, reset acted flag,
    // clear the snapshot, close the menu, then re-select the unit so that
    // reachable/attack overlays come back (mirrors a fresh click on the unit).
    moveUnitTo(unit, STATE.undo.q, STATE.undo.r);
    unit.acted = false;
    STATE.undo = null;
    closeMenu();
    interactAt(unit.q, unit.r);
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
    if (STATE.stats) STATE.stats.summoned[unit.owner]++;
    pushLog(unit.name + " summons " + u.name + ".", PAL.purple);
    pushAnim("summon", slot.q, slot.r, "", PAL.gold, "190, 150, 230");
    beep(660, 0.08, "triangle", 0.18);
    STATE.undo = null; unit.acted = true; closeMenu();
  } else if (item.kind === "ability") {
    const ab = abilityFor(unit);
    if (!ab) { closeMenu(); return; }
    if (ab.target === "none") {
      if (resolveInstantAbility(unit, ab)) {
        unit.cd = ab.cd;
        STATE.undo = null;
        if (unit.secondMove) {
          closeMenu();
          interactAt(unit.q, unit.r); // reselect: fresh reachable for the move-only leg
        } else {
          unit.acted = true;
          closeMenu();
        }
      }
      return;
    }
    if (ab.target === "enemy") {
      const targets = computeAttackTargets(unit, unit.q, unit.r);
      if (!targets.size) { pushLog("No target in range."); return; } // menu stays open
      STATE.attackTargets = targets;
      STATE.abilityArm = { unit, ab };
      STATE.menu = null; // keep selection; next target click routes via interactAt
      return;
    }
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
  } else if (item.kind === "back") {
    openPostMoveMenu(unit);
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
    openPostMoveMenu(STATE.menu.unit);
    return;
  }
  // Post-move menu cancel commits the move (move is already applied; this
  // is equivalent to Wait). Without this, the unit becomes reselectable
  // and the player can repeatedly move it.
  if (STATE.menu.unit && !STATE.menu.unit.acted) STATE.menu.unit.acted = true;
  STATE.undo = null; // 6.2 escape-to-cancel commits, so undo is no longer valid
  STATE.abilityArm = null; STATE.blinkArm = null; // 1.3
  closeMenu();
}

// =========================================================================
// 13. Turn / phase machinery
// =========================================================================

function endTurn() {
  if (STATE.menu) closeMenu();
  STATE.undo = null; // 6.2 turn ends — any in-flight undo snapshot is void
  for (const u of aliveUnits(STATE.currentPlayer)) u.acted = true;
  STATE.currentPlayer = 1 - STATE.currentPlayer;
  if (STATE.currentPlayer === 0) STATE.turn++;
  const m = masterOf(STATE.currentPlayer);
  if (m) {
    const towerBonus = MAP.towers.filter(t => t.owner === STATE.currentPlayer).length * 2;
    const regen = m.mpRegen + towerBonus;
    m.mp = Math.min(m.maxMp, m.mp + regen);
    pushLog(PLAYERS[STATE.currentPlayer].name + " gains " + regen + " MP (towers +" + towerBonus + ").", PAL.inkDim);
  }
  tickStatuses(STATE.currentPlayer);
  if (STATE.screen !== "play") return; // burn-kill may have ended the match
  for (const u of aliveUnits(STATE.currentPlayer)) {
    u.acted = false;
    u.secondMove = false;
    if (u.cd > 0) u.cd--;
    const c = cellAt({ q: u.q, r: u.r });
    const hpBefore = u.hp;
    if (c && c.terrain === "tower" && c.owner === u.owner) u.hp = Math.min(u.maxHp, u.hp + 2);
    if (c && c.terrain === "castle" && c.owner === u.owner) u.hp = Math.min(u.maxHp, u.hp + 4);
    if (u.hp > hpBefore) pushAnim("float", u.q, u.r, "+" + (u.hp - hpBefore), "#5fd06a");
    tryEvolve(u, c); // level-4+ on owned tower/castle → terminal form
  }
  STATE.selected = null;
  STATE.reachable = null;
  STATE.attackTargets = null;
  STATE.abilityArm = null; STATE.blinkArm = null; // 1.3 stale arms cleared on turn change
  STATE.banner = { text: PLAYERS[STATE.currentPlayer].name + " — TURN " + STATE.turn, ttl: 80, color: PLAYERS[STATE.currentPlayer].color };
  // Weather ticks once per full round, AFTER the turn banner is set so a
  // shift's banner isn't clobbered by it (1.5 review fix).
  if (STATE.currentPlayer === 0 && STATE.weather && --STATE.weather.turnsLeft <= 0) rollWeather();
  checkWinCondition();
  if (STATE.screen !== "play") return;
  saveGame(); // autosave each turn (6.1)
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

  // Campaign entry (5.3) — sits between the two archons; CONTINUE (6.1)
  // appears beside it when an autosave exists.
  const drawTitleBtn = (r, label, sub, accent) => {
    ctx.fillStyle = "rgba(31, 28, 48, 0.9)";
    ctx.fillRect(r.x, r.y, r.w, r.h);
    ctx.strokeStyle = accent;
    ctx.lineWidth = 1;
    ctx.strokeRect(r.x + 0.5, r.y + 0.5, r.w - 1, r.h - 1);
    ctx.font = "bold 13px 'Courier New', monospace";
    ctx.fillStyle = accent;
    ctx.fillText(label, r.x + r.w / 2, r.y + 17);
    ctx.font = "9px 'Courier New', monospace";
    ctx.fillStyle = PAL.inkDim;
    ctx.fillText(sub, r.x + r.w / 2, r.y + 30);
  };
  const nextMission = STATE.campaignProgress >= CAMPAIGN.length - 1 ? null : CAMPAIGN[STATE.campaignProgress];
  drawTitleBtn(titleCampaignRect(), "CAMPAIGN",
    nextMission ? "next: " + nextMission.name : "all missions open", PAL.gold);
  if (STATE.hasSave) {
    drawTitleBtn(titleContinueRect(), "CONTINUE", "resume the saved battle", PAL.green);
  }

  ctx.font = "13px 'Courier New', monospace";
  ctx.fillStyle = PAL.inkDim;
  const lore = [
    "Two summoning archons command the frontier.",
    "Bind elemental beasts. Seize the spires.",
  ];
  for (let i = 0; i < lore.length; i++) {
    ctx.fillText(lore[i], CANVAS_W / 2, CANVAS_H * 0.835 + i * 17);
  }

  // Map selector (5.2) — a row of named battlefields; ↑/↓ also cycles.
  const mapRects = titleMapRects();
  ctx.font = "bold 11px 'Courier New', monospace";
  ctx.textAlign = "center";
  for (const r of mapRects) {
    const sel = r.index === STATE.mapIndex;
    ctx.fillStyle = sel ? PAL.purple : "rgba(31, 28, 48, 0.85)";
    ctx.fillRect(r.x, r.y, r.w, r.h);
    ctx.strokeStyle = sel ? PAL.purple : PAL.inkFaint;
    ctx.lineWidth = 1;
    ctx.strokeRect(r.x + 0.5, r.y + 0.5, r.w - 1, r.h - 1);
    ctx.fillStyle = sel ? PAL.bg : PAL.inkDim;
    ctx.fillText(MAPS[r.index].name.toUpperCase(), r.x + r.w / 2, r.y + 15);
  }
  // Selected map blurb under the row.
  ctx.font = "10px 'Courier New', monospace";
  ctx.fillStyle = PAL.inkDim;
  const selMap = MAPS[STATE.mapIndex] || MAPS[0];
  ctx.fillText(selMap.desc + "  (" + selMap.cols + "x" + selMap.rows + ", " + selMap.towers + " spires)",
    CANVAS_W / 2, mapRects[0].y + mapRects[0].h + 13);

  // Difficulty selector (4.3) — boxes drawn from the same rects onClick tests.
  const diffRects = titleDiffRects();
  ctx.font = "bold 12px 'Courier New', monospace";
  ctx.textAlign = "center";
  for (const r of diffRects) {
    const sel = r.key === STATE.difficulty;
    ctx.fillStyle = sel ? PAL.gold : "rgba(31, 28, 48, 0.85)";
    ctx.fillRect(r.x, r.y, r.w, r.h);
    ctx.strokeStyle = sel ? PAL.gold : PAL.inkFaint;
    ctx.lineWidth = 1;
    ctx.strokeRect(r.x + 0.5, r.y + 0.5, r.w - 1, r.h - 1);
    ctx.fillStyle = sel ? PAL.bg : PAL.inkDim;
    ctx.fillText(r.key.toUpperCase(), r.x + r.w / 2, r.y + 16);
  }

  const blink = Math.floor(frame / 30) % 2 === 0;
  if (blink) {
    ctx.font = "bold 15px 'Courier New', monospace";
    ctx.fillStyle = PAL.gold;
    ctx.fillText("CLICK OR PRESS ENTER TO BEGIN", CANVAS_W / 2, CANVAS_H * 0.973);
  }
  ctx.font = "10px 'Courier New', monospace";
  ctx.fillStyle = PAL.inkFaint;
  ctx.textAlign = "right";
  ctx.fillText("v1.2 — M music", CANVAS_W - 10, CANVAS_H - 10);
  ctx.textAlign = "center";
}

// Clickable difficulty boxes on the title screen (4.3); shared by render+click.
function titleDiffRects() {
  const w = 92, h = 24, gap = 14;
  const total = DIFFICULTIES.length * w + (DIFFICULTIES.length - 1) * gap;
  const x0 = (CANVAS_W - total) / 2;
  const y = 742;
  return DIFFICULTIES.map((key, i) => ({ key, x: x0 + i * (w + gap), y, w, h }));
}

// Clickable map boxes on the title screen (5.2); shared by render+click.
function titleMapRects() {
  const w = 150, h = 22, gap = 8;
  const total = MAPS.length * w + (MAPS.length - 1) * gap;
  const x0 = (CANVAS_W - total) / 2;
  const y = 698;
  return MAPS.map((m, i) => ({ index: i, x: x0 + i * (w + gap), y, w, h }));
}

// Campaign button between the title archons (5.3); shared by render+click.
// When a save exists the two buttons sit side by side.
function titleCampaignRect() {
  const y = CANVAS_H * 0.60;
  return STATE.hasSave
    ? { x: CANVAS_W / 2 - 188, y, w: 180, h: 38 }
    : { x: CANVAS_W / 2 - 90, y, w: 180, h: 38 };
}

// Continue (load autosave) button on the title screen (6.1).
function titleContinueRect() {
  return { x: CANVAS_W / 2 + 8, y: CANVAS_H * 0.60, w: 180, h: 38 };
}

// Leave a finished match: back to title, drop the campaign tag, and restore
// the player's persisted skirmish prefs (a campaign mission overrode
// STATE.difficulty for its own match).
function returnToTitle() {
  STATE.screen = "title";
  STATE.campaign = null;
  STATE.story = null;
  STATE.matchDifficulty = null;
}

// =========================================================================
// 14b. Campaign screens (5.3)
// =========================================================================

// Mission list rows; shared by renderCampaignScreen and onClick.
function campaignRowRects() {
  const w = 720, h = 70, gap = 16;
  const x = (CANVAS_W - w) / 2;
  const y0 = 170;
  return CAMPAIGN.map((sc, i) => ({ index: i, x, y: y0 + i * (h + gap), w, h }));
}

function renderCampaignScreen() {
  ctx.fillStyle = "#05030c";
  ctx.fillRect(0, 0, CANVAS_W, CANVAS_H);
  ctx.textAlign = "center";
  ctx.font = "bold 28px 'Courier New', monospace";
  ctx.fillStyle = PAL.gold;
  ctx.fillText("CAMPAIGN", CANVAS_W / 2, 90);
  ctx.font = "11px 'Courier New', monospace";
  ctx.fillStyle = PAL.inkDim;
  ctx.fillText("— the fall of the crimson archon, in four battles —", CANVAS_W / 2, 116);

  for (const r of campaignRowRects()) {
    const sc = CAMPAIGN[r.index];
    const unlocked = r.index <= STATE.campaignProgress;
    const cleared = r.index < STATE.campaignProgress;
    ctx.fillStyle = unlocked ? PAL.panelLight : "rgba(19, 17, 31, 0.7)";
    ctx.fillRect(r.x, r.y, r.w, r.h);
    ctx.strokeStyle = unlocked ? PAL.gold : PAL.inkFaint;
    ctx.lineWidth = 1;
    ctx.strokeRect(r.x + 0.5, r.y + 0.5, r.w - 1, r.h - 1);

    ctx.textAlign = "left";
    ctx.font = "bold 16px 'Courier New', monospace";
    ctx.fillStyle = unlocked ? PAL.gold : PAL.inkFaint;
    ctx.fillText((r.index + 1) + ".  " + sc.name, r.x + 18, r.y + 28);
    ctx.font = "10px 'Courier New', monospace";
    ctx.fillStyle = unlocked ? PAL.inkDim : PAL.inkFaint;
    ctx.fillText(unlocked ? sc.intro[0] + " ..." : "locked — clear the previous mission",
      r.x + 18, r.y + 48);
    ctx.textAlign = "right";
    ctx.font = "bold 11px 'Courier New', monospace";
    if (cleared) { ctx.fillStyle = PAL.green; ctx.fillText("CLEARED", r.x + r.w - 16, r.y + 28); }
    else if (unlocked) { ctx.fillStyle = PAL.gold; ctx.fillText("READY", r.x + r.w - 16, r.y + 28); }
    else { ctx.fillStyle = PAL.inkFaint; ctx.fillText("LOCKED", r.x + r.w - 16, r.y + 28); }
    ctx.font = "10px 'Courier New', monospace";
    ctx.fillStyle = unlocked ? PAL.inkDim : PAL.inkFaint;
    ctx.fillText(sc.difficulty.toUpperCase(), r.x + r.w - 16, r.y + 48);
    ctx.textAlign = "center";
  }

  ctx.font = "11px 'Courier New', monospace";
  ctx.fillStyle = PAL.inkDim;
  ctx.fillText("click a mission to begin  ·  ESC to return", CANVAS_W / 2, CANVAS_H - 40);
}

function renderStoryScreen() {
  const sc = CAMPAIGN[STATE.story.index];
  ctx.fillStyle = "#05030c";
  ctx.fillRect(0, 0, CANVAS_W, CANVAS_H);
  ctx.textAlign = "center";
  ctx.font = "10px 'Courier New', monospace";
  ctx.fillStyle = PAL.inkFaint;
  ctx.fillText("MISSION " + (STATE.story.index + 1) + " OF " + CAMPAIGN.length, CANVAS_W / 2, CANVAS_H * 0.3);
  ctx.font = "bold 24px 'Courier New', monospace";
  ctx.fillStyle = PAL.gold;
  ctx.fillText(sc.name.toUpperCase(), CANVAS_W / 2, CANVAS_H * 0.3 + 34);

  ctx.font = "14px 'Courier New', monospace";
  ctx.fillStyle = PAL.ink;
  // Lines fade in one after another for a little ceremony.
  for (let i = 0; i < sc.intro.length; i++) {
    const a = Math.max(0, Math.min(1, (frame - (STATE.story.shownAt || 0) - i * 26) / 26));
    if (a <= 0) continue;
    ctx.globalAlpha = a;
    ctx.fillText(sc.intro[i], CANVAS_W / 2, CANVAS_H * 0.46 + i * 24);
  }
  ctx.globalAlpha = 1;

  if (Math.floor(frame / 30) % 2 === 0) {
    ctx.font = "bold 14px 'Courier New', monospace";
    ctx.fillStyle = PAL.gold;
    ctx.fillText("CLICK TO BEGIN", CANVAS_W / 2, CANVAS_H * 0.78);
  }
  ctx.textAlign = "left";
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

  // Match summary
  const st = STATE.stats || { summoned: [0, 0], lost: [0, 0], battles: 0 };
  const towers = [
    MAP.towers.filter(t => t.owner === 0).length,
    MAP.towers.filter(t => t.owner === 1).length,
  ];
  ctx.font = "14px 'Courier New', monospace";
  ctx.textAlign = "center";
  ctx.fillStyle = PAL.inkDim;
  ctx.fillText("Turns elapsed: " + STATE.turn + "     Battles fought: " + st.battles, CANVAS_W / 2, CANVAS_H / 2 + 116);

  // two-column stat table
  const cx0 = CANVAS_W / 2, colL = cx0 - 90, colR = cx0 + 90, top = CANVAS_H / 2 + 140;
  ctx.font = "bold 13px 'Courier New', monospace";
  ctx.fillStyle = PAL.p0; ctx.fillText("AZURE", colL, top);
  ctx.fillStyle = PAL.p1; ctx.fillText("CRIMSON", colR, top);
  const rows = [
    ["Summoned", st.summoned[0], st.summoned[1]],
    ["Lost",     st.lost[0],     st.lost[1]],
    ["Spires",   towers[0],      towers[1]],
  ];
  ctx.font = "12px 'Courier New', monospace";
  rows.forEach((row, i) => {
    const ry = top + 20 + i * 17;
    ctx.fillStyle = PAL.inkDim; ctx.textAlign = "center";
    ctx.fillText(row[0], cx0, ry);
    ctx.fillStyle = PAL.ink; ctx.textAlign = "center";
    ctx.fillText(String(row[1]), colL, ry);
    ctx.fillText(String(row[2]), colR, ry);
  });

  // Campaign verdict (5.3)
  if (STATE.campaign) {
    ctx.font = "bold 13px 'Courier New', monospace";
    ctx.textAlign = "center";
    if (STATE.winner === 0) {
      const last = STATE.campaign.index >= CAMPAIGN.length - 1;
      ctx.fillStyle = PAL.green;
      ctx.fillText(last ? "CAMPAIGN COMPLETE — THE REALM IS YOURS"
                        : "MISSION COMPLETE — THE NEXT BATTLE AWAITS", CANVAS_W / 2, CANVAS_H / 2 + 196);
    } else {
      ctx.fillStyle = PAL.red;
      ctx.fillText("MISSION FAILED — THE FRONTIER REMEMBERS", CANVAS_W / 2, CANVAS_H / 2 + 196);
    }
  }

  const blink = Math.floor(frame / 30) % 2 === 0;
  if (blink) {
    ctx.font = "14px 'Courier New', monospace";
    ctx.fillStyle = PAL.gold;
    ctx.textAlign = "center";
    ctx.fillText("PRESS ENTER TO RETURN", CANVAS_W / 2, CANVAS_H / 2 + 224);
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
  saveSettings(); // persist the new track choice (3.3)
}

function playSynth(freq, type, dur, gain, filterHz, attack, reverbSend) {
  if (!audio.ctx) return;
  if (STATE.settings.musicVol <= 0) return; // muted — skip (avoids exponentialRamp from 0)
  const t = audio.ctx.currentTime;
  const osc = audio.ctx.createOscillator();
  const g = audio.ctx.createGain();
  const lp = audio.ctx.createBiquadFilter();
  lp.type = "lowpass";
  lp.frequency.value = filterHz || 2000;
  lp.Q.value = 0.7;
  osc.type = type;
  osc.frequency.value = freq;
  const peak = gain * audio.duck * STATE.settings.musicVol;
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
  if (STATE.settings.musicVol <= 0) return;
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
  const peak = gain * audio.duck * STATE.settings.musicVol;
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
  if (STATE.settings.musicVol <= 0) return;
  const t = audio.ctx.currentTime;
  const osc = audio.ctx.createOscillator();
  const g = audio.ctx.createGain();
  osc.type = "sine";
  osc.frequency.setValueAtTime(110, t);
  osc.frequency.exponentialRampToValueAtTime(40, t + 0.08);
  g.gain.setValueAtTime(0, t);
  g.gain.linearRampToValueAtTime(gain * audio.duck * STATE.settings.musicVol, t + 0.002);
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
  clickG.gain.setValueAtTime(gain * 0.5 * audio.duck * STATE.settings.musicVol, t);
  clickG.gain.exponentialRampToValueAtTime(0.0001, t + 0.015);
  src.connect(clickFilt); clickFilt.connect(clickG); clickG.connect(audio.musicGain);
  src.start(t, 0, 0.02);
}

// Snare: noise band-passed at 1.5 kHz with a short tonal "thwack" body
// triangle at 200→100 Hz layered underneath.
function playSnare(gain) {
  if (!audio.ctx) return;
  if (STATE.settings.musicVol <= 0) return;
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
  ng.gain.linearRampToValueAtTime(gain * audio.duck * STATE.settings.musicVol, t + 0.002);
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
  og.gain.linearRampToValueAtTime(gain * 0.45 * audio.duck * STATE.settings.musicVol, t + 0.002);
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
  if (STATE.settings.musicVol <= 0) return;
  const t = audio.ctx.currentTime;
  const src = audio.ctx.createBufferSource();
  src.buffer = audio.noiseBuf;
  const hp = audio.ctx.createBiquadFilter();
  hp.type = "highpass";
  hp.frequency.value = 7000;
  const g = audio.ctx.createGain();
  g.gain.setValueAtTime(0, t);
  g.gain.linearRampToValueAtTime(gain * audio.duck * STATE.settings.musicVol, t + 0.001);
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
  const sfxPeak = (gain || 0.1) * STATE.settings.sfxVol;
  if (sfxPeak <= 0) { osc.start(t); osc.stop(t); return; } // muted — skip
  g.gain.setValueAtTime(0, t);
  g.gain.linearRampToValueAtTime(sfxPeak, t + 0.005);
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

  // Load persisted settings before any music starts (3.3).
  loadSettings();
  probeSave(); // does a CONTINUE autosave exist? (6.1)

  generateMap(123);

  canvas.addEventListener("mousemove", onMouseMove);
  canvas.addEventListener("mouseleave", () => { STATE.mouse = null; });
  canvas.addEventListener("click", onClick);
  canvas.addEventListener("wheel", onWheel);  // 6.2 log scrollback
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

// =========================================================================
// 17. Status effects (v2 1.1)
// =========================================================================

const STATUS_META = {
  burn:         { color: "#e07050", label: "burning" },
  slow:         { color: "#5aa8d8", label: "slowed" },
  regen:        { color: "#7ac075", label: "regenerating" },
  bulwark:      { color: "#f0c674", label: "bulwark +2 DEF" },
  ward:         { color: "#b078c8", label: "warded" },
  mark:         { color: "#ff8888", label: "marked +20% dmg taken" },
  skitterBoost: { color: "#c8c8d8", label: "skittering" },
};

function addStatus(unit, key, turns) {
  if (!unit.status) unit.status = {};
  unit.status[key] = Math.max(unit.status[key] || 0, turns);
}

function hasStatus(unit, key) {
  return !!(unit.status && unit.status[key] > 0);
}

// Movement allowance after statuses and weather (1.5).
function effectiveMove(unit) {
  let m = unit.move;
  if (hasStatus(unit, "slow")) m = Math.max(1, m - 2);
  if (hasStatus(unit, "skitterBoost")) m += 2;
  if (weatherNow().flyBonus && unit.flying) m += weatherNow().flyBonus;
  return m;
}

// Tick all statuses for `owner`'s units at the start of their turn.
// Called from endTurn right after the player switch.
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
    if (STATE.stats) STATE.stats.summoned[0]++;
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

// =========================================================================
// 18. Abilities (v2 1.2-1.4)
// =========================================================================

// One active ability per monster line — an ALTERNATIVE to attacking
// (a turn = move + one of attack/ability/capture/wait). Cooldown lives on
// the instance as u.cd (turns until ready), ticked in endTurn.
// target kinds: "none" (resolves instantly), "enemy" (attack-flavored,
// runs through beginBattle with a status payload — 1.3), "tile" (Blink, 1.3).
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

// Resolve an instant (target:"none") ability at the unit's current hex.
// Returns true if it fired. Sets nothing on the unit — caller owns
// cooldown/acted/menu state.
function resolveInstantAbility(unit, ab) {
  if (ab.key === "healPulse") {
    for (const n of hexNeighbors(unit.q, unit.r)) {
      const a = unitAt(n.q, n.r);
      if (a && a.owner === unit.owner && a.hp < a.maxHp) {
        const h = Math.min(5, a.maxHp - a.hp);
        a.hp += h;
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
    if (ab.key === "skitter") addStatus(unit, "skitterBoost", 1);
    unit.secondMove = true; // move-only leg; cleared when its menu opens or at endTurn
    pushLog(unit.name + " surges with speed.", PAL.green);
    beep(880, 0.08, "triangle", 0.18);
    return true;
  }
  if (ab.key === "bulwark" || ab.key === "ward") {
    // 1 tick: covers exactly the enemy round, expiring at the owner's next
    // turn start (decrement-then-delete in tickStatuses). 2 would shield
    // through two enemy rounds — Phase-1 review tuning fix.
    addStatus(unit, ab.key, 1);
    for (const n of hexNeighbors(unit.q, unit.r)) {
      const a = unitAt(n.q, n.r);
      if (a && a.owner === unit.owner) addStatus(a, ab.key, 1);
    }
    pushLog(unit.name + " raises a " + ab.name.toLowerCase() + ".", PAL.purple);
    beep(560, 0.1, "triangle", 0.2);
    return true;
  }
  return false;
}

// Score firing the unit's instant ability from its CURRENT hex (v2 1.4).
// Returns {score} or null. Tuned against aiActUnit's attack scores
// (confirmed kill ≈ 30+, decent attack ≈ 8-15). Evaluated where the unit
// stands — a documented simplification; repositioning-then-casting is not
// searched.
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
    if (hasStatus(u, ab.key)) return null; // never refresh an active aura
    let allies = 0;
    for (const n of hexNeighbors(u.q, u.r)) {
      const a = unitAt(n.q, n.r);
      if (a && a.owner === u.owner) allies++;
    }
    s = allies * 5 + 4;
    if (s < 12) s = 0; // needs at least a small cluster to be worth a turn
  }
  // skitter/galeRush: movement value — out of scope for AI v1 (documented)
  return s > 0 ? { score: s } : null;
}

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
  const def = STATE.mapDef || MAPS[STATE.mapIndex] || MAPS[0];
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
