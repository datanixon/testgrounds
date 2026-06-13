class_name RosterStore
extends RefCounted
## Phase 5.1 persistent campaign roster. Pure data ops (harness-tested) + thin
## user:// JSON I/O (the campaign.v2 slot). Veterans carry level/xp/evolution/
## relic between missions; deaths are permanent. Modeled on SaveGame /
## SettingsStore. Live wiring (deploy, win-reconcile, AI scaling) = Phase 5.2.

const Units = preload("res://core/units.gd")
const UnitTypes = preload("res://data/unit_types.gd")

const SLOT_PATH := "user://wraithspire_campaign.json"

# Non-transient unit fields stored verbatim in a roster entry (full snapshot).
const _CARRY_STR := ["type_key", "name", "element", "sprite", "attack", "relic"]
const _CARRY_INT := ["level", "xp", "max_hp", "power", "def", "move", "range"]

# ---- pure roster editors ----
# `roster_id` is a permanent monotonic UID assigned from `next_roster_id`; it is
# never reused, so `remove_entry`/`clear` intentionally leave `next_roster_id`
# untouched (a removed veteran's id is never handed out again).

static func new_roster() -> Dictionary:
	return {"v": 2, "roster": [], "next_roster_id": 1}

static func entry_from_unit(unit: Dictionary, roster_id: int) -> Dictionary:
	var e := {"roster_id": roster_id}
	for k in _CARRY_STR:
		e[k] = String(unit.get(k, ""))
	for k in _CARRY_INT:
		e[k] = int(unit.get(k, 0))
	e["flying"] = bool(unit.get("flying", false))
	return e

static func add_entry(blob: Dictionary, unit: Dictionary) -> int:
	var rid: int = int(blob["next_roster_id"])
	(blob["roster"] as Array).append(entry_from_unit(unit, rid))
	blob["next_roster_id"] = rid + 1
	return rid

static func remove_entry(blob: Dictionary, roster_id: int) -> bool:
	var arr: Array = blob["roster"]
	for i in arr.size():
		if int(arr[i]["roster_id"]) == roster_id:
			arr.remove_at(i)
			return true
	return false

static func clear(blob: Dictionary) -> void:
	blob["roster"] = []
