class_name UiQueries
extends RefCounted
## Pure, presentation-agnostic UI queries — the action-availability + summon-list logic
## lifted out of the JS openPostMoveMenu (game.js 4559+). The HUD Control nodes render
## exactly what these return; they hold no game logic. All functions are pure reads:
## they never mutate state or the unit/cell dicts passed in. `has_undo` is presentation
## state (a live pre-move snapshot) passed in as a bool so this stays pure + testable.

const Pathfinding = preload("res://core/pathfinding.gd")
const Abilities = preload("res://data/abilities.gd")
const Terrain = preload("res://data/terrain.gd")
const UnitTypes = preload("res://data/unit_types.gd")
const Elements = preload("res://data/elements.gd")

## can_capture — true if `unit` standing on `cell` could flip it: a capturable terrain
## (the `capturable` flag — towers only) not already owned by this unit.
static func can_capture(state, unit, cell) -> bool:
	if cell == null:
		return false
	if not Terrain.TERRAIN.get(cell["terrain"], {}).get("capturable", false):
		return false
	return cell.get("owner", -1) != unit["owner"]

## available_actions — the ordered post-move action list for `unit` at its current tile.
## Each item is {kind, label, disabled}. Mirrors openPostMoveMenu: second-move leg yields
## only Capture (if applicable) + Wait; otherwise Attack (with targets) / Capture / Summon
## (master, mp>=6) / Ability (disabled on cd, label carries the count) / Undo (if has_undo)
## / Wait. PURE.
static func available_actions(state, unit, has_undo := false) -> Array:
	var actions: Array = []
	var cell: Variant = state.cell_at(unit["q"], unit["r"])
	if unit.get("second_move", false):
		if can_capture(state, unit, cell):
			actions.append({"kind": "capture", "label": "Capture", "disabled": false})
		actions.append({"kind": "wait", "label": "Wait", "disabled": false})
		return actions
	var targets := Pathfinding.compute_attack_targets(state, unit, unit["q"], unit["r"])
	if not targets.is_empty():
		actions.append({"kind": "attack", "label": "Attack", "disabled": false})
	if can_capture(state, unit, cell):
		actions.append({"kind": "capture", "label": "Capture", "disabled": false})
	if unit["is_master"] and unit["mp"] >= 6:
		actions.append({"kind": "summon", "label": "Summon", "disabled": false})
	var ab: Variant = Abilities.ability_for(unit)
	if ab != null:
		var label: String = ab["name"] if unit["cd"] <= 0 else "%s (%d)" % [ab["name"], unit["cd"]]
		actions.append({"kind": "ability", "label": label, "disabled": unit["cd"] > 0})
	if has_undo:
		actions.append({"kind": "undo", "label": "Undo", "disabled": false})
	actions.append({"kind": "wait", "label": "Wait", "disabled": false})
	return actions

## summon_options — the summon picker list for `master`: every SUMMON_LIST type with a
## "Name  ELT  NNMP" label, its cost, and disabled when the master can't afford it. PURE.
static func summon_options(state, master) -> Array:
	var opts: Array = []
	for k in UnitTypes.SUMMON_LIST:
		var t: Dictionary = UnitTypes.UNIT_TYPES[k]
		var el: String = Elements.ELEMENT[t["element"]]["short"]
		var cost: int = t["cost"]
		opts.append({
			"key": k,
			"label": "%s  %s  %dMP" % [t["name"], el, cost],
			"cost": cost,
			"disabled": cost > master["mp"],
		})
	return opts
