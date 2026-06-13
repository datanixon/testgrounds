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
