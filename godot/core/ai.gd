class_name AI
extends RefCounted
## Enemy AI — threat map + scored decision tree + summon economy (port of game.js
## sec. 8). The designated C#-swap seam: every function reads a GameState plus the
## pure query/combat modules and returns intended actions; take_turn() is the thin
## runner that applies them. Scoring is side-effect-free (candidate tiles are scored
## via a duplicated probe unit, never by mutating the real unit).

const AiProfiles = preload("res://data/ai_profiles.gd")
const Hex = preload("res://core/hex.gd")
const Terrain = preload("res://data/terrain.gd")
const Pathfinding = preload("res://core/pathfinding.gd")
const Abilities = preload("res://data/abilities.gd")
const Status = preload("res://core/status.gd")

## weights — the active difficulty's weight profile (defaults to normal).
static func weights(state) -> Dictionary:
	return AiProfiles.AI_PROFILES.get(state.difficulty, AiProfiles.AI_PROFILES["normal"])

## build_threat_map — total potential enemy damage onto every tile: each enemy of the
## OTHER player expands its reachable tiles by its attack range; one enemy contributes
## its power at most once per tile, separate enemies stack. Returns { "q,r": int }.
static func build_threat_map(state, owner: int) -> Dictionary:
	var threat := {}
	for e in state.alive_units(1 - owner):
		var seen := {}
		var reach := Pathfinding.compute_reachable(state, e)
		for k in reach:
			var node: Dictionary = reach[k]
			for n1 in Hex.neighbors(Vector2i(node["q"], node["r"])):
				_threat_mark(threat, seen, n1, e["power"])
				if e["range"] >= 2:
					for n2 in Hex.neighbors(n1):
						_threat_mark(threat, seen, n2, e["power"])
	return threat

static func _threat_mark(threat: Dictionary, seen: Dictionary, p: Vector2i, power: int) -> void:
	var k := Hex.key(p)
	if seen.has(k):
		return
	seen[k] = true
	threat[k] = threat.get(k, 0) + power

static func threat_at(threat: Dictionary, q: int, r: int) -> int:
	return threat.get(Hex.key(Vector2i(q, r)), 0)

## find_summon_slot — first free, non-blocking, non-mountain neighbor of the master.
static func find_summon_slot(state, master: Dictionary) -> Variant:
	for n in Hex.neighbors(Vector2i(master["q"], master["r"])):
		if not state.in_bounds(n.x, n.y):
			continue
		var cell: Variant = state.cell_at(n.x, n.y)
		if cell == null:
			continue
		if Terrain.TERRAIN[cell["terrain"]].get("blocks", false):
			continue
		if cell["terrain"] == "mountain":
			continue
		if state.unit_at(n.x, n.y) != null:
			continue
		return n
	return null

## _retreat_node — best reachable tile for a wounded unit: near an owned heal tile
## (tower/castle), low threat, decent cover. Returns the reach node dict, or null.
static func _retreat_node(state, unit: Dictionary, reach: Dictionary, threat: Dictionary) -> Variant:
	var heals: Array[Vector2i] = []
	for k in state.map["cells"]:
		var c: Dictionary = state.map["cells"][k]
		if (c["terrain"] == "tower" or c["terrain"] == "castle") and c.get("owner", -1) == unit["owner"]:
			heals.append(Vector2i(c["q"], c["r"]))
	var best: Variant = null
	var best_score := INF
	for k in reach:
		var node: Dictionary = reach[k]
		var np := Vector2i(node["q"], node["r"])
		var d_heal := 0
		if not heals.is_empty():
			d_heal = 9999
			for h in heals:
				d_heal = mini(d_heal, Hex.distance(np, h))
		var tdef: int = Terrain.TERRAIN[state.cell_at(np.x, np.y)["terrain"]]["def"]
		var s: float = d_heal * 2 + threat_at(threat, np.x, np.y) * 1.5 - tdef * 1.5
		if s < best_score:
			best_score = s
			best = node
	return best

## score_instant_ability — score firing the unit's instant (target:"none") ability from
## where it stands. Returns {score} or null. Tuned vs attack scores (kill ~30+, decent
## attack ~8-15). heal/quake/bulwark/ward only; skitter/galeRush are movement value
## (out of scope for AI v1, as in the JS).
static func score_instant_ability(state, unit: Dictionary) -> Variant:
	var ab: Variant = Abilities.ability_for(unit)
	if ab == null or unit["cd"] > 0 or ab["target"] != "none":
		return null
	var s := 0.0
	match ab["key"]:
		"healPulse":
			for n in Hex.neighbors(Vector2i(unit["q"], unit["r"])):
				var a: Variant = state.unit_at(n.x, n.y)
				if a != null and a["owner"] == unit["owner"] and a["hp"] < a["max_hp"] * 0.6:
					s += 12
		"quake":
			for n in Hex.neighbors(Vector2i(unit["q"], unit["r"])):
				var e: Variant = state.unit_at(n.x, n.y)
				if e != null and e["owner"] != unit["owner"]:
					s += 20 if e["hp"] <= 4 else 9
			if s < 18:
				s = 0.0
		"bulwark", "ward":
			if Status.has_status(unit, ab["key"]):
				return null
			var allies := 0
			for n in Hex.neighbors(Vector2i(unit["q"], unit["r"])):
				var a: Variant = state.unit_at(n.x, n.y)
				if a != null and a["owner"] == unit["owner"]:
					allies += 1
			s = allies * 5 + 4
			if s < 12:
				s = 0.0
	return {"score": s} if s > 0 else null
