class_name AbilityResolve
extends RefCounted
## Instant + tile ability resolution — port of game.js resolveInstantAbility + the
## Blink teleport (sec. 18). Enemy-target abilities run through Combat.resolve_attack
## with a status payload (handled in combat.gd, not here). Pure logic on a GameState;
## cooldown/acted are set by the CALLER (matching the JS contract).

const Hex = preload("res://core/hex.gd")
const Status = preload("res://core/status.gd")
const Units = preload("res://core/units.gd")
const Terrain = preload("res://data/terrain.gd")

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

## blink_targets — set of "q,r" within 4 hexes of `unit` that are empty and landable:
## not a `blocks` tile (water — excluded for everyone), and not a `flyers_only` tile
## (mountain) for a non-flyer. The unit's own tile is excluded (it's occupied).
static func blink_targets(state, unit: Dictionary) -> Dictionary:
	var out := {}
	var origin := Vector2i(unit["q"], unit["r"])
	for key in state.map["cells"]:
		var c: Dictionary = state.map["cells"][key]
		var p := Vector2i(c["q"], c["r"])
		if Hex.distance(origin, p) > 4:
			continue
		if state.unit_at(p.x, p.y) != null:
			continue
		var t: Dictionary = Terrain.TERRAIN[c["terrain"]]
		if t.get("blocks", false):
			continue
		if t.get("flyers_only", false) and not unit["flying"]:
			continue
		out[key] = true
	return out

## do_blink — teleport `unit` to (q,r). Caller validates it's a blink_targets entry.
static func do_blink(unit: Dictionary, q: int, r: int) -> void:
	unit["q"] = q
	unit["r"] = r
