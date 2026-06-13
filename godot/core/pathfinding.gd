class_name Pathfinding
extends RefCounted
## Pure movement/attack queries — port of game.js sec. 6 (computeReachable,
## reconstructPath, computeAttackTargets) + effectiveMove (sec. 16). Operates on a
## GameState; no globals, no nodes. The reachable search is the AI's hot path and
## the most likely future C#-swap candidate, so it stays clean and side-effect-free.

const Hex = preload("res://core/hex.gd")
const Terrain = preload("res://data/terrain.gd")
const Status = preload("res://core/status.gd")
const Weather = preload("res://core/weather.gd")
const Relics = preload("res://data/relics.gd")

## effectiveMove — move allowance after status + weather. Slow -2 (min 1), skitter +2,
## and the weather fly bonus for flyers. Needs `state` for the active weather.
static func effective_move(unit: Dictionary, state) -> int:
	var m: int = unit["move"]
	if Status.has_status(unit, "slow"):
		m = maxi(1, m - 2)
	if Status.has_status(unit, "skitterBoost"):
		m += 2
	var w: Dictionary = Weather.weather_now(state)
	if w.get("fly_bonus", 0) != 0 and unit["flying"]:
		m += w["fly_bonus"]
	m += int(Relics.unit_bonus(unit, "move"))
	return m

## moveCostFor — cost to ENTER `cell`, or INF if impassable for this unit. `cell`
## may be null (off-board). Flyers pay 1 everywhere and ignore the mountain/water
## bans; grounded units can't enter `blocks` terrain (water) or mountains.
static func move_cost_for(unit: Dictionary, cell: Variant) -> float:
	if cell == null:
		return INF
	var t: Dictionary = Terrain.TERRAIN[cell["terrain"]]
	if t.get("blocks", false) and not unit["flying"]:
		return INF
	if cell["terrain"] == "mountain" and not unit["flying"]:
		return INF
	if unit["flying"]:
		return 1.0
	return float(t["move_cost"])

## computeReachable — Dijkstra over move cost from the unit's tile. Returns
##   { "q,r": {cost:int, prev:String|null, q:int, r:int} }
## Enemy-occupied tiles block movement (never entered); the final pass drops any
## tile that ends on another unit (the start tile is kept, so the menu/anim have
## an anchor). Friendly units are passable but not valid destinations.
static func compute_reachable(state, unit: Dictionary) -> Dictionary:
	var out := {}
	var start := Hex.key(Vector2i(unit["q"], unit["r"]))
	out[start] = {"cost": 0.0, "prev": null, "q": unit["q"], "r": unit["r"]}
	var frontier: Array = [{"q": unit["q"], "r": unit["r"], "cost": 0}]
	var limit := effective_move(unit, state)
	while not frontier.is_empty():
		frontier.sort_custom(func(a, b): return a["cost"] < b["cost"])
		var cur: Dictionary = frontier.pop_front()
		for n in Hex.neighbors(Vector2i(cur["q"], cur["r"])):
			if not state.in_bounds(n.x, n.y):
				continue
			var cell: Variant = state.cell_at(n.x, n.y)
			var blocker: Variant = state.unit_at(n.x, n.y)
			if blocker != null and blocker["owner"] != unit["owner"]:
				continue
			var step := move_cost_for(unit, cell)
			if not is_finite(step):
				continue
			var new_cost: float = float(cur["cost"]) + step
			if new_cost > limit:
				continue
			var key := Hex.key(n)
			var existing: Variant = out.get(key)
			if existing == null or existing["cost"] > new_cost:
				out[key] = {"cost": new_cost, "prev": Hex.key(Vector2i(cur["q"], cur["r"])), "q": n.x, "r": n.y}
				frontier.append({"q": n.x, "r": n.y, "cost": new_cost})
	# Drop tiles that end on a unit (keep the start tile).
	for k in out.keys():
		var v: Dictionary = out[k]
		var u: Variant = state.unit_at(v["q"], v["r"])
		if u != null and not (v["q"] == unit["q"] and v["r"] == unit["r"]):
			out.erase(k)
	return out

## reconstructPath — walk prev links back from (q,r) to the start, start-first.
## Returns Array[Vector2i]. Guarded against cycles (4096 cap, as in the JS).
static func reconstruct_path(reach: Dictionary, q: int, r: int) -> Array:
	var path: Array = []
	var key: Variant = Hex.key(Vector2i(q, r))
	var guard := 0
	while key != null and guard < 4096:
		guard += 1
		var node: Variant = reach.get(key)
		if node == null:
			break
		path.append(Vector2i(node["q"], node["r"]))
		key = node["prev"]
	path.reverse()
	return path

## computeAttackTargets — set of "q,r" keys of enemies within `unit.range` of
## (from_q, from_r). Returned as a Dictionary used as a set (key -> true).
static func compute_attack_targets(state, unit: Dictionary, from_q: int, from_r: int) -> Dictionary:
	var targets := {}
	for u in state.units:
		if u["hp"] <= 0:
			continue
		if u["owner"] == unit["owner"]:
			continue
		var d := Hex.distance(Vector2i(from_q, from_r), Vector2i(u["q"], u["r"]))
		if d <= Relics.effective_range(unit) and d >= 1:
			targets[Hex.key(Vector2i(u["q"], u["r"]))] = true
	return targets
