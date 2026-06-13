class_name UnitTypes
extends RefCounted
## Faithful port of game.js UNIT_TYPES / SUMMON_LIST / MASTER_TEMPLATE (sec. 4).
## Balance-locked numbers — verified against the reference. `evolves_to` /
## `evolved` / `ability` are carried as DATA now; the leveling, evolution, and
## ability LOGIC land in M4/M5 alongside the systems that read them.

const UNIT_TYPES := {
	# Base monsters (original 8)
	"cinderling":  {"name": "Cinderling",  "element": "pyro",   "max_hp": 12, "move": 4, "range": 1, "power": 5,  "def": 1, "cost": 6,  "flying": false, "sprite": "imp",      "attack": "melee",  "evolves_to": "infernite",    "ability": "ignite"},
	"pyrowyrm":    {"name": "Pyrowyrm",    "element": "pyro",   "max_hp": 18, "move": 3, "range": 2, "power": 7,  "def": 2, "cost": 12, "flying": false, "sprite": "wyrm",     "attack": "breath", "evolves_to": "emberdrake",   "ability": "cinderBreath"},
	"tidekin":     {"name": "Tidekin",     "element": "hydro",  "max_hp": 14, "move": 4, "range": 1, "power": 5,  "def": 2, "cost": 7,  "flying": false, "sprite": "merfolk",  "attack": "melee",  "evolves_to": "tidelord",     "ability": "healPulse"},
	"mistleviath": {"name": "Mistlevy",    "element": "hydro",  "max_hp": 20, "move": 3, "range": 2, "power": 6,  "def": 3, "cost": 14, "flying": false, "sprite": "serpent",  "attack": "spray",  "evolves_to": "leviathan",    "ability": "undertow"},
	"stoneward":   {"name": "Stoneward",   "element": "terra",  "max_hp": 22, "move": 2, "range": 1, "power": 5,  "def": 4, "cost": 8,  "flying": false, "sprite": "golem",    "attack": "melee",  "evolves_to": "colossus",     "ability": "bulwark"},
	"geomaul":     {"name": "Geomaul",     "element": "terra",  "max_hp": 26, "move": 2, "range": 1, "power": 9,  "def": 4, "cost": 16, "flying": false, "sprite": "ogre",     "attack": "melee",  "evolves_to": "earthbreaker", "ability": "quake"},
	"galewisp":    {"name": "Galewisp",    "element": "zephyr", "max_hp": 10, "move": 5, "range": 2, "power": 4,  "def": 1, "cost": 7,  "flying": true,  "sprite": "wisp",     "attack": "spark",  "evolves_to": "stormwisp",    "ability": "galeRush"},
	"skyharrow":   {"name": "Skyharrow",   "element": "zephyr", "max_hp": 16, "move": 4, "range": 2, "power": 7,  "def": 2, "cost": 13, "flying": true,  "sprite": "raptor",   "attack": "dive",   "evolves_to": "skytyrant",    "ability": "diveMark"},
	# Evolved forms (terminal tier; not directly summonable)
	"infernite":    {"name": "Infernite",    "element": "pyro",   "max_hp": 22, "move": 4, "range": 1, "power": 9,  "def": 3, "cost": 18, "flying": false, "sprite": "infernite",    "attack": "melee",  "evolved": true, "ability": "ignite"},
	"emberdrake":   {"name": "Emberdrake",   "element": "pyro",   "max_hp": 30, "move": 3, "range": 2, "power": 11, "def": 4, "cost": 26, "flying": false, "sprite": "emberdrake",   "attack": "breath", "evolved": true, "ability": "cinderBreath"},
	"tidelord":     {"name": "Tidelord",     "element": "hydro",  "max_hp": 24, "move": 4, "range": 1, "power": 9,  "def": 4, "cost": 18, "flying": false, "sprite": "tidelord",     "attack": "melee",  "evolved": true, "ability": "healPulse"},
	"leviathan":    {"name": "Leviathan",    "element": "hydro",  "max_hp": 32, "move": 3, "range": 2, "power": 10, "def": 5, "cost": 28, "flying": false, "sprite": "leviathan",    "attack": "spray",  "evolved": true, "ability": "undertow"},
	"colossus":     {"name": "Colossus",     "element": "terra",  "max_hp": 36, "move": 2, "range": 1, "power": 9,  "def": 6, "cost": 20, "flying": false, "sprite": "colossus",     "attack": "melee",  "evolved": true, "ability": "bulwark"},
	"earthbreaker": {"name": "Earthbreaker", "element": "terra",  "max_hp": 42, "move": 2, "range": 1, "power": 14, "def": 6, "cost": 30, "flying": false, "sprite": "earthbreaker", "attack": "melee",  "evolved": true, "ability": "quake"},
	"stormwisp":    {"name": "Stormwisp",    "element": "zephyr", "max_hp": 18, "move": 5, "range": 2, "power": 8,  "def": 2, "cost": 18, "flying": true,  "sprite": "stormwisp",    "attack": "spark",  "evolved": true, "ability": "galeRush"},
	"skytyrant":    {"name": "Skytyrant",    "element": "zephyr", "max_hp": 26, "move": 4, "range": 2, "power": 11, "def": 3, "cost": 24, "flying": true,  "sprite": "skytyrant",    "attack": "dive",   "evolved": true, "ability": "diveMark"},
	# New base monsters (arcane coverage + roster depth)
	"hexwisp":   {"name": "Hexwisp",   "element": "arcane", "max_hp": 11, "move": 5, "range": 2, "power": 5,  "def": 1, "cost": 8,  "flying": true,  "sprite": "hexwisp",   "attack": "bolt",  "evolves_to": "hexlord",     "ability": "blink"},
	"runeward":  {"name": "Runeward",  "element": "arcane", "max_hp": 24, "move": 2, "range": 1, "power": 7,  "def": 5, "cost": 15, "flying": false, "sprite": "runeward",  "attack": "melee", "evolves_to": "sigilwarden", "ability": "ward"},
	"frostmaw":  {"name": "Frostmaw",  "element": "hydro",  "max_hp": 28, "move": 3, "range": 1, "power": 10, "def": 3, "cost": 18, "flying": false, "sprite": "frostmaw",  "attack": "melee", "evolves_to": "glaciamaw",   "ability": "frostBite"},
	"duneskink": {"name": "Duneskink", "element": "terra",  "max_hp": 13, "move": 5, "range": 1, "power": 6,  "def": 1, "cost": 6,  "flying": false, "sprite": "duneskink", "attack": "melee", "evolves_to": "dunestalker", "ability": "skitter"},
	# Evolved forms for the four newest bases (P4.1; sprites art-pending)
	"hexlord":     {"name": "Hexlord",     "element": "arcane", "max_hp": 19, "move": 5, "range": 2, "power": 9,  "def": 2, "cost": 20, "flying": true,  "sprite": "hexlord",     "attack": "bolt",  "evolved": true, "ability": "blink"},
	"sigilwarden": {"name": "Sigilwarden", "element": "arcane", "max_hp": 38, "move": 2, "range": 1, "power": 10, "def": 7, "cost": 30, "flying": false, "sprite": "sigilwarden", "attack": "melee", "evolved": true, "ability": "ward"},
	"glaciamaw":   {"name": "Glaciamaw",   "element": "hydro",  "max_hp": 40, "move": 3, "range": 1, "power": 14, "def": 5, "cost": 34, "flying": false, "sprite": "glaciamaw",   "attack": "melee", "evolved": true, "ability": "frostBite"},
	"dunestalker": {"name": "Dunestalker", "element": "terra",  "max_hp": 23, "move": 5, "range": 1, "power": 10, "def": 3, "cost": 16, "flying": false, "sprite": "dunestalker", "attack": "melee", "evolved": true, "ability": "skitter"},
	# Bosses (P4.3; non-summonable, pre-placed only; reuse existing abilities; sprites art-pending)
	"pyre_colossus": {"name": "Pyre Colossus", "element": "pyro",   "max_hp": 52, "move": 2, "range": 1, "power": 16, "def": 6, "cost": 40, "flying": false, "sprite": "pyre_colossus", "attack": "melee", "ability": "quake",    "boss": true},
	"storm_tyrant":  {"name": "Storm Tyrant",  "element": "zephyr", "max_hp": 40, "move": 4, "range": 2, "power": 14, "def": 4, "cost": 38, "flying": true,  "sprite": "storm_tyrant",  "attack": "dive",  "ability": "diveMark", "boss": true},
}

const SUMMON_LIST := ["cinderling", "tidekin", "stoneward", "galewisp", "duneskink", "pyrowyrm", "hexwisp", "mistleviath", "runeward", "geomaul", "frostmaw", "skyharrow"]

const MASTER_TEMPLATE := {
	"name": "Archon", "element": "arcane", "max_hp": 40, "max_mp": 30, "move": 3, "range": 1,
	"power": 7, "def": 3, "mp_regen": 4, "flying": false, "sprite": "archon", "attack": "bolt",
}
