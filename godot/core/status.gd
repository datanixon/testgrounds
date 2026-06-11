class_name Status
extends RefCounted
## Status engine — port of game.js addStatus/hasStatus/tickStatuses (sec. 16).
## Statuses live on unit["status"] = {key: turns_left}; the dict is created lazily.
## Stateless: operates on the unit dict (or a GameState for the per-turn tick).

## addStatus — set `key` to max(existing, turns); never shortens an active status.
static func add_status(unit: Dictionary, key: String, turns: int) -> void:
	if not unit.has("status"):
		unit["status"] = {}
	unit["status"][key] = maxi(unit["status"].get(key, 0), turns)

## hasStatus — true if `key` is present with > 0 turns.
static func has_status(unit: Dictionary, key: String) -> bool:
	return unit.has("status") and unit["status"].get(key, 0) > 0

## tickStatuses — start-of-turn tick for `owner`'s living units: burn -3 (floored
## at 0, can kill), regen +2 (capped at max_hp), then decrement all and drop expired.
## Pure logic — no floats/logs (those are presentation, added at the HUD/battle layer).
static func tick_statuses(state, owner: int) -> void:
	for u in state.alive_units(owner):
		if not u.has("status"):
			continue
		if u["status"].get("burn", 0) > 0:
			u["hp"] = maxi(0, u["hp"] - 3)
		if u["status"].get("regen", 0) > 0 and u["hp"] > 0 and u["hp"] < u["max_hp"]:
			u["hp"] += mini(2, u["max_hp"] - u["hp"])
		for k in u["status"].keys():
			u["status"][k] -= 1
			if u["status"][k] <= 0:
				u["status"].erase(k)
	state.check_win_condition()
