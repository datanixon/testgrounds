class_name Deploy
extends RefCounted
## Phase 5.2 campaign deploy. Pure-ish helpers (harness-tested) for the pre-mission
## veteran picker: reconstruct a live unit from a roster entry, value the deployed
## army, scale AI opening strength, resolve the per-mission slot cap, and place the
## chosen veterans. Takes `state` as a param (no GameState preload cycle — mirrors
## core/ai.gd) and reuses the global AI class + RosterStore's carry-field contract.

const RosterStore = preload("res://core/roster_store.gd")
const UnitTypes = preload("res://data/unit_types.gd")

const AI_SCALE_DIVISOR := 10   # roster value per +1 AI MP
const AI_SCALE_CAP := 12       # max extra AI MP from scaling
const DEFAULT_SLOTS := 3       # deploy cap when a scenario omits deploy_slots

static func unit_from_entry(entry: Dictionary, id: int, owner: int, q: int, r: int) -> Dictionary:
	var u := {
		"id": id, "owner": owner, "q": q, "r": r,
		"is_master": false, "acted": false, "cd": 0, "second_move": false,
		"roster_id": int(entry["roster_id"]),
	}
	for k in RosterStore._CARRY_STR:
		u[k] = String(entry.get(k, ""))
	for k in RosterStore._CARRY_INT:
		u[k] = int(entry.get(k, 0))
	for k in RosterStore._CARRY_BOOL:
		u[k] = bool(entry.get(k, false))
	u["hp"] = u["max_hp"]
	return u

static func roster_value(entries: Array) -> int:
	var total := 0
	for e in entries:
		total += int(UnitTypes.UNIT_TYPES.get(e.get("type_key", ""), {}).get("cost", 0))
	return total

static func ai_scale_mp(value: int) -> int:
	return clampi(value / AI_SCALE_DIVISOR, 0, AI_SCALE_CAP)

static func slots_for(scenario: Dictionary) -> int:
	return int(scenario.get("deploy_slots", DEFAULT_SLOTS))

# Place the chosen veterans on the board near the player master, record their
# roster_ids on the state, and bump the AI master's MP by the scaled army value.
static func commit(state, entries: Array) -> void:
	var m0 = state.master_of(0)
	for e in entries:
		if m0 == null:
			break
		var slot = AI.find_summon_slot(state, m0)
		if slot == null:
			break   # board full near the master; place what fits
		var u := unit_from_entry(e, state._new_id(), 0, slot.x, slot.y)
		state.units.append(u)
		state.deployed_roster_ids.append(int(e["roster_id"]))
	var m1 = state.master_of(1)
	if m1 != null:
		var extra := ai_scale_mp(roster_value(entries))
		m1["mp"] = clampi(m1["mp"] + extra, mini(4, m1["max_mp"]), m1["max_mp"])
