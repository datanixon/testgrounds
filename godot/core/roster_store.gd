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
const _CARRY_BOOL := ["flying", "evolved"]

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
	for k in _CARRY_BOOL:
		e[k] = bool(unit.get(k, false))
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

# ---- reconcile (called after a mission win, in Phase 5.2) ----

static func reconcile(blob: Dictionary, living_units: Array, deployed_ids: Array) -> Dictionary:
	var out: Dictionary = blob.duplicate(true)
	# Index living units that carry a roster_id (deployed veterans that survived).
	var living_by_rid := {}
	for u in living_units:
		if u.has("roster_id"):
			living_by_rid[int(u["roster_id"])] = u
	# Deployed veterans: update survivors, cull the dead (permadeath).
	for rid in deployed_ids:
		var r := int(rid)
		if living_by_rid.has(r):
			_update_entry(out, r, living_by_rid[r])
		else:
			remove_entry(out, r)
	# Fresh summons that survived (no roster_id) join the roster.
	for u in living_units:
		if not u.has("roster_id"):
			add_entry(out, u)
	return out

static func _update_entry(blob: Dictionary, roster_id: int, unit: Dictionary) -> void:
	var arr: Array = blob["roster"]
	for i in arr.size():
		if int(arr[i]["roster_id"]) == roster_id:
			arr[i] = entry_from_unit(unit, roster_id)
			return

# ---- migration: v1 campaign_progress -> starter roster ----

# One veteran per cleared act: [type_key, level]. Acts 1..4 (index 0..3).
# geomaul@4 and hexwisp@5 cross EVOLVE_LEVEL, so they migrate as their evolved
# forms (earthbreaker / hexlord) via Units.evolve_unit.
const GRANT := [
	["stoneward", 2],
	["tidekin", 3],
	["geomaul", 4],
	["hexwisp", 5],
]

static func migrate(progress: int) -> Dictionary:
	var blob := new_roster()
	var n := clampi(progress, 0, GRANT.size())
	for i in n:
		add_entry(blob, _build_veteran(GRANT[i][0], GRANT[i][1]))
	return blob

# Build a veteran through the game's own progression path so it is rule-
# consistent with a naturally leveled unit. apply_level_growth bumps stats but
# not level; evolve_unit reads unit["level"] and recomputes stats from the
# evolved base + (level-1) growth. The two paths are mutually exclusive.
static func _build_veteran(type_key: String, level: int) -> Dictionary:
	var u := Units.make_unit(0, type_key, 0, 0, 0)
	u["level"] = level
	u["xp"] = 0
	if level >= Units.EVOLVE_LEVEL and UnitTypes.UNIT_TYPES[type_key].has("evolves_to"):
		Units.evolve_unit(u)
	else:
		for _i in range(level - 1):
			Units.apply_level_growth(u)
	return u
