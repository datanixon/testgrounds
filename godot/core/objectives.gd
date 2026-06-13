class_name Objectives
extends RefCounted
## ROADMAP2 Phase 4.2 — mission objectives. Pure: evaluates the active objective on a
## GameState into a winner verdict, beside the always-on archon-kill. No node deps; reads
## the `state` param dynamically (no preload of game_state -> no cycle). The objective
## belongs to player 0. Shapes (JSON-safe): {"kind":"survive","turns":int},
## {"kind":"seize","q":int,"r":int}, {"kind":"protect","unit_id":int}, {"kind":"rout"}.

## evaluate — winner the objective implies: 0 (player 0 wins), 1 (player 0 loses),
## or -1 (no verdict — defer to the archon-kill check).
static func evaluate(state) -> int:
	var obj: Dictionary = state.objective
	if obj.is_empty():
		return -1
	match obj.get("kind", ""):
		"survive":
			var start := int(state.objective_progress.get("start_turn", state.turn))
			if state.turn - start >= int(obj["turns"]):
				return 0
		"seize":
			var u = state.unit_at(int(obj["q"]), int(obj["r"]))
			if u != null and u["owner"] == 0:
				return 0
		"protect":
			if state.unit_by_id(int(obj["unit_id"])) == null:
				return 1
		"rout":
			if state.turn >= 2 and state.enemy_non_masters(0).is_empty():
				return 0
	return -1

## label — topbar string for the active objective (with survive/rout progress), or "".
static func label(state) -> String:
	var obj: Dictionary = state.objective
	if obj.is_empty():
		return ""
	match obj.get("kind", ""):
		"survive":
			var start := int(state.objective_progress.get("start_turn", state.turn))
			var done: int = maxi(0, state.turn - start)
			return "Survive: %d/%d" % [done, int(obj["turns"])]
		"seize":
			return "Seize the marked hex"
		"protect":
			return "Protect your ally"
		"rout":
			return "Rout the enemy (%d left)" % state.enemy_non_masters(0).size()
	return ""
