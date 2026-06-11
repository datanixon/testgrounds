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
