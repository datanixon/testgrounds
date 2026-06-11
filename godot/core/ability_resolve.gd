class_name AbilityResolve
extends RefCounted
## Instant + tile ability resolution — port of game.js resolveInstantAbility + the
## Blink teleport (sec. 18). Enemy-target abilities run through Combat.resolve_attack
## with a status payload (handled in combat.gd, not here). Pure logic on a GameState;
## cooldown/acted are set by the CALLER (matching the JS contract).

const Hex = preload("res://core/hex.gd")
const Status = preload("res://core/status.gd")
const Units = preload("res://core/units.gd")

## resolve_instant — fire a target:"none" ability at the unit's current hex. Returns
## true if it fired. Does NOT set cd/acted (caller owns those).
static func resolve_instant(state, unit: Dictionary, ab: Dictionary) -> bool:
	match ab["key"]:
		"healPulse":
			for n in Hex.neighbors(Vector2i(unit["q"], unit["r"])):
				var a: Variant = state.unit_at(n.x, n.y)
				if a != null and a["owner"] == unit["owner"] and a["hp"] < a["max_hp"]:
					a["hp"] += mini(5, a["max_hp"] - a["hp"])
			return true
		"quake":
			var total := 0
			for n in Hex.neighbors(Vector2i(unit["q"], unit["r"])):
				var e: Variant = state.unit_at(n.x, n.y)
				if e != null and e["owner"] != unit["owner"]:
					e["hp"] -= 4
					total += 4
					if e["hp"] <= 0:
						total += Units.KILL_XP_BONUS
			if total > 0:
				Units.gain_xp(unit, total)
			state.check_win_condition()
			return true
		"skitter", "galeRush":
			if ab["key"] == "skitter":
				Status.add_status(unit, "skitterBoost", 1)
			unit["second_move"] = true
			return true
		"bulwark", "ward":
			Status.add_status(unit, ab["key"], 1)
			for n in Hex.neighbors(Vector2i(unit["q"], unit["r"])):
				var a: Variant = state.unit_at(n.x, n.y)
				if a != null and a["owner"] == unit["owner"]:
					Status.add_status(a, ab["key"], 1)
			return true
	return false
