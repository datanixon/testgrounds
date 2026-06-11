class_name Abilities
extends RefCounted
## Port of game.js ABILITIES + abilityFor (sec. 18). One active ability per monster
## line — an alternative to attacking. Cooldown lives on unit["cd"] (ticked in
## end_turn). target kinds: "none" (instant, resolve at current hex), "enemy"
## (attack-flavored, runs through Combat.resolve_attack with a status payload),
## "tile" (Blink teleport). JS `statusTurns` -> snake_case `status_turns`.

const UnitTypes = preload("res://data/unit_types.gd")

const ABILITIES := {
	"healPulse":    {"name": "Heal Pulse",    "cd": 3, "target": "none",  "desc": "+5 HP to adjacent allies"},
	"quake":        {"name": "Quake",         "cd": 4, "target": "none",  "desc": "4 dmg to all adjacent enemies, no counter"},
	"skitter":      {"name": "Skitter",       "cd": 2, "target": "none",  "desc": "take a second move-only action (+2 MOV)"},
	"frostBite":    {"name": "Frost Bite",    "cd": 3, "target": "enemy", "desc": "attack; slows the target", "status": "slow", "status_turns": 2},
	"ignite":       {"name": "Ignite",        "cd": 3, "target": "enemy", "desc": "attack; burns the target", "status": "burn", "status_turns": 2},
	"cinderBreath": {"name": "Cinder Breath", "cd": 4, "target": "enemy", "desc": "attack; burns the target", "status": "burn", "status_turns": 2},
	"undertow":     {"name": "Undertow",      "cd": 3, "target": "enemy", "desc": "attack; slows the target", "status": "slow", "status_turns": 2},
	"diveMark":     {"name": "Dive Mark",     "cd": 4, "target": "enemy", "desc": "attack; marks the target", "status": "mark", "status_turns": 2},
	"bulwark":      {"name": "Bulwark",       "cd": 3, "target": "none",  "desc": "+2 DEF to self & adjacent allies for a turn"},
	"ward":         {"name": "Ward",          "cd": 4, "target": "none",  "desc": "shield self & adjacent allies from the next hit"},
	"blink":        {"name": "Blink",         "cd": 3, "target": "tile",  "desc": "teleport up to 4 hexes"},
	"galeRush":     {"name": "Gale Rush",     "cd": 4, "target": "none",  "desc": "take a second move-only action"},
}

## abilityFor — the ability record for `unit`'s type, with `key` added. Evolved forms
## get cd reduced by 1 (min 1). Returns null if the type has no ability (e.g. master).
static func ability_for(unit: Dictionary) -> Variant:
	var t: Dictionary = UnitTypes.UNIT_TYPES.get(unit["type_key"], {})
	if not t.has("ability"):
		return null
	var base: Dictionary = ABILITIES.get(t["ability"], {})
	if base.is_empty():
		return null
	var out := base.duplicate()
	out["key"] = t["ability"]
	out["cd"] = maxi(1, base["cd"] - (1 if t.get("evolved", false) else 0))
	return out
