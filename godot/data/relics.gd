class_name Relics
extends RefCounted
## ROADMAP2 Phase 2 — relic table + pure stat helpers. Effects flow through the
## existing stat functions (compute_damage/effective_move/range/max_hp/regen), so
## forecast + AI inherit them. 6 passive + 3 consumable. (Veilstone -> Phase 3.)

const RELICS := {
	"atk_charm":   {"name": "Atk Charm",     "kind": "passive",    "glyph": "A", "color": Color("#e0662e"), "atk": 2},
	"vital":       {"name": "Vital Idol",    "kind": "passive",    "glyph": "V", "color": Color("#7ac075"), "max_hp": 4},
	"swift":       {"name": "Swift Boots",   "kind": "passive",    "glyph": "S", "color": Color("#7fd0c0"), "move": 1},
	"farsight":    {"name": "Farsight Lens", "kind": "passive",    "glyph": "F", "color": Color("#a07acd"), "range": 1},
	"regenring":   {"name": "Regen Ring",    "kind": "passive",    "glyph": "R", "color": Color("#70d070"), "regen": 2},
	"thorncharm":  {"name": "Thorn Charm",   "kind": "passive",    "glyph": "T", "color": Color("#cccccc"), "counter": 2},
	"phoenix":     {"name": "Phoenix Charm", "kind": "consumable", "glyph": "P", "color": Color("#ff7f50"), "revive": true},
	"warhorn":     {"name": "Warhorn",       "kind": "consumable", "glyph": "W", "color": Color("#f0c674"), "atk_mult": 1.5},
	"ley_crystal": {"name": "Ley Crystal",   "kind": "consumable", "glyph": "L", "color": Color("#5aa8d8"), "master_only": true, "mp": 6},
}

## Ids eligible to spawn on the map (all 9; map-gen rolls from this).
const POOL := ["atk_charm", "vital", "swift", "farsight", "regenring", "thorncharm", "phoenix", "warhorn", "ley_crystal"]

static func is_passive(id: String) -> bool:
	return RELICS.has(id) and RELICS[id]["kind"] == "passive"

static func is_consumable(id: String) -> bool:
	return RELICS.has(id) and RELICS[id]["kind"] == "consumable"

## bonus — numeric effect value for a relic id + key, 0 if absent.
static func bonus(id: String, key: String) -> Variant:
	if not RELICS.has(id):
		return 0
	return RELICS[id].get(key, 0)

## unit_bonus — bonus for the relic a unit currently holds.
static func unit_bonus(unit: Dictionary, key: String) -> Variant:
	return bonus(unit.get("relic", ""), key)

static func has_relic(unit: Dictionary, id: String) -> bool:
	return unit.get("relic", "") == id

## max_hp — effective max HP including a vital relic. Single source for HP clamps/bars.
static func max_hp(unit: Dictionary) -> int:
	return int(unit["max_hp"]) + int(unit_bonus(unit, "max_hp"))

## effective_range — attack range including farsight, capped at 2 total.
static func effective_range(unit: Dictionary) -> int:
	return mini(2, int(unit["range"]) + int(unit_bonus(unit, "range")))
