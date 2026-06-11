class_name Units
extends RefCounted
## Pure unit-record factories — port of game.js makeUnit / makeMaster (sec. 4).
## A unit is a plain Dictionary so the logic core stays node-free and records
## serialize directly for save/load. `id` is supplied by the caller (GameState
## owns the counter) so the factories stay pure and testable in isolation.

const UnitTypes = preload("res://data/unit_types.gd")

static func make_unit(id: int, type_key: String, owner: int, q: int, r: int) -> Dictionary:
	var t: Dictionary = UnitTypes.UNIT_TYPES[type_key]
	return {
		"id": id, "type_key": type_key, "name": t["name"], "element": t["element"],
		"owner": owner, "q": q, "r": r,
		"hp": t["max_hp"], "max_hp": t["max_hp"],
		"move": t["move"], "range": t["range"], "power": t["power"], "def": t["def"],
		"flying": t["flying"], "sprite": t["sprite"], "attack": t["attack"],
		"level": 1, "xp": 0,
		"acted": false, "is_master": false,
		"cd": 0, "second_move": false,
	}

static func make_master(id: int, owner: int, q: int, r: int) -> Dictionary:
	var t := UnitTypes.MASTER_TEMPLATE
	return {
		"id": id, "type_key": "master", "name": t["name"], "element": t["element"],
		"owner": owner, "q": q, "r": r,
		"hp": t["max_hp"], "max_hp": t["max_hp"],
		"mp": 14, "max_mp": t["max_mp"],
		"move": t["move"], "range": t["range"], "power": t["power"], "def": t["def"],
		"mp_regen": t["mp_regen"],
		"flying": false, "sprite": "archon", "attack": "bolt",
		"level": 1, "xp": 0,
		"acted": false, "is_master": true,
		"cd": 0, "second_move": false,
	}

# ---- XP, leveling, evolution (port of game.js sec. 4 cont.) ----
const MAX_LEVEL := 5
const KILL_XP_BONUS := 10
const EVOLVE_LEVEL := 4

## XP required to advance FROM `level` (12, 20, 28, 36); effectively infinite at max.
static func xp_to_next(level: int) -> int:
	return 1_000_000_000 if level >= MAX_LEVEL else 12 + (level - 1) * 8

## One level-up: bump maxHp/power/def and full-restore HP (classic MoM behaviour).
static func apply_level_growth(unit: Dictionary) -> void:
	unit["max_hp"] += 6 if unit["is_master"] else 4
	unit["power"] += 1
	unit["def"] += 1
	unit["hp"] = unit["max_hp"]

## Award XP, resolving multi-level-ups. Returns levels gained this call.
static func gain_xp(unit: Dictionary, amount: int) -> int:
	if amount <= 0 or unit["level"] >= MAX_LEVEL:
		return 0
	unit["xp"] += amount
	var gained := 0
	while unit["level"] < MAX_LEVEL and unit["xp"] >= xp_to_next(unit["level"]):
		unit["xp"] -= xp_to_next(unit["level"])
		unit["level"] += 1
		apply_level_growth(unit)
		gained += 1
	if unit["level"] >= MAX_LEVEL:
		unit["xp"] = 0
	return gained

## Evolve a unit into its terminal form, absorbing accumulated level growth.
## NOTE: `ability` is NOT cached on the unit record — read it via
## UnitTypes.UNIT_TYPES[unit["type_key"]]["ability"], which now points at the evo.
static func evolve_unit(unit: Dictionary) -> bool:
	var base: Dictionary = UnitTypes.UNIT_TYPES.get(unit["type_key"], {})
	if base.is_empty() or not base.has("evolves_to"):
		return false
	var evo: Dictionary = UnitTypes.UNIT_TYPES.get(base["evolves_to"], {})
	if evo.is_empty():
		return false
	var lvl_bonus: int = unit["level"] - 1
	unit["type_key"] = base["evolves_to"]
	unit["name"] = evo["name"]
	unit["element"] = evo["element"]
	unit["move"] = evo["move"]
	unit["range"] = evo["range"]
	unit["flying"] = evo["flying"]
	unit["sprite"] = evo["sprite"]
	unit["attack"] = evo["attack"]
	unit["max_hp"] = evo["max_hp"] + lvl_bonus * 4
	unit["power"] = evo["power"] + lvl_bonus
	unit["def"] = evo["def"] + lvl_bonus
	unit["hp"] = unit["max_hp"]
	unit["evolved"] = true
	return true

## Try to evolve `unit` standing on `cell`: level 4+, not master, not already
## evolved, on an OWNED tower/castle, and has an evolution path. Returns success.
static func try_evolve(unit: Dictionary, cell: Variant) -> bool:
	if unit["is_master"] or unit.get("evolved", false):
		return false
	if unit["level"] < EVOLVE_LEVEL:
		return false
	if cell == null or cell["owner"] != unit["owner"]:
		return false
	if cell["terrain"] != "tower" and cell["terrain"] != "castle":
		return false
	if not UnitTypes.UNIT_TYPES.get(unit["type_key"], {}).has("evolves_to"):
		return false
	return evolve_unit(unit)
